#!/bin/bash
# Shared configuration for ONT Assembly Pipeline
# Source this file in your scripts: source pipeline_config.sh

# Project paths
export PROJECT_ROOT="/projects/students/Bio-25-BT-7-2/rigtig_P7"
export SHARED_CONDA="/projects/students/Bio-25-BT-7-2/shared_conda_envs"
export SHARED_RESOURCES="/projects/students/Bio-25-BT-7-2/shared_resources"
export SCRIPT_DIR="${PROJECT_ROOT}/scripts" 
# Data paths
export DATA_DIR="${PROJECT_ROOT}/data"
export ANALYSIS_DIR="${PROJECT_ROOT}/analysis"
export LOG_DIR="${PROJECT_ROOT}/logs/${USER}"

# Shared databases
export BUSCO_DOWNLOADS="${SHARED_RESOURCES}/busco_downloads"
export KRAKEN_DB="${SHARED_RESOURCES}/kraken2_db"
export ANTISMASH_DB="${SHARED_RESOURCES}/antismash_db"
export CHECKM2DB="${SHARED_RESOURCES}/CheckM2_database/uniref100.KO.1.dmnd"
export GTDBTK_DATA="/databases/GTDB/gtdbtk_packages/GTDB-TK_release226_2025_04_11"


# Create user-specific log directory
mkdir -p "${LOG_DIR}"

# Helper function to activate shared environment
activate_shared() {
    local ENV_NAME=$1
    
    # Sanitize Python environment variables to prevent conflicts
    unset PYTHONPATH
    unset PYTHONHOME
    
    conda activate "${SHARED_CONDA}/${ENV_NAME}"
    
    # Set LD_LIBRARY_PATH for the activated environment
    export LD_LIBRARY_PATH="${SHARED_CONDA}/${ENV_NAME}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    
    # Set PERL5LIB for perl-based tools
    # 1. Standard Perl modules (Prokka, etc.)
    if [[ -d "${SHARED_CONDA}/${ENV_NAME}/lib/perl5" ]]; then
        export PERL5LIB="${SHARED_CONDA}/${ENV_NAME}/lib/perl5/site_perl:${SHARED_CONDA}/${ENV_NAME}/lib/perl5${PERL5LIB:+:$PERL5LIB}"
    fi
    
  # 2. Kraken2 standard setup
    if [[ "${ENV_NAME}" == "kraken2_env" ]]; then
        # Just in case the fresh install still puts libs in lib/perl5
        if [[ -d "${SHARED_CONDA}/${ENV_NAME}/lib/perl5" ]]; then
             export PERL5LIB="${SHARED_CONDA}/${ENV_NAME}/lib/perl5/site_perl:${SHARED_CONDA}/${ENV_NAME}/lib/perl5${PERL5LIB:+:$PERL5LIB}"
        fi
    fi
}
echo "✅ Pipeline configuration loaded"
echo "   Project: ${PROJECT_ROOT}"
echo "   Shared conda: ${SHARED_CONDA}"
echo "   Logs: ${LOG_DIR}"
