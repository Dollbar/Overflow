"""Run after step/case artifacts exist:
python3 verification/tl_prepared_partition/test_equivalence_evidence.py.
Exercises the audit on real graphs and deliberate graph corruption. No EDA output
is modified; next run the complete composition auditor in normal and -O modes.
"""
from pathlib import Path
import copy
import hashlib
import unittest

from check_equivalence import audit_cut,audit_cofactor,read,reference_identity,OLD_COMMENT,NEW_COMMENT

ROOT=Path(__file__).resolve().parents[2]
STAGE=ROOT/'build/verification/tl_prepared_equivalence'


class Tests(unittest.TestCase):
    def test_reference_declaration_comment_only(self):
        current=Path(__file__).with_name('reference.v').read_bytes()
        old=current.replace(NEW_COMMENT,OLD_COMMENT,1)
        self.assertTrue(reference_identity(current,hashlib.sha256(old).hexdigest()))

    def test_reference_comment_bridge_rejects_rtl_change(self):
        current=Path(__file__).with_name('reference.v').read_bytes()
        old=current.replace(NEW_COMMENT,OLD_COMMENT,1)
        changed=current.replace(b'if(o_captured)begin',b'if(i_source_valid)begin',1)
        self.assertNotEqual(changed,current)
        self.assertFalse(reference_identity(changed,hashlib.sha256(old).hexdigest()))

    @classmethod
    def setUpClass(cls):
        folder=STAGE/'step_observed/w8'
        cls.original=read(folder/'gate_original.json')['modules']['tl_prepared_partition']
        cls.cut=read(folder/'gate_cut.json')['modules']['step_gate']
        cls.layout=read(folder/'gate_state.json')
        cls.step=read(folder/'step_structure.json')
        cls.case=read(STAGE/'cases/w8/owned_0/cofactor.json')
        cls.fixed=dict(i_rstn=1,h_owned=1,h_cursor=0)

    def test_actual_graphs_are_accepted(self):
        audit_cut(self.original,self.cut,self.layout)
        audit_cofactor(self.step,self.case,self.fixed)

    def test_next_state_cannot_be_replaced_by_current_state(self):
        cut=copy.deepcopy(self.cut);current=self.layout['fields']['control']['q'][0]
        self.assertNotEqual(cut['ports']['n_control']['bits'][0],current)
        cut['ports']['n_control']['bits'][0]=current
        with self.assertRaises(ValueError):audit_cut(self.original,cut,self.layout)

    def test_original_capture_acknowledgement_cannot_be_dropped(self):
        cut=copy.deepcopy(self.cut);del cut['ports']['o_captured']
        with self.assertRaises(ValueError):audit_cut(self.original,cut,self.layout)

    def test_clock_must_be_actual_primary_edge(self):
        original=copy.deepcopy(self.original)
        cell=next(c for c in original['cells'].values() if c['type']=='$dff')
        cell['connections']['CLK']=original['ports']['i_done']['bits']
        with self.assertRaises(ValueError):audit_cut(original,self.cut,self.layout)

    def test_cofactor_cannot_drop_a_combinational_equation(self):
        case=copy.deepcopy(self.case);cells=case['modules']['step']['cells'];del cells[next(iter(cells))]
        with self.assertRaises(ValueError):audit_cofactor(self.step,case,self.fixed)

    def test_cofactor_cannot_change_a_nonfixed_input(self):
        case=copy.deepcopy(self.case)
        bits=case['modules']['step']['ports']['i_ready']['bits'];bits[0]='0'
        with self.assertRaises(ValueError):audit_cofactor(self.step,case,self.fixed)


if __name__=='__main__':
    unittest.main()
