#!/usr/bin/env bash
#
# 11-install-llama-cpp-v0.46.sh — Laptop-only bootstrap
# Author: Kevin Price
# Last Updated: 2025-11-24
#
# Purpose:
#   - Build llama.cpp for GPU (RTX 2060M)
#   - Prompt user to recompile if existing binary is present
#   - Download Meta-Llama-3-8B.gguf public model
#   - Minimal dependencies, no CLI hacks

set -e

INSTALL_DIR="/opt/llama.cpp"
MODEL_DIR="/srv/ai/models"
MODEL_FILE="Meta-Llama-3-8B.gguf"

echo "=== Llama.cpp Bootstrap v0.46 ==="

# 1️⃣ Check if llama.cpp binary exists and prompt for recompile
if [[ -f "$INSTALL_DIR/build/bin/llama" ]]; then
    BIN_DATE=$(stat -c %y "$INSTALL_DIR/build/bin/llama")
    echo "Compiled llama binary found: $BIN_DATE"
    read -rp "Do you want to recompile? [y/N]: " RECOMPILE
    RECOMPILE=${RECOMPILE:-N}
else
    RECOMPILE="Y"
fi

if [[ "$RECOMPILE" =~ ^[Yy]$ ]]; then
    echo "=== Building llama.cpp (GPU) ==="
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    if [[ ! -d ".git" ]]; then
        git clone https://github.com/ggerganov/llama.cpp.git .
    else
        git pull
    fi

    mkdir -p build && cd build
    cmake .. -DLLAMA_CUBLAS=ON
    cmake --build . --parallel
    echo "=== llama.cpp build complete ==="
fi

# 2️⃣ Ensure model directory exists
mkdir -p "$MODEL_DIR"

# 3️⃣ Download model using Python HuggingFace API
if [[ ! -f "$MODEL_DIR/$MODEL_FILE" ]]; then
    echo "=== Downloading public model: $MODEL_FILE ==="
    python3 - <<EOF
from huggingface_hub import hf_hub_download

MODEL_DIR = "$MODEL_DIR"
MODEL_FILE = "$MODEL_FILE"

hf_hub_download(
    repo_id="meta-llama/Meta-Llama-3-8B",
    filename=MODEL_FILE,
    cache_dir=MODEL_DIR,
    local_files_only=False,
    use_auth_token=None
)

print(f"Downloaded {MODEL_FILE} to {MODEL_DIR}")
EOF
else
    echo "Model $MODEL_FILE already exists. Skipping download."
fi

echo "=== Bootstrap Complete ==="
echo "llama.cpp binary location: $INSTALL_DIR/build/bin/"
echo "Model location: $MODEL_DIR/$MODEL_FILE"
echo "You can now run llama.cpp using GPU"
