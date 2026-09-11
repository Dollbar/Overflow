"""Exercise the real UART journal importer on synthetic connectivity fixtures.

Run: python3 -m unittest verification.tools.test_uart_tx_sizing_guard -v
Outputs: unittest results with temporary Yosys graphs; no process claims.
Next: complete actual-library all-state equivalence and all-corner timing.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from verification.tools.test_burst_sizing import fixture_library

SCRIPT = Path(__file__).resolve().parents[2]/'scripts/apply_uart_tx_sizing.tcl'


@unittest.skipUnless(shutil.which('yosys'), 'actual Yosys required')
class UARTTxSizingGuardTests(unittest.TestCase):
    def exercise(self, journal):
        with tempfile.TemporaryDirectory(prefix='uart_tx_journal_guard_') as directory:
            run = Path(directory)
            lib, net, changes, out = (run/n for n in ('synthetic.lib', 'original.v', 'changes.tcl', 'mapped.json'))
            lib.write_text(fixture_library(0.4, 0.2))
            original = '''module dl_uart_tx_source(input i_clk,input i_data,output o_first,output o_second,output [2:0] o_ties);
BUFFD1BWP40P140 first(.I(i_data),.Z(o_first));
BUFFD2BWP40P140 second(.I(i_data),.Z(o_second));
assign o_ties=3'b101;
endmodule
'''
            net.write_text(original)
            changes.write_text(journal)
            wrapper = run/'apply.tcl'
            wrapper.write_text('source $env(UART_TEST_SCRIPT)\n'
                               'yosys hierarchy -check -top dl_uart_tx_source\n'
                               'yosys check -assert\n'
                               'yosys write_json $env(UART_TEST_OUTPUT)\n')
            result = subprocess.run(['yosys', '-Q', '-T', '-c', str(wrapper)],
                env=dict(os.environ, UART_TEST_SCRIPT=str(SCRIPT), UART_TEST_OUTPUT=str(out),
                         UALINK_LIBERTY=str(lib), UALINK_NETLIST=str(net), UALINK_SIZE_CHANGES=str(changes)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(net.read_text(), original)
            return result, json.loads(out.read_text()) if out.exists() else None

    def test_only_selected_cell_changes_and_output_constants_survive(self):
        result, design = self.exercise('{first BUFFD1BWP40P140 BUFFD2BWP40P140}\n')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        top = design['modules']['dl_uart_tx_source']
        self.assertEqual(top['ports']['o_ties']['bits'], ['1', '0', '1'])
        self.assertEqual(top['cells']['first']['type'], 'BUFFD2BWP40P140')
        self.assertEqual(top['cells']['first']['connections']['I'], top['ports']['i_data']['bits'])
        self.assertEqual(top['cells']['second']['connections']['I'], top['ports']['i_data']['bits'])
        self.assertEqual(top['cells']['first']['connections']['Z'], top['ports']['o_first']['bits'])
        self.assertEqual(top['cells']['second']['connections']['Z'], top['ports']['o_second']['bits'])

    def test_wildcard_cannot_change_an_extra_cell_of_a_different_type(self):
        result, design = self.exercise('{* BUFFD1BWP40P140 BUFFD2BWP40P140}\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(design)
        self.assertIn('Assertion failed: selection contains 2 elements instead of the asserted 1', result.stdout+result.stderr)

    def test_wrong_original_and_nonexistent_cell_are_rejected(self):
        for journal in ('{first BUFFD2BWP40P140 BUFFD1BWP40P140}',
                        '{absent BUFFD1BWP40P140 BUFFD2BWP40P140}'):
            with self.subTest(journal=journal):
                result, design = self.exercise(journal)
                self.assertNotEqual(result.returncode, 0)
                self.assertIsNone(design)

    def test_malformed_and_undefined_replacements_cannot_emit_accepted_graph(self):
        for journal in ('{first BUFFD1BWP40P140}', '{first BUFFD1BWP40P140 missing_cell}'):
            with self.subTest(journal=journal):
                result, design = self.exercise(journal)
                self.assertNotEqual(result.returncode, 0)
                self.assertIsNone(design)


if __name__ == '__main__':
    unittest.main()
