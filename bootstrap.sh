#!/usr/bin/env bash
# bootstrap.sh - Configure WSL Ubuntu environment for GPU-enabled development + AI stack
# Logs everything to ~/bootstrap.log

LOGFILE="$HOME/bootstrap.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== Starting Bootstrap Script ==="
echo "Timestamp: $(date)"

##############################################
# [0/11] Configure WSL default user and home
##############################################
echo "[0/11] Configuring /etc/wsl.conf to start in /root..."
cat << 'EOF' | sudo tee /etc/wsl.conf > /dev/null
[user]
default=root

[boot]
command="cd ~"
EOF

##############################################
# [1/11] Update & Upgrade System
##############################################
echo "[1/11] Updating system..."
apt-get update -y && apt-get upgrade -y

##############################################
# [2/11] Install Fastfetch for system info
##############################################
echo "[2/11] Installing Fastfetch..."
add-apt-repository ppa:zhangsongcui3371/fastfetch -y
apt-get update -y
apt-get install fastfetch -y

# Add Fastfetch and GPU summary to .bashrc if not already present
if ! grep -q "fastfetch" ~/.bashrc; then
    echo "fastfetch" >> ~/.bashrc
fi
if ! grep -q "nvidia-smi --query-gpu" ~/.bashrc; then
    echo 'nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu --format=csv,noheader' >> ~/.bashrc
fi

##############################################
# [3/11] Install libtinfo5 (CUDA dependency)
##############################################
echo "[3/11] Installing libtinfo5..."
apt-get install libtinfo5 -y

##############################################
# [4/11] Install NVIDIA CLI tools & CUDA runtime
##############################################
echo "[4/11] Installing NVIDIA CLI tools and CUDA runtime..."
CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/"
apt-get install wget gnupg -y
wget ${CUDA_REPO}/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update -y
apt-get install nvidia-utils-535 nvidia-container-toolkit cuda-runtime-12-2 -y

##############################################
# [5/11] Verify GPU Access
##############################################
echo "[5/11] Verifying GPU access..."
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi
else
    echo "nvidia-smi not found. Check NVIDIA installation."
fi

##############################################
# [6/11] Install btop (system monitor)
##############################################
echo "[6/11] Installing btop..."
apt-get install btop -y

##############################################
# [7/11] Cleanup
##############################################
echo "[7/11] Cleaning up..."
apt-get autoremove -y && apt-get clean

##############################################
# [8/11] Install Python, PyTorch (CUDA), HuggingFace
##############################################
echo "[8/11] Installing Python, PyTorch (CUDA), and HuggingFace..."
apt-get install python3 python3-pip git curl -y
# Install PyTorch with CUDA support (CUDA 12.x)
pip install --break-system-packages torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
# Install HuggingFace tools
pip install --break-system-packages transformers accelerate sentencepiece

# Verify PyTorch GPU support
python3 - << 'EOF'
import torch
print("PyTorch CUDA available:", torch.cuda.is_available())
print("GPU Name:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "No GPU detected")
EOF

##############################################
# [9/11] Install and configure Open LLaMA (7B)
##############################################
echo "[9/11] Installing Open LLaMA..."
git clone https://github.com/openlm-research/open_llama.git /opt/open_llama
cd /opt/open_llama

# Download 7B model weights from HuggingFace
mkdir -p models/open_llama_7b && cd models/open_llama_7b
wget https://huggingface.co/openlm-research/open_llama_7b/resolve/main/pytorch_model.bin
wget https://huggingface.co/openlm-research/open_llama_7b/resolve/main/config.json
wget https://huggingface.co/openlm-research/open_llama_7b/resolve/main/tokenizer.model
cd /opt/open_llama

echo "Open LLaMA installed. Test with: python3 inference.py --model models/open_llama_7b"

##############################################
# [10/11] Install Ollama CLI and start service
##############################################
echo "[10/11] Installing Ollama CLI..."
curl -fsSL https://ollama.com/install.sh | sh

# Start Ollama service
echo "Starting Ollama service..."
nohup ollama serve > /var/log/ollama.log 2>&1 &

echo "Ollama installed. Pull models with: ollama pull <model-name>"
echo "Browse models: https://ollama.com/library"

##############################################
# [11/11] Install and configure OpenWebUI
##############################################
echo "[11/11] Installing OpenWebUI..."
pip install --break-system-packages open-webui

# Ensure PATH includes pip binaries
export PATH=$PATH:~/.local/bin
echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc

# Start OpenWebUI with Ollama integration
echo "Starting OpenWebUI on 0.0.0.0:8080 with Ollama integration..."
nohup open-webui serve --host 0.0.0.0 --port 8080 --ollama-base-url http://localhost:11434 > /var/log/openwebui.log 2>&1 &

echo "Access OpenWebUI at: http://<your-ip>:8080"
echo "First-use will prompt you to create an admin account."

##############################################
# Final Notes
##############################################
echo "=== Bootstrap Completed Successfully ==="
echo "Log saved to $LOGFILE"
echo "Reminder: run 'wsl --shutdown' in PowerShell to apply /etc/wsl.conf changes."#!/usr/bin/env bash
# bootstrap.sh - Configure WSL Ubuntu environment for GPU-enabled development + AI stack
# Logs everything to ~/bootstrap.log

LOGFILE="$HOME/bootstrap.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== Starting Bootstrap Script ==="
echo "Timestamp: $(date)"

##############################################
# [0/11] Configure WSL default user and home
##############################################
echo "[0/11] Configuring /etc/wsl.conf to start in /root..."
cat << 'EOF' | sudo tee /etc/wsl.conf > /dev/null
[user]
default=root

[boot]
command="cd ~"
EOF

##############################################
# [1/11] Update & Upgrade System
##############################################
echo "[1/11] Updating system..."
apt-get update -y && apt-get upgrade -y

##############################################
# [2/11] Install Fastfetch for system info
##############################################
echo "[2/11] Installing Fastfetch..."
add-apt-repository ppa:zhangsongcui3371/fastfetch -y
apt-get update -y
apt-get install fastfetch -y

# Add Fastfetch and GPU summary to .bashrc if not already present
if ! grep -q "fastfetch" ~/.bashrc; then
    echo "fastfetch" >> ~/.bashrc
fi
if ! grep -q "nvidia-smi --query-gpu" ~/.bashrc; then
    echo 'nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu --format=csv,noheader' >> ~/.bashrc
fi

##############################################
# [3/11] Install libtinfo5 (CUDA dependency)
##############################################
echo "[3/11] Installing libtinfo5..."
apt-get install libtinfo5 -y

##############################################
# [4/11] Install NVIDIA CLI tools & CUDA runtime
##############################################
echo "[4/11] Installing NVIDIA CLI tools and CUDA runtime..."
CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/"
apt-get install wget gnupg -y
wget ${CUDA_REPO}/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update -y
apt-get install nvidia-utils-535 nvidia-container-toolkit cuda-runtime-12-2 -y

##############################################
# [5/11] Verify GPU Access
##############################################
echo "[5/11] Verifying GPU access..."
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi
else
    echo "nvidia-smi not found. Check NVIDIA installation."
fi

##############################################
# [6/11] Install btop (system monitor)
##############################################
echo "[6/11] Installing btop..."
apt-get install btop -y

##############################################
# [7/11] Cleanup
##############################################
echo "[7/11] Cleaning up..."
apt-get autoremove -y && apt-get clean

##############################################
# [8/11] Install Python, PyTorch (CUDA), HuggingFace
##############################################
echo "[8/11] Installing Python, PyTorch (CUDA), and HuggingFace..."
apt-get install python3 python3-pip git curl -y
# Install PyTorch with CUDA support (CUDA 12.x)
pip install --break-system-packages torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
# Install HuggingFace tools
pip install --break-system-packages transformers accelerate sentencepiece

# Verify PyTorch GPU support
python3 - << 'EOF'
import torch
print("PyTorch CUDA available:", torch.cuda.is_available())
print("GPU Name:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "No GPU detected")
EOF

##############################################
# [9/11] Install and configure Open LLaMA (7B)
##############################################
echo "[9/11] Installing Open LLaMA..."
git clone https://github.com/openlm-research/open_llama.git /opt/open_llama
cd /opt/open_llama

# Download 7B model weights from HuggingFace
mkdir -p models/open_llama_7b && cd models/open_llama_7b
wget https://huggingface.co/openlm-research/open_llama_7b/resolve/main/pytorch_model.bin
wget https://huggingface.co/openlm-research/open_llama_7b/resolve/main/config.json
wget https://huggingface.co/openlm-research/open_llama_7b/resolve/main/tokenizer.model
cd /opt/open_llama

echo "Open LLaMA installed. Test with: python3 inference.py --model models/open_llama_7b"

##############################################
# [10/11] Install Ollama CLI and start service
##############################################
echo "[10/11] Installing Ollama CLI..."
curl -fsSL https://ollama.com/install.sh | sh

# Start Ollama service
echo "Starting Ollama service..."
nohup ollama serve > /var/log/ollama.log 2>&1 &

echo "Ollama installed. Pull models with: ollama pull <model-name>"
echo "Browse models: https://ollama.com/library"

##############################################
# [11/11] Install and configure OpenWebUI
##############################################
echo "[11/11] Installing OpenWebUI..."
pip install --break-system-packages open-webui

# Ensure PATH includes pip binaries
export PATH=$PATH:~/.local/bin
echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc

# Start OpenWebUI with Ollama integration
echo "Starting OpenWebUI on 0.0.0.0:8080 with Ollama integration..."
nohup open-webui serve --host 0.0.0.0 --port 8080 --ollama-base-url http://localhost:11434 > /var/log/openwebui.log 2>&1 &

echo "Access OpenWebUI at: http://<your-ip>:8080"
echo "First-use will prompt you to create an admin account."

##############################################
# Final Notes
##############################################
echo "=== Bootstrap Completed Successfully ==="
echo "Log saved to $LOGFILE"
echo "Reminder: run 'wsl --shutdown' in PowerShell to apply /etc/wsl.conf changes."
