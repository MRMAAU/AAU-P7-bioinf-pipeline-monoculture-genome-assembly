#!/bin/bash
# MultiQC Aggregation Script
# Generates a single MultiQC report combining all samples
# Usage: ./generate_multiqc_report.sh

umask 002
source /projects/students/Bio-25-BT-7-2/pipeline_config.sh

set -e
set -u
set -o pipefail

# Initialize conda
CONDA_DIR=$(dirname $(dirname $(which conda)))
source "${CONDA_DIR}/etc/profile.d/conda.sh"

# Configuration
PROJECT_ROOT="/projects/students/Bio-25-BT-7-2/rigtig_P7"
ANALYSIS_DIR="${PROJECT_ROOT}/analysis"
MULTIQC_OUTPUT="${PROJECT_ROOT}/multiqc_all_samples"

# Create output directory
mkdir -p "${MULTIQC_OUTPUT}"
chmod g+rwxs "${MULTIQC_OUTPUT}"

echo "========================================="
echo "MultiQC Aggregation Report"
echo "========================================="
echo "Scanning: ${ANALYSIS_DIR}"
echo "Output: ${MULTIQC_OUTPUT}"
echo "========================================="

# Activate MultiQC environment
activate_shared multiqc_env

# Count samples
SAMPLE_COUNT=$(find "${ANALYSIS_DIR}" -maxdepth 1 -type d | wc -l)
echo "Found $((SAMPLE_COUNT - 1)) sample directories"

# Run MultiQC on entire analysis directory
# This will recursively find all supported tool outputs
multiqc "${ANALYSIS_DIR}" \
    --outdir "${MULTIQC_OUTPUT}" \
    --filename "multiqc_report_all_samples" \
    --title "ONT Pipeline - All Samples" \
    --comment "Aggregate report for Bio-25-BT-7-2 project" \
    --force \
    --verbose \
    --dirs \
    --dirs-depth 2 \
    --export \
    --data-format json \
    --zip-data-dir

echo ""
echo "========================================="
echo "MultiQC Report Generated!"
echo "========================================="
echo "Report location:"
echo "  HTML: ${MULTIQC_OUTPUT}/multiqc_report_all_samples.html"
echo "  Data: ${MULTIQC_OUTPUT}/multiqc_report_all_samples_data/"
echo ""
echo "To view the report:"
echo "  1. Copy to your local machine, or"
echo "  2. Open in a browser if you have X11 forwarding"
echo "========================================="

# Create a sample summary
echo ""
echo "Sample Summary:"
echo "---------------"

SUMMARY_FILE="${MULTIQC_OUTPUT}/samples_processed.txt"
cat > "${SUMMARY_FILE}" << EOF
MultiQC Aggregate Report - Sample Summary
Generated: $(date)
Project: Bio-25-BT-7-2

Samples included in this report:
EOF

# List all sample directories
find "${ANALYSIS_DIR}" -maxdepth 1 -type d -not -path "${ANALYSIS_DIR}" | \
    while read -r sample_dir; do
        sample_name=$(basename "$sample_dir")
        echo "  - $sample_name" | tee -a "${SUMMARY_FILE}"
    done

echo ""
echo "Summary saved to: ${SUMMARY_FILE}"
echo "========================================="