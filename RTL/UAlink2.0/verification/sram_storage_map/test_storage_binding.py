"""Run python3 -m unittest discover -s verification/sram_storage_map -p test_storage_binding.py.
First generate the fixture with:
python3 verification/sram_storage_map/check_storage_binding.py --kd28-root PATH
--label production_bindings --widths 256 512 600 --depths 1 2 3 5
Expect four tests on stdout using the actual production graph. Next execute
check_storage_binding.py on the production-width matrix with explicit KD28 root.
"""
import copy
import json
import unittest
from run_formal import ROOT
from check_storage_binding import inspect_binding


class BindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.graph=json.loads((ROOT/'build/verification/sram_storage_map/production_bindings/w600_d3_raw0/binding.json').read_text())

    def storage(self,graph):
        mods=graph['modules']
        return mods[mods['binding']['cells']['dut']['type']]

    def test_actual_binding(self):
        self.assertEqual(inspect_binding(self.graph,600,3,0)['macro_count'],19)

    def test_read_return_bypass_rejected(self):
        graph=copy.deepcopy(self.graph);m=self.storage(graph)
        m['cells']['Fifo_Inst']['connections']['i_sram_read_data']=m['ports']['i_write_data']['bits']
        with self.assertRaises(ValueError):
            inspect_binding(graph,600,3,0)

    def test_wrong_logical_capacity_rejected(self):
        graph=copy.deepcopy(self.graph);m=self.storage(graph)
        f=graph['modules'][m['cells']['Fifo_Inst']['type']]
        f['parameter_default_values']['C_DEPTH']=format(4,'032b')
        with self.assertRaises(ValueError):
            inspect_binding(graph,600,3,0)

    def test_fixed_model_mask_bypass_rejected(self):
        graph=copy.deepcopy(self.graph);m=graph['modules']['KD28_SRAM_SDP_256X32']
        m['cells']['u_model']['connections']['write_mask_i']=['0']*4
        with self.assertRaises(ValueError):
            inspect_binding(graph,600,3,0)


if __name__=='__main__':
    unittest.main()
