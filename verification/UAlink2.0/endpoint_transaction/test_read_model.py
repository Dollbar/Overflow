#!/usr/bin/env python3
"""Run: python3 [-O] verification/endpoint_transaction/test_read_model.py --label NEW --faults.

Outputs: build/verification/endpoint_transaction/NEW (snapshot, logs, result and hashes).
Next: compare actual full Read RTL and transport with these independent byte/field expectations.
"""
from dataclasses import replace
from pathlib import Path
import argparse
import hashlib
import importlib.util
import io
import itertools
import json
import re
import subprocess
import sys
import unittest
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
CANDIDATE=None
COVERAGE={}


class ReadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m=None
        if CANDIDATE and CANDIDATE.exists():
            spec=importlib.util.spec_from_file_location('read_model_candidate',CANDIDATE)
            cls.m=importlib.util.module_from_spec(spec);sys.modules[spec.name]=cls.m;spec.loader.exec_module(cls.m)

    def setUp(self):
        self.assertIsNotNone(self.m,'READ_MODEL_NOT_IMPLEMENTED')

    def request(self,**changes):
        fields=dict(port=0,tag=1024,address=60,src=513,dst=766,length=1,attr=0x81,asi=2,metadata=0x5a)
        fields.update(changes);return self.m.ReadRequest(**fields)

    def response(self,req,offset=0,last=True,**changes):
        fields=dict(port=req.port,tag=req.tag,src=req.dst,dst=req.src,data=0,status=0,offset=offset,last=last)
        fields.update(changes);return self.m.ReadResponse(**fields)

    def collector(self,requests):
        c=self.m.ReadCollector(local_id=requests[0].src,capacity=len(requests),num_ports=4)
        for req in requests:c.reserve(req);c.mark_sent(req.port,req.tag)
        return c

    @staticmethod
    def bytes_selected(req):
        # Enumerate actual DWORDs and natural byte positions; no model mask helper.
        result=[]
        for dw in range(req.length+1):
            for lane in range(4):
                nibble=req.attr&15 if dw==0 else req.attr>>4 if dw==req.length else 15
                if nibble&(1<<lane):result.append(req.address+4*dw+lane)
        return result

    def test_00_fixed_request_words(self):
        cases=[(self.request(address=0,length=0,tag=0,src=0,dst=0,attr=0,asi=0,metadata=0),'10c00000000000000000000000000000'),
               (self.request(address=(1<<57)-64,length=15,tag=2047,src=1023,dst=1022,attr=0xa5,asi=3,metadata=0xd3),'10cfffa94fd3ffffffffffffe1ffffc0'),
               (self.request(src=1,dst=2),'10ca0020415a0000000000001e008040')]
        for req,raw in cases:
            self.assertEqual(self.m.encode_read(req),int(raw,16))
            self.assertEqual(self.m.decode_read(int(raw,16),port=req.port),req)
        raw=int(cases[-1][1],16)
        self.assertEqual(self.m.decode_read(raw|12,port=0),cases[-1][0])
        for bad in [raw|1,raw|2,raw|16,raw^(1<<118),raw^(1<<124),-1,1<<128]:
            with self.assertRaises(ValueError):self.m.decode_read(bad,port=0)

    def test_01_masks_single_dw_and_natural_lanes(self):
        for req,region,relative,n in [(self.request(address=252,length=0,attr=0xf5),5<<252,5<<60,1),
                                    (self.request(address=60,length=1,attr=0x81),(1<<60)|(1<<67),(1<<60)|(1<<67),2),
                                    (self.request(address=188,length=1,attr=0x18),(1<<191)|(1<<192),(1<<63)|(1<<64),2),
                                    (self.request(address=128,length=2,attr=0),15<<132,15<<4,1),
                                    (self.request(address=0,length=63,attr=255),(1<<256)-1,(1<<256)-1,4)]:
            mask=self.m.byte_masks(req);self.assertEqual((mask.region,mask.relative,mask.beats),(region,relative,n))
        for high in range(16):self.assertEqual(self.m.byte_masks(self.request(address=252,length=0,attr=high<<4)).relative,0)

    def test_02_request_validation(self):
        req=self.request()
        for kw in [dict(address=61),dict(address=252,length=1),dict(address=1<<57),dict(address=-4),dict(length=64),dict(tag=True),dict(tag=2048),dict(src=1024),dict(dst=-1),dict(attr=256),dict(asi=4),dict(metadata=256),dict(port=4),dict(pool=1),dict(pool=True),dict(vc=1)]:
            with self.assertRaises((ValueError,TypeError)):self.m.validate_read(replace(req,**kw))
        self.m.validate_read(self.request(address=252,length=0,attr=0,asi=3,metadata=255))
        self.m.validate_read(self.request(address=(1<<57)-256,length=63))

    def test_03_memory_and_masked_completion(self):
        raw=bytes((x*13+(x//7)*19+23)&255 for x in range(1024))
        geometries=[(0,0),(60,1),(124,1),(188,1),(252,0),(4,62),(0,63),(64,47),(128,31),(192,15)]
        count=0
        for high in (0,1<<56):
            memory=self.m.ByteMemory(raw,base_address=high)
            for start,length in geometries:
                for attr in (0,1,0x81,0x18,0x5a,0xff):
                    req=self.request(address=high+start,length=length,attr=attr)
                    result=self.m.memory_read(req,memory)
                    blocks=sorted({a//64 for a in range(req.address,req.address+4*(length+1))})
                    self.assertEqual(len(result.responses),len(blocks));self.assertEqual(result.memory.executions,1);self.assertEqual(memory.executions,0);self.assertEqual(result.memory.data,raw)
                    c=self.collector([req]);selected=set(self.bytes_selected(req));expected=bytearray(len(blocks)*64)
                    for j,block in enumerate(blocks):
                        rsp=result.responses[j]
                        self.assertEqual((rsp.offset,rsp.last,rsp.num_beats,rsp.status),(j,j==len(blocks)-1,0,0))
                        self.assertEqual(rsp.data,int.from_bytes(raw[block*64-high:block*64-high+64],'little'))
                        for lane in range(64):
                            addr=block*64+lane
                            if addr in selected:expected[j*64+lane]=raw[addr-high]
                        c.receive(rsp)
                        if j+1<len(blocks):self.assertIsNone(c.peek(req.port,req.tag))
                    completion=c.peek(req.port,req.tag)
                    self.assertEqual(completion.data,int.from_bytes(expected,'little'))
                    self.assertEqual(completion.requested_mask,sum(1<<(a-blocks[0]*64) for a in selected))
                    self.assertEqual(completion.valid_mask,completion.requested_mask);self.assertEqual(completion.poison_mask,0)
                    self.assertEqual(c.occupancy,1);self.assertEqual(c.retire(req.port,req.tag),completion);self.assertEqual(c.occupancy,0);count+=1
        COVERAGE['memory_cases']=count

    def test_04_errors_all_beats_and_poison(self):
        for n in range(1,5):
            for status in (0,2,3,6,8):
                req=self.request(address=0,length=n*16-1,attr=255)
                for pattern in (0,255):
                    result=self.m.memory_read(req,self.m.ByteMemory(bytes(range(256))),status=status,error_pattern=pattern)
                    self.assertEqual(len(result.responses),n);c=self.collector([req])
                    for j,rsp in enumerate(result.responses):
                        self.assertEqual(rsp.status,status)
                        if status:self.assertEqual(rsp.data,int.from_bytes(bytes([pattern])*64,'little'))
                        try:c.receive(rsp)
                        except ValueError as exc:self.fail("legal error stream rejected: "+str(exc))
                        if j<n-1:self.assertIsNone(c.peek(0,req.tag))
                    completion=c.peek(0,req.tag)
                    self.assertEqual(completion.status,status)
                    if status:self.assertEqual((completion.data,completion.valid_mask),(0,0))
        req=self.request();c=self.collector([req]);c.receive(self.response(req,0,False,data_error=True));self.assertIsNone(c.peek(0,req.tag));c.receive(self.response(req,1,True))
        done=c.peek(0,req.tag);self.assertEqual((done.poison_mask,done.data,done.valid_mask),(1,0,0))
        miss=self.m.memory_read(self.request(address=(1<<56)+60),self.m.ByteMemory(b'\0'*256));self.assertEqual([r.status for r in miss.responses],[3,3])

    def test_05_single_permutations_cross_tag_and_hold(self):
        reqs=[self.request(address=0,length=63,tag=1024),self.request(address=64,length=31,tag=2047),self.request(address=188,length=1,tag=1024,port=1)]
        for order in itertools.permutations(range(4)):
            c=self.collector(reqs)
            for j,offset in enumerate(order):
                c.receive(self.response(reqs[0],offset,j==3,data=offset+1,src=0))
                if j<2:
                    c.receive(self.response(reqs[1],1-j,j==1,data=0x10+j))
                    c.receive(self.response(reqs[2],1-j,j==1,data=0x20+j))
                if j<3:self.assertIsNone(c.peek(0,1024))
            self.assertEqual(c.occupancy,3);saved=c.peek(0,1024)
            for _ in range(4):self.assertEqual(c.peek(0,1024),saved)
            with self.assertRaises(ValueError):c.reserve(reqs[0])
            for req in reqs:c.retire(req.port,req.tag)
            self.assertEqual(c.occupancy,0);c.reserve(reqs[0])
        COVERAGE['single_four_beat_permutations']=24

    def test_06_multi_sequence_and_burst_decode(self):
        for n in (2,3,4):
            req=self.request(address=0,length=16*n-1)
            for status in (0,2,3,6,8):
                c=self.collector([req])
                for offset in range(n):
                    c.receive(self.response(req,offset,offset==n-1,num_beats=n-1,status=status,data=offset+31))
                    self.assertEqual(c.peek(0,req.tag) is not None,offset==n-1)
            # Multi Header OFFSET is invalid and Header LAST has an unresolved UPLI reduction.
            # Decoder reconstructs event offsets/last from its complete TL Data tenure.
            for raw_offset in range(4):
                for raw_last in (0,1):
                    word=int('2200002000000000',16)|((n-1)<<44)|(raw_offset<<42)|(raw_last<<36)|(766<<26)|(513<<16)
                    events=self.m.decode_response_burst(word,port=0,data_beats=tuple(range(n)))
                    self.assertEqual([(e.offset,e.last,e.num_beats) for e in events],[(k,k==n-1,n-1) for k in range(n)])
                    c=self.collector([req])
                    for event in events:c.receive(event)
                    self.assertIsNotNone(c.peek(0,req.tag))
                    with self.assertRaises(ValueError):self.m.decode_response_burst(word,port=0,data_beats=(0,))

    def test_07_invalid_response_atomicity(self):
        req=self.request(address=0,length=63);other=self.request(address=0,length=63,tag=2047)
        c=self.collector([req,other]);first=self.response(req,0,False)
        invalid=[replace(first,last=True),replace(first,status=1),replace(first,offset=3,num_beats=3),replace(first,num_beats=1),replace(first,dst=0),replace(first,tag=0),replace(first,data=-1),replace(first,data=1<<512),replace(first,data_error=1),replace(first,pool=True),replace(first,vc=1),replace(first,rsp_type=2)]
        for rsp in invalid:
            with self.assertRaises((ValueError,TypeError)):c.receive(rsp)
            self.assertIsNone(c.peek(0,req.tag));self.assertEqual(c.occupancy,2)
        c.receive(first)
        for rsp in [first,replace(first,offset=1,status=3),replace(first,offset=1,num_beats=3)]:
            with self.assertRaises(ValueError):c.receive(rsp)
        for offset in (1,2):c.receive(self.response(req,offset,False))
        with self.assertRaises(ValueError):c.receive(self.response(req,3,False))
        c.receive(self.response(req,3,True));saved=c.peek(0,req.tag)
        with self.assertRaises(ValueError):c.receive(self.response(req,3,True))
        self.assertEqual(c.peek(0,req.tag),saved)
        # A multi-Beat burst cannot be interleaved on the same port.
        m=self.collector([req,other]);m.receive(self.response(req,0,False,num_beats=3))
        with self.assertRaises(ValueError):m.receive(self.response(other,0,False))
        with self.assertRaises(ValueError):m.receive(self.response(req,2,False,num_beats=3))
        for offset in (1,2,3):m.receive(self.response(req,offset,offset==3,num_beats=3))
        m.receive(self.response(other,0,False))

    def test_07a_fixed_response_words_and_validation(self):
        words={0:'23ff8c2ffffe0000',2:'23ff8caffffe0000',3:'23ff8ceffffe0000',6:'23ff8daffffe0000',8:'23ff8e2ffffe0000'}
        for status,raw in words.items():
            event=self.m.ReadResponse(port=3,tag=2047,src=1023,dst=1022,data=123,status=status,offset=3,last=False)
            self.assertEqual(self.m.encode_response(event),int(raw,16))
            self.assertEqual(self.m.decode_response_burst(int(raw,16)|0x3fff,port=3,data_beats=(123,)),(event,))
        event=self.m.ReadResponse(port=0,tag=0,src=0,dst=0,data=0)
        for status in range(16):
            if status not in words:
                with self.assertRaises(ValueError):self.m.validate_response(replace(event,status=status))
        for raw in [int(words[0],16)^(1<<37),int(words[0],16)|(1<<14),int(words[0],16)|(1<<58),int(words[0],16)|(1<<46),1<<64,-1]:
            with self.assertRaises(ValueError):self.m.decode_response_burst(raw,port=0,data_beats=(0,))
        for values in [(0,0),(),[0],(-1,),(1<<512,)]:
            with self.assertRaises((ValueError,TypeError)):self.m.decode_response_burst(int(words[0],16),port=0,data_beats=values)
        with self.assertRaises(ValueError):self.m.encode_response(replace(event,num_beats=1))
        for changes in [dict(offset=4),dict(num_beats=4),dict(dst=1024),dict(last=1),dict(status=True),dict(port=-1)]:
            with self.assertRaises((ValueError,TypeError)):self.m.validate_response(replace(event,**changes))

    def test_08_ownership_and_reset(self):
        req=self.request();c=self.m.ReadCollector(local_id=req.src,capacity=1,num_ports=1)
        with self.assertRaises(ValueError):c.receive(self.response(req,0,False))
        c.reserve(req)
        with self.assertRaises(ValueError):c.receive(self.response(req,0,False))
        with self.assertRaises(ValueError):c.reserve(replace(req,tag=7))
        with self.assertRaises(ValueError):c.retire(0,req.tag)
        c.mark_sent(0,req.tag)
        with self.assertRaises(ValueError):c.mark_sent(0,req.tag)
        c.receive(self.response(req,0,False));c.reset();self.assertEqual(c.occupancy,0)
        with self.assertRaises(ValueError):c.receive(self.response(req,1,True))
        c.reserve(req);c.mark_sent(0,req.tag);c.receive(self.response(req,1,False));c.receive(self.response(req,0,True));c.retire(0,req.tag)
        for kwargs in [dict(capacity=0),dict(num_ports=0),dict(local_id=1024)]:
            args=dict(local_id=513,capacity=4,num_ports=4);args.update(kwargs)
            with self.assertRaises((ValueError,TypeError)):self.m.ReadCollector(**args)

    def test_09_all_geometry_all_attributes(self):
        good=bad=checks=0
        for start in range(0,256,4):
            for length in range(64):
                req=self.request(address=start,length=length)
                if start+4*(length+1)>256:
                    with self.assertRaises(ValueError):self.m.validate_read(req)
                    bad+=1;continue
                good+=1
                # Independently enumerate byte positions once, then select each nibble's bytes.
                first=[sum(1<<a for a in range(start,start+4) if nibble&(1<<(a%4))) for nibble in range(16)]
                last=[sum(1<<a for a in range(start+4*length,start+4*length+4) if nibble&(1<<(a%4))) for nibble in range(16)]
                middle=sum(1<<a for a in range(start+4,start+4*length))
                blocks=sorted({a//64 for a in range(start,start+4*(length+1))})
                for attr in range(256):
                    actual=self.m.byte_masks(replace(req,attr=attr))
                    expected=first[attr%16] if length==0 else first[attr%16]|last[attr//16]|middle
                    self.assertEqual(actual.region,expected)
                    self.assertEqual(actual.relative,expected//(1<<(blocks[0]*64)))
                    self.assertEqual(actual.beats,len(blocks));checks+=1
        self.assertEqual((good,bad,checks),(2080,2016,532480))
        COVERAGE.update(legal_geometries=good,illegal_geometries=bad,geometry_attribute_masks=checks)


def main():
    global CANDIDATE
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--faults',action='store_true');p.add_argument('--candidate',type=Path);p.add_argument('--case')
    a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe new label required')
    stage=ROOT/'build/verification/endpoint_transaction'/a.label;stage.mkdir(parents=True,exist_ok=False)
    runner=Path(__file__).read_bytes();(stage/'test_read_model.py').write_bytes(runner)
    source=a.candidate or ROOT/'model/ualink/endpoint_read.py';data=source.read_bytes() if source.exists() else None
    CANDIDATE=stage/'model.py'
    if data is not None:CANDIDATE.write_bytes(data)
    suite=unittest.defaultTestLoader.loadTestsFromName(a.case,ReadTests) if a.case else unittest.defaultTestLoader.loadTestsFromTestCase(ReadTests)
    stream=io.StringIO();result=unittest.TextTestRunner(stream=stream,verbosity=2).run(suite);(stage/'tests.log').write_text(stream.getvalue())
    report=dict(passed=result.wasSuccessful(),tests=result.testsRun,failures=len(result.failures),errors=len(result.errors),optimized=sys.flags.optimize,source_sha256=hashlib.sha256(data).hexdigest() if data is not None else None,coverage=COVERAGE,mutations=[])
    if a.faults and data is not None:
        mutations={
         'len0_high':('first=request.attr & 15','first=(request.attr & 15) & (request.attr >> 4)','test_01_masks_single_dw_and_natural_lanes'),
         'compress_lanes':('byte=memory.data[address-memory.base_address]','byte=memory.data[(request.address+lane)-memory.base_address] if 0 <= request.address+lane-memory.base_address < len(memory.data) else 0','test_03_memory_and_masked_completion'),
         'early_error':('done=len(seen)==mask.beats','done=(response.status != 0) or len(seen)==mask.beats','test_04_errors_all_beats_and_poison'),
         'duplicate':("if response.offset in state['seen']:","if False and response.offset in state['seen']:",'test_07_invalid_response_atomicity'),
        }
        for name,(before,after,case) in mutations.items():
            text=data.decode()
            if text.count(before)!=1:raise ValueError('mutation anchor missing/ambiguous: '+name)
            mutant=stage/(name+'.py');mutant.write_text(text.replace(before,after))
            label=a.label+'_'+name;cmd=[sys.executable,*(['-O'] if sys.flags.optimize else []),str(Path(__file__).resolve()),'--label',label,'--candidate',str(mutant),'--case',case]
            proc=subprocess.run(cmd,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=120);(stage/(name+'.log')).write_text(proc.stdout)
            child=json.loads((ROOT/'build/verification/endpoint_transaction'/label/'result.json').read_text())
            detected=proc.returncode==1 and child['failures']>0 and child['errors']==0
            report['mutations'].append(dict(name=name,detected=detected,returncode=proc.returncode,source_sha256=hashlib.sha256(mutant.read_bytes()).hexdigest(),command=cmd));report['passed']=report['passed'] and detected
    report['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(report,indent=2)+'\n');print(stream.getvalue(),end='');print('PASS' if report['passed'] else 'FAIL',stage/'result.json');return 0 if report['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
