#!/usr/bin/env bash

set -e

###############################################
# CONFIGURATION
###############################################
MODEL_REPO="Qwen/Qwen-2.5-Coder-7B-GGUF"
MODEL_INSTALL_DIR="/opt/ai-models"

###############################################
# 0. Update package lists
###############################################
echo "=== Updating package lists ==="
apt update -y

###############################################
# 1. Install prerequisites
###############################################
echo "=== Installing prerequisites ==="
apt install -y wget btop python3 python3-venv python3-pip git curl pipx

# Ensure pipx bin is on PATH for this session
export PATH="$PATH:/root/.local/bin"
if ! grep -q "/root/.local/bin" /root/.bashrc; then
    echo 'export PATH="$PATH:/root/.local/bin"' >> /root/.bashrc
fi

###############################################
# 2. Install Fastfetch
###############################################
echo "=== Installing Fastfetch ==="
if ! command -v fastfetch >/dev/null 2>&1; then
    cd /tmp
    wget -O fastfetch-linux-amd64.deb \
      https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb
    apt install -y ./fastfetch-linux-amd64.deb
fi

if ! grep -q "fastfetch" /root/.bashrc; then
    echo "fastfetch" >> /root/.bashrc
fi

###############################################
# 3. Ensure login starts in /root
###############################################
echo "=== Fixing WSL default login directory ==="
if ! grep -q "cd ~" /root/.bashrc; then
    echo "cd ~" >> /root/.bashrc
fi

if [ -n "$SUDO_USER" ] && [ -f "/home/$SUDO_USER/.bashrc" ]; then
    if ! grep -q "cd ~" /home/$SUDO_USER/.bashrc; then
        echo "cd ~" >> /home/$SUDO_USER/.bashrc
    fi
fi

###############################################
# 4. Install Hugging Face Hub CLI via pipx
###############################################
echo "=== Installing Hugging Face Hub CLI (hf) via pipx ==="
pipx install --force huggingface_hub

# Ensure hf CLI is on PATH
export PATH="$PATH:/root/.local/bin"

###############################################
# 5. Hugging Face login & model download
###############################################
echo "=== Logging into Hugging Face ==="
"$HOME/.local/bin/hf" auth login || true

echo "=== Creating model install directory ==="
mkdir -p "$MODEL_INSTALL_DIR"

echo "=== Downloading Qwen 2.5-Coder 7B model ==="
cd "$MODEL_INSTALL_DIR"
"$HOME/.local/bin/hf" repo clone "$MODEL_REPO" .

echo "✓ Model downloaded to $MODEL_INSTALL_DIR"

###############################################
# 6. Completion message
###############################################
echo "=== Setup complete! ==="
echo "Close and reopen your WSL terminal to see Fastfetch on login."
echo "Hugging Face CLI available at $HOME/.local/bin/hf"
echo "Qwen 2.5-Coder 7B model installed at $MODEL_INSTALL_DIR"
#!/usr/bin/env bash

set -e

###############################################
# CONFIGURATION
###############################################
MODEL_REPO="Qwen/Qwen-2.5-Coder-7B-GGUF"
MODEL_INSTALL_DIR="/opt/ai-models"

###############################################
# 0. Update package lists
###############################################
echo "=== Updating package lists ==="
apt update -y

###############################################
# 1. Install prerequisites
###############################################
echo "=== Installing prerequisites ==="
apt install -y wget btop python3 python3-venv python3-pip git curl pipx

# Ensure pipx bin is on PATH for this session
export PATH="$PATH:/root/.local/bin"
if ! grep -q "/root/.local/bin" /root/.bashrc; then
    echo 'export PATH="$PATH:/root/.local/bin"' >> /root/.bashrc
fi

###############################################
# 2. Install Fastfetch
###############################################
echo "=== Installing Fastfetch ==="
if ! command -v fastfetch >/dev/null 2>&1; then
    cd /tmp
    wget -O fastfetch-linux-amd64.deb \
      https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb
    apt install -y ./fastfetch-linux-amd64.deb
fi

if ! grep -q "fastfetch" /root/.bashrc; then
    echo "fastfetch" >> /root/.bashrc
fi

###############################################
# 3. Ensure login starts in /root
###############################################
echo "=== Fixing WSL default login directory ==="
if ! grep -q "cd ~" /root/.bashrc; then
    echo "cd ~" >> /root/.bashrc
fi

if [ -n "$SUDO_USER" ] && [ -f "/home/$SUDO_USER/.bashrc" ]; then
    if ! grep -q "cd ~" /home/$SUDO_USER/.bashrc; then
        echo "cd ~" >> /home/$SUDO_USER/.bashrc
    fi
fi

###############################################
# 4. Install Hugging Face Hub CLI via pipx
###############################################
echo "=== Installing Hugging Face Hub CLI (hf) via pipx ==="
pipx install --force huggingface_hub

# Ensure hf CLI is on PATH
export PATH="$PATH:/root/.local/bin"

###############################################
# 5. Hugging Face login & model download
###############################################
echo "=== Logging into Hugging Face ==="
"$HOME/.local/bin/hf" auth login || true

echo "=== Creating model install directory ==="
mkdir -p "$MODEL_INSTALL_DIR"

echo "=== Downloading Qwen 2.5-Coder 7B model ==="
cd "$MODEL_INSTALL_DIR"
"$HOME/.local/bin/hf" repo clone "$MODEL_REPO" .

echo "✓ Model downloaded to $MODEL_INSTALL_DIR"

###############################################
# 6. Completion message
###############################################
echo "=== Setup complete! ==="
echo "Close and reopen your WSL terminal to see Fastfetch on login."
echo "Hugging Face CLI available at $HOME/.local/bin/hf"
echo "Qwen 2.5-Coder 7B model installed at $MODEL_INSTALL_DIR"
