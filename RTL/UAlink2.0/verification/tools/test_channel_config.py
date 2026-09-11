"""Execute the actual Tcl profile parser; no textual script assertions."""

import os
from pathlib import Path
import subprocess
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/channel_config.tcl"


class ChannelConfigTests(unittest.TestCase):
    def run_config(self, ports="1", width="32", credit="4", capacity="50132", depth="4"):
        env = dict(os.environ, UALINK_PORTS=ports, UALINK_WIDTH=width,
                   UALINK_CREDIT_WIDTH=credit, UALINK_CAP_HEX=capacity, UALINK_RETURN_DEPTH=depth)
        source = ('if {[catch {source {'+str(SCRIPT)+'}} message]} {puts stderr $message; exit 1}\n'
                  'puts "$channel_ports $channel_width $channel_word_width $channel_macro_total"\n'
                  'puts $channel_macro_counts\nputs $channel_capacities\n')
        return subprocess.run(["tclsh"], input=source, text=True, capture_output=True, env=env)

    def test_mixed_width_padding_and_actual_account_macros(self):
        run = self.run_config()
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.splitlines(), ["1 32 40 8", "KD28_SRAM_SDP_256X32 8", "2 3 1 0 5"])

    def test_all_zero_has_no_storage_and_four_port_mapping_is_not_merged(self):
        run = self.run_config(ports="4", capacity="0")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.splitlines()[0:2], ["4 32 40 0", ""])
        run = self.run_config(ports="4", capacity="50132"*4)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.splitlines()[0:2], ["4 32 40 32", "KD28_SRAM_SDP_256X32 32"])

    def test_four_macro_classes_banks_and_width_tiles(self):
        run = self.run_config(width="520", credit="12", capacity="801201101001")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.splitlines(), ["1 520 528 37", "KD28_SRAM_SDP_256X32 17 KD28_SRAM_SDP_512X64 9 KD28_SRAM_SDP_1024X128 5 KD28_SRAM_SDP_2048X256 6", "1 257 513 2049 0"])

    def test_rejects_invalid_ranges_truncation_and_tcl_injection(self):
        for options in ({"ports":"3"}, {"width":"0"}, {"credit":"2"}, {"credit":"17"},
                        {"capacity":"100000"}, {"capacity":"-1"}, {"capacity":"1;exit 0"},
                        {"depth":"0"}, {"depth":"17"}):
            with self.subTest(options=options):
                self.assertNotEqual(self.run_config(**options).returncode, 0)


if __name__ == "__main__":
    unittest.main()
