"""Run python3 verification/tl_tx_prepared/test_reset_inventory.py.
Uses actual mapped_pair layouts; outputs unittest results. Next run reset SAT.
"""
import copy
import json
import unittest
from pathlib import Path

from run_reset_state import reset_inventory

BASE = Path(__file__).resolve().parents[2] / 'build/verification/tl_tx_prepared/mapped_pair'


class ResetInventory(unittest.TestCase):
    def test_actual_reset_and_dormant_coverage(self):
        for width in (8, 16):
            for side in ('gold', 'gate'):
                layout = json.loads((BASE / f'w{width}/{side}_state.json').read_text())
                observed, dormant = reset_inventory(layout, side)
                self.assertEqual(len(observed), 4184 if side == 'gold' else 4194)
                self.assertEqual(len(dormant), 2060 if width == 8 else 2380)
                self.assertEqual(sum(observed.values()), 1 if side == 'gold' else 3)
                for lane in (0, 1):
                    cursor = layout['aliases'][f'gen_prepare[{lane}].Prepare_Inst.r_cursor']
                    self.assertEqual([observed[i] for i in cursor],
                                     [0, 0, 0, 0] if side == 'gold' else [1, 0, 0, 0, 0, 0, 0, 0, 0])

    def test_unknown_preparation_field_cannot_be_excluded(self):
        layout = json.loads((BASE / 'w8/gold_state.json').read_text())
        changed = copy.deepcopy(layout)
        field = 'gen_prepare[0].Prepare_Inst.r_owned'
        changed['aliases'][field + '_unknown'] = changed['aliases'].pop(field)
        with self.assertRaises(ValueError):
            reset_inventory(changed, 'gold')

    def test_unobserved_state_rejected(self):
        layout = json.loads((BASE / 'w8/gold_state.json').read_text())
        layout['state_bits'] += 1
        with self.assertRaises(ValueError):
            reset_inventory(layout, 'gold')


if __name__ == '__main__':
    unittest.main()
