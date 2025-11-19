#!/usr/bin/env bash
# ==============================================================
# Bootstrap: llama.cpp + OpenWebUI (v0.17a)
# - Detect NVIDIA/CUDA
# - Auto CPU fallback
# - Systemd services
# - WSL2/Ubuntu safe Python venv for OpenWebUI
# ==============================================================

set -euo pipefail

# ------------------------ Variables --------------------------
LLAMACPP_REPO="https://github.com/ggerganov/llama.cpp.git"
LLAMACPP_OPT="/opt/llama.cpp"
OPENWEBUI_REPO="https://github.com/openwebui/openwebui.git"
OPENWEBUI_OPT="/opt/openwebui"
SERVICE_USER="aiuser"
AUTO=${AUTO:-0}

# ------------------------ Helper -----------------------------
pause() {
    if [ "$AUTO" -ne 1 ]; then
        read -rp "⏸ Press ENTER to continue (or set AUTO=1 to skip)..."
    fi
}

section() {
    echo
    echo "=============================================================="
    echo " $1"
    echo "=============================================================="
}

# ------------------------ 0. Prepare dirs & user -------------------
section "[0/12] Preparing directories and service user"
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$SERVICE_USER"
    echo "Created system user: $SERVICE_USER"
fi
pause

# ------------------------ 1. Update & install packages -------------------
section "[1/12] Update & install build/runtime packages"
apt update && apt upgrade -y
apt install -y git build-essential cmake ninja-build python3 python3-pip python3-venv wget curl lsb-release software-properties-common
pause

# ------------------------ 2. Detect NVIDIA/CUDA -------------------
section "[2/12] NVIDIA/CUDA detection"
HAS_CUDA=0
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "NVIDIA GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)"
    if nvidia-smi >/dev/null 2>&1; then
        HAS_CUDA=1
        echo "CUDA toolkit detected: $(nvcc --version 2>/dev/null || echo 0)"
    fi
else
    echo "No NVIDIA GPU detected, will use CPU build"
fi
pause

# ------------------------ 3. Clone llama.cpp -------------------
section "[3/12] Clone & prepare llama.cpp source"
rm -rf "$LLAMACPP_OPT"
git clone --branch master "$LLAMACPP_REPO" "$LLAMACPP_OPT"
pause

# ------------------------ 4. Build llama.cpp -------------------
section "[4/12] Build llama.cpp (CUDA if available, else CPU). Auto-retry CPU on failure"
cd "$LLAMACPP_OPT"
mkdir -p build
cd build

build_llama() {
    local mode="$1"
    echo "Configuring llama.cpp build (mode=${mode})"
    if [ "$mode" = "cuda" ]; then
        cmake -S .. -B . -G Ninja -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release || return 1
    else
        cmake -S .. -B . -G Ninja -DCMAKE_BUILD_TYPE=Release || return 1
    fi
    echo "Running ninja build..."
    if ninja -v; then
        return 0
    else
        return 1
    fi
}

if [ "$HAS_CUDA" -eq 1 ]; then
    if ! build_llama "cuda"; then
        echo "CUDA build failed. Retrying CPU-only build..."
        build_llama "cpu" || { echo "Both CUDA and CPU builds failed. Exiting."; exit 1; }
    fi
else
    build_llama "cpu" || { echo "CPU build failed. Exiting."; exit 1; }
fi
pause

# ------------------------ 5. Clone OpenWebUI -------------------
section "[5/12] Clone OpenWebUI"
rm -rf "$OPENWEBUI_OPT"
git clone "$OPENWEBUI_REPO" "$OPENWEBUI_OPT"
pause

# ------------------------ 6. Setup Python venv for OpenWebUI -------------------
section "[6/12] Python virtual environment for OpenWebUI"
sudo -u $SERVICE_USER python3 -m venv "$OPENWEBUI_OPT/venv"
sudo -u $SERVICE_USER "$OPENWEBUI_OPT/venv/bin/pip" install --upgrade pip setuptools wheel
sudo -u $SERVICE_USER "$OPENWEBUI_OPT/venv/bin/pip" install -r "$OPENWEBUI_OPT/requirements.txt"
pause

# ------------------------ 7. Setup systemd services -------------------
section "[7/12] Setup systemd services"

# llama.cpp service
cat <<EOF >/etc/systemd/system/llamacpp.service
[Unit]
Description=llama.cpp Server
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
ExecStart=$LLAMACPP_OPT/build/main -m /srv/llama.cpp/models
Restart=always
WorkingDirectory=$LLAMACPP_OPT

[Install]
WantedBy=multi-user.target
EOF

# OpenWebUI service
cat <<EOF >/etc/systemd/system/openwebui.service
[Unit]
Description=OpenWebUI
After=network.target llamacpp.service

[Service]
Type=simple
User=$SERVICE_USER
ExecStart=$OPENWEBUI_OPT/venv/bin/python $OPENWEBUI_OPT/start-webui.py --host 0.0.0.0 --port 8080
Restart=always
WorkingDirectory=$OPENWEBUI_OPT

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable llamacpp.service
systemctl enable openwebui.service
pause

# ------------------------ 8. Setup model directory -------------------
section "[8/12] Create model directory"
mkdir -p /srv/llama.cpp/models
chown -R $SERVICE_USER:$SERVICE_USER /srv/llama.cpp
pause

# ------------------------ 9. Firewall hints -------------------
section "[9/12] Firewall (optional)"
echo "Make sure ports 8080 (OpenWebUI) and any llama.cpp server ports are open."
pause

# ------------------------ 10. Summary -------------------
section "[10/12] Bootstrap completed"
echo "llama.cpp and OpenWebUI installed."
echo "Systemd services:"
echo "  sudo systemctl start llamacpp"
echo "  sudo systemctl start openwebui"
echo "Models directory: /srv/llama.cpp/models"
echo "OpenWebUI: http://<host>:8080"
pause
