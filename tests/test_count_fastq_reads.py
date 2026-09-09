import gzip
import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "count_fastq_reads.py"
SPEC = importlib.util.spec_from_file_location("count_fastq_reads", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CountFastqReadsTest(unittest.TestCase):
    def test_plain_and_gzip_fastq_are_summed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            plain = Path(temp_dir) / "reads.fastq"
            compressed = Path(temp_dir) / "reads.fastq.gz"
            plain.write_bytes(b"@r1\nACGT\n+\nIIII\n")
            with gzip.open(compressed, "wb") as handle:
                handle.write(b"@r2\nAC\nGT\n+\nII\nII\n@r3\nA\n+\nI\n")

            self.assertEqual(MODULE.count_fastq(plain.as_posix()), 1)
            self.assertEqual(MODULE.count_fastq(compressed.as_posix()), 2)

    def test_truncated_fastq_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "broken.fastq"
            path.write_bytes(b"@r1\nACGT\n+\nIII\n")

            with self.assertRaises(ValueError):
                MODULE.count_fastq(path.as_posix())


if __name__ == "__main__":
    unittest.main()
