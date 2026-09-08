#!/bin/bash
# Extract non-human (hg38-unmapped) reads from a single-end (Nanopore) BAM.
# Usage: extract_nonhuman_se.sh <in.bam> <out.fastq.gz>
set -euo pipefail
bam="$1"
out="$2"
mkdir -p "$(dirname "$out")"
samtools view -b -f 4 -F 0x900 "$bam" | samtools fastq - | gzip -c > "$out"
