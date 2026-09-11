"""Run python3 [-O] verification/tl_tx_prepared/test_correspondence_stages.py.
Check candidate evidence selection and rejection of mixed-baseline SAT evidence.
Next run the complete current mapped correspondence audit.
"""
from pathlib import Path
import unittest
from unittest.mock import patch

import check_mapped_correspondence as audit


class StageSelection(unittest.TestCase):
    def test_default_preserves_baseline(self):
        selected = audit.configure_stages(None)
        self.assertTrue(all(k == v for k, v in selected.items()))
        self.assertEqual(len(selected), 10)

    def test_prefix_selects_all_candidate_obligations(self):
        selected = audit.configure_stages('qualification_reuse')
        self.assertEqual(selected['mapped_pair'], 'qualification_reuse_pair')
        self.assertEqual(selected['actual_partition_fault'], 'qualification_reuse_partition_fault')
        self.assertEqual(len(set(selected.values())), 10)
        self.assertTrue(all(v.startswith('qualification_reuse_') for v in selected.values()))

    def test_invalid_prefix_rejected(self):
        for prefix in ('', '../old', '/tmp/source', 'a/b', 'a b'):
            with self.subTest(prefix=prefix), self.assertRaises(ValueError):
                audit.configure_stages(prefix)

    def test_current_reset_script_accepted_only_with_current_pair(self):
        folder = audit.BASE / 'qualification_reuse_reset/w8_gold'
        report = audit.read(folder.parent / 'results.json')
        row = next(r for r in report['results'] if r['width'] == 8 and r['side'] == 'gold')
        selected = audit.configure_stages('qualification_reuse')
        with patch.dict(audit.STAGES, selected, clear=True):
            audit.sat(folder, row)
        selected['mapped_pair'] = 'mapped_pair'
        with patch.dict(audit.STAGES, selected, clear=True):
            with self.assertRaisesRegex(ValueError, 'actual obligation'):
                audit.sat(folder, row)

    def test_baseline_scope_not_accepted_in_candidate_audit(self):
        with patch.dict(audit.STAGES, audit.configure_stages('qualification_reuse'), clear=True):
            with self.assertRaisesRegex(ValueError, 'unknown SAT proof scope'):
                audit.sat(Path('/tmp/independent_reset/w8_gold'), {'proof': {'exit': 0}})


if __name__ == '__main__':
    unittest.main()
