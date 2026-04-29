#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

AI_ENGINE_ROOT="/opt/ai-engine-ollama"
STATE_DIR="${AI_ENGINE_ROOT}/state"
LOG_DIR="${AI_ENGINE_ROOT}/logs"
WRAPPER_PATH="/usr/local/bin/ai-engine"
ADMIN_APP_PATH="/usr/local/libexec/ai-engine-ollama-admin.py"
INSTALL_STAMP_PATH="${AI_ENGINE_ROOT}/.install-script.sha256"
OLLAMA_DOWNLOAD_BASE_URL="https://ollama.com/download"

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

install_ollama_binary() {
    local arch
    local archive_name
    local download_url
    local install_dir="/usr/local"
    local bindir="/usr/local/bin"

    if command -v ollama >/dev/null 2>&1 && ollama --version >/dev/null 2>&1; then
        return 0
    fi

    case "$(uname -m)" in
        x86_64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            echo "Unsupported architecture for Ollama: $(uname -m)" >&2
            exit 1
            ;;
    esac

    archive_name="ollama-linux-${arch}.tar.zst"
    download_url="${OLLAMA_DOWNLOAD_BASE_URL}/${archive_name}"

    install -d -m 0755 "$bindir" "${install_dir}/lib/ollama"
    rm -rf "${install_dir}/lib/ollama"
    install -d -m 0755 "${install_dir}/lib/ollama"

    curl --fail --show-error --location --progress-bar "$download_url" | zstd -d | tar -xf - -C "$install_dir"

    if [[ "${install_dir}/bin/ollama" != "${bindir}/ollama" ]]; then
        ln -sf "${install_dir}/ollama" "${bindir}/ollama"
    fi
}

write_admin_server() {
    install -d -m 0755 "$(dirname "$ADMIN_APP_PATH")"

    cat > "$ADMIN_APP_PATH" <<'PY'
#!/usr/bin/env python3
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def installed_models():
    try:
        result = subprocess.run(
            ["ollama", "list"],
            check=True,
            capture_output=True,
            text=True,
        )
    except Exception:
        return []

    models = []
    for line in result.stdout.splitlines()[1:]:
        parts = line.split()
        if parts:
            models.append(parts[0])
    return models


class Handler(BaseHTTPRequestHandler):
    def _write_json(self, status_code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        payload = {
            "backend": "ollama",
            "default_model": os.environ.get("OLLAMA_DEFAULT_MODEL", "qwen2.5-coder:7b"),
            "models": installed_models(),
            "api_base": f"http://{os.environ.get('AI_ENGINE_HOST', '0.0.0.0')}:{os.environ.get('AI_ENGINE_PORT', '8080')}",
        }

        if self.path == "/health":
            self._write_json(200, {"status": "ok", **payload})
            return

        if self.path == "/engine/status":
            self._write_json(200, payload)
            return

        self._write_json(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    host = os.environ.get("AI_ENGINE_ADMIN_HOST", "0.0.0.0")
    port = int(os.environ.get("AI_ENGINE_ADMIN_PORT", "18080"))
    server = ThreadingHTTPServer((host, port), Handler)
    server.serve_forever()
PY

    chmod 0755 "$ADMIN_APP_PATH"
}

write_wrapper() {
    cat > "$WRAPPER_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

state_dir="/opt/ai-engine-ollama/state"
log_dir="/opt/ai-engine-ollama/logs"
home_dir="/usr/share/ollama"
models_dir="${state_dir}/models"
ollama_log="${log_dir}/ollama.log"
admin_log="${log_dir}/admin.log"
default_model="${OLLAMA_DEFAULT_MODEL:-qwen2.5-coder:7b}"
engine_host="${AI_ENGINE_HOST:-0.0.0.0}"
engine_port="${AI_ENGINE_PORT:-8080}"

install -d -m 0755 "$state_dir" "$log_dir" "$home_dir" "$models_dir"
export HOME="$home_dir"
export OLLAMA_MODELS="$models_dir"
export OLLAMA_HOST="${engine_host}:${engine_port}"

cleanup() {
    if [[ -n "${admin_pid:-}" ]]; then
        kill "$admin_pid" 2>/dev/null || true
    fi
    if [[ -n "${ollama_pid:-}" ]]; then
        kill "$ollama_pid" 2>/dev/null || true
        wait "$ollama_pid" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

ollama serve >> "$ollama_log" 2>&1 &
ollama_pid=$!

for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${engine_port}/api/tags" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

python3 /usr/local/libexec/ai-engine-ollama-admin.py >> "$admin_log" 2>&1 &
admin_pid=$!

if [[ -n "$default_model" ]]; then
    if ! ollama list | awk 'NR > 1 { print $1 }' | grep -Fxq "$default_model"; then
        ollama pull "$default_model"
    fi
    printf '%s\n' "$default_model" > "${state_dir}/active-model.txt"
fi

wait "$ollama_pid"
EOF

    chmod 0755 "$WRAPPER_PATH"
}

disable_vendor_service() {
    if systemctl list-unit-files | grep -Fq 'ollama.service'; then
        systemctl disable --now ollama >/dev/null 2>&1 || true
    fi
}

main() {
    ensure_apt_packages ca-certificates curl python3 zstd
    install -d -m 0755 "$AI_ENGINE_ROOT" "$STATE_DIR" "$LOG_DIR"
    install_ollama_binary
    disable_vendor_service
    write_admin_server
    write_wrapper
    printf '%s\n' "$(script_sha256)" > "$INSTALL_STAMP_PATH"
}

main "$@"