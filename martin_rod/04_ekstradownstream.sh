#!/bin/bash

# Downstream Analysis Pipeline: BGC Detection and AMR Analysis
# Requires: genome assembly (contigs/scaffolds in FASTA format)
# Performs: DeepBGC, Gekko, ARTS, and CARD RGI analysis

set -e

############################
# Initialize conda properly
############################
umask 002

source /projects/students/Bio-25-BT-7-2/pipeline_config.sh

SAMPLE="test1"

CONDA_BASE=$(conda info --base)
source "${CONDA_BASE}/etc/profile.d/conda.sh"

PROJECT_ROOT="/projects/students/Bio-25-BT-7-2/rigtig_P7"

DATA_DIR="${PROJECT_ROOT}/data"
ANALYSIS_DIR="${PROJECT_ROOT}/analysis/${SAMPLE}"
LOG_DIR="${ANALYSIS_DIR}/logs"

# Downstream analysis directories
DEEPBGC_DIR="${ANALYSIS_DIR}/deepbgc"
GEKKO_DIR="${ANALYSIS_DIR}/gekko"
ARTS_DIR="${ANALYSIS_DIR}/arts"
CARD_DIR="${ANALYSIS_DIR}/card_rgi"

# Input assembly file (adjust path as needed)
ASSEMBLY="${ANALYSIS_DIR}/assembly/${SAMPLE}_assembly.fasta"

# Create directories
mkdir -p "${DEEPBGC_DIR}" "${GEKKO_DIR}" "${ARTS_DIR}" "${CARD_DIR}"
chmod g+rwxs "${DEEPBGC_DIR}" "${GEKKO_DIR}" "${ARTS_DIR}" "${CARD_DIR}"

echo "========================================="
echo "Starting Downstream Analysis Pipeline"
echo "Sample: ${SAMPLE}"
echo "========================================="

############################
# 1. DeepBGC Analysis
############################
echo ""
echo ">>> Running DeepBGC for BGC detection..."

activate_shared deepbgc_env

# Download/update DeepBGC database (run once)
# deepbgc download

deepbgc pipeline \
    "${ASSEMBLY}" \
    --output "${DEEPBGC_DIR}" \
    --detector deepbgc \
    --score 0.5 \
    2>&1 | tee "${LOG_DIR}/deepbgc.log"

echo "✅ DeepBGC complete. Results in: ${DEEPBGC_DIR}"

############################
# 2. Gekko Analysis
############################
echo ""
echo ">>> Running Gekko (Random Forest BGC prediction)..."

activate_shared gekko_env

# Gekko typically requires antiSMASH input or similar format
# Adjust parameters based on your specific Gekko installation
gekko \
    --input "${ASSEMBLY}" \
    --output "${GEKKO_DIR}" \
    --threads 4 \
    --model random_forest \
    2>&1 | tee "${LOG_DIR}/gekko.log"

echo "✅ Gekko complete. Results in: ${GEKKO_DIR}"

############################
# 3. ARTS Analysis
############################
echo ""
echo ">>> Running ARTS (Antibiotic Resistant Target Seeker)..."

activate_shared arts_env

# Run ARTS
arts \
    --antismash "${ANTISMASH_DIR}" \
    --output "${ARTS_DIR}" \
    --cores 4 \
    --known-clusters \
    2>&1 | tee "${LOG_DIR}/arts.log"

echo "✅ ARTS complete. Results in: ${ARTS_DIR}"

############################
# 4. CARD RGI Analysis
############################
echo ""
echo ">>> Running CARD RGI (Resistance Gene Identifier)..."

source activate_shared_env.sh rgi_env

# Load/update CARD database (run once or periodically)
# rgi load --card_json /path/to/card.json --local

# Run RGI main for genome analysis
rgi main \
    --input_sequence "${ASSEMBLY}" \
    --output_file "${CARD_DIR}/${SAMPLE}_rgi" \
    --input_type contig \
    --local \
    --clean \
    --num_threads 4 \
    --alignment_tool DIAMOND \
    2>&1 | tee "${LOG_DIR}/rgi.log"


# Generate heatmap (optional)
rgi heatmap \
    --input "${CARD_DIR}/${SAMPLE}_rgi.txt" \
    --output "${CARD_DIR}/${SAMPLE}_heatmap" \
    --cluster both \
    --display frequency \
    2>&1 | tee -a "${LOG_DIR}/rgi.log"

echo "✅ CARD RGI complete. Results in: ${CARD_DIR}"

############################
# Summary Report
############################
echo ""
echo "========================================="
echo "Pipeline Complete!"
echo "========================================="
echo ""
echo "Results locations:"
echo "  - DeepBGC:   ${DEEPBGC_DIR}"
echo "  - Gekko:     ${GEKKO_DIR}"
echo "  - ARTS:      ${ARTS_DIR}"
echo "  - CARD RGI:  ${CARD_DIR}"
echo ""
echo "Key output files:"
echo "  - DeepBGC BGCs: ${DEEPBGC_DIR}/bgc_predictions.tsv"
echo "  - RGI results:  ${CARD_DIR}/${SAMPLE}_rgi.txt"
echo "  - ARTS hits:    ${ARTS_DIR}/arts_results.txt"
echo ""
echo "All logs saved to: ${LOG_DIR}"
echo "========================================="