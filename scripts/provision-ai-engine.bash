#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

AI_ENGINE_ROOT="/opt/ai-engine"
BACKEND_REPO_DIR="${AI_ENGINE_ROOT}/backend"
BUILD_DIR="${BACKEND_REPO_DIR}/build"
WRAPPER_PATH="/usr/local/bin/ai-engine"
BACKEND_PATH="/usr/local/libexec/ai-engine-backend"
MANAGER_VENV_DIR="${AI_ENGINE_ROOT}/venv"
MANAGER_APP_PATH="${AI_ENGINE_ROOT}/engine_manager.py"
STATE_DIR="${AI_ENGINE_ROOT}/state"
ACTIVE_MODEL_PATH="${STATE_DIR}/active-model.txt"
AI_ENGINE_DATA_DIR="${AI_ENGINE_ROOT}/data"
AI_ENGINE_PROJECTS_DIR="${AI_ENGINE_DATA_DIR}/projects"
LEGO_PROJECT_DIR="${AI_ENGINE_PROJECTS_DIR}/lego-project"
ROADMAP_DB_PATH="${AI_ENGINE_DATA_DIR}/roadmaps-charters.sqlite3"
LEGO_CHARTER_PATH="${LEGO_PROJECT_DIR}/charter.md"
LEGO_ROADMAP_PATH="${LEGO_PROJECT_DIR}/roadmap.md"
LEGO_PROJECTIONS_PATH="${LEGO_PROJECT_DIR}/projections.md"
INSTALL_STAMP_PATH="${AI_ENGINE_ROOT}/.install-script.sha256"
SOURCE_URL="https://github.com/ggerganov/llama.cpp/archive/refs/heads/master.tar.gz"

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

seed_roadmap_database() {
    sqlite3 "$ROADMAP_DB_PATH" <<'SQL'
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS project_charters (
    project_slug TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    source_system TEXT NOT NULL,
    primary_goal TEXT NOT NULL,
    constraints TEXT NOT NULL,
    success_definition TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS roadmap_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_slug TEXT NOT NULL,
    phase_order INTEGER NOT NULL,
    item_order INTEGER NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    outcome TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'planned',
    UNIQUE(project_slug, phase_order, item_order),
    FOREIGN KEY(project_slug) REFERENCES project_charters(project_slug) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS project_projections (
    project_slug TEXT PRIMARY KEY,
    assumptions TEXT NOT NULL,
    timeline_projection TEXT NOT NULL,
    delivery_ranges TEXT NOT NULL,
    milestone_forecast TEXT NOT NULL,
    projection_risks TEXT NOT NULL,
    recommended_target TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_slug) REFERENCES project_charters(project_slug) ON DELETE CASCADE
);

INSERT INTO project_charters (
    project_slug,
    title,
    summary,
    source_system,
    primary_goal,
    constraints,
    success_definition,
    updated_at
) VALUES (
    'lego-project',
    'Lego Project',
    'Analyze photos from OneDrive, decide whether Lego appears in each image, and identify the most likely exact piece when confidence is sufficient.',
    'OneDrive',
    'Build a repeatable vision workflow that filters non-Lego images first, then classifies the likely Lego piece with ranked candidates and confidence scores.',
    'Many photos will contain partial or obstructed pieces, inconsistent lighting, background clutter, and incomplete visibility of the target part.',
    'High-confidence Lego presence detection, top-ranked piece predictions for positive images, and a review path for low-confidence or partially exposed pieces.',
    CURRENT_TIMESTAMP
) ON CONFLICT(project_slug) DO UPDATE SET
    title = excluded.title,
    summary = excluded.summary,
    source_system = excluded.source_system,
    primary_goal = excluded.primary_goal,
    constraints = excluded.constraints,
    success_definition = excluded.success_definition,
    updated_at = CURRENT_TIMESTAMP;

DELETE FROM roadmap_items WHERE project_slug = 'lego-project';

INSERT INTO roadmap_items (project_slug, phase_order, item_order, title, description, outcome, status) VALUES
    (
        'lego-project',
        1,
        1,
        'Define intake contract',
        'Specify how OneDrive photos are discovered, copied, deduplicated, and tracked with image identifiers and timestamps.',
        'A stable ingestion contract exists for downstream model evaluation and reruns.',
        'planned'
    ),
    (
        'lego-project',
        1,
        2,
        'Assemble labeled dataset',
        'Collect representative images with positive Lego examples, negative non-Lego examples, and difficult partial-visibility samples.',
        'The project has a labeled baseline dataset that covers presence detection and hard identification cases.',
        'planned'
    ),
    (
        'lego-project',
        2,
        1,
        'Ship Lego presence detector',
        'Train or configure the first-stage model to answer whether a photo contains Lego before any fine-grained classification occurs.',
        'Non-Lego images are filtered early so exact-piece identification only runs on relevant photos.',
        'planned'
    ),
    (
        'lego-project',
        2,
        2,
        'Set confidence thresholds',
        'Define acceptance thresholds, rejection thresholds, and fallback handling for uncertain Lego-presence predictions.',
        'The detection stage can route uncertain cases to review without contaminating downstream identification.',
        'planned'
    ),
    (
        'lego-project',
        3,
        1,
        'Prototype exact piece identification',
        'Build the second-stage classifier or retrieval workflow that proposes the exact Lego piece and returns ranked candidates.',
        'Positive images receive candidate piece predictions instead of a single brittle guess.',
        'planned'
    ),
    (
        'lego-project',
        3,
        2,
        'Handle partial occlusion',
        'Add retrieval features, multi-view matching, and partial-shape reasoning so hidden studs or blocked edges do not force complete failure.',
        'The system remains useful even when not all of the Lego piece is exposed in the image.',
        'planned'
    ),
    (
        'lego-project',
        4,
        1,
        'Create review workflow',
        'Store model confidence, top candidates, and image references so a reviewer can confirm or override uncertain classifications.',
        'Low-confidence cases have a human-in-the-loop path instead of silent bad predictions.',
        'planned'
    ),
    (
        'lego-project',
        4,
        2,
        'Measure production quality',
        'Track precision for Lego presence detection, top-k piece accuracy, and review rate on new OneDrive batches.',
        'The project has operating metrics that show whether the implementation is improving or regressing.',
        'planned'
    );

INSERT INTO project_projections (
    project_slug,
    assumptions,
    timeline_projection,
    delivery_ranges,
    milestone_forecast,
    projection_risks,
    recommended_target,
    updated_at
) VALUES (
    'lego-project',
    'Start date: April 27, 2026. One team works sequentially with light overlap. The first release targets practical accuracy rather than perfect exact-piece recall. Existing OneDrive access and image export are available.',
    'Phase 1 intake and labeling: 2 to 3 weeks. Phase 2 Lego presence detection: 2 to 4 weeks. Phase 3 exact piece identification: 2 to 3 weeks. Phase 4 partial occlusion handling: 2 to 5 weeks. Phase 5 review workflow and quality metrics: 1 to 2 weeks.',
    'Optimistic: first working version in June 2026, review-ready version in July 2026, practical occlusion-aware version in early August 2026. Expected: first working version in mid-June to early July 2026, practical version in August 2026. Conservative: first working version in July 2026, practical version in September 2026.',
    'Milestone 1 ingestion baseline by mid-May 2026. Milestone 2 presence detection operational by early to mid-June 2026. Milestone 3 piece candidate matching by late June to early July 2026. Milestone 4 occlusion-aware classification by July to early August 2026. Milestone 5 review and metrics by August 2026.',
    'The schedule is mostly driven by labeled-image quality for partially visible pieces, ambiguity between similar parts, and annotation expansion when images contain multiple mixed pieces.',
    'Plan for an expected delivery window ending in August 2026, with a first usable checkpoint in June 2026 and fallback buffer into September 2026.',
    CURRENT_TIMESTAMP
) ON CONFLICT(project_slug) DO UPDATE SET
    assumptions = excluded.assumptions,
    timeline_projection = excluded.timeline_projection,
    delivery_ranges = excluded.delivery_ranges,
    milestone_forecast = excluded.milestone_forecast,
    projection_risks = excluded.projection_risks,
    recommended_target = excluded.recommended_target,
    updated_at = CURRENT_TIMESTAMP;
SQL
}

write_project_documents() {
    cat > "$LEGO_CHARTER_PATH" <<'EOF'
# Lego Project Charter

## Summary

Build a workflow that pulls photos from OneDrive, determines whether each image contains Lego, and then attempts to identify the exact Lego piece when confidence is high enough.

## Goals

- Detect whether Lego is present in each image before spending compute on detailed classification.
- Return the most likely exact Lego piece or a ranked candidate list when full certainty is not possible.
- Preserve a review path for low-confidence images and partially obscured pieces.

## Scope

- Ingest photos from OneDrive.
- Run first-stage Lego presence detection.
- Run second-stage piece identification for positive images.
- Store confidence, ranked candidates, and review status.

## Constraints

- Many photos will not contain Lego at all.
- Some Lego pieces will be partially hidden or cropped.
- Lighting, shadows, background clutter, and motion blur will reduce classification quality.
- Exact-piece identification will be harder than presence detection and will require a fallback review workflow.

## Success Criteria

- Non-Lego images are filtered reliably enough to reduce wasted downstream processing.
- Positive images return either a high-confidence piece prediction or a ranked shortlist.
- Low-confidence and occluded cases are routed to human review instead of silently accepted.
- The workflow can be rerun on new OneDrive batches without changing the contract.

## Risks

- Insufficient labeled examples for rare or partially visible pieces.
- Ambiguity between visually similar Lego parts.
- OneDrive image quality and metadata inconsistency.
- Overfitting to a narrow set of image backgrounds or camera angles.
EOF

    cat > "$LEGO_ROADMAP_PATH" <<'EOF'
# Lego Project Roadmap

## Phase 1: Intake and Dataset Foundation

1. Define the OneDrive intake contract for discovery, copy, deduplication, and image tracking.
2. Assemble a labeled dataset with positive Lego examples, negative non-Lego examples, and difficult partial-visibility samples.

## Phase 2: Presence Detection

1. Ship the first-stage model that decides whether a photo contains Lego.
2. Set confidence thresholds and fallback handling for uncertain detection results.

## Phase 3: Exact Piece Identification

1. Prototype the second-stage classifier or retrieval workflow that returns ranked piece candidates.
2. Improve partial-occlusion handling so hidden studs or blocked edges do not force complete failure.

## Phase 4: Review and Metrics

1. Create a human review workflow for low-confidence classifications.
2. Measure production quality with detection precision, top-k piece accuracy, and review rate metrics.
EOF

    cat > "$LEGO_PROJECTIONS_PATH" <<'EOF'
# Lego Project Projections

## Assumptions

- Start date: April 27, 2026.
- One team is working sequentially with light overlap between phases.
- The first release targets practical accuracy, not perfect exact-piece recall.
- Existing OneDrive access and image export are available.

## Timeline Projection

| Phase | Focus | Estimated Duration | Projected Window |
| --- | --- | --- | --- |
| 1 | Intake contract and labeled dataset | 2 to 3 weeks | Apr 27, 2026 to May 15, 2026 |
| 2 | Lego presence detection | 2 to 4 weeks | May 11, 2026 to Jun 12, 2026 |
| 3 | Exact piece identification | 2 to 3 weeks | Jun 8, 2026 to Jul 3, 2026 |
| 4 | Partial occlusion handling | 2 to 5 weeks | Jun 22, 2026 to Aug 7, 2026 |
| 5 | Review workflow and quality metrics | 1 to 2 weeks | Aug 3, 2026 to Aug 21, 2026 |

## Delivery Ranges

### Optimistic

- First working version: June 2026
- Review-ready version with ranked candidates: July 2026
- Practical version for obstructed pieces: early August 2026

### Expected

- First working version: mid-June to early July 2026
- Review-ready version with ranked candidates: July 2026
- Practical version for obstructed pieces: August 2026

### Conservative

- First working version: July 2026
- Review-ready version with ranked candidates: August 2026
- Practical version for obstructed pieces: September 2026

## Milestone Forecast

### Milestone 1: Ingestion Baseline

- Outcome: OneDrive images are discovered, copied, deduplicated, and tracked.
- Target: Mid-May 2026.

### Milestone 2: Presence Detection Operational

- Outcome: The system can decide whether an image likely contains Lego.
- Target: Early to mid-June 2026.

### Milestone 3: Piece Candidate Matching

- Outcome: Positive images return the most likely piece candidates with confidence scores.
- Target: Late June to early July 2026.

### Milestone 4: Occlusion-Aware Classification

- Outcome: The system remains usable when pieces are partially hidden, cropped, or blocked.
- Target: July to early August 2026.

### Milestone 5: Review and Metrics

- Outcome: Low-confidence predictions route to review and quality metrics are measurable across new batches.
- Target: August 2026.

## Projection Risks

- The biggest schedule driver is the quality of labeled images for partially visible pieces.
- Exact-piece identification may need retrieval or top-k ranking instead of single-label classification.
- If many images contain mixed bins or multiple pieces, annotation effort can expand quickly.
- A weak negative dataset will slow down the presence-detector threshold tuning.

## Recommended Target

Plan for an expected delivery window ending in August 2026, with a first usable checkpoint in June 2026 and a fallback buffer into September 2026 if the occlusion problem proves harder than expected.
EOF
}

install_manager_app() {
    cat > "$MANAGER_APP_PATH" <<'EOF'
import os
import socket
import subprocess
import threading
import time
from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

BACKEND_PATH = os.environ.get("AI_ENGINE_BACKEND_PATH", "/usr/local/libexec/ai-engine-backend")
MODEL_PATH = os.environ.get("AI_ENGINE_MODEL", "/models/default.gguf")
HOST = os.environ.get("AI_ENGINE_HOST", "0.0.0.0")
PORT = int(os.environ.get("AI_ENGINE_PORT", "8080"))
STATE_PATH = Path(os.environ.get("AI_ENGINE_ACTIVE_MODEL_PATH", "/opt/ai-engine/state/active-model.txt"))


class ActivateRequest(BaseModel):
    model_path: str


class EngineSupervisor:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._process: subprocess.Popen[str] | None = None
        self._current_model: str | None = None
        self._monitor = threading.Thread(target=self._monitor_loop, daemon=True)

    def _resolve_model(self, requested: str | None = None) -> str:
        if requested:
            candidate = requested
        elif STATE_PATH.exists():
            candidate = STATE_PATH.read_text().strip()
        else:
            candidate = MODEL_PATH

        if not candidate:
            raise RuntimeError("No active model path configured")

        if not Path(candidate).exists():
            raise RuntimeError(f"Model path does not exist: {candidate}")

        return candidate

    def _persist_model(self, model_path: str) -> None:
        STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
        STATE_PATH.write_text(model_path + "\n")

    def _wait_for_backend(self, timeout_seconds: int = 60) -> None:
        deadline = time.time() + timeout_seconds
        while time.time() < deadline:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
                probe.settimeout(1)
                if probe.connect_ex(("127.0.0.1", PORT)) == 0:
                    return
            time.sleep(1)
        raise RuntimeError(f"AI engine backend did not become ready on 127.0.0.1:{PORT}")

    def _stop_locked(self) -> None:
        if self._process is None:
            return
        if self._process.poll() is None:
            self._process.terminate()
            try:
                self._process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                self._process.kill()
                self._process.wait(timeout=10)
        self._process = None

    def start(self, requested_model: str | None = None) -> dict[str, object]:
        model_path = self._resolve_model(requested_model)
        with self._lock:
            if self._process is not None and self._process.poll() is None and self._current_model == model_path:
                return self.status()

            self._stop_locked()
            self._process = subprocess.Popen(
                [
                    BACKEND_PATH,
                    "--model",
                    model_path,
                    "--host",
                    HOST,
                    "--port",
                    str(PORT),
                ]
            )
            self._current_model = model_path
            self._persist_model(model_path)

        self._wait_for_backend()
        return self.status()

    def stop(self) -> None:
        with self._lock:
            self._stop_locked()

    def status(self) -> dict[str, object]:
        with self._lock:
            running = self._process is not None and self._process.poll() is None
            pid = self._process.pid if running and self._process is not None else None
            return {
                "status": "ok" if running else "stopped",
                "running": running,
                "pid": pid,
                "model_path": self._current_model,
                "port": PORT,
            }

    def _monitor_loop(self) -> None:
        while not self._stop_event.wait(5):
            restart_model = None
            with self._lock:
                if self._process is not None and self._process.poll() is not None:
                    restart_model = self._current_model
                    self._process = None
            if restart_model:
                try:
                    self.start(restart_model)
                except Exception:
                    pass

    def start_monitor(self) -> None:
        if not self._monitor.is_alive():
            self._monitor.start()

    def shutdown(self) -> None:
        self._stop_event.set()
        self.stop()


supervisor = EngineSupervisor()
app = FastAPI(title="AI Engine Manager")


@app.on_event("startup")
def startup() -> None:
    supervisor.start()
    supervisor.start_monitor()


@app.on_event("shutdown")
def shutdown() -> None:
    supervisor.shutdown()


@app.get("/")
def root() -> dict[str, object]:
    return {"service": "ai-engine-manager", **supervisor.status()}


@app.get("/health")
def health() -> dict[str, object]:
    return supervisor.status()


@app.get("/engine/status")
def engine_status() -> dict[str, object]:
    return supervisor.status()


@app.post("/engine/activate")
def activate(request: ActivateRequest) -> dict[str, object]:
    try:
        return supervisor.start(request.model_path)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
EOF
}

install_wrapper() {
    cat > "$WRAPPER_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

host="${AI_ENGINE_ADMIN_HOST:-0.0.0.0}"
port="${AI_ENGINE_ADMIN_PORT:-18080}"

exec /opt/ai-engine/venv/bin/uvicorn engine_manager:app --app-dir /opt/ai-engine --host "$host" --port "$port"
EOF

    chmod 0755 "$WRAPPER_PATH"
}

artifacts_ready() {
    [[ -x "$WRAPPER_PATH" && -x "$BACKEND_PATH" && -x "$MANAGER_VENV_DIR/bin/uvicorn" && -f "$MANAGER_APP_PATH" && -f "$ROADMAP_DB_PATH" && -f "$LEGO_CHARTER_PATH" && -f "$LEGO_ROADMAP_PATH" && -f "$LEGO_PROJECTIONS_PATH" ]]
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

install -d -m 0755 "$AI_ENGINE_ROOT"
install -d -m 0755 "$STATE_DIR"
install -d -m 0755 "$AI_ENGINE_DATA_DIR"
install -d -m 0755 "$AI_ENGINE_PROJECTS_DIR"
install -d -m 0755 "$LEGO_PROJECT_DIR"
install -d -m 0755 /usr/local/libexec

current_script_sha="$(script_sha256)"
installed_script_sha=""
if [[ -f "$INSTALL_STAMP_PATH" ]]; then
    installed_script_sha="$(cat "$INSTALL_STAMP_PATH")"
fi

if [[ "$installed_script_sha" == "$current_script_sha" ]] && artifacts_ready; then
    install_wrapper
    exit 0
fi

ensure_apt_packages \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    ninja-build \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    sqlite3

if [[ ! -x "$MANAGER_VENV_DIR/bin/python" ]]; then
    python3 -m venv "$MANAGER_VENV_DIR"
fi

"$MANAGER_VENV_DIR/bin/pip" install --upgrade pip setuptools wheel
"$MANAGER_VENV_DIR/bin/pip" install --upgrade fastapi 'uvicorn[standard]'

if [[ ! -f "$BACKEND_REPO_DIR/CMakeLists.txt" ]]; then
    temp_archive="$(mktemp)"
    rm -rf "$BACKEND_REPO_DIR"
    install -d -m 0755 "$BACKEND_REPO_DIR"
    curl -4 -fsSL "$SOURCE_URL" -o "$temp_archive"
    tar -xzf "$temp_archive" --strip-components=1 -C "$BACKEND_REPO_DIR"
    rm -f "$temp_archive"
fi

if [[ ! -x "$BACKEND_PATH" ]]; then
    cmake -S "$BACKEND_REPO_DIR" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build "$BUILD_DIR" --parallel

    backend_binary="$(find "$BUILD_DIR" -maxdepth 3 -type f -perm -111 -name '*server' | sort | head -n 1)"
    [[ -n "$backend_binary" ]] || {
        echo "ERROR: Unable to locate a built AI engine server binary" >&2
        exit 1
    }

    install -m 0755 "$backend_binary" "$BACKEND_PATH"
fi

seed_roadmap_database
write_project_documents
install_manager_app
install_wrapper
printf '%s\n' "$current_script_sha" > "$INSTALL_STAMP_PATH"