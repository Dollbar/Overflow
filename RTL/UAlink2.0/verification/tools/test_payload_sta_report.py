"""Report gate must reject negative, incomplete, warning and wrong-profile runs."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class PayloadStaReportTests(unittest.TestCase):
    def test_actual_parser_accepts_only_complete_declared_pass(self):
        root = Path(__file__).resolve().parents[2]
        valid = ("worst slack max 0.012000\nworst slack min 0.007000\n"
                 "PASS burst_sender setup/hold at period_ns=0.640; prelayout budget only\n")
        cases = [(valid, True), (valid.replace("0.012000", "-0.001000"), False),
                 (valid.replace("0.007000", "nan"), False),
                 (valid+"Warning: undriven port\n", False),
                 (valid+"unconstrained endpoint\n", False),
                 (valid.replace("0.640", "1.000"), False),
                 (valid.replace("burst_sender", "burst_control"), False),
                 (valid+"worst slack max 0.100000\n", False),
                 ("worst slack max 0.100000\n", False)]
        with tempfile.TemporaryDirectory(prefix="ualink_sta_gate_") as directory:
            report = Path(directory)/"report.log"
            for content, expected in cases:
                with self.subTest(content=content):
                    report.write_text(content)
                    result = subprocess.run([sys.executable,
                        str(root/"scripts/check_payload_sta_report.py"), str(report)],
                        capture_output=True, text=True, check=False)
                    self.assertEqual(result.returncode == 0, expected, result.stdout+result.stderr)
                    if expected:
                        values = json.loads(result.stdout)
                        self.assertEqual(values["setup_slack_ns"], 0.012)
                        self.assertEqual(values["hold_slack_ns"], 0.007)
                        self.assertEqual(values["period_ns"], 0.640)


if __name__ == "__main__":
    unittest.main()
