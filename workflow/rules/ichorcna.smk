IC_CFG = config["ichorcna"]
EXTDATA = IC_CFG["extdata"]
CHROMS_CSV = ",".join([f"chr{c}" for c in list(range(1, 23)) + ["X", "Y"]])


# Plattformunabhängig: readCounter/ichorCNA arbeiten auf dem BAM, egal ob
# Nanopore- oder Illumina-Alignment.
rule read_counter:
    input:
        bam=rules.align.output.bam,
    output:
        wig=f"{RESULTS}/{{sample}}/ichorCNA/{{sample}}.{IC_CFG['bin_label']}.wig",
    log:
        f"{LOGDIR}/{{sample}}/read_counter.log",
    params:
        window=IC_CFG["bin_size"],
        chroms=CHROMS_CSV,
    shell:
        "PATH={ENV_ALIGN}/bin:$PATH readCounter --window {params.window} --quality 20 "
        "--chromosome {params.chroms} {input.bam} > {output.wig} 2> {log}"


# Immer MIT Panel-of-Normals -- Parameter übernommen von nanoDx, siehe
# config/config.yaml.
rule ichorcna:
    input:
        wig=rules.read_counter.output.wig,
    output:
        params_txt=f"{RESULTS}/{{sample}}/ichorCNA/{{sample}}.params.txt",
        cna=f"{RESULTS}/{{sample}}/ichorCNA/{{sample}}.cna.seg",
        seg=f"{RESULTS}/{{sample}}/ichorCNA/{{sample}}.seg.txt",
        plot=f"{RESULTS}/{{sample}}/ichorCNA/{{sample}}/{{sample}}_genomeWide.png",
    log:
        f"{LOGDIR}/{{sample}}/ichorcna.log",
    threads: config["threads"]["ichorcna"]
    params:
        outdir=lambda wc: f"{RESULTS}/{wc.sample}/ichorCNA",
        gc_wig=EXTDATA["gc_wig"],
        map_wig=EXTDATA["map_wig"],
        centromere=EXTDATA["centromere"],
        normal_panel=EXTDATA["normal_panel"],
        chrs=IC_CFG["chrs"],
        chr_normalize=IC_CFG["chr_normalize"],
        chr_train=IC_CFG["chr_train"],
        genome_build=IC_CFG["genome_build"],
        genome_style=IC_CFG["genome_style"],
        include_homd="TRUE" if IC_CFG["include_homd"] else "FALSE",
        normal=IC_CFG["normal"],
        ploidy=IC_CFG["ploidy"],
        min_map_score=IC_CFG["min_map_score"],
        txn_strength=IC_CFG["txn_strength"],
        txn_e=IC_CFG["txn_e"],
        normalize_male_x="TRUE" if IC_CFG["normalize_male_x"] else "FALSE",
        estimate_sc_prevalence="TRUE" if IC_CFG["estimate_sc_prevalence"] else "FALSE",
        plot_y_lim=IC_CFG["plot_y_lim"],
    shell:
        """
        EXTDATA_DIR=$(PATH={ENV_ICHORCNA}/bin:$PATH Rscript -e 'cat(system.file("extdata", package="ichorCNA"))')
        PATH={ENV_ICHORCNA}/bin:$PATH Rscript workflow/scripts/run_ichorcna.R \
            --WIG {input.wig} \
            --gcWig "$EXTDATA_DIR/{params.gc_wig}" \
            --mapWig "$EXTDATA_DIR/{params.map_wig}" \
            --centromere "$EXTDATA_DIR/{params.centromere}" \
            --normalPanel "$EXTDATA_DIR/{params.normal_panel}" \
            --id {wildcards.sample} \
            --outDir {params.outdir} \
            --genomeBuild {params.genome_build} \
            --genomeStyle {params.genome_style} \
            --chrs '{params.chrs}' \
            --chrNormalize '{params.chr_normalize}' \
            --chrTrain '{params.chr_train}' \
            --normal '{params.normal}' \
            --ploidy '{params.ploidy}' \
            --minMapScore {params.min_map_score} \
            --txnStrength {params.txn_strength} \
            --txnE {params.txn_e} \
            --normalizeMaleX {params.normalize_male_x} \
            --estimateScPrevalence {params.estimate_sc_prevalence} \
            --plotYLim '{params.plot_y_lim}' \
            --includeHOMD {params.include_homd} \
            --plotFileType png \
            --cores {threads} \
            > {log} 2>&1
        """
