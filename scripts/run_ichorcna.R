#!/usr/bin/env Rscript
#
# Thin CLI wrapper around ichorCNA::run_ichorCNA().
#
# The bioconda package r-ichorcna==0.5.1 (pinned in workflow/envs/ichorcna.yaml)
# restructured the upstream repo so that "run_ichorCNA" ships as an *exported R
# function* inside the package (R/runIchorCNA.R) rather than as the classic
# optparse-based scripts/runIchorCNA.R CLI from older ichorCNA releases. This
# wrapper recreates just enough of that CLI surface for our Snakemake rule.
#
# Parameter defaults below (normal/ploidy grid, minMapScore, txnStrength/txnE,
# normalizeMaleX, estimateScPrevalence, plotYLim) match nanoDx
# (gitlab.com/pesk/nanoDx, workflow/scripts/ichorCNA.R), which pins the same
# r-ichorcna==0.5.1 -- see config/config.yaml for the rationale.
#
# Usage:
#   Rscript run_ichorcna.R \
#     --WIG tumor.wig --gcWig gc.wig --mapWig map.wig --centromere centromere.txt \
#     --normalPanel pon.rds \
#     --id SAMPLE --outDir OUTDIR \
#     --genomeBuild hg38 --genomeStyle UCSC \
#     --chrs 'c(1:22,"X")' --chrNormalize 'c(1:22)' --chrTrain 'c(1:22)' \
#     --normal 'c(0.5,0.6,0.7,0.8,0.9,0.95,0.99)' --ploidy 'c(2,3)' \
#     --minMapScore 0.75 --txnStrength 10000 --txnE 0.9999 \
#     --normalizeMaleX FALSE --estimateScPrevalence FALSE --plotYLim 'c(-2,4)' \
#     --includeHOMD FALSE --plotFileType png

suppressPackageStartupMessages({
  library(optparse)
  library(ichorCNA)
})

option_list <- list(
  make_option("--WIG", type = "character"),
  make_option("--gcWig", type = "character"),
  make_option("--mapWig", type = "character", default = NULL),
  make_option("--centromere", type = "character", default = NULL),
  make_option("--normalPanel", type = "character", default = NULL),
  make_option("--id", type = "character", default = "test"),
  make_option("--outDir", type = "character", default = "./"),
  make_option("--genomeBuild", type = "character", default = "hg19"),
  make_option("--genomeStyle", type = "character", default = "NCBI"),
  make_option("--chrs", type = "character", default = 'c(1:22,"X")'),
  make_option("--chrNormalize", type = "character", default = "c(1:22)"),
  make_option("--chrTrain", type = "character", default = "c(1:22)"),
  make_option("--normal", type = "character", default = "0.5"),
  make_option("--ploidy", type = "character", default = "2"),
  make_option("--minMapScore", type = "double", default = 0.9),
  make_option("--txnStrength", type = "double", default = 1e7),
  make_option("--txnE", type = "double", default = 0.9999999),
  make_option("--normalizeMaleX", type = "character", default = "TRUE"),
  make_option("--estimateScPrevalence", type = "character", default = "TRUE"),
  make_option("--plotYLim", type = "character", default = "c(-2,2)"),
  make_option("--includeHOMD", type = "character", default = "FALSE"),
  make_option("--plotFileType", type = "character", default = "pdf"),
  make_option("--cores", type = "integer", default = 1)
)

opt <- parse_args(OptionParser(option_list = option_list))

dir.create(opt$outDir, recursive = TRUE, showWarnings = FALSE)

run_ichorCNA(
  tumor_wig             = opt$WIG,
  gcWig                 = opt$gcWig,
  mapWig                = opt$mapWig,
  centromere            = opt$centromere,
  normal_panel          = opt$normalPanel,
  id                    = opt$id,
  outDir                = opt$outDir,
  genomeBuild           = opt$genomeBuild,
  genomeStyle           = opt$genomeStyle,
  chrs                  = opt$chrs,
  chrNormalize          = opt$chrNormalize,
  chrTrain              = opt$chrTrain,
  normal                = opt$normal,
  ploidy                = opt$ploidy,
  minMapScore           = opt$minMapScore,
  txnStrength           = opt$txnStrength,
  txnE                  = opt$txnE,
  normalizeMaleX        = as.logical(opt$normalizeMaleX),
  estimateScPrevalence  = as.logical(opt$estimateScPrevalence),
  plotYLim              = opt$plotYLim,
  includeHOMD           = opt$includeHOMD,
  plotFileType          = opt$plotFileType,
  cores                 = opt$cores
)
