"""Literal DL/PL2.0 table3-5 calendar checks at transmitted-codeword boundaries.
Run: python3 [-O] -m unittest verification.model.test_rs_rate_calendar -v
Output: model tests; next connect the independently checked calendar to actual RS RTL.
"""
import unittest
try:
    from model.ualink.rs_rate_calendar import tx_codeword_kind
except ModuleNotFoundError as error:
    if error.name!='model.ualink.rs_rate_calendar':raise
    tx_codeword_kind=None

class RateCalendarTests(unittest.TestCase):
    def setUp(self):self.assertIsNotNone(tx_codeword_kind,'RS calendar not implemented')
    def test_literal_normal_boundaries(self):
        vectors={0:'alignment_marker',1:'dl_flit',1023:'dl_flit',1024:'rate_idle',1025:'dl_flit',2048:'rate_idle',3072:'rate_idle',4095:'dl_flit',4096:'alignment_marker',4097:'dl_flit'}
        for index,kind in vectors.items():self.assertEqual(tx_codeword_kind(200,1,index),kind,index)
    def test_all_six_table_profiles_normal_cycles(self):
        for rate,lanes,period in ((100,1,4096),(100,2,4096),(100,4,8192),(200,1,4096),(200,2,8192),(200,4,16384)):
            slots=[tx_codeword_kind(rate,lanes,i) for i in range(2*period)]
            self.assertEqual([i for i,k in enumerate(slots) if k=='alignment_marker'],[0,period])
            self.assertEqual([i for i,k in enumerate(slots) if k=='rate_idle'],[i for i in range(1024,2*period,1024) if i!=period])
            self.assertEqual(slots.count('dl_flit'),2*period-2*period//1024)
            self.assertEqual(set(slots),{'dl_flit','rate_idle','alignment_marker'})
    def test_all_six_table_profiles_rapid_cycles(self):
        for rate,lanes,period,ram in ((100,1,4096,32),(100,2,4096,32),(100,4,8192,64),(200,1,4096,32),(200,2,8192,64),(200,4,16384,128)):
            slots=[tx_codeword_kind(rate,lanes,i,rapid_alignment=True) for i in range(2*period)]
            self.assertEqual([i for i,k in enumerate(slots) if k=='rapid_alignment_marker'],list(range(0,2*period,ram)))
            self.assertEqual(slots.count('rapid_alignment_marker'),256)
            self.assertEqual(set(slots),{'dl_flit','rapid_alignment_marker'})
    def test_literal_aggregate_and_lane_examples(self):
        self.assertEqual(tx_codeword_kind(100,2,32,rapid_alignment=True),'rapid_alignment_marker')
        self.assertEqual(tx_codeword_kind(200,1,32,rapid_alignment=True),'rapid_alignment_marker')
        self.assertEqual(tx_codeword_kind(100,4,4096),'rate_idle')
        self.assertEqual(tx_codeword_kind(200,2,8192),'alignment_marker')
    def test_large_ordinal_keeps_codeword_epoch(self):
        epoch=16384*(2**60)
        for offset,kind in ((0,'alignment_marker'),(1,'dl_flit'),(1024,'rate_idle'),(16384,'alignment_marker')):
            self.assertEqual(tx_codeword_kind(200,4,epoch+offset),kind)
    def test_invalid_profiles_are_rejected(self):
        for rate,lanes in ((50,1),(400,1),(100,0),(200,3),(200,8),(True,1),(200,True),(200.0,1),(200,1.0)):
            with self.subTest(rate=rate,lanes=lanes),self.assertRaises(ValueError):tx_codeword_kind(rate,lanes,0)
    def test_invalid_ordinals_are_rejected(self):
        for index in (-1,True,1.0,'0',None):
            with self.subTest(index=index),self.assertRaises(ValueError):tx_codeword_kind(200,1,index)
    def test_mode_is_explicit_boolean(self):
        for mode in (0,1,'rapid',None):
            with self.subTest(mode=mode),self.assertRaises(ValueError):tx_codeword_kind(200,1,0,rapid_alignment=mode)

if __name__=='__main__':unittest.main()
