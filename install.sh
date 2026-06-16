#!/usr/bin/env bash
set -euo pipefail

WITH_MD=false
MINIMAL=false

for arg in "$@"; do
    case "$arg" in
        --full|--with-md) WITH_MD=true ;;
        --minimal) MINIMAL=true ;;
        --help)
            echo "Usage: install.sh [--full | --with-md] [--minimal]"
            echo ""
            echo "  --full      Also install MD validation tools (OpenMM, +2min)"
            echo "  --minimal   Skip colabfold[alphafold] extras (~200MB saved)"
            exit 0
            ;;
    esac
done

TOTAL=4
if $WITH_MD; then TOTAL=6; fi

echo "========================================"
echo "  ColabFold GPU Server Installer"
echo "========================================"
$WITH_MD && echo "  (MD validation included)"
$MINIMAL && echo "  (minimal install, skipping alphafold extras)"
echo ""

need_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "[ERROR] $1 not found. Please install it first."
        exit 1
    fi
}

echo "[1/${TOTAL}] Checking dependencies..."
need_cmd python
need_cmd nvidia-smi

echo "      python   : $(python --version 2>/dev/null || echo '???')"
echo "      CUDA     : $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"

CUDA_MAJOR=$(nvidia-smi | grep -oP "CUDA Version: \K[0-9]+" 2>/dev/null || echo "12")
echo "      CUDA ver : ${CUDA_MAJOR}.x"

# Auto-detect correct jax CUDA variant
if [ "$CUDA_MAJOR" = "12" ]; then
    JAX_CUDA="jax[cuda12]"
elif [ "$CUDA_MAJOR" = "11" ]; then
    JAX_CUDA="jax[cuda11]"
else
    echo "      [WARN] Unrecognized CUDA version '${CUDA_MAJOR}', defaulting to cuda12"
    JAX_CUDA="jax[cuda12]"
fi

# Install uv if missing (fast pip alternative)
UV_AVAILABLE=false
if command -v uv &>/dev/null; then
    UV_AVAILABLE=true
else
    echo "      uv not found, installing (1 sec)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
    UV_AVAILABLE=true
fi

echo "      uv       : $(uv --version 2>/dev/null || echo '???')"

# Pre-existing package check helper
already_installed() {
    python -c "import $1" 2>/dev/null && echo "true" || echo "false"
}

echo ""
echo "[2/${TOTAL}] Installing colabfold + JAX..."

if $MINIMAL; then
    CF_PKG="colabfold"
    echo "      (minimal: skipping [alphafold] extras)"
else
    CF_PKG="colabfold[alphafold]"
fi

uv pip install -U --system "${CF_PKG}" "${JAX_CUDA}"

echo "      Done."

if $WITH_MD; then
    echo ""
    echo "[3/${TOTAL}] Installing MD tools (OpenMM, PDBFixer, MDTraj)..."

    MD_DEPS="openmm pdbfixer mdtraj"
    SKIP_LIST=""
    for pkg in openmm pdbfixer mdtraj matplotlib; do
        mod=$(echo "$pkg" | sed 's/-/_/g')
        if [ "$(already_installed "${mod}")" = "true" ]; then
            echo "      [skip] ${pkg} already installed"
        else
            SKIP_LIST="${SKIP_LIST} ${pkg}"
        fi
    done

    if [ -n "${SKIP_LIST}" ]; then
        uv pip install --system ${SKIP_LIST}
    fi

    echo "      Done."

    STEP_NOW=5

    echo ""
    echo "[4/${TOTAL}] Verifying MD tools..."
    python -c "
import openmm as mm
platforms = [mm.Platform.getPlatform(i).getName() for i in range(mm.Platform.getNumPlatforms())]
print(f'      openmm v{mm.__version__}  platforms: {platforms}')
if 'CUDA' in platforms:
    print('      OpenMM GPU (CUDA) : available')
elif 'OpenCL' in platforms:
    print('      OpenMM OpenCL     : available (CPU)')
else:
    print('      OpenMM            : CPU only')
import mdtraj, matplotlib
print(f'      mdtraj v{mdtraj.__version__}    matplotlib OK')
"
else
    STEP_NOW=3
fi

echo ""
echo "[${STEP_NOW}/${TOTAL}] Verifying colabfold + JAX..."

python -c "
import colabfold
print(f'      colabfold : v{colabfold.__version__}')
import jax
print(f'      jax       : v{jax.__version__}')
import jaxlib
print(f'      jaxlib    : v{jaxlib.__version__}')
devices = jax.devices('gpu')
if devices:
    print(f'      GPU       : {devices[0].device_kind} ({len(devices)} device(s))')
else:
    print('      [WARN] No GPU device found by jax. Check CUDA/cuDNN setup.')
import numpy, scipy, matplotlib
print(f'      numpy v{numpy.__version__}, scipy v{scipy.__version__}')
"

STEP_NOW=$((STEP_NOW + 1))
echo ""
echo "[${STEP_NOW}/${TOTAL}] Done."

echo ""
echo "========================================"
echo "  Installation complete!"
echo "========================================"
echo ""
echo "  Usage:"
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
