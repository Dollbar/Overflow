"""Real two-port complete-state proof must close, not time out or omit groups."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import unittest


class PayloadProofPartitionTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("yosys"), "real Yosys proof required")
    def test_two_ports_prove_every_inductive_conclusion(self):
        root = Path(__file__).resolve().parents[2]
        result = subprocess.run([sys.executable,
            str(root/"verification/formal/run_payload_proof.py"),
            "--ports", "2", "--credit-width", "3"],
            cwd=root.parent, capture_output=True, text=True, timeout=600, check=False)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        report = json.loads(result.stdout.splitlines()[-1])
        self.assertTrue(report["passed"])
        self.assertTrue(report["reset_base_passed"])
        self.assertTrue(report["induction_passed"])
        self.assertTrue(report["partition_union_proved"])
        self.assertEqual(report["proved_groups"], list(range(14)))
        self.assertFalse(report["timeout"])
        self.assertTrue(report["source_unchanged"])


if __name__ == "__main__":
    unittest.main()
