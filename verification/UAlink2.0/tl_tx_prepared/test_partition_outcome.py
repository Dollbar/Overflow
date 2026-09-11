"""Run python3 verification/tl_tx_prepared/test_partition_outcome.py.
Exercises real ABC pass/mismatch/read-error handling. Next audit actual matrix.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

from run_partitioned_cec import outcome


class PartitionOutcome(unittest.TestCase):
    def invoke(self, other):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            gold = '.model gold\n.inputs a b\n.outputs out\n.names a b out\n11 1\n.end\n'
            (folder / 'gold.blif').write_text(gold)
            (folder / 'gate.blif').write_text(other)
            command = f'cec "{folder}/gold.blif" "{folder}/gate.blif"'
            run = subprocess.run(['yosys-abc', '-c', command], text=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
            return outcome({'exit': run.returncode}, run.stdout)

    def test_real_equivalent_networks(self):
        gate = '.model gate\n.inputs a b\n.outputs out\n.names a b out\n11 1\n.end\n'
        self.assertEqual(self.invoke(gate), 'equivalent')

    def test_real_changed_logic(self):
        gate = '.model gate\n.inputs a b\n.outputs out\n.names a b out\n1- 1\n-1 1\n.end\n'
        self.assertEqual(self.invoke(gate), 'different')

    def test_zero_exit_does_not_turn_read_failure_into_pass(self):
        gate = '.model gate\n.inputs a b\n.outputs out\n.subckt missing A=a B=b Y=out\n.end\n'
        self.assertEqual(self.invoke(gate), 'tool_error')

    def test_timeout_and_warning_override_success_text(self):
        self.assertEqual(outcome({'exit': 124}, 'Networks are equivalent.'), 'timeout')
        self.assertEqual(outcome({'exit': 0}, 'Warning: missing driver\nNetworks are equivalent.'), 'tool_error')


if __name__ == '__main__':
    unittest.main()
