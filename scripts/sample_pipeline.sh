#!/bin/bash
# =============================================================================
# sample_pipeline.sh -- kompletter Analysepfad für EINE Probe:
#   Concat (nur Nanopore) -> hg38-Alignment -> Host-Depletion -> ichorCNA
#   -> KrakenUniq (falls aktiviert) -> Report (PDF/JSON/Nexus-docx)
#
# Wird von run_pipeline.sh als sbatch-Job (oder lokal direkt) je Probe
# aufgerufen, nicht direkt vom Nutzer.
#
# Usage:
#   Nanopore:  sample_pipeline.sh nanopore <sample> <reads1.fastq.gz> [reads2 ...]
#   Illumina:  sample_pipeline.sh illumina <sample> <R1.fastq.gz> <R2.fastq.gz>
#
# sbatch-Flags hier sind nur Defaults für einen direkten
# `sbatch scripts/sample_pipeline.sh ...`-Aufruf; run_pipeline.sh übergibt
# beim Submit eigene Flags, die diese überschreiben.
# =============================================================================
#SBATCH --job-name=mngs
#SBATCH --partition=requeue
#SBATCH --cpus-per-task=36
#SBATCH --mem=140G
#SBATCH --time=4:00:00
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

mkdir -p "output/$SAMPLE" log "tmp/$SAMPLE"
OUT="output/$SAMPLE"

echo "=== mNGS-Pipeline: $SAMPLE ($PLATFORM) ==="
echo "Threads: $THREADS"
echo "Reads:   ${READS[*]}"

# ── 1. Concat (nur Nanopore; Illumina-Paar wird direkt aligned) ────────────
if [ "$PLATFORM" = "nanopore" ]; then
    FASTQ="$OUT/$SAMPLE.fastq.gz"
    bash scripts/concat_fastq.sh "$FASTQ" "${READS[@]}"
    ALIGN_INPUT=("$FASTQ")
    MMI="$HG38_MMI_NANOPORE"
    PRESET="map-ont"
elif [ "$PLATFORM" = "illumina" ]; then
    ALIGN_INPUT=("${READS[@]}")
    MMI="$HG38_MMI_ILLUMINA"
    PRESET="sr"
else
    echo "Unbekannte Plattform: $PLATFORM (erwartet: nanopore|illumina)" >&2
    exit 1
fi

# ── 2. Alignment gegen hg38 ─────────────────────────────────────────────────
echo "--- Alignment (minimap2 -ax $PRESET) ---"
BAM="$OUT/$SAMPLE.hg38.bam"
export PATH="$ENV_ALIGN/bin:$PATH"
minimap2 -ax "$PRESET" --secondary=no -t "$THREADS" "$MMI" "${ALIGN_INPUT[@]}" \
    | samtools sort -@ "$THREADS_SAMTOOLS_SORT" -o "$BAM" -
samtools index "$BAM"
samtools flagstat "$BAM" > "$OUT/$SAMPLE.flagstat.txt"

# ── 3. Host-Depletion (non-human Reads -> KrakenUniq-Input) ────────────────
echo "--- Host-Depletion ---"
if [ "$PLATFORM" = "nanopore" ]; then
    NONHUMAN="$OUT/$SAMPLE.nonhuman.fastq.gz"
    bash scripts/extract_nonhuman_se.sh "$BAM" "$NONHUMAN"
    KU_READS=("$NONHUMAN")
else
    R1="$OUT/$SAMPLE.nonhuman_R1.fastq.gz"
    R2="$OUT/$SAMPLE.nonhuman_R2.fastq.gz"
    bash scripts/extract_nonhuman_pe.sh "$BAM" "$R1" "$R2"
    KU_READS=("$R1" "$R2")
fi

# ── 4. ichorCNA (readCounter + R, hg38-PoN, nanoDx-Parameter) ──────────────
echo "--- ichorCNA ---"
WIG="$OUT/$SAMPLE.$ICHORCNA_BIN_LABEL.wig"
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
    --outDir "$OUT" \
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

CNV_PARAMS="$OUT/$SAMPLE.params.txt"
CNV_PLOT="$OUT/$SAMPLE/${SAMPLE}_genomeWide.png"

# ── 5. KrakenUniq (auf non-human Reads) ─────────────────────────────────────
KU_REPORT=""
if [ "$KRAKENUNIQ_ENABLED" = "true" ]; then
    echo "--- KrakenUniq ---"
    eval "$MODULE_PREFIX"
    export PATH="$KRAKENUNIQ_BIN_DIR:$EXTRA_BIN_DIR:$ENV_KRAKENUNIQ/bin:$PATH"
    KU_REPORT="$OUT/$SAMPLE.krakenuniq.report.txt"
    bash scripts/krakenuniq_run.sh "$KRAKENUNIQ_DB" "$THREADS_KRAKENUNIQ" "$KRAKENUNIQ_PRELOAD_SIZE" \
        "$KU_REPORT" "tmp/$SAMPLE" "${KU_READS[@]}"
else
    echo "--- KrakenUniq übersprungen (KRAKENUNIQ_ENABLED=$KRAKENUNIQ_ENABLED) ---"
fi

# ── 6. Report (PDF mit CNV-Plot + Host-Depletion, JSON, Nexus-Befund.docx) ──
echo "--- Report ---"
export PATH="$ENV_REPORT/bin:$PATH"
python3 scripts/build_report.py \
    --sample "$SAMPLE" --platform "$PLATFORM" \
    --flagstat "$OUT/$SAMPLE.flagstat.txt" \
    --ichorcna-params "$CNV_PARAMS" \
    --ichorcna-plot "$CNV_PLOT" \
    --krakenuniq-report "$KU_REPORT" \
    --output-pdf "$OUT/$SAMPLE.metagenomics_report.pdf" \
    --output-json "$OUT/$SAMPLE.summary.json" \
    --output-docx "$OUT/${SAMPLE}_Nexus_Befund.docx"

echo "=== Fertig: $SAMPLE ==="
echo "  $OUT/$SAMPLE.metagenomics_report.pdf"
echo "  $OUT/$SAMPLE.summary.json"
echo "  $OUT/${SAMPLE}_Nexus_Befund.docx"
