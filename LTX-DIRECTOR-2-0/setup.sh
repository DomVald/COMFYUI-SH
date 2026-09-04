#!/usr/bin/env bash
# ==============================================================================
# Setup Pipeline Automatizado: ComfyUI + WhatDreamsCost + LTX-Video en RunPod
# Arquitectura: NVIDIA Ada Lovelace / L40S
# ==============================================================================

set -eo pipefail

BASE_DIR="/workspace"
if [ ! -d "$BASE_DIR" ]; then
    BASE_DIR="$(pwd)"
fi

COMFY_DIR="${BASE_DIR}/ComfyUI"
CUSTOM_NODES_DIR="${COMFY_DIR}/custom_nodes"
MODELS_DIR="${COMFY_DIR}/models"

echo "==> [1/5] Actualizando dependencias del sistema operativo..."
apt-get update -qq && apt-get install -y -qq \
    ffmpeg \
    libsndfile1 \
    aria2 \
    git \
    wget > /dev/null

echo "==> [2/5] Desplegando repositorio central de ComfyUI..."
if [ ! -d "$COMFY_DIR" ]; then
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
fi

cd "$COMFY_DIR"
pip install --no-cache-dir -r requirements.txt > /dev/null

echo "==> [3/5] Clonando nodos de extension de WhatDreamsCost y dependencias..."
mkdir -p "$CUSTOM_NODES_DIR"

declare -A NODES=(
    ["WhatDreamsCost-ComfyUI"]="https://github.com/WhatDreamsCost/WhatDreamsCost-ComfyUI.git"
    ["ComfyUI-LTXVideo"]="https://github.com/Lightricks/ComfyUI-LTXVideo.git"
    ["ComfyUI-KJNodes"]="https://github.com/kijai/ComfyUI-KJNodes.git"
    ["ComfyUI-VideoHelperSuite"]="https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    ["ComfyUI-Manager"]="https://github.com/ltdrdata/ComfyUI-Manager.git"
)

for NODE_NAME in "${!NODES[@]}"; do
    TARGET_PATH="${CUSTOM_NODES_DIR}/${NODE_NAME}"
    if [ ! -d "$TARGET_PATH" ]; then
        echo "    -> Instalando ${NODE_NAME}..."
        git clone --depth 1 "${NODES[$NODE_NAME]}" "$TARGET_PATH"
    fi
    if [ -f "${TARGET_PATH}/requirements.txt" ]; then
        pip install --no-cache-dir -r "${TARGET_PATH}/requirements.txt" > /dev/null 2>&1 || true
    fi
done

pip install --no-cache-dir soundfile librosa moviepy triton > /dev/null

echo "==> [4/5] Descargando pesos requeridos (LTX-Video 2B & T5-XXL FP16)..."
mkdir -p "${MODELS_DIR}/checkpoints"
mkdir -p "${MODELS_DIR}/clip"

aria_download() {
    local url="$1"
    local dir="$2"
    local filename="$3"
    if [ ! -f "${dir}/${filename}" ]; then
        echo "    -> Descargando ${filename}..."
        aria2c -c -x 16 -s 16 -k 1M --dir="$dir" -o "$filename" "$url" || {
            echo "    [ADVERTENCIA] Fallo al transferir ${filename}. Continuando..."
            return 0
        }
    else
        echo "    -> ${filename} ya se encuentra presente."
    fi
}

# 1. Checkpoint LTX-Video 2B oficial
aria_download \
    "https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltx-video-2b-v0.9.1.safetensors" \
    "${MODELS_DIR}/checkpoints" \
    "ltx-video-2b-v0.9.1.safetensors"

# 2. Text Encoder T5-XXL (FP16 para maximo rendimiento en 48GB VRAM)
aria_download \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors" \
    "${MODELS_DIR}/clip" \
    "t5xxl_fp16.safetensors"

echo "==> [5/5] Pipeline aprovisionado correctamente."
echo "==> Levantando servicio ComfyUI en el puerto 8188..."

cd "$COMFY_DIR"
exec python main.py --listen 0.0.0.0 --port 8188 --highvram --preview-method auto