#!/bin/bash
# Extract non-human (hg38-unmapped) read PAIRS from a paired-end (Illumina)
# BAM: keeps pairs where BOTH mates are unmapped (flag 12 = unmapped + mate
# unmapped) -- the conservative definition of a "confidently non-human" pair.
# Needs name-sorting first so mates are adjacent for `samtools fastq -1/-2`.
# Usage: extract_nonhuman_pe.sh <in.bam> <out_R1.fastq.gz> <out_R2.fastq.gz>
set -euo pipefail
bam="$1"
out1="$2"
out2="$3"
mkdir -p "$(dirname "$out1")"
samtools view -b -f 12 -F 0x100 "$bam" \
    | samtools sort -n -o - - \
    | samtools fastq -1 "$out1" -2 "$out2" -0 /dev/null -s /dev/null -
