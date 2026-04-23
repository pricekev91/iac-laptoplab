#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

AI_ENGINE_ROOT="/opt/ai-engine"
BACKEND_REPO_DIR="${AI_ENGINE_ROOT}/backend"
BUILD_DIR="${BACKEND_REPO_DIR}/build"
WRAPPER_PATH="/usr/local/bin/ai-engine"
BACKEND_PATH="/usr/local/libexec/ai-engine-backend"
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

install_wrapper() {
    cat > "$WRAPPER_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

exec /usr/local/libexec/ai-engine-backend "$@"
EOF

    chmod 0755 "$WRAPPER_PATH"
}

artifacts_ready() {
    [[ -x "$WRAPPER_PATH" && -x "$BACKEND_PATH" ]]
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
    pkg-config

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

install_wrapper
printf '%s\n' "$current_script_sha" > "$INSTALL_STAMP_PATH"