#!/bin/bash
# Analysepfad für eine Probe: Concat (nur Nanopore) -> hg19-Alignment ->
# Extraktion nicht-humaner Reads -> ichorCNA -> KrakenUniq (falls aktiv,
# nur auf nicht-humanen Reads) -> Report.
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
#SBATCH --mem=120G
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
elif [ "$PLATFORM" = "illumina" ]; then
    ALIGN_INPUT=("${READS[@]}")
else
    echo "Unbekannte Plattform: $PLATFORM (erwartet: nanopore|illumina)" >&2
    exit 1
fi

# 2. Alignment gegen hg19 für ichorCNA, Report-Statistik und Host-Depletion.
# Das vollständige BAM bleibt erhalten, damit flagstat weiterhin alle Reads
# als Nenner verwendet. Die nicht-humanen FASTQs werden danach daraus
# extrahiert, ohne ein zweites Alignment durchzuführen.
BAM="$TMP/$SAMPLE.hg19.bam"
FLAGSTAT="$TMP/$SAMPLE.flagstat.txt"
export PATH="$ENV_ALIGN/bin:$PATH"

# Module auch bei einem Resume-Lauf laden: Die Host-Depletion benötigt
# samtools selbst dann, wenn das Alignment-BAM bereits vorhanden ist.
if command -v module >/dev/null 2>&1; then
    module purge
    if [ "$PLATFORM" = "nanopore" ]; then
        ml $MINIMAP2_MODULES $SAMTOOLS_MODULES
    else
        ml $BWA_MEM2_MODULES $SAMTOOLS_MODULES
    fi
fi

if [ -s "$BAM" ] && [ -s "$BAM.bai" ] && [ -s "$FLAGSTAT" ]; then
    echo "--- Alignment: $BAM bereits vorhanden, überspringe ---"
else
    echo "--- Alignment ($PLATFORM) ---"
    # Aligner + samtools kommen aus PALMA-Modulen, falls vorhanden, sonst conda.
    if [ "$PLATFORM" = "nanopore" ]; then
        minimap2 -ax map-ont --secondary=no -t "$THREADS" "$HG19_MMI_NANOPORE" "${ALIGN_INPUT[@]}" \
            | samtools sort -@ "$THREADS_SAMTOOLS_SORT" -o "$BAM" -
    else
        bwa-mem2 mem -t "$THREADS" "$HG19_BWA_MEM2_PREFIX" "${ALIGN_INPUT[@]}" \
            | samtools sort -@ "$THREADS_SAMTOOLS_SORT" -o "$BAM" -
    fi
    samtools index "$BAM"
    samtools flagstat "$BAM" > "$FLAGSTAT"
fi

# ── 3. Nicht-humane Reads für KrakenUniq extrahieren ──────────────────────
# Nanopore: jeder unmapped Read (SAM-Flag 0x4).
# Illumina: nur vollständige Paare, bei denen Read und Mate unmapped sind
# (0x4 + 0x8 = 0xC/12). Dadurch gelangen keine verwaisten Mates eines human
# gemappten Fragments in die taxonomische Klassifikation.
if [ "$PLATFORM" = "nanopore" ]; then
    NONHUMAN_FASTQ="$TMP/$SAMPLE.nonhuman.fastq.gz"
    KU_READS=("$NONHUMAN_FASTQ")

    if [ -s "$NONHUMAN_FASTQ" ]; then
        echo "--- Host-Depletion: $NONHUMAN_FASTQ bereits vorhanden, überspringe ---"
    else
        echo "--- Host-Depletion (Nanopore: unmapped Reads) ---"
        NONHUMAN_FASTQ_TMP="$TMP/$SAMPLE.nonhuman.tmp.fastq.gz"
        rm -f "$NONHUMAN_FASTQ_TMP"
        samtools fastq -@ "$THREADS_SAMTOOLS_SORT" -f 4 \
            -0 "$NONHUMAN_FASTQ_TMP" "$BAM"
        mv "$NONHUMAN_FASTQ_TMP" "$NONHUMAN_FASTQ"
    fi
else
    NONHUMAN_R1="$TMP/$SAMPLE.nonhuman_R1.fastq.gz"
    NONHUMAN_R2="$TMP/$SAMPLE.nonhuman_R2.fastq.gz"
    KU_READS=("$NONHUMAN_R1" "$NONHUMAN_R2")

    if [ -s "$NONHUMAN_R1" ] && [ -s "$NONHUMAN_R2" ]; then
        echo "--- Host-Depletion: nicht-humane Read-Paare bereits vorhanden, überspringe ---"
    else
        echo "--- Host-Depletion (Illumina: beide Mates unmapped) ---"
        NONHUMAN_R1_TMP="$TMP/$SAMPLE.nonhuman_R1.tmp.fastq.gz"
        NONHUMAN_R2_TMP="$TMP/$SAMPLE.nonhuman_R2.tmp.fastq.gz"
        rm -f "$NONHUMAN_R1_TMP" "$NONHUMAN_R2_TMP"
        samtools view -@ "$THREADS_SAMTOOLS_SORT" -u -f 12 "$BAM" \
            | samtools collate -@ "$THREADS_SAMTOOLS_SORT" -u -O - \
            | samtools fastq -@ "$THREADS_SAMTOOLS_SORT" \
                -1 "$NONHUMAN_R1_TMP" \
                -2 "$NONHUMAN_R2_TMP" \
                -0 /dev/null -s /dev/null -n -
        mv "$NONHUMAN_R1_TMP" "$NONHUMAN_R1"
        mv "$NONHUMAN_R2_TMP" "$NONHUMAN_R2"
    fi
fi

# ── 4. ichorCNA (readCounter + R, hg19-PoN, nanoDx-Parameter) ──────────────
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

# ── 5. KrakenUniq (nur Reads ohne humanes Alignment) ──────────────────────
KU_REPORT="$OUT/$SAMPLE.krakenuniq.report.txt"
if [ "$KRAKENUNIQ_ENABLED" = "true" ]; then
    KU_REPORT_CURRENT=false
    if [ -s "$KU_REPORT" ]; then
        KU_REPORT_CURRENT=true
        for reads_file in "${KU_READS[@]}"; do
            if [ ! "$KU_REPORT" -nt "$reads_file" ]; then
                KU_REPORT_CURRENT=false
                break
            fi
        done
    fi

    if [ "$KU_REPORT_CURRENT" = "true" ]; then
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

# ── 6. Report (PDF mit CNV-Plot + Top-Hits, JSON, Nexus-Befund.docx) ───────
# Läuft immer, auch wenn alle Schritte oben übersprungen wurden -- so lässt
# sich der Report nach einer Layout-Änderung für eine bereits verarbeitete
# Probe einfach durch erneuten Aufruf dieses Skripts neu rendern.
# Ausgelagert nach generate_sample_report.sh, das denselben Weg auch für ein
# reines Report-Rebuild ohne die Schritte oben nutzt.
echo "--- Report ---"
bash scripts/generate_sample_report.sh "$SAMPLE" "$PLATFORM"

echo "=== Fertig: $SAMPLE ==="
