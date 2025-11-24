#!/bin/bash
# ONT Assembly Pipeline - Part 1: Assembly & Polishing
# Author: [Your name]
# Date: $(date)

#Exit hvis noget fejler under kørsel, Sæt ikke angivne variabler til at være en error, sæt navnet på error til pipefail, giv adgang til andre kan ændre
set -e
set -u
set -o pipefail
umask 002

source /projects/students/Bio-25-BT-7-2/pipeline_config.sh

# Trap errors and log them
trap 'error_handler $? $LINENO' ERR

error_handler() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Command failed with exit code $1 at line $2" | tee -a "${LOG_FILE:-/tmp/pipeline_error.log}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Last command: $BASH_COMMAND" | tee -a "${LOG_FILE:-/tmp/pipeline_error.log}"
    exit $1
}

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Initialize conda
CONDA_DIR=$(dirname $(dirname $(which conda)))
source "${CONDA_DIR}/etc/profile.d/conda.sh"

#####################
# Configuration
#####################
SAMPLE="${1:-PBI54877.barcode01}"  # Allow sample as argument (det er vel Sample som Variable)
GENOME_SIZE="${2:-5m}"  # Allow genome size as argument
CPU="${SLURM_CPUS_PER_TASK:-$(nproc)}"  # Use all available CPUs

# Absolut sti til roden af dit P7 projekt

ANALYSIS_DIR="${PROJECT_ROOT}/analysis/${SAMPLE}"
LOG_DIR="${ANALYSIS_DIR}/logs"
QC_DIR="${ANALYSIS_DIR}/qc"

# Full path til input filen (hvorfor lave en input fil og ikke bare brug sample file)
INPUT_FILE="${DATA_DIR}/${SAMPLE}.fastq.gz"
# Create directories
mkdir -p "${ANALYSIS_DIR}" "${LOG_DIR}" "${QC_DIR}"
LOG_FILE="${LOG_DIR}/assembly_$(date +%Y%m%d_%H%M%S).log"

log "================================================"
log "ONT Assembly Pipeline - Part 1: Assembly"
log "================================================"
log "Sample: ${SAMPLE}"
log "Genome size: ${GENOME_SIZE}"
log "CPUs: ${CPU}"
log "================================================"

# Save tool versions
VERSIONS_FILE="${ANALYSIS_DIR}/tool_versions_assembly.txt"
echo "Assembly Pipeline Run: $(date)" > "${VERSIONS_FILE}"

#####################
# 0: Initial QC with NanoPlot
#####################
log "Step 0: Initial quality control with NanoPlot"
activate_shared nanoplot_env || error_exit "Failed to activate nanoplot_env"

log "Running NanoPlot on raw reads..."
NanoPlot --fastq "${INPUT_FILE}" \
         --outdir "${QC_DIR}/nanoplot_raw" \
         --threads ${CPU} \
         --plots dot kde 2>&1 | tee -a "${LOG_FILE}" || error_exit "NanoPlot failed"

NanoPlot --version >> "${VERSIONS_FILE}" 2>&1
log "NanoPlot completed"

#####################
# 1: Filtlong - adaptive quality filtering
#####################
log "Step 1: Quality filtering with Filtlong"
activate_shared filtlong_env

FILT_FILE="${DATA_DIR}/${SAMPLE}_filt.fastq"

# More conservative: keep 95% and min length 500
filtlong --min_length 500 \
         --keep_percent 95 \
         --target_bases 500000000 \
         "${DATA_DIR}/${SAMPLE}.fastq.gz" > "${FILT_FILE}" || error_exit "Filtlong failed"

[ -f "${FILT_FILE}" ] || error_exit "Filtered file not created"

filtlong --version >> "${VERSIONS_FILE}" 2>&1
log "Filtlong completed. Output: ${FILT_FILE}"

# QC on filtered reads
conda activate nanoplot_env
NanoPlot --fastq "${FILT_FILE}" \
         --outdir "${QC_DIR}/nanoplot_filtered" \
         --threads ${CPU} 2>&1 | tee -a "${LOG_FILE}"

log "Post-filtering QC completed"

#####################
# 2: Flye - assembly
#####################
log "Step 2: Genome assembly with Flye"
activate_shared flye_env

FLYE_DIR="${ANALYSIS_DIR}/flye"

flye --nano-raw "${FILT_FILE}" \
     --genome-size ${GENOME_SIZE} \
     --out-dir "${FLYE_DIR}" \
     --threads ${CPU} \
     --iterations 3 || error_exit "Flye failed"

[ -f "${FLYE_DIR}/assembly.fasta" ] || error_exit "Assembly file not created"

flye --version >> "${VERSIONS_FILE}" 2>&1
log "Flye assembly completed"

#####################
# 3: Calculate coverage
#####################
log "Step 3: Coverage analysis"
activate_shared minimap2

minimap2 -ax map-ont -t ${CPU} \
         "${FLYE_DIR}/assembly.fasta" \
         "${FILT_FILE}" > "${ANALYSIS_DIR}/coverage.sam" || error_exit "Minimap2 failed"

activate_shared samtools
samtools view -bS "${ANALYSIS_DIR}/coverage.sam" | \
samtools sort -@ ${CPU} -o "${ANALYSIS_DIR}/coverage.bam"
samtools index "${ANALYSIS_DIR}/coverage.bam"
samtools depth "${ANALYSIS_DIR}/coverage.bam" > "${ANALYSIS_DIR}/coverage.txt"

# Calculate mean coverage
MEAN_COV=$(awk '{sum+=$3; count++} END {print sum/count}' "${ANALYSIS_DIR}/coverage.txt")
log "Mean coverage: ${MEAN_COV}x"
echo "Mean coverage: ${MEAN_COV}x" >> "${VERSIONS_FILE}"

samtools --version | head -1 >> "${VERSIONS_FILE}"
activate_shared minimap2
minimap2 --version >> "${VERSIONS_FILE}" 2>&1

#####################
# 4: Racon polishing (3 rounds)
#####################
log "Step 4: Polishing with Racon (3 iterations)"
activate_shared racon_env

CURRENT_ASSEMBLY="${FLYE_DIR}/assembly.fasta"

for i in {1..3}; do
    log "Racon iteration ${i}/3"
    
    # Map reads
    activate_shared minimap2
    minimap2 -ax map-ont -t ${CPU} \
             "${CURRENT_ASSEMBLY}" \
             "${FILT_FILE}" > "${ANALYSIS_DIR}/racon_${i}.sam" || error_exit "Minimap2 round ${i} failed"
    
    # Run Racon
    activate_shared racon_env
    racon -t ${CPU} \
          "${FILT_FILE}" \
          "${ANALYSIS_DIR}/racon_${i}.sam" \
          "${CURRENT_ASSEMBLY}" > "${ANALYSIS_DIR}/assembly_racon_${i}.fasta" || error_exit "Racon round ${i} failed"
    
    CURRENT_ASSEMBLY="${ANALYSIS_DIR}/assembly_racon_${i}.fasta"
    log "Racon iteration ${i} completed"
    
    # Cleanup intermediate SAM files
    rm "${ANALYSIS_DIR}/racon_${i}.sam"
done

racon --version >> "${VERSIONS_FILE}" 2>&1
log "Racon polishing completed (3 rounds)"

#####################
# 5: Final polishing with Medaka
#####################
log "Step 5: Final polishing with Medaka"

# Create Medaka output directory
MEDAKA_DIR="${ANALYSIS_DIR}/medaka"

# Clean previous Medaka results if they exist
if [ -d "${MEDAKA_DIR}" ]; then
    log "Removing previous Medaka results..."
    rm -rf "${MEDAKA_DIR}"
fi

# Create the directory
mkdir -p "${MEDAKA_DIR}"

# Activate Medaka environment
log "Activating Medaka environment (medaka_env)"
activate_shared medaka_env || error_exit "Failed to activate medaka_env"

# Map reads to current assembly and produce sorted BAM
BAM_FILE="${MEDAKA_DIR}/reads_mapped.bam"
log "Mapping reads to assembly for Medaka..."
minimap2 -ax map-ont -t ${CPU} "${CURRENT_ASSEMBLY}" "${FILT_FILE}" | \
samtools view -bS - | samtools sort -@ ${CPU} -o "${BAM_FILE}" || error_exit "Mapping and sorting failed"
samtools index "${BAM_FILE}" || error_exit "BAM indexing failed"
log "Reads mapped and BAM indexed"

# Run Medaka consensus
log "Running Medaka consensus..."
medaka_consensus -i "${BAM_FILE}" \
                 -d "${CURRENT_ASSEMBLY}" \
                 -o "${MEDAKA_DIR}" \
                 -t ${CPU} \
                 -m r941_min_hac_g507 2>&1 | tee -a "${LOG_FILE}" || error_exit "Medaka consensus failed"

# The consensus file is already generated by medaka_consensus
FINAL_ASSEMBLY="${MEDAKA_DIR}/consensus.fasta"

# Create a copy for easier reference
cp "${FINAL_ASSEMBLY}" "${ANALYSIS_DIR}/assembly_final.fasta" || error_exit "Failed to copy final assembly"

# Record Medaka version
medaka --version >> "${VERSIONS_FILE}" 2>&1
log "Medaka polishing completed. Output: ${FINAL_ASSEMBLY}"

#####################
# Cleanup intermediate files
#####################
log "Cleaning up intermediate files..."
rm -f "${ANALYSIS_DIR}/coverage.sam"

log "Cleanup completed"

#####################
# Create assembly summary
#####################
log "Creating assembly summary..."

SUMMARY_FILE="${ANALYSIS_DIR}/assembly_summary.txt"
cat > "${SUMMARY_FILE}" << EOF
================================================================================
ONT Assembly Pipeline - Assembly Summary
================================================================================
Sample: ${SAMPLE}
Date: $(date)
Genome Size (estimate): ${GENOME_SIZE}
Mean Coverage: ${MEAN_COV}x

Key Files:
- Raw assembly (Flye): ${FLYE_DIR}/assembly.fasta
- After Racon (3x): ${ANALYSIS_DIR}/assembly_racon_3.fasta
- Final assembly (Medaka): ${ANALYSIS_DIR}/assembly_final.fasta

Quality Control:
- Raw reads QC: ${QC_DIR}/nanoplot_raw/
- Filtered reads QC: ${QC_DIR}/nanoplot_filtered/

Logs:
- Assembly log: ${LOG_FILE}
- Tool versions: ${VERSIONS_FILE}

================================================================================
Next Steps:
Run evaluation and annotation pipeline:
  ./02_evaluation.sh ${SAMPLE}
================================================================================
EOF

cat "${SUMMARY_FILE}" | tee -a "${LOG_FILE}"

#####################
# Final statistics
#####################
log "================================================"
log "Assembly Pipeline Completed Successfully!"
log "================================================"
log "Final assembly: ${ANALYSIS_DIR}/assembly_final.fasta"
log "Total runtime: $SECONDS seconds ($((SECONDS/60)) minutes)"
log "================================================"
log ""
log "To run evaluation and annotation, execute:"
log "  ./02_evaluation.sh ${SAMPLE}"
log "================================================"
