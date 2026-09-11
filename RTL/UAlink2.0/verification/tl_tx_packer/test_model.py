"""Run: python3 verification/tl_tx_packer/test_model.py.
Outputs reference checks; next run the same behavior through actual RTL.
"""
from pathlib import Path
import sys,unittest
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'model/tl'))
from tx_packer import Packer
HEAD=(1<<124)|(0x23<<118)|2

def inputs(**change):
    x=dict(pending=0,auth=False,done=True,shared=False,available=[8]*20,capacity=[8]*20,request_budget=4,response_budget=8,header_valid=True,header=HEAD,tags_valid=True,tags=0,data_valid=2,data0=0x1234,data1=0x5678,fc_valid=False,fc=1<<22,fc_msg=0)
    x.update(change);return x

class TestPacker(unittest.TestCase):
    def test_blocked_new_header_does_not_hold_old_tail(self):
        x=inputs(pending=1,available=[0]*20);o=Packer().step(**x)
        self.assertEqual((o['flit'],o['msg'],o['header_taken'],o['data_taken']), (0x1234<<256,0,False,1))
    def test_fc_and_tail_share_flit(self):
        o=Packer().step(**inputs(pending=1,fc_valid=True));self.assertEqual((o['flit'],o['fc_taken'],o['data_taken']),((0x1234<<256)|(1<<22),True,1))
    def test_auth_tail_cannot_take_new_header(self):
        o=Packer().step(**inputs(pending=1,auth=True));self.assertEqual((o['flit'],o['header_taken'],o['tags_taken']),(0x1234<<256,False,False))
    def test_completion_upper_waits_for_tail(self):
        p=Packer();o=p.step(**inputs(pending=1,fc_valid=True,fc=1<<256,fc_msg=2));self.assertFalse(o['fc_taken']);self.assertFalse(o['header_taken']);self.assertEqual(o['data_taken'],1)
        o=p.step(**inputs(pending=0,fc_valid=True,fc=1<<256,fc_msg=2));self.assertEqual((o['msg'],o['flit'],o['fc_taken']),(2,1<<256,True))
    def test_stall_holds_choice_and_consumes_nothing(self):
        p=Packer();a=p.step(**inputs(),transfer=False);b=p.step(**inputs(fc_valid=True),transfer=False)
        self.assertEqual((a['flit'],a['msg']),(b['flit'],b['msg']));self.assertEqual((b['header_taken'],b['data_taken'],b['fc_taken']),(False,0,False))
        c=p.step(**inputs(fc_valid=True));self.assertTrue(c['header_taken']);self.assertFalse(c['fc_taken'])
    def test_data_tenure_no_control_and_budget_nop(self):
        o=Packer().step(**inputs(pending=73,fc_valid=True));self.assertEqual((o['flit'],o['data_taken'],o['fc_taken']),((0x5678<<256)|0x1234,2,False))
        o=Packer().step(**inputs(request_budget=0));self.assertTrue(o['valid']);self.assertEqual((o['flit'],o['header_taken'],o['data_taken']),(0,False,0))
    def test_round_robin_and_reset(self):
        p=Packer();order=[]
        for _ in range(8):
            o=p.step(**inputs(fc_valid=True));order.append(o['fc_taken'])
        self.assertEqual(order,[True,False]*4)
        o=p.step(**inputs(fc_valid=True),reset=True);self.assertFalse(o['valid']);self.assertFalse(o['fc_taken'])
    def test_auth_and_missing_data_inputs(self):
        o=Packer().step(**inputs(auth=True,tags=0x88,data_valid=0));self.assertEqual((o['flit'],o['data_taken'],o['tags_taken']),((0x88<<256)|HEAD,0,True))
        o=Packer().step(**inputs(data_valid=0));self.assertFalse(o['valid'])

if __name__=='__main__':unittest.main()
