#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="colabfold"
PYTHON_VER="3.10"
WITH_MD=false

for arg in "$@"; do
    case "$arg" in
        --full|--with-md) WITH_MD=true ;;
        --help) echo "Usage: install.sh [--full | --with-md]"; echo "  --full  Also install MD validation tools (OpenMM)"; exit 0 ;;
    esac
done

TOTAL=5
if $WITH_MD; then TOTAL=7; fi

echo "========================================"
echo "  ColabFold GPU Server Installer"
[ "$WITH_MD" = true ] && echo "  (with MD validation tools)"
echo "========================================"
echo ""

need_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "[ERROR] $1 not found. Please install it first."
        exit 1
    fi
}

echo "[1/${TOTAL}] Checking dependencies..."
need_cmd conda
need_cmd nvidia-smi
echo "      conda    : $(conda --version 2>/dev/null || echo '???')"
echo "      CUDA     : $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"

echo ""
echo "[2/${TOTAL}] Creating conda environment '${ENV_NAME}' (python=${PYTHON_VER})..."
if conda env list | grep -q "^${ENV_NAME} "; then
    echo "      Environment '${ENV_NAME}' already exists, skipping creation."
else
    conda create -n "${ENV_NAME}" python="${PYTHON_VER}" -y
    echo "      Done."
fi

echo ""
echo "[3/${TOTAL}] Activating environment and installing colabfold..."

eval "$(conda shell.bash hook)"
conda activate "${ENV_NAME}"

echo "      Upgrading pip..."
pip install --upgrade pip -q

echo "      Installing colabfold[alphafold]..."
pip install -U "colabfold[alphafold]" jax[cuda12]

echo "      Done."

if $WITH_MD; then
    echo ""
    echo "[4/${TOTAL}] Installing OpenMM + MD tools..."
    pip install openmm pdbfixer mdtraj matplotlib

    echo "      Done."
    echo ""
    echo "[5/${TOTAL}] Verifying MD tools..."
    python -c "
import openmm as mm
print(f'      openmm version: {mm.__version__}')
platforms = [mm.Platform.getPlatform(i).getName() for i in range(mm.Platform.getNumPlatforms())]
print(f'      platforms      : {platforms}')
if 'CUDA' in platforms:
    print(f'      GPU (CUDA)     : available')
else:
    print(f'      [WARN] CUDA platform not found. OpenMM may run on CPU.')
import pdbfixer
print(f'      pdbfixer        : OK')
import mdtraj
print(f'      mdtraj          : {mdtraj.__version__}')
import matplotlib
print(f'      matplotlib      : {matplotlib.__version__}')
"
    STEP_NOW=6
else
    STEP_NOW=4
fi

echo ""
echo "[${STEP_NOW}/${TOTAL}] Verifying colabfold installation..."
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

STEP_NOW=$((STEP_NOW + 1))
echo ""
echo "[${STEP_NOW}/${TOTAL}] Cleaning up..."
conda deactivate

echo ""
echo "========================================"
echo "  Installation complete!"
echo "========================================"
echo ""
echo "  To use:"
echo "    conda activate ${ENV_NAME}"
echo "    predict.sh example.fasta"
echo "    predict.sh --seq 'MKFLILF...' --name my_protein"
if $WITH_MD; then
    echo "    validate_md.sh my_protein.pdb"
    echo "    validate_all.sh example.fasta --full-md"
else
    echo ""
    echo "  MD validation not installed."
    echo "  To add it: ./install.sh --full"
fi
echo ""
echo "  Output will be packed as *_<timestamp>.tar.gz"
echo ""
