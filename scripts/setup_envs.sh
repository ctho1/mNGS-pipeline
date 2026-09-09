#!/bin/bash
# Legt alle Conda-Envs an (macOS zum Testen, Linux/PALMA produktiv inkl.
# KrakenUniq). Einmalig aufrufen, danach reicht `bash run_pipeline.sh`.
#
# macOS/arm64: r-ichorcna hat keinen Build dort -> ichorcna-Env läuft unter
# Rosetta 2 (osx-64); krakenuniq hat keinen osx-Build und wird übersprungen.
#
# Nutzt `mamba create` statt `mamba env create -f`: die "env"-Subcommand
# unterstützt in älteren mamba-Versionen (u.a. PALMA) kein
# --override-channels. --no-channel-priority umgeht außerdem einen
# libmamba-Solver-Bug (mamba <2, sichtbar an "SOLVER_RULE_STRICT_REPO_
# PRIORITY not implemented"-Warnungen), der mit channel_priority=strict in
# der globalen .condarc zu spurious "unlösbar"-Fehlern führt (z.B.
# samtools/htslib, r-base/libtiff -- beide über libdeflate, ohne echten
# Versionskonflikt).
set -euo pipefail

# Bereits aktive/PATH-Installation nutzen (z.B. PALMA-Modul), sonst Miniforge-Default.
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

# mamba bevorzugen, sonst conda
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

MAMBA_FLAGS=(--override-channels --no-channel-priority)

if [ "$OS" = "Linux" ]; then
    echo "=== align (readCounter; minimap2/bwa-mem2/samtools kommen auf PALMA aus dem Modulsystem) ==="
    if [ ! -d "$ENV_DIR/align" ]; then
        "$MAMBA" create -y "${MAMBA_FLAGS[@]}" -c bioconda -c conda-forge -p "$ENV_DIR/align" \
            "hmmcopy=0.1.1"
    else
        echo "  bereits vorhanden, überspringe"
    fi
else
    echo "=== align (minimap2, bwa-mem2, samtools, readCounter) ==="
    if [ ! -d "$ENV_DIR/align" ]; then
        "$MAMBA" create -y "${MAMBA_FLAGS[@]}" -c bioconda -c conda-forge -p "$ENV_DIR/align" \
            "minimap2>=2.28,<3" "bwa-mem2=2.2.1" "samtools>=1.20,<2" "hmmcopy=0.1.1"
    else
        echo "  bereits vorhanden, überspringe"
    fi
fi

echo "=== report (python, reportlab, python-docx) ==="
if [ ! -d "$ENV_DIR/report" ]; then
    "$MAMBA" create -y "${MAMBA_FLAGS[@]}" -c conda-forge -p "$ENV_DIR/report" \
        "python=3.11" "reportlab" "python-docx"
else
    echo "  bereits vorhanden, überspringe"
fi

echo "=== ichorcna (R, r-ichorcna) ==="
if [ ! -d "$ENV_DIR/ichorcna" ]; then
    if [ "$OS" = "Darwin" ] && [ "$ARCH" = "arm64" ]; then
        echo "  kein osx-arm64-Build -- Env läuft unter Rosetta 2 (osx-64)"
        CONDA_SUBDIR=osx-64 "$MAMBA" create -y "${MAMBA_FLAGS[@]}" -c bioconda -c conda-forge -p "$ENV_DIR/ichorcna" \
            "r-base=4.3" "r-ichorcna=0.5.1" "r-optparse"
        echo "subdir: osx-64" >> "$ENV_DIR/ichorcna/.condarc"
    else
        "$MAMBA" create -y "${MAMBA_FLAGS[@]}" -c bioconda -c conda-forge -p "$ENV_DIR/ichorcna" \
            "r-base=4.3" "r-ichorcna=0.5.1" "r-optparse"
    fi
else
    echo "  bereits vorhanden, überspringe"
fi

echo "=== krakenuniq ==="
if [ "$OS" = "Linux" ]; then
    if [ ! -d "$ENV_DIR/krakenuniq" ]; then
        "$MAMBA" create -y "${MAMBA_FLAGS[@]}" -c bioconda -c conda-forge -p "$ENV_DIR/krakenuniq" \
            "krakenuniq=1.0.4"
    else
        echo "  bereits vorhanden, überspringe"
    fi
else
    echo "  übersprungen (kein osx-Build) -- lokal mit KRAKENUNIQ_ENABLED=false deaktivieren"
    echo "  (siehe scripts/config.sh oder: KRAKENUNIQ_ENABLED=false bash run_pipeline.sh)"
fi

echo ""
echo "=== Fertig. Envs liegen unter $ENV_DIR ==="
