#!/bin/bash
# Usage: ./run_final_pipeline.sh
# Author: BT72

# 1. LOAD CONFIGURATION
# This must point to the absolute path of your config file
SOURCE_CONFIG="/projects/students/Bio-25-BT-7-2/pipeline_config.sh"



if [ -f "$SOURCE_CONFIG" ]; then
    source "$SOURCE_CONFIG"
else
    echo "ERROR: Could not find pipeline_config.sh at $SOURCE_CONFIG"
    exit 1
fi

# 2. DEFINE SAMPLES
SAMPLES=(
 "BC1-STG2023-Gr1-ISP2-14"
 "BC2-2-AGS-10-04-24-Gr15-ISP2-10" 
 "BC3-AAU-BT72-ZO-071025-10NB-3"
 "BC4-SIL-28-02-2024-Gr16-BHI-19"
 "BC5-HOLS2023-GR6-AC-20"
 "BC6-SIL-22-01-2024-GR2-AC-18"
 "BC7-AAU-BT72-LV-071025-LB-7"
 "BC8-AAU-BT72-LV-071025-LB-8"
 "BC9-SKIV2023-Gr7-AC-2"
 "BC10-SIL-21-02-2024-Gr2-ISP2-4"
 "BC11-AGS-07-02-2024-GR6-10NB-5"
 "BC12-AAU-BT72-LV-071025-ISP2-12"
 "BC13-AAU-BT72-ZO-071025-PDA-13"
 "BC14-AAU-BT72-LV-071025-BHI-14"
 "BC15-AAU-BT72-ZO-071025-BHI-15"
 "BC16-HJOR2023-Gr1-AC-18"
) 




# 3. PREPARE DIRECTORIES
mkdir -p "${LOG_DIR}"

echo "======================================================"
echo "      Multiqc Submission"
echo "======================================================"
echo "Project Root: ${PROJECT_ROOT}"
echo "Script Dir:   ${SCRIPT_DIR}"
echo "Logs:         ${LOG_DIR}"
echo "Samples:      ${#SAMPLES[@]}"
echo "======================================================"

# Verify scripts exist before starting
if [ ! -f "${SCRIPT_DIR}/01_assembly.sh" ]; then
    echo "ERROR: Cannot find scripts in ${SCRIPT_DIR}"
    echo "Check that SCRIPT_DIR is correct in pipeline_config.sh"
    exit 1
fi

# 4. SUBMISSION LOOP
for SAMPLE in "${SAMPLES[@]}"; do
    echo "Processing sample: ${SAMPLE}"

    # --- JOB 1: ASSEMBLY ---
    ID_ASM=$(sbatch --parsable \
        --job-name="multiqc_${SAMPLE}" \
        --output="${LOG_DIR}/multiqc_${SAMPLE}_%j.out" \
        --error="${LOG_DIR}/multiqc_${SAMPLE}_%j.err" \
        --cpus-per-task=4 \
        --mem=4G \
        --time=00:20:00 \
        "${SCRIPT_DIR}/multiqc.sh" "${SAMPLE}" "5m")

    if [ -z "${ID_ASM}" ]; then
        echo "  ERROR: multiqc submission failed. Stopping for ${SAMPLE}."
        continue
    fi
    echo "  > [1/3] MultiQC submitted   (Job ID: $ID_ASM)"
done

echo "Done! Monitor your jobs with: squeue -u $USER"