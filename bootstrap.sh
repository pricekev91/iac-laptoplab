#!/usr/bin/env bash
# ===============================================
# bootstrap.sh — Version 0.8 (WSL CUDA Fix)
# -----------------------------------------------
# Author: Kevin Price
# Purpose:
#     Configure a WSL Ubuntu environment for GPU-enabled
#     AI and development workloads without installing Linux GPU drivers.
#
# Changelog:
#   v0.8 - Removed Linux NVIDIA driver installs, kept CUDA toolkit only,
#          added PATH export for nvcc, improved idempotency.
# ===============================================

LOGFILE="$HOME/bootstrap.log"
exec > >(tee -a "$LOGFILE") 2>&1
set -e  # Exit immediately on any error

pause() {
    if [ -z "$AUTO" ]; then
        read -rp $'\nPress any key to continue to the next step... ' -n1 -s
        echo -e "\n"
    fi
}

echo "=== Starting Bootstrap Script v0.8 ==="
echo "Timestamp: $(date)"
echo "Logfile: $LOGFILE"
echo "====================================="

##############################################
# [0/10] Configure WSL default user and home
##############################################
echo "[0/10] Configuring /etc/wsl.conf to start in /root..."
pause
cat << 'EOF' | sudo tee /etc/wsl.conf > /dev/null
[user]
default=root

[boot]
command="cd ~"
EOF

##############################################
# [1/10] Update & Upgrade System
##############################################
echo "[1/10] Updating and upgrading system packages..."
pause
apt-get update -y && apt-get upgrade -y

##############################################
# [2/10] Install Fastfetch for system info
##############################################
echo "[2/10] Installing Fastfetch..."
pause
add-apt-repository ppa:zhangsongcui3371/fastfetch -y
apt-get update -y
apt-get install fastfetch -y

grep -q "fastfetch" ~/.bashrc || echo "fastfetch" >> ~/.bashrc
grep -q "nvidia-smi --query-gpu" ~/.bashrc || \
echo 'nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu --format=csv,noheader' >> ~/.bashrc

##############################################
# [3/10] Install CUDA Toolkit (WSL-safe)
##############################################
echo "[3/10] Installing NVIDIA CUDA toolkit (WSL-safe)..."
pause
apt-get install -y wget gnupg libtinfo6
CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/"
wget ${CUDA_REPO}/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update -y
apt-get install -y cuda-toolkit-12-4

# Add CUDA to PATH
grep -q "/usr/local/cuda/bin" ~/.bashrc || echo 'export PATH=$PATH:/usr/local/cuda/bin' >> ~/.bashrc
export PATH=$PATH:/usr/local/cuda/bin

##############################################
# [4/10] Verify GPU Access
##############################################
echo "[4/10] Verifying GPU access..."
pause
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi
else
    echo "⚠️ nvidia-smi not found. WSL uses Windows driver; this is expected."
fi

##############################################
# [5/10] Install system utilities (btop, etc.)
##############################################
echo "[5/10] Installing btop and base utilities..."
pause
apt-get install -y btop git curl software-properties-common

##############################################
# [6/10] Install Python, PyTorch (CUDA), HuggingFace
##############################################
echo "[6/10] Installing Python, PyTorch (CUDA), and HuggingFace..."
pause
apt-get install -y python3 python3-pip
export PATH=$PATH:/usr/local/bin:~/.local/bin

pip install --break-system-packages torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
pip install --break-system-packages transformers accelerate sentencepiece

python3 - << 'EOF'
import torch
print("PyTorch CUDA available:", torch.cuda.is_available())
print("GPU Name:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "No GPU detected")
EOF

##############################################
# [7/10] Install and start Ollama
##############################################
echo "[7/10] Installing Ollama CLI..."
pause
curl -fsSL https://ollama.com/install.sh | sh

echo "Starting Ollama service..."
nohup ollama serve > /var/log/ollama.log 2>&1 &
sleep 5

echo "Verifying Ollama API..."
curl -s http://localhost:11434/api/tags || echo "⚠️ Ollama may not be running yet."

##############################################
# [8/10] Install OpenWebUI
##############################################
echo "[8/10] Installing OpenWebUI..."
pause
curl -fsSL https://openwebui.com/install.sh | bash || {
    echo "Fallback to pip install..."
    pip install --break-system-packages open-webui
}

export PATH=$PATH:/usr/local/bin:~/.local/bin
grep -q "open-webui" ~/.bashrc || echo 'export PATH=$PATH:/usr/local/bin:~/.local/bin' >> ~/.bashrc

echo "Starting OpenWebUI on port 8080..."
nohup open-webui serve --host 0.0.0.0 --port 8080 --ollama-base-url http://localhost:11434 > /var/log/openwebui.log 2>&1 &
sleep 5

##############################################
# [9/10] Cleanup
##############################################
echo "[9/10] Cleaning up..."
pause
apt-get autoremove -y && apt-get clean

##############################################
# [10/10] Final Notes
##############################################
echo "=== Bootstrap Completed Successfully ==="
echo "Access OpenWebUI at: http://<your-ip>:8080"
echo "First-use will prompt you to create an admin account."
echo "Log saved to $LOGFILE"
echo "Run 'wsl --shutdown' in PowerShell to apply /etc/wsl.conf changes."
echo "==============================================="
pause
