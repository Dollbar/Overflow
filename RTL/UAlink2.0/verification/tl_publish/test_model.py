"""Run python3 verification/tl_publish/test_model.py; next RTL and actual receiver integration."""
from pathlib import Path
import json,sys,unittest
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/tl_publish';S.mkdir(parents=True,exist_ok=True);sys.path.insert(0,str(R/'model/tl'))

from credit_publish import Publisher
class Tests(unittest.TestCase):
 def test_initial_chunk_and_order(self):
  p=Publisher(8);cap=[10]*10+[65]*10;p.step(start=True,capacities=cap);received=[0]*20;messages=0
  for _ in range(200):
   out=p.step(send=True)
   if out['taken']:
    if out['complete']:self.assertEqual(received,cap);messages+=1
    else:
     for i,n in enumerate(out['grants']):received[i]+=n
  self.assertEqual(messages,1);self.assertTrue(p.done);self.assertEqual(sum(p.pending),0)
 def test_hold_and_late_done(self):
  p=Publisher(3);p.step(start=True,capacities=[1]*20,shared=True);p.step();before=p.output()
  for _ in range(5):self.assertEqual(p.step(),before)
  self.assertFalse(p.done)
 def test_invalid_nonshared(self):
  p=Publisher(8);r=p.step(start=True,capacities=[0]*20);self.assertFalse(r['start_taken']);self.assertTrue(r['config_error']);self.assertFalse(p.active)
 def test_shared_zero_class(self):
  cap=[0]*20;cap[10]=2;p=Publisher(3);p.step(start=True,capacities=cap,shared=True)
  for _ in range(10):p.step(send=True)
  self.assertTrue(p.done);rel=[0]*20;rel[15]=2;self.assertTrue(p.step(release=rel,release_valid=True)['release_taken'])
  totals=[0]*20
  for _ in range(5):
   r=p.step(send=True)
   if r['taken']:
    for i,n in enumerate(r['grants']):totals[i]+=n
  self.assertEqual(totals[15],2)
 def test_no_same_cycle_space_bypass(self):
  p=Publisher(1);p.step(start=True,capacities=[0]*20,shared=True)
  for _ in range(4):p.step(send=True)
  rel=[0]*20;rel[0]=3;p.step(release_valid=True,release=rel);p.step();self.assertTrue(p.valid)
  one=[0]*20;one[0]=1;r=p.step(send=True,release_valid=True,release=one);self.assertFalse(r['release_taken']);self.assertEqual(p.pending[0],0)
 def test_reset_cancels_offer(self):
  p=Publisher(8);p.step(start=True,capacities=[1]*20);p.step();self.assertTrue(p.valid);p.step(reset=True);self.assertFalse(p.valid);self.assertFalse(p.active);self.assertEqual(sum(p.pending),0)
if __name__=='__main__':unittest.main(verbosity=2)
