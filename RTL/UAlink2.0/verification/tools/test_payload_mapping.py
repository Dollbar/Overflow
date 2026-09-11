"""Actual authorized-library mapping must retain the complete staged payload."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class PayloadMappingTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("UALINK_TEST_LIBERTY") and shutil.which("yosys"),
                         "explicit authorized UALINK_TEST_LIBERTY and Yosys required")
    def test_mapped_sender_contains_all_tail_storage_and_no_generic_cells(self):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix="ualink_payload_mapping_") as directory:
            env = dict(os.environ, UALINK_LIBERTY=os.environ["UALINK_TEST_LIBERTY"],
                       UALINK_BUILD_DIR=directory, UALINK_PORTS="1", UALINK_CREDIT_WIDTH="3",
                       UALINK_REQUEST_WIDTH="96", UALINK_INIT_CYCLES="2")
            result = subprocess.run(["yosys", "-Q", "-T", "-c",
                str(root/"scripts/synth_burst_sender.tcl")], env=env,
                text=True, capture_output=True, cwd=root.parent, timeout=300, check=False)
            self.assertEqual(result.returncode, 0, result.stdout[-3000:]+result.stderr)
            graph = json.loads((Path(directory)/"mapped.json").read_text())
            top = graph["modules"]["upli_burst_sender"]
            types = [cell["type"] for cell in top["cells"].values()]
            self.assertGreaterEqual(sum(t.startswith("DF") for t in types), 3*577)
            self.assertFalse(any(t.startswith("$") for t in types))
            self.assertEqual(len(top["ports"]["o_data_payload"]["bits"]), 512)
            self.assertEqual(len(top["ports"]["o_data_byte_enable"]["bits"]), 64)
            self.assertTrue((Path(directory)/"mapped.v").stat().st_size > 1000)
            self.assertTrue((Path(directory)/"area.json").is_file())
            env["UALINK_NETLIST"] = str(Path(directory)/"mapped.v")
            equivalent = subprocess.run([sys.executable,
                str(root/"verification/formal/run_payload_mapping.py"),
                "--netlist", env["UALINK_NETLIST"], "--liberty", env["UALINK_LIBERTY"],
                "--ports", "1", "--credit-width", "3"], env=env,
                text=True, capture_output=True, cwd=root.parent, timeout=1260, check=False)
            self.assertEqual(equivalent.returncode, 0, equivalent.stdout[-3000:]+equivalent.stderr)
            summary = json.loads(equivalent.stdout.splitlines()[-1])
            self.assertTrue(summary["passed"])
            self.assertTrue(summary["reset_base_passed"])
            self.assertTrue(summary["partition_union_passed"])
            self.assertEqual(summary["proved_groups"], [0,1,2])
            self.assertTrue(summary["inputs_unchanged"])


if __name__ == "__main__":
    unittest.main()
