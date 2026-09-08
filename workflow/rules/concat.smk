# Nur für Nanopore-Proben (Unterordner-Layout) -- Illumina-Paare werden
# direkt aligned, kein Concat nötig.
rule concat_fastq:
    input:
        lambda wc: nanopore_sample_fastqs(wc.sample),
    output:
        f"{RESULTS}/{{sample}}/fastq/{{sample}}.fastq.gz",
    log:
        f"{LOGDIR}/{{sample}}/concat_fastq.log",
    wildcard_constraints:
        sample="|".join(NANOPORE_SAMPLES) if NANOPORE_SAMPLES else "NOMATCH",
    shell:
        "bash workflow/scripts/concat_fastq.sh {output} {input} > {log} 2>&1"
