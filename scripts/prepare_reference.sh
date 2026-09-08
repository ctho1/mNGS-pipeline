#!/bin/bash
# =============================================================================
# prepare_reference.sh -- lädt hg38 herunter und baut beide minimap2-Indizes
# (map-ont für Nanopore, sr für Illumina), falls noch nicht vorhanden.
# Wird einmalig von run_pipeline.sh submitted/ausgeführt; alle Probenjobs
# warten (per --dependency) darauf, falls per SLURM eingereicht.
#
# Direkter Aufruf (z.B. zum Vorab-Cachen der Referenz):
#   sbatch scripts/prepare_reference.sh
#   bash scripts/prepare_reference.sh          # lokal ohne SLURM
# =============================================================================
#SBATCH --job-name=prepare_reference
#SBATCH --partition=normal
#SBATCH --cpus-per-task=12
#SBATCH --mem=32G
#SBATCH --time=30:00
#SBATCH --error=./log/%x_%j.err.txt
#SBATCH --output=./log/%x_%j.out.txt

set -euo pipefail

REPO_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO_ROOT"
source scripts/config.sh

THREADS=${SLURM_CPUS_PER_TASK:-$THREADS_MINIMAP2}

mkdir -p references log

echo "=== Referenz vorbereiten (hg38, UCSC No-Alt Analysis Set) ==="

if [ ! -s "$HG38_FASTA" ]; then
    GZ="references/hg38.analysisSet.fa.gz"
    if [ ! -s "$GZ" ]; then
        echo "Lade $HG38_FASTA_URL ..."
        curl -fL -o "$GZ" "$HG38_FASTA_URL"
    fi
    gzip -dc "$GZ" > "$HG38_FASTA"
fi

export PATH="$ENV_ALIGN/bin:$PATH"

[ -s "$HG38_FASTA.fai" ] || samtools faidx "$HG38_FASTA"

# minimap2 kommt auf PALMA aus dem Modulsystem (nicht aus dem conda-align-
# Env); module purge löscht keine manuell gesetzten PATH-Einträge, samtools
# oben bleibt also weiter über conda erreichbar. Ohne Modulsystem (z.B.
# lokaler Testlauf ohne SLURM) wird das übersprungen -- dann kommt minimap2
# aus dem conda-align-Env.
command -v module >/dev/null 2>&1 && eval "$MINIMAP2_MODULE_PREFIX"

if [ ! -s "$HG38_MMI_NANOPORE" ]; then
    echo "Baue minimap2-Index (map-ont) ..."
    minimap2 -x map-ont -t "$THREADS" -d "$HG38_MMI_NANOPORE" "$HG38_FASTA"
fi

if [ ! -s "$HG38_MMI_ILLUMINA" ]; then
    echo "Baue minimap2-Index (sr) ..."
    minimap2 -x sr -t "$THREADS" -d "$HG38_MMI_ILLUMINA" "$HG38_FASTA"
fi

echo "=== Referenz bereit ==="
