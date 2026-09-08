KU_CFG = config["krakenuniq"]


def krakenuniq_input_reads(wc):
    if SAMPLE_PLATFORM[wc.sample] == "nanopore":
        return [f"{RESULTS}/{wc.sample}/nonhuman/{wc.sample}.nonhuman.fastq.gz"]
    return [
        f"{RESULTS}/{wc.sample}/nonhuman/{wc.sample}.nonhuman_R1.fastq.gz",
        f"{RESULTS}/{wc.sample}/nonhuman/{wc.sample}.nonhuman_R2.fastq.gz",
    ]


# Eine Rule für beide Plattformen: krakenuniq_run.sh entscheidet anhand der
# Anzahl übergebener Read-Dateien (1 = single-end, 2 = --paired).
rule krakenuniq_classify:
    input:
        reads=krakenuniq_input_reads,
    output:
        report=f"{RESULTS}/{{sample}}/krakenuniq/{{sample}}.krakenuniq.report.txt",
    log:
        f"{LOGDIR}/{{sample}}/krakenuniq.log",
    threads: config["threads"]["krakenuniq"]
    params:
        db=KU_CFG["db"],
        bin_dir=KU_CFG["bin_dir"],
        extra_bin_dir=KU_CFG["extra_bin_dir"],
        preload=KU_CFG["preload_size"],
        module_prefix=KU_CFG["module_prefix"],
        tmp=lambda wc: f"{TMPDIR}/{wc.sample}",
    shell:
        """
        {params.module_prefix}
        export PATH="{params.bin_dir}:{params.extra_bin_dir}:{ENV_KRAKENUNIQ}/bin:$PATH"
        bash workflow/scripts/krakenuniq_run.sh {params.db} {threads} {params.preload} \
            {output.report} {params.tmp} {input.reads} > {log} 2>&1
        """
