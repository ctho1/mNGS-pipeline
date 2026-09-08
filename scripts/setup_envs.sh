#!/bin/bash
# =============================================================================
# setup_envs.sh -- legt alle Conda-Umgebungen an (lokal macOS zum Testen,
# oder direkt auf PALMA/Linux zum produktiven Einsatz inkl. KrakenUniq).
#
# Einmalig aufrufen, danach reicht `bash run_pipeline.sh` (siehe README).
# Nutzt Miniforge/Mambaforge (Installation siehe README).
#
# macOS/Apple Silicon (osx-arm64): r-ichorcna hat dort keinen Build -> das
# ichorcna-Env wird explizit als osx-64 angelegt und läuft unter Rosetta 2;
# krakenuniq hat gar keinen osx-Build und wird übersprungen (siehe README zum
# lokalen Deaktivieren über KRAKENUNIQ_ENABLED=false in scripts/config.sh).
# Linux (PALMA): alle Envs, inkl. krakenuniq, laufen nativ.
# =============================================================================
set -euo pipefail

# CONDA_BASE: falls nicht explizit gesetzt, erst eine bereits aktive/auf PATH
# befindliche Installation nutzen (z.B. auf PALMA per Modul/eigenem Setup
# bereitgestellt, "(base)" im Prompt aktiv), sonst Miniforge-Standardpfad.
if [ -z "${CONDA_BASE:-}" ]; then
    if command -v conda >/dev/null 2>&1; then
        CONDA_BASE="$(conda info --base)"
    else
        CONDA_BASE="$HOME/miniforge3"
    fi
fi
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$REPO_ROOT}"
ENV_DIR="$WORK_DIR/conda_envs"

if [ ! -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
    echo "Conda-Installation nicht gefunden unter: $CONDA_BASE" >&2
    echo "Setze CONDA_BASE explizit, z.B.:" >&2
    echo "  CONDA_BASE=\$(conda info --base) bash scripts/setup_envs.sh" >&2
    exit 1
fi
source "$CONDA_BASE/etc/profile.d/conda.sh"

# mamba bevorzugen (schneller), sonst conda -- erst auf PATH, dann im
# erkannten CONDA_BASE suchen.
if command -v mamba >/dev/null 2>&1; then
    MAMBA="$(command -v mamba)"
elif [ -x "$CONDA_BASE/bin/mamba" ]; then
    MAMBA="$CONDA_BASE/bin/mamba"
else
    MAMBA="$CONDA_BASE/bin/conda"
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

mkdir -p "$ENV_DIR"

echo "=== align (minimap2, samtools, readCounter) ==="
if [ ! -d "$ENV_DIR/align" ]; then
    "$MAMBA" env create -y --override-channels -p "$ENV_DIR/align" -f "$REPO_ROOT/scripts/envs/align.yaml"
else
    echo "  bereits vorhanden, überspringe"
fi

echo "=== report (python, reportlab, python-docx) ==="
if [ ! -d "$ENV_DIR/report" ]; then
    "$MAMBA" env create -y --override-channels -p "$ENV_DIR/report" -f "$REPO_ROOT/scripts/envs/report.yaml"
else
    echo "  bereits vorhanden, überspringe"
fi

echo "=== ichorcna (R, r-ichorcna) ==="
if [ ! -d "$ENV_DIR/ichorcna" ]; then
    if [ "$OS" = "Darwin" ] && [ "$ARCH" = "arm64" ]; then
        echo "  kein osx-arm64-Build -- Env läuft unter Rosetta 2 (osx-64)"
        CONDA_SUBDIR=osx-64 "$MAMBA" env create -y --override-channels -p "$ENV_DIR/ichorcna" -f "$REPO_ROOT/scripts/envs/ichorcna.yaml"
        echo "subdir: osx-64" >> "$ENV_DIR/ichorcna/.condarc"
    else
        "$MAMBA" env create -y --override-channels -p "$ENV_DIR/ichorcna" -f "$REPO_ROOT/scripts/envs/ichorcna.yaml"
    fi
else
    echo "  bereits vorhanden, überspringe"
fi

echo "=== krakenuniq ==="
if [ "$OS" = "Linux" ]; then
    if [ ! -d "$ENV_DIR/krakenuniq" ]; then
        "$MAMBA" env create -y --override-channels -p "$ENV_DIR/krakenuniq" -f "$REPO_ROOT/scripts/envs/krakenuniq.yaml"
    else
        echo "  bereits vorhanden, überspringe"
    fi
else
    echo "  übersprungen (kein osx-Build) -- lokal mit KRAKENUNIQ_ENABLED=false deaktivieren"
    echo "  (siehe scripts/config.sh oder: KRAKENUNIQ_ENABLED=false bash run_pipeline.sh)"
fi

echo ""
echo "=== Fertig. Envs liegen unter $ENV_DIR ==="
