"""A journal must identify exactly one cell, not a wider selection pattern."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from verification.tools.test_burst_sizing import fixture_library


@unittest.skipUnless(shutil.which("yosys"), "actual Yosys required")
class PayloadSizingGuardTests(unittest.TestCase):
    def test_ambiguous_instance_cannot_match_extra_cells_of_another_type(self):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix="ualink_sizing_guard_") as directory:
            run = Path(directory)
            library, netlist = run/"synthetic.lib", run/"original.v"
            journal, output = run/"changes.list", run/"must_not_exist.json"
            library.write_text(fixture_library(0.4,0.2))
            original = ("module upli_burst_sender(input i_clk,input i_data,output o_first,output o_second);\n"
                        "BUFFD1BWP40P140 first(.I(i_data),.Z(o_first));\n"
                        "BUFFD2BWP40P140 second(.I(i_data),.Z(o_second));\nendmodule\n")
            netlist.write_text(original)
            journal.write_text("{* BUFFD1BWP40P140 BUFFD2BWP40P140}\n")
            command = (f"tcl {root/'scripts/apply_burst_sender_sizing.tcl'}; "
                       f"check -assert; write_json {output}")
            result = subprocess.run(["yosys","-Q","-T","-p",command],
                env=dict(os.environ,UALINK_LIBERTY=str(library),UALINK_NETLIST=str(netlist),
                         UALINK_SIZE_CHANGES=str(journal)),
                capture_output=True,text=True,timeout=30,check=False)
            self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertFalse(output.exists())
            self.assertEqual(netlist.read_text(),original)


if __name__ == "__main__":
    unittest.main()
