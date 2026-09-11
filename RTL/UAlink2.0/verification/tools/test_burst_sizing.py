"""Run the real OpenSTA sizing entry on hand-defined, synthetic scalar gates.

These tiny fixtures test tooling only; they are not process or SerDes models.
Run: python3 -m unittest verification.tools.test_burst_sizing -v
Output: real temporary netlists and captured STA diagnostics; next: actual PDK runs.
"""

import os
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "size_burst_control.tcl"
APPLY = SCRIPT.with_name("apply_burst_sizing.tcl")


def fixture_library(first_delay, second_delay):
    cells = []
    for strength, delay in ((1, first_delay), (2, second_delay)):
        cells.append(f'''cell(BUFFD{strength}BWP40P140) {{
          area: {strength};
          pin(I) {{direction: input; capacitance: 0.001;}}
          pin(Z) {{direction: output; function: "I"; max_capacitance: 0.1;
            timing() {{related_pin: "I"; timing_sense: positive_unate;
              cell_rise(scalar) {{values("{delay}");}}
              cell_fall(scalar) {{values("{delay}");}}
              rise_transition(scalar) {{values("0.020");}}
              fall_transition(scalar) {{values("0.020");}}
            }}
          }}
        }}''')
    return '''library(synthetic_test_only) {
      delay_model: table_lookup; time_unit: "1ns"; voltage_unit: "1V";
      current_unit: "1mA"; pulling_resistance_unit: "1kohm";
      capacitive_load_unit(1,pf); leakage_power_unit: "1nW";
      nom_process: 1; nom_temperature: 25; nom_voltage: 1;
      slew_lower_threshold_pct_rise: 20; slew_upper_threshold_pct_rise: 80;
      slew_lower_threshold_pct_fall: 20; slew_upper_threshold_pct_fall: 80;
      input_threshold_pct_rise: 50; input_threshold_pct_fall: 50;
      output_threshold_pct_rise: 50; output_threshold_pct_fall: 50;
    ''' + "\n".join(cells) + "\n}"


@unittest.skipUnless(shutil.which(os.environ.get("STA", "sta")), "OpenSTA is required")
class BurstSizingTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), "reproducible burst sizing entry missing")
        self.temp = tempfile.TemporaryDirectory(prefix="ualink-burst-size-")
        self.addCleanup(self.temp.cleanup)
        self.run = Path(self.temp.name)
        self.lib = self.run / "synthetic.lib"
        self.net = self.run / "before.v"
        self.out = self.run / "after.v"
        self.changes = self.run / "changes.list"
        self.net.write_text("module upli_burst_control(input i_clk, input i_data, output o_data);\n"
                            "BUFFD1BWP40P140 driver(.I(i_data),.Z(o_data));\nendmodule\n")

    def execute(self, first=0.400, second=0.200, **overrides):
        self.lib.write_text(fixture_library(first, second))
        env = dict(os.environ, UALINK_LIBERTY=str(self.lib), UALINK_NETLIST=str(self.net),
                   UALINK_SIZE_OUT=str(self.out), UALINK_SIZE_CHANGES=str(self.changes))
        env.update(overrides)
        return subprocess.run([os.environ.get("STA", "sta"), "-exit", str(SCRIPT)],
                              env=env, capture_output=True, text=True, timeout=30)

    def test_negative_setup_is_repaired_by_a_faster_equivalent_driver(self):
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("BUFFD2BWP40P140 driver", self.out.read_text())
        self.assertIn("worst slack max 0.152000", result.stdout)
        self.assertIn("BUFFD1BWP40P140 driver", self.net.read_text())

    def test_already_met_budget_does_not_spend_unneeded_area(self):
        result = self.execute(first=0.200)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("BUFFD1BWP40P140 driver", self.out.read_text())

    def test_slower_trial_is_restored_and_failure_to_close_is_visible(self):
        result = self.execute(second=0.500)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("BUFFD1BWP40P140 driver", self.out.read_text())
        self.assertIn("worst slack max -0.048000", result.stdout)
        self.assertNotIn("PASS", result.stdout)

    def test_missing_library_is_nonzero_and_does_not_emit_a_netlist(self):
        result = self.execute(UALINK_LIBERTY=str(self.run / "absent.lib"))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.out.exists())

    def test_in_place_output_and_output_symlink_cannot_overwrite_inputs(self):
        before = self.net.read_text()
        for target in (self.net, self.out):
            if target == self.out:
                self.out.symlink_to(self.net)
            with self.subTest(target=target.name):
                result = self.execute(UALINK_SIZE_OUT=str(target))
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.net.read_text(), before)

    @unittest.skipUnless(shutil.which("yosys"), "Yosys is required")
    def test_journal_applied_to_original_graph_preserves_constant_output_bits(self):
        self.assertTrue(APPLY.is_file(), "sized graph must retain Yosys constant connections")
        self.net.write_text("module upli_burst_control(input i_clk, input i_data, output o_data, output [2:0] o_ties);\n"
                            "BUFFD1BWP40P140 driver(.I(i_data),.Z(o_data));\nassign o_ties=3'b101;\nendmodule\n")
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = self.run / "mapped.json"
        # Start from an empty Yosys design: the journal refers to the serialized
        # pre-sizing graph, whose auto-generated names can differ from memory.
        command = f'tcl {APPLY}; check -assert; write_json {output}'
        result = subprocess.run(["yosys", "-Q", "-T", "-p", command], capture_output=True, text=True,
                                env=dict(os.environ, UALINK_SIZE_CHANGES=str(self.changes),
                                         UALINK_NETLIST=str(self.net), UALINK_LIBERTY=str(self.lib)))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        graph = json.loads(output.read_text())["modules"]["upli_burst_control"]
        self.assertEqual(graph["ports"]["o_ties"]["bits"], ["1", "0", "1"])
        self.assertEqual(graph["cells"]["driver"]["type"], "BUFFD2BWP40P140")
        self.assertEqual(graph["cells"]["driver"]["connections"]["I"], graph["ports"]["i_data"]["bits"])
        self.assertEqual(graph["cells"]["driver"]["connections"]["Z"], graph["ports"]["o_data"]["bits"])

    @unittest.skipUnless(shutil.which("yosys"), "Yosys is required")
    def test_journal_cannot_silently_resize_a_different_original_cell(self):
        self.assertTrue(APPLY.is_file(), "missing checked journal application")
        self.lib.write_text(fixture_library(0.400, 0.200))
        self.changes.write_text("{driver BUFFD2BWP40P140 BUFFD1BWP40P140}\n")
        output = self.run / "must_not_emit.json"
        command = f'read_liberty -lib {self.lib}; read_verilog {self.net}; tcl {APPLY}; write_json {output}'
        result = subprocess.run(["yosys", "-Q", "-T", "-p", command], capture_output=True, text=True,
                                env=dict(os.environ, UALINK_SIZE_CHANGES=str(self.changes),
                                         UALINK_NETLIST=str(self.net), UALINK_LIBERTY=str(self.lib)))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
