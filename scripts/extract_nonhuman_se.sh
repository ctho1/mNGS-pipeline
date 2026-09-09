#!/bin/bash
# Extracts non-human (hg19-unmapped) reads from a live SAM stream on stdin
# (a `tee`'d copy of the aligner's output, running alongside `samtools sort`
# -- avoids a second pass reading the finished BAM back from disk).
# Usage: minimap2 ... | tee >(extract_nonhuman_se.sh out.fastq.gz) | samtools sort ...
set -euo pipefail
out="$1"
mkdir -p "$(dirname "$out")"
samtools view -b -f 4 -F 0x900 - | samtools fastq - | gzip -c > "$out"
