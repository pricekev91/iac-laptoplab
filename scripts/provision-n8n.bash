#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

N8N_ROOT="/opt/n8n"
WRAPPER_PATH="/usr/local/bin/ai-orchestrator"
INSTALL_STAMP_PATH="${N8N_ROOT}/.install-script.sha256"
AI_ENGINE_CLIENT_PACKAGE="@bpmsoftwaresolutions/ai-engine-client"

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

npm_global_package_installed() {
    npm list -g --depth=0 "$1" >/dev/null 2>&1
}

install_wrapper() {
    cat > "$WRAPPER_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

exec /usr/bin/n8n "$@"
EOF

    chmod 0755 "$WRAPPER_PATH"
}

artifacts_ready() {
    [[ -x /usr/bin/n8n && -x "$WRAPPER_PATH" ]] && npm_global_package_installed "$AI_ENGINE_CLIENT_PACKAGE"
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

install -d -m 0755 "$N8N_ROOT"

current_script_sha="$(script_sha256)"
installed_script_sha=""
if [[ -f "$INSTALL_STAMP_PATH" ]]; then
    installed_script_sha="$(cat "$INSTALL_STAMP_PATH")"
fi

if [[ "$installed_script_sha" == "$current_script_sha" ]] && artifacts_ready; then
    install_wrapper
    exit 0
fi

ensure_apt_packages ca-certificates curl gpg

if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
    curl -4 -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource-setup.sh
    bash /tmp/nodesource-setup.sh
    rm -f /tmp/nodesource-setup.sh
fi

ensure_apt_packages nodejs

if ! command -v n8n >/dev/null 2>&1; then
    npm install -g n8n
fi

if ! npm_global_package_installed "$AI_ENGINE_CLIENT_PACKAGE"; then
    npm install -g "$AI_ENGINE_CLIENT_PACKAGE"
fi

install_wrapper
printf '%s\n' "$current_script_sha" > "$INSTALL_STAMP_PATH"