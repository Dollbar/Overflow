"""Run python3 verification/tl_tx_prepared/test_dormant_inventory.py.
Outputs unittest results using retained mapped layouts; next run dormant SAT.
"""
import json
import unittest
from pathlib import Path
from run_dormant_state import dormant_inventory

BASE = Path(__file__).resolve().parents[2] / 'build/verification/tl_tx_prepared/mapped_pair'


class DormantInventory(unittest.TestCase):
    def test_exactly_one_lane_payload_can_be_independent(self):
        for width in (8, 16):
            layout = json.loads((BASE / f'w{width}/gate_state.json').read_text())
            for lane in (0, 1):
                payload, fixed, observed = dormant_inventory(layout, lane)
                self.assertEqual(len(payload), 1030 if width == 8 else 1190)
                self.assertEqual(len(fixed), 10)
                self.assertEqual(sum(fixed.values()), 1)
                self.assertEqual(set(payload) | set(observed), set(range(layout['state_bits'])))
                self.assertFalse(set(payload) & set(observed))
                other = layout['aliases'][f'gen_prepare[{1-lane}].Prepare_Inst.r_control']
                self.assertTrue(set(other) <= set(observed))

    def test_invalid_lane_rejected(self):
        layout = json.loads((BASE / 'w8/gate_state.json').read_text())
        for lane in (-1, 2, True):
            with self.assertRaises(ValueError):
                dormant_inventory(layout, lane)


if __name__ == '__main__':
    unittest.main()
