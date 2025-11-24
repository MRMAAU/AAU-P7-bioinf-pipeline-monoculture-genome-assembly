#!/bin/bash
#SBATCH --job-name=deepbgc_test
#SBATCH --output=/projects/students/Bio-25-BT-7-2/rigtig_P7/analysis/%x_%j.out
#SBATCH --error=/projects/students/Bio-25-BT-7-2/rigtig_P7/analysis/%x_%j.err
#SBATCH --time=2:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --partition=default

# ONT Assembly Pipeline - Optional Part 3b: DeepBGC Standalone
# Author: BT72
# Date: $(date +%Y-%m-%d)
umask 002
source /projects/students/Bio-25-BT-7-2/pipeline_config.sh

set -e #Exit if any command fails
set -u #Treat unset variables as errors
set -o pipefail #command fail = pipeline fail

######################### Configuration #######################

SAMPLE="${1:-PAW78174}" # Defaults to PAW78174 if no argument given
CPU="${SLURM_CPUS_PER_TASK:-$(nproc)}"

# Folders
PROJECT_ROOT="/projects/students/Bio-25-BT-7-2/rigtig_P7"
ANALYSIS_DIR="${PROJECT_ROOT}/analysis/${SAMPLE}"
LOG_DIR="${ANALYSIS_DIR}/logs"
DEEPBGC_DIR="${ANALYSIS_DIR}/deepbgc"

# Logging
mkdir -p "${LOG_DIR}" "${DEEPBGC_DIR}"
LOG_FILE="${LOG_DIR}/deepbgc_standalone_$(date +%Y%m%d_%H%M%S).log"

# Input: We need the .gbk file from Prokka (Step 02)
INPUT_GBK="${ANALYSIS_DIR}/annotation/${SAMPLE}.gbk"

# Initialize conda
CONDA_DIR=$(dirname $(dirname $(which conda)))
source "${CONDA_DIR}/etc/profile.d/conda.sh"

# Logging function
log() {
   echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log "================================================"
log "DeepBGC Standalone Test"
log "================================================"
log "Sample: ${SAMPLE}"
log "Input File: ${INPUT_GBK}"
log "Output Dir: ${DEEPBGC_DIR}"
log "================================================"

# Check input
if [ ! -f "${INPUT_GBK}" ]; then
    log "ERROR: Input file not found: ${INPUT_GBK}"
    log "Make sure you have run 02_evaluation.sh (Prokka) first."
    exit 1
fi

# Check environment
if [ ! -d "${SHARED_CONDA}/deepbgc_env" ]; then
    log "ERROR: deepbgc_env does not exist in ${SHARED_CONDA}"
    log "Please create it first using the instructions provided."
    exit 1
fi

######################### Execution #######################

log "Activating deepbgc_env..."
activate_shared deepbgc_env

log "Running DeepBGC pipeline..."

# Capture start time
START_TIME=$SECONDS

# Run DeepBGC
# --force overwrites previous results in that folder
{
    echo "=== DeepBGC Tool Log Start ==="
    deepbgc pipeline "${INPUT_GBK}" \
        --output "${DEEPBGC_DIR}" \
        --force \
        --log "${DEEPBGC_DIR}/deepbgc_debug.log"
    echo "=== DeepBGC Tool Log End ==="
} &>> "${LOG_FILE}"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && [ -f "${DEEPBGC_DIR}/report.bgc.tsv" ]; then
    DURATION=$(( SECONDS - START_TIME ))
    COUNT=$(grep -c -v "detector_label" "${DEEPBGC_DIR}/report.bgc.tsv" || true)
    
    log "SUCCESS: DeepBGC finished in ${DURATION} seconds."
    log "Clusters found: ${COUNT}"
    log "Report: ${DEEPBGC_DIR}/report.bgc.tsv"
else
    log "ERROR: DeepBGC failed with exit code ${EXIT_CODE}."
    log "Check the log file for details: ${LOG_FILE}"
    exit 1
fi

conda deactivate

log "Done."