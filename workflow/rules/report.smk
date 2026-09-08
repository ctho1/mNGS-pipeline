def report_inputs(wc):
    d = {
        "flagstat": f"{RESULTS}/{wc.sample}/align/{wc.sample}.flagstat.txt",
        "ichor_params": f"{RESULTS}/{wc.sample}/ichorCNA/{wc.sample}.params.txt",
        "ichor_plot": f"{RESULTS}/{wc.sample}/ichorCNA/{wc.sample}/{wc.sample}_genomeWide.png",
    }
    if KU_CFG["enabled"]:
        d["ku_report"] = f"{RESULTS}/{wc.sample}/krakenuniq/{wc.sample}.krakenuniq.report.txt"
    return d


# Ein Report pro Probe: PDF (Host-Depletion + CNV-Plot + ggf. KrakenUniq-
# Top-Hits, siehe generate_report_v3.py) + maschinenlesbares JSON.
rule metagenomics_report:
    input:
        unpack(report_inputs),
    output:
        pdf=f"{RESULTS}/{{sample}}/report/{{sample}}.metagenomics_report.pdf",
        json=f"{RESULTS}/{{sample}}/report/{{sample}}.summary.json",
        docx=f"{RESULTS}/{{sample}}/report/{{sample}}_Nexus_Befund.docx",
    log:
        f"{LOGDIR}/{{sample}}/metagenomics_report.log",
    params:
        platform=lambda wc: SAMPLE_PLATFORM[wc.sample],
        ku_report=lambda wc, input: getattr(input, "ku_report", ""),
    shell:
        """
        PATH={ENV_REPORT}/bin:$PATH python3 workflow/scripts/build_report.py \
            --sample {wildcards.sample} \
            --platform {params.platform} \
            --flagstat {input.flagstat} \
            --ichorcna-params {input.ichor_params} \
            --ichorcna-plot {input.ichor_plot} \
            --krakenuniq-report "{params.ku_report}" \
            --output-pdf {output.pdf} \
            --output-json {output.json} \
            --output-docx {output.docx} \
            > {log} 2>&1
        """
