"""Run python3 verification/tl_tx_prepared/test_correspondence_audit.py.
Checks missing proof scope and incomplete actual partition evidence rejection.
Next run the whole mapped correspondence auditor under ordinary/optimized Python.
"""
from pathlib import Path
import copy
import tempfile
import unittest

from check_mapped_correspondence import BASE, read, sat, audit_parts
from proof_partitions import Network


class CorrespondenceAudit(unittest.TestCase):
    def test_success_log_cannot_hide_different_sat_obligation(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / 'independent_reset/w8_gold'
            folder.mkdir(parents=True)
            (folder / 'proof.log').write_text('SAT proof finished - no model found: SUCCESS!\n')
            (folder / 'proof.ys').write_text('sat -prove unrelated 0\n')
            with self.assertRaises(ValueError):
                sat(folder, {'proof': {'exit': 0}})

    def test_actual_reset_obligation_accepted(self):
        report = read(BASE / 'independent_reset/results.json')
        row = next(r for r in report['results'] if r['width'] == 8 and r['side'] == 'gold')
        sat(BASE / 'independent_reset/w8_gold', row)

    def test_incomplete_actual_partition_inventory_rejected(self):
        report = read(BASE / 'explicit_wide_partition/results.json')
        row = copy.deepcopy(report['widths']['8'])
        row['results'].pop()
        original = Network((BASE / 'encoded_step_techmapped/w8/gold_pruned.blif').read_text())
        with self.assertRaisesRegex(ValueError, 'incomplete partition matrix'):
            audit_parts(row, {'gold': original}, BASE / 'explicit_wide_partition/w8')

    def test_duplicate_root_cannot_replace_next_state(self):
        report = read(BASE / 'explicit_wide_partition/results.json')
        row = copy.deepcopy(report['widths']['8'])
        row['parts'][1][0] = row['parts'][0][0]
        original = Network((BASE / 'encoded_step_techmapped/w8/gold_pruned.blif').read_text())
        with self.assertRaisesRegex(ValueError, 'omitted, duplicate or unknown'):
            audit_parts(row, {'gold': original}, BASE / 'explicit_wide_partition/w8')


if __name__ == '__main__':
    unittest.main()
