"""Run python3 verification/tl_tx_prepared/test_physical_audit.py --graph FILE.
Qualifies the audit against actual mapped cells; next check_physical.py.
"""
from pathlib import Path
import argparse
import copy
import json
import unittest

P=argparse.ArgumentParser();P.add_argument('--graph',type=Path,required=True);ARGS,REST=P.parse_known_args()


class MappedInventoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.graph=json.loads(ARGS.graph.read_text())

    def check(self,g):
        from check_physical import inventory
        return inventory(g)

    def test_actual_inventory(self):self.assertEqual(self.check(self.graph)['macros'],64)

    def test_wrong_macro_clock(self):
        g=copy.deepcopy(self.graph);m=g['modules']['tl_tx_prepared'];c=next(c for c in m['cells'].values() if c['type'].startswith('KD28'))
        c['connections']['RCLK']=m['ports']['i_rstn']['bits']
        with self.assertRaises(ValueError):self.check(g)

    def test_wrong_ff_clock(self):
        g=copy.deepcopy(self.graph);m=g['modules']['tl_tx_prepared'];c=next(c for c in m['cells'].values() if c['type'].startswith('DF'))
        c['connections']['CP']=m['ports']['i_rstn']['bits']
        with self.assertRaises(ValueError):self.check(g)

    def test_missing_macro(self):
        g=copy.deepcopy(self.graph);m=g['modules']['tl_tx_prepared'];n=next(n for n,c in m['cells'].items() if c['type'].startswith('KD28'));del m['cells'][n]
        with self.assertRaises(ValueError):self.check(g)

    def test_missing_macro_pin(self):
        g=copy.deepcopy(self.graph);m=g['modules']['tl_tx_prepared'];c=next(c for c in m['cells'].values() if c['type'].startswith('KD28'));c['connections']['Q'].pop()
        with self.assertRaises(ValueError):self.check(g)

    def test_unknown_cell(self):
        g=copy.deepcopy(self.graph);m=g['modules']['tl_tx_prepared'];m['cells'][next(iter(m['cells']))]['type']='$mystery'
        with self.assertRaises(ValueError):self.check(g)


if __name__=='__main__':unittest.main(argv=[__file__]+REST)
