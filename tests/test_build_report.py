import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "build_report.py"
SPEC = importlib.util.spec_from_file_location("build_report", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class BuildReportReadCountsTest(unittest.TestCase):
    def test_fastq_counts_and_alignment_counts_remain_distinct(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            flagstat = temp / "sample.flagstat.txt"
            read_counts = temp / "sample.read_counts.tsv"
            flagstat.write_text(
                "10 + 0 primary\n"
                "7 + 0 primary mapped (70.00% : N/A)\n",
                encoding="utf-8",
            )
            read_counts.write_text(
                "initial_reads\t12\nunaligned_reads\t4\n",
                encoding="utf-8",
            )

            counts = MODULE.parse_read_counts(read_counts)
            host = MODULE.parse_flagstat(
                flagstat,
                counts["initial_reads"],
                counts["unaligned_reads"],
            )

            self.assertEqual(host["total_reads"], 12)
            self.assertEqual(host["alignment_total_reads"], 10)
            self.assertEqual(host["human_reads"], 7)
            self.assertEqual(host["unaligned_reads"], 4)
            self.assertEqual(host["pct_human"], 58.33)
            self.assertEqual(host["pct_unaligned"], 33.33)


if __name__ == "__main__":
    unittest.main()
