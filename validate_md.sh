#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    cat <<EOF
Usage: validate_md.sh <file.pdb>
       validate_md.sh <archive.tar.gz>

Validate protein structure stability via OpenMM MD simulation.

Options:
  --ns <N>       Simulation length in ns (default: 10)
  --full         Run full-length MD (50ns, default is 10ns for quick check)
  --save-traj    Save full DCD trajectory (large file)
  --help         Show this message

Examples:
  validate_md.sh protein.pdb
  validate_md.sh results_*.tar.gz --full
  validate_md.sh protein.pdb --ns 20 --save-traj
EOF
    exit 0
}

if [ $# -eq 0 ]; then
    usage
fi

NS=10
SAVE_TRAJ=""
INPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ns)    NS="$2"; shift 2 ;;
        --full)  NS=50; shift ;;
        --save-traj) SAVE_TRAJ="--save-trajectory"; shift ;;
        --help)  usage ;;
        *)
            if [ -f "$1" ]; then
                INPUT_FILE="$1"
                shift
            else
                echo "[ERROR] Unknown argument or file not found: $1"
                exit 1
            fi
            ;;
    esac
done

if [ -z "${INPUT_FILE}" ]; then
    echo "[ERROR] No input file provided."
    usage
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
VA_DIR="${SCRIPT_DIR}/validation_${TIMESTAMP}"
mkdir -p "${VA_DIR}"

EXT="${INPUT_FILE##*.}"
PDB_FILE=""

if [ "${EXT}" == "gz" ] || [ "${EXT}" == "tgz" ]; then
    echo "[1/4] Extracting archive..."
    TMP_EXTRACT="${VA_DIR}/_extracted"
    mkdir -p "${TMP_EXTRACT}"
    tar -xzf "${INPUT_FILE}" -C "${TMP_EXTRACT}"

    PDB_FILE=$(find "${TMP_EXTRACT}" -name "*_relaxed_rank_001_*.pdb" -type f 2>/dev/null | head -1)
    if [ -z "${PDB_FILE}" ]; then
        PDB_FILE=$(find "${TMP_EXTRACT}" -name "*.pdb" -type f 2>/dev/null | head -1)
    fi
    if [ -z "${PDB_FILE}" ]; then
        echo "[ERROR] No PDB file found in archive: ${INPUT_FILE}"
        exit 1
    fi
    echo "      Found: $(basename "${PDB_FILE}")"
else
    PDB_FILE="${INPUT_FILE}"
    echo "[1/4] Using PDB: $(basename "${PDB_FILE}")"
fi

echo "[2/4] Running MD simulation (${NS}ns)..."
python "${SCRIPT_DIR}/scripts/run_md.py" \
    --pdb "${PDB_FILE}" \
    --out-dir "${VA_DIR}" \
    --ns "${NS}" \
    ${SAVE_TRAJ} || {
        echo "[ERROR] MD simulation failed."
        exit 1
    }

echo "[3/4] Generating RMSD plot..."
python "${SCRIPT_DIR}/scripts/plot_md.py" \
    --csv "${VA_DIR}/rmsd.csv" \
    --png "${VA_DIR}/rmsd_plot.png" \
    --title "MD RMSD :: $(basename "${PDB_FILE}" .pdb)" || {
        echo "[WARN] Plot generation failed (non-critical)."
    }

echo "[4/4] Packaging results..."

REPORT_FILE="${VA_DIR}/report.json"
if [ -f "${REPORT_FILE}" ]; then
    FINAL_RMSD=$(python -c "import json; d=json.load(open('${REPORT_FILE}')); print(d['rmsd_final_nm'])")
    STABILITY=$(python -c "import json; d=json.load(open('${REPORT_FILE}')); print(d['stability'])")
    MEAN_RMSD=$(python -c "import json; d=json.load(open('${REPORT_FILE}')); print(d['rmsd_mean_last200_nm'])")
    NSPD=$(python -c "import json; d=json.load(open('${REPORT_FILE}')); print(d.get('ns_per_day','N/A'))")
else
    FINAL_RMSD="N/A"
    STABILITY="unknown"
    MEAN_RMSD="N/A"
    NSPD="N/A"
fi

# Merge predictors if pLDDT available
PLDDT="N/A"
PLDDT_JSON=$(find "$(dirname "${PDB_FILE}")" -name "*_plddt_*.json" -type f 2>/dev/null | head -1 || true)
if [ -n "${PLDDT_JSON}" ] && [ -f "${PLDDT_JSON}" ]; then
    PLDDT=$(python -c "
import json
with open('${PLDDT_JSON}') as f:
    d = json.load(f)
values = list(d.values())[0] if isinstance(d, dict) else d
print(f'{sum(values)/len(values):.1f}')
" 2>/dev/null || echo "N/A")
fi

ARCHIVE_NAME="${SCRIPT_DIR}/validation_${TIMESTAMP}.tar.gz"
tar -czf "${ARCHIVE_NAME}" -C "${SCRIPT_DIR}" "validation_${TIMESTAMP}"

# Clean up extracted temp inside archive dir
rm -rf "${VA_DIR}/_extracted"

echo ""
echo "========================================"
echo "  Validation Complete"
echo "========================================"
echo ""
echo "  pLDDT mean     : ${PLDDT}"
echo "  MD RMSD final  : ${FINAL_RMSD} nm"
echo "  MD RMSD mean   : ${MEAN_RMSD} nm"
echo "  MD Stability   : ${STABILITY}"
echo "  MD Speed       : ${NSPD} ns/day"
echo ""

# Combined verdict
VERDICT_EMOJI=""
VERDICT_TEXT=""

python -c "
pl = float('${PLDDT}') if '${PLDDT}' != 'N/A' else 0
rmsd = float('${FINAL_RMSD}') if '${FINAL_RMSD}' != 'N/A' else 99

if pl > 85 and rmsd < 0.35:
    result = 'PASS'
elif pl > 70 and rmsd < 0.50:
    result = 'CAUTION'
else:
    result = 'WARN'

print(result)
" > "${VA_DIR}/_verdict.tmp" 2>/dev/null || echo "WARN" > "${VA_DIR}/_verdict.tmp"

VERDICT=$(cat "${VA_DIR}/_verdict.tmp")
rm -f "${VA_DIR}/_verdict.tmp"

case "${VERDICT}" in
    PASS)
        echo "  > Combined: PASS - Structure is likely stable and well-folded."
        ;;
    CAUTION)
        echo "  > Combined: CAUTION - Marginal stability. Consider further validation."
        ;;
    *)
        echo "  > Combined: WARN - High risk of misfolding or instability."
        ;;
esac

echo ""
echo "  Archive: ${ARCHIVE_NAME}"
echo "  Size   : $(du -h "${ARCHIVE_NAME}" | cut -f1)"

rm -rf "${VA_DIR}"
echo ""
