#!/bin/bash
# Erstellt PDF/JSON/docx für eine Probe aus vorhandenen Zwischendateien
# (tmp/<sample>/, output/<sample>/krakenuniq.report.txt) -- ohne Alignment/
# ichorCNA/KrakenUniq neu laufen zu lassen. Wird von sample_pipeline.sh als
# letzter Schritt aufgerufen; lässt sich aber auch eigenständig nutzen, um
# nach einer Report-Änderung nur den Report neu zu bauen (z.B. nach einem
# Layout-Update in generate_report_v3.py), ohne die restliche Pipeline neu
# laufen zu lassen:
#   bash scripts/generate_sample_report.sh <sample> <nanopore|illumina>
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
source scripts/config.sh

SAMPLE="$1"
PLATFORM="$2"

TMP="tmp/$SAMPLE"
OUT="output/$SAMPLE"
mkdir -p "$OUT"

for f in "$TMP/$SAMPLE.flagstat.txt" "$TMP/$SAMPLE.read_counts.tsv" "$TMP/$SAMPLE.params.txt" "$TMP/$SAMPLE/${SAMPLE}_genomeWide.png"; do
    [ -s "$f" ] || { echo "FEHLER: $f fehlt -- Alignment/ichorCNA muss zuerst laufen" >&2; exit 1; }
done

KU_REPORT=""
[ -s "$OUT/$SAMPLE.krakenuniq.report.txt" ] && KU_REPORT="$OUT/$SAMPLE.krakenuniq.report.txt"

export PATH="$ENV_REPORT/bin:$PATH"
python3 scripts/build_report.py \
    --sample "$SAMPLE" --platform "$PLATFORM" \
    --flagstat "$TMP/$SAMPLE.flagstat.txt" \
    --read-counts "$TMP/$SAMPLE.read_counts.tsv" \
    --ichorcna-params "$TMP/$SAMPLE.params.txt" \
    --ichorcna-plot "$TMP/$SAMPLE/${SAMPLE}_genomeWide.png" \
    --krakenuniq-report "$KU_REPORT" \
    --output-pdf "$OUT/$SAMPLE.metagenomics_report.pdf" \
    --output-json "$OUT/$SAMPLE.summary.json" \
    --output-docx "$OUT/${SAMPLE}_Nexus_Befund.docx"

echo "  $OUT/$SAMPLE.metagenomics_report.pdf"
echo "  $OUT/$SAMPLE.krakenuniq.report.txt"
echo "  $OUT/$SAMPLE.summary.json"
echo "  $OUT/${SAMPLE}_Nexus_Befund.docx"
