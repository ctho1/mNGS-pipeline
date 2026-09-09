#!/bin/bash
# Central config. Paths are relative to the repo root (portable). Override
# any value via env var, e.g.:
#   KRAKENUNIQ_ENABLED=false bash run_pipeline.sh

: "${MAIL_USER:=}"

# SLURM partition selection. General-purpose public CPU partitions plus the
# explicitly permitted preemptible requeue queues are considered; scarce
# large-memory and GPU nodes remain excluded. The order is also the tie-breaker
# when partitions have equal idle capacity.
: "${SLURM_AUTO_PARTITION:=true}"
: "${SLURM_CPU_PARTITIONS:=normal,zen2-128C-496G,zen3,zen4,zen4x,requeue,requeue-zen}"
: "${SLURM_FALLBACK_PARTITION:=normal}"

# KrakenUniq (unchanged from the original krakenuniq-report)
: "${KRAKENUNIQ_ENABLED:=true}"
: "${KRAKENUNIQ_DB:=/scratch/tmp/thomachr/references/krakenuniq/microbial_db}"
: "${KRAKENUNIQ_BIN_DIR:=/scratch/tmp/thomachr/software/krakenuniq}"
: "${EXTRA_BIN_DIR:=/home/t/thomachr/bin}"
: "${KRAKENUNIQ_PRELOAD_SIZE:=64G}"
: "${MODULE_PREFIX:=module purge && ml palma/2024a GCC/13.3.0 Jellyfish/2.3.1 bzip2/1.0.8}"

# Aligners + samtools come from PALMA modules (conda's samtools hits an
# unresolvable libdeflate conflict there); bare module lists, loaded via
# `module purge && ml $X_MODULES $SAMTOOLS_MODULES` right before use.
: "${MINIMAP2_MODULES:=palma/2024a GCCcore/13.3.0 minimap2/2.29}"
: "${BWA_MEM2_MODULES:=palma/2024a GCC/13.3.0 bwa-mem2/2.2.1}"
: "${SAMTOOLS_MODULES:=palma/2024a GCC/13.3.0 SAMtools/1.21}"

# Conda envs (see scripts/setup_envs.sh)
: "${CONDA_ENV_DIR:=$REPO_ROOT/conda_envs}"
ENV_ALIGN="$CONDA_ENV_DIR/align"
ENV_ICHORCNA="$CONDA_ENV_DIR/ichorcna"
ENV_REPORT="$CONDA_ENV_DIR/report"
ENV_KRAKENUNIQ="$CONDA_ENV_DIR/krakenuniq"

# Reference genome: hg19, reusing the shared fasta + bwa-mem2 index already
# built for ngs-tumor-pipeline (config/palma.sh: REF_GENOME_CNV) if present.
# Chromosome naming there is UCSC-style ("chr1", confirmed via its panel BED)
# -- matches ICHORCNA_GENOME_STYLE below. prepare_reference.sh symlinks these
# into references/ if found, else downloads+builds from HG19_FASTA_URL.
: "${EXISTING_HG19_FASTA:=/cloud/wwu1/e_np_ngs/references/genomes/hg19.fa}"
: "${HG19_FASTA_URL:=https://hgdownload.soe.ucsc.edu/goldenPath/hg19/bigZips/hg19.fa.gz}"
HG19_FASTA="$REPO_ROOT/references/hg19.fa"
HG19_MMI_NANOPORE="$REPO_ROOT/references/hg19.map-ont.mmi"
HG19_BWA_MEM2_PREFIX="$HG19_FASTA"  # bwa-mem2 index files share this prefix

# Threads (local override; on PALMA these come from sbatch/SLURM_CPUS_PER_TASK)
: "${THREADS_MINIMAP2:=36}"
: "${THREADS_SAMTOOLS_SORT:=8}"
: "${THREADS_ICHORCNA:=4}"
: "${THREADS_KRAKENUNIQ:=36}"

# ichorCNA params, taken from nanoDx (gitlab.com/pesk/nanoDx), which pins
# the same r-ichorcna==0.5.1 and is itself hg19-native -- genome build/wigs/
# PoN below match it directly. Always runs with PoN, no matched normal.
: "${ICHORCNA_BIN_SIZE:=1000000}"
: "${ICHORCNA_BIN_LABEL:=1000kb}"
: "${ICHORCNA_CHRS:=c(1:22,\"X\")}"
: "${ICHORCNA_CHR_NORMALIZE:=c(1:22)}"
: "${ICHORCNA_CHR_TRAIN:=c(1:22)}"
: "${ICHORCNA_GENOME_BUILD:=hg19}"
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
: "${ICHORCNA_GC_WIG:=gc_hg19_1000kb.wig}"
: "${ICHORCNA_MAP_WIG:=map_hg19_1000kb.wig}"
: "${ICHORCNA_CENTROMERE:=GRCh37.p13_centromere_UCSC-gapTable.txt}"
: "${ICHORCNA_NORMAL_PANEL:=HD_ULP_PoN_1Mb_median_normAutosome_mapScoreFiltered_median.rds}"

export MAIL_USER
export SLURM_AUTO_PARTITION SLURM_CPU_PARTITIONS SLURM_FALLBACK_PARTITION
export KRAKENUNIQ_ENABLED KRAKENUNIQ_DB KRAKENUNIQ_BIN_DIR EXTRA_BIN_DIR KRAKENUNIQ_PRELOAD_SIZE MODULE_PREFIX
export MINIMAP2_MODULES BWA_MEM2_MODULES SAMTOOLS_MODULES
export ENV_ALIGN ENV_ICHORCNA ENV_REPORT ENV_KRAKENUNIQ
export EXISTING_HG19_FASTA HG19_FASTA_URL HG19_FASTA HG19_MMI_NANOPORE HG19_BWA_MEM2_PREFIX
export THREADS_MINIMAP2 THREADS_SAMTOOLS_SORT THREADS_ICHORCNA THREADS_KRAKENUNIQ
export ICHORCNA_BIN_SIZE ICHORCNA_BIN_LABEL ICHORCNA_CHRS ICHORCNA_CHR_NORMALIZE ICHORCNA_CHR_TRAIN
export ICHORCNA_GENOME_BUILD ICHORCNA_GENOME_STYLE ICHORCNA_INCLUDE_HOMD
export ICHORCNA_NORMAL ICHORCNA_PLOIDY ICHORCNA_MIN_MAP_SCORE ICHORCNA_TXN_STRENGTH ICHORCNA_TXN_E
export ICHORCNA_NORMALIZE_MALE_X ICHORCNA_ESTIMATE_SC_PREVALENCE ICHORCNA_PLOT_Y_LIM
export ICHORCNA_GC_WIG ICHORCNA_MAP_WIG ICHORCNA_CENTROMERE ICHORCNA_NORMAL_PANEL
