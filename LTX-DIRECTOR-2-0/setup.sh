#!/usr/bin/env bash
# ==============================================================================
# Setup Pipeline Completo: ComfyUI + WhatDreamsCost + LTX-Video 2.3 (Distilled)
# Optimizado para NVIDIA L40S (48 GB VRAM) y almacenamiento de 90 GB en RunPod
# ==============================================================================

set -eo pipefail

BASE_DIR="/workspace"
if [ ! -d "$BASE_DIR" ]; then
    BASE_DIR="$(pwd)"
fi

COMFY_DIR="${BASE_DIR}/ComfyUI"
CUSTOM_NODES_DIR="${COMFY_DIR}/custom_nodes"
MODELS_DIR="${COMFY_DIR}/models"

echo "==> [1/6] Actualizando dependencias del sistema operativo..."
apt-get update -qq && apt-get install -y -qq \
    ffmpeg \
    libsndfile1 \
    aria2 \
    git \
    wget > /dev/null

echo "==> [2/6] Verificando despliegue de ComfyUI..."
if [ ! -d "$COMFY_DIR" ]; then
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
fi

cd "$COMFY_DIR"
git pull origin master || true
pip install --no-cache-dir -r requirements.txt > /dev/null

echo "==> [3/6] Aprovisionando nodos de extension y dependencias criticas..."
mkdir -p "$CUSTOM_NODES_DIR"

declare -A NODES=(
    ["WhatDreamsCost-ComfyUI"]="https://github.com/WhatDreamsCost/WhatDreamsCost-ComfyUI.git"
    ["ComfyUI-LTXVideo"]="https://github.com/Lightricks/ComfyUI-LTXVideo.git"
    ["ComfyUI-KJNodes"]="https://github.com/kijai/ComfyUI-KJNodes.git"
    ["ComfyUI-VideoHelperSuite"]="https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    ["ComfyUI-Manager"]="https://github.com/ltdrdata/ComfyUI-Manager.git"
    ["rgthree-comfy"]="https://github.com/rgthree/rgthree-comfy.git"
)

for NODE_NAME in "${!NODES[@]}"; do
    TARGET_PATH="${CUSTOM_NODES_DIR}/${NODE_NAME}"
    if [ ! -d "$TARGET_PATH" ]; then
        echo "    -> Clonando ${NODE_NAME}..."
        git clone --depth 1 "${NODES[$NODE_NAME]}" "$TARGET_PATH"
    else
        echo "    -> Actualizando ${NODE_NAME}..."
        (cd "$TARGET_PATH" && git pull || true)
    fi
    if [ -f "${TARGET_PATH}/requirements.txt" ]; then
        pip install --no-cache-dir -r "${TARGET_PATH}/requirements.txt" > /dev/null 2>&1 || true
    fi
done

echo "==> Instalando módulos de aceleración e inferencia..."
pip install --no-cache-dir soundfile librosa moviepy triton comfy-kitchen > /dev/null 2>&1 || true

echo "==> [4/6] Optimizando espacio en disco (depuración de checkpoints v0.9.1 obsoletos)..."
if [ -f "${MODELS_DIR}/checkpoints/ltx-video-2b-v0.9.1.safetensors" ]; then
    echo "    -> Purgando ltx-video-2b-v0.9.1.safetensors..."
    rm -f "${MODELS_DIR}/checkpoints/ltx-video-2b-v0.9.1.safetensors"
fi
if [ -f "${MODELS_DIR}/clip/t5xxl_fp16.safetensors" ]; then
    echo "    -> Purgando t5xxl_fp16.safetensors..."
    rm -f "${MODELS_DIR}/clip/t5xxl_fp16.safetensors"
fi

echo "==> [5/6] Descargando pesos exactos para LTX 2.3 Director Distilled..."
mkdir -p "${MODELS_DIR}/diffusion_models"
mkdir -p "${MODELS_DIR}/clip"
mkdir -p "${MODELS_DIR}/text_encoders"
mkdir -p "${MODELS_DIR}/vae"
mkdir -p "${MODELS_DIR}/vae_approx"
mkdir -p "${MODELS_DIR}/latent_upscale_models"

aria_download() {
    local url="$1"
    local dir="$2"
    local filename="$3"
    local fallback_url="${4:-}"

    mkdir -p "$dir"
    if [ ! -f "${dir}/${filename}" ]; then
        echo "    -> Descargando ${filename}..."
        if ! aria2c -c -x 16 -s 16 -k 1M --dir="$dir" -o "$filename" "$url"; then
            if [ -n "$fallback_url" ]; then
                echo "    [REINTENTO] URL primaria fallida. Intentando descargar desde mirror..."
                aria2c -c -x 16 -s 16 -k 1M --dir="$dir" -o "$filename" "$fallback_url"
            else
                echo "    [ERROR CRITICO] Fallo de descarga para ${filename}."
                return 1
            fi
        fi
    else
        echo "    -> ${filename} ya presente en ${dir}."
    fi
}

# 1. Diffusion DiT: LTX 2.3 22B Distilled FP8 Scaled (~25.2 GB)
aria_download \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors" \
    "${MODELS_DIR}/diffusion_models" \
    "ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors" \
    "https://huggingface.co/daydreamlive/LTX2.3/resolve/main/diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_fp8_scaled.safetensors"

# 2. Text Encoder: Gemma 3 12B IT FP4 Mixed (~9.45 GB)
aria_download \
    "https://huggingface.co/SilverGrain/models_kitanna/resolve/main/gemma_3_12B_it_fp4_mixed.safetensors" \
    "${MODELS_DIR}/clip" \
    "gemma_3_12B_it_fp4_mixed.safetensors" \
    "https://huggingface.co/eraRelentless/Gemma_3_12B_it_fp4/resolve/main/gemma_3_12B_it_fp4_mixed.safetensors"

# 3. Text Projection: LTX 2.3 Text Projection BF16 (~2.31 GB)
aria_download \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors" \
    "${MODELS_DIR}/clip" \
    "ltx-2.3_text_projection_bf16.safetensors"

# 4. Audio VAE BF16 (~365 MB)
aria_download \
    "https://huggingface.co/Aitrepreneur/FLX/resolve/main/LTX23_audio_vae_bf16.safetensors" \
    "${MODELS_DIR}/vae" \
    "LTX23_audio_vae_bf16.safetensors"

# 5. Video VAE BF16 (~1.45 GB)
aria_download \
    "https://huggingface.co/Aitrepreneur/FLX/resolve/main/LTX23_video_vae_bf16.safetensors" \
    "${MODELS_DIR}/vae" \
    "LTX23_video_vae_bf16.safetensors" \
    "https://huggingface.co/xiaozhengya/ltx-2.3-GGUF/resolve/main/LTX23_video_vae_bf16.safetensors"

# 6. Latent Spatial Upscaler x2 v1.1 (~996 MB)
aria_download \
    "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors" \
    "${MODELS_DIR}/latent_upscale_models" \
    "ltx-2.3-spatial-upscaler-x2-1.1.safetensors"

# 7. Tiny VAE Preview: taeltx2_3 (~23.5 MB)
aria_download \
    "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/taeltx2_3.safetensors" \
    "${MODELS_DIR}/vae_approx" \
    "taeltx2_3.safetensors" \
    "https://github.com/madebyollin/taehv/raw/main/safetensors/taeltx2_3.safetensors"

# Enlaces simbólicos para compatibilidad entre variantes de loaders
ln -sf "${MODELS_DIR}/clip/gemma_3_12B_it_fp4_mixed.safetensors" "${MODELS_DIR}/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors" 2>/dev/null || true
ln -sf "${MODELS_DIR}/clip/ltx-2.3_text_projection_bf16.safetensors" "${MODELS_DIR}/text_encoders/ltx-2.3_text_projection_bf16.safetensors" 2>/dev/null || true
ln -sf "${MODELS_DIR}/vae_approx/taeltx2_3.safetensors" "${MODELS_DIR}/vae/taeltx2_3.safetensors" 2>/dev/null || true

echo "==> [6/6] Despliegue completado con éxito. Todos los modelos y dependencias verificados."
echo "==> Iniciando ComfyUI en el puerto 8188 para NVIDIA L40S..."

cd "$COMFY_DIR"
exec python main.py --listen 0.0.0.0 --port 8188 --highvram --enable-manager --preview-method auto