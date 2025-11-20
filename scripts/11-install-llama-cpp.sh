#!/usr/bin/env bash
#
# 11-install-llama-cpp.sh — Version 0.33
# Author: Kevin Price
# Last Updated: 2025-11-20
#
# Purpose:
#   Install llama.cpp to /opt/llama.cpp with CPU/GPU detection and automatic build.
#   Logs to /opt/llama-cpp-install.log
#

INSTALL_DIR="/opt/llama.cpp"
LOG_FILE="/opt/llama-cpp-install.log"

# Ensure log file exists
sudo touch "$LOG_FILE"
sudo chown $(whoami):$(whoami) "$LOG_FILE"

log() { echo "$(date +"%Y-%m-%d %H:%M:%S") [LLAMA-C++] $1" | tee -a "$LOG_FILE"; }

log "Starting llama.cpp installation..."

# Source GPU detection
if [[ -f "$(dirname "$0")/00-detect-gpu.sh" ]]; then
    log "Sourcing GPU detection script..."
    source "$(dirname "$0")/00-detect-gpu.sh"
else
    log "WARNING: GPU detection script missing. Defaulting to CPU."
    GPU_TYPE="cpu"
    CUDA_AVAILABLE=false
fi

log "Detected GPU type: $GPU_TYPE"
log "CUDA available: $CUDA_AVAILABLE"

# Install required packages
log "Installing required packages..."
sudo apt update
sudo apt install -y build-essential cmake git python3 python3-pip wget curl libomp-dev pkg-config >>"$LOG_FILE" 2>&1

# Remove old install if exists
if [[ -d "$INSTALL_DIR" ]]; then
    log "Removing existing llama.cpp installation..."
    sudo rm -rf "$INSTALL_DIR"
fi

# Recreate install directory
log "Creating installation directory..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown -R $(whoami):$(whoami) "$INSTALL_DIR"

# Clone llama.cpp
log "Cloning llama.cpp repository to $INSTALL_DIR..."
git clone https://github.com/ggerganov/llama.cpp.git "$INSTALL_DIR" >>"$LOG_FILE" 2>&1
cd "$INSTALL_DIR" || { log "ERROR: Failed to cd into $INSTALL_DIR"; exit 1; }

# Prepare build
log "Preparing CMake build..."
mkdir -p build
cd build || { log "ERROR: Failed to cd into build directory"; exit 1; }

CMAKE_FLAGS="-DLLAMA_ENABLE_GPU=OFF -DLLAMA_CURL=OFF"

if [[ "$GPU_TYPE" == "nvidia" && "$CUDA_AVAILABLE" == true ]]; then
    log "Building llama.cpp with CUDA support..."
    CMAKE_FLAGS="-DLLAMA_ENABLE_GPU=ON -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DLLAMA_CURL=OFF"
else
    log "No GPU detected or CUDA unavailable. Building CPU-only version..."
fi

log "Running CMake configure: cmake .. $CMAKE_FLAGS"
cmake .. $CMAKE_FLAGS >>"$LOG_FILE" 2>&1

log "Compiling llama.cpp..."
cmake --build . --config Release >>"$LOG_FILE" 2>&1

if [[ $? -eq 0 ]]; then
    log "llama.cpp built successfully."
else
    log "ERROR: Build failed. Check log $LOG_FILE."
    exit 1
fi

# Verify
log "Verifying build..."
if [[ -x "$INSTALL_DIR/build/main" ]]; then
    log "Build verification successful. Executable exists."
else
    log "WARNING: main executable not found or not runnable."
fi

log "llama.cpp installation completed."
