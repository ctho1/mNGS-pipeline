import io
import importlib.util
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "scripts" / "select_slurm_partitions.py"
SPEC = importlib.util.spec_from_file_location("select_slurm_partitions", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SelectSlurmPartitionsTest(unittest.TestCase):
    def test_ranks_available_partitions_by_summed_idle_cpus(self):
        output = "\n".join([
            "normal*|up|100/200/0/300",
            "zen4|up|20/80/0/100",
            "zen4|up|10/150/0/160",
            "zen3|down|0/500/0/500",
            "zen2-128C-496G|up|128/0/0/128",
            "unknown|up|0/999/0/999",
        ])

        ranked, idle = MODULE.parse_sinfo(
            output, ["normal", "zen2-128C-496G", "zen3", "zen4"])

        self.assertEqual(ranked, ["zen4", "normal"])
        self.assertEqual(idle["zen4"], 230)
        self.assertEqual(idle["normal"], 200)

    def test_uses_configured_order_to_break_ties(self):
        output = "normal|up|0/36/0/36\nzen4|up|0/36/0/36\n"

        ranked, _idle = MODULE.parse_sinfo(output, ["normal", "zen4"])

        self.assertEqual(ranked, ["normal", "zen4"])

    @mock.patch.object(MODULE.subprocess, "run")
    def test_cli_prints_only_currently_idle_partitions(self, run):
        run.return_value = mock.Mock(
            stdout="normal|up|36/0/0/36\nzen4|up|0/192/0/192\n")
        stdout = io.StringIO()
        stderr = io.StringIO()

        with redirect_stdout(stdout), redirect_stderr(stderr):
            MODULE.main([
                "--partitions", "normal,zen4",
                "--fallback", "normal",
            ])

        self.assertEqual(stdout.getvalue().strip(), "zen4")
        self.assertIn("zen4: 192 freie CPUs", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
