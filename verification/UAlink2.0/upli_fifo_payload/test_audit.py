"""Run python3 -m unittest discover -s verification/upli_fifo_payload -p test_audit.py.
Expect eight passing tests on stdout. Use real graphs to reject evidence corruption.
The tests require payload_full/w8_d3_raw0; next run check_formal.py on the matrix.
"""
import copy
import json
import unittest

from run_formal import ROOT
from check_formal import check_graph, check_properties


class AuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        folder = ROOT / 'build/verification/upli_fifo_payload/payload_full/w8_d3_raw0'
        cls.original = json.loads((folder / 'original.json').read_text())
        cls.observed = json.loads((folder / 'observed.json').read_text())
        cls.properties = (folder / 'properties.sv').read_text()

    def test_healthy_graph_and_properties(self):
        check_graph(self.original, self.observed, 3, 8)
        check_properties(self.properties, 3, 8, 0)

    def test_clock_changed(self):
        bad = copy.deepcopy(self.observed)
        cell = next(c for c in bad['modules']['fifo_memory']['cells'].values() if c['type'] == '$dff')
        cell['connections']['CLK'] = ['0']
        with self.assertRaises(ValueError):
            check_graph(self.original, bad, 3, 8)

    def test_memory_observation_aliased(self):
        bad = copy.deepcopy(self.observed)
        ports = bad['modules']['fifo_memory']['ports']
        ports['f_mem_1']['bits'] = ports['f_mem_0']['bits']
        with self.assertRaises(ValueError):
            check_graph(self.original, bad, 3, 8)

    def test_internal_input_cut(self):
        bad = copy.deepcopy(self.observed)
        bad['modules']['fifo_memory']['ports']['f_pending']['direction'] = 'input'
        with self.assertRaises(ValueError):
            check_graph(self.original, bad, 3, 8)

    def test_payload_obligation_removed(self):
        bad = self.properties.replace('assert(o_read_data==reference[0]);', '')
        with self.assertRaises(ValueError):
            check_properties(bad, 3, 8, 0)

    def test_stall_assumption_added(self):
        bad = self.properties.replace('if(!started)assume(!i_rstn);', 'if(!started)assume(!i_rstn);assume(i_read_ready);')
        with self.assertRaises(ValueError):
            check_properties(bad, 3, 8, 0)

    def test_reference_admission_tied_to_dut(self):
        bad = self.properties.replace('wire push=i_rstn&&i_write_valid&&(ref_count<3);', 'wire push=i_rstn&&i_write_valid&&o_write_ready;')
        with self.assertRaises(ValueError):
            check_properties(bad, 3, 8, 0)

    def test_permanently_disabled_assertions(self):
        bad = self.properties.replace('started<=1;', 'started<=0;')
        with self.assertRaises(ValueError):
            check_properties(bad, 3, 8, 0)


if __name__ == '__main__':
    unittest.main()
