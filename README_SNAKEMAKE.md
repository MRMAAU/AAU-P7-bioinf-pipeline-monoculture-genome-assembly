# Snakemake Pipeline for ONT Genome Assembly

This repository contains a Snakemake pipeline for Oxford Nanopore Technologies (ONT) genome assembly, converted from the original shell scripts.

## Prerequisites

-   `snakemake` must be installed.
-   Access to shared Conda environments and resources as defined in `config.yaml`.

## Usage

1.  **Configure the pipeline:**
    Edit `config.yaml` to specify your sample names and any path adjustments.

    ```yaml
    samples:
      - "PBI54877.barcode01"
      - "AnotherSample"
    ```

2.  **Run the pipeline:**

    To run locally (dry-run):
    ```bash
    snakemake -n
    ```

    To run locally with 8 cores:
    ```bash
    snakemake --cores 8
    ```

    To run on SLURM (if configured with slurm profile):
    ```bash
    snakemake --profile slurm
    ```

## Pipeline Steps

1.  **QC & Filtering:** NanoPlot (raw), Filtlong, NanoPlot (filtered).
2.  **Assembly:** Flye.
3.  **Polishing:** Racon (3 rounds), Medaka.
4.  **Evaluation:**
    -   Kraken2 (contamination)
    -   QUAST (assembly metrics)
    -   BUSCO (completeness)
    -   Prokka (annotation)
    -   CheckM2 (quality)
    -   AMRFinderPlus (resistance genes)
    -   MultiQC (aggregated report)

## Output

Outputs are stored in `analysis/{sample}/`.
Key files:
-   `assembly_final.fasta`: Final polished assembly.
-   `evaluation_report.txt`: Summary of evaluation metrics.
-   `multiqc_report/multiqc_report.html`: Interactive QC report.
