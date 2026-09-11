"""Run python3 verification/tl_control_partition/test_model.py; next actual RTL.
Detects lost fields/tags, mid-field cuts, invalid consumption and shared-pool mistakes.
"""
from pathlib import Path
import importlib.util,sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'model/tl'))
class Tests(unittest.TestCase):
    def choose(self,*args,**kw):
        self.assertIsNotNone(importlib.util.find_spec('control_partition'),'capacity-aware field model missing')
        from control_partition import choose
        return choose(*args,**kw)
    def test_four_distinct_single_beats_preserved(self):
        fields=[(2<<60)|(1<<37)|(j<<42)|(int(j==3)<<36)|(j<<47) for j in range(4)];word=sum(x<<(64*j) for j,x in enumerate(fields));caps=[1]*20;cursor=0
        for j in range(4):
            x=self.choose(word,sum((100+k)<<(64*k) for k in range(4)),caps,cursor=cursor,response=True,auth=True)
            self.assertEqual((x['word'],x['tags'],x['fields']), (fields[j]<<(64*j),100+j,1));self.assertEqual(x['end'],2*(j+1));cursor=x['end']
    def test_individual_oversize_is_not_split(self):
        word=(2<<60)|(1<<37)|(2<<44);x=self.choose(word,0,[1]*20,response=True)
        self.assertTrue(x['shortfall']);self.assertFalse(x['valid'])
    def test_shared_pool_uses_merged_response_data(self):
        word=(2<<60)|(1<<37)|(1<<46);caps=[1]*20;caps[15]=0
        self.assertTrue(self.choose(word,0,caps,response=True,shared=True)['valid']);self.assertFalse(self.choose(word,0,caps,response=True)['valid'])
    def test_wrong_class_and_nonzero_fc_rejected(self):
        word=(2<<60)|(1<<37)
        self.assertTrue(self.choose(word,0,[8]*20,response=False)['error']);self.assertTrue(self.choose(word|(1<<64),0,[8]*20,response=True)['error'])
    def test_auth_limits_eight_response_tags(self):
        word=sum(((5<<28)|(j<<15))<<(32*j) for j in range(8));tags=sum((j+1)<<(64*j) for j in range(8));x=self.choose(word,tags,[8]*20,response=True,auth=True)
        self.assertEqual((x['end'],x['fields'],x['tags']),(4,4,tags&((1<<256)-1)))
        y=self.choose(word,tags,[8]*20,cursor=4,response=True,auth=True);self.assertEqual((y['end'],y['fields'],y['tags']),(8,4,tags>>256))
if __name__=='__main__':unittest.main()
