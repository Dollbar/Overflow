"""Run: python3 [-O] verification/endpoint_transaction/test_model.py [--label NAME].
Output: unittest results; optional fresh label stores log/result/source hashes under build.
Next: compare actual RTL fields with fixed contract vectors.
Expected words below are constant Table5-29/30 field fixtures, never model round trips.
"""
from dataclasses import replace
from pathlib import Path
import argparse
import hashlib
import io
import re
import importlib
import importlib.util
import json
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'model'))


class TransactionTests(unittest.TestCase):
    def setUp(self):
        name = 'ualink.endpoint_transaction'
        self.assertIsNotNone(importlib.util.find_spec(name), 'independent Read transaction model missing')
        self.m = importlib.import_module(name)
        self.req = self.m.ReadRequest(port=0, tag=1023, address=0x12340, src=1, dst=1023)
        self.rsp = self.m.ReadResponse(port=0, tag=1023, src=1023, dst=1, data_halves=(0x123, 0x456))

    def tracker(self, **kwargs):
        return self.m.ReadTracker(local_id=1, **kwargs)

    def test_request_constant_vectors(self):
        cases = [(0, 0, 0, 0, '10c0003fcf0000000000000000000000'),
                 (2047, (1 << 57) - 64, 1023, 1022, '10c3ffbfcf00ffffffffffffe1ffffc0'),
                 (1023, 0x12340, 1, 1023, '10c1ffbfcf00000000000091a000ffe0')]
        for tag, addr, src, dst, raw in cases:
            with self.subTest(raw=raw):
                request = self.m.ReadRequest(port=0, tag=tag, address=addr, src=src, dst=dst)
                self.assertEqual(self.m.encode_read(request), int(raw, 16))
                self.assertEqual(self.m.decode_read(int(raw, 16), port=0), request)

    def test_response_constant_vectors(self):
        for tag, src, dst, status, raw in [(0,0,0,0,'2000003000000000'), (2047,1023,1022,3,'23ff80fffffe0000'), (1023,1,1023,0,'21ff803007ff0000')]:
            response = self.m.ReadResponse(port=0, tag=tag, src=src, dst=dst, status=status, data_halves=(7,9))
            self.assertEqual(self.m.encode_response(response), int(raw, 16))
            self.assertEqual(self.m.decode_response(int(raw, 16), data_halves=(7,9), port=0), response)

    def test_high_bits_have_independent_wire_positions(self):
        baseline = self.m.ReadRequest(port=0, tag=0, address=0, src=0, dst=0)
        baseline_word = int('10c0003fcf0000000000000000000000', 16)
        for field, value, expected_bit in [('tag',1024,113), ('address',1<<56,79), ('src',512,24), ('dst',512,14)]:
            self.assertEqual(self.m.encode_read(replace(baseline, **{field:value})) ^ baseline_word, 1 << expected_bit)

    def test_widths_types_and_local_profile_rejected(self):
        for field, values in {'tag':(-1,2048,True), 'address':(-1,1<<57,4,True), 'src':(-1,1024,True), 'dst':(-1,1024), 'port':(-1,4,True), 'length':(0,63), 'attr':(0,), 'vc':(1,), 'pool':(True,0), 'asi':(1,), 'metadata':(1,)}.items():
            for value in values:
                with self.subTest(field=field,value=value), self.assertRaises((TypeError,ValueError)):
                    self.m.encode_read(replace(self.req, **{field:value}))

    def test_request_fixed_fields_and_reserved_width(self):
        raw = int('10c1ffbfcf00000000000091a000ffe0',16)
        for changed in (raw ^ (1<<124), raw ^ (1<<118), raw | 1, raw | 4, raw | 16, raw | (1<<102), raw | (1<<114), raw | (1<<80), raw ^ (1<<88), -1, 1<<128):
            with self.subTest(changed=changed), self.assertRaises((TypeError,ValueError)):
                self.m.decode_read(changed, port=0)

    def test_response_requires_two_full_data_halves(self):
        for halves in ((), (1,), (1,2,3), (-1,0), (1<<256,0), (True,0), [1,2], None):
            with self.subTest(halves=halves), self.assertRaises((TypeError,ValueError)):
                self.m.decode_response(int('2000003000000000',16), data_halves=halves, port=0)

    def test_response_profile_fields_rejected(self):
        for field, value in [('num_beats',1),('offset',1),('last',False),('rsp_type',2),('status',1),('data_error',True),('vc',1),('pool',True),('tag',2048),('src',1024),('dst',1024)]:
            with self.subTest(field=field), self.assertRaises((TypeError,ValueError)):
                self.m.encode_response(replace(self.rsp, **{field:value}))
        for changed in (int('2000003000000000',16) ^ (1<<37), 1<<64, -1):
            with self.assertRaises((TypeError,ValueError)):
                self.m.decode_response(changed, data_halves=(0,0), port=0)

    def test_spare_bits_not_used_as_local_identity(self):
        raw = int('2000003000000000',16)
        a = self.m.decode_response(raw, data_halves=(0,0), port=0)
        b = self.m.decode_response(raw|0x3fff, data_halves=(0,0), port=0)
        self.assertEqual(a,b)

    def test_capacity_and_full_tag_comparison(self):
        tracker = self.tracker()
        for tag in (0,1,1023,2047):
            tracker.reserve(replace(self.req,tag=tag))
        self.assertEqual(tracker.occupancy,4)
        for tag in (1023,2):
            with self.assertRaises(ValueError):tracker.reserve(replace(self.req,tag=tag))
        self.assertEqual(tracker.occupancy,4)

    def test_no_response_or_retirement_before_send_and_receive(self):
        tracker=self.tracker();tracker.reserve(self.req)
        with self.assertRaises(ValueError):tracker.receive(self.rsp)
        with self.assertRaises(ValueError):tracker.retire(0,1023)
        self.assertIsNone(tracker.peek(0,1023))
        tracker.mark_sent(0,1023)
        with self.assertRaises(ValueError):tracker.mark_sent(0,1023)
        with self.assertRaises(ValueError):tracker.retire(0,1023)
        self.assertEqual(tracker.occupancy,1)

    def test_unknown_tag_wrong_dst_and_invalid_response_atomic(self):
        tracker=self.tracker();tracker.reserve(self.req);tracker.mark_sent(0,1023)
        for response in (replace(self.rsp,tag=2047), replace(self.rsp,dst=2), replace(self.rsp,last=False), replace(self.rsp,data_halves=())):
            with self.assertRaises((TypeError,ValueError)):tracker.receive(response)
            self.assertIsNone(tracker.peek(0,1023));self.assertEqual(tracker.occupancy,1)
        tracker.receive(self.rsp)
        self.assertEqual(tracker.peek(0,1023).data,(0x456<<256)|0x123)

    def test_debug_source_id_not_functional_match(self):
        tracker=self.tracker();tracker.reserve(self.req);tracker.mark_sent(0,1023)
        tracker.receive(replace(self.rsp,src=0))
        self.assertEqual(tracker.peek(0,1023).tag,1023)

    def test_completion_holds_capacity_duplicate_and_reuse(self):
        tracker=self.tracker(capacity=1);tracker.reserve(self.req);tracker.mark_sent(0,1023);tracker.receive(self.rsp)
        saved=tracker.peek(0,1023)
        with self.assertRaises(ValueError):tracker.reserve(self.req)
        with self.assertRaises(ValueError):tracker.receive(self.rsp)
        self.assertEqual(tracker.peek(0,1023),saved);self.assertEqual(tracker.occupancy,1)
        self.assertEqual(tracker.retire(0,1023),saved);self.assertEqual(tracker.occupancy,0)
        with self.assertRaises(ValueError):tracker.receive(self.rsp)
        with self.assertRaises(ValueError):tracker.retire(0,1023)
        tracker.reserve(self.req);self.assertEqual(tracker.occupancy,1)

    def test_error_completes_without_successful_data(self):
        tracker=self.tracker();tracker.reserve(self.req);tracker.mark_sent(0,1023)
        tracker.receive(replace(self.rsp,status=3,data_halves=((1<<256)-1,(1<<256)-1)))
        result=tracker.retire(0,1023)
        self.assertEqual(result.status,3);self.assertIsNone(result.data)

    def test_cross_port_tag_identity(self):
        tracker=self.tracker(num_ports=2)
        tracker.reserve(self.req);tracker.reserve(replace(self.req,port=1))
        tracker.mark_sent(0,1023);tracker.mark_sent(1,1023)
        tracker.receive(replace(self.rsp,port=1))
        self.assertIsNone(tracker.peek(0,1023));self.assertIsNotNone(tracker.peek(1,1023))
        with self.assertRaises(ValueError):self.tracker().reserve(replace(self.req,port=1))

    def test_tracker_configuration_and_source_identity(self):
        for kwargs in ({'local_id':1024},{'local_id':True},{'local_id':1,'capacity':0},{'local_id':1,'capacity':True},{'local_id':1,'num_ports':3}):
            with self.assertRaises((TypeError,ValueError)):self.m.ReadTracker(**kwargs)
        with self.assertRaises(ValueError):self.tracker().reserve(replace(self.req,src=2))

    def test_memory_data_has_natural_byte_order_and_route(self):
        memory=bytes((i*29+7)&255 for i in range(4096));request=replace(self.req,address=64)
        response=self.m.memory_read(request,memory)
        self.assertEqual(response.data_halves,(int.from_bytes(memory[64:96],'little'),int.from_bytes(memory[96:128],'little')))
        self.assertEqual((response.tag,response.src,response.dst,response.status),(1023,1023,1,0))

    def test_memory_high_address_no_alias_and_full_error_beat(self):
        memory=bytes(range(256))*16
        for address in (4096,1<<56,(1<<57)-64):
            response=self.m.memory_read(replace(self.req,address=address),memory)
            self.assertEqual((response.status,response.data_halves,response.last),(3,(0,0),True))
        response=self.m.memory_read(replace(self.req,address=4032),memory)
        self.assertEqual(response.status,0)

    def test_contract_fixed_layout_and_vectors(self):
        contract=json.loads((ROOT/'config/endpoint_transaction_contract.json').read_text())
        self.assertEqual(contract['request_fields']['TAG']['lsb'],103)
        self.assertEqual(contract['request_fields']['ADDR']['width'],55)
        self.assertEqual(contract['response_fields']['RSPTYPE']['lsb'],14)
        self.assertEqual(contract['profile']['read_bytes'],64)
        self.assertEqual(contract['known_vectors']['request'][1]['word'],'10c3ffbfcf00ffffffffffffe1ffffc0')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label')
    args, remaining = parser.parse_known_args()
    if args.label is None:
        unittest.main(argv=[sys.argv[0]] + remaining, verbosity=2)
        return
    if remaining or not re.fullmatch(r'[A-Za-z0-9_-]+', args.label):
        parser.error('--label requires one safe fresh directory name and no test selectors')
    directory = ROOT / 'build/verification/endpoint_transaction' / args.label
    directory.mkdir(parents=True, exist_ok=False)
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(TransactionTests))
    (directory / 'run.log').write_text(stream.getvalue())
    sources = [ROOT/'model/ualink/endpoint_transaction.py',
               ROOT/'config/endpoint_transaction_contract.json', Path(__file__)]
    record = dict(passed=result.wasSuccessful(), tests=result.testsRun,
                  failures=len(result.failures), errors=len(result.errors),
                  python=sys.version, optimize=sys.flags.optimize,
                  command=[sys.executable] + (['-O'] if sys.flags.optimize else []) +
                          [str(Path(__file__).resolve()), '--label', args.label],
                  sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in sources if p.is_file()},
                  log_sha256=hashlib.sha256((directory/'run.log').read_bytes()).hexdigest())
    (directory / 'result.json').write_text(json.dumps(record,indent=2)+'\n')
    print(stream.getvalue(), end='')
    raise SystemExit(0 if result.wasSuccessful() else 1)


if __name__ == '__main__':
    main()
