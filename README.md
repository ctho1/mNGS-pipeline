# mNGS-Pipeline: Host-Depletion + CNV (ichorCNA) + KrakenUniq

Bash/SLURM-Pipeline für metagenomische Next-Generation-Sequencing-Diagnostik
(mNGS), kompatibel mit **Nanopore** und **Illumina**. Steuert SLURM auf PALMA
direkt an (`sbatch`, ein Job pro Probe) -- wie das ursprüngliche
[krakenuniq-report](https://github.com/ctho1/krakenuniq-report). Läuft ohne
SLURM (z.B. lokal zum Testen) automatisch seriell im Vordergrund.

Pro Probe:

1. **Nanopore**: alle FASTQ-Dateien im Proben-Unterordner werden zu einer
   Datei konkateniert. **Illumina**: R1/R2-Paar wird direkt verwendet (kein
   Concat nötig) -- das ist der einzige Unterschied im Input-Layout, siehe
   unten.
2. **Alignment** gegen hg38 (UCSC No-Alt Analysis Set) mit `minimap2`
   (Preset `map-ont` bzw. `sr`).
3. **CNV-Profil** mit ichorCNA (hg38-Panel-of-Normals, kein gematchtes
   Normalgewebe). Parameter (normal/ploidy-Grid, minMapScore, txnStrength/
   txnE, normalizeMaleX, estimateScPrevalence, plotYLim) übernommen von
   [nanoDx](https://gitlab.com/pesk/nanoDx) (der Pipeline hinter crossNN,
   Yuan et al. 2025, *Nat Cancer*), das dieselbe ichorCNA-Version pinnt.
4. **Host-Depletion**: nicht auf hg38 gemappte ("non-human") Reads werden
   extrahiert (Nanopore: single-end; Illumina: nur Read-Paare, bei denen
   **beide** Mates ungemappt sind).
5. **KrakenUniq-Klassifikation** dieser non-human Reads (Single-end oder
   `--paired`, je nach Plattform).
6. **Report** pro Probe (`scripts/generate_report_v3.py`, erweitert um
   Host-Depletion- und CNV-Abschnitt inkl. eingebettetem Genome-Wide-Plot):
   - `{sample}.metagenomics_report.pdf` -- vollständiger Report (Top-Hits,
     z-Scores, Prävalenz wie im ursprünglichen krakenuniq-report; CNV-Plot
     und Host-Depletion-Zahlen jetzt direkt mit drin)
   - `{sample}.summary.json` -- maschinenlesbar
   - `{sample}_Nexus_Befund.docx` -- Word-Vorlagenbefund (Calibri 11pt) mit
     Standardtext für den unauffälligen Fall + eingefügtem CNV-Plot; bei
     tatsächlichen Erreger-/CNV-Befunden vor Ausgabe manuell anzupassen

## Verzeichnisstruktur

```
mNGS-pipeline/
├── run_pipeline.sh          # Einstiegspunkt: erkennt Proben in input/, reicht sbatch-Jobs ein
├── scripts/
│   ├── config.sh              # einzige Stelle mit externen/nutzerspezifischen Pfaden
│   ├── setup_envs.sh          # legt Conda-Envs an (einmalig)
│   ├── prepare_reference.sh   # sbatch-Job: hg38 laden + beide minimap2-Indizes bauen
│   ├── sample_pipeline.sh     # sbatch-Job: Concat -> Alignment -> ichorCNA -> KrakenUniq -> Report
│   ├── concat_fastq.sh
│   ├── extract_nonhuman_se.sh / extract_nonhuman_pe.sh
│   ├── krakenuniq_run.sh
│   ├── run_ichorcna.R
│   ├── build_report.py        # ruft generate_report_v3.py + erzeugt JSON/docx
│   ├── generate_report_v3.py  # PDF-Report-Generator (Top-Hits, CNV, Host-Depletion)
│   ├── kraken_tree.py
│   └── envs/*.yaml             # Conda-Umgebungsdefinitionen
├── analysis/                   # Referenz-/Hintergrunddaten für z-Score & Prävalenz
├── input/                      # hier Proben ablegen (siehe unten)
└── log/, output/, tmp/, references/, conda_envs/   # werden automatisch angelegt
```

## Input-Layout

```
input/
├── N1234_26/                              # Nanopore: Unterordner = 1 Probe
│   ├── PBM..._0.fastq.gz                  #   (rekursiv eingesammelt, wird
│   └── PBM..._1.fastq.gz                  #    zu N1234_26.fastq.gz konkateniert)
├── ILL_Probe01_R1_001.fastq.gz            # Illumina: flach, R1/R2-Paar
└── ILL_Probe01_R2_001.fastq.gz            #   (gleiche Erkennung wie im
                                            #    ursprünglichen krakenuniq-report)
```

## Einrichtung

```bash
# 1. Miniforge (falls noch nicht vorhanden)
curl -fsSL -o /tmp/Miniforge3.sh \
  "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname -s)-$(uname -m).sh"
bash /tmp/Miniforge3.sh -b -p "$HOME/miniforge3"

# 2. Conda-Envs anlegen (auf macOS/Apple Silicon läuft ichorcna via Rosetta 2,
#    krakenuniq wird übersprungen; auf PALMA/Linux laufen alle Envs nativ)
bash scripts/setup_envs.sh

# 3. scripts/config.sh prüfen/anpassen (Referenz-DB-Pfad, KrakenUniq-
#    Installationspfad). Bei unverändertem Konto/Setup nicht nötig.

# 4. FASTQ-Dateien nach input/ kopieren (siehe Input-Layout oben).
```

## Ausführen

```bash
cd mNGS-pipeline

bash run_pipeline.sh                              # standardmäßig ohne Mail-Benachrichtigung
bash run_pipeline.sh --mail user@uni-muenster.de   # Mail-Benachrichtigung aktivieren

# Lokaler Testlauf ohne KrakenUniq-DB (z.B. auf macOS ohne Zugriff auf die
# PALMA-Scratch-DB): Report wird trotzdem erzeugt, nur ohne Top-Hits-Tabellen
KRAKENUNIQ_ENABLED=false bash run_pipeline.sh
```

`run_pipeline.sh` erkennt automatisch, ob `sbatch` verfügbar ist:

- **Mit SLURM (PALMA)**: reicht zunächst -- falls die Referenz fehlt -- einen
  `prepare_reference.sh`-Job ein, dann für jede erkannte Probe einen eigenen
  `sample_pipeline.sh`-Job (Partition `requeue`, 36 Cores, 140G RAM, 4h
  Zeitlimit; per `--dependency` an den Referenz-Job gekoppelt, falls dieser
  läuft).
- **Ohne SLURM (lokal)**: führt Referenz-Vorbereitung und alle Proben direkt
  seriell im Vordergrund aus (`bash scripts/...` statt `sbatch scripts/...`).

Logs landen in `log/`, Zwischendateien in `tmp/`.

## Ergebnisse

Liegen unter `output/<Sample>/`:

```
<Sample>.hg38.bam(.bai)                    # Alignment gegen hg38
<Sample>.flagstat.txt                      # human/non-human-Split
<Sample>.nonhuman(_R1/_R2).fastq.gz        # Input für KrakenUniq
<Sample>.params.txt / .seg.txt / .cna.seg  # ichorCNA CNV-Profil
<Sample>/<Sample>_genomeWide.png           # ichorCNA Genome-Wide-Plot
<Sample>.krakenuniq.report.txt
<Sample>.metagenomics_report.pdf
<Sample>.summary.json
<Sample>_Nexus_Befund.docx
```

## KrakenUniq-Referenzdatenbank

Pfad ist unverändert aus dem ursprünglichen
[krakenuniq-report](https://github.com/ctho1/krakenuniq-report)
(`scripts/config.sh`) übernommen und in `scripts/config.sh` als Default
gesetzt -- auf PALMA i.d.R. ohne Anpassung lauffähig. Für ein anderes
Konto/Setup dort (oder per Umgebungsvariable, z.B.
`KRAKENUNIQ_DB=/anderer/pfad bash run_pipeline.sh`) überschreiben.

Die Genus-Prävalenz-/z-Score-Referenzdaten für den PDF-Report
(`analysis/*.csv`, `reference_meta.json`) sind ebenfalls unverändert aus
diesem Repo übernommen; Aktualisierung weiterhin über
`scripts/build_reference_db.py` (falls benötigt, aus dem ursprünglichen Repo
nachziehen).

## Herkunft

Die Metagenomik-Klassifikation (KrakenUniq + PDF-Report) stammt aus
[ctho1/krakenuniq-report](https://github.com/ctho1/krakenuniq-report) und
wurde um Host-Depletion, CNV-Profil (ichorCNA) und Illumina-Unterstützung zu
einer einheitlichen Pipeline erweitert.
