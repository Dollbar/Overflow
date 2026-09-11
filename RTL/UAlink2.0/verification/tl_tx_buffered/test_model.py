"""Run python3 verification/tl_tx_buffered/test_model.py; next real SRAM regression.
Breaks caught: parity inversion, over-capacity acceptance, partial invalid dequeue,
reset ownership leakage and FIFO order corruption under mixed half counts.
"""
from pathlib import Path
import importlib.util,sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'model/tl'))
class Tests(unittest.TestCase):
    def queue(self,depth):
        self.assertIsNotNone(importlib.util.find_spec('tx_data_fifo'),'required transmit queue reference is missing')
        from tx_data_fifo import HalfQueue
        return HalfQueue(depth)
    def test_single_then_pair_order(self):
        q=self.queue(2);self.assertTrue(q.push([11]));self.assertTrue(q.push([22,33]));self.assertEqual(q.pop(2),[11,22]);self.assertEqual(q.pop(1),[33]);self.assertEqual(q.count,0)
    def test_full_rejects_whole_pair(self):
        q=self.queue(2);q.push([1,2]);q.push([3]);self.assertFalse(q.push([4,5]));self.assertEqual(q.pop(2),[1,2]);self.assertEqual(q.pop(1),[3])
    def test_illegal_take_is_atomic(self):
        q=self.queue(1);q.push([8]);self.assertEqual(q.pop(2),[]);self.assertEqual(q.count,1);self.assertEqual(q.pop(3),[]);self.assertEqual(q.pop(1),[8]);self.assertFalse(q.push([]));self.assertFalse(q.push([1,2,3]))
    def test_partial_offer_resolves_minimum_depth_wait(self):
        q=self.queue(1);q.push([11]);self.assertTrue(hasattr(q,'offer'),'partial offer acceptance is missing')
        self.assertEqual(q.offer([22,33]),1);self.assertEqual(q.pop(2),[11,22]);self.assertEqual(q.offer([33]),1);self.assertEqual(q.pop(1),[33])
    def test_reset_clears_odd_parity(self):
        q=self.queue(1);q.push([99]);q.reset();q.push([4,5]);self.assertEqual(q.pop(2),[4,5])
if __name__=='__main__':unittest.main()
