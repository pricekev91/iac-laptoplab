#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

AI_BROKER_ROOT="/opt/ai-broker"
VENV_DIR="${AI_BROKER_ROOT}/venv"
APP_PATH="${AI_BROKER_ROOT}/app.py"
WRAPPER_PATH="/usr/local/bin/ai-broker"
INSTALL_STAMP_PATH="${AI_BROKER_ROOT}/.install-script.sha256"
REGISTRY_DIR="${AI_BROKER_ROOT}/data"
REGISTRY_PATH="${REGISTRY_DIR}/registry.json"

script_sha256() {
    sha256sum "$0" | awk '{ print $1 }'
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fq 'install ok installed'
}

ensure_apt_packages() {
    local package
    local missing_packages=()

    for package in "$@"; do
        if ! package_installed "$package"; then
            missing_packages+=("$package")
        fi
    done

    if (( ${#missing_packages[@]} == 0 )); then
        return 0
    fi

    apt-get -o Acquire::ForceIPv4=true update
    apt-get -o Acquire::ForceIPv4=true install -y --no-install-recommends "${missing_packages[@]}"
}

install_app() {
    cat > "$APP_PATH" <<'EOF'
import json
import os
from pathlib import Path
from typing import Any

import requests
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response, StreamingResponse
from huggingface_hub import hf_hub_download
from pydantic import BaseModel

app = FastAPI(title="AI Broker")

REGISTRY_PATH = Path(os.environ.get("AI_BROKER_REGISTRY_PATH", "/opt/ai-broker/data/registry.json"))
MODELS_DIR = Path(os.environ.get("AI_BROKER_MODELS_DIR", "/models"))
ENGINE_BASE_URL = os.environ.get("AI_BROKER_ENGINE_BASE_URL", "http://engine:8080").rstrip("/")
ENGINE_ADMIN_BASE_URL = os.environ.get("AI_BROKER_ENGINE_ADMIN_BASE_URL", "http://engine:18080").rstrip("/")
DEFAULT_ALIAS = os.environ.get("AI_BROKER_DEFAULT_MODEL_ALIAS", "default")
DEFAULT_MODEL_PATH = os.environ.get("AI_BROKER_DEFAULT_MODEL_PATH", "/models/default.gguf")


class DownloadRequest(BaseModel):
    alias: str
    repo_id: str
    filename: str
    revision: str | None = None
    token: str | None = None


class RegisterRequest(BaseModel):
    alias: str
    path: str
    source: str = "manual"
    repo_id: str | None = None
    filename: str | None = None


class ActivateRequest(BaseModel):
    alias: str


def load_registry() -> dict[str, Any]:
    if REGISTRY_PATH.exists():
        return json.loads(REGISTRY_PATH.read_text())

    return {"models": {}, "active_alias": None}


def save_registry(registry: dict[str, Any]) -> None:
    REGISTRY_PATH.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY_PATH.write_text(json.dumps(registry, indent=2, sort_keys=True) + "\n")


def ensure_default_model() -> None:
    registry = load_registry()
    models = registry.setdefault("models", {})
    if DEFAULT_ALIAS not in models:
        models[DEFAULT_ALIAS] = {
            "alias": DEFAULT_ALIAS,
            "path": DEFAULT_MODEL_PATH,
            "source": "seed",
            "repo_id": None,
            "filename": Path(DEFAULT_MODEL_PATH).name,
        }
    if registry.get("active_alias") is None:
        registry["active_alias"] = DEFAULT_ALIAS
    save_registry(registry)


def model_list_payload() -> dict[str, Any]:
    registry = load_registry()
    active_alias = registry.get("active_alias")
    data = []
    for alias, entry in sorted(registry.get("models", {}).items()):
        data.append(
            {
                "id": alias,
                "object": "model",
                "owned_by": "ai-broker",
                "permission": [],
                "root": entry.get("path"),
                "metadata": {
                    "active": alias == active_alias,
                    "source": entry.get("source"),
                    "repo_id": entry.get("repo_id"),
                    "filename": entry.get("filename"),
                },
            }
        )
    return {"object": "list", "data": data, "active_alias": active_alias}


def activate_alias(alias: str) -> dict[str, Any]:
    registry = load_registry()
    entry = registry.get("models", {}).get(alias)
    if entry is None:
        raise HTTPException(status_code=404, detail=f"Unknown model alias: {alias}")

    model_path = entry["path"]
    if not Path(model_path).exists():
        raise HTTPException(status_code=400, detail=f"Model file is missing: {model_path}")

    response = requests.post(
        f"{ENGINE_ADMIN_BASE_URL}/engine/activate",
        json={"model_path": model_path},
        timeout=120,
    )
    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    registry["active_alias"] = alias
    save_registry(registry)
    return {"active_alias": alias, "engine": response.json()}


def proxy_request(method: str, path: str, payload: dict[str, Any], stream: bool) -> Response:
    upstream = requests.request(
        method,
        f"{ENGINE_BASE_URL}{path}",
        json=payload,
        timeout=600,
        stream=stream,
    )

    headers = {}
    content_type = upstream.headers.get("content-type")
    if content_type:
        headers["content-type"] = content_type

    if stream:
        return StreamingResponse(
            (chunk for chunk in upstream.iter_content(chunk_size=None) if chunk),
            status_code=upstream.status_code,
            headers=headers,
            media_type=content_type or "text/event-stream",
        )

    return Response(content=upstream.content, status_code=upstream.status_code, headers=headers)


@app.on_event("startup")
def startup() -> None:
    ensure_default_model()


@app.get("/")
def root() -> dict[str, Any]:
    return {
        "service": "ai-broker",
        "status": "ok",
        "engine_base_url": ENGINE_BASE_URL,
        "active_alias": load_registry().get("active_alias"),
    }


@app.get("/health")
def health() -> dict[str, Any]:
    return {"status": "ok", "active_alias": load_registry().get("active_alias")}


@app.get("/admin/models")
def admin_models() -> dict[str, Any]:
    return load_registry()


@app.post("/admin/models/register")
def register_model(request: RegisterRequest) -> dict[str, Any]:
    registry = load_registry()
    registry.setdefault("models", {})[request.alias] = request.model_dump()
    save_registry(registry)
    return registry["models"][request.alias]


@app.post("/admin/models/download")
def download_model(request: DownloadRequest) -> dict[str, Any]:
    downloaded = hf_hub_download(
        repo_id=request.repo_id,
        filename=request.filename,
        revision=request.revision,
        token=request.token,
        local_dir=str(MODELS_DIR),
        local_dir_use_symlinks=False,
    )

    registry = load_registry()
    registry.setdefault("models", {})[request.alias] = {
        "alias": request.alias,
        "path": downloaded,
        "source": "huggingface",
        "repo_id": request.repo_id,
        "filename": request.filename,
    }
    save_registry(registry)
    return registry["models"][request.alias]


@app.post("/admin/models/activate")
def activate_model(request: ActivateRequest) -> dict[str, Any]:
    return activate_alias(request.alias)


@app.get("/v1/models")
def v1_models() -> dict[str, Any]:
    return model_list_payload()


@app.post("/v1/chat/completions")
async def chat_completions(request: Request) -> Response:
    payload = await request.json()
    return proxy_request("POST", "/v1/chat/completions", payload, bool(payload.get("stream", False)))


@app.post("/v1/completions")
async def completions(request: Request) -> Response:
    payload = await request.json()
    return proxy_request("POST", "/v1/completions", payload, bool(payload.get("stream", False)))
EOF
}

install_wrapper() {
    cat > "$WRAPPER_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

host="${AI_BROKER_HOST:-0.0.0.0}"
port="${AI_BROKER_PORT:-4000}"

exec /opt/ai-broker/venv/bin/uvicorn app:app --app-dir /opt/ai-broker --host "$host" --port "$port"
EOF

    chmod 0755 "$WRAPPER_PATH"
}

artifacts_ready() {
    [[ -x "$VENV_DIR/bin/uvicorn" && -x "$WRAPPER_PATH" && -f "$APP_PATH" && -f "$REGISTRY_PATH" ]]
}

ensure_ipv4_preferred() {
    local gai_conf="/etc/gai.conf"
    local preference_line="precedence ::ffff:0:0/96  100"

    if grep -Fqx "$preference_line" "$gai_conf" 2>/dev/null; then
        return 0
    fi

    printf '\n%s\n' "$preference_line" >> "$gai_conf"
}

ensure_ipv4_preferred

install -d -m 0755 "$AI_BROKER_ROOT"
install -d -m 0755 "$REGISTRY_DIR"

current_script_sha="$(script_sha256)"
installed_script_sha=""
if [[ -f "$INSTALL_STAMP_PATH" ]]; then
    installed_script_sha="$(cat "$INSTALL_STAMP_PATH")"
fi

if [[ "$installed_script_sha" == "$current_script_sha" ]] && artifacts_ready; then
    install_app
    install_wrapper
    exit 0
fi

ensure_apt_packages \
    build-essential \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel
"$VENV_DIR/bin/pip" install --upgrade fastapi 'uvicorn[standard]' requests huggingface_hub

if [[ ! -f "$REGISTRY_PATH" ]]; then
    printf '{"models": {}, "active_alias": null}\n' > "$REGISTRY_PATH"
fi

install_app
install_wrapper
printf '%s\n' "$current_script_sha" > "$INSTALL_STAMP_PATH"