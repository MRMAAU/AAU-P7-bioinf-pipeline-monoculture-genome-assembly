#!/bin/bash
#SBATCH --job-name=antismash_mining
#SBATCH --output=/projects/students/Bio-25-BT-7-2/P7/analysis/%x_%j.out
#SBATCH --error=/projects/students/Bio-25-BT-7-2/P7/analysis/%x_%j.err
#SBATCH --time=2:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --partition=default

# ONT Assembly Pipeline - Part 3: Genome Mining (SLURM version)
# Author: Martin & Gemini
# Date: $(date)

set -e
set -u
set -o pipefail

# --- Konfiguration ---
SAMPLE="${1:-SRR26624655}"

# Detekter om vi kører via SLURM eller interaktivt
if [ -n "${SLURM_JOB_ID:-}" ]; then
    RUNNING_MODE="SLURM"
    CPU="${SLURM_CPUS_PER_TASK}"
else
    RUNNING_MODE="Interactive"
    CPU="${2:-$(nproc)}"
fi

# Absolut sti til roden af dit P7 projekt
PROJECT_ROOT="/projects/students/Bio-25-BT-7-2/P7" 
ANALYSIS_DIR="${PROJECT_ROOT}/analysis/${SAMPLE}"
LOG_DIR="${ANALYSIS_DIR}/logs"
LOG_FILE="${LOG_DIR}/mining_$(date +%Y%m%d_%H%M%S).log"

# Opret log directory hvis det ikke eksisterer
mkdir -p "${LOG_DIR}"

# Inputfil (fra Prokka)
INPUT_GBK="${ANALYSIS_DIR}/annotation/${SAMPLE}.gbk"

# Output mappe
ANTISMASH_DIR="${ANALYSIS_DIR}/antismash"

# Logging funktion
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# --- Tjek Input ---
if [ ! -f "${INPUT_GBK}" ]; then
    log "ERROR: Prokka annotation file not found at ${INPUT_GBK}"
    log "Please run 02_evaluation.sh first!"
    exit 1
fi

# Initialiser conda
CONDA_DIR=$(dirname $(dirname $(which conda)))
source "${CONDA_DIR}/etc/profile.d/conda.sh"

log "================================================"
log "ONT Assembly Pipeline - Part 3: Genome Mining"
log "================================================"
log "Running mode: ${RUNNING_MODE}"
if [ "${RUNNING_MODE}" = "SLURM" ]; then
    log "SLURM Job ID: ${SLURM_JOB_ID}"
    log "Node: ${SLURM_NODELIST}"
    log "Memory: ${SLURM_MEM_PER_NODE}M"
fi
log "Sample: ${SAMPLE}"
log "CPUs: ${CPU}"
log "Input GBK: ${INPUT_GBK}"
log "================================================"

# Gem tool version
VERSIONS_FILE="${ANALYSIS_DIR}/tool_versions_mining.txt"
echo "Mining Pipeline Run: $(date)" > "${VERSIONS_FILE}"
echo "Running mode: ${RUNNING_MODE}" >> "${VERSIONS_FILE}"
if [ "${RUNNING_MODE}" = "SLURM" ]; then
    echo "SLURM Job ID: ${SLURM_JOB_ID}" >> "${VERSIONS_FILE}"
fi

#####################
# 1: antiSMASH - BGC Mining
#####################
log "Step 1: Mining for BGCs with antiSMASH"

if conda env list | grep -q "antismash_env"; then
    log "Activating antismash_env..."
    conda activate antismash_env
    antismash --version >> "${VERSIONS_FILE}" 2>&1

    # Kør antiSMASH med tilgængelige analyser (uden cassis der kræver meme-suite)
    log "Running antiSMASH with comprehensive analysis..."
    antismash --cpus ${CPU} \
              --taxon bacteria \
              --output-dir "${ANTISMASH_DIR}" \
              --genefinding-tool none \
              --allow-long-headers \
              --fullhmmer \
              --clusterhmmer \
              --tigrfam \
              --asf \
              --cc-mibig \
              --cb-general \
              --cb-subclusters \
              --cb-knownclusters \
              --pfam2go \
              --rre \
              --smcog-trees \
              --tfbs \
              "${INPUT_GBK}" 2>&1 | tee -a "${LOG_FILE}"
    
    ANTISMASH_EXIT_CODE=$?
    if [ ${ANTISMASH_EXIT_CODE} -ne 0 ]; then
        log "ERROR: antiSMASH failed with exit code ${ANTISMASH_EXIT_CODE}"
        exit 1
    fi

    if [ -f "${ANTISMASH_DIR}/index.html" ]; then
        log "antiSMASH completed successfully."
        log "Se den interaktive rapport her: ${ANTISMASH_DIR}/index.html"
    else
        log "WARNING: antiSMASH did not produce an output HTML file."
    fi
    
    conda deactivate
else
    log "WARNING: antismash_env not found. Skipping antiSMASH."
fi

log "================================================"
log "Genome Mining Pipeline Completed!"
log "Job finished at: $(date)"
log "================================================"