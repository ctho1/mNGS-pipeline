# mNGS-Pipeline: Host-Depletion + CNV (ichorCNA) + KrakenUniq

Snakemake-Pipeline für metagenomische Next-Generation-Sequencing-Diagnostik
(mNGS), kompatibel mit **Nanopore** und **Illumina**. Pro Probe:

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
6. **Report** pro Probe (`workflow/scripts/generate_report_v3.py`, erweitert
   um Host-Depletion- und CNV-Abschnitt inkl. eingebettetem Genome-Wide-Plot):
   - `{sample}.metagenomics_report.pdf` -- vollständiger Report (Top-Hits,
     z-Scores, Prävalenz wie im ursprünglichen krakenuniq-report; CNV-Plot
     und Host-Depletion-Zahlen jetzt direkt mit drin)
   - `{sample}.summary.json` -- maschinenlesbar
   - `{sample}_Nexus_Befund.docx` -- Word-Vorlagenbefund (Calibri 11pt) mit
     Standardtext für den unauffälligen Fall + eingefügtem CNV-Plot; bei
     tatsächlichen Erreger-/CNV-Befunden vor Ausgabe manuell anzupassen

Alle Pfade/Parameter stehen zentral in [`config/config.yaml`](config/config.yaml).
Referenzgenom + Index werden beim ersten Lauf automatisch nach `references/`
heruntergeladen/gebaut, falls dort noch nicht vorhanden -- wie der Rest dieses
Repos ist das relativ zum Repo-Root, der komplette Ordner kann also an eine
beliebige Stelle kopiert werden (PALMA-Scratch, anderes Nutzerkonto, ...).

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

## Einmalige Einrichtung

```bash
# Miniforge (falls noch nicht vorhanden)
curl -fsSL -o /tmp/Miniforge3.sh \
  "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname -s)-$(uname -m).sh"
bash /tmp/Miniforge3.sh -b -p "$HOME/miniforge3"

# Conda-Envs anlegen (auf macOS/Apple Silicon läuft ichorcna via Rosetta 2,
# krakenuniq wird übersprungen -- siehe workflow/scripts/setup_envs.sh;
# auf PALMA/Linux laufen alle Envs nativ inkl. krakenuniq)
bash workflow/scripts/setup_envs.sh

alias smk="./conda_envs/snakemake/bin/snakemake"
```

## Ausführen

```bash
# Dry-Run: zeigt den vollständigen DAG
smk -s workflow/Snakefile --profile profiles/local -n -p

# Vollauf (lokal)
smk -s workflow/Snakefile --profile profiles/local

# Lokaler Testlauf ohne KrakenUniq-DB (z.B. auf macOS ohne Zugriff auf die
# PALMA-Scratch-DB): Report wird trotzdem erzeugt, nur ohne Top-Hits-Tabellen
smk -s workflow/Snakefile --profile profiles/local \
    --config 'krakenuniq={"enabled": false}'

# Auf PALMA
smk -s workflow/Snakefile --profile profiles/palma
```

(Snakemake >=8 erwartet für verschachtelte Config-Keys auf der Kommandozeile
JSON-Syntax; einfaches `krakenuniq.enabled=false` funktioniert nicht.)

## Ergebnisse

Liegen unter `{work_dir}/results/<Sample>/` (Default `work_dir: "."`, also
direkt im Repo):

```
fastq/<Sample>.fastq.gz                    # nur Nanopore (konkateniert)
align/<Sample>.hg38.bam(.bai)              # Alignment gegen hg38
align/<Sample>.flagstat.txt                # human/non-human-Split
nonhuman/<Sample>.nonhuman(.R1/.R2).fastq.gz  # Input für KrakenUniq
ichorCNA/<Sample>.*                        # CNV-Profil (params.txt, .seg.txt, .cna.seg, Plot)
krakenuniq/<Sample>.krakenuniq.report.txt
report/<Sample>.metagenomics_report.pdf
report/<Sample>.summary.json
report/<Sample>_Nexus_Befund.docx
```

## KrakenUniq-Referenzdatenbank

Pfad ist unverändert aus dem ursprünglichen
[krakenuniq-report](https://github.com/ctho1/krakenuniq-report)
(`scripts/config.sh`) übernommen und in `config/config.yaml` als Default
gesetzt -- auf PALMA i.d.R. ohne Anpassung lauffähig. Für ein anderes
Konto/Setup dort (oder per `--config`) überschreiben.

Die Genus-Prävalenz-/z-Score-Referenzdaten für den PDF-Report
(`workflow/analysis/*.csv`, `reference_meta.json`) sind ebenfalls unverändert
aus diesem Repo übernommen; Aktualisierung weiterhin über
`workflow/scripts/build_reference_db.py` (falls benötigt, aus dem
ursprünglichen Repo nachziehen).

## Herkunft

Die Metagenomik-Klassifikation (KrakenUniq + PDF-Report) stammt aus
[ctho1/krakenuniq-report](https://github.com/ctho1/krakenuniq-report) und
wurde um Host-Depletion, CNV-Profil (ichorCNA) und Illumina-Unterstützung zu
einer einheitlichen Snakemake-Pipeline erweitert.
