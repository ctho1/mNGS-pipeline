#!/bin/bash
# =============================================================================
# config.sh -- einzige Stelle mit deployment-/nutzerspezifischen Werten.
#
# Alle anderen Pfade in diesem Paket sind relativ zum Paket-Wurzelverzeichnis
# (portabel: der komplette Ordner kann an eine beliebige Stelle auf PALMA oder
# in ein anderes Nutzerkonto kopiert werden). Wird von run_pipeline.sh,
# scripts/sample_pipeline.sh und scripts/prepare_reference.sh eingelesen.
# Werte können per Umgebungsvariable überschrieben werden, ohne diese Datei
# zu ändern, z.B.:
#   KRAKENUNIQ_DB=/anderer/pfad bash run_pipeline.sh
#   KRAKENUNIQ_ENABLED=false bash run_pipeline.sh   # lokaler Testlauf ohne DB
# =============================================================================

# ── SLURM-Job-Benachrichtigung ──────────────────────────────────────────────
: "${MAIL_USER:=}"

# ── KrakenUniq (unverändert aus dem ursprünglichen krakenuniq-report übernommen) ──
: "${KRAKENUNIQ_ENABLED:=true}"
: "${KRAKENUNIQ_DB:=/scratch/tmp/thomachr/references/krakenuniq/microbial_db}"
: "${KRAKENUNIQ_BIN_DIR:=/scratch/tmp/thomachr/software/krakenuniq}"
: "${EXTRA_BIN_DIR:=/home/t/thomachr/bin}"
: "${KRAKENUNIQ_PRELOAD_SIZE:=64G}"
: "${MODULE_PREFIX:=module purge && ml palma/2024a GCC/13.3.0 Jellyfish/2.3.1 bzip2/1.0.8}"

# minimap2 UND samtools kommen auf PALMA aus dem Modulsystem, nicht aus dem
# conda-align-Env (das liefert dort nur noch readCounter/hmmcopy -- samtools
# konnte über conda wegen eines libdeflate/htslib-Solver-Konflikts nicht
# zuverlässig installiert werden). Beide Modullisten werden zusammen vor dem
# Alignment-Schritt geladen (module purge + ml beide Listen), da minimap2 und
# samtools dort direkt gepiped werden. Reine Modullisten (ohne "module purge
# && ml", das übernehmen die aufrufenden Skripte selbst).
: "${MINIMAP2_MODULES:=palma/2024a GCCcore/13.3.0 minimap2/2.29}"
: "${SAMTOOLS_MODULES:=palma/2024a GCC/13.3.0 SAMtools/1.21}"

# ── Conda-Umgebungen (siehe scripts/setup_envs.sh) ──────────────────────────
: "${CONDA_ENV_DIR:=$REPO_ROOT/conda_envs}"
ENV_ALIGN="$CONDA_ENV_DIR/align"
ENV_ICHORCNA="$CONDA_ENV_DIR/ichorcna"
ENV_REPORT="$CONDA_ENV_DIR/report"
ENV_KRAKENUNIQ="$CONDA_ENV_DIR/krakenuniq"

# ── Referenzgenom (hg38, UCSC No-Alt Analysis Set) ──────────────────────────
# Wird bei Bedarf automatisch nach references/ heruntergeladen/gebaut
# (siehe scripts/prepare_reference.sh).
: "${HG38_FASTA_URL:=https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/analysisSet/hg38.analysisSet.fa.gz}"
HG38_FASTA="$REPO_ROOT/references/hg38.analysisSet.fa"
HG38_MMI_NANOPORE="$REPO_ROOT/references/hg38.analysisSet.map-ont.mmi"
HG38_MMI_ILLUMINA="$REPO_ROOT/references/hg38.analysisSet.sr.mmi"

# ── Threads (lokal per Env-Variable überschreibbar; auf PALMA kommen die
#    tatsächlichen Werte von den sbatch-Flags in run_pipeline.sh / SLURM_CPUS_PER_TASK) ──
: "${THREADS_MINIMAP2:=36}"
: "${THREADS_SAMTOOLS_SORT:=8}"
: "${THREADS_ICHORCNA:=4}"
: "${THREADS_KRAKENUNIQ:=36}"

# ── ichorCNA ─────────────────────────────────────────────────────────────
# Parameter übernommen von nanoDx (gitlab.com/pesk/nanoDx,
# workflow/scripts/ichorCNA.R), der Nanopore-WGS-Pipeline hinter crossNN
# (Yuan et al. 2025, Nat Cancer) -- selbe gepinnte Version r-ichorcna==0.5.1.
# Übernommen: 1-Mb-Bins/-q20 für readCounter, normal/ploidy-Grid,
# minMapScore, txnStrength/txnE, normalizeMaleX, estimateScPrevalence,
# plotYLim. NICHT übernommen: genomeBuild/gcWig/mapWig/normalPanel bleiben
# hg38 (nanoDx nutzt hg19) -- der Rest dieser Pipeline arbeitet konsistent
# mit hg38. Immer MIT PoN (kein "ohne PoN"-Lauf, siehe nanoDx-Vorbild).
: "${ICHORCNA_BIN_SIZE:=1000000}"
: "${ICHORCNA_BIN_LABEL:=1000kb}"
: "${ICHORCNA_CHRS:=c(1:22,\"X\")}"
: "${ICHORCNA_CHR_NORMALIZE:=c(1:22)}"
: "${ICHORCNA_CHR_TRAIN:=c(1:22)}"
: "${ICHORCNA_GENOME_BUILD:=hg38}"
: "${ICHORCNA_GENOME_STYLE:=UCSC}"
: "${ICHORCNA_INCLUDE_HOMD:=FALSE}"
: "${ICHORCNA_NORMAL:=c(0.5,0.6,0.7,0.8,0.9,0.95,0.99)}"
: "${ICHORCNA_PLOIDY:=c(2,3)}"
: "${ICHORCNA_MIN_MAP_SCORE:=0.75}"
: "${ICHORCNA_TXN_STRENGTH:=10000}"
: "${ICHORCNA_TXN_E:=0.9999}"
: "${ICHORCNA_NORMALIZE_MALE_X:=FALSE}"
: "${ICHORCNA_ESTIMATE_SC_PREVALENCE:=FALSE}"
: "${ICHORCNA_PLOT_Y_LIM:=c(-2,4)}"
: "${ICHORCNA_GC_WIG:=gc_hg38_1000kb.wig}"
: "${ICHORCNA_MAP_WIG:=map_hg38_1000kb.wig}"
: "${ICHORCNA_CENTROMERE:=GRCh38.GCA_000001405.2_centromere_acen.txt}"
: "${ICHORCNA_NORMAL_PANEL:=HD_ULP_PoN_hg38_1Mb_normAutosomes_median.rds}"

export MAIL_USER
export KRAKENUNIQ_ENABLED KRAKENUNIQ_DB KRAKENUNIQ_BIN_DIR EXTRA_BIN_DIR KRAKENUNIQ_PRELOAD_SIZE MODULE_PREFIX
export MINIMAP2_MODULES SAMTOOLS_MODULES
export ENV_ALIGN ENV_ICHORCNA ENV_REPORT ENV_KRAKENUNIQ
export HG38_FASTA_URL HG38_FASTA HG38_MMI_NANOPORE HG38_MMI_ILLUMINA
export THREADS_MINIMAP2 THREADS_SAMTOOLS_SORT THREADS_ICHORCNA THREADS_KRAKENUNIQ
export ICHORCNA_BIN_SIZE ICHORCNA_BIN_LABEL ICHORCNA_CHRS ICHORCNA_CHR_NORMALIZE ICHORCNA_CHR_TRAIN
export ICHORCNA_GENOME_BUILD ICHORCNA_GENOME_STYLE ICHORCNA_INCLUDE_HOMD
export ICHORCNA_NORMAL ICHORCNA_PLOIDY ICHORCNA_MIN_MAP_SCORE ICHORCNA_TXN_STRENGTH ICHORCNA_TXN_E
export ICHORCNA_NORMALIZE_MALE_X ICHORCNA_ESTIMATE_SC_PREVALENCE ICHORCNA_PLOT_Y_LIM
export ICHORCNA_GC_WIG ICHORCNA_MAP_WIG ICHORCNA_CENTROMERE ICHORCNA_NORMAL_PANEL
