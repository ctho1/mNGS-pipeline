# mNGS-Pipeline: CNV (ichorCNA) + KrakenUniq

Bash/SLURM-Pipeline für mNGS-Diagnostik, kompatibel mit **Nanopore** und
**Illumina**. Steuert SLURM auf PALMA direkt an (`sbatch`, ein Job pro
Probe), wie [krakenuniq-report](https://github.com/ctho1/krakenuniq-report).
Ohne SLURM (z.B. lokal) läuft alles seriell im Vordergrund.

Pro Probe:

1. **Concat** (nur Nanopore, per Datei-Stamm gruppierte Chunks → eine Datei)
   und **Alignment** gegen hg19 -- Nanopore mit `minimap2 -ax map-ont`,
   Illumina mit `bwa-mem2 mem` (reuse des geteilten hg19-Index von
   ngs-tumor-pipeline, siehe unten).
2. **Host-Depletion** aus dem hg19-Alignment: bei Nanopore werden Reads mit
   SAM-Flag `0x4` extrahiert; bei Illumina nur Paare, bei denen beide Mates
   unmapped sind (`0x4 + 0x8 = 0xC`).
3. **CNV-Profil** mit ichorCNA (hg19-PoN, kein gematchtes Normalgewebe).
   Parameter + Referenzdaten von [nanoDx](https://gitlab.com/pesk/nanoDx)
   übernommen (gleiche r-ichorcna-Version, selbst hg19-nativ).
4. **KrakenUniq** ausschließlich auf diesen nicht-humanen Reads
   beziehungsweise Read-Paaren.
5. **Report**: `{sample}.metagenomics_report.pdf` (KrakenUniq-Übersicht,
   CNV-Profil direkt darüber den Top-Hits, via erweitertem
   `generate_report_v3.py`), `{sample}.summary.json`,
   `{sample}_Nexus_Befund.docx` (Word-Vorlagenbefund). Lässt sich aus
   vorhandenen Zwischendateien neu erzeugen, siehe unten.

## Struktur

```
run_pipeline.sh              # Einstiegspunkt: scannt input/, reicht sbatch-Jobs ein
scripts/
├── config.sh                 # alle Pfade/Parameter
├── setup_envs.sh             # Conda-Envs anlegen (einmalig)
├── prepare_reference.sh      # sbatch-Job: hg19 + Indizes
├── sample_pipeline.sh        # sbatch-Job: Alignment -> ichorCNA -> KrakenUniq -> Report
├── generate_sample_report.sh # nur der Report-Schritt (auch eigenständig nutzbar, siehe unten)
├── discover_samples.py, concat_fastq.sh, krakenuniq_run.sh, run_ichorcna.R
├── build_report.py           # PDF/JSON/docx
└── generate_report_v3.py, kraken_tree.py
analysis/                     # z-Score-/Prävalenz-Referenzdaten
input/                        # Proben (siehe unten)
```
`log/`, `output/`, `tmp/`, `references/`, `conda_envs/` werden automatisch angelegt.

## Input

Alle Dateien liegen flach in `input/` (keine Unterordner):

```
input/PBM37034_pass_barcode05_3856fdc5_0.fastq.gz   # Nanopore: nach Datei-
input/PBM37034_pass_barcode05_3856fdc5_1.fastq.gz   #   Stamm gruppiert (alles
input/PBM37034_pass_barcode05_3856fdc5_2.fastq.gz   #   vor der letzten "_<Zahl>",
                                                     #   MinKNOW/Guppy-Konvention;
                                                     #   numerisch sortiert konkateniert)
input/Probe01_R1_001.fastq.gz          # Illumina: flaches R1/R2-Paar
input/Probe01_R2_001.fastq.gz
```

Erkennung (`scripts/discover_samples.py`): `*_R1_001`/`*_R2_001`-Paare sind
Illumina; alle übrigen `*.fastq(.gz)`-Dateien werden anhand des
gemeinsamen Namensstamms zu Nanopore-Proben gruppiert (unterschiedliche
Barcodes = unterschiedliche Proben, da der Barcode Teil des Stamms ist).

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

`sample_pipeline.sh` ist **resumable**: jeder Schritt (Concat, Alignment,
Host-Depletion, FASTQ-Read-Zählung, ichorCNA, KrakenUniq) prüft zuerst, ob
sein Ergebnis in `tmp/<Sample>/` bzw. `output/<Sample>/` schon vorhanden ist,
und überspringt ihn dann. Ein
erneuter `bash run_pipeline.sh` für eine bereits (teilweise) verarbeitete
Probe wiederholt also nur die fehlenden Schritte und rendert am Ende den
Report neu -- praktisch nach einem abgebrochenen Lauf oder um z.B.
KrakenUniq nachträglich zu aktivieren, ohne Alignment/ichorCNA zu wiederholen.

**Nur Report neu erzeugen** (z.B. nach einer Anpassung am PDF-Layout), ohne
Alignment/ichorCNA/KrakenUniq erneut laufen zu lassen -- braucht die
Zwischendateien in `tmp/<Sample>/` (siehe unten):

```bash
bash scripts/generate_sample_report.sh <Sample> nanopore   # oder: illumina
```

## Ergebnisse

`output/<Sample>/` -- Deliverables:

```
<Sample>.krakenuniq.report.txt
<Sample>.metagenomics_report.pdf, .summary.json, _Nexus_Befund.docx
```

`tmp/<Sample>/` -- Zwischendateien (BAM, FASTQ, ichorCNA-Rohdaten; bleiben
nach dem Lauf liegen, können bei Bedarf gelöscht werden):

```
<Sample>.hg19.bam(.bai), .flagstat.txt
<Sample>.nonhuman.fastq.gz                         # Nanopore
<Sample>.nonhuman_R1.fastq.gz, .nonhuman_R2.fastq.gz  # Illumina
<Sample>.read_counts.tsv                           # initial + an KrakenUniq
<Sample>.params.txt / .seg.txt / .cna.seg, <Sample>/<Sample>_genomeWide.png
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
