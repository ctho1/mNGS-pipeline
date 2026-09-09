#!/usr/bin/env python3
"""Count FASTQ records in one or more plain or gzip-compressed files."""

import gzip
import sys


def open_fastq(path):
    return gzip.open(path, "rb") if path.endswith(".gz") else open(path, "rb")


def count_fastq(path):
    """Count records while accepting both four-line and wrapped FASTQ."""
    count = 0
    with open_fastq(path) as handle:
        while True:
            header = handle.readline()
            if not header:
                return count
            if not header.startswith(b"@"):
                raise ValueError(f"{path}: FASTQ-Header erwartet bei Read {count + 1}")

            sequence_length = 0
            while True:
                line = handle.readline()
                if not line:
                    raise ValueError(f"{path}: unvollstaendiger Read {count + 1}")
                if line.startswith(b"+"):
                    break
                sequence_length += len(line.rstrip(b"\r\n"))

            quality_length = 0
            while quality_length < sequence_length:
                line = handle.readline()
                if not line:
                    raise ValueError(f"{path}: fehlende Qualitaetswerte bei Read {count + 1}")
                quality_length += len(line.rstrip(b"\r\n"))
            if quality_length != sequence_length:
                raise ValueError(f"{path}: Sequenz und Qualitaet unterschiedlich lang bei Read {count + 1}")
            count += 1


def main(argv):
    if not argv:
        raise SystemExit("Usage: count_fastq_reads.py <reads.fastq[.gz]> [...]")
    try:
        print(sum(count_fastq(path) for path in argv))
    except (OSError, ValueError) as exc:
        raise SystemExit(f"FEHLER: {exc}") from exc


if __name__ == "__main__":
    main(sys.argv[1:])
