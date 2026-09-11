"""Run: python3 verification/tl_receive_credit/test_model.py.
Outputs unittest results; next run actual SRAM/FC integration RTL tests.
"""
import importlib.util
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'model/tl'))

class Tests(unittest.TestCase):
    def policy(self):
        spec=importlib.util.find_spec('receive_credit')
        self.assertIsNotNone(spec,'actual FIFO/credit publication integration policy is missing')
        import receive_credit
        return receive_credit

    def test_capacity_boundary(self):
        p=self.policy();cap=[0]*20;cap[0]=cap[10]=cap[15]=1
        self.assertEqual(p.required_words(cap),6)
        self.assertTrue(p.configuration_valid(cap,width=8,depth=6,shared=False))
        self.assertFalse(p.configuration_valid(cap,width=8,depth=5,shared=False))

    def test_shared_pool_budget_is_counted_once_per_issued_credit(self):
        p=self.policy();cap=[0]*20;cap[10]=2;cap[15]=3
        self.assertEqual(p.required_words(cap),10)
        self.assertTrue(p.configuration_valid(cap,width=8,depth=10,shared=True))
        self.assertTrue(p.configuration_valid([0]*20,width=1,depth=1,shared=True))
        self.assertFalse(p.configuration_valid([0]*20,width=1,depth=1,shared=False))

    def test_vector_and_parameter_rejection(self):
        p=self.policy()
        for cap,w,d in [([1]*19,8,100),([1]*20,0,100),([1]*20,17,100),([1]*20,8,0),([1]*20,8,65536),([2]*20,1,100),([-1]*20,8,100)]:
            self.assertFalse(p.configuration_valid(cap,width=w,depth=d,shared=True))
        self.assertFalse(p.configuration_valid([65535]*20,width=16,depth=65535,shared=True))

    def test_consumer_and_credit_are_atomic(self):
        p=self.policy()
        for valid in (False,True):
            for ready in (False,True):
                for credit in (False,True):
                    for fatal in (False,True):
                        out=p.retirement(valid,ready,credit,fatal)
                        self.assertEqual(out['retired'],out['release_taken'])
                        self.assertEqual(out['retired'],valid and ready and credit and not fatal)
                        self.assertEqual(out['read_valid'],valid and credit and not fatal)

if __name__=='__main__':unittest.main(verbosity=2)
