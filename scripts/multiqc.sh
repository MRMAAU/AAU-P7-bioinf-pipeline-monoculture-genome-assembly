#!/bin/bash
# ONT Assembly Pipeline - Part 2: Evaluation & Annotation
# Author: Martin
# Date: $(date)
umask 002
set -e
set -u
set -o pipefail

source /projects/students/Bio-25-BT-7-2/pipeline_config.sh

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Non-critical error handler (logs but continues)
log_warning() {
    log "WARNING: $1"
}

# Initialize conda
CONDA_DIR=$(dirname $(dirname $(which conda)))
source "${CONDA_DIR}/etc/profile.d/conda.sh"

#####################
# Configuration
#####################
SAMPLE="${1:-BC4-SIL-28-02-2024-Gr16-BHI-19}"  # Allow sample as argument
CPU="${SLURM_CPUS_PER_TASK:-$(nproc)}"  # Use all available CPUs

# Paths
BASE_DIR="/projects/students/Bio-25-BT-7-2/rigtig_P7"
ANALYSIS_DIR="${PROJECT_ROOT}/analysis/${SAMPLE}"
LOG_DIR="${ANALYSIS_DIR}/logs"
# Database paths
BAKTA_DB="/databases/bakta/20240125/db"
# Check if assembly exists
if [ ! -f "${ANALYSIS_DIR}/assembly_final.fasta" ]; then
    echo "ERROR: Assembly not found at ${ANALYSIS_DIR}/assembly_final.fasta"
    echo "Please run 01_assembly.sh first!"
    exit 1
fi

# Create log file
LOG_FILE="${LOG_DIR}/multiqc_$(date +%Y%m%d_%H%M%S).log"

log "================================================"
log "MultiQC"
log "================================================"
log "Sample: ${SAMPLE}"
log "CPUs: ${CPU}"
log "Assembly: ${ANALYSIS_DIR}/assembly_final.fasta"
log "================================================"

# Save tool versions
VERSIONS_FILE="${ANALYSIS_DIR}/tool_versions_evaluation.txt"
echo "Evaluation Pipeline Run: $(date)" > "${VERSIONS_FILE}"

#####################
# 7: MultiQC report
#####################
log "Step 1: Generating MultiQC report"

if conda env list | grep -q "multiqc_env"; then
    activate_shared multiqc_env
    multiqc "${ANALYSIS_DIR}" -o "${ANALYSIS_DIR}/multiqc_report" -f 2>&1 | tee -a "${LOG_FILE}" || log_warning "MultiQC had issues"
    
    if [ -d "${ANALYSIS_DIR}/multiqc_report" ]; then
        multiqc --version >> "${VERSIONS_FILE}" 2>&1
        log "MultiQC report generated"
    fi
else
    log_warning "MultiQC environment not found. Skipping MultiQC report."
fi

