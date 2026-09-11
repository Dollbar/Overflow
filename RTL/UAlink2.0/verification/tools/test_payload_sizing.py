"""Real OpenSTA on explicit synthetic scalar fixtures, not process evidence."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from verification.tools.test_burst_sizing import fixture_library

SCRIPT = Path(__file__).resolve().parents[2]/"scripts/size_burst_sender.tcl"


@unittest.skipUnless(shutil.which(os.environ.get("STA", "sta")), "actual OpenSTA required")
class PayloadSizingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ualink_payload_size_")
        self.addCleanup(self.temp.cleanup)
        self.run = Path(self.temp.name)
        self.lib = self.run/"synthetic.lib"
        self.net = self.run/"before.v"
        self.out = self.run/"diagnostic.v"
        self.journal = self.run/"changes.list"

    def execute(self, delay_cell=False, first=0.400, second=0.200, **overrides):
        cell = "DEL025D1BWP40P140" if delay_cell else "BUFFD1BWP40P140"
        self.lib.write_text(fixture_library(first, second).replace("BUFFD1BWP40P140", cell))
        self.net.write_text("module upli_burst_sender(input i_clk, input i_data, output o_data, output [2:0] o_ties);\n"
                            f"{cell} driver(.I(i_data),.Z(o_data));\nassign o_ties=3'b101;\nendmodule\n")
        env = dict(os.environ, UALINK_LIBERTY=str(self.lib), UALINK_NETLIST=str(self.net),
                   UALINK_SIZE_OUT=str(self.out), UALINK_SIZE_CHANGES=str(self.journal))
        env.update(overrides)
        return subprocess.run([os.environ.get("STA", "sta"), "-exit", str(SCRIPT)],
                              env=env,capture_output=True,text=True,timeout=30,check=False)

    def test_faster_driver_improves_the_actual_setup_path(self):
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn("worst slack max 0.152000", result.stdout)
        self.assertIn("{driver BUFFD1BWP40P140 BUFFD2BWP40P140}", self.journal.read_text())
        self.assertIn("BUFFD1BWP40P140 driver", self.net.read_text())

    def test_already_met_setup_keeps_existing_driver(self):
        result = self.execute(first=0.200)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(self.journal.read_text().strip(), "")

    def test_slower_replacement_is_rolled_back_without_false_pass(self):
        result = self.execute(second=0.500)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(self.journal.read_text().strip(), "")
        self.assertIn("worst slack max -0.048000", result.stdout)
        self.assertNotIn("PASS", result.stdout)

    def test_delay_buffer_can_be_replaced_when_both_slacks_improve(self):
        result = self.execute(delay_cell=True)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn("{driver DEL025D1BWP40P140 BUFFD2BWP40P140}", self.journal.read_text())
        self.assertIn("worst slack max 0.152000", result.stdout)

    def test_setup_improvement_cannot_create_hold_failure(self):
        result = self.execute(delay_cell=True, second=0.001)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(self.journal.read_text().strip(), "")
        self.assertIn("worst slack max -0.048000", result.stdout)

    def test_input_netlist_cannot_be_overwritten_by_diagnostic_output(self):
        result = self.execute(UALINK_SIZE_OUT=str(self.net))
        self.assertNotEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn("BUFFD1BWP40P140 driver", self.net.read_text())
        self.assertFalse(self.journal.exists())

    @unittest.skipUnless(shutil.which("yosys"), "actual Yosys required")
    def test_checked_journal_preserves_original_constant_connections(self):
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        apply_script = SCRIPT.with_name("apply_burst_sender_sizing.tcl")
        output = self.run/"applied.json"
        env = dict(os.environ, UALINK_LIBERTY=str(self.lib), UALINK_NETLIST=str(self.net),
                   UALINK_SIZE_CHANGES=str(self.journal))
        result = subprocess.run(["yosys", "-Q", "-T", "-p",
            f"tcl {apply_script}; check -assert; write_json {output}"], env=env,
            text=True,capture_output=True,timeout=30,check=False)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        graph = json.loads(output.read_text())["modules"]["upli_burst_sender"]
        self.assertEqual(graph["ports"]["o_ties"]["bits"], ["1","0","1"])
        self.assertEqual(graph["cells"]["driver"]["type"], "BUFFD2BWP40P140")
        self.assertEqual(graph["cells"]["driver"]["connections"]["I"],graph["ports"]["i_data"]["bits"])
        self.assertEqual(graph["cells"]["driver"]["connections"]["Z"],graph["ports"]["o_data"]["bits"])

    @unittest.skipUnless(shutil.which("yosys"), "actual Yosys required")
    def test_stale_journal_cannot_resize_a_different_original_cell(self):
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.journal.write_text("{driver BUFFD2BWP40P140 BUFFD1BWP40P140}\n")
        apply_script = SCRIPT.with_name("apply_burst_sender_sizing.tcl")
        output = self.run/"must_not_exist.json"
        result = subprocess.run(["yosys", "-Q", "-T", "-p",
            f"tcl {apply_script}; write_json {output}"],
            env=dict(os.environ,UALINK_LIBERTY=str(self.lib),UALINK_NETLIST=str(self.net),
                     UALINK_SIZE_CHANGES=str(self.journal)),
            text=True,capture_output=True,timeout=30,check=False)
        self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
