# 1. Set path
BUSCO_PATH="/projects/students/Bio-25-BT-7-2/shared_conda_envs/busco_env"

# 2. Remove the corrupted environment
echo "Removing broken BUSCO environment..."
rm -rf "$BUSCO_PATH"

# 3. Reinstall using Mamba (ensures correct libglib and dependencies)
echo "Installing BUSCO with Mamba..."
mamba create -p "$BUSCO_PATH" \
    -c conda-forge -c bioconda -c defaults \
    busco=5.7.1 \
    -y