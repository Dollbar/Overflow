"""Run python3 verification/tl_receive/test_release.py.
Writes unittest output to stdout; next RTL and actual SRAM integration.
"""
import json,sys,unittest
from pathlib import Path
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/tl_receive';S.mkdir(parents=True,exist_ok=True);sys.path.insert(0,str(R/'model/tl'))

from receive_context import ReceiveContext
class Tests(unittest.TestCase):
 def test_cmd_no_data(self):
  c=ReceiveContext();r=c.step((1<<124)|(3<<118)|(1<<102));self.assertEqual(r['demands'][0],1);self.assertEqual(r['releases'][0],1);self.assertTrue(r['store'])
 def test_two_halves_then_be(self):
  c=ReceiveContext();w=(3<<60)|(3<<57)|(1<<41)
  a=c.step(w);self.assertEqual((a['demands'][0],a['demands'][10]),(1,1));self.assertEqual(sum(a['releases']),0)
  b=c.step(0);self.assertEqual(b['classes'],('DATA','BYTE_ENABLE'));self.assertEqual((b['releases'][0],b['releases'][10]),(1,1));self.assertEqual(len(c.pending),0)
 def test_auth_separates_header(self):
  c=ReceiveContext(auth=True);w=(1<<124)|(0x23<<118)|(1<<102)|1
  rows=[c.step(w),c.step(),c.step()];self.assertEqual([r['releases'][0] for r in rows],[0,0,1]);self.assertEqual([r['releases'][10] for r in rows],[0,1,1])
 def test_old_tail_new_command(self):
  c=ReceiveContext();c.step((1<<124)|(0x23<<118)|(1<<102));r=c.step((4<<28)|(2<<26));self.assertEqual(r['classes'],('CONTROL','DATA'));self.assertEqual(r['releases'][0],1);self.assertEqual(r['releases'][10],1);self.assertEqual(r['demands'][8],1)
  r=c.step();self.assertEqual((r['releases'][8],r['releases'][18]),(1,1))
 def test_ordinary_message_does_not_release(self):
  c=ReceiveContext();c.step((1<<124)|(0x23<<118));saved=c.pending;r=c.step(msg=(None,0));self.assertEqual(sum(r['releases']),0);self.assertEqual(c.pending,saved);self.assertFalse(r['store'])
 def test_poison_and_stall(self):
  c=ReceiveContext(auth=True);c.step((1<<124)|(0x23<<118));saved=c.pending
  r=c.step(msg=(32,32),transfer=False);self.assertEqual(c.pending,saved);self.assertEqual((r['releases'][1],r['releases'][11]),(1,1))
  c.step(msg=(32,32));self.assertEqual(c.pending,())
 def test_reject_and_reset(self):
  c=ReceiveContext();c.step((3<<60)|(3<<57));saved=c.pending
  with self.assertRaises(ValueError):c.step(msg=(32,32))
  self.assertEqual(c.pending,saved);c.step(reset=True);self.assertEqual(c.pending,())
if __name__=='__main__':unittest.main(verbosity=2)
