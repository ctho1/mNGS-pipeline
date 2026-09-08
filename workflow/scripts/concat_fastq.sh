#!/bin/bash
# Concatenate all FASTQ files (gz or plain) belonging to one sample into a
# single gzip'd FASTQ. Gzip streams are valid when simply concatenated
# (multi-member gzip), so .gz inputs are appended byte-for-byte; plain .fastq
# inputs are compressed on the fly.
#
# Usage: concat_fastq.sh <output.fastq.gz> <input1> [input2 ...]
set -euo pipefail

out="$1"
shift

mkdir -p "$(dirname "$out")"
: > "$out"

for f in "$@"; do
    case "$f" in
        *.gz) cat "$f" >> "$out" ;;
        *)    gzip -c "$f" >> "$out" ;;
    esac
done
