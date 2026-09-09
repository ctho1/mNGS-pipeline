# mNGS-Pipeline: Host-Depletion + CNV (ichorCNA) + KrakenUniq

Bash/SLURM-Pipeline für mNGS-Diagnostik, kompatibel mit **Nanopore** und
**Illumina**. Steuert SLURM auf PALMA direkt an (`sbatch`, ein Job pro
Probe), wie [krakenuniq-report](https://github.com/ctho1/krakenuniq-report).
Ohne SLURM (z.B. lokal) läuft alles seriell im Vordergrund.

Pro Probe:

1. **Concat** (nur Nanopore, Unterordner → eine Datei) und **Alignment**
   gegen hg19 -- Nanopore mit `minimap2 -ax map-ont`, Illumina mit
   `bwa-mem2 mem` (reuse des geteilten hg19-Index von ngs-tumor-pipeline,
   siehe unten). **Host-Depletion** läuft inline: non-human Reads werden
   per `tee` live aus dem SAM-Stream abgezweigt, parallel zum BAM-Sort.
2. **CNV-Profil** mit ichorCNA (hg19-PoN, kein gematchtes Normalgewebe).
   Parameter + Referenzdaten von [nanoDx](https://gitlab.com/pesk/nanoDx)
   übernommen (gleiche r-ichorcna-Version, selbst hg19-nativ).
3. **KrakenUniq** auf den non-human Reads.
4. **Report**: `{sample}.metagenomics_report.pdf` (Top-Hits + CNV-Plot +
   Host-Depletion, via erweitertem `generate_report_v3.py`),
   `{sample}.summary.json`, `{sample}_Nexus_Befund.docx` (Word-Vorlagenbefund).

## Struktur

```
run_pipeline.sh              # Einstiegspunkt: scannt input/, reicht sbatch-Jobs ein
scripts/
├── config.sh                 # alle Pfade/Parameter
├── setup_envs.sh             # Conda-Envs anlegen (einmalig)
├── prepare_reference.sh      # sbatch-Job: hg19 + Indizes
├── sample_pipeline.sh        # sbatch-Job: Alignment -> ichorCNA -> KrakenUniq -> Report
├── concat_fastq.sh, extract_nonhuman_{se,pe}.sh, krakenuniq_run.sh, run_ichorcna.R
├── build_report.py           # PDF/JSON/docx
└── generate_report_v3.py, kraken_tree.py
analysis/                     # z-Score-/Prävalenz-Referenzdaten
input/                        # Proben (siehe unten)
```
`log/`, `output/`, `tmp/`, `references/`, `conda_envs/` werden automatisch angelegt.

## Input

```
input/N1234_26/*.fastq.gz              # Nanopore: Unterordner = 1 Probe
input/Probe01_R1_001.fastq.gz          # Illumina: flaches R1/R2-Paar
input/Probe01_R2_001.fastq.gz
```

## Setup

```bash
bash scripts/setup_envs.sh   # Conda-Envs (macOS: ichorcna via Rosetta 2; PALMA: alles nativ)
# scripts/config.sh bei Bedarf anpassen (DB-Pfade, Module)
```

## Ausführen

```bash
bash run_pipeline.sh                              # ohne Mail
bash run_pipeline.sh --mail user@uni-muenster.de
KRAKENUNIQ_ENABLED=false bash run_pipeline.sh      # lokaler Test ohne DB
```

Mit SLURM: `prepare_reference.sh` (falls Referenz fehlt) läuft zuerst,
Probenjobs hängen per `--dependency` daran. Ohne SLURM: alles seriell direkt.

## Ergebnisse (`output/<Sample>/`)

```
<Sample>.hg19.bam(.bai), .flagstat.txt
<Sample>.nonhuman(_R1/_R2).fastq.gz
<Sample>.params.txt / .seg.txt / .cna.seg, <Sample>/<Sample>_genomeWide.png
<Sample>.krakenuniq.report.txt
<Sample>.metagenomics_report.pdf, .summary.json, _Nexus_Befund.docx
```

## PALMA-Module statt Conda

`minimap2`, `bwa-mem2`, `samtools` kommen auf PALMA aus dem Modulsystem
(`scripts/config.sh`: `*_MODULES`) -- conda-samtools hatte dort einen
unlösbaren libdeflate-Konflikt. Lokal (kein Modulsystem) kommen alle drei
weiter aus conda.

## Referenzgenom (hg19)

`prepare_reference.sh` nutzt die geteilte hg19-Fasta + bwa-mem2-Index von
ngs-tumor-pipeline (`EXISTING_HG19_FASTA`, Default
`/cloud/wwu1/e_np_ngs/references/genomes/hg19.fa`) per Symlink, statt neu zu
laden/bauen -- Chromosomen-Namen dort sind UCSC-Style (`chr1`), passend zu
`ICHORCNA_GENOME_STYLE`. Der minimap2-Index (Nanopore) wird einmalig daraus
gebaut, da dafür kein vorhandener Index bekannt ist. Existiert der Pfad
nicht (z.B. lokal ohne PALMA-Mount), lädt/baut `prepare_reference.sh`
stattdessen alles selbst.

KrakenUniq-DB-Pfad und Referenz-CSVs (`analysis/`) sind unverändert aus
[krakenuniq-report](https://github.com/ctho1/krakenuniq-report) übernommen.
