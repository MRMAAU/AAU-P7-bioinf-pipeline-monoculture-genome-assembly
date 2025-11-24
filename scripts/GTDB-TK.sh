#!/bin/bash

# GTDB-Tk Classification Pipeline
# Author: Martin
# Date: $(date)

set -e
set -u
set -o pipefail
umask 002
source /projects/students/Bio-25-BT-7-2/pipeline_config.sh

#############################
# Logging functions
#############################
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    log "WARNING: $1"
}

#############################
# Configuration
#############################
SAMPLE="${1:-PAW78174}"
BASE_DIR="rigtig_P7"
ANALYSIS_DIR="${BASE_DIR}/analysis/${SAMPLE}"
LOG_DIR="${ANALYSIS_DIR}/logs"
CPU=$(nproc)

ASSEMBLY="${ANALYSIS_DIR}/assembly_final.fasta"

if [ ! -f "${ASSEMBLY}" ]; then
    echo "ERROR: Assembly not found at: ${ASSEMBLY}"
    exit 1
fi

mkdir -p "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/gtdbtk_$(date +%Y%m%d_%H%M%S).log"
VERSIONS_FILE="${ANALYSIS_DIR}/tool_versions_gtdbtk.txt"
echo "GTDB-Tk Run: $(date)" > "${VERSIONS_FILE}"

log "================================================"
log "GTDB-Tk Classification Pipeline"
log "Sample: ${SAMPLE}"
log "Assembly: ${ASSEMBLY}"
log "CPUs: ${CPU}"
log "================================================"

#############################
# Activate GTDB-Tk environment
#############################
GTDBTK_ENV="/projects/students/Bio-25-BT-7-2/shared_conda_envs/gtdbtk_env"

if [ ! -d "${GTDBTK_ENV}" ]; then
    log "ERROR: GTDB-Tk environment not found at ${GTDBTK_ENV}"
    exit 1
fi

# Source base conda installation (rigtig sti fra which conda)
source /usr/local/Miniforge3-25.3.1-0-Linux-x86_64/etc/profile.d/conda.sh

# Activate shared GTDB-Tk environment
conda activate "${GTDBTK_ENV}" || { log "ERROR: Failed to activate GTDB-Tk environment"; exit 1; }

# Ensure gtdbtk binary exists
if ! command -v gtdbtk &> /dev/null; then
    log "ERROR: gtdbtk command not found in environment"
    exit 1
fi

#############################
# Set GTDB-Tk database path
#############################
GTDB_DB_PATH="/databases/GTDB/gtdb_data/release214"
export GTDBTK_DATA_PATH="${GTDB_DB_PATH}"

log "Using GTDB database: ${GTDB_DB_PATH}"

# Check if database exists and is accessible
if [ ! -d "${GTDB_DB_PATH}" ]; then
    log "ERROR: GTDB database not found at ${GTDB_DB_PATH}"
    exit 1
fi

#############################
# Run GTDB-Tk classification
#############################
log "Step 1: Running GTDB-Tk classification"

GTDB_OUT="${ANALYSIS_DIR}/gtdbtk"
mkdir -p "${GTDB_OUT}"

# Create temporary directory for intermediate files
TMP_DIR="${GTDB_OUT}/tmp"
mkdir -p "${TMP_DIR}"

gtdbtk classify_wf \
    --genome_dir "$(dirname "${ASSEMBLY}")" \
    --extension "fasta" \
    --prefix "${SAMPLE}" \
    --out_dir "${GTDB_OUT}" \
    --cpus "${CPU}" \
    --tmpdir "${TMP_DIR}" \
    --force 2>&1 | tee -a "${LOG_FILE}" \
    || log_warning "GTDB-Tk classification failed"

# Alternative approach if the above doesn't work:
# gtdbtk classify_wf \
#     --genome_fna "${ASSEMBLY}" \
#     --out_dir "${GTDB_OUT}" \
#     --cpus "${CPU}" \
#     --tmpdir "${TMP_DIR}" \
#     --force 2>&1 | tee -a "${LOG_FILE}" \
#     || log_warning "GTDB-Tk classification failed"

# Save version information
(gtdbtk --version >> "${VERSIONS_FILE}" 2>&1) || true

# Check if output files were generated
if [ -f "${GTDB_OUT}/${SAMPLE}.classify.tree" ] || [ -f "${GTDB_OUT}/classify/${SAMPLE}.summary.tsv" ]; then
    log "GTDB-Tk completed successfully"
    
    # Log summary if available
    if [ -f "${GTDB_OUT}/classify/${SAMPLE}.summary.tsv" ]; then
        log "Classification summary:"
        cat "${GTDB_OUT}/classify/${SAMPLE}.summary.tsv" | tee -a "${LOG_FILE}"
    fi
else
    log_warning "GTDB-Tk output files missing"
fi

# Clean up temporary directory if desired
# rm -rf "${TMP_DIR}"

# Deactivate environment
conda deactivate

#############################
# Summary
#############################
log "================================================"
log "GTDB-Tk Completed!"
log "Outputs:"
log "   - GTDB-Tk results: ${GTDB_OUT}"
log "   - Classification: ${GTDB_OUT}/classify/"
log "   - Log: ${LOG_FILE}"
log "================================================"