#!/bin/bash
# ONT Assembly Pipeline - Part 4: Deep Functional Annotation
# Author: BT72
# Date: $(date)
# Description: Comprehensive annotation for high-priority isolates

#En del fejl pga for nye version af filer eller noget, kig på senere
umask 002
source /projects/students/Bio-25-BT-7-2/pipeline_config.sh

set -e
set -u
set -o pipefail

######################### Configuration #######################

SAMPLE="${1:-test1}"
CPU="${SLURM_CPUS_PER_TASK:-$(nproc)}"

# Toggle analyses (set to true/false)
RUN_BAKTA="${RUN_BAKTA:-true}"
RUN_EGGNOG="${RUN_EGGNOG:-false}"
RUN_DRAM="${RUN_DRAM:-false}"  # Set to true if you want full metabolic analysis

# Paths
ANALYSIS_DIR="${PROJECT_ROOT}/analysis/${SAMPLE}"
LOG_DIR="${ANALYSIS_DIR}/logs"
LOG_FILE="${LOG_DIR}/deep_annotation_$(date +%Y%m%d_%H%M%S).log"

DEEP_ANNOTATION_DIR="${ANALYSIS_DIR}/deep_annotation"
mkdir -p "${LOG_DIR}" "${DEEP_ANNOTATION_DIR}"

VERSIONS_FILE="${ANALYSIS_DIR}/tool_versions_deep_annotation.txt"

# Input files
ASSEMBLY_FASTA="${ANALYSIS_DIR}/assembly_final.fasta"
PROKKA_FAA="${ANALYSIS_DIR}/annotation/${SAMPLE}.faa"
PROKKA_GFF="${ANALYSIS_DIR}/annotation/${SAMPLE}.gff"

# Database paths
BAKTA_DB="/databases/bakta/20240125/db"
EGGNOG_DB="/databases/eggnog/eggnog_2019-10-29"
DRAM_DB="/databases/DRAM/20241018"

# Initialize conda
CONDA_DIR=$(dirname $(dirname $(which conda)))
source "${CONDA_DIR}/etc/profile.d/conda.sh"

# Logging function
log() {
   echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Check if assembly exists
if [ ! -f "${ASSEMBLY_FASTA}" ]; then
   log "ERROR: Assembly not found at ${ASSEMBLY_FASTA}"
   log "Run 01_assembly.sh first!"
   exit 1
fi

log "================================================"
log "Deep Functional Annotation Pipeline"
log "================================================"
log "Sample: ${SAMPLE}"
log "CPUs: ${CPU}"
log "Assembly: ${ASSEMBLY_FASTA}"
log ""
log "Analysis Plan:"
log "  - Bakta: ${RUN_BAKTA}"
log "  - eggNOG-mapper: ${RUN_EGGNOG}"
log "  - DRAM: ${RUN_DRAM}"
log "================================================"

# Save tool versions
echo "Deep Annotation Pipeline - $(date)" > "${VERSIONS_FILE}"

#####################
# 1: Bakta - Comprehensive Annotation
#####################
if [ "${RUN_BAKTA}" = "true" ]; then
    log "Step 1: Running Bakta annotation"
    
    BAKTA_OUT="${DEEP_ANNOTATION_DIR}/bakta"
    BAKTA_ENV="/projects/students/Bio-25-BT-7-2/shared_conda_envs/bakta_1.10"

    if [ ! -d "${BAKTA_DB}" ]; then
        log "WARNING: Bakta database not found at ${BAKTA_DB}. Skipping Bakta."
    elif [ -d "${BAKTA_ENV}" ]; then
        log "Activating Bakta environment at ${BAKTA_ENV}..."
        conda activate "${BAKTA_ENV}"
        
        log "Running Bakta with comprehensive annotation..."
        bakta \
            --db "${BAKTA_DB}" \
            --output "${BAKTA_OUT}" \
            --prefix "${SAMPLE}" \
            --threads ${CPU} \
            --verbose \
            --skip-plot \
            --force \
            --skip-analysis amrfinder \
            "${ASSEMBLY_FASTA}" 2>&1 | tee -a "${LOG_FILE}" || log "WARNING: Bakta failed"
        
        if [ -f "${BAKTA_OUT}/${SAMPLE}.gbff" ]; then
            bakta --version >> "${VERSIONS_FILE}" 2>&1
            log "Bakta completed successfully"
            
            # Generate summary
            BAKTA_SUMMARY="${BAKTA_OUT}/bakta_summary.txt"
            {
                echo "=========================================="
                echo "Bakta Annotation Summary for ${SAMPLE}"
                echo "=========================================="
                echo ""
                if [ -f "${BAKTA_OUT}/${SAMPLE}.tsv" ]; then
                    echo "Feature counts:"
                    cut -f2 "${BAKTA_OUT}/${SAMPLE}.tsv" | tail -n +2 | sort | uniq -c | sort -rn
                    echo ""
                    echo "Total features: $(tail -n +2 ${BAKTA_OUT}/${SAMPLE}.tsv | wc -l)"
                fi
                echo ""
                echo "Key output files:"
                echo "  - GenBank: ${BAKTA_OUT}/${SAMPLE}.gbff"
                echo "  - GFF3: ${BAKTA_OUT}/${SAMPLE}.gff3"
                echo "  - Proteins: ${BAKTA_OUT}/${SAMPLE}.faa"
                echo "  - TSV summary: ${BAKTA_OUT}/${SAMPLE}.tsv"
            } > "${BAKTA_SUMMARY}"
            
            cat "${BAKTA_SUMMARY}" | tee -a "${LOG_FILE}"
        fi
        
        conda deactivate
    else
        log "WARNING: Bakta environment not found at ${BAKTA_ENV}. Skipping Bakta."
        log "To install: mamba create -p ${BAKTA_ENV} -c conda-forge -c bioconda bakta=1.10.2"
    fi
else
    log "Step 1: Bakta annotation skipped (RUN_BAKTA=false)"
fi


#####################
# 2: eggNOG-mapper - Functional Annotation
#####################

if [ "${RUN_EGGNOG}" = "true" ]; then
    log "Step 2: Running eggNOG-mapper functional annotation"
    
    EGGNOG_OUT="${DEEP_ANNOTATION_DIR}/eggnog"
    mkdir -p "${EGGNOG_OUT}"
    
    # Determine which protein file to use (prefer Bakta, fallback to Prokka)
    if [ -f "${DEEP_ANNOTATION_DIR}/bakta/${SAMPLE}.faa" ]; then
        PROTEIN_INPUT="${DEEP_ANNOTATION_DIR}/bakta/${SAMPLE}.faa"
        log "Using Bakta proteins as input"
    elif [ -f "${PROKKA_FAA}" ]; then
        PROTEIN_INPUT="${PROKKA_FAA}"
        log "Using Prokka proteins as input"
    else
        log "WARNING: No protein file found. Skipping eggNOG-mapper."
        PROTEIN_INPUT=""
    fi
    
    if [ -n "${PROTEIN_INPUT}" ] && [ ! -d "${EGGNOG_DB}" ]; then
        log "WARNING: eggNOG database not found at ${EGGNOG_DB}. Skipping eggNOG-mapper."
    elif [ -n "${PROTEIN_INPUT}" ] && conda env list | grep -q "eggnog_env"; then
        activate_shared eggnog_env
        
        log "Running eggNOG-mapper..."
        emapper.py \
            -i "${PROTEIN_INPUT}" \
            --output "${SAMPLE}_eggnog" \
            --output_dir "${EGGNOG_OUT}" \
            --data_dir "${EGGNOG_DB}" \
            --cpu ${CPU} \
            --override \
            2>&1 | tee -a "${LOG_FILE}" || log "WARNING: eggNOG-mapper failed"
        
        if [ -f "${EGGNOG_OUT}/${SAMPLE}_eggnog.emapper.annotations" ]; then
            emapper.py --version >> "${VERSIONS_FILE}" 2>&1
            log "eggNOG-mapper completed successfully"
            
            # Generate summary
            EGGNOG_SUMMARY="${EGGNOG_OUT}/eggnog_summary.txt"
            {
                echo "=========================================="
                echo "eggNOG-mapper Summary for ${SAMPLE}"
                echo "=========================================="
                echo ""
                ANNOT_FILE="${EGGNOG_OUT}/${SAMPLE}_eggnog.emapper.annotations"
                
                echo "Annotation statistics:"
                TOTAL_QUERIES=$(tail -n +5 "${ANNOT_FILE}" | grep -v "^#" | wc -l)
                ANNOTATED=$(tail -n +5 "${ANNOT_FILE}" | grep -v "^#" | cut -f7 | grep -v "^-$" | wc -l)
                
                echo "  Total proteins: ${TOTAL_QUERIES}"
                echo "  Annotated: ${ANNOTATED}"
                echo "  Annotation rate: $(awk "BEGIN {printf \"%.1f\", (${ANNOTATED}/${TOTAL_QUERIES})*100}")%"
                echo ""
                
                echo "Top 10 KEGG pathways:"
                tail -n +5 "${ANNOT_FILE}" | grep -v "^#" | cut -f12 | grep -v "^-$" | \
                    tr ',' '\n' | sed 's/ko://g' | sort | uniq -c | sort -rn | head -10
                echo ""
                
                echo "Output files:"
                echo "  - Annotations: ${ANNOT_FILE}"
                echo "  - Orthologs: ${EGGNOG_OUT}/${SAMPLE}_eggnog.emapper.seed_orthologs"
            } > "${EGGNOG_SUMMARY}"
            
            cat "${EGGNOG_SUMMARY}" | tee -a "${LOG_FILE}"
        fi
        
        conda deactivate
    else
        log "WARNING: eggNOG environment not found. Skipping eggNOG-mapper."
        log "To install: mamba create -p ${SHARED_CONDA}/eggnog_env -c bioconda eggnog-mapper"
    fi
else
    log "Step 2: eggNOG-mapper skipped (RUN_EGGNOG=false)"
fi

#####################
# 3: DRAM - Metabolic Annotation (Optional)
#####################

if [ "${RUN_DRAM}" = "true" ]; then
    log "Step 3: Running DRAM metabolic annotation"
    
    DRAM_OUT="${DEEP_ANNOTATION_DIR}/dram"
    
    if [ ! -d "${DRAM_DB}" ]; then
        log "WARNING: DRAM database not found at ${DRAM_DB}. Skipping DRAM."
    elif conda env list | grep -q "dram_env"; then
        activate_shared dram_env
        
        # DRAM needs to know where its databases are
        export DRAM_CONFIG_LOCATION="${DRAM_DB}/CONFIG"
        
        log "Running DRAM annotation..."
        DRAM.py annotate \
            -i "${ASSEMBLY_FASTA}" \
            -o "${DRAM_OUT}/annotation" \
            --threads ${CPU} \
            2>&1 | tee -a "${LOG_FILE}" || log "WARNING: DRAM annotation failed"
        
        if [ -f "${DRAM_OUT}/annotation/annotations.tsv" ]; then
            log "Running DRAM distillation..."
            DRAM.py distill \
                -i "${DRAM_OUT}/annotation/annotations.tsv" \
                -o "${DRAM_OUT}/distillation" \
                2>&1 | tee -a "${LOG_FILE}" || log "WARNING: DRAM distillation failed"
            
            DRAM.py --version >> "${VERSIONS_FILE}" 2>&1
            log "DRAM completed successfully"
            
            # Generate summary
            if [ -f "${DRAM_OUT}/distillation/metabolism_summary.xlsx" ]; then
                log "DRAM metabolic summary generated"
                log "View results: ${DRAM_OUT}/distillation/product.html"
            fi
        fi
        
        conda deactivate
    else
        log "WARNING: DRAM environment not found. Skipping DRAM."
        log "To install: mamba create -p ${SHARED_CONDA}/dram_env -c bioconda dram"
    fi
else
    log "Step 3: DRAM annotation skipped (RUN_DRAM=false)"
fi

#####################
# Generate Combined Report
#####################

log "Step 4: Generating combined annotation report"

FINAL_REPORT="${DEEP_ANNOTATION_DIR}/annotation_report.txt"

{
    echo "=========================================="
    echo "Deep Annotation Report for ${SAMPLE}"
    echo "Date: $(date)"
    echo "=========================================="
    echo ""
    
    if [ -f "${DEEP_ANNOTATION_DIR}/bakta/bakta_summary.txt" ]; then
        cat "${DEEP_ANNOTATION_DIR}/bakta/bakta_summary.txt"
        echo ""
    fi
    
    if [ -f "${DEEP_ANNOTATION_DIR}/eggnog/eggnog_summary.txt" ]; then
        cat "${DEEP_ANNOTATION_DIR}/eggnog/eggnog_summary.txt"
        echo ""
    fi
    
    if [ -d "${DEEP_ANNOTATION_DIR}/dram/distillation" ]; then
        echo "=========================================="
        echo "DRAM Metabolic Annotation"
        echo "=========================================="
        echo "Results available at: ${DEEP_ANNOTATION_DIR}/dram/distillation/"
        echo ""
    fi
    
    echo "=========================================="
    echo "All Output Files"
    echo "=========================================="
    echo ""
    
    if [ -d "${DEEP_ANNOTATION_DIR}/bakta" ]; then
        echo "Bakta Annotation:"
        echo "  - GenBank: ${DEEP_ANNOTATION_DIR}/bakta/${SAMPLE}.gbff"
        echo "  - GFF3: ${DEEP_ANNOTATION_DIR}/bakta/${SAMPLE}.gff3"
        echo "  - Proteins: ${DEEP_ANNOTATION_DIR}/bakta/${SAMPLE}.faa"
        echo "  - TSV: ${DEEP_ANNOTATION_DIR}/bakta/${SAMPLE}.tsv"
        echo ""
    fi
    
    if [ -d "${DEEP_ANNOTATION_DIR}/eggnog" ]; then
        echo "eggNOG Functional Annotation:"
        echo "  - Annotations: ${DEEP_ANNOTATION_DIR}/eggnog/${SAMPLE}_eggnog.emapper.annotations"
        echo ""
    fi
    
    if [ -d "${DEEP_ANNOTATION_DIR}/dram" ]; then
        echo "DRAM Metabolic Annotation:"
        echo "  - Annotations: ${DEEP_ANNOTATION_DIR}/dram/annotation/annotations.tsv"
        echo "  - Distillation: ${DEEP_ANNOTATION_DIR}/dram/distillation/"
        echo "  - HTML Report: ${DEEP_ANNOTATION_DIR}/dram/distillation/product.html"
        echo ""
    fi
    
    echo "=========================================="
    echo "Tool Versions"
    echo "=========================================="
    cat "${VERSIONS_FILE}"
    
} > "${FINAL_REPORT}"

cat "${FINAL_REPORT}"

log "================================================"
log "Deep Annotation Pipeline Completed!"
log "================================================"
log "Combined report: ${FINAL_REPORT}"
log "Runtime: $SECONDS seconds ($((SECONDS/60)) minutes)"
log "================================================"