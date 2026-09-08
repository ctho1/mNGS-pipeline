def align_input_reads(wc):
    if SAMPLE_PLATFORM[wc.sample] == "nanopore":
        return [f"{RESULTS}/{wc.sample}/fastq/{wc.sample}.fastq.gz"]
    r1, r2 = ILLUMINA_PAIRS[wc.sample]
    return [r1, r2]


def align_preset(wc):
    key = SAMPLE_PLATFORM[wc.sample]
    return config["reference"]["presets"][key]


def align_input_mmi(wc):
    preset = align_preset(wc)
    return f"{REF_DIR}/" + config["reference"]["mmi_pattern"].format(preset=preset)


# Eine Rule für beide Plattformen: minimap2 unterstützt sowohl Nanopore
# (Preset map-ont, ein FASTQ) als auch Illumina-Paired-End (Preset sr, zwei
# FASTQ-Dateien als Positionsargumente -- automatischer Paired-Modus).
rule align:
    input:
        reads=align_input_reads,
        mmi=align_input_mmi,
        fai=rules.faidx_reference.output.fai,
    output:
        bam=f"{RESULTS}/{{sample}}/align/{{sample}}.hg38.bam",
        bai=f"{RESULTS}/{{sample}}/align/{{sample}}.hg38.bam.bai",
    log:
        f"{LOGDIR}/{{sample}}/align.log",
    threads: config["threads"]["minimap2"]
    params:
        preset=align_preset,
        sort_threads=config["threads"]["samtools_sort"],
    shell:
        """
        PATH={ENV_ALIGN}/bin:$PATH minimap2 -ax {params.preset} --secondary=no -t {threads} {input.mmi} {input.reads} 2> {log} \
            | PATH={ENV_ALIGN}/bin:$PATH samtools sort -@ {params.sort_threads} -o {output.bam} - >> {log} 2>&1
        PATH={ENV_ALIGN}/bin:$PATH samtools index {output.bam}
        """


rule bam_stats:
    input:
        bam=rules.align.output.bam,
    output:
        flagstat=f"{RESULTS}/{{sample}}/align/{{sample}}.flagstat.txt",
        idxstats=f"{RESULTS}/{{sample}}/align/{{sample}}.idxstats.txt",
        stats=f"{RESULTS}/{{sample}}/align/{{sample}}.stats.txt",
    log:
        f"{LOGDIR}/{{sample}}/bam_stats.log",
    shell:
        """
        PATH={ENV_ALIGN}/bin:$PATH samtools flagstat {input.bam} > {output.flagstat} 2> {log}
        PATH={ENV_ALIGN}/bin:$PATH samtools idxstats {input.bam} > {output.idxstats} 2>> {log}
        PATH={ENV_ALIGN}/bin:$PATH samtools stats {input.bam} > {output.stats} 2>> {log}
        """


# Non-human-Extraktion: Output-Struktur (1 vs. 2 Dateien) unterscheidet sich
# strukturell zwischen SE/PE, daher zwei Rules (statt einer mit variabler
# Output-Zahl) -- je per wildcard_constraints auf ihre Plattform beschränkt.
rule extract_nonhuman_se:
    input:
        bam=rules.align.output.bam,
    output:
        fastq=f"{RESULTS}/{{sample}}/nonhuman/{{sample}}.nonhuman.fastq.gz",
    log:
        f"{LOGDIR}/{{sample}}/extract_nonhuman.log",
    wildcard_constraints:
        sample="|".join(NANOPORE_SAMPLES) if NANOPORE_SAMPLES else "NOMATCH",
    shell:
        "PATH={ENV_ALIGN}/bin:$PATH bash workflow/scripts/extract_nonhuman_se.sh {input.bam} {output.fastq} > {log} 2>&1"


rule extract_nonhuman_pe:
    input:
        bam=rules.align.output.bam,
    output:
        r1=f"{RESULTS}/{{sample}}/nonhuman/{{sample}}.nonhuman_R1.fastq.gz",
        r2=f"{RESULTS}/{{sample}}/nonhuman/{{sample}}.nonhuman_R2.fastq.gz",
    log:
        f"{LOGDIR}/{{sample}}/extract_nonhuman.log",
    wildcard_constraints:
        sample="|".join(ILLUMINA_SAMPLES) if ILLUMINA_SAMPLES else "NOMATCH",
    shell:
        "PATH={ENV_ALIGN}/bin:$PATH bash workflow/scripts/extract_nonhuman_pe.sh {input.bam} {output.r1} {output.r2} > {log} 2>&1"
