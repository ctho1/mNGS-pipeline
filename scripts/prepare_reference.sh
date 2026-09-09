#!/bin/bash
# Stellt hg19-Fasta + minimap2-/bwa-mem2-Index bereit, falls fehlend.
# Bevorzugt die geteilte hg19-Fasta/-Index von ngs-tumor-pipeline
# (EXISTING_HG19_FASTA, scripts/config.sh) per Symlink, sonst Download+Bau.
# Läuft einmalig vor allen Probenjobs (siehe run_pipeline.sh).
#SBATCH --job-name=prepare_reference
#SBATCH --partition=normal
#SBATCH --cpus-per-task=12
#SBATCH --mem=48G
#SBATCH --time=3:00:00
#SBATCH --error=./log/%x_%j.err.txt
#SBATCH --output=./log/%x_%j.out.txt

set -euo pipefail

REPO_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO_ROOT"
source scripts/config.sh

THREADS=${SLURM_CPUS_PER_TASK:-$THREADS_MINIMAP2}

mkdir -p references log

echo "=== Referenz vorbereiten (hg19) ==="

if [ ! -s "$HG19_FASTA" ]; then
    if [ -s "$EXISTING_HG19_FASTA" ]; then
        echo "Nutze vorhandene hg19-Fasta: $EXISTING_HG19_FASTA"
        ln -s "$EXISTING_HG19_FASTA" "$HG19_FASTA"
    else
        GZ="references/hg19.fa.gz"
        [ -s "$GZ" ] || { echo "Lade $HG19_FASTA_URL ..."; curl -fL -o "$GZ" "$HG19_FASTA_URL"; }
        gzip -dc "$GZ" > "$HG19_FASTA"
    fi
fi

export PATH="$ENV_ALIGN/bin:$PATH"

# Aligner + samtools kommen aus PALMA-Modulen, falls vorhanden, sonst conda.
if command -v module >/dev/null 2>&1; then
    module purge
    ml $MINIMAP2_MODULES $BWA_MEM2_MODULES $SAMTOOLS_MODULES
fi

if [ -s "$EXISTING_HG19_FASTA.fai" ] && [ ! -s "$HG19_FASTA.fai" ]; then
    ln -s "$EXISTING_HG19_FASTA.fai" "$HG19_FASTA.fai"
else
    [ -s "$HG19_FASTA.fai" ] || samtools faidx "$HG19_FASTA"
fi

# minimap2-Index (Nanopore) -- kein bekannter vorhandener Index, wird gebaut
if [ ! -s "$HG19_MMI_NANOPORE" ]; then
    echo "Baue minimap2-Index (map-ont) ..."
    minimap2 -x map-ont -t "$THREADS" -d "$HG19_MMI_NANOPORE" "$HG19_FASTA"
fi

# bwa-mem2-Index (Illumina) -- geteilten Index nutzen, falls vorhanden
if [ ! -s "$HG19_BWA_MEM2_PREFIX.bwt.2bit.64" ]; then
    if [ -s "$EXISTING_HG19_FASTA.bwt.2bit.64" ]; then
        echo "Nutze vorhandenen bwa-mem2-Index: $EXISTING_HG19_FASTA.*"
        for ext in 0123 amb ann bwt.2bit.64 pac; do
            ln -sf "$EXISTING_HG19_FASTA.$ext" "$HG19_FASTA.$ext"
        done
    else
        echo "Baue bwa-mem2-Index ..."
        bwa-mem2 index "$HG19_FASTA"
    fi
fi

echo "=== Referenz bereit ==="
