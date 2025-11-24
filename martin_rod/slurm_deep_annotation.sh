#!/bin/bash
#SBATCH --job-name=deep_annot
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=3:00:00
#SBATCH --output=logs/deep_annotation_%j.out

# For your top 5 samples
for SAMPLE in sample_01 sample_05 sample_12 sample_15 sample_17; do
    ./04_deep_annotation.sh ${SAMPLE}
done


mamba create -p /projects/students/Bio-25-BT-7-2/shared_conda_envs/bakta_env -c conda-forge -c bioconda bakta

# eggNOG-mapper
mamba create -p /projects/students/Bio-25-BT-7-2/shared_conda_envs/eggnog_env -c bioconda eggnog-mapper

# DRAM (optional)
mamba create -p /projects/students/Bio-25-BT-7-2/shared_conda_envs/dram_env -c bioconda dram