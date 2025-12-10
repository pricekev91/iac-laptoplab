# ============================================================
#  wsl-bootstrap.sh  — v0.13
#  Author: Kevin Price — 2025-11-24
#
#  === AI-EDITING RULES (READ BEFORE CHANGES) ===
#
#  • Do NOT rewrite or refactor the full script.
#    Only modify sections I explicitly request.
#
#  • When updating the entire script increment the script version .001 unless otherwise requested.
#
#  • Keep the script VERBOSE (IAC style):
#    preserve comments, logging, echoes, structure.
#
#  • Maintain compatibility with:
#    Bash 5+, Ubuntu/WSL2, llama.cpp master, OpenWebUI.
#
#  • Do NOT remove: safety checks, dependency installs,
#    GPU detection, systemd service creation.
#
#  • When adding code:
#      - use clear comments
#      - follow existing style/indentation
#      - use defensive scripting
#
#  • Do NOT change variables/paths/defaults unless I ask.
#
#  • Output must be DROP-IN SAFE:
#      no placeholders, no partial examples.
#
#  === PROMPT HANDLING ===
#  Assume I paste back a modified full script.
#  Integrate only requested changes.
#
#  === OUTPUT RULE ===
#  Only output the changed section(s),
#  unless I explicitly request the entire script.
# ============================================================

#!/usr/bin/env bash

set -e

###############################################
# CONFIGURATION
###############################################
MODEL_REPO="Qwen/Qwen2.5-Coder-7B-Instruct-GGUF"
MODEL_FILE="qwen2.5-coder-7b-instruct-q4_k_m.gguf"
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
apt install -y wget btop python3 python3-venv python3-pip git curl

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
# 4. Download Qwen 2.5-Coder 7B model (public, no login)
###############################################
echo "=== Creating model install directory ==="
mkdir -p "$MODEL_INSTALL_DIR"

echo "=== Downloading Qwen 2.5-Coder 7B GGUF model ==="
cd "$MODEL_INSTALL_DIR"

# Direct download of specific quantized model file
# Using Q4_K_M (balanced size/quality) - adjust quant level if needed
MODEL_URL="https://huggingface.co/$MODEL_REPO/resolve/main/$MODEL_FILE"

if [ -f "$MODEL_FILE" ]; then
    echo "✓ Model already exists: $MODEL_FILE"
else
    echo "Downloading $MODEL_FILE..."
    curl -L -o "$MODEL_FILE" "$MODEL_URL"
    
    if [ -f "$MODEL_FILE" ]; then
        echo "✓ Model downloaded successfully"
    else
        echo "✗ Download failed"
        exit 1
    fi
fi

echo "✓ Model ready at $MODEL_INSTALL_DIR/$MODEL_FILE"

###############################################
# 5. Completion message
###############################################
echo "=== Setup complete! ==="
echo "Close and reopen your WSL terminal to see Fastfetch on login."
echo "Qwen 2.5-Coder 7B model installed at $MODEL_INSTALL_DIR/$MODEL_FILE"
