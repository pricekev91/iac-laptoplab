#!/usr/bin/env bash
# 00-detect-gpu.sh — v0.2
# Detects available GPU type and prints result for use by installer scripts.
# Updated to assume installation and runtime location under /opt.

set -euo pipefail

SCRIPT_DIR="/opt/ai-setup"
LOG_FILE="${SCRIPT_DIR}/gpu-detect.log"

mkdir -p "$SCRIPT_DIR"
touch "$LOG_FILE"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')  $*" | tee -a "$LOG_FILE"
}

log "=== GPU Detection Script v0.2 Starting ==="

# Detect NVIDIA
if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi >/dev/null 2>&1; then
        log "Detected NVIDIA GPU via nvidia-smi."
        echo "nvidia"
        exit 0
    fi
fi

# Detect AMD ROCm
if command -v rocminfo >/dev/null 2>&1; then
    if rocminfo >/dev/null 2>&1; then
        log "Detected AMD GPU via rocminfo."
        echo "amd"
        exit 0
    fi
fi

# Detect Intel iGPU (via lspci)
if command -v lspci >/dev/null 2>&1; then
    if lspci | grep -i 'vga' | grep -qi 'intel'; then
        log "Detected Intel integrated GPU via lspci."
        echo "intel"
        exit 0
    fi
fi

# No GPU
log "No supported GPU detected."
echo "cpu"
exit 0
