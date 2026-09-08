rule download_reference:
    output:
        fasta=f"{REF_DIR}/{config['reference']['fasta']}",
    params:
        url=config["reference"]["fasta_url"],
        gz=f"{REF_DIR}/{config['reference']['fasta']}.gz",
    log:
        f"{LOGDIR}/reference/download_reference.log",
    shell:
        """
        mkdir -p {REF_DIR}
        if [ ! -s {params.gz} ]; then
            curl -fL -o {params.gz} {params.url} 2> {log}
        fi
        gzip -dc {params.gz} > {output.fasta} 2>> {log}
        """


rule faidx_reference:
    input:
        fasta=rules.download_reference.output.fasta,
    output:
        fai=f"{REF_DIR}/{config['reference']['fasta']}.fai",
    log:
        f"{LOGDIR}/reference/faidx.log",
    shell:
        "PATH={ENV_ALIGN}/bin:$PATH samtools faidx {input.fasta} > {log} 2>&1"


# minimap2-Presets sind indexspezifisch (k-mer/window-Größe) -- getrennter
# Index je Plattform (map-ont für Nanopore, sr für Illumina-Kurzreads).
rule minimap2_index:
    input:
        fasta=rules.download_reference.output.fasta,
    output:
        mmi=f"{REF_DIR}/" + config["reference"]["mmi_pattern"],
    wildcard_constraints:
        preset="|".join(config["reference"]["presets"].values()),
    log:
        f"{LOGDIR}/reference/minimap2_index_{{preset}}.log",
    threads: config["threads"]["minimap2"]
    shell:
        "PATH={ENV_ALIGN}/bin:$PATH minimap2 -x {wildcards.preset} -t {threads} -d {output.mmi} {input.fasta} > {log} 2>&1"
