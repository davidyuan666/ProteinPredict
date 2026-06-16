#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="colabfold"
PYTHON_VER="3.10"

echo "========================================"
echo "  ColabFold GPU Server Installer"
echo "========================================"
echo ""

need_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "[ERROR] $1 not found. Please install it first."
        exit 1
    fi
}

echo "[1/5] Checking dependencies..."
need_cmd conda
need_cmd nvidia-smi
echo "      conda    : $(conda --version 2>/dev/null || echo '???')"
echo "      CUDA     : $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"

echo ""
echo "[2/5] Creating conda environment '${ENV_NAME}' (python=${PYTHON_VER})..."
if conda env list | grep -q "^${ENV_NAME} "; then
    echo "      Environment '${ENV_NAME}' already exists, skipping creation."
else
    conda create -n "${ENV_NAME}" python="${PYTHON_VER}" -y
    echo "      Done."
fi

echo ""
echo "[3/5] Activating environment and installing colabfold..."

eval "$(conda shell.bash hook)"
conda activate "${ENV_NAME}"

echo "      Upgrading pip..."
pip install --upgrade pip -q

echo "      Installing colabfold[alphafold]..."
pip install -U "colabfold[alphafold]" jax[cuda12]

echo "      Done."

echo ""
echo "[4/5] Verifying installation..."
python -c "
import colabfold
print(f'      colabfold version: {colabfold.__version__}')
import jax
print(f'      jax version      : {jax.__version__}')
devices = jax.devices('gpu')
if devices:
    print(f'      GPU detected     : {devices[0].device_kind}')
else:
    print('      [WARN] No GPU device found by jax. Check CUDA/cudnn setup.')
"

echo ""
echo "[5/5] Cleaning up..."
conda deactivate

echo ""
echo "========================================"
echo "  Installation complete!"
echo "========================================"
echo ""
echo "  To use:"
echo "    conda activate ${ENV_NAME}"
echo "    predict.sh --seq 'MKFLILF...' --name my_protein"
echo "    predict.sh input.fasta"
echo ""
echo "  Output will be packed as results_<timestamp>.tar.gz"
echo ""
