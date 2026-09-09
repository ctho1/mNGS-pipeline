#!/usr/bin/env python3
"""Scans input/ (flat, no recursion) for sample groups, one line per sample:
    "<platform>\\t<sample>\\t<file1>\\t<file2>\\t..."

Illumina: paired *_R1_001*.fastq(.gz) + *_R2_001*.fastq(.gz), matched by
prefix+suffix around the "_R1_001"/"_R2_001" marker (which may appear
anywhere in the stem, not just at the end -- e.g. Probe01_R1_001_nonhuman_reads
+ Probe01_R2_001_nonhuman_reads pairs on the shared "Probe01"+"_nonhuman_reads"
prefix/suffix).
Nanopore: all other *.fastq(.gz) files, grouped by shared filename stem --
everything before a trailing "_<digits>" chunk index (MinKNOW/Guppy output
convention, e.g. PBM37034_pass_barcode05_xxx_0.fastq.gz + ..._1.fastq.gz ->
one sample "PBM37034_pass_barcode05_xxx"), concatenated in numeric chunk
order. Files with no trailing "_<digits>" are their own single-file sample.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

INPUT_DIR = Path(sys.argv[1] if len(sys.argv) > 1 else "input")
ILLUMINA_RE = re.compile(r"^(.*)_R([12])_001(.*)$")
CHUNK_RE = re.compile(r"^(.+)_(\d+)$")


def strip_ext(name):
    for ext in (".fastq.gz", ".fastq"):
        if name.endswith(ext):
            return name[: -len(ext)]
    return None


def main():
    if not INPUT_DIR.is_dir():
        return

    files = sorted(p for p in INPUT_DIR.iterdir() if p.is_file() and strip_ext(p.name))

    illumina_r1, illumina_r2 = {}, {}
    nanopore_groups = defaultdict(list)

    for p in files:
        stem = strip_ext(p.name)
        m = ILLUMINA_RE.match(stem)
        if m:
            prefix, read, suffix = m.groups()
            key = prefix + suffix
            (illumina_r1 if read == "1" else illumina_r2)[key] = p
            continue
        m = CHUNK_RE.match(stem)
        sample, chunk = (m.group(1), int(m.group(2))) if m else (stem, 0)
        nanopore_groups[sample].append((chunk, p))

    for sample in sorted(illumina_r1):
        if sample in illumina_r2:
            print("\t".join(["illumina", sample, str(illumina_r1[sample]), str(illumina_r2[sample])]))
        else:
            print(f"SKIP {illumina_r1[sample]} (keine passende R2 gefunden)", file=sys.stderr)

    for sample in sorted(nanopore_groups):
        paths = [str(p) for _, p in sorted(nanopore_groups[sample])]
        print("\t".join(["nanopore", sample] + paths))


if __name__ == "__main__":
    main()
