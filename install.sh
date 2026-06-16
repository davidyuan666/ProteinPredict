#!/usr/bin/env bash
set -euo pipefail

WITH_MD=false

for arg in "$@"; do
    case "$arg" in
        --full|--with-md) WITH_MD=true ;;
        --help) echo "Usage: install.sh [--full | --with-md]"; echo "  --full  Also install MD validation tools (OpenMM)"; exit 0 ;;
    esac
done

TOTAL=4
if $WITH_MD; then TOTAL=6; fi

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
need_cmd python
if ! command -v uv &>/dev/null; then
    echo "      uv not found, installing..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
fi
need_cmd nvidia-smi
echo "      python   : $(python --version 2>/dev/null || echo '???')"
echo "      uv       : $(uv --version 2>/dev/null || echo '???')"
echo "      CUDA     : $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"

echo ""
echo "[2/${TOTAL}] Installing colabfold[alphafold]..."
uv pip install -U "colabfold[alphafold]" jax[cuda12]
echo "      Done."

if $WITH_MD; then
    echo ""
    echo "[3/${TOTAL}] Installing OpenMM + MD tools..."
    uv pip install openmm pdbfixer mdtraj matplotlib
    echo "      Done."
    echo ""
    echo "[4/${TOTAL}] Verifying MD tools..."
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
    STEP_NOW=5
else
    STEP_NOW=3
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
echo "[${STEP_NOW}/${TOTAL}] Done."

echo ""
echo "========================================"
echo "  Installation complete!"
echo "========================================"
echo ""
echo "  To use:"
echo "    ./predict.sh example.fasta"
echo "    ./predict.sh --seq 'MKFLILF...' --name my_protein"
if $WITH_MD; then
    echo "    ./validate_md.sh my_protein.pdb"
    echo "    ./validate_all.sh example.fasta --full-md"
else
    echo ""
    echo "  MD validation not installed."
    echo "  To add it: ./install.sh --full"
fi
echo ""
echo "  Output will be packed as *_<timestamp>.tar.gz"
echo ""
