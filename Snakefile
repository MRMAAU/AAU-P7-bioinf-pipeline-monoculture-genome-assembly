configfile: "config.yaml"

import os

# Helper to activate shared environments
def get_env_cmd(env_name):
    shared_conda = config["paths"]["shared_conda"]
    env_path = os.path.join(shared_conda, env_name)

    # Base command to activate environment
    # We assume conda is available in the shell or via 'source $(conda info --base)/etc/profile.d/conda.sh'
    # However, 'conda info' might not work if conda isn't in path.
    # The original scripts find conda via 'dirname $(dirname $(which conda))'.
    # We'll try to rely on the shell having conda initialized or use a robust method.

    # Using a robust activation strategy
    cmd = f"""
    # Initialize conda (try standard locations if not in path)
    if [ -z "$CONDA_EXE" ]; then
        if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
            source "$HOME/miniconda3/etc/profile.d/conda.sh"
        elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
            source "$HOME/anaconda3/etc/profile.d/conda.sh"
        elif which conda > /dev/null 2>&1; then
             CONDA_BASE=$(conda info --base)
             source "$CONDA_BASE/etc/profile.d/conda.sh"
        fi
    else
         # If CONDA_EXE is set, derive base from it
         CONDA_BASE=$(dirname $(dirname "$CONDA_EXE"))
         source "$CONDA_BASE/etc/profile.d/conda.sh"
    fi

    set +u # Conda activate sometimes triggers unbound variable error
    conda activate {env_path}
    set -u

    export LD_LIBRARY_PATH="{env_path}/lib:$LD_LIBRARY_PATH"

    # Perl setup
    if [[ -d "{env_path}/lib/perl5" ]]; then
        export PERL5LIB="{env_path}/lib/perl5/site_perl:{env_path}/lib/perl5:$PERL5LIB"
    fi
    """
    return cmd

# --- Target Rules ---

rule all:
    input:
        expand("{analysis_dir}/{sample}/multiqc_report/multiqc_report.html",
               analysis_dir=config["paths"]["analysis_dir"],
               sample=config["samples"]),
        expand("{analysis_dir}/{sample}/evaluation_report.txt",
               analysis_dir=config["paths"]["analysis_dir"],
               sample=config["samples"])

# --- Part 1: Assembly ---

rule nanoplot_raw:
    input:
        lambda wildcards: os.path.join(config["paths"]["data_dir"], f"{wildcards.sample}.fastq.gz")
    output:
        directory("{analysis_dir}/{sample}/qc/nanoplot_raw")
    threads: config["threads"]
    params:
        env_cmd = get_env_cmd("nanoplot_env")
    shell:
        """
        {params.env_cmd}
        NanoPlot --fastq {input} \
                 --outdir {output} \
                 --threads {threads} \
                 --plots dot kde
        """

rule filtlong:
    input:
        lambda wildcards: os.path.join(config["paths"]["data_dir"], f"{wildcards.sample}.fastq.gz")
    output:
        "{analysis_dir}/{sample}/reads/{sample}_filt.fastq"
    # Filtlong doesn't seem to have a threads parameter in the original script command,
    # but it usually supports multithreading if input is huge, but here it's simple filtering.
    # The original script didn't use -t for filtlong. So we leave it single threaded or default.
    params:
        env_cmd = get_env_cmd("filtlong_env")
    shell:
        """
        {params.env_cmd}
        filtlong --min_length 500 \
                 --keep_percent 95 \
                 --target_bases 500000000 \
                 {input} > {output}
        """

rule nanoplot_filtered:
    input:
        "{analysis_dir}/{sample}/reads/{sample}_filt.fastq"
    output:
        directory("{analysis_dir}/{sample}/qc/nanoplot_filtered")
    threads: config["threads"]
    params:
        env_cmd = get_env_cmd("nanoplot_env")
    shell:
        """
        {params.env_cmd}
        NanoPlot --fastq {input} \
                 --outdir {output} \
                 --threads {threads}
        """

rule flye:
    input:
        "{analysis_dir}/{sample}/reads/{sample}_filt.fastq"
    output:
        "{analysis_dir}/{sample}/flye/assembly.fasta",
        directory("{analysis_dir}/{sample}/flye")
    threads: config["threads"]
    params:
        genome_size = config["genome_size"],
        env_cmd = get_env_cmd("flye_env"),
        out_dir = "{analysis_dir}/{sample}/flye"
    shell:
        """
        {params.env_cmd}
        # Flye fails if output dir exists, so we remove it first.
        # Snakemake might have created it as part of directory output handling.
        rm -rf {params.out_dir}

        flye --nano-raw {input} \
             --genome-size {params.genome_size} \
             --out-dir {params.out_dir} \
             --threads {threads} \
             --iterations 3
        """

rule minimap2_coverage:
    input:
        assembly = "{analysis_dir}/{sample}/flye/assembly.fasta",
        reads = "{analysis_dir}/{sample}/reads/{sample}_filt.fastq"
    output:
        bam = "{analysis_dir}/{sample}/coverage.bam",
        txt = "{analysis_dir}/{sample}/coverage.txt"
    threads: config["threads"]
    params:
        minimap_env = get_env_cmd("minimap2"),
        samtools_env = get_env_cmd("samtools")
    shell:
        """
        {params.minimap_env}
        minimap2 -ax map-ont -t {threads} {input.assembly} {input.reads} > coverage_{wildcards.sample}.tmp.sam

        {params.samtools_env}
        samtools view -bS coverage_{wildcards.sample}.tmp.sam | \
        samtools sort -@ {threads} -o {output.bam}
        samtools index {output.bam}
        samtools depth {output.bam} > {output.txt}

        rm coverage_{wildcards.sample}.tmp.sam
        """

# Racon Rounds
# We unroll the loop for clarity and restartability

rule racon_round1:
    input:
        assembly = "{analysis_dir}/{sample}/flye/assembly.fasta",
        reads = "{analysis_dir}/{sample}/reads/{sample}_filt.fastq"
    output:
        "{analysis_dir}/{sample}/racon/assembly_racon_1.fasta"
    threads: config["threads"]
    params:
        minimap_env = get_env_cmd("minimap2"),
        racon_env = get_env_cmd("racon_env")
    shell:
        """
        {params.minimap_env}
        minimap2 -ax map-ont -t {threads} {input.assembly} {input.reads} > racon_1_{wildcards.sample}.tmp.sam

        {params.racon_env}
        racon -t {threads} {input.reads} racon_1_{wildcards.sample}.tmp.sam {input.assembly} > {output}

        rm racon_1_{wildcards.sample}.tmp.sam
        """

rule racon_round2:
    input:
        assembly = "{analysis_dir}/{sample}/racon/assembly_racon_1.fasta",
        reads = "{analysis_dir}/{sample}/reads/{sample}_filt.fastq"
    output:
        "{analysis_dir}/{sample}/racon/assembly_racon_2.fasta"
    threads: config["threads"]
    params:
        minimap_env = get_env_cmd("minimap2"),
        racon_env = get_env_cmd("racon_env")
    shell:
        """
        {params.minimap_env}
        minimap2 -ax map-ont -t {threads} {input.assembly} {input.reads} > racon_2_{wildcards.sample}.tmp.sam

        {params.racon_env}
        racon -t {threads} {input.reads} racon_2_{wildcards.sample}.tmp.sam {input.assembly} > {output}

        rm racon_2_{wildcards.sample}.tmp.sam
        """

rule racon_round3:
    input:
        assembly = "{analysis_dir}/{sample}/racon/assembly_racon_2.fasta",
        reads = "{analysis_dir}/{sample}/reads/{sample}_filt.fastq"
    output:
        "{analysis_dir}/{sample}/racon/assembly_racon_3.fasta"
    threads: config["threads"]
    params:
        minimap_env = get_env_cmd("minimap2"),
        racon_env = get_env_cmd("racon_env")
    shell:
        """
        {params.minimap_env}
        minimap2 -ax map-ont -t {threads} {input.assembly} {input.reads} > racon_3_{wildcards.sample}.tmp.sam

        {params.racon_env}
        racon -t {threads} {input.reads} racon_3_{wildcards.sample}.tmp.sam {input.assembly} > {output}

        rm racon_3_{wildcards.sample}.tmp.sam
        """

rule medaka:
    input:
        assembly = "{analysis_dir}/{sample}/racon/assembly_racon_3.fasta",
        reads = "{analysis_dir}/{sample}/reads/{sample}_filt.fastq"
    output:
        consensus = "{analysis_dir}/{sample}/medaka/consensus.fasta",
        final_link = "{analysis_dir}/{sample}/assembly_final.fasta"
    threads: config["threads"]
    params:
        medaka_env = get_env_cmd("medaka_env"),
        samtools_env = get_env_cmd("samtools"), # needed for mapping pipe
        minimap_env = get_env_cmd("minimap2"), # needed for mapping pipe
        out_dir = "{analysis_dir}/{sample}/medaka"
    shell:
        """
        # We need to map first. The original script does mapping inside medaka step manually.

        BAM_FILE="{params.out_dir}/reads_mapped.bam"
        mkdir -p {params.out_dir}

        {params.minimap_env}
        # Note: we need to switch envs carefully or put all in one line if possible
        # Since env activation overrides paths, better do it sequentially

        minimap2 -ax map-ont -t {threads} {input.assembly} {input.reads} > medaka_{wildcards.sample}.tmp.sam

        {params.samtools_env}
        samtools view -bS medaka_{wildcards.sample}.tmp.sam | samtools sort -@ {threads} -o $BAM_FILE
        samtools index $BAM_FILE
        rm medaka_{wildcards.sample}.tmp.sam

        {params.medaka_env}
        medaka_consensus -i $BAM_FILE \
                         -d {input.assembly} \
                         -o {params.out_dir} \
                         -t {threads} \
                         -m r941_min_hac_g507

        cp {output.consensus} {output.final_link}
        """

# --- Part 2: Evaluation ---

rule kraken2:
    input:
        reads = "{analysis_dir}/{sample}/reads/{sample}_filt.fastq"
    output:
        report = "{analysis_dir}/{sample}/kraken2_report.txt"
    threads: config["threads"]
    params:
        db = config["paths"]["kraken_db"],
        env_cmd = get_env_cmd("kraken2_env")
    shell:
        """
        {params.env_cmd}
        kraken2 --db {params.db} \
                --threads {threads} \
                --report {output.report} \
                {input.reads} > /dev/null
        """

# Also kraken2 on assembly? The script did it on reads.
# The evaluation script also has "kraken2_assembly_report.txt" mentioned in the report generation but doesn't run it?
# Wait, looking at 02_evaluation.sh:
# It runs kraken2 on `_filt.fastq`.
# But in report generation it greps `kraken2_assembly_report.txt`.
# That looks like a bug or I missed where `kraken2_assembly_report.txt` is created.
# Ah, I see `kraken2 --report ... kraken2_report.txt` in the execution.
# But in report generation: `grep ... kraken2_assembly_report.txt`.
# If `kraken2_assembly_report.txt` is not created, the report will miss it.
# I will stick to what the script EXECUTES: `kraken2_report.txt`.

rule quast:
    input:
        flye = "{analysis_dir}/{sample}/flye/assembly.fasta",
        racon3 = "{analysis_dir}/{sample}/racon/assembly_racon_3.fasta",
        final = "{analysis_dir}/{sample}/assembly_final.fasta"
    output:
        directory("{analysis_dir}/{sample}/quast_comparison")
    threads: config["threads"]
    params:
        env_cmd = get_env_cmd("quast_env")
    shell:
        """
        {params.env_cmd}
        quast.py -o {output} \
                 --threads {threads} \
                 --min-contig 500 \
                 -l "Flye,Racon_3x,Medaka_final" \
                 {input.flye} {input.racon3} {input.final}
        """

rule busco:
    input:
        "{analysis_dir}/{sample}/assembly_final.fasta"
    output:
        directory("{analysis_dir}/{sample}/{sample}_BUSCO")
    threads: config["threads"]
    params:
        lineage = config["busco_lineage"],
        downloads = config["paths"]["busco_downloads"],
        out_name = "{sample}_BUSCO",
        out_path = "{analysis_dir}/{sample}",
        env_cmd = get_env_cmd("busco_env")
    shell:
        """
        {params.env_cmd}
        busco -i {input} \
              -l {params.lineage} \
              -o {params.out_name} \
              --out_path {params.out_path} \
              -m genome \
              -c {threads} \
              --offline \
              --download_path {params.downloads} \
              -f
        """

rule prokka:
    input:
        "{analysis_dir}/{sample}/assembly_final.fasta"
    output:
        directory("{analysis_dir}/{sample}/annotation"),
        "{analysis_dir}/{sample}/annotation/{sample}.faa",
        "{analysis_dir}/{sample}/annotation/{sample}.txt"
    threads: config["threads"]
    params:
        env_cmd = get_env_cmd("prokka_env")
    shell:
        """
        {params.env_cmd}
        prokka --outdir {output[0]} \
               --prefix {wildcards.sample} \
               --cpus {threads} \
               --kingdom Bacteria \
               --force \
               {input}
        """

rule assembly_stats:
    input:
        "{analysis_dir}/{sample}/assembly_final.fasta"
    output:
        "{analysis_dir}/{sample}/assembly_stats.txt"
    params:
        env_cmd = get_env_cmd("bbmap_env")
    shell:
        """
        {params.env_cmd}
        stats.sh in={input} > {output}
        """

rule checkm2:
    input:
        "{analysis_dir}/{sample}/assembly_final.fasta"
    output:
        directory("{analysis_dir}/{sample}/checkm2"),
        "{analysis_dir}/{sample}/checkm2/quality_report.tsv"
    threads: config["threads"]
    params:
        db = config["paths"]["checkm2_db"],
        env_cmd = get_env_cmd("checkm2_env")
    shell:
        """
        {params.env_cmd}
        checkm2 predict \
            --threads {threads} \
            --input {input} \
            --output-directory {output[0]} \
            --database_path {params.db} \
            --force
        """

rule amrfinder:
    input:
        assembly = "{analysis_dir}/{sample}/assembly_final.fasta",
        protein = "{analysis_dir}/{sample}/annotation/{sample}.faa"
    output:
        dir = directory("{analysis_dir}/{sample}/amrfinderplus"),
        tsv = "{analysis_dir}/{sample}/amrfinderplus/amr_results.tsv",
        prot_tsv = "{analysis_dir}/{sample}/amrfinderplus/amr_results_proteins.tsv"
    threads: config["threads"]
    params:
        env_cmd = get_env_cmd("amrfinderplus_env")
    shell:
        """
        {params.env_cmd}
        mkdir -p {output.dir}

        amrfinder \
            --nucleotide {input.assembly} \
            --threads {threads} \
            --output {output.tsv} \
            --plus

        amrfinder \
            --protein {input.protein} \
            --threads {threads} \
            --output {output.prot_tsv} \
            --plus
        """

rule multiqc:
    input:
        # We need to list all inputs that MultiQC should aggregate
        "{analysis_dir}/{sample}/qc/nanoplot_raw",
        "{analysis_dir}/{sample}/qc/nanoplot_filtered",
        "{analysis_dir}/{sample}/quast_comparison",
        "{analysis_dir}/{sample}/{sample}_BUSCO",
        "{analysis_dir}/{sample}/annotation",
        "{analysis_dir}/{sample}/kraken2_report.txt",
        "{analysis_dir}/{sample}/assembly_stats.txt"
    output:
        directory("{analysis_dir}/{sample}/multiqc_report"),
        "{analysis_dir}/{sample}/multiqc_report/multiqc_report.html"
    params:
        env_cmd = get_env_cmd("multiqc_env"),
        search_dir = "{analysis_dir}/{sample}"
    shell:
        """
        {params.env_cmd}
        multiqc {params.search_dir} -o {output[0]} -f
        """

rule evaluation_report:
    input:
        checkm2 = "{analysis_dir}/{sample}/checkm2/quality_report.tsv",
        stats = "{analysis_dir}/{sample}/assembly_stats.txt",
        quast = "{analysis_dir}/{sample}/quast_comparison",
        busco = "{analysis_dir}/{sample}/{sample}_BUSCO",
        kraken = "{analysis_dir}/{sample}/kraken2_report.txt",
        prokka_txt = "{analysis_dir}/{sample}/annotation/{sample}.txt",
        amr = "{analysis_dir}/{sample}/amrfinderplus/amr_results.tsv"
    output:
        "{analysis_dir}/{sample}/evaluation_report.txt"
    shell:
        """
        echo "================================================================================" > {output}
        echo "ONT Assembly Pipeline - Evaluation Report" >> {output}
        echo "================================================================================" >> {output}
        echo "Sample: {wildcards.sample}" >> {output}
        echo "Date: $(date)" >> {output}
        echo "" >> {output}

        echo "CHECKM2 QUALITY:" >> {output}
        if [ -f {input.checkm2} ]; then
            column -t -s $'\t' {input.checkm2} >> {output}
        fi
        echo "" >> {output}

        echo "ASSEMBLY STATISTICS:" >> {output}
        cat {input.stats} >> {output}
        echo "" >> {output}

        echo "QUAST ASSEMBLY QUALITY METRICS:" >> {output}
        if [ -f {input.quast}/report.txt ]; then
            head -30 {input.quast}/report.txt >> {output}
        fi
        echo "" >> {output}

        echo "BUSCO COMPLETENESS:" >> {output}
        grep "C:" {input.busco}/short_summary*.txt >> {output} || true
        echo "" >> {output}

        echo "KRAKEN2 TAXONOMY (Top 10 species):" >> {output}
        # Assuming the kraken report format
        grep -P "\tS\t" {input.kraken} | sort -k1 -nr | head -10 >> {output} || true
        echo "" >> {output}

        echo "PROKKA ANNOTATION SUMMARY:" >> {output}
        cat {input.prokka_txt} >> {output}
        echo "" >> {output}

        echo "AMRFINDERPLUS - ANTIMICROBIAL RESISTANCE:" >> {output}
        AMR_COUNT=$(tail -n +2 {input.amr} | wc -l)
        echo "Total AMR/virulence genes found: $AMR_COUNT" >> {output}
        if [ $AMR_COUNT -gt 0 ]; then
            echo "" >> {output}
            echo "Top findings:" >> {output}
            head -20 {input.amr} | column -t -s $'\t' >> {output}
        fi
        """
