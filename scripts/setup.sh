#!/bin/bash
# Setup Shared Conda Environments for ONT Assembly Pipeline
# For collaborative work on HPC
# Author: Martin & Gemini (Enhanced)
# Usage: Run ONCE by one team member to setup shared environments

set -e
set -u
set -o pipefail

echo "================================================"
echo "🚀 ONT Pipeline - Shared Environment Setup"
echo "================================================"
echo ""

# --- Configuration ---
PROJECT_ROOT="/projects/students/Bio-25-BT-7-2"
SHARED_CONDA="${PROJECT_ROOT}/shared_conda_envs"
SHARED_RESOURCES="${PROJECT_ROOT}/shared_resources"
CHANNELS="-c conda-forge -c bioconda -c defaults"

# Create directories
mkdir -p "${SHARED_CONDA}"
mkdir -p "${SHARED_RESOURCES}"

echo "📁 Shared environments will be installed in:"
echo "   ${SHARED_CONDA}"
echo ""
echo "📁 Shared resources (BUSCO, Kraken2 DBs) will be stored in:"
echo "   ${SHARED_RESOURCES}"
echo ""

# Check if mamba is available
if ! command -v mamba &> /dev/null; then
    echo "⚠️  Mamba not found. Installing mamba first..."
    conda install mamba -n base -c conda-forge -y
fi

echo "✅ Using mamba for fast package installation"
echo ""

# Function to create shared environment
setup_shared_env() {
    local ENV_NAME=$1
    local PACKAGE_LIST=$2
    local ENV_PATH="${SHARED_CONDA}/${ENV_NAME}"
    
    echo "================================================"
    echo "🔧 Setting up ${ENV_NAME}..."
    echo "================================================"
    
    if [ -d "${ENV_PATH}" ]; then
        echo "⚠️  Environment already exists: ${ENV_PATH}"
        echo "   Skipping... (remove directory to reinstall)"
        echo ""
        return 0
    fi
    
    # Create environment with mamba
    mamba create --prefix "${ENV_PATH}" ${PACKAGE_LIST} ${CHANNELS} -y || {
        echo "🚨 ERROR: Failed to create environment ${ENV_NAME}"
        echo "   Cleaning up partial installation..."
        rm -rf "${ENV_PATH}"
        exit 1
    }
    
    echo "✅ ${ENV_NAME} installed successfully"
    echo "   Location: ${ENV_PATH}"
    echo ""
}

# --- Install All Environments ---

echo "Starting installation of all pipeline environments..."
echo "This will take 15-30 minutes depending on network speed."
echo ""

# 1. Quality Control
setup_shared_env "nanoplot_env" "nanoplot"

# 2. Read Filtering
setup_shared_env "filtlong_env" "filtlong"

# 3. Assembly
setup_shared_env "flye_env" "flye"

# 4. Mapping Tools
setup_shared_env "minimap2" "minimap2"
setup_shared_env "samtools" "samtools"

# 5. Polishing
setup_shared_env "racon_env" "racon"
setup_shared_env "medaka_env" "medaka"

# 6. Contamination & Taxonomy
setup_shared_env "kraken2_env" "kraken2"

# 7. Assembly Evaluation
setup_shared_env "quast_env" "quast"
setup_shared_env "busco_env" "busco"

# 8. Annotation
setup_shared_env "prokka_env" "prokka"

# 9. Secondary Metabolite Mining
setup_shared_env "antismash_env" "antismash"

# 10. Statistics & Reporting
setup_shared_env "bbmap_env" "bbmap"
setup_shared_env "multiqc_env" "multiqc"

# --- Set Permissions ---
echo "================================================"
echo "🔒 Setting group permissions..."
echo "================================================"

# Specific group for Bio HPC
BIO_GROUP="bio_server_users@bio.aau.dk"
echo "Setting group to: ${BIO_GROUP}"

# Set group ownership and permissions
echo "Setting group ownership on shared environments..."
chgrp -R "${BIO_GROUP}" "${SHARED_CONDA}" 2>&1 | grep -v "Operation not permitted" || true
chmod -R g+rwX "${SHARED_CONDA}" 2>&1 | grep -v "Operation not permitted" || true

echo "Setting group ownership on shared resources..."
chgrp -R "${BIO_GROUP}" "${SHARED_RESOURCES}" 2>&1 | grep -v "Operation not permitted" || true
chmod -R g+rwX "${SHARED_RESOURCES}" 2>&1 | grep -v "Operation not permitted" || true

# Set setgid bit for new files to inherit group
echo "Setting setgid bit on directories..."
find "${SHARED_CONDA}" -type d -exec chmod g+s {} \; 2>&1 | grep -v "Operation not permitted" || true
find "${SHARED_RESOURCES}" -type d -exec chmod g+s {} \; 2>&1 | grep -v "Operation not permitted" || true

echo "✅ Permissions configured for group: ${BIO_GROUP}"
echo ""

# Verify permissions
echo "Verifying permissions:"
ls -la "${SHARED_CONDA}" | head -5
echo ""

# --- Create Helper Script ---
HELPER_SCRIPT="${PROJECT_ROOT}/activate_shared_env.sh"

cat > "${HELPER_SCRIPT}" << 'HELPER_EOF'
#!/bin/bash
# Helper script to activate shared environments
# Usage: source activate_shared_env.sh <env_name>

SHARED_CONDA="/projects/students/Bio-25-BT-7-2/P7/shared_conda_envs"

if [ $# -eq 0 ]; then
    echo "Usage: source activate_shared_env.sh <environment_name>"
    echo ""
    echo "Available environments:"
    ls -1 "${SHARED_CONDA}" 2>/dev/null || echo "No environments found"
    return 1
fi

ENV_NAME=$1
ENV_PATH="${SHARED_CONDA}/${ENV_NAME}"

if [ -d "${ENV_PATH}" ]; then
    conda activate "${ENV_PATH}"
    echo "✅ Activated: ${ENV_NAME}"
else
    echo "❌ Environment not found: ${ENV_NAME}"
    echo "Available environments:"
    ls -1 "${SHARED_CONDA}"
    return 1
fi
HELPER_EOF

chmod +x "${HELPER_SCRIPT}"

echo "📝 Created helper script: ${HELPER_SCRIPT}"
echo ""

# --- Create Configuration Template ---
CONFIG_FILE="${PROJECT_ROOT}/pipeline_config.sh"

cat > "${CONFIG_FILE}" << 'CONFIG_EOF'
#!/bin/bash
# Shared configuration for ONT Assembly Pipeline
# Source this file in your scripts: source pipeline_config.sh

# Project paths
export PROJECT_ROOT="/projects/students/Bio-25-BT-7-2/P7"
export SHARED_CONDA="${PROJECT_ROOT}/shared_conda_envs"
export SHARED_RESOURCES="${PROJECT_ROOT}/shared_resources"

# Data paths
export DATA_DIR="${PROJECT_ROOT}/data"
export ANALYSIS_DIR="${PROJECT_ROOT}/analysis"
export LOG_DIR="${PROJECT_ROOT}/logs/${USER}"

# Shared databases
export BUSCO_DOWNLOADS="${SHARED_RESOURCES}/busco_downloads"
export KRAKEN_DB="${SHARED_RESOURCES}/kraken2_db"

# Create user-specific log directory
mkdir -p "${LOG_DIR}"

# Helper function to activate shared environment
activate_shared() {
    local ENV_NAME=$1
    conda activate "${SHARED_CONDA}/${ENV_NAME}"
}

echo "✅ Pipeline configuration loaded"
echo "   Project: ${PROJECT_ROOT}"
echo "   Logs: ${LOG_DIR}"
CONFIG_EOF

chmod +x "${CONFIG_FILE}"

echo "📝 Created configuration file: ${CONFIG_FILE}"
echo ""

# --- Summary ---
echo "================================================"
echo "🎉 SETUP COMPLETE!"
echo "================================================"
echo ""
echo "✅ All environments installed in: ${SHARED_CONDA}"
echo ""
echo "📋 How to use:"
echo ""
echo "1. In your scripts, add at the top:"
echo "   source ${PROJECT_ROOT}/pipeline_config.sh"
echo "   activate_shared flye_env"
echo ""
echo "2. Or activate manually:"
echo "   conda activate ${SHARED_CONDA}/flye_env"
echo ""
echo "3. List all environments:"
echo "   ls ${SHARED_CONDA}/"
echo ""
echo "📦 Installed environments:"
ls -1 "${SHARED_CONDA}" | sed 's/^/   - /'
echo ""
echo "🔄 Next steps:"
echo "   1. Download BUSCO dataset (if needed):"
echo "      conda activate ${SHARED_CONDA}/busco_env"
echo "      busco --download bacteria_odb10"
echo "      mv ~/.local/share/busco/lineages ${SHARED_RESOURCES}/busco_downloads"
echo ""
echo "   2. Setup Kraken2 database (optional):"
echo "      mkdir -p ${SHARED_RESOURCES}/kraken2_db"
echo "      # Download and extract database there"
echo ""
echo "   3. Update your pipeline scripts to use shared environments"
echo ""
echo "================================================"
echo "Total installation time: $SECONDS seconds ($((SECONDS/60)) min)"
echo "================================================"