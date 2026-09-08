#!/bin/bash

# ==============================================================================
# Orquestador EFÍMERO (Alta Velocidad): Motor ComfyUI para TESS / ValTech
# Arquitectura: SDXL + IP-Adapter Plus + ControlNet Advanced + OpenPose Editor
# Estrategia: Cero persistencia, instalación directa global, descargas paralelas
# ==============================================================================

set -e

echo "[1/6] Preparando contenedor para despliegue ultra-rápido..."
# Instalamos aria2c para descargas paralelas hiper-rápidas
apt-get update -qq && apt-get install -yqq aria2 git python3-pip

echo "[2/6] Clonando núcleo y dependencias base..."
git clone -q https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI_Studio
cd /workspace/ComfyUI_Studio

# Instalación directa, ignorando bloqueos del SO, ya que el contenedor morirá pronto
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 --break-system-packages -q
pip install -r requirements.txt --break-system-packages -q

echo "[3/6] Inyectando Nodos Personalizados..."
cd custom_nodes

git clone -q https://github.com/ltdrdata/ComfyUI-Manager.git
git clone -q https://github.com/cubiq/ComfyUI_IPAdapter_plus.git
git clone -q https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet.git
git clone -q https://github.com/hinablue/ComfyUI_3dPoseEditor.git

echo "[4/6] Resolviendo requerimientos de nodos..."
for dir in */ ; do
    if [ -f "$dir/requirements.txt" ]; then
        pip install -r "$dir/requirements.txt" --break-system-packages -q
    fi
done
cd ..

echo "[5/6] Acelerando descarga de tensores (Conexiones Paralelas 16x)..."
# Configuración global para aria2c
ARIA_OPT="-x 16 -s 16 -k 1M -q --allow-overwrite=true"

# Pre-creación de directorios
mkdir -p models/ipadapter models/clip_vision models/controlnet

# Descargamos todo en paralelo enviando los procesos a background (&)
echo "Descargando Juggernaut XL..."
aria2c $ARIA_OPT -d models/checkpoints -o juggernautXL_v11.safetensors "https://huggingface.co/RunDiffusion/Juggernaut-XL-v9/resolve/main/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors" &

echo "Descargando IP-Adapter..."
aria2c $ARIA_OPT -d models/ipadapter -o ip-adapter-plus_sdxl_vit-h.safetensors "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors" &

echo "Descargando CLIP Vision..."
aria2c $ARIA_OPT -d models/clip_vision -o CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" &

echo "Descargando ControlNet..."
aria2c $ARIA_OPT -d models/controlnet -o thibaud_xl_openpose.safetensors "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/thibaud_xl_openpose.safetensors" &

# Esperamos a que todas las descargas paralelas terminen antes de iniciar
wait
echo "Descargas completadas."

echo "[6/6] Inicializando Servidor ComfyUI (48GB VRAM Activa)..."
echo "El servidor estará en línea en un instante. Usa 'Connect to HTTP Service [Port 8188]'."
echo "=============================================================================="

# Ejecutamos directamente, reteniendo la VRAM
python3 main.py --highvram --disable-smart-memory --listen 0.0.0.0 --port 8188