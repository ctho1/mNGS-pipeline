#!/bin/bash
# Entry point: scans input/ and runs the pipeline per sample. Submits one
# SLURM job per sample if sbatch is available, else runs them directly/
# serially (local testing). Must be run from the repo root (relative paths).
#
# Usage:
#   bash run_pipeline.sh [--mail user@uni-muenster.de]
#   bash run_pipeline.sh --partition normal   # automatische Auswahl umgehen
#   KRAKENUNIQ_ENABLED=false bash run_pipeline.sh   # local test, no DB
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
source scripts/config.sh

PARTITION_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mail) MAIL_USER="$2"; shift 2 ;;
        --partition) PARTITION_OVERRIDE="$2"; shift 2 ;;
        *)      echo "Unknown argument: $1"; exit 1 ;;
    esac
done

MAIL_ARGS=()
if [[ -n "$MAIL_USER" ]]; then
    MAIL_ARGS=(--mail-user="$MAIL_USER" --mail-type=ALL)
fi

mkdir -p log output tmp input references

USE_SLURM=0
command -v sbatch >/dev/null 2>&1 && USE_SLURM=1
if [ "$USE_SLURM" = "1" ]; then
    echo "SLURM erkannt -- reiche Jobs per sbatch ein."
else
    echo "Kein SLURM (sbatch nicht gefunden) -- führe Proben direkt/seriell aus."
fi

SBATCH_PARTITION_ARGS=()
if [ "$USE_SLURM" = "1" ]; then
    if [ -n "$PARTITION_OVERRIDE" ]; then
        SELECTED_PARTITIONS="$PARTITION_OVERRIDE"
        echo "SLURM-Partition manuell gesetzt: $SELECTED_PARTITIONS"
    elif [ "$SLURM_AUTO_PARTITION" = "true" ]; then
        SELECTED_PARTITIONS=$(python3 scripts/select_slurm_partitions.py \
            --partitions "$SLURM_CPU_PARTITIONS" \
            --fallback "$SLURM_FALLBACK_PARTITION")
        echo "SLURM-Partitionen nach freier CPU-Kapazität: $SELECTED_PARTITIONS"
    else
        SELECTED_PARTITIONS="$SLURM_FALLBACK_PARTITION"
        echo "Automatische Partitionswahl deaktiviert: $SELECTED_PARTITIONS"
    fi
    SBATCH_PARTITION_ARGS=(--partition="$SELECTED_PARTITIONS")
fi

# Reference (build once, submit as a dependency for all sample jobs)
REF_DEP=()
if [ ! -s "$HG19_MMI_NANOPORE" ] || [ ! -s "$HG19_BWA_MEM2_PREFIX.bwt.2bit.64" ]; then
    echo ""
    echo "=== Referenz fehlt -- wird vorbereitet ==="
    if [ "$USE_SLURM" = "1" ]; then
        REF_JOBID=$(sbatch --parsable "${MAIL_ARGS[@]}" "${SBATCH_PARTITION_ARGS[@]}" \
            scripts/prepare_reference.sh)
        REF_DEP=(--dependency=afterok:"$REF_JOBID")
        echo "  Referenz-Job: $REF_JOBID (alle Probenjobs warten darauf)"
    else
        bash scripts/prepare_reference.sh
    fi
fi

submitted=0
skipped=0

# Proben in input/ erkennen (flach, keine Unterordner): Illumina-R1/R2-Paare
# und Nanopore-Dateien gruppiert nach gemeinsamem Namensstamm (alles vor der
# letzten "_<Zahl>", z.B. PBM37034_pass_barcode05_xxx_0.fastq.gz + ..._1 ->
# eine Probe), numerisch nach Chunk-Nummer sortiert. Siehe scripts/discover_samples.py.
echo ""
echo "=== Proben in input/ ==="
skip_log="$(mktemp)"
while IFS=$'\t' read -r -a fields; do
    platform="${fields[0]}"
    sample="${fields[1]}"
    reads=("${fields[@]:2}")
    echo "  Submitting $sample ($platform, ${#reads[@]} Datei(en))"
    if [ "$USE_SLURM" = "1" ]; then
        sbatch "${MAIL_ARGS[@]}" "${REF_DEP[@]}" "${SBATCH_PARTITION_ARGS[@]}" \
            --job-name="$sample" \
            scripts/sample_pipeline.sh "$platform" "$sample" "${reads[@]}"
    else
        bash scripts/sample_pipeline.sh "$platform" "$sample" "${reads[@]}"
    fi
    (( submitted++ )) || true
done < <(python3 scripts/discover_samples.py input 2>"$skip_log")
sed 's/^/  /' "$skip_log" >&2
skipped=$(wc -l < "$skip_log" | tr -d ' ')
rm -f "$skip_log"

echo ""
if [ "$USE_SLURM" = "1" ]; then
    echo "=== $submitted Job(s) eingereicht | $skipped übersprungen ==="
else
    echo "=== $submitted Probe(n) fertig ausgeführt | $skipped übersprungen ==="
fi
