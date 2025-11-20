#!/usr/bin/env bash
#
# 11-install-llama-cpp.sh — Version 0.2
# Author: Kevin Price
# Last Updated: 2025-11-20
#
# Purpose:
#   Install llama.cpp automatically using GPU detection results
#   from 00-detect-gpu.sh. Builds CUDA version if possible,
#   otherwise falls back to CPU-only.
#

set -euo pipefail

LOG_DIR="/var/log/laptoplab"
LOG_FILE="${LOG_DIR}/llama-cpp-install.log"
INSTALL_DIR="/srv/llama.cpp"

mkdir -p "$LOG_DIR"
mkdir -p "$INSTALL_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [LLAMA-C++] $1" | tee -a "$LOG_FILE"
}

# ---------------------------
# BEGIN INSTALLATION
# ---------------------------

log "Starting llama.cpp installation..."
log "Sourcing GPU detection script..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-detect-gpu.sh"

log "Detected GPU type: $GPU_TYPE"
log "CUDA available: $CUDA_AVAILABLE"

# ---------------------------
# Install dependencies
# ---------------------------

log "Installing dependencies..."

apt update -y >> "$LOG_FILE" 2>&1
apt install -y \
    build-essential \
    cmake \
    git \
    libcurl4-openssl-dev \
    pkg-config \
    unzip >> "$LOG_FILE" 2>&1

log "Dependencies installed."

# ---------------------------
# Clone llama.cpp
# ---------------------------

if [[ ! -d "${INSTALL_DIR}/llama.cpp" ]]; then
    log "Cloning llama.cpp repository..."
    git clone https://github.com/ggerganov/llama.cpp.git "${INSTALL_DIR}/llama.cpp" >> "$LOG_FILE" 2>&1
else
    log "llama.cpp already exists — pulling latest changes..."
    git -C "${INSTALL_DIR}/llama.cpp" pull >> "$LOG_FILE" 2>&1
fi

# ---------------------------
# Prepare build folder
# ---------------------------

log "Preparing CMake build..."

cd "${INSTALL_DIR}/llama.cpp"
rm -rf build
mkdir build
cd build

# ---------------------------
# Configure CMake
# ---------------------------

if [[ "$GPU_TYPE" == "nvidia" && "$CUDA_AVAILABLE" == true ]]; then
    log "Building with CUDA GPU support..."
    CMAKE_OPTS="-DLLAMA_CUDA=ON"
else
    log "No GPU detected or CUDA unavailable. Building CPU-only version..."
    CMAKE_OPTS="-DLLAMA_CUDA=OFF"
fi

log "Running CMake configure: cmake .. $CMAKE_OPTS"

if ! cmake .. $CMAKE_OPTS >> "$LOG_FILE" 2>&1; then
    log "ERROR: CMake configuration failed. See $LOG_FILE"
    exit 1
fi

# ---------------------------
# Compile llama.cpp
# ---------------------------

log "Compiling llama.cpp..."

if ! cmake --build . -j"$(nproc)" >> "$LOG_FILE" 2>&1; then
    log "ERROR: Build failed. See $LOG_FILE"
    exit 1
fi

log "llama.cpp build completed successfully!"
log "Binary located at: ${INSTALL_DIR}/llama.cpp/build/bin/llama-cli"
log "Installation finished."
