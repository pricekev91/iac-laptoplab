#!/usr/bin/env bash
#
# 11-install-llama-cpp.sh — Version 0.1
# Author: Kevin Price
# Last Updated: 2025-11-20
#
# Purpose:
#   Build llama.cpp automatically (CPU or GPU), hands-off, WSL friendly.
#

LOG_DIR="/var/log/laptoplab"
LOG_FILE="$LOG_DIR/llama-cpp-install.log"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log() { echo "$(date +"%Y-%m-%d %H:%M:%S") [LLAMA-C++] $1" | tee -a "$LOG_FILE"; }

log "Starting llama.cpp installation..."

# Source GPU detection
if [[ -z "$GPU_TYPE" ]]; then
    if [[ -f "$(dirname "$0")/00-detect-gpu.sh" ]]; then
        log "Sourcing GPU detection script..."
        source "$(dirname "$0")/00-detect-gpu.sh"
    else
        log "WARNING: GPU detection script not found. Defaulting to CPU."
        GPU_TYPE="cpu"
        CUDA_AVAILABLE=false
    fi
fi

log "Detected GPU type: $GPU_TYPE"
log "CUDA available: $CUDA_AVAILABLE"

# Install required packages
log "Installing dependencies..."
sudo apt update -y >>"$LOG_FILE" 2>&1
sudo apt install -y build-essential cmake git python3 python3-pip wget curl libomp-dev pkg-config >>"$LOG_FILE" 2>&1

# Remove old llama.cpp
LLAMA_DIR="$HOME/llama.cpp"
if [[ -d "$LLAMA_DIR" ]]; then
    log "Removing existing llama.cpp directory..."
    rm -rf "$LLAMA_DIR"
fi

# Clone repository
log "Cloning llama.cpp repository..."
git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR" >>"$LOG_FILE" 2>&1
cd "$LLAMA_DIR" || { log "ERROR: Failed to enter llama.cpp directory"; exit 1; }

# Prepare CMake build
log "Preparing CMake build..."
mkdir -p build
cd build || { log "ERROR: Failed to enter build directory"; exit 1; }

# Set CMake flags
CMAKE_FLAGS="-DLLAMA_ENABLE_GPU=OFF"
if [[ "$GPU_TYPE" == "nvidia" && "$CUDA_AVAILABLE" == true ]]; then
    log "Configuring build for NVIDIA GPU with CUDA..."
    CMAKE_FLAGS="-DLLAMA_ENABLE_GPU=ON -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc"
elif [[ "$GPU_TYPE" == "intel" ]]; then
    log "Configuring build for CPU (Intel optimized)..."
elif [[ "$GPU_TYPE" == "amd" ]]; then
    log "Configuring build for CPU (AMD optimized)..."
else
    log "No GPU detected or CUDA unavailable. Building CPU-only version..."
fi

# Run CMake
log "Running CMake configure: cmake .. $CMAKE_FLAGS"
cmake .. $CMAKE_FLAGS >>"$LOG_FILE" 2>&1

# Build
log "Compiling llama.cpp..."
cmake --build . --config Release >>"$LOG_FILE" 2>&1

if [[ $? -eq 0 ]]; then
    log "llama.cpp built successfully."
else
    log "ERROR: Build failed. Check log $LOG_FILE"
    exit 1
fi

# Verify build
log "Verifying build..."
if ./main -h >>"$LOG_FILE" 2>&1; then
    log "llama.cpp main executable works."
else
    log "WARNING: main executable failed to run."
fi

log "llama.cpp installation completed."
