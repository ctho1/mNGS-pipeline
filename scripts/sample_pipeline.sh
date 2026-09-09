#!/bin/bash
# Analysepfad für eine Probe: Concat (nur Nanopore) -> hg19-Alignment ->
# ichorCNA -> KrakenUniq (falls aktiv, auf allen Reads, wie im
# ursprünglichen krakenuniq-report) -> Report.
# Wird von run_pipeline.sh aufgerufen, nicht direkt.
#
# Jeder Schritt prüft zuerst, ob sein Ergebnis in tmp/<sample>/ bzw.
# output/<sample>/ bereits vorhanden ist, und überspringt ihn dann --
# ein erneuter Aufruf für eine bereits (teilweise) verarbeitete Probe
# wiederholt nur die fehlenden Schritte und rendert den Report neu.
#
# Zwischendateien (BAM, FASTQ, ichorCNA-Rohdaten) landen in tmp/<sample>/;
# output/<sample>/ enthält nur die Deliverables (PDF, KrakenUniq-Report,
# JSON, Nexus-Befund.docx).
#
# Usage:
#   Nanopore:  sample_pipeline.sh nanopore <sample> <reads1.fastq.gz> [reads2 ...]
#   Illumina:  sample_pipeline.sh illumina <sample> <R1.fastq.gz> <R2.fastq.gz>
#SBATCH --job-name=mngs
#SBATCH --partition=normal
#SBATCH --cpus-per-task=36
#SBATCH --mem=80G
#SBATCH --time=30:00
#SBATCH --error=./log/%x_%j.err.txt
#SBATCH --output=./log/%x_%j.out.txt

set -euo pipefail

REPO_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO_ROOT"
source scripts/config.sh

PLATFORM="$1"
SAMPLE="$2"
shift 2
READS=("$@")

THREADS=${SLURM_CPUS_PER_TASK:-$THREADS_MINIMAP2}

TMP="tmp/$SAMPLE"
OUT="output/$SAMPLE"
mkdir -p "$OUT" log "$TMP"

echo "=== mNGS-Pipeline: $SAMPLE ($PLATFORM) ==="
echo "Threads: $THREADS"
echo "Reads:   ${READS[*]}"

# 1. Concat (nur Nanopore; Illumina-Paar wird direkt aligned)
if [ "$PLATFORM" = "nanopore" ]; then
    FASTQ="$TMP/$SAMPLE.fastq.gz"
    if [ -s "$FASTQ" ]; then
        echo "--- Concat: $FASTQ bereits vorhanden, überspringe ---"
    else
        bash scripts/concat_fastq.sh "$FASTQ" "${READS[@]}"
    fi
    ALIGN_INPUT=("$FASTQ")
    KU_READS=("$FASTQ")
elif [ "$PLATFORM" = "illumina" ]; then
    ALIGN_INPUT=("${READS[@]}")
    KU_READS=("${READS[@]}")
else
    echo "Unbekannte Plattform: $PLATFORM (erwartet: nanopore|illumina)" >&2
    exit 1
fi

# 2. Alignment gegen hg19 (nur für ichorCNA/Report-Statistik; KrakenUniq
# unten bekommt unabhängig davon alle Reads, wie im ursprünglichen
# krakenuniq-report -- keine Host-Depletion vorab).
BAM="$TMP/$SAMPLE.hg19.bam"
FLAGSTAT="$TMP/$SAMPLE.flagstat.txt"
export PATH="$ENV_ALIGN/bin:$PATH"
if [ -s "$BAM" ] && [ -s "$BAM.bai" ] && [ -s "$FLAGSTAT" ]; then
    echo "--- Alignment: $BAM bereits vorhanden, überspringe ---"
else
    echo "--- Alignment ($PLATFORM) ---"
    # Aligner + samtools kommen aus PALMA-Modulen, falls vorhanden, sonst conda.
    if [ "$PLATFORM" = "nanopore" ]; then
        if command -v module >/dev/null 2>&1; then
            module purge
            ml $MINIMAP2_MODULES $SAMTOOLS_MODULES
        fi
        minimap2 -ax map-ont --secondary=no -t "$THREADS" "$HG19_MMI_NANOPORE" "${ALIGN_INPUT[@]}" \
            | samtools sort -@ "$THREADS_SAMTOOLS_SORT" -o "$BAM" -
    else
        if command -v module >/dev/null 2>&1; then
            module purge
            ml $BWA_MEM2_MODULES $SAMTOOLS_MODULES
        fi
        bwa-mem2 mem -t "$THREADS" "$HG19_BWA_MEM2_PREFIX" "${ALIGN_INPUT[@]}" \
            | samtools sort -@ "$THREADS_SAMTOOLS_SORT" -o "$BAM" -
    fi
    samtools index "$BAM"
    samtools flagstat "$BAM" > "$FLAGSTAT"
fi

# ── 3. ichorCNA (readCounter + R, hg19-PoN, nanoDx-Parameter) ──────────────
CNV_PARAMS="$TMP/$SAMPLE.params.txt"
CNV_SEG="$TMP/$SAMPLE.seg.txt"
CNV_PLOT="$TMP/$SAMPLE/${SAMPLE}_genomeWide.png"
if [ -s "$CNV_PARAMS" ] && [ -s "$CNV_SEG" ] && [ -s "$CNV_PLOT" ]; then
    echo "--- ichorCNA: $CNV_PARAMS bereits vorhanden, überspringe ---"
else
    echo "--- ichorCNA ---"
    WIG="$TMP/$SAMPLE.$ICHORCNA_BIN_LABEL.wig"
    CHROMS=$(printf 'chr%s,' {1..22}; echo "chrX,chrY")
    readCounter --window "$ICHORCNA_BIN_SIZE" --quality 20 --chromosome "$CHROMS" "$BAM" > "$WIG"

    export PATH="$ENV_ICHORCNA/bin:$PATH"
    EXTDATA_DIR=$(Rscript -e 'cat(system.file("extdata", package="ichorCNA"))')
    Rscript scripts/run_ichorcna.R \
        --WIG "$WIG" \
        --gcWig "$EXTDATA_DIR/$ICHORCNA_GC_WIG" \
        --mapWig "$EXTDATA_DIR/$ICHORCNA_MAP_WIG" \
        --centromere "$EXTDATA_DIR/$ICHORCNA_CENTROMERE" \
        --normalPanel "$EXTDATA_DIR/$ICHORCNA_NORMAL_PANEL" \
        --id "$SAMPLE" \
        --outDir "$TMP" \
        --genomeBuild "$ICHORCNA_GENOME_BUILD" \
        --genomeStyle "$ICHORCNA_GENOME_STYLE" \
        --chrs "$ICHORCNA_CHRS" \
        --chrNormalize "$ICHORCNA_CHR_NORMALIZE" \
        --chrTrain "$ICHORCNA_CHR_TRAIN" \
        --normal "$ICHORCNA_NORMAL" \
        --ploidy "$ICHORCNA_PLOIDY" \
        --minMapScore "$ICHORCNA_MIN_MAP_SCORE" \
        --txnStrength "$ICHORCNA_TXN_STRENGTH" \
        --txnE "$ICHORCNA_TXN_E" \
        --normalizeMaleX "$ICHORCNA_NORMALIZE_MALE_X" \
        --estimateScPrevalence "$ICHORCNA_ESTIMATE_SC_PREVALENCE" \
        --plotYLim "$ICHORCNA_PLOT_Y_LIM" \
        --includeHOMD "$ICHORCNA_INCLUDE_HOMD" \
        --plotFileType png \
        --cores "$THREADS_ICHORCNA"
fi

# ── 4. KrakenUniq (alle Reads, wie im ursprünglichen krakenuniq-report) ────
KU_REPORT="$OUT/$SAMPLE.krakenuniq.report.txt"
if [ "$KRAKENUNIQ_ENABLED" = "true" ]; then
    if [ -s "$KU_REPORT" ]; then
        echo "--- KrakenUniq: $KU_REPORT bereits vorhanden, überspringe ---"
    else
        echo "--- KrakenUniq ---"
        eval "$MODULE_PREFIX"
        export PATH="$KRAKENUNIQ_BIN_DIR:$EXTRA_BIN_DIR:$ENV_KRAKENUNIQ/bin:$PATH"
        bash scripts/krakenuniq_run.sh "$KRAKENUNIQ_DB" "$THREADS_KRAKENUNIQ" "$KRAKENUNIQ_PRELOAD_SIZE" \
            "$KU_REPORT" "$TMP" "${KU_READS[@]}"
    fi
else
    echo "--- KrakenUniq übersprungen (KRAKENUNIQ_ENABLED=$KRAKENUNIQ_ENABLED) ---"
fi

# ── 5. Report (PDF mit CNV-Plot + Top-Hits, JSON, Nexus-Befund.docx) ───────
# Läuft immer, auch wenn alle Schritte oben übersprungen wurden -- so lässt
# sich der Report nach einer Layout-Änderung für eine bereits verarbeitete
# Probe einfach durch erneuten Aufruf dieses Skripts neu rendern.
# Ausgelagert nach generate_sample_report.sh, das denselben Weg auch für ein
# reines Report-Rebuild ohne die Schritte oben nutzt.
echo "--- Report ---"
bash scripts/generate_sample_report.sh "$SAMPLE" "$PLATFORM"

echo "=== Fertig: $SAMPLE ==="
