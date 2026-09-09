#!/bin/bash
# Extracts non-human (hg19-unmapped) read PAIRS from a live SAM stream on
# stdin (a `tee`'d copy of the aligner's output, running alongside
# `samtools sort` -- avoids a second pass reading the finished BAM back from
# disk). Keeps pairs where BOTH mates are unmapped (flag 12 = unmapped +
# mate unmapped) -- the conservative definition of a "confidently non-human"
# pair. No name-sort needed: for paired input, bwa-mem2/minimap2 already
# emit each pair's two records consecutively in the live stream.
# Usage: bwa-mem2 mem ... | tee >(extract_nonhuman_pe.sh R1.fq.gz R2.fq.gz) | samtools sort ...
set -euo pipefail
out1="$1"
out2="$2"
mkdir -p "$(dirname "$out1")"
samtools view -b -f 12 -F 0x900 - \
    | samtools fastq -1 "$out1" -2 "$out2" -0 /dev/null -s /dev/null -
