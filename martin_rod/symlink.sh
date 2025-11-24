#!/bin/bash

ANALYSIS_DIR="/projects/students/Bio-25-BT-7-2/rigtig_P7/analysis"
SAMPLES=(BC1-STG2023-Gr1-ISP2-14 BC2-2-AGS-10-04-24-Gr15-ISP2-10 BC3-AAU-BT72-ZO-071025-10NB-3 BC4-SIL-28-02-2024-Gr16-BHI-19 BC5-HOLS2023-GR6-AC-20 BC6-SIL-22-01-2024-GR2-AC-18 BC7-AAU-BT72-LV-071025-LB-7 BC8-AAU-BT72-LV-071025-LB-8 BC9-SKIV2023-Gr7-AC-2 BC10-SIL-21-02-2024-Gr2-ISP2-4 BC11-AGS-07-02-2024-GR6-10NB-5 BC12-AAU-BT72-LV-071025-ISP2-12 BC13-AAU-BT72-ZO-071025-PDA-13 BC14-AAU-BT72-LV-071025-BHI-14 BC15-AAU-BT72-ZO-071025-BHI-15 BC16-HJOR2023-Gr1-AC-18)

for SAMPLE in "${SAMPLES[@]}"; do
    cd "$ANALYSIS_DIR/$SAMPLE" || continue

    # Prokka
    if [ -d annotation ] && [ ! -L prokka ]; then
        ln -s annotation prokka
    fi

    # BUSCO
    if [ -d "${SAMPLE}_BUSCO" ] && [ ! -L busco ]; then
        ln -s "${SAMPLE}_BUSCO" busco
    fi

    # QUAST
    if [ -d quast_comparison ] && [ ! -L quast ]; then
        ln -s quast_comparison quast
    fi

    # GTDB-Tk (already named correctly, but safe)
    if [ -d gtdbtk ] && [ ! -L gtdbtk_link ]; then
        ln -s gtdbtk gtdbtk_link
    fi

    # Medaka
    if [ -d medaka ] && [ ! -L medaka_link ]; then
        ln -s medaka medaka_link
    fi

    # Antismash
    if [ -d antismash ] && [ ! -L antismash_link ]; then
        ln -s antismash antismash_link
    fi

done

echo "Symlinks created. Ready for MultiQC."
