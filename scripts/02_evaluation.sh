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

#####################
# 1: Kraken2 - Contamination check
#####################
log "Step 1: Contamination screening with Kraken2"
activate_shared kraken2_env || { log "WARNING: Kraken2 skipped"; }


kraken2 --db ${KRAKEN_DB} \
        --threads ${CPU} \
        --report "${ANALYSIS_DIR}/kraken2_report.txt" \
        "${BASE_DIR}/data/${SAMPLE}_filt.fastq" 2>&1 | tee -a "${LOG_FILE}"

log "Kraken2 completed"

#####################
# 2: QUAST - Assembly evaluation
#####################
log "Step 2: Assembly evaluation with QUAST"

if conda env list | grep -q "quast_env"; then
    activate_shared quast_env
    
    # Collect all assemblies for comparison
    ASSEMBLIES=""
    LABELS=""
    
    FLYE_DIR="${ANALYSIS_DIR}/flye"
    
    if [ -f "${FLYE_DIR}/assembly.fasta" ]; then
        ASSEMBLIES="${ASSEMBLIES} ${FLYE_DIR}/assembly.fasta"
        LABELS="${LABELS}Flye,"
    fi
    
    if [ -f "${ANALYSIS_DIR}/assembly_racon_3.fasta" ]; then
        ASSEMBLIES="${ASSEMBLIES} ${ANALYSIS_DIR}/assembly_racon_3.fasta"
        LABELS="${LABELS}Racon_3x,"
    fi
    
    if [ -f "${ANALYSIS_DIR}/assembly_final.fasta" ]; then
        ASSEMBLIES="${ASSEMBLIES} ${ANALYSIS_DIR}/assembly_final.fasta"
        LABELS="${LABELS}Medaka_final"
    fi
    
    if [ -n "${ASSEMBLIES}" ]; then
        quast.py -o "${ANALYSIS_DIR}/quast_comparison" \
                 --threads ${CPU} \
                 --min-contig 500 \
                 -l "${LABELS}" \
                 ${ASSEMBLIES} 2>&1 | tee -a "${LOG_FILE}" || log_warning "QUAST failed"
        
        quast.py --version >> "${VERSIONS_FILE}" 2>&1
        log "QUAST completed"
    else
        log_warning "No assembly files found for QUAST evaluation"
    fi
else
    log_warning "QUAST environment not found. Skipping QUAST evaluation."
fi

#####################
# 3: BUSCO - Genome completeness
#####################
log "Step 3: Genome completeness with BUSCO (Fixed)"

# Konfiguration
BUSCO_LINEAGE="bacteria_odb10"
# VIGTIGT: Denne mappe SKAL indeholde 'lineages' og 'datasets' mapperne
BUSCO_OUT_NAME="${SAMPLE}_BUSCO"

if conda env list | grep -q "busco_env"; then
    log "Activating busco_env..."
    activate_shared busco_env
    busco --version >> "${VERSIONS_FILE}" 2>&1
    
    # Tjek om lineage-datasættet findes lokalt
    if [ -d "${BUSCO_DOWNLOADS}/lineages/${BUSCO_LINEAGE}" ]; then
        log "Running BUSCO analysis offline..."
        
        # BUSCO FIX: Udskift --datadir med --download_path for nyere versioner
        busco -i "${ANALYSIS_DIR}/assembly_final.fasta" \
              -l ${BUSCO_LINEAGE} \
              -o "${BUSCO_OUT_NAME}" \
              --out_path "${ANALYSIS_DIR}" \
              -m genome \
              -c ${CPU} \
              --offline \
              --download_path "${BUSCO_DOWNLOADS}" \
              -f 2>&1 | tee -a "${LOG_FILE}" || log_warning "BUSCO analysis failed!"

        # Tjek for succes baseret på mappe-eksistens
        if [ -d "${ANALYSIS_DIR}/${BUSCO_OUT_NAME}" ]; then
            log "BUSCO analysis completed successfully."
            log "Result directory: ${ANALYSIS_DIR}/${BUSCO_OUT_NAME}"
        else
             log_warning "BUSCO analysis failed or did not produce output directory. Check the full log (${LOG_FILE})."
        fi
        
    else
        log_warning "BUSCO lineage dataset '${BUSCO_LINEAGE}' not found locally in ${BUSCO_DOWNLOADS}/lineages."
        log "INFO: Please download the dataset."
    fi
    
    conda deactivate

else
    log_warning "BUSCO environment (busco_env) not found. Skipping BUSCO analysis."
fi

#####################
# 4: Prokka - Gene annotation
#####################
log "Step 4: Gene annotation with Prokka"

if conda env list | grep -q "prokka_env"; then
    activate_shared prokka_env
    
    prokka --outdir "${ANALYSIS_DIR}/annotation" \
           --prefix ${SAMPLE} \
           --cpus ${CPU} \
           --kingdom Bacteria \
           --force \
           "${ANALYSIS_DIR}/assembly_final.fasta" 2>&1 | tee -a "${LOG_FILE}" || log_warning "Prokka failed"
    
    if [ -d "${ANALYSIS_DIR}/annotation" ]; then
        prokka --version >> "${VERSIONS_FILE}" 2>&1
        log "Prokka annotation completed"
    fi
else
    log_warning "Prokka environment not found. Skipping gene annotation."
fi

#####################
# 5: Assembly statistics
#####################
log "Step 5: Generating assembly statistics"

if conda env list | grep -q "bbmap_env"; then
    activate_shared bbmap_env
    stats.sh in="${ANALYSIS_DIR}/assembly_final.fasta" > "${ANALYSIS_DIR}/assembly_stats.txt" 2>&1
    log "Assembly statistics generated with BBMap"
else
    log_warning "BBMap not available, using basic stats"
    # Basic stats without BBMap
    {
        echo "Assembly: ${ANALYSIS_DIR}/assembly_final.fasta"
        echo "Number of contigs: $(grep -c '>' ${ANALYSIS_DIR}/assembly_final.fasta)"
        echo "Total length: $(grep -v '>' ${ANALYSIS_DIR}/assembly_final.fasta | tr -d '\n' | wc -c)"
    } > "${ANALYSIS_DIR}/assembly_stats.txt"
fi

log "Assembly statistics completed"


#####################
# 6: CheckM2 - Quality Assessment
#####################
log "Step 6: CheckM2 Quality Assessment"

CHECKM2_OUT="${ANALYSIS_DIR}/checkm2"

if [ ! -f "${CHECKM2DB}" ]; then
    log_warning "CheckM2 database not found at ${CHECKM2DB}. Skipping CheckM2."
elif conda env list | grep -q "checkm2_env"; then
    activate_shared checkm2_env
    
    log "Running CheckM2..."
    checkm2 predict \
        --threads ${CPU} \
        --input "${ANALYSIS_DIR}/assembly_final.fasta" \
        --output-directory "${CHECKM2_OUT}" \
        --database_path "${CHECKM2DB}" \
        --force \
        2>&1 | tee -a "${LOG_FILE}" || log_warning "CheckM2 failed"
        
    if [ -f "${CHECKM2_OUT}/quality_report.tsv" ]; then
        checkm2 --version >> "${VERSIONS_FILE}" 2>&1
        log "CheckM2 completed"
    fi
else
    log_warning "CheckM2 environment not found. Skipping CheckM2."
fi

#####################
# 7: AMRFinderPlus - Antimicrobial Resistance Detection
#####################
log "Step 7: Antimicrobial resistance detection with AMRFinderPlus"

AMRFINDER_OUT="${ANALYSIS_DIR}/amrfinderplus"
mkdir -p "${AMRFINDER_OUT}"

if conda env list | grep -q "amrfinderplus_env"; then
    activate_shared amrfinderplus_env
    
    log "Running AMRFinderPlus on nucleotide sequences..."
    amrfinder \
        --nucleotide "${ANALYSIS_DIR}/assembly_final.fasta" \
        --threads ${CPU} \
        --output "${AMRFINDER_OUT}/amr_results.tsv" \
        --plus \
        2>&1 | tee -a "${LOG_FILE}" || log_warning "AMRFinderPlus failed"
    
    # Also run on protein sequences if Prokka was successful
    if [ -f "${ANALYSIS_DIR}/annotation/${SAMPLE}.faa" ]; then
        log "Running AMRFinderPlus on protein sequences..."
        amrfinder \
            --protein "${ANALYSIS_DIR}/annotation/${SAMPLE}.faa" \
            --threads ${CPU} \
            --output "${AMRFINDER_OUT}/amr_results_proteins.tsv" \
            --plus \
            2>&1 | tee -a "${LOG_FILE}" || log_warning "AMRFinderPlus protein analysis failed"
    fi
        
    if [ -f "${AMRFINDER_OUT}/amr_results.tsv" ]; then
        amrfinder --version >> "${VERSIONS_FILE}" 2>&1
        amrfinder --database_version >> "${VERSIONS_FILE}" 2>&1
        
        # Count findings
        AMR_GENES=$(tail -n +2 "${AMRFINDER_OUT}/amr_results.tsv" | wc -l)
        log "AMRFinderPlus completed: Found ${AMR_GENES} AMR/virulence genes"
    fi
else
    log_warning "AMRFinderPlus environment not found. Skipping AMR detection."
fi

#####################
# 7: MultiQC report
#####################
log "Step 7: Generating MultiQC report"

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



#####################
# Generate final report
#####################
log "Generating final evaluation report..."

REPORT_FILE="${ANALYSIS_DIR}/evaluation_report.txt"
cat > "${REPORT_FILE}" << EOF
================================================================================
ONT Assembly Pipeline - Evaluation Report
================================================================================
Sample: ${SAMPLE}
Date: $(date)

Assembly File: ${ANALYSIS_DIR}/assembly_final.fasta

================================================================================
RESULTS SUMMARY
================================================================================

EOF

if [ -f "${CHECKM2_OUT}/quality_report.tsv" ]; then
    echo "CHECKM2 QUALITY:" >> "${REPORT_FILE}"
    # Print header and data row neatly
    column -t -s $'\t' "${CHECKM2_OUT}/quality_report.tsv" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
fi


# Add assembly statistics
if [ -f "${ANALYSIS_DIR}/assembly_stats.txt" ]; then
    echo "ASSEMBLY STATISTICS:" >> "${REPORT_FILE}"
    cat "${ANALYSIS_DIR}/assembly_stats.txt" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
fi

# Add QUAST results
if [ -f "${ANALYSIS_DIR}/quast_comparison/report.txt" ]; then
    echo "QUAST ASSEMBLY QUALITY METRICS:" >> "${REPORT_FILE}"
    head -30 "${ANALYSIS_DIR}/quast_comparison/report.txt" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
fi

# Add BUSCO results
if ls "${ANALYSIS_DIR}/${SAMPLE}_BUSCO/short_summary"*.txt 1> /dev/null 2>&1; then
    echo "BUSCO COMPLETENESS:" >> "${REPORT_FILE}"
    grep "C:" "${ANALYSIS_DIR}/${SAMPLE}_BUSCO/short_summary"*.txt >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
fi

# Add Kraken2 top hits
if [ -f "${ANALYSIS_DIR}/kraken2_assembly_report.txt" ]; then
    echo "KRAKEN2 TAXONOMY (Top 10 species):" >> "${REPORT_FILE}"
    grep -P "\tS\t" "${ANALYSIS_DIR}/kraken2_assembly_report.txt" | sort -k1 -nr | head -10 >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
fi

# Add Prokka summary
if [ -f "${ANALYSIS_DIR}/annotation/${SAMPLE}.txt" ]; then
    echo "PROKKA ANNOTATION SUMMARY:" >> "${REPORT_FILE}"
    cat "${ANALYSIS_DIR}/annotation/${SAMPLE}.txt" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
fi

# Add AMRFinderPlus results
if [ -f "${AMRFINDER_OUT}/amr_results.tsv" ]; then
    echo "AMRFINDERPLUS - ANTIMICROBIAL RESISTANCE:" >> "${REPORT_FILE}"
    AMR_COUNT=$(tail -n +2 "${AMRFINDER_OUT}/amr_results.tsv" | wc -l)
    echo "Total AMR/virulence genes found: ${AMR_COUNT}" >> "${REPORT_FILE}"
    if [ ${AMR_COUNT} -gt 0 ]; then
        echo "" >> "${REPORT_FILE}"
        echo "Top findings:" >> "${REPORT_FILE}"
        head -20 "${AMRFINDER_OUT}/amr_results.tsv" | column -t -s $'\t' >> "${REPORT_FILE}"
    fi
    echo "" >> "${REPORT_FILE}"
fi

cat >> "${REPORT_FILE}" << EOF
================================================================================
OUTPUT FILES
================================================================================

Quality Control:
  - CheckM2 report: ${CHECKM2_OUT}/quality_report.tsv
  - QUAST report: ${ANALYSIS_DIR}/quast_comparison/
  - BUSCO results: ${ANALYSIS_DIR}/${SAMPLE}_BUSCO/
  - MultiQC report: ${ANALYSIS_DIR}/multiqc_report/

Contamination:
  - Kraken2 reports: ${ANALYSIS_DIR}/kraken2_*_report.txt

Annotation:
  - Prokka output: ${ANALYSIS_DIR}/annotation/
  - GenBank file: ${ANALYSIS_DIR}/annotation/${SAMPLE}.gbk
  - GFF file: ${ANALYSIS_DIR}/annotation/${SAMPLE}.gff
  - Protein sequences: ${ANALYSIS_DIR}/annotation/${SAMPLE}.faa

Antimicrobial Resistance:
  - AMRFinderPlus results: ${AMRFINDER_OUT}/amr_results.tsv
  - Protein analysis: ${AMRFINDER_OUT}/amr_results_proteins.tsv

Logs:
  - Evaluation log: ${LOG_FILE}
  - Tool versions: ${VERSIONS_FILE}

================================================================================
EOF

cat "${REPORT_FILE}"

#####################
# Summary
#####################
log "================================================"
log "Evaluation Pipeline Completed!"
log "================================================"
log "Key outputs:"
log "  - Evaluation report: ${REPORT_FILE}"
log "  - QUAST report: ${ANALYSIS_DIR}/quast_comparison/"
if [ -d "${ANALYSIS_DIR}/${SAMPLE}_BUSCO" ]; then
    log "  - BUSCO results: ${ANALYSIS_DIR}/${SAMPLE}_BUSCO/"
fi
if [ -d "${ANALYSIS_DIR}/annotation" ]; then
    log "  - Annotation: ${ANALYSIS_DIR}/annotation/"
fi
if [ -d "${ANALYSIS_DIR}/multiqc_report" ]; then
    log "  - MultiQC report: ${ANALYSIS_DIR}/multiqc_report/"
fi
log "  - Evaluation log: ${LOG_FILE}"
log "================================================"
log "Total runtime: $SECONDS seconds ($((SECONDS/60)) minutes)"
log "================================================"

# Print key statistics to console
if [ -f "${ANALYSIS_DIR}/assembly_stats.txt" ]; then
    log ""
    log "Assembly Statistics:"
    cat "${ANALYSIS_DIR}/assembly_stats.txt" | tee -a "${LOG_FILE}"
fi

if ls "${ANALYSIS_DIR}/${SAMPLE}_BUSCO/short_summary"*.txt 1> /dev/null 2>&1; then
    log ""
    log "BUSCO Summary:"
    grep "C:" "${ANALYSIS_DIR}/${SAMPLE}_BUSCO/short_summary"*.txt | tee -a "${LOG_FILE}"
fi

log ""
log "Evaluation pipeline finished at $(date)"