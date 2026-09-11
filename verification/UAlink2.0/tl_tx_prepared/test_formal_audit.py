"""Run: python3 verification/tl_tx_prepared/test_formal_audit.py --fixture DIR.
Uses real elaborated graphs from run_formal.py; outputs unittest results.
Next run the source-bound whole-matrix evidence auditor.
"""
from pathlib import Path
import argparse
import copy
import json
import tempfile
import unittest

P=argparse.ArgumentParser();P.add_argument('--fixture',type=Path,required=True)
ARGS,OTHER=P.parse_known_args()


class FormalBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original=json.loads((ARGS.fixture/'original.json').read_text())
        cls.observed=json.loads((ARGS.fixture/'observed.json').read_text())

    def check(self, graph):
        from check_formal import audit_transform
        return audit_transform(self.original,graph)

    def test_accepts_actual_memory_only_abstraction(self):
        self.assertEqual(self.check(self.observed)['macros'],64)

    def test_rejects_modified_real_state_input(self):
        graph=copy.deepcopy(self.observed)
        ff=next(c for c in graph['modules']['tl_tx_prepared']['cells'].values() if c['type']=='$dff')
        ff['connections']['D'][0]='0'
        with self.assertRaises(ValueError):self.check(graph)

    def test_rejects_removed_control_cell(self):
        graph=copy.deepcopy(self.observed);cells=graph['modules']['tl_tx_prepared']['cells']
        del cells[next(iter(cells))]
        with self.assertRaises(ValueError):self.check(graph)

    def test_rejects_arbitrary_internal_control_input(self):
        graph=copy.deepcopy(self.observed);top=graph['modules']['tl_tx_prepared']
        top['ports']['f_cheat']=dict(direction='input',bits=top['ports']['f_owned_0']['bits'])
        with self.assertRaises(ValueError):self.check(graph)

    def test_rejects_wrong_observed_owner(self):
        graph=copy.deepcopy(self.observed);ports=graph['modules']['tl_tx_prepared']['ports']
        ports['f_owned_0']['bits']=ports['f_owned_1']['bits']
        with self.assertRaises(ValueError):self.check(graph)

    def test_rejects_changed_original_port(self):
        graph=copy.deepcopy(self.observed)
        graph['modules']['tl_tx_prepared']['ports']['o_header_count']['bits'][0]='0'
        with self.assertRaises(ValueError):self.check(graph)

    def test_rejects_memory_output_zeroed(self):
        graph=copy.deepcopy(self.observed)
        graph['modules']['tl_tx_prepared']['ports']['f_memory_0']['bits'][0]='0'
        with self.assertRaises(ValueError):self.check(graph)

    def test_rejects_changed_non_top_module(self):
        graph=copy.deepcopy(self.observed)
        name=next(n for n in graph['modules'] if n!='tl_tx_prepared')
        graph['modules'][name]['attributes']['blackbox']='0'
        with self.assertRaises(ValueError):self.check(graph)

    def test_scalar_witness_missing_initial_value(self):
        from check_formal import wave_values
        self.assertEqual(wave_values(dict(name='i_rstn',wave='401.')),[None,0,1,1])

    def test_bus_witness_missing_initial_value(self):
        from check_formal import wave_values
        self.assertEqual(wave_values(dict(name='ready',wave='4==.',data=['','00','11'])),[None,0,3,3])

    def test_rejects_extra_environment_assumption(self):
        from check_formal import audit_properties
        source=(ARGS.fixture/'properties.sv').read_text().replace('assume(!i_rstn);','assume(!i_rstn);assume(i_auth);')
        graph=json.loads((ARGS.fixture/'proof.json').read_text())
        with self.assertRaises(ValueError):audit_properties(source,1,graph)

    def test_rejects_weakened_group_balance(self):
        from check_formal import audit_properties
        source=(ARGS.fixture/'properties.sv').read_text().replace('assert(groups_0<=1);','assert(groups_0<=2);')
        graph=json.loads((ARGS.fixture/'proof.json').read_text())
        with self.assertRaises(ValueError):audit_properties(source,1,graph)

    def test_rejects_missing_compiled_assertion(self):
        from check_formal import audit_properties
        source=(ARGS.fixture/'properties.sv').read_text()
        graph=json.loads((ARGS.fixture/'proof.json').read_text());cells=graph['modules']['properties']['cells']
        name=next(n for n,c in cells.items() if c['type']=='$assert');del cells[name]
        with self.assertRaises(ValueError):audit_properties(source,1,graph)

    def test_rejects_all_unknown_fault_witness(self):
        from check_formal import fault_witness
        names=('i_rstn','i_auth','i_source_tags_valid','o_source_ready','o_source_captured','o_partition_taken','o_group_queued','f_write_0','f_write_1','f_owned_0','f_owned_1')
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'witness.json'
            path.write_text(json.dumps({'signal':[dict(name=n,wave='xxxx') for n in names]}))
            with self.assertRaises(ValueError):fault_witness(path,'tags')

    def test_rejects_fault_witness_without_a_violation(self):
        from check_formal import fault_witness
        names=('i_rstn','i_auth','i_source_tags_valid','o_source_ready','o_source_captured','o_partition_taken','o_group_queued','f_write_0','f_write_1','f_owned_0','f_owned_1')
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'witness.json'
            path.write_text(json.dumps({'signal':[dict(name=n,wave='0...') for n in names]}))
            with self.assertRaises(ValueError):fault_witness(path,'enqueue')


if __name__=='__main__':unittest.main(argv=[__file__]+OTHER)
