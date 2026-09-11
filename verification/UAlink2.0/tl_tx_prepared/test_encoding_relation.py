"""Run python3 verification/tl_tx_prepared/test_encoding_relation.py.

Uses retained actual mapped_pair/physical_baseline artifacts at WIDTH 8/16.
Outputs unittest results; next qualify actual mapped logic mutations and reset.
"""
import copy
import json
import re
import unittest

from run_encoding_cec import ROOT, relation


class EncodingRelationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        base = ROOT / 'build/verification/tl_tx_prepared'
        cls.cases = []
        for width in (8, 16):
            folder = base / 'mapped_pair' / f'w{width}'
            gold, gate = [json.loads((folder / f'{side}_state.json').read_text())
                          for side in ('gold', 'gate')]
            log = (base / 'physical_baseline' / f'w{width}/map.log').read_text()
            cls.cases.append((width, gold, gate, log))

    def test_actual_codebook_and_complete_state(self):
        for width, gold, gate, log in self.cases:
            with self.subTest(width=width):
                result = relation(gold, gate, log)
                self.assertEqual(result['gold_state_bits'], {8: 6244, 16: 6564}[width])
                self.assertEqual(result['gate_state_bits'], {8: 6254, 16: 6574}[width])
                for table in result['cursor_encodings'].values():
                    self.assertEqual(table, {0: 1, 8: 2, 4: 4, 2: 8, 6: 16,
                                             1: 32, 5: 64, 3: 128, 7: 256})

    def test_missing_codebook_row_rejected(self):
        for _, gold, gate, log in self.cases:
            changed = re.sub(r'\s+0000 -> --------1\n', '\n', log, count=1)
            self.assertNotEqual(log, changed)
            with self.assertRaises(ValueError):
                relation(gold, gate, changed)

    def test_duplicate_hot_code_rejected(self):
        for _, gold, gate, log in self.cases:
            changed = log.replace('1000 -> -------1-', '1000 -> --------1', 1)
            self.assertNotEqual(log, changed)
            with self.assertRaises(ValueError):
                relation(gold, gate, changed)

    def test_uncovered_actual_state_rejected(self):
        for _, gold, gate, log in self.cases:
            for side in ('gold', 'gate'):
                changed = copy.deepcopy(gold if side == 'gold' else gate)
                changed['state_bits'] += 1
                with self.assertRaises(ValueError):
                    relation(changed if side == 'gold' else gold,
                             changed if side == 'gate' else gate, log)

    def test_changed_non_cursor_constant_rejected(self):
        for _, gold, gate, log in self.cases:
            changed = copy.deepcopy(gate)
            field = next(n for n, bits in changed['aliases'].items() if '0' in bits)
            index = changed['aliases'][field].index('0')
            changed['aliases'][field][index] = '1'
            with self.assertRaisesRegex(ValueError, 'constant changed'):
                relation(gold, changed, log)


if __name__ == '__main__':
    unittest.main()
