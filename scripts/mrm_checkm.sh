#!/bin/bash
#SBATCH --job-name=checkm2_eval
#SBATCH --output=/projects/students/Bio-25-BT-7-2/rigtig_P7/analysis/%x_%j.out
#SBATCH --error=/projects/students/Bio-25-BT-7-2/rigtig_P7/analysis/%x_%j.err
#SBATCH --time=1:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --partition=default

# ONT Assembly Pipeline - Optional Part 2b: CheckM2
# Author: BT72
# Date: $(date +%Y-%m-%d)
umask 002
source /projects/students/Bio-25-BT-7-2/pipeline_config.sh

set -e
set -u
set -o pipefail

######################### Configuration #######################

SAMPLE="${1:-PAW78174}" # Default sample if none provided
CPU="${SLURM_CPUS_PER_TASK:-$(nproc)}"

# Paths
PROJECT_ROOT="/projects/students/Bio-25-BT-7-2/rigtig_P7"
ANALYSIS_DIR="${PROJECT_ROOT}/analysis/${SAMPLE}"
LOG_DIR="${ANALYSIS_DIR}/logs"
CHECKM2_OUT="${ANALYSIS_DIR}/checkm2"

# THE CRITICAL PART: Path to your manual database
# Points to the .dmnd file inside the folder you extracted
CHECKM2_DB="/projects/students/Bio-25-BT-7-2/shared_resources/checkm2_db/CheckM2_database/uniref100.KO.1.dmnd"

# Input Assembly
INPUT_FASTA="${ANALYSIS_DIR}/assembly_final.fasta"

# Logging
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/checkm2_$(date +%Y%m%d_%H%M%S).log"

# Initialize conda
CONDA_DIR=$(dirname $(dirname $(which conda)))
source "${CONDA_DIR}/etc/profile.d/conda.sh"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log "================================================"
log "CheckM2 Quality Assessment"
log "================================================"
log "Sample: ${SAMPLE}"
log "Input: ${INPUT_FASTA}"
log "Database: ${CHECKM2_DB}"
log "================================================"

# 1. Checks
if [ ! -f "${INPUT_FASTA}" ]; then
    log "ERROR: Input assembly not found at ${INPUT_FASTA}"
    exit 1
fi

if [ ! -f "${CHECKM2_DB}" ]; then
    log "ERROR: CheckM2 database file not found at ${CHECKM2_DB}"
    log "Did you run the manual download commands?"
    exit 1
fi

# 2. Activate Environment
if [ ! -d "${SHARED_CONDA}/checkm2_env" ]; then
    log "ERROR: checkm2_env not found in ${SHARED_CONDA}"
    exit 1
fi

log "Activating checkm2_env..."
activate_shared checkm2_env

# 3. Run CheckM2
# Note: We use --database_path to override any internal config
log "Running CheckM2 predict..."

checkm2 predict \
    --threads ${CPU} \
    --input "${INPUT_FASTA}" \
    --output-directory "${CHECKM2_OUT}" \
    --database_path "${CHECKM2_DB}" \
    --force \
    2>&1 | tee -a "${LOG_FILE}"

# 4. Report Results
if [ -f "${CHECKM2_OUT}/quality_report.tsv" ]; then
    log "CheckM2 completed successfully."
    log "Report: ${CHECKM2_OUT}/quality_report.tsv"
    
    log "--- Summary ---"
    # Print the header and the first data line
    head -n 2 "${CHECKM2_OUT}/quality_report.tsv" | tee -a "${LOG_FILE}"
else
    log "ERROR: CheckM2 failed to generate a report."
    exit 1
fi

conda deactivate
log "Done."