#!/usr/bin/env bash
# ============================================================
#  WSL2 AI Appliance Installer — v0.52
#  Author: Kevin Price — 2025-11-24
#
#  === AI-EDITING RULES (READ BEFORE CHANGES) ===
#
#  • Do NOT rewrite or refactor the full script.
#    Only modify sections I explicitly request.
#
#  • When update the entire script increment the script version .001 unless otherwise requested.
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

set -e

SCRIPT_VERSION="0.52"
INSTALL_DIR="/srv/ai"
LLAMA_DIR="${INSTALL_DIR}/llama.cpp"
MODEL_DIR="${INSTALL_DIR}/models"
OPENWEBUI_DIR="${INSTALL_DIR}/openwebui"
MODEL_URL="https://huggingface.co/QuantFactory/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct.Q4_0.gguf"
MODEL_FILE="Meta-Llama-3-8B-Instruct.Q4_0.gguf"

echo "============================================================"
echo "WSL2 AI Appliance Installer v${SCRIPT_VERSION}"
echo "CUDA-accelerated llama.cpp + OpenWebUI + API + Switcher"
echo "============================================================"
echo ""

###############################################
# Root check
###############################################
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Must run as root. Use: sudo bash $0"
    exit 1
fi

###############################################
# Install system dependencies
###############################################
echo "=== Installing system packages ==="
apt-get update
apt-get install -y \
    git cmake build-essential \
    python3 python3-pip python3-venv python3-full \
    curl wget unzip \
    libcurl4-openssl-dev pkg-config

###############################################
# Install CUDA runtime for GPU acceleration
###############################################
echo "=== Checking for NVIDIA GPU ==="
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv || true
    echo "✓ NVIDIA GPU detected"
    
    if ! command -v nvcc >/dev/null 2>&1; then
        echo "=== Installing CUDA runtime ==="
        wget -q https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.1-1_all.deb
        dpkg -i cuda-keyring_1.1-1_all.deb
        apt-get update
        apt-get install -y cuda-nvcc-12-6 cuda-cudart-dev-12-6 libcublas-12-6 libcublas-dev-12-6
        
        export PATH=/usr/local/cuda/bin:$PATH
        export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        
        echo "✓ CUDA runtime installed"
    else
        echo "✓ CUDA already installed"
    fi
else
    echo "⚠ No NVIDIA GPU detected - CPU-only build"
fi

###############################################
# Prepare directories
###############################################
echo "=== Setting up directories ==="
mkdir -p "${INSTALL_DIR}" "${MODEL_DIR}" "${OPENWEBUI_DIR}"

###############################################
# Clone/update llama.cpp with API/server support
###############################################
echo "=== Syncing llama.cpp (API/server support) ==="
if [ ! -d "${LLAMA_DIR}" ]; then
    git clone --branch master https://github.com/ggerganov/llama.cpp.git "${LLAMA_DIR}"
else
    cd "${LLAMA_DIR}"
    git fetch origin
    git checkout master
    git pull --rebase origin master
fi

###############################################
# Build llama.cpp with CUDA
###############################################
echo "=== Building llama.cpp with CUDA ==="
cd "${LLAMA_DIR}"
rm -rf build
mkdir -p build
cd build

if command -v nvcc >/dev/null 2>&1; then
    echo "Building with CUDA support..."
    cmake .. -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
else
    echo "Building CPU-only version..."
    cmake .. -DCMAKE_BUILD_TYPE=Release
fi

make -j"$(nproc)"
echo "✓ llama.cpp build complete"

# Create symlinks
ln -sf "${LLAMA_DIR}/build/bin/llama-server" /usr/local/bin/llama-server
ln -sf "${LLAMA_DIR}/build/bin/llama-cli" /usr/local/bin/llama-cli

###############################################
# Download model
###############################################
echo "=== Checking model ==="
cd "${MODEL_DIR}"

if [ ! -f "${MODEL_FILE}" ]; then
    echo "Downloading model (this may take a while)..."
    curl -L --progress-bar -o "${MODEL_FILE}" "${MODEL_URL}"
    echo "✓ Model downloaded"
else
    echo "✓ Model already exists: ${MODEL_FILE}"
fi

###############################################
# Install OpenWebUI in venv
###############################################
echo "=== Installing OpenWebUI ==="
cd "${OPENWEBUI_DIR}"

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate
pip install --upgrade pip
pip install open-webui
deactivate

echo "✓ OpenWebUI installed"

###############################################
# Create systemd services
###############################################
echo "=== Creating systemd services ==="

# llama-server service with API support
cat > /etc/systemd/system/llama-server.service <<EOF
[Unit]
Description=Llama.cpp Server (CUDA-accelerated with OpenAI API)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/llama-server \\
    --model ${MODEL_DIR}/${MODEL_FILE} \\
    --host 0.0.0.0 \\
    --port 8081 \\
    --api \\
    --chat-template qwen2 \\
    --n-gpu-layers 50
Restart=always
RestartSec=3
WorkingDirectory=${MODEL_DIR}

[Install]
WantedBy=multi-user.target
EOF

# OpenWebUI service
cat > /etc/systemd/system/openwebui.service <<EOF
[Unit]
Description=OpenWebUI
After=network.target llama-server.service
Requires=llama-server.service

[Service]
Type=simple
WorkingDirectory=${OPENWEBUI_DIR}
ExecStart=${OPENWEBUI_DIR}/venv/bin/open-webui serve \\
    --host 0.0.0.0 \\
    --port 8080
Environment="OPENAI_API_BASE_URL=http://localhost:8081/v1"
Environment="OPENAI_API_KEY=dummy"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable llama-server.service openwebui.service

###############################################
# Create model switcher script and symlink
###############################################
echo "=== Creating model switcher script ==="

cat > /usr/local/bin/switch-model.sh <<'EOF'
#!/bin/bash

# Configuration
MODELS_DIR="/srv/ai/models"
SERVICE_FILE="/etc/systemd/system/llama-server.service"
SERVICE_NAME="llama-server.service"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Llama Server Model Switcher ===${NC}\n"

# Check if models directory exists
if [ ! -d "$MODELS_DIR" ]; then
    echo -e "${RED}Error: Models directory not found: $MODELS_DIR${NC}"
    exit 1
fi

# Find all .gguf files and sort by modification time (newest first)
mapfile -t models < <(find "$MODELS_DIR" -maxdepth 1 -type f -name "*.gguf" -printf "%T@ %p\n" | sort -rn | cut -d' ' -f2-)

# Check if any models were found
if [ ${#models[@]} -eq 0 ]; then
    echo -e "${RED}Error: No .gguf model files found in $MODELS_DIR${NC}"
    exit 1
fi

# Display models with numbers
echo -e "${GREEN}Available models (newest to oldest):${NC}\n"
for i in "${!models[@]}"; do
    model_name=$(basename "${models[$i]}")
    mod_time=$(stat -c "%y" "${models[$i]}" | cut -d'.' -f1)
    echo -e "${YELLOW}$((i+1)).${NC} $model_name"
    echo -e "   Modified: $mod_time"
    echo
done

# Get user selection
while true; do
    read -p "Select model number (1-${#models[@]}): " selection

    # Validate input
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#models[@]} ]; then
        break
    else
        echo -e "${RED}Invalid selection. Please enter a number between 1 and ${#models[@]}${NC}"
    fi
done

# Get selected model path
selected_model="${models[$((selection-1))]}"
echo -e "\n${GREEN}Selected model:${NC} $(basename "$selected_model")"

# Backup service file
if [ -f "$SERVICE_FILE" ]; then
    cp "$SERVICE_FILE" "${SERVICE_FILE}.bak"
    echo -e "${GREEN}Backup created:${NC} ${SERVICE_FILE}.bak"
else
    echo -e "${RED}Warning: Service file not found: $SERVICE_FILE${NC}"
    exit 1
fi

# Update service file with new model path
sed -i "s|--model .*/.*\.gguf|--model $selected_model|g" "$SERVICE_FILE"
echo -e "${GREEN}Service file updated${NC}"

# Reload systemd daemon
echo -e "\n${BLUE}Reloading systemd daemon...${NC}"
systemctl daemon-reload

# Restart service
echo -e "${BLUE}Restarting $SERVICE_NAME...${NC}"
systemctl restart "$SERVICE_NAME"

# Check service status
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "\n${GREEN}✓ Service restarted successfully!${NC}"
    echo -e "${GREEN}✓ Now using model:${NC} $(basename "$selected_model")"
else
    echo -e "\n${RED}✗ Service failed to start. Check status with: systemctl status $SERVICE_NAME${NC}"
    exit 1
fi

echo -e "\n${BLUE}Done!${NC}"
EOF

chmod +x /usr/local/bin/switch-model.sh
ln -sf /usr/local/bin/switch-model.sh /usr/local/bin/switch
echo "✓ Model switcher script created and symlinked as 'switch'"

###############################################
# Start services
###############################################
echo "=== Starting services ==="
systemctl start llama-server.service
systemctl start openwebui.service

# Wait a moment for services to start
sleep 3

echo ""
echo "============================================================"
echo "Installation Complete! v${SCRIPT_VERSION}"
echo "============================================================"
echo ""
echo "Services Status:"
systemctl status llama-server.service --no-pager -l || true
echo ""
systemctl status openwebui.service --no-pager -l || true
echo ""
echo "Access OpenWebUI at: http://localhost:8080"
echo "Llama API endpoint:  http://localhost:8081"
echo ""
echo "Model: ${MODEL_DIR}/${MODEL_FILE}"
echo "Logs: journalctl -u llama-server -f"
echo "      journalctl -u openwebui -f"
echo "============================================================"
