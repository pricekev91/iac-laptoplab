#!/usr/bin/env bash
# =====================================================
# bootstrap-llamacpp.sh — Version 0.1
# -----------------------------------------------------
# Author: Kevin Price (adapted by ChatGPT)
# Purpose:
#     Provision a WSL Ubuntu environment with:
#       • llama.cpp (CUDA build)
#       • OpenWebUI (pip)
#       • systemd units to auto-start services (WSL2 systemd required)
#
# Paths:
#   Executables: /opt/<service>/
#   Models/Data: /srv/ai/models, /srv/llama.cpp/models, /srv/openwebui/data
#
# Notes:
#   - Script logs everything to $HOME/bootstrap-llamacpp.log
#   - Designed to be idempotent (safe to re-run)
#   - Versioning: v0.1 (beta)
# =====================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ---------- Config / Versions ----------
LOGFILE="${HOME}/bootstrap-llamacpp.log"
exec > >(tee -a "${LOGFILE}") 2>&1

# Versions (adjust later if you want a different commit/tag)
LLAMACPP_REPO="https://github.com/ggerganov/llama.cpp.git"
LLAMACPP_BRANCH="main"            # keep as branch; change to commit SHA to pin
OPENWEBUI_PIPPKG="open-webui"
PYTHON_MIN_VER="3.10"             # prefer 3.11 if available

# Install paths
OPT_DIR="/opt"
SRV_DIR="/srv"
LLAMACPP_OPT="${OPT_DIR}/llama.cpp"
OPENWEBUI_OPT="${OPT_DIR}/openwebui"
AI_MODELS_DIR="${SRV_DIR}/ai/models"
LLAMACPP_MODELS_DIR="${SRV_DIR}/llama.cpp/models"
OPENWEBUI_DATA_DIR="${SRV_DIR}/openwebui/data"

# Systemd unit names
LLAMACPP_SERVICE="llamacpp.service"
OPENWEBUI_SERVICE="openwebui.service"

AUTO="${AUTO:-}"   # if set (non-empty), skip interactive pauses

# ---------- Helpers ----------
section() {
    printf "\n%s\n" "=============================================================="
    printf " %s\n" "$1"
    printf "%s\n\n" "=============================================================="
}

pause() {
    if [ -z "${AUTO}" ]; then
        read -rp $'\n⏸  Press any key to continue (or set AUTO=1 to skip)... ' -n1 -s || true
        echo -e "\n"
    fi
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script requires root. Re-run with sudo."
        exit 1
    fi
}

safe_apt_update() {
    apt-get update -y
}

# Make dirs idempotent
mkdir_if_missing() {
    local d="$1"
    if [ ! -d "${d}" ]; then
        mkdir -p "${d}"
        chown root:root "${d}"
        chmod 0755 "${d}"
    fi
}

# ---------- Begin ----------
section "Bootstrap: llama.cpp + OpenWebUI (v0.1)"
date
echo "Logfile: ${LOGFILE}"

pause

# Require root so installs /opt /srv /etc operations succeed
require_root

############################################
# [0] Create base directories and users
############################################
section "[0/12] Preparing directories and service user"
pause

# create service user to run services (non-login)
if ! id -u aiuser &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin aiuser
    echo "Created system user: aiuser"
else
    echo "System user aiuser already exists"
fi

# directories
mkdir_if_missing "${OPT_DIR}"
mkdir_if_missing "${SRV_DIR}"
mkdir_if_missing "${AI_MODELS_DIR}"
mkdir_if_missing "${LLAMACPP_MODELS_DIR}"
mkdir_if_missing "${OPENWEBUI_DATA_DIR}"

# make aiuser own the model/data dirs
chown -R aiuser:aiuser "${SRV_DIR}"

############################################
# [1] Update system & install core build deps
############################################
section "[1/12] Update & install build/runtime packages"
pause

safe_apt_update
apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git curl wget ca-certificates \
    pkg-config unzip \
    python3 python3-venv python3-pip python3-distutils python3-dev \
    gcc g++ make

# install additional libraries often needed for builds
apt-get install -y --no-install-recommends libopenblas-dev libblas-dev liblapack-dev

# ensure pip is usable and up to date
python3 -m pip install --upgrade pip setuptools wheel || true

############################################
# Optional: install fastfetch (safe, distro-only) or fallback to neofetch
############################################
# Do NOT add third-party PPAs or build from random GitHub releases in an
# unattended bootstrap. This block installs `fastfetch` only if it's available
# in the distro repositories. If not present, it will try `neofetch` as a
# harmless fallback. If neither is found, it skips installation.
install_fastfetch_safe() {
    local tool=""

    if apt-cache show fastfetch >/dev/null 2>&1; then
        echo "fastfetch available in distro repos — installing"
        apt-get update -y
        apt-get install -y --no-install-recommends fastfetch || {
            echo "fastfetch install failed; continuing without it"
        }
        tool=$(command -v fastfetch || true)
    elif apt-cache show neofetch >/dev/null 2>&1; then
        echo "fastfetch not in repos; installing neofetch as a safe fallback"
        apt-get update -y
        apt-get install -y --no-install-recommends neofetch || {
            echo "neofetch install failed; continuing without it"
        }
        tool=$(command -v neofetch || true)
    else
        echo "fastfetch/neofetch not present in distro repos; skipping UI info tool install"
        tool=""
    fi

        # Optionally create a system-wide, non-fatal login hook so interactive shells
        # display info. This is opt-in: set `INSTALL_SYSTEM_INFO=1` when running the
        # bootstrap to enable it. We avoid changing user dotfiles by using
        # /etc/profile.d when explicitly requested.
        if [ -n "${tool}" ]; then
                if [ -n "${INSTALL_SYSTEM_INFO:-}" ]; then
                        cat > /etc/profile.d/00-system-info.sh <<EOF
# Show system info on interactive login if ${tool} exists
if [ -n "\$PS1" ] && command -v ${tool##*/} >/dev/null 2>&1; then
        # run the tool but never fail the shell if it errors
        command -v ${tool##*/} >/dev/null 2>&1 && ${tool##*/} || true
fi
EOF
                        chmod 644 /etc/profile.d/00-system-info.sh || true
                        echo "Installed system info hook using: ${tool}"
                else
                        cat <<EOF
System info tool available: ${tool##*/}

This installer detected ${tool##*/} in the distro repositories but did not enable
an automatic login hook. To enable the system-info hook on interactive shells,
re-run the bootstrap with:

    sudo INSTALL_SYSTEM_INFO=1 bash bootstrap-llama.cpp-openwebui.sh

Or create the hook manually (example):

    sudo tee /etc/profile.d/00-system-info.sh > /dev/null <<'HOOK'
# Show system info on interactive login
if [ -n "\$PS1" ] && command -v ${tool##*/} >/dev/null 2>&1; then
    command -v ${tool##*/} >/dev/null 2>&1 && ${tool##*/} || true
fi
HOOK

EOF
                fi
        fi
}

# Run safe installer (non-fatal)
install_fastfetch_safe || true

############################################
# [2] Install/verify CUDA runtime for WSL (WSL-friendly)
############################################
section "[2/12] Install NVIDIA CUDA runtime (WSL-friendly)"
pause

# Attempt to install CUDA runtime through NVIDIA repository (WSL recommended)
# This mirrors the common pattern used for WSL CUDA installs (may require adjustment per Ubuntu version).
CUDA_KEYRING="/tmp/cuda-keyring.deb"
CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64"
if ! command -v nvidia-smi &>/dev/null; then
    echo "nvidia-smi not found. Attempting to install CUDA runtime package (WSL)..."
    apt-get install -y gnupg software-properties-common lsb-release
    if [ ! -f "${CUDA_KEYRING}" ]; then
        wget -q "${CUDA_REPO}/cuda-keyring_1.1-1_all.deb" -O "${CUDA_KEYRING}" || true
    fi
    if [ -f "${CUDA_KEYRING}" ]; then
        dpkg -i "${CUDA_KEYRING}" || true
        safe_apt_update
        apt-get install -y --no-install-recommends cuda-runtime-12-4 || {
            echo "WARNING: cuda-runtime-12-4 install failed or not available for this distro. You may need to install CUDA from NVIDIA's site or update packages manually."
        }
    else
        echo "Could not download CUDA keyring; skipping automatic install. Please install NVIDIA CUDA for WSL manually if you want GPU acceleration."
    fi
else
    echo "nvidia-smi found. CUDA runtime likely already installed."
    nvidia-smi || true
fi

# Export common CUDA paths if present
if [ -d "/usr/local/cuda/bin" ]; then
    grep -q "/usr/local/cuda/bin" /etc/profile.d/llamacpp_path.sh 2>/dev/null || \
    echo 'export PATH=$PATH:/usr/local/cuda/bin' > /etc/profile.d/llamacpp_path.sh
fi

############################################
# [3] Build llama.cpp (CUDA)
############################################
section "[3/12] Clone & build llama.cpp with CUDA support"
pause

# clone if missing, else fetch latest
if [ ! -d "${LLAMACPP_OPT}" ]; then
    git clone --depth 1 --branch "${LLAMACPP_BRANCH}" "${LLAMACPP_REPO}" "${LLAMACPP_OPT}"
else
    echo "llama.cpp already cloned under ${LLAMACPP_OPT}; fetching updates"
    (cd "${LLAMACPP_OPT}" && git fetch --depth=1 origin "${LLAMACPP_BRANCH}" && git reset --hard "origin/${LLAMACPP_BRANCH}") || true
fi

# Build: create build dir, configure with CMake enabling CUDA/cuBLAS if possible
cd "${LLAMACPP_OPT}"
mkdir -p build
cd build

# Detect CUDA availability (simple check)
CUDA_PRESENT=0
if command -v nvcc &>/dev/null || [ -d "/usr/local/cuda" ]; then
    CUDA_PRESENT=1
fi

if [ "${CUDA_PRESENT}" -eq 1 ]; then
    echo "CUDA detected — building with CUDA/cuBLAS support"
    # configure and build (attempting to enable cublas)
    cmake -S .. -B . -G Ninja -DLLAMA_CUBLAS=ON -DCMAKE_BUILD_TYPE=Release || {
        echo "CMake configure failed for CUDA build; retrying without CUDA..."
        cmake -S .. -B . -G Ninja -DCMAKE_BUILD_TYPE=Release
    }
else
    echo "CUDA not detected — building CPU-only optimized version"
    cmake -S .. -B . -G Ninja -DCMAKE_BUILD_TYPE=Release
fi

ninja -v || {
    echo "Build failed. Please inspect the log and resolve missing dependencies."
    exit 1
}

# copy binaries to /opt/llama.cpp/bin (idempotent)
LLAMA_BIN_DIR="${LLAMACPP_OPT}/bin"
mkdir -p "${LLAMA_BIN_DIR}"
cp -u ./main "${LLAMA_BIN_DIR}/llamacpp" 2>/dev/null || true
chmod +x "${LLAMA_BIN_DIR}/llamacpp"

# Symlink to /usr/local/bin for convenience (if not present)
if [ -x "${LLAMA_BIN_DIR}/llamacpp" ]; then
    ln -sf "${LLAMA_BIN_DIR}/llamacpp" /usr/local/bin/llamacpp || true
fi

echo "llama.cpp built and installed into ${LLAMA_BIN_DIR}"

############################################
# [4] Install OpenWebUI (pip) into /opt via venv
############################################
section "[4/12] Install OpenWebUI (Python venv) into /opt"
pause

# ensure python version acceptable
PY_VER=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))' 2>/dev/null || echo "0.0")
echo "Detected Python version: ${PY_VER}"

OPENWEBUI_VENV="${OPENWEBUI_OPT}/venv"
if [ ! -d "${OPENWEBUI_OPT}" ]; then
    mkdir -p "${OPENWEBUI_OPT}"
    chown root:root "${OPENWEBUI_OPT}"
fi

# create venv and install open-webui into it
if [ ! -d "${OPENWEBUI_VENV}" ]; then
    python3 -m venv "${OPENWEBUI_VENV}"
fi

# activate venv for installation
# shellcheck disable=SC1090
source "${OPENWEBUI_VENV}/bin/activate"
pip install --upgrade pip setuptools wheel
pip install --break-system-packages --upgrade "${OPENWEBUI_PIPPKG}" || {
    echo "pip install returned non-zero; attempting a second time..."
    pip install --break-system-packages --upgrade "${OPENWEBUI_PIPPKG}" || true
}
deactivate

# Create a small wrapper script to run open-webui from /opt/openwebui/bin
mkdir -p "${OPENWEBUI_OPT}/bin"
cat > "${OPENWEBUI_OPT}/bin/openwebui-run" <<'EOF'
#!/usr/bin/env bash
BASE_DIR="$(dirname "$(dirname "$0")")"
source "${BASE_DIR}/venv/bin/activate"
exec open-webui serve --host 0.0.0.0 --port 8080
EOF
chmod +x "${OPENWEBUI_OPT}/bin/openwebui-run"
ln -sf "${OPENWEBUI_OPT}/bin/openwebui-run" /usr/local/bin/openwebui-run || true

# ensure openwebui has writable data dir
mkdir -p "${OPENWEBUI_DATA_DIR}"
chown -R aiuser:aiuser "${OPENWEBUI_DATA_DIR}"

############################################
# [5] Configure model directories + permissions
############################################
section "[5/12] Configure model directories and permissions"
pause

mkdir -p "${AI_MODELS_DIR}"
mkdir -p "${LLAMACPP_MODELS_DIR}"
mkdir -p "${OPENWEBUI_DATA_DIR}"

chown -R aiuser:aiuser "${SRV_DIR}"
chmod -R 0755 "${SRV_DIR}"

echo "Models directory: ${AI_MODELS_DIR}"
echo "LLAMA models dir: ${LLAMACPP_MODELS_DIR}"
echo "OpenWebUI data dir: ${OPENWEBUI_DATA_DIR}"

############################################
# [6] Create systemd service for llama.cpp
############################################
section "[6/12] Create systemd service for llama.cpp"
pause

LLAMA_SYSTEMD_PATH="/etc/systemd/system/${LLAMACPP_SERVICE}"
cat > "${LLAMA_SYSTEMD_PATH}" <<EOF
[Unit]
Description=llama.cpp inference (CUDA-enabled if available)
After=network.target

[Service]
Type=simple
User=aiuser
Group=aiuser
WorkingDirectory=${LLAMACPP_OPT}
# ExecStart: run the built binary in a mode that accepts HTTP/JSON requests (if you have such a server wrapper)
# The default llama.cpp main may be interactive; adapt ExecStart to your server wrapper or create one.
ExecStart=/usr/local/bin/llamacpp
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "${LLAMA_SYSTEMD_PATH}"
systemctl daemon-reload || true

############################################
# [7] Create systemd service for OpenWebUI
############################################
section "[7/12] Create systemd service for OpenWebUI"
pause

OPENWEBUI_SYSTEMD_PATH="/etc/systemd/system/${OPENWEBUI_SERVICE}"
cat > "${OPENWEBUI_SYSTEMD_PATH}" <<EOF
[Unit]
Description=Open WebUI (Python venv)
After=network.target

[Service]
Type=simple
User=aiuser
Group=aiuser
WorkingDirectory=${OPENWEBUI_OPT}
ExecStart=${OPENWEBUI_OPT}/bin/openwebui-run
Restart=on-failure
RestartSec=5s
Environment=OPENWEBUI_DATA_DIR=${OPENWEBUI_DATA_DIR}
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "${OPENWEBUI_SYSTEMD_PATH}"
systemctl daemon-reload || true

############################################
# [8] Enable and (optionally) start services
############################################
section "[8/12] Enable and start systemd services"
pause

# Enable services (will auto-start with systemd)
systemctl enable --now "${LLAMACPP_SERVICE}" || echo "Warning: enabling/starting ${LLAMACPP_SERVICE} failed (WSL may not have systemd enabled)."
systemctl enable --now "${OPENWEBUI_SERVICE}" || echo "Warning: enabling/starting ${OPENWEBUI_SERVICE} failed (WSL may not have systemd enabled)."

echo "systemd enable attempted. If your WSL distro does not support systemd, please enable it (Windows + WSL updates) or run services manually."

############################################
# [9] Quick verification
############################################
section "[9/12] Quick verification checks"
pause

echo "--- Commands to check status ---"
echo "systemctl status ${LLAMACPP_SERVICE} --no-pager"
echo "systemctl status ${OPENWEBUI_SERVICE} --no-pager"
echo "ps aux | grep -E 'llamacpp|open-webui'"

if command -v nvidia-smi &>/dev/null; then
    echo "--- GPU Info ---"
    nvidia-smi
else
    echo "nvidia-smi not present; CUDA may not be available in this environment."
fi

############################################
# [10] Cleanup and notes
############################################
section "[10/12] Cleanup & Final Notes"
pause

apt-get autoremove -y || true
apt-get clean || true

cat <<EOF

Bootstrap completed (v0.1) — summary:

• llama.cpp installed to: ${LLAMACPP_OPT}
  - main binary symlinked to: /usr/local/bin/llamacpp
  - models root: ${LLAMACPP_MODELS_DIR}

• OpenWebUI installed in venv at: ${OPENWEBUI_OPT}
  - run via: openwebui-run (symlinked to /usr/local/bin/openwebui-run)
  - openwebui data: ${OPENWEBUI_DATA_DIR}

• Unified models directory: ${AI_MODELS_DIR}
  - please place your gguf/quantized models in ${AI_MODELS_DIR} and create symlinks into ${LLAMACPP_MODELS_DIR} if desired.

• Systemd services:
  - ${LLAMACPP_SERVICE}
  - ${OPENWEBUI_SERVICE}

Notes:
- If systemd is not active inside WSL, enable it via the WSL update or run the services manually:
    sudo -u aiuser /usr/local/bin/llamacpp &
    sudo -u aiuser ${OPENWEBUI_OPT}/bin/openwebui-run &

- For CUDA builds you may need matching NVIDIA Windows drivers and the WSL CUDA runtime; see NVIDIA docs.

Log file: ${LOGFILE}

EOF

############################################
# [11] Provide usage examples
############################################
section "[11/12] Usage examples & suggestions"
pause

cat <<'EOF'
Examples:
- To list models (OpenWebUI), visit http://<wsl-ip>:8080
- To run llama.cpp manually:
    sudo -u aiuser /usr/local/bin/llamacpp --help
- To add a model:
    # copy gguf file to /srv/ai/models and then symlink
    ln -s /srv/ai/models/your-model.gguf /srv/llama.cpp/models/your-model.gguf

Recommended next steps:
1) Verify CUDA with `nvidia-smi` on the WSL shell.
2) If OpenWebUI complains about Python version, consider installing Python 3.11 and recreating the venv.
3) If you prefer Docker deployment, consider using containerized OpenWebUI/llama.cpp and systemd-run or docker-compose with systemd unit wrappers.
EOF

############################################
# [12] Finish
############################################
section "[12/12] Done"
echo "Bootstrap finished at: $(date)"
echo "Please inspect ${LOGFILE} for details."
