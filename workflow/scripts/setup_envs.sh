#!/bin/bash
# =============================================================================
# setup_envs.sh -- legt alle Conda-Umgebungen an (lokal macOS zum Testen,
# oder direkt auf PALMA/Linux zum produktiven Einsatz inkl. KrakenUniq).
#
# Einmalig aufrufen, danach reicht `snakemake ...` (siehe README).
# Nutzt Miniforge/Mambaforge (Installation siehe README).
#
# macOS/Apple Silicon (osx-arm64): r-ichorcna hat dort keinen Build -> das
# ichorcna-Env wird explizit als osx-64 angelegt und läuft unter Rosetta 2;
# krakenuniq hat gar keinen osx-Build und wird übersprungen (siehe README zum
# lokalen Deaktivieren über krakenuniq.enabled=false).
# Linux (PALMA): alle Envs, inkl. krakenuniq, laufen nativ.
# =============================================================================
set -euo pipefail

CONDA_BASE="${CONDA_BASE:-$HOME/miniforge3}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${WORK_DIR:-$REPO_ROOT}"
ENV_DIR="$WORK_DIR/conda_envs"

source "$CONDA_BASE/etc/profile.d/conda.sh"
MAMBA="$CONDA_BASE/bin/mamba"
command -v "$MAMBA" >/dev/null || MAMBA="$CONDA_BASE/bin/conda"

OS="$(uname -s)"
ARCH="$(uname -m)"

mkdir -p "$ENV_DIR"

echo "=== snakemake (Workflow-Runner) ==="
if [ ! -d "$ENV_DIR/snakemake" ]; then
    "$MAMBA" create -y -p "$ENV_DIR/snakemake" -c bioconda -c conda-forge snakemake-minimal=9
else
    echo "  bereits vorhanden, überspringe"
fi

echo "=== align (minimap2, samtools, readCounter) ==="
if [ ! -d "$ENV_DIR/align" ]; then
    "$MAMBA" env create -y -p "$ENV_DIR/align" -f "$REPO_ROOT/workflow/envs/align.yaml"
else
    echo "  bereits vorhanden, überspringe"
fi

echo "=== report (python, reportlab) ==="
if [ ! -d "$ENV_DIR/report" ]; then
    "$MAMBA" env create -y -p "$ENV_DIR/report" -f "$REPO_ROOT/workflow/envs/report.yaml"
else
    echo "  bereits vorhanden, überspringe"
fi

echo "=== ichorcna (R, r-ichorcna) ==="
if [ ! -d "$ENV_DIR/ichorcna" ]; then
    if [ "$OS" = "Darwin" ] && [ "$ARCH" = "arm64" ]; then
        echo "  kein osx-arm64-Build -- Env läuft unter Rosetta 2 (osx-64)"
        CONDA_SUBDIR=osx-64 "$MAMBA" env create -y -p "$ENV_DIR/ichorcna" -f "$REPO_ROOT/workflow/envs/ichorcna.yaml"
        echo "subdir: osx-64" >> "$ENV_DIR/ichorcna/.condarc"
    else
        "$MAMBA" env create -y -p "$ENV_DIR/ichorcna" -f "$REPO_ROOT/workflow/envs/ichorcna.yaml"
    fi
else
    echo "  bereits vorhanden, überspringe"
fi

echo "=== krakenuniq ==="
if [ "$OS" = "Linux" ]; then
    if [ ! -d "$ENV_DIR/krakenuniq" ]; then
        "$MAMBA" env create -y -p "$ENV_DIR/krakenuniq" -f "$REPO_ROOT/workflow/envs/krakenuniq.yaml"
    else
        echo "  bereits vorhanden, überspringe"
    fi
else
    echo "  übersprungen (kein osx-Build) -- lokal mit --config 'krakenuniq={\"enabled\": false}' deaktivieren"
fi

echo ""
echo "=== Fertig. Envs liegen unter $ENV_DIR ==="
