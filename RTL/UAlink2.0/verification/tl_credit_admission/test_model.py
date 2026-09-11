"""Run: python3 verification/tl_credit_admission/test_model.py.
Outputs unittest results; next compare the actual RTL with these field fixtures.
"""
from pathlib import Path
import sys, unittest
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'model/tl'))
from credit_admission import requirements, admit

def fixtures():
    # Literal protocol fields, expected resources follow beat count, not a decoder.
    yield 0,(0,)*20
    for kind in range(1,6):
        sectors=(4,2,2,1,1)[kind-1]
        for start in range(0,8,sectors):
            for lane in range(5):
                vc=max(0,lane-1);pool=int(lane==0)
                for beats in range(1,5):
                    if kind==4 and beats!=1:continue
                    for be in ((0,1) if kind in (1,3) else (0,)):
                        if kind==1:field=(1<<124)|((0x26 if be else 0x23)<<118)|(vc<<116)|(pool<<102)|(beats-1)
                        elif kind==2:field=(2<<60)|(vc<<58)|(pool<<46)|((beats-1)<<44)|(1<<37)
                        elif kind==3:field=(3<<60)|((3 if be else 5)<<57)|(vc<<55)|(pool<<41)|((beats-1)<<39)
                        elif kind==4:field=(4<<28)|(vc<<26)|(pool<<14)
                        else:field=(5<<28)|(vc<<26)|(pool<<14)|((beats-1)<<2)|2
                        d=[0]*20;role=0 if kind in (1,3) else 1;d[5*role+lane]=1;d[10+5*role+lane]=beats
                        yield field<<(start*32),tuple(d)
    f=(5<<28)|(1<<14)|(3<<2)|2;d=[0]*20;d[5]=8;d[15]=32
    yield sum(f<<(32*j) for j in range(8)),tuple(d)
    req=(1<<124)|(0x23<<118)|(1<<102)|3;rsp=(2<<60)|(1<<46)|(3<<44)|(1<<37)
    d=[0]*20;d[0]=1;d[5]=2;d[10]=4;d[15]=8
    yield req|(rsp<<128)|(rsp<<192),tuple(d)

class TestAdmission(unittest.TestCase):
    def test_all_fields_and_shared_counts(self):
        for word,expected in fixtures():
            for shared in (False,True):
                d=list(expected)
                if shared:d[10]+=d[15];d[15]=0
                self.assertEqual(requirements(word,shared=shared),tuple(d))
    def test_wait_differs_from_insufficient_total_capacity(self):
        word=(1<<124)|(0x23<<118)|(2<<116)|2
        cap=[0]*20;cap[3]=2;cap[13]=4;available=cap.copy();available[13]=1
        self.assertEqual(admit(word,available,cap), (False,True,False))
        self.assertEqual(admit(word,cap,cap), (True,False,False))
        self.assertEqual(admit(word,available,available), (False,False,True))
    def test_fc_and_data_boundary(self):
        self.assertEqual(admit(0,[0]*20,[0]*20,done=False),(True,False,False))
        self.assertEqual(admit((1<<256)-1,[0]*20,[0]*20,control=False),(True,False,False))
    def test_invalid_and_initialization(self):
        with self.assertRaises(ValueError):requirements(6<<28)
        word=(4<<28)|(1<<14)
        self.assertEqual(admit(word,[0]*20,[0]*20,done=False),(False,True,False))

if __name__=='__main__':unittest.main()
