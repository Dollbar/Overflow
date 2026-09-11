"""Run: python3 verification/tl_tx_channels/test_model.py; next actual RTL tests.
Outputs class-selection/ownership reference tests, not complete protocol certification.
"""
from pathlib import Path
import sys,unittest
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'model/tl'))
from tx_channels import Channels
REQ=(1<<124)|(0x23<<118)|2
RSP=(2<<60)|(2<<44)|(1<<37)
def inputs(**changes):
    src=[dict(valid=True,header=REQ,tags_valid=True,tags=0,data_valid=2,data0=0x11,data1=0x12),dict(valid=True,header=RSP,tags_valid=True,tags=0,data_valid=2,data0=0x21,data1=0x22)]
    d=dict(sources=src,pending=0,auth=False,done=True,shared=False,available=[8]*20,capacity=[8]*20,request_budget=4,response_budget=8,fc_valid=False,fc=1<<22,fc_msg=0)
    d.update(changes);return d
class TestChannels(unittest.TestCase):
    def test_blocked_request_does_not_block_response(self):
        x=inputs();x['available'][11]=0;o=Channels().step(**x)
        self.assertEqual((o['header_taken'],o['data_taken'],o['flit']),(2,(0,1),(0x21<<256)|RSP))
    def test_blocked_response_does_not_block_request(self):
        x=inputs();x['available'][16]=0;o=Channels().step(**x)
        self.assertEqual((o['header_taken'],o['data_taken']),(1,(1,0)))
    def test_tail_owner_does_not_follow_new_header_class(self):
        c=Channels();c.step(**inputs())
        o=c.step(**inputs(pending=1));self.assertEqual((o['header_taken'],o['data_taken'],o['flit']),(2,(1,0),(0x11<<256)|RSP))
        o=c.step(**inputs(pending=6));self.assertEqual((o['header_taken'],o['data_taken'],o['flit']),(0,(0,2),(0x22<<256)|0x21))
    def test_stalled_header_stays_on_chosen_class(self):
        c=Channels();x=inputs();x['sources'][0]['valid']=False;a=c.step(**x,transfer=False)
        b=c.step(**inputs(),transfer=False);self.assertEqual(a['flit'],b['flit']);self.assertEqual(b['header_taken'],0)
        b=c.step(**inputs());self.assertEqual(b['header_taken'],2)
    def test_missing_request_payload_and_budget_choose_response(self):
        x=inputs();x['sources'][0]['data_valid']=0;self.assertEqual(Channels().step(**x)['header_taken'],2)
        x=inputs(request_budget=0);self.assertEqual(Channels().step(**x)['header_taken'],2)
    def test_class_mismatch_does_not_send_as_wrong_queue(self):
        x=inputs();x['sources'][0]['header']=RSP;o=Channels().step(**x);self.assertEqual(o['header_taken'],2);self.assertEqual(o['header_error'],1)
    def test_budget_recovery_not_hidden_by_unfunded_other_class(self):
        x=inputs(response_budget=1);x['available'][11]=0;x['sources'][1]['header']=sum((5<<28)<<(32*j) for j in range(4))
        o=Channels().step(**x);self.assertEqual((o['valid'],o['flit'],o['header_taken']),(True,0,0))
    def test_fairness_and_auth_tail(self):
        c=Channels();self.assertEqual([c.step(**inputs())['header_taken'] for _ in range(6)],[1,2,1,2,1,2])
        c=Channels();c.step(**inputs(auth=True));o=c.step(**inputs(auth=True,pending=1));self.assertEqual((o['header_taken'],o['data_taken']),(0,(1,0)))
        self.assertFalse(c.step(**inputs(),reset=True)['valid'])
if __name__=='__main__':unittest.main()
