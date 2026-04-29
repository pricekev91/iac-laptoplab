#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

OPENWEBUI_ROOT="/opt/openwebui"
VENV_DIR="${OPENWEBUI_ROOT}/venv"
WRAPPER_PATH="/usr/local/bin/ai-presentation"
INSTALL_STAMP_PATH="${OPENWEBUI_ROOT}/.install-script.sha256"

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

cleanup_partial_install() {
    rm -rf /root/.cache/pip

    if [[ -d "$VENV_DIR" && ! -x "$VENV_DIR/bin/open-webui" ]]; then
        rm -rf "$VENV_DIR"
    fi
}

install_wrapper() {
    cat > "$WRAPPER_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

export HOST="${AI_PRESENTATION_HOST:-0.0.0.0}"
export PORT="${AI_PRESENTATION_PORT:-3000}"

exec /opt/openwebui/venv/bin/open-webui "$@"
EOF

    chmod 0755 "$WRAPPER_PATH"
}

artifacts_ready() {
    [[ -x "$VENV_DIR/bin/open-webui" && -x "$WRAPPER_PATH" ]]
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

install -d -m 0755 "$OPENWEBUI_ROOT"

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
    python3 \
    python3-pip \
    python3-venv

cleanup_partial_install

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    python3 -m venv "$VENV_DIR"
fi

if ! "$VENV_DIR/bin/pip" show open-webui >/dev/null 2>&1; then
    PIP_NO_CACHE_DIR=1 "$VENV_DIR/bin/pip" install --upgrade --no-cache-dir pip setuptools wheel

    if ! "$VENV_DIR/bin/pip" show torch >/dev/null 2>&1; then
        PIP_NO_CACHE_DIR=1 "$VENV_DIR/bin/pip" install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch
    fi

    PIP_NO_CACHE_DIR=1 "$VENV_DIR/bin/pip" install --upgrade --no-cache-dir open-webui
fi

install_wrapper
printf '%s\n' "$current_script_sha" > "$INSTALL_STAMP_PATH"