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
LOG_FILE="${LOG_DIR}/evaluation_$(date +%Y%m%d_%H%M%S).log"

log "================================================"
log "ONT Assembly Pipeline - Part 2: Evaluation"
log "================================================"
log "Sample: ${SAMPLE}"
log "CPUs: ${CPU}"
log "Assembly: ${ANALYSIS_DIR}/assembly_final.fasta"
log "================================================"

# Save tool versions
VERSIONS_FILE="${ANALYSIS_DIR}/tool_versions_evaluation.txt"
echo "Evaluation Pipeline Run: $(date)" > "${VERSIONS_FILE}"


#Virker men kræver fuuucking meget RAM


#####################
# 7: GTDB-Tk - Taxonomic Classification
#####################
log "Step 7: Taxonomic classification with GTDB-Tk"

GTDBTK_OUT="${ANALYSIS_DIR}/gtdbtk"

if [ ! -d "${GTDBTK_DATA}" ]; then
    log_warning "GTDB-Tk database not found at ${GTDBTK_DATA}. Skipping GTDB-Tk."
elif conda env list | grep -q "gtdbtk_env"; then
    activate_shared gtdbtk_env
    
    # Set GTDB-Tk database path
    export GTDBTK_DATA_PATH="${GTDBTK_DATA}"
    
    log "Running GTDB-Tk classify workflow..."
    gtdbtk classify_wf \
        --genome_dir "${ANALYSIS_DIR}" \
        --out_dir "${GTDBTK_OUT}" \
        --extension fasta \
        --cpus ${CPU} \
        --skip_ani_screen \
        2>&1 | tee -a "${LOG_FILE}" || log_warning "GTDB-Tk failed"
        
    if [ -f "${GTDBTK_OUT}/gtdbtk.bac120.summary.tsv" ] || [ -f "${GTDBTK_OUT}/gtdbtk.ar53.summary.tsv" ]; then
        gtdbtk --version >> "${VERSIONS_FILE}" 2>&1
        log "GTDB-Tk completed"
        
        # Parse and save taxonomy results
        for summary in "${GTDBTK_OUT}"/gtdbtk.*.summary.tsv; do
            if [ -f "$summary" ]; then
                log "Taxonomy results: $(basename $summary)"
                # Extract classification for reporting
                tail -n +2 "$summary" | cut -f1,2 | tee -a "${ANALYSIS_DIR}/taxonomy_summary.txt"
            fi
        done
        
        # Check for warnings
        if [ -f "${GTDBTK_OUT}/gtdbtk.warnings.log" ] && [ -s "${GTDBTK_OUT}/gtdbtk.warnings.log" ]; then
            log_warning "GTDB-Tk warnings detected. Check ${GTDBTK_OUT}/gtdbtk.warnings.log"
        fi
    else
        log_warning "GTDB-Tk output files not found"
    fi
else
    log_warning "GTDB-Tk environment not found. Skipping taxonomic classification."
fi