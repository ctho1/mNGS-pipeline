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

# Absolute Pfade auflösen, BEVOR ins tmp-Verzeichnis gewechselt wird -- sonst
# lösen die übrigen relativen Pfade (Report-Datei, Read-Dateien) nach dem cd
# falsch auf (führte zu "malformed fasta"-Fehlern in krakenuniq).
report="$(cd "$(dirname "$report")" && pwd)/$(basename "$report")"
report_tmp="${report}.tmp.${SLURM_JOB_ID:-$$}"
rm -f "$report_tmp"
reads=()
for f in "$@"; do
    reads+=("$(cd "$(dirname "$f")" && pwd)/$(basename "$f")")
done

cd "$tmp"

if [ "${#reads[@]}" -eq 2 ]; then
    krakenuniq --preload-size "$preload" --report-file "$report_tmp" \
        --db "$db" --threads "$threads" --output - --paired "${reads[@]}"
else
    krakenuniq --preload-size "$preload" --report-file "$report_tmp" \
        --db "$db" --threads "$threads" --output - "${reads[@]}"
fi

# Erst nach erfolgreichem Abschluss veröffentlichen. Das verhindert, dass ein
# auf einer requeue-Partition unterbrochener Teilreport beim Neustart als
# vollständiges Ergebnis erkannt wird.
mv "$report_tmp" "$report"
