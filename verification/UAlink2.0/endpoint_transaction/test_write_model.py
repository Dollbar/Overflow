"""Run: python3 [-O] verification/endpoint_transaction/test_write_model.py --label NAME.

Writes a fresh build/verification/endpoint_transaction/NAME evidence directory.
Next: compare typed RTL with these literal fields and independent byte expectations.
The oracle never calls a model encoder to calculate its expected memory or words.
"""
from dataclasses import replace
from pathlib import Path
import argparse
import hashlib
import importlib
import importlib.util
import io
import json
import re
import subprocess
import sys
import unittest

ROOT = (lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
sys.path.insert(0, str(ROOT / 'model'))
MODEL_PATH = None


class WriteTests(unittest.TestCase):
    def setUp(self):
        name = 'ualink.endpoint_write'
        spec = importlib.util.spec_from_file_location(name, MODEL_PATH) if MODEL_PATH else importlib.util.find_spec(name)
        self.assertIsNotNone(spec, 'independent Write model is not implemented')
        if MODEL_PATH:
            self.m = importlib.util.module_from_spec(spec)
            sys.modules[name] = self.m
            spec.loader.exec_module(self.m)
        else:
            self.m = importlib.import_module(name)

    def request(self, address=0, length=15, **kw):
        # Oracle counts touched 64-byte regions by enumeration, not model geometry.
        blocks = sorted({a // 64 for a in range(address, address + 4 * (length + 1))})
        data = tuple(int.from_bytes(bytes((j * 73 + k * 19 + 7) % 256 for k in range(64)), 'little') for j in range(len(blocks)))
        mask = sum(1 << (a % 256) for a in range(address, address + 4 * (length + 1)))
        args = dict(port=0, tag=17, address=address, src=1, dst=2, length=length, data_beats=data, byte_enable=mask)
        args.update(kw)
        return self.m.WriteRequest(**args)

    def test_fixed_request_words_and_high_fields(self):
        # Fixed binary-concatenation worksheet, not model roundtrip expectations.
        cases = [(self.request(length=0, tag=0, src=0, dst=0), '1a000000000000000000000000000000'),
                 (self.request(address=(1 << 57)-64, tag=2047, src=1023, dst=1022, full=True, attr=0xa5, asi=3, metadata=0xd3), '1a4fffa94fd3ffffffffffffe1ffffc0'),
                 (self.request(address=60, length=1, tag=1024, attr=0x81, asi=2, metadata=0x5a), '1a0a0020415a0000000000001e008041')]
        for req, raw in cases:
            with self.subTest(raw=raw):
                self.assertEqual(self.m.encode_write(req), int(raw, 16))
                got = self.m.decode_write(int(raw, 16), port=req.port, data_beats=req.data_beats, byte_enable=req.byte_enable)
                self.assertEqual(got, req)

    def test_all_4096_geometry_combinations(self):
        good = bad = 0
        for offset in range(0, 256, 4):
            for length in range(64):
                req = self.request(address=offset, length=length)
                if offset + 4*(length+1) > 256:
                    with self.assertRaises(ValueError): self.m.validate_write(req)
                    bad += 1
                else:
                    self.m.validate_write(req)
                    blocks = {a//64 for a in range(offset, offset+4*(length+1))}
                    self.assertEqual(self.m.encode_write(req) & 3, len(blocks)-1)
                    good += 1
        self.assertEqual((good,bad), (2080,2016))

    def test_full_ten_legal_and_adjacent_illegal(self):
        count = 0
        for offset in range(0,256,4):
            for length in range(64):
                req = self.request(address=offset,length=length,full=True,byte_enable=0)
                legal = offset % 64 == 0 and length in (15,31,47,63) and offset + (length+1)*4 <= 256
                if legal:
                    self.m.validate_write(req)
                    expected = sum(1 << a for a in range(offset,offset+(length+1)*4))
                    self.assertEqual(self.m.effective_byte_enable(req),expected)
                    self.assertEqual(len(self.m.data_halves(req)),len(req.data_beats)*2)
                    count += 1
                else:
                    with self.assertRaises(ValueError): self.m.validate_write(req)
        self.assertEqual(count,10)

    def test_data_tuple_and_region_be_mapping(self):
        for addr,length in [(60,1),(124,1),(188,1),(128,15),(192,15),(4,62),(0,63)]:
            req=self.request(address=addr,length=length)
            halves=self.m.data_halves(req)
            self.assertEqual(halves[-1],sum(1 << a for a in range(addr,addr+4*(length+1))))
            for j,beat in enumerate(req.data_beats):
                raw=beat.to_bytes(64,'little')
                self.assertEqual(halves[2*j],int.from_bytes(raw[:32],'little'))
                self.assertEqual(halves[2*j+1],int.from_bytes(raw[32:],'little'))
            self.assertEqual(len(halves),2*len(req.data_beats)+1)

    def test_invalid_data_be_and_python_types(self):
        req=self.request(address=60,length=1)
        mutations=[dict(data_beats=(0,)),dict(data_beats=(0,0,0)),dict(data_beats=[0,0]),
                   dict(data_beats=(-1,0)),dict(data_beats=(1<<512,0)),dict(byte_enable=1<<256),
                   dict(byte_enable=1),dict(address=61),dict(length=64),dict(tag=2048),
                   dict(src=1024),dict(dst=-1),dict(port=4),dict(address=1<<57),
                   dict(attr=256),dict(asi=4),dict(metadata=256),dict(vc=1),dict(pool=True),
                   dict(full=1),dict(tag=True)]
        for changes in mutations:
            with self.subTest(changes=changes):
                with self.assertRaises((ValueError,TypeError)): self.m.validate_write(replace(req,**changes))

    def test_request_decode_rejects_command_cache_and_count(self):
        req=self.request(address=60,length=1)
        raw=int('1a0a0020415a0000000000001e008041',16)
        for word in [raw^(1<<118),raw|(1<<4),raw^1,raw|(1<<128),-1]:
            with self.assertRaises(ValueError): self.m.decode_write(word,port=0,data_beats=req.data_beats,byte_enable=req.byte_enable)
        got=self.m.decode_write(raw|12,port=0,data_beats=req.data_beats,byte_enable=req.byte_enable)
        self.assertEqual((got.address,got.tag,got.asi,got.metadata),(60,1024,2,90))

    def test_response_five_literals_and_invalid_statuses(self):
        words={0:'23ff800ffffe0000',2:'23ff808ffffe0000',3:'23ff80cffffe0000',6:'23ff818ffffe0000',8:'23ff820ffffe0000'}
        for status in range(16):
            rsp=self.m.WriteResponse(port=0,tag=2047,src=1023,dst=1022,status=status)
            if status in words:
                self.assertEqual(self.m.encode_response(rsp),int(words[status],16))
                self.assertEqual(self.m.decode_response(int(words[status],16),port=0),rsp)
            else:
                with self.assertRaises(ValueError):self.m.validate_response(rsp)
                with self.assertRaises(ValueError):self.m.decode_response(int(words[0],16)|(status<<38),port=0)

    def test_response_unused_fields_and_wrong_kind(self):
        raw=int('23ff800ffffe0000',16)
        for offset in range(4):
            for last in (False,True):
                rsp=self.m.decode_response(raw|(offset<<42)|(int(last)<<36)|0x3fff,port=0)
                self.assertEqual((rsp.offset,rsp.last,rsp.status),(offset,last,0))
                self.assertEqual(self.m.encode_response(rsp),raw)
        for word in [raw|(1<<37),raw|(1<<44),raw|(1<<14),raw|(1<<58),raw|(1<<46),raw|(1<<64),-1]:
            with self.assertRaises(ValueError):self.m.decode_response(word,port=0)
        for changes in [dict(data_error=True),dict(tag=2048),dict(status=-1),dict(pool=True),dict(last=1)]:
            with self.assertRaises((ValueError,TypeError)):
                self.m.validate_response(replace(self.m.WriteResponse(port=0,tag=0,src=0,dst=0),**changes))

    def test_immutable_byte_oracle_all_legal_geometry_and_masks(self):
        original=bytes((a*11+3)%256 for a in range(256))
        for offset in range(0,256,4):
            for length in range(64):
                end=offset+4*(length+1)
                if end>256:continue
                for pattern in (0,1,2,3):
                    enabled=[a for a in range(offset,end) if pattern==1 or (pattern==2 and a%2==0) or (pattern==3 and a in (offset,end-1))]
                    req=self.request(address=offset,length=length,byte_enable=sum(1<<a for a in enabled))
                    old=self.m.ByteMemory(original)
                    result=self.m.memory_write(req,old)
                    expected=bytearray(original)
                    for a in enabled:
                        j=a//64-offset//64; lane=a%64
                        expected[a]=req.data_beats[j].to_bytes(64,'little')[lane]
                    self.assertEqual(result.memory.data,bytes(expected))
                    self.assertEqual(old.data,original)
                    self.assertEqual((old.executions,result.memory.executions),(0,1))
                    self.assertEqual((result.response.tag,result.response.src,result.response.dst,result.response.status),(17,2,1,0))

    def test_full_reconstructs_be_and_high_memory_base(self):
        base=(1<<57)-256
        for addr,length in [(base+128,31),(base+192,15)]:
            req=self.request(address=addr,length=length,full=True,byte_enable=0)
            result=self.m.memory_write(req,self.m.ByteMemory(bytes(256),base_address=base))
            expected=bytearray(256)
            for j,beat in enumerate(req.data_beats):expected[addr-base+j*64:addr-base+(j+1)*64]=beat.to_bytes(64,'little')
            self.assertEqual(result.memory.data,bytes(expected))

    def test_memory_error_has_no_update_and_counts_attempt(self):
        old=self.m.ByteMemory(bytes([93])*128)
        for status in (2,3,6,8):
            result=self.m.memory_write(self.request(),old,status=status)
            self.assertEqual((result.memory.data,result.memory.executions,result.response.status),(old.data,1,status))
        result=self.m.memory_write(self.request(address=128),old)
        self.assertEqual((result.memory.data,result.response.status),(old.data,3))
        with self.assertRaises(ValueError):self.m.memory_write(self.request(),old,status=1)
        with self.assertRaises(TypeError):self.m.ByteMemory(bytearray(256))

    def test_backend_accept_result_and_completion_are_separate(self):
        b=self.m.WriteBackend(self.m.ByteMemory(bytes(256)),local_id=2,capacity=2)
        req=self.request()
        b.accept(4,req); b.accept(9,self.request(address=64,tag=18))
        self.assertEqual(b.memory.executions,0)
        self.assertIsNone(b.peek_response(4))
        with self.assertRaises(ValueError):b.accept(10,req)
        with self.assertRaises(ValueError):b.finish(99)
        with self.assertRaises(ValueError):b.finish(4,status=1)
        self.assertEqual(b.memory.executions,0)
        b.finish(9); self.assertIsNone(b.peek_response(4))
        self.assertEqual(b.peek_response(9).tag,18)
        b.finish(4)
        self.assertEqual(b.memory.executions,2)
        with self.assertRaises(ValueError):b.finish(4)
        with self.assertRaises(ValueError):b.accept(4,req)
        self.assertEqual(b.retire_response(4).tag,17)
        b.accept(4,replace(req,byte_enable=0));b.finish(4)
        self.assertEqual(b.memory.executions,3)

    def test_backend_invalid_destination_has_no_allocation(self):
        b=self.m.WriteBackend(self.m.ByteMemory(bytes(256)),local_id=2,capacity=1)
        with self.assertRaises(ValueError):b.accept(0,self.request(dst=3))
        b.accept(0,self.request())
        with self.assertRaises(ValueError):b.retire_response(0)
        b.finish(0,status=6)
        self.assertEqual(b.retire_response(0).status,6)

    def test_shared_read_write_tags_conflict_kind_and_retirement(self):
        tags=self.m.ReadWriteTags(local_id=1,capacity=3,num_ports=2)
        tags.reserve(0,2047,'read')
        with self.assertRaises(ValueError):tags.reserve(0,2047,'write')
        tags.reserve(1,2047,'write')
        with self.assertRaises(ValueError):tags.receive(1,2047,'write',0,1)
        tags.mark_sent(1,2047)
        for args in [(1,2047,'read',0,1),(1,2047,'write',0,2),(1,2046,'write',0,1),(1,2047,'write',1,1)]:
            with self.assertRaises(ValueError):tags.receive(*args)
        self.assertIsNone(tags.peek(1,2047))
        tags.receive(1,2047,'write',8,1)
        with self.assertRaises(ValueError):tags.receive(1,2047,'write',8,1)
        with self.assertRaises(ValueError):tags.reserve(1,2047,'write')
        self.assertEqual((tags.retire(1,2047).kind,tags.occupancy),('write',1))
        tags.reserve(1,2047,'write')
        tags.mark_sent(0,2047);tags.receive(0,2047,'read',3,1)
        self.assertEqual(tags.retire(0,2047).status,3)

    def test_tag_capacity_width_and_invalid_events(self):
        for kwargs in [dict(capacity=0),dict(num_ports=3),dict(local_id=1024)]:
            with self.assertRaises(ValueError):self.m.ReadWriteTags(**(dict(local_id=1)|kwargs))
        tags=self.m.ReadWriteTags(local_id=1,capacity=1)
        for args in [(1,1,'write'),(0,2048,'write'),(0,1,'atomic')]:
            with self.assertRaises(ValueError):tags.reserve(*args)
        with self.assertRaises(ValueError):tags.mark_sent(0,1)
        tags.reserve(0,1,'write')
        with self.assertRaises(ValueError):tags.reserve(0,2,'read')
        with self.assertRaises(ValueError):tags.retire(0,1)
        tags.mark_sent(0,1)
        with self.assertRaises(ValueError):tags.mark_sent(0,1)


def main():
    global MODEL_PATH
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--label');p.add_argument('--model-path',type=Path)
    p.add_argument('--faults',action='store_true',help='rerun four actual model-source mutations in isolated evidence files')
    args=p.parse_args();MODEL_PATH=args.model_path
    if args.faults and (not args.label or args.model_path):p.error('--faults requires --label and no --model-path')
    folder=None
    if args.label:
        if not re.fullmatch(r'[A-Za-z0-9_-]+',args.label):p.error('unsafe label')
        folder=ROOT/'build/verification/endpoint_transaction'/args.label
        folder.mkdir(parents=True,exist_ok=False)
    stream=io.StringIO()
    result=unittest.TextTestRunner(stream=stream,verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(WriteTests))
    log=stream.getvalue();print(log,end='')
    mutation_results=[]
    if args.faults and result.wasSuccessful():
        source=(ROOT/'model/ualink/endpoint_write.py').read_text()
        mutations={
            'wrong_command':('0x29 if request.full else 0x28','0x29 if request.full else 0x26'),
            'beat_count_ignores_offset':('((request.address & 63) + 4*(request.length+1) + 63)//64','(4*(request.length+1) + 63)//64'),
            'mask_ignored':('if mask&(1<<(address-region_base)):','if True:'),
            'wrong_response_kind_accepted':('if kind!=expected or not sent or completion is not None or dst!=self.local_id:',
                                            'if not sent or completion is not None or dst!=self.local_id:')}
        mutations_dir=folder/'mutations';mutations_dir.mkdir()
        for name,(old,new) in mutations.items():
            if source.count(old)!=1:raise RuntimeError('mutation target missing or ambiguous: '+name)
            mutated=mutations_dir/(name+'.py');mutated.write_text(source.replace(old,new))
            label=args.label+'_fault_'+name
            command=[sys.executable]+(['-O'] if not __debug__ else [])+[str(Path(__file__).resolve()),'--label',label,'--model-path',str(mutated)]
            child=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=60)
            (mutations_dir/(name+'.log')).write_text(child.stdout)
            report=json.loads((folder.parent/label/'result.json').read_text())
            mutation_results.append(dict(name=name,rejected=child.returncode==1 and not report['passed'],
                                         exit_code=child.returncode,failures=report['failures'],errors=report['errors'],
                                         source_sha256=hashlib.sha256(mutated.read_bytes()).hexdigest()))
        print(json.dumps({'mutations':mutation_results},indent=2))
    success=result.wasSuccessful() and all(m['rejected'] for m in mutation_results)
    if folder:
        (folder/'run.log').write_text(log)
        sources={}
        for rel in ['model/ualink/endpoint_write.py','verification/endpoint_transaction/test_write_model.py','config/endpoint_write_contract.json','docs/endpoint_write_model_review.md']:
            source=ROOT/rel
            if source.exists():
                raw=source.read_bytes();sources[rel]=hashlib.sha256(raw).hexdigest()
                dest=folder/'snapshot'/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)
        report=dict(passed=success,tests=result.testsRun,failures=len(result.failures),errors=len(result.errors),optimized=not __debug__,source_sha256=sources,
                    model_override=str(MODEL_PATH) if MODEL_PATH else None,mutations=mutation_results,
                    coverage={'normal_geometry':4096,'normal_legal':2080,'normal_illegal':2016,'full_legal':10,'byte_memory_cases':8320,'legal_write_statuses':[0,2,3,6,8]})
        if MODEL_PATH:report['model_override_sha256']=hashlib.sha256(MODEL_PATH.read_bytes()).hexdigest()
        (folder/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    return 0 if success else 1


if __name__=='__main__':sys.exit(main())
