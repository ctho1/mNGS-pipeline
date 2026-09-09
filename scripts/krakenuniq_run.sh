#!/bin/bash
# Runs krakenuniq on one (Nanopore) or two (Illumina, --paired) FASTQ files;
# mode inferred from argument count.
#
# Usage (SE): krakenuniq_run.sh <db> <threads> <preload> <report_out> <tmpdir> <reads.fastq.gz>
# Usage (PE): krakenuniq_run.sh <db> <threads> <preload> <report_out> <tmpdir> <R1.fastq.gz> <R2.fastq.gz>
set -euo pipefail
db="$1"; threads="$2"; preload="$3"; report="$4"; tmp="$5"
shift 5

mkdir -p "$tmp" "$(dirname "$report")"
cd "$tmp"

if [ "$#" -eq 2 ]; then
    krakenuniq --preload-size "$preload" --report-file "$report" \
        --db "$db" --threads "$threads" --output - --paired "$1" "$2"
else
    krakenuniq --preload-size "$preload" --report-file "$report" \
        --db "$db" --threads "$threads" --output - "$1"
fi
