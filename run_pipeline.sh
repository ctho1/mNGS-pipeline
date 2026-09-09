#!/bin/bash
# Entry point: scans input/ and runs the pipeline per sample. Submits one
# SLURM job per sample if sbatch is available, else runs them directly/
# serially (local testing). Must be run from the repo root (relative paths).
#
# Usage:
#   bash run_pipeline.sh [--mail user@uni-muenster.de]
#   KRAKENUNIQ_ENABLED=false bash run_pipeline.sh   # local test, no DB
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
source scripts/config.sh

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mail) MAIL_USER="$2"; shift 2 ;;
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

# Reference (build once, submit as a dependency for all sample jobs)
REF_DEP=()
if [ ! -s "$HG19_MMI_NANOPORE" ] || [ ! -s "$HG19_BWA_MEM2_PREFIX.bwt.2bit.64" ]; then
    echo ""
    echo "=== Referenz fehlt -- wird vorbereitet ==="
    if [ "$USE_SLURM" = "1" ]; then
        REF_JOBID=$(sbatch --parsable "${MAIL_ARGS[@]}" scripts/prepare_reference.sh)
        REF_DEP=(--dependency=afterok:"$REF_JOBID")
        echo "  Referenz-Job: $REF_JOBID (alle Probenjobs warten darauf)"
    else
        bash scripts/prepare_reference.sh
    fi
fi

submitted=0
skipped=0

# Nanopore: subfolders in input/
echo ""
echo "=== Nanopore-Proben (input/<sample>/) ==="
for dir in input/*/; do
    [ -d "$dir" ] || continue
    sample=$(basename "$dir")
    # no mapfile/readarray (bash <4, e.g. macOS system bash)
    reads=()
    while IFS= read -r -d '' f; do
        reads+=("$f")
    done < <(find "$dir" -type f \( -name "*.fastq.gz" -o -name "*.fastq" \) -print0 | sort -z)
    if [ "${#reads[@]}" -eq 0 ]; then
        echo "  SKIP $sample (keine FASTQ-Dateien)"
        (( skipped++ )) || true
        continue
    fi
    echo "  Submitting $sample (${#reads[@]} Datei(en))"
    if [ "$USE_SLURM" = "1" ]; then
        sbatch "${MAIL_ARGS[@]}" "${REF_DEP[@]}" --job-name="$sample" \
            scripts/sample_pipeline.sh nanopore "$sample" "${reads[@]}"
    else
        bash scripts/sample_pipeline.sh nanopore "$sample" "${reads[@]}"
    fi
    (( submitted++ )) || true
done

# Illumina: R1/R2 pairs directly in input/
echo ""
echo "=== Illumina-Proben (input/*_R1_001.fastq.gz) ==="
while IFS= read -r -d '' r1; do
    r2="${r1/_R1_001.fastq.gz/_R2_001.fastq.gz}"
    if [ ! -f "$r2" ]; then
        echo "  SKIP $r1 (keine passende R2 gefunden: $r2)"
        (( skipped++ )) || true
        continue
    fi
    sample=$(basename "$r1" "_R1_001.fastq.gz")
    echo "  Submitting $sample"
    if [ "$USE_SLURM" = "1" ]; then
        sbatch "${MAIL_ARGS[@]}" "${REF_DEP[@]}" --job-name="$sample" \
            scripts/sample_pipeline.sh illumina "$sample" "$r1" "$r2"
    else
        bash scripts/sample_pipeline.sh illumina "$sample" "$r1" "$r2"
    fi
    (( submitted++ )) || true
done < <(find input -maxdepth 1 -type f -name "*_R1_001.fastq.gz" -print0 | sort -z)

echo ""
if [ "$USE_SLURM" = "1" ]; then
    echo "=== $submitted Job(s) eingereicht | $skipped übersprungen ==="
else
    echo "=== $submitted Probe(n) fertig ausgeführt | $skipped übersprungen ==="
fi
