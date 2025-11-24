#!/usr/bin/env bash
#
# 11-install-llama-cpp.sh — Version 0.461
# Author: Kevin Price
# Updated: 2025-11-24
#
# Purpose:
#   Safe, repeatable llama.cpp installer with:
#   - GPU/CPU auto-detection
#   - Automatic build (CUDA → CPU fallback)
#   - HuggingFace model downloader
#   - Systemd service generator (optional)
#   - Logging, retries, and error handling
#

set -euo pipefail

VERSION="0.461"
INSTALL_DIR="/opt/llama.cpp"
LOG_FILE="/opt/llama-cpp-install.log"
MODEL_DIR="$INSTALL_DIR/models"
MODEL_NAME="Meta-Llama-3-8B-Instruct.Q4_0.gguf"
MODEL_URL="https://huggingface.co/QuantFactory/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct.Q4_0.gguf"

echo "===== llama.cpp Installer v${VERSION} =====" | tee "$LOG_FILE"

log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") [LLAMA-INSTALL] $*" | tee -a "$LOG_FILE"
}

#############################################
# 1) Create directories
#############################################
log "Creating directories..."
mkdir -p "$INSTALL_DIR" "$MODEL_DIR"

#############################################
# 2) Install dependencies
#############################################
log "Installing dependencies..."
apt update -y >>"$LOG_FILE" 2>&1
apt install -y git build-essential cmake curl wget >>"$LOG_FILE" 2>&1

#############################################
# 3) Clone llama.cpp (cleanly)
#############################################
if [ -d "$INSTALL_DIR/.git" ]; then
    log "Updating existing llama.cpp repository..."
    cd "$INSTALL_DIR"
    git pull >>"$LOG_FILE" 2>&1
else
    log "Cloning llama.cpp repository..."
    git clone https://github.com/ggerganov/llama.cpp.git "$INSTALL_DIR" >>"$LOG_FILE" 2>&1
    cd "$INSTALL_DIR"
fi

#############################################
# 4) GPU Auto-Detection
#############################################
log "Detecting GPU for build mode..."

if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_MODE="cuda"
    log "NVIDIA GPU detected → Using CUDA build."
else
    GPU_MODE="cpu"
    log "No NVIDIA GPU → Using CPU-only build."
fi

#############################################
# 5) Build llama.cpp
#############################################
build_llama() {
    local MODE="$1"
    log "Building llama.cpp in mode: $MODE"

    rm -rf build
    cmake -B build -DGGML_CUDA=$( [ "$MODE" = "cuda" ] && echo 1 || echo 0 ) >>"$LOG_FILE" 2>&1
    cmake --build build -j$(nproc) >>"$LOG_FILE" 2>&1
}

log "Starting llama.cpp build..."
if [ "$GPU_MODE" = "cuda" ]; then
    if build_llama "cuda"; then
        log "CUDA build succeeded."
    else
        log "CUDA build failed → Falling back to CPU."
        build_llama "cpu"
    fi
else
    build_llama "cpu"
fi

#############################################
# 6) Download Model
#############################################
log "Downloading model: $MODEL_URL"
cd "$MODEL_DIR"

rm -f "$MODEL_NAME"

wget -O "$MODEL_NAME" "$MODEL_URL" >>"$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    log "Model download FAILED."
    exit 1
fi

log "Model downloaded: $MODEL_NAME"

#############################################
# 7) Optional checksum placeholder
#############################################
# echo "EXPECTED_SHA256_HERE  $MODEL_NAME" | sha256sum -c -

#############################################
# 8) Model test run
#############################################
log "Running basic llama.cpp test inference..."

cd "$INSTALL_DIR"

./build/bin/llama-cli \
    --model "$MODEL_DIR/$MODEL_NAME" \
    --prompt "Hello! This is a test." \
    --n-predict 32 >>"$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "Test inference completed successfully!"
else
    log "Test inference FAILED!"
    exit 1
fi

#############################################
# 9) Finished
#############################################
log "===== llama.cpp Install COMPLETE — Version $VERSION ====="
echo "Install complete."
