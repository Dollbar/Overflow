"""Run python3 -m unittest discover -s verification/upli_fifo_payload -p test_slices.py.
Expect four passing tests on stdout, using the retained payload_full fixture.
Check that payload slicing covers every bit and retains the actual interface
and all control obligations. Next audit all actual slice induction evidence.
"""
import unittest
from run_formal import ROOT
from run_sliced import slice_properties, coverage
from check_formal import check_slice_coverage


class SliceTests(unittest.TestCase):
    def test_no_gap_or_overlap(self):
        self.assertEqual(coverage(512, 64), [(i,64) for i in range(0,512,64)])
        self.assertEqual(coverage(513,64)[-1],(512,1))
        with self.assertRaises(ValueError):
            coverage(512,0)

    def test_actual_interface_and_control_preserved(self):
        path=ROOT/'build/verification/upli_fifo_payload/payload_full/w512_d3_raw0/properties.sv'
        source=path.read_text();sliced=slice_properties(source,512,448,64,3)
        self.assertIn('[511:0] i_write_data',sliced)
        self.assertIn('reg [63:0] reference[0:2];',sliced)
        self.assertIn('o_read_data[448 +: 64]==reference[0]',sliced)
        self.assertIn('reference[2]<=i_write_data[448 +: 64]',sliced)
        self.assertIn('f_rd[448 +: 64]==reference[f_cached]',sliced)
        self.assertEqual(source.count('assert('),sliced.count('assert('))
        self.assertEqual(source.count('assume('),sliced.count('assume('))

    def test_missing_high_bits_rejected(self):
        with self.assertRaises(ValueError):
            check_slice_coverage([(0,448)],512)

    def test_overlap_rejected(self):
        with self.assertRaises(ValueError):
            check_slice_coverage([(0,256),(255,257)],512)


if __name__=='__main__':
    unittest.main()
