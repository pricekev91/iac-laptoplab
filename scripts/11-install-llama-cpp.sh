#!/usr/bin/env bash
#
# 11-install-llama-cpp.sh — Version 0.3.1
# Author: Kevin Price
# Last Updated: 2025-11-20
#
# Purpose:
#   Install and build llama.cpp in /opt/llama.cpp for CPU or GPU.
#   Fully automated: detects GPU, falls back to CPU, installs dependencies,
#   builds with CMake, and verifies the main executable.
#
# Changelog:
#   v0.3.1 — Fixed folder creation, logging, hands-off installation.

INSTALL_DIR="/opt/llama.cpp"
LOG_DIR="$INSTALL_DIR/logs"
LOG_FILE="$LOG_DIR/llama-cpp-install.log"

# Ensure install directory exists and is writable
sudo mkdir -p "$INSTALL_DIR"
sudo chown $(whoami):$(whoami) "$INSTALL_DIR"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log() { echo "$(date +"%Y-%m-%d %H:%M:%S") [LLAMA-C++] $1" | tee -a "$LOG_FILE"; }

log "Starting llama.cpp installation..."

# Source GPU detection if not already sourced
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
log "Installing required packages..."
sudo apt update
sudo apt install -y build-essential cmake git python3 python3-pip wget curl libomp-dev pkg-config >>"$LOG_FILE" 2>&1

# Remove existing llama.cpp folder if present
if [[ -d "$INSTALL_DIR" ]]; then
    log "Removing existing llama.cpp installation..."
    rm -rf "$INSTALL_DIR"/*
fi

# Clone repository
log "Cloning llama.cpp repository to $INSTALL_DIR..."
git clone https://github.com/ggerganov/llama.cpp.git "$INSTALL_DIR" >>"$LOG_FILE" 2>&1
cd "$INSTALL_DIR" || { log "ERROR: Failed to cd into $INSTALL_DIR"; exit 1; }

# Prepare CMake build
log "Preparing CMake build..."
mkdir -p build
cd build || { log "ERROR: Failed to cd into build directory"; exit 1; }

CMAKE_FLAGS="-DLLAMA_ENABLE_GPU=OFF"

if [[ "$GPU_TYPE" == "nvidia" && "$CUDA_AVAILABLE" == true ]]; then
    log "Building llama.cpp with CUDA support..."
    CMAKE_FLAGS="-DLLAMA_ENABLE_GPU=ON -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc"
elif [[ "$GPU_TYPE" == "intel" ]]; then
    log "Building llama.cpp for CPU (Intel optimized)..."
elif [[ "$GPU_TYPE" == "amd" ]]; then
    log "Building llama.cpp for CPU (AMD optimized)..."
else
    log "No GPU detected or CUDA unavailable. Building CPU-only version..."
fi

# Optional: disable CURL to prevent missing lib errors
CMAKE_FLAGS="$CMAKE_FLAGS -DLLAMA_CURL=OFF"

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

# Verify main executable
log "Verifying build..."
if ./main -h >>"$LOG_FILE" 2>&1; then
    log "llama.cpp main executable works."
else
    log "WARNING: main executable failed. Attempting to fix..."
    chmod +x ./main
    if ./main -h >>"$LOG_FILE" 2>&1; then
        log "llama.cpp main executable fixed."
    else
        log "ERROR: main executable still fails."
    fi
fi

log "llama.cpp installation completed at $INSTALL_DIR"
