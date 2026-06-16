#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="colabfold"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    cat <<EOF
Usage: predict.sh <file.fasta>
       predict.sh --seq <SEQUENCE> --name <NAME>
       predict.sh --multi <file.fasta>     (batch run)

Options:
  --seq      Amino acid sequence (single-letter code)
  --name     Protein name for output (required with --seq)
  --multi    Run multiple sequences in one fasta file
  --msa-mode mmseqs2  (default) or single_sequence
  --num-recycle NUM   (default: 3)
  --help     Show this message

Examples:
  predict.sh example.fasta
  predict.sh --seq "MSKGEELFTGVV..." --name my_gfp
  predict.sh --multi batch.fasta --msa-mode single_sequence
EOF
    exit 0
}

if [ $# -eq 0 ]; then
    usage
fi

MSA_MODE="mmseqs2"
NUM_RECYCLE="3"
SEQUENCE=""
NAME=""
FASTA_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --seq)   SEQUENCE="$2"; shift 2 ;;
        --name)  NAME="$2"; shift 2 ;;
        --multi) FASTA_FILE="$2"; shift 2 ;;
        --msa-mode) MSA_MODE="$2"; shift 2 ;;
        --num-recycle) NUM_RECYCLE="$2"; shift 2 ;;
        --help)  usage ;;
        *)
            if [[ "$1" =~ \.(fasta|fa|faa|fas)$ ]] || [[ -f "$1" ]]; then
                FASTA_FILE="$1"
                shift
            else
                echo "[ERROR] Unknown argument: $1"
                usage
            fi
            ;;
    esac
done

if [ -z "${SEQUENCE}" ] && [ -z "${FASTA_FILE}" ]; then
    echo "[ERROR] No input. Provide a .fasta file or --seq + --name."
    usage
fi

if [ -n "${SEQUENCE}" ] && [ -z "${NAME}" ]; then
    echo "[ERROR] --seq requires --name."
    usage
fi

eval "$(conda shell.bash hook)"
if ! conda activate "${ENV_NAME}" 2>/dev/null; then
    echo "[ERROR] Conda env '${ENV_NAME}' not found. Run install.sh first."
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_DIR="${SCRIPT_DIR}/results_${TIMESTAMP}"
WORK_DIR="${SCRIPT_DIR}"

if [ -n "${SEQUENCE}" ]; then
    TEMP_FASTA="${WORK_DIR}/.temp_${TIMESTAMP}.fasta"
    echo ">${NAME}" > "${TEMP_FASTA}"
    echo "${SEQUENCE}" >> "${TEMP_FASTA}"
    FASTA_FILE="${TEMP_FASTA}"
    echo "Input : sequence (${#SEQUENCE} residues)"
else
    echo "Input : ${FASTA_FILE}"
fi

echo "Output: ${OUT_DIR}"
echo "MSA   : ${MSA_MODE}"
echo ""

echo "[1/2] Running ColabFold prediction..."
colabfold_batch \
    --msa-mode "${MSA_MODE}" \
    --num-recycle "${NUM_RECYCLE}" \
    "${FASTA_FILE}" \
    "${OUT_DIR}" || {
        echo "[ERROR] ColabFold prediction failed."
        [ -n "${SEQUENCE}" ] && rm -f "${TEMP_FASTA}"
        exit 1
    }

if [ -n "${SEQUENCE}" ]; then
    rm -f "${TEMP_FASTA}"
fi

echo ""
echo "[2/2] Packaging results..."

ARCHIVE_NAME="${SCRIPT_DIR}/results_${TIMESTAMP}.tar.gz"
tar -czf "${ARCHIVE_NAME}" -C "${SCRIPT_DIR}" "results_${TIMESTAMP}"

echo "       Archive: ${ARCHIVE_NAME}"
echo "       Size   : $(du -h "${ARCHIVE_NAME}" | cut -f1)"

echo ""
echo "========================================"
echo "  Prediction complete!"
echo "========================================"

BEST_PDB=$(ls "${OUT_DIR}"/*_relaxed_rank_001_*.pdb 2>/dev/null | head -1)
if [ -n "${BEST_PDB}" ]; then
    echo ""
    echo "  Best model : $(basename "${BEST_PDB}")"
    PLDDT_JSON=$(ls "${OUT_DIR}"/*_plddt_*.json 2>/dev/null | head -1)
    if [ -n "${PLDDT_JSON}" ]; then
        MEAN_PLDDT=$(python -c "
import json
with open('${PLDDT_JSON}') as f:
    d = json.load(f)
values = list(d.values())[0] if isinstance(d, dict) else d
print(f'{sum(values)/len(values):.2f}')
" 2>/dev/null || echo "N/A")
        echo "  Mean pLDDT : ${MEAN_PLDDT}"
    fi
    echo ""
    echo "  Visualize  : Open in PyMOL or https://3dmol.csb.pitt.edu"
fi

rm -rf "${OUT_DIR}"
echo ""
echo "  All files in: ${ARCHIVE_NAME}"
echo ""
