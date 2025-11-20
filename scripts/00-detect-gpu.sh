#!/usr/bin/env bash
#
# 00-detect-gpu.sh — Version 0.1
# Author: Kevin Price
# Last Updated: 2025-11-20
#
# Purpose:
#   Automatically detect GPU type and CUDA availability.
#   Sets and exports:
#     GPU_TYPE       = "nvidia", "intel", "amd", or "cpu"
#     CUDA_AVAILABLE = true/false
#     WSL_DETECTED   = true/false
#

GPU_TYPE="cpu"
CUDA_AVAILABLE=false
WSL_DETECTED=false

# Detect NVIDIA GPU
if command -v nvidia-smi >/dev/null 2>&1; then
    if [[ $(nvidia-smi -L 2>/dev/null | wc -l) -gt 0 ]]; then
        GPU_TYPE="nvidia"
        # Check for CUDA compiler
        if command -v nvcc >/dev/null 2>&1; then
            CUDA_AVAILABLE=true
        fi
    fi
fi

# Detect Intel GPU
if [[ "$GPU_TYPE" == "cpu" ]] && command -v lspci >/dev/null 2>&1; then
    lspci | grep -iq 'intel.*graphics' && GPU_TYPE="intel"
fi

# Detect AMD GPU
if [[ "$GPU_TYPE" == "cpu" ]] && command -v lspci >/dev/null 2>&1; then
    lspci | grep -iqE 'amd.*vga|radeon|vega' && GPU_TYPE="amd"
fi

# Detect WSL
grep -qi microsoft /proc/version 2>/dev/null && WSL_DETECTED=true

# Print summary
echo "-------------------------------------"
echo "[GPU-DETECT] GPU detection complete:"
echo "[GPU-DETECT]   GPU_TYPE:       $GPU_TYPE"
echo "[GPU-DETECT]   CUDA_AVAILABLE: $CUDA_AVAILABLE"
echo "[GPU-DETECT]   WSL_DETECTED:   $WSL_DETECTED"
echo "-------------------------------------"

# Export variables
export GPU_TYPE CUDA_AVAILABLE WSL_DETECTED
