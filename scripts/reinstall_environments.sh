#!/bin/bash
#SBATCH --job-name=fix_envs
#SBATCH --output=fix_envs_%j.log
#SBATCH --partition=rome
#SBATCH --mem=32G                 # Mamba needs good RAM to solve complex envs like AntiSMASH
#SBATCH --cpus-per-task=8         # Speed up downloads and extraction
#SBATCH --time=06:00:00           # Enough time for all envs

set -u

# 1. Initialize Conda/Mamba
# Adjust this path if your conda is in a different location
CONDA_BASE=$(dirname $(dirname $(which conda)))
source "${CONDA_BASE}/etc/profile.d/conda.sh"

# 2. Shared Environment Path
ENV_DIR="/projects/students/Bio-25-BT-7-2/shared_conda_envs"

echo "Starting Environment Repair at $(date)"
echo "Target Directory: ${ENV_DIR}"
echo "--------------------------------------------------"

# --- Helper Function ---
reinstall_env() {
    local ENV_NAME=$1
    local PACKAGES=$2
    local TARGET="${ENV_DIR}/${ENV_NAME}"

    echo "♻️  Processing: ${ENV_NAME}"
    
    # Remove old environment
    if [ -d "${TARGET}" ]; then
        echo "   Removing old directory..."
        rm -rf "${TARGET}"
    fi

    # Create new environment
    echo "   Installing packages: ${PACKAGES}"
    mamba create -p "${TARGET}" \
        -c bioconda -c conda-forge -c defaults \
        ${PACKAGES} \
        -y > /dev/null  # Hide verbose output, show errors only

    # Validation
    if [ -f "${TARGET}/bin/conda" ] || [ -f "${TARGET}/bin/${ENV_NAME%%_*}" ] || [ -d "${TARGET}/bin" ]; then
        echo "✅ Success: ${ENV_NAME}"
    else
        echo "❌ FAILED: ${ENV_NAME}"
    fi
    echo "--------------------------------------------------"
}

# --- A. DELETE UNWANTED ENVS ---
echo "🗑️  Deleting unused environments..."
rm -rf "${ENV_DIR}/gecco_env"
rm -rf "${ENV_DIR}/deepbgc_env"
# Also catch them if they were named without _env
rm -rf "${ENV_DIR}/gecco"
rm -rf "${ENV_DIR}/deepbgc"
echo "   Done."
echo "--------------------------------------------------"

# --- B. REINSTALL PIPELINE ENVS ---

# 1. Evaluation & Stats (The ones causing errors)
reinstall_env "kraken2_env" "kraken2"
reinstall_env "quast_env" "quast"
reinstall_env "busco_env" "busco=5.7.1"
reinstall_env "checkm2_env" "checkm2"
reinstall_env "bbmap_env" "bbmap"
reinstall_env "multiqc_env" "multiqc"
reinstall_env "prokka_env" "prokka"
reinstall_env "rgi_env" "rgi"  # Resistance Gene Identifier

# 2. Assembly & Filtering (Part 1 Tools)
reinstall_env "flye_env" "flye"
reinstall_env "filtlong_env" "filtlong"
reinstall_env "nanoplot_env" "nanoplot chopper"
reinstall_env "racon_env" "racon minimap2 samtools"
reinstall_env "medaka_env" "medaka minimap2 samtools"

# 3. Secondary Metabolites
reinstall_env "antismash_env" "antismash"

# 4. Utility Envs (Based on your list)
# Note: Often these are inside other envs, but we reinstall as listed
reinstall_env "minimap2" "minimap2"
reinstall_env "samtools" "samtools"

echo "=================================================="
echo "🎉 All operations finished at $(date)"