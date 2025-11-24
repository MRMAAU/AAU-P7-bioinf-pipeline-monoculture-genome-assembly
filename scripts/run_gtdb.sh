#!/bin/bash
#SBATCH --job-name=gtdb_supervisor
#SBATCH --output=/projects/students/Bio-25-BT-7-2/logs/gtdb_supervisor_%j.out
#SBATCH --error=/projects/students/Bio-25-BT-7-2/logs/gtdb_supervisor_%j.err
#SBATCH --time=48:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G

# 1. Load config file (e.g., points to GTDB-Tk environment, paths, etc.)
SOURCE_CONFIG="/projects/students/Bio-25-BT-7-2/pipeline_config.sh"

if [ -f "$SOURCE_CONFIG" ]; then
    source "$SOURCE_CONFIG"
else
    echo "ERROR: Could not find config file at $SOURCE_CONFIG"
    exit 1
fi

# 2. Define samples (FASTA files or sample names)
SAMPLES=(
#"BC1-STG2023-Gr1-ISP2-14"
#"BC2-2-AGS-10-04-24-Gr15-ISP2-10"
#"BC3-AAU-BT72-ZO-071025-10NB-3"
#"BC4-SIL-28-02-2024-Gr16-BHI-19"
"BC5-HOLS2023-GR6-AC-20"
"BC6-SIL-22-01-2024-GR2-AC-18"
"BC7-AAU-BT72-LV-071025-LB-7"
"BC8-AAU-BT72-LV-071025-LB-8"
#"BC9-SKIV2023-Gr7-AC-2"
#"BC10-SIL-21-02-2024-Gr2-ISP2-4"
#"BC11-AGS-07-02-2024-GR6-10NB-5"
#"BC12-AAU-BT72-LV-071025-ISP2-12"
#"BC13-AAU-BT72-ZO-071025-PDA-13"
#"BC14-AAU-BT72-LV-071025-BHI-14"
#"BC15-AAU-BT72-ZO-071025-BHI-15"
#"BC16-HJOR2023-Gr1-AC-18"
)

# GTDB-Tk script
GTDB_SCRIPT="/projects/students/Bio-25-BT-7-2/martin_rod/taxonomy_gtdb_tk.sh"

mkdir -p "${LOG_DIR}"

echo "======================================================"
echo "          Sequential GTDB-Tk Submission"
echo "======================================================"
echo "Samples: ${#SAMPLES[@]}"
echo "Logs:    ${LOG_DIR}"
echo "======================================================"

for SAMPLE in "${SAMPLES[@]}"; do
    echo "Submitting GTDB-Tk for: ${SAMPLE}"

    JOB_ID=$(sbatch --parsable \
        --job-name="gtdb_${SAMPLE}" \
        --output="${LOG_DIR}/gtdb_${SAMPLE}_%j.out" \
        --error="${LOG_DIR}/gtdb_${SAMPLE}_%j.err" \
        --cpus-per-task=46 \
        --mem=300G \
        --time=24:00:00 \
        "${GTDB_SCRIPT}" "${SAMPLE}")

    if [ -z "$JOB_ID" ]; then
        echo "  ERROR: Submission failed for ${SAMPLE}"
        exit 1
    fi

    echo "  Submitted (Job ID: ${JOB_ID})"
    echo "  Waiting for job to finish before proceeding..."

    # ---- WAIT FOR JOB TO FINISH ----
    while squeue -j "${JOB_ID}" > /dev/null 2>&1 && \
          squeue -j "${JOB_ID}" | grep -q "${JOB_ID}"; do
        sleep 60   # check every minute
    done

    echo "  ✔ GTDB-Tk finished for ${SAMPLE}"
    echo "------------------------------------------------------"
done

echo "All samples completed!"
