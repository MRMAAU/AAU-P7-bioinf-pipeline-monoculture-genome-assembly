#!/bin/bash

# Setup script for downstream analysis conda environments
# Location: /projects/students/Bio-25-BT-7-2/shared_conda_envs

set -e

SHARED_ENV_DIR="/projects/students/Bio-25-BT-7-2/shared_conda_envs"
mkdir -p "${SHARED_ENV_DIR}"
chmod g+rwxs "${SHARED_ENV_DIR}"

echo "========================================="
echo "Setting up Downstream Analysis Environments"
echo "Location: ${SHARED_ENV_DIR}"
echo "========================================="

############################
# 1. DeepBGC Environment
############################
echo ""
echo ">>> Creating deepbgc_env..."
mamba create -p "${SHARED_ENV_DIR}/deepbgc_env" \
    -c bioconda -c conda-forge \
    deepbgc \
    python=3.8 \
    -y

#echo ">>> Downloading DeepBGC database..."
#source activate "${SHARED_ENV_DIR}/deepbgc_env"
#deepbgc download
#conda deactivate

#echo "✅ deepbgc_env complete"

############################
# 2. Gekko Environment
############################
echo ""
echo ">>> Creating gekko_env..."
# Note: Gekko might need to be installed via pip or from source
# Adjust based on actual installation method
mamba create -p "/projects/students/Bio-25-BT-7-2/shared_conda_envs/gekko_env" \
    -c bioconda -c conda-forge \
    python=3.8 \
    scikit-learn \
    pandas \
    biopython \
    -y

# If Gekko needs pip installation:
#source activate "/projects/students/Bio-25-BT-7-2/shared_conda_envs/gekko_env"
#pip install gekko-bgc
#conda deactivate

#echo "✅ gekko_env complete"

############################
# 4. ARTS Environment
############################
echo ""
echo ">>> Creating arts_env..."
mamba create -p "/projects/students/Bio-25-BT-7-2/shared_conda_envs/arts_env" \
    -c bioconda -c conda-forge \
    arts \
    python=3.8 \
    -y

echo "✅ arts_env complete"

############################
# 5. CARD RGI Environment
############################
echo ""
echo ">>> Creating rgi_env..."
mamba create -p "/projects/students/Bio-25-BT-7-2/shared_conda_envs/rgi_env" \
    -c bioconda -c conda-forge \
    rgi \
    diamond \
    python=3.9 \
    -y

echo ">>> Downloading CARD database..."
#source activate "${SHARED_ENV_DIR}/rgi_env"

# Download CARD data
cd "/projects/students/Bio-25-BT-7-2/shared_conda_envs/"
wget https://card.mcmaster.ca/latest/data
tar -xvf data ./card.json
rgi load --card_json "$/projects/students/Bio-25-BT-7-2/shared_conda_envs/card.json" --local

# Load wildcard data for RGI BWT (optional but recommended)
wget -O wildcard_data.tar.bz2 https://card.mcmaster.ca/latest/variants
mkdir -p wildcard
tar -xjf wildcard_data.tar.bz2 -C wildcard
rgi card_annotation -i wildcard/index-for-model-sequences.txt > card_annotation.log 2>&1
rgi wildcard_annotation -i wildcard --version 3.2.7 > wildcard_annotation.log 2>&1
rgi load --card_annotation card_database_v3.2.7.fasta --wildcard_annotation wildcard_database_v3.2.7.fasta --wildcard_index wildcard/index-for-model-sequences.txt --wildcard_version 3.2.7 --local

conda deactivate

echo "✅ rgi_env complete"

############################
# Set permissions
############################
echo ""
echo ">>> Setting group permissions..."
chmod -R g+rwX "/projects/students/Bio-25-BT-7-2/shared_conda_envs"
find "/projects/students/Bio-25-BT-7-2/shared_conda_envs" -type d -exec chmod g+s {} \;

############################
# Summary
############################
echo ""
echo "========================================="
echo "Environment Setup Complete!"
echo "========================================="
echo ""
echo "Created environments:"
echo "  1. ${SHARED_ENV_DIR}/deepbgc_env"
echo "  2. ${SHARED_ENV_DIR}/antismash_env"
echo "  3. ${SHARED_ENV_DIR}/gekko_env"
echo "  4. ${SHARED_ENV_DIR}/arts_env"
echo "  5. ${SHARED_ENV_DIR}/rgi_env"
echo ""
echo "To activate an environment, use:"
echo "  conda activate ${SHARED_ENV_DIR}/[env_name]"
echo ""
echo "Or use your activate_shared_env.sh script"
echo "========================================="