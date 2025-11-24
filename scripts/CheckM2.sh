#!/bin/bash

# ONT Assembly Pipeline - CheckM2 only
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

LOG_FILE="${LOG_DIR}/checkm2_$(date +%Y%m%d_%H%M%S).log"
VERSIONS_FILE="${ANALYSIS_DIR}/tool_versions_checkm2.txt"
echo "CheckM2 Run: $(date)" > "${VERSIONS_FILE}"

log "================================================"
log "CheckM2 Pipeline"
log "Sample: ${SAMPLE}"
log "Assembly: ${ASSEMBLY}"
log "CPUs: ${CPU}"
log "================================================"

#############################
# Activate CheckM2 environment
#############################
CHECKM2_ENV="/projects/students/Bio-25-BT-7-2/shared_conda_envs/checkm2_env"

if [ ! -d "${CHECKM2_ENV}" ]; then
    log "ERROR: CheckM2 environment not found at ${CHECKM2_ENV}"
    exit 1
fi

# Source base conda installation (rigtig sti fra which conda)
source /usr/local/Miniforge3-25.3.1-0-Linux-x86_64/etc/profile.d/conda.sh

# Activate shared CheckM2 environment
conda activate "${CHECKM2_ENV}" || { log "ERROR: Failed to activate CheckM2 environment"; exit 1; }

# Ensure checkm2 binary exists
if ! command -v checkm2 &> /dev/null; then
    log "ERROR: checkm2 command not found in environment"
    exit 1
fi

#############################
# Ensure CheckM2 database exists
#############################
log "Checking CheckM2 database..."
if ! checkm2 database --check &> /dev/null; then
    log "CheckM2 database not found. Downloading..."
    checkm2 database --download 2>&1 | tee -a "${LOG_FILE}"
    log "CheckM2 database downloaded successfully."
else
    log "CheckM2 database already present."
fi

#############################
# Run CheckM2
#############################
log "Step 1: Running CheckM2"

CHECKM2_OUT="${ANALYSIS_DIR}/checkm2"
mkdir -p "${CHECKM2_OUT}"

checkm2 predict \
    --threads ${CPU} \
    --input "${ASSEMBLY}" \
    --output-directory "${CHECKM2_OUT}" \
    --force 2>&1 | tee -a "${LOG_FILE}" \
    || log_warning "CheckM2 failed"

# Save version
(checkm2 --version >> "${VERSIONS_FILE}" 2>&1) || true

if [ -f "${CHECKM2_OUT}/quality_report.tsv" ]; then
    log "CheckM2 completed successfully"
else
    log_warning "CheckM2 output missing"
fi

# Deactivate environment
conda deactivate

#############################
# Summary
#############################
log "================================================"
log "CheckM2 Completed!"
log "Outputs:"
log "   - CheckM2: ${CHECKM2_OUT}"
log "   - Log: ${LOG_FILE}"
log "================================================"