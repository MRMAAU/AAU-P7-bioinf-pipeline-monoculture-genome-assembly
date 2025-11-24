#!/bin/bash
# ONT Assembly Pipeline - Part 3: Genome Mining with antiSMASH
# Author: BT72
# Date: $(date)
umask 002
source /projects/students/Bio-25-BT-7-2/pipeline_config.sh

set -e
set -u
set -o pipefail

######################### Configuration #######################

SAMPLE="${1:-test1}"
CPU="${SLURM_CPUS_PER_TASK:-$(nproc)}"

# Paths
ANALYSIS_DIR="${PROJECT_ROOT}/analysis/${SAMPLE}"
LOG_DIR="${ANALYSIS_DIR}/logs"
LOG_FILE="${LOG_DIR}/antismash_$(date +%Y%m%d_%H%M%S).log"

ANTISMASH_DIR="${ANALYSIS_DIR}/antismash"
mkdir -p "${LOG_DIR}" "${ANTISMASH_DIR}"

VERSIONS_FILE="${ANALYSIS_DIR}/tool_versions_antismash.txt"

INPUT_GBK="${ANALYSIS_DIR}/annotation/${SAMPLE}.gbk"

# Initialize conda
CONDA_DIR=$(dirname $(dirname $(which conda)))
source "${CONDA_DIR}/etc/profile.d/conda.sh"

# Logging function
log() {
   echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Check if input files exist
if [ ! -f "${INPUT_GBK}" ]; then
   log "ERROR: Prokka GenBank file not found at ${INPUT_GBK}"
   log "Run 02_evaluation.sh first!"
   exit 1
fi

log "================================================"
log "antiSMASH Analysis - Biosynthetic Gene Cluster Detection"
log "================================================"
log "Sample: ${SAMPLE}"
log "CPUs: ${CPU}"
log "Input: ${INPUT_GBK}"
log "Output: ${ANTISMASH_DIR}"
log "================================================"

######################### antiSMASH Analysis #######################

log "Step 1: Activating antiSMASH environment"

if [ ! -d "${SHARED_CONDA}/antismash_env" ]; then
    log "ERROR: antiSMASH environment not found at ${SHARED_CONDA}/antismash_env"
    exit 1
fi

activate_shared antismash_env

# Save version info
echo "antiSMASH Analysis - $(date)" > "${VERSIONS_FILE}"
antismash --version >> "${VERSIONS_FILE}" 2>&1

log "Step 2: Running antiSMASH with comprehensive options"

antismash --cpus "${CPU}" \
          --taxon bacteria \
          --output-dir "${ANTISMASH_DIR}" \
          --genefinding-tool none \
          --databases "${ANTISMASH_DB}" \
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
          --html-title "${SAMPLE} Biosynthetic Gene Clusters" \
          "${INPUT_GBK}" 2>&1 | tee -a "${LOG_FILE}"

# Check success
if [ -f "${ANTISMASH_DIR}/index.html" ]; then
    log "antiSMASH completed successfully"
    
    # Parse and summarize results
    log "Step 3: Parsing antiSMASH results"
    
    SUMMARY_FILE="${ANTISMASH_DIR}/bgc_summary.txt"
    
    {
        echo "=========================================="
        echo "antiSMASH BGC Summary for ${SAMPLE}"
        echo "Date: $(date)"
        echo "=========================================="
        echo ""
        
        # Count BGCs by type from JSON file
        if [ -f "${ANTISMASH_DIR}/${SAMPLE}.json" ]; then
            echo "Biosynthetic Gene Clusters Detected:"
            grep -o '"product": "[^"]*"' "${ANTISMASH_DIR}/${SAMPLE}.json" 2>/dev/null | \
                cut -d'"' -f4 | sort | uniq -c | sort -rn || echo "  Could not parse BGC types"
            echo ""
            
            TOTAL_BGCS=$(grep -o '"product": "[^"]*"' "${ANTISMASH_DIR}/${SAMPLE}.json" 2>/dev/null | wc -l)
            echo "Total BGCs found: ${TOTAL_BGCS}"
        else
            echo "JSON file not found, checking for alternative output files..."
            # Check for GBK file instead
            if [ -f "${ANTISMASH_DIR}/${SAMPLE}.gbk" ]; then
                echo "GenBank file found: ${ANTISMASH_DIR}/${SAMPLE}.gbk"
            fi
        fi
        
        echo ""
        echo "Key Files:"
        echo "  - Interactive report: ${ANTISMASH_DIR}/index.html"
        if [ -f "${ANTISMASH_DIR}/${SAMPLE}.gbk" ]; then
            echo "  - GenBank with clusters: ${ANTISMASH_DIR}/${SAMPLE}.gbk"
        fi
        if [ -f "${ANTISMASH_DIR}/${SAMPLE}.json" ]; then
            echo "  - JSON data: ${ANTISMASH_DIR}/${SAMPLE}.json"
        fi
        if [ -d "${ANTISMASH_DIR}/knownclusterblast" ]; then
            echo "  - Cluster predictions: ${ANTISMASH_DIR}/knownclusterblast/"
        fi
        echo ""
        
        # List interesting cluster types (with error handling)
        if [ -f "${ANTISMASH_DIR}/${SAMPLE}.json" ]; then
            echo "High-Priority Clusters (potential antibiotics):"
            PRIORITY_COUNT=$(grep -o '"product": "[^"]*"' "${ANTISMASH_DIR}/${SAMPLE}.json" 2>/dev/null | \
                cut -d'"' -f4 | grep -iE 'NRPS|PKS|RiPP|terpene|lantipeptide|thiopeptide|glycopeptide' | wc -l)
            
            if [ "${PRIORITY_COUNT}" -gt 0 ]; then
                grep -o '"product": "[^"]*"' "${ANTISMASH_DIR}/${SAMPLE}.json" | \
                    cut -d'"' -f4 | grep -iE 'NRPS|PKS|RiPP|terpene|lantipeptide|thiopeptide|glycopeptide' | \
                    sort | uniq -c
            else
                echo "  None of the typical antibiotic types detected"
            fi
        fi
        
    } > "${SUMMARY_FILE}" 2>&1
    
    cat "${SUMMARY_FILE}" | tee -a "${LOG_FILE}"
    
    log "Results summary saved to: ${SUMMARY_FILE}"
    log "View interactive HTML report: ${ANTISMASH_DIR}/index.html"
    
else
    log "ERROR: antiSMASH did not complete successfully - no output HTML found"
    exit 1
fi

conda deactivate

log "================================================"
log "antiSMASH Analysis Completed!"
log "================================================"
log "Runtime: $SECONDS seconds ($((SECONDS/60)) minutes)"
log "================================================"