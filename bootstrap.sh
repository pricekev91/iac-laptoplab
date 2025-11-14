#!/usr/bin/env bash
# ===============================================
# bootstrap.sh — Version 0.9 (WSL AI + Ollama + WebUI)
# -----------------------------------------------
# Author: Kevin Price (Updated)
# Purpose:
#     Configure a WSL Ubuntu environment for running
#     Ollama and OpenWebUI with GPU support (WSL-safe)
#     Auto-start services and set DeepSeek-R1:1.5b as default model
#
# Changelog:
#   v0.9 - Added auto-start for Ollama & OpenWebUI
#          Persistent Ollama models
#          Default model: deepseek-r1:1.5b
# ===============================================

LOGFILE="$HOME/bootstrap.log"
exec > >(tee -a "$LOGFILE") 2>&1
set -e  # Exit immediately on any error

pause() {
    if [ -z "$AUTO" ]; then
        read -rp $'\n⏸️  Press any key to continue... ' -n1 -s
        echo -e "\n"
    fi
}

echo "=== Starting Bootstrap Script v0.9 ==="
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
add-apt-repository -y ppa:zhangsongcui3371/fastfetch
apt-get update -y
apt-get install -y fastfetch

grep -q "fastfetch" ~/.bashrc || echo "fastfetch" >> ~/.bashrc
grep -q "nvidia-smi" ~/.bashrc || \
echo 'nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu --format=csv,noheader' >> ~/.bashrc

##############################################
# [3/10] Install WSL-safe CUDA runtime only
##############################################
echo "[3/10] Installing NVIDIA CUDA runtime libraries (WSL-safe)..."
pause
apt-get install -y wget gnupg software-properties-common libtinfo6

CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/"
wget -q ${CUDA_REPO}/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb
dpkg -i /tmp/cuda-keyring.deb
apt-get update -y

apt-get install -y cuda-runtime-12-4

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
# [5/10] Install system utilities
##############################################
echo "[5/10] Installing btop and common utilities..."
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

# Persistent Ollama data
export OLLAMA_HOME="$HOME/.ollama"
grep -q "OLLAMA_HOME" ~/.bashrc || echo 'export OLLAMA_HOME="$HOME/.ollama"' >> ~/.bashrc

echo "Starting Ollama service..."
nohup ollama serve > /var/log/ollama.log 2>&1 &
sleep 5

echo "Pulling default Ollama model (deepseek-r1:1.5b)..."
ollama pull deepseek-r1:1.5b

##############################################
# [8/10] Install OpenWebUI
##############################################
echo "[8/10] Installing OpenWebUI..."
pause
pip install --break-system-packages --ignore-installed open-webui || {
    echo "[WARN] Pip install failed, retrying..."
    pip install --break-system-packages --ignore-installed open-webui
}

export PATH=$PATH:/usr/local/bin:~/.local/bin
grep -q "open-webui" ~/.bashrc || echo 'export PATH=$PATH:/usr/local/bin:~/.local/bin' >> ~/.bashrc

echo "Starting OpenWebUI on port 8080..."
nohup open-webui serve --host 0.0.0.0 --port 8080 --ollama-base-url http://localhost:11434 > /var/log/openwebui.log 2>&1 &
sleep 5

##############################################
# [9/10] Auto-start Ollama & OpenWebUI on WSL launch
##############################################
echo "[9/10] Adding auto-start for Ollama and OpenWebUI..."
pause
cat << 'EOF' >> ~/.bashrc

# Auto-start Ollama and OpenWebUI
if ! pgrep -f "ollama serve" > /dev/null; then
    nohup ollama serve > /var/log/ollama.log 2>&1 &
fi

if ! pgrep -f "open-webui serve" > /dev/null; then
    nohup open-webui serve --host 0.0.0.0 --port 8080 --ollama-base-url http://localhost:11434 \
    > /var/log/openwebui.log 2>&1 &
fi
EOF

##############################################
# [10/10] Cleanup
##############################################
echo "[10/10] Cleaning up..."
pause
apt-get autoremove -y && apt-get clean

##############################################
# Final Notes
##############################################
echo "==============================================="
echo "✅ Bootstrap Completed Successfully!"
echo "✅ Access OpenWebUI at: http://<your-ip>:8080"
echo "✅ Default model: deepseek-r1:1.5b"
echo "✅ Log saved to $LOGFILE"
echo "Run 'wsl --shutdown' in PowerShell to apply /etc/wsl.conf changes."
echo "==============================================="
