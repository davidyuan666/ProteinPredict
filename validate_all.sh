#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    cat <<EOF
Usage: validate_all.sh <file.fasta>
       validate_all.sh --seq <SEQUENCE> --name <NAME>

Full pipeline: FASTA -> ColabFold prediction -> MD validation -> report.

Options:
  --seq <seq>    Amino acid sequence
  --name <name>  Protein name (required with --seq)
  --msa-mode M   MSA mode: mmseqs2 (default) or single_sequence
  --md-ns <N>    MD simulation ns (default: 10, use 50 for thorough)
  --full-md      Run 50ns MD (thorough, slower)
  --save-traj    Save MD trajectory files (large)
  --help         Show this message

Examples:
  validate_all.sh example.fasta
  validate_all.sh --seq "MKFLILF..." --name my_design --full-md
EOF
    exit 0
}

if [ $# -eq 0 ]; then
    usage
fi

SEQUENCE=""
NAME=""
FASTA_FILE=""
MSA_MODE="mmseqs2"
MD_NS=10
SAVE_TRAJ=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --seq)       SEQUENCE="$2"; shift 2 ;;
        --name)      NAME="$2"; shift 2 ;;
        --msa-mode)  MSA_MODE="$2"; shift 2 ;;
        --md-ns)     MD_NS="$2"; shift 2 ;;
        --full-md)   MD_NS=50; shift ;;
        --save-traj) SAVE_TRAJ="--save-traj"; shift ;;
        --help)      usage ;;
        *)
            if [ -f "$1" ]; then
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

echo "========================================"
echo "  Full Pipeline: Predict + Validate"
echo "========================================"
echo ""

echo "=== Stage 1/2: Structure Prediction ==="
echo ""

if [ -n "${SEQUENCE}" ]; then
    PREDICT_ARGS="--seq \"${SEQUENCE}\" --name \"${NAME}\" --msa-mode ${MSA_MODE}"
    bash "${SCRIPT_DIR}/predict.sh" --seq "${SEQUENCE}" --name "${NAME}" --msa-mode "${MSA_MODE}"
else
    PREDICT_ARGS="${FASTA_FILE} --msa-mode ${MSA_MODE}"
    bash "${SCRIPT_DIR}/predict.sh" "${FASTA_FILE}" --msa-mode "${MSA_MODE}"
fi

# Find the latest results tar.gz
RESULTS_ARCHIVE=$(ls -t "${SCRIPT_DIR}"/results_*.tar.gz 2>/dev/null | head -1)

if [ -z "${RESULTS_ARCHIVE}" ]; then
    echo "[ERROR] Prediction did not produce expected results_*.tar.gz."
    exit 1
fi

echo ""
echo "=== Stage 2/2: MD Validation ==="
echo ""

MD_ARGS="${RESULTS_ARCHIVE} --ns ${MD_NS} ${SAVE_TRAJ}"
bash "${SCRIPT_DIR}/validate_md.sh" ${MD_ARGS}

# Find the latest validation tar.gz
VA_ARCHIVE=$(ls -t "${SCRIPT_DIR}"/validation_*.tar.gz 2>/dev/null | head -1)

echo ""
echo "========================================"
echo "  Pipeline Complete"
echo "========================================"
echo ""
echo "  Prediction  : ${RESULTS_ARCHIVE}"
if [ -n "${VA_ARCHIVE}" ]; then
    echo "  Validation  : ${VA_ARCHIVE}"
fi
echo ""
echo "  To visualize:"
echo "    1. Extract the archive"
echo "    2. Open *_relaxed_rank_001_*.pdb in PyMOL"
echo "    3. Check rmsd_plot.png for stability"
echo ""
