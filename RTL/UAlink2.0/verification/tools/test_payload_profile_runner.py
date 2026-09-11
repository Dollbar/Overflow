"""Real source-only execution: a clean checkout need not contain build/."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class PayloadProfileRunnerTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("verilator"), "Verilator is required for real relocation execution")
    def test_zero_capacity_from_fresh_source_and_external_cwd(self):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix="ualink_profile_test_") as directory:
            outer = Path(directory)
            copied = outer/"source"
            for name in ("model/ualink", "verification/rtl", "rtl/upli"):
                shutil.copytree(root/name, copied/name,
                                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
            self.assertFalse((copied/"build").exists())
            result = subprocess.run([sys.executable,
                str(copied/"verification/rtl/run_payload_profiles.py"),
                "--ports", "1", "--credit-width", "3", "--kind", "zero"],
                cwd=outer, text=True, capture_output=True, timeout=300, check=False)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            item = json.loads(result.stdout.splitlines()[-1])
            self.assertTrue(item["passed"])
            self.assertGreater(item["rows"], 1000)
            self.assertEqual(item["allocation_cases"], 240)
            self.assertEqual((item["requests"], item["data"], item["read_overlays"]), (0, 0, 0))
            summary = json.loads((copied/item["directory"]/"summary.json").read_text())
            self.assertEqual(summary["actual"]["journal"], 0)
            self.assertEqual(summary["actual"]["rows"], item["rows"])


if __name__ == "__main__":
    unittest.main()
