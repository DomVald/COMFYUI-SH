#!/bin/bash

# ==============================================================================
# Orquestador de Despliegue Zero-Touch: Motor ComfyUI para TESS / ValTech
# Arquitectura: SDXL + IP-Adapter Plus + ControlNet Advanced + PoseX
# Optimizado para: RunPod (48GB VRAM / 50GB RAM)
# ==============================================================================

set -e # Detiene la ejecución inmediatamente si ocurre un error

echo "[0/7] Verificando entorno de persistencia (RunPod)..."
if [ -d "/workspace" ]; then
    cd /workspace
    echo "Directorio /workspace detectado. Navegando al volumen persistente..."
else
    echo "ADVERTENCIA: /workspace no encontrado. Instalando en el directorio actual ($(pwd))."
fi

echo "[1/7] Inicializando variables y definiendo estructura de directorios..."
BASE_DIR="ComfyUI_Studio"
git clone https://github.com/comfyanonymous/ComfyUI.git $BASE_DIR
cd $BASE_DIR

echo "[2/7] Configurando el Entorno Virtual (Python venv)..."
python3 -m venv venv
source venv/bin/activate

echo "[3/7] Instalando PyTorch (Optimizacion CUDA 12.x) y dependencias base..."
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
pip install -r requirements.txt

echo "[4/7] Clonando Nodos Personalizados (Custom Nodes)..."
cd custom_nodes

git clone https://github.com/ltdrdata/ComfyUI-Manager.git
git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git
git clone https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet.git
git clone https://github.com/hnmr293/comfyui-posex.git

echo "[5/7] Instalando dependencias de los Nodos Personalizados..."
for dir in */ ; do
    if [ -f "$dir/requirements.txt" ]; then
        echo "Instalando requerimientos para $dir..."
        pip install -r "$dir/requirements.txt"
    fi
done

cd .. # Regreso a la raíz de ComfyUI_Studio

echo "[6/7] Descargando Modelos Fundacionales y Tensores de Control..."
WGET_OPT="-c -q --show-progress"

echo "Descargando Juggernaut XL..."
wget $WGET_OPT -O models/checkpoints/juggernautXL_v11.safetensors "https://huggingface.co/RunDiffusion/Juggernaut-XL-v9/resolve/main/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors"

echo "Descargando IP-Adapter Plus SDXL..."
mkdir -p models/ipadapter
wget $WGET_OPT -O models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors"

echo "Descargando CLIP Vision (Requerido por IP-Adapter)..."
mkdir -p models/clip_vision
wget $WGET_OPT -O models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors"

echo "Descargando ControlNet OpenPose para SDXL..."
mkdir -p models/controlnet
wget $WGET_OPT -O models/controlnet/thibaud_xl_openpose.safetensors "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/thibaud_xl_openpose.safetensors"

echo "[7/7] Generando ejecutable de arranque optimizado para 48GB VRAM..."
cat << 'EOF' > start_tess_engine.sh
#!/bin/bash
source venv/bin/activate
python main.py --highvram --disable-smart-memory --listen 0.0.0.0 --port 8188
EOF

chmod +x start_tess_engine.sh

echo "=============================================================================="
echo "Instalación completada. Inicializando servidor ComfyUI..."
echo "Podrás acceder a la interfaz en breve desde el panel 'Connect' de RunPod."
echo "=============================================================================="

# --- CAMBIO REALIZADO: Inicialización automática del servidor web ---
./start_tess_engine.sh