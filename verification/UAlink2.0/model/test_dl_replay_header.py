"""Independent Table 2-16/17 field checks; no CRC or complete LLR claims.
Run: python3 -m unittest verification.model.test_dl_replay_header -v
Outputs test results; next implement the actual LLR event/state pipeline.
"""
import unittest
try:
    from model.ualink.dl_replay_header import decode_header, encode_command, encode_explicit
except ModuleNotFoundError as error:
    if error.name != 'model.ualink.dl_replay_header':
        raise
    decode_header = encode_command = encode_explicit = None


class ReplayHeaderTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(decode_header, 'LLR header codec not implemented')

    def test_literal_transmit_vectors(self):
        self.assertEqual(encode_explicit(511, payload=False), 0x01FF00)
        self.assertEqual(encode_explicit(1, payload=True), 0x100100)
        self.assertEqual(encode_explicit(511, payload=True, replay=True), 0x31FF00)
        self.assertEqual(encode_command(7, 511, payload=True), 0x5FFF00)
        self.assertEqual(encode_command(0, 1, payload=False, request=True), 0x600800)

    def test_literal_receive_fields(self):
        h=decode_header(0x31FF00)
        self.assertEqual((h.op,h.payload,h.sequence,h.sequence_low,h.ack_request,h.errors),(1,True,511,None,None,()))
        h=decode_header(0x600800)
        self.assertEqual((h.op,h.payload,h.sequence,h.sequence_low,h.ack_request,h.errors),(3,False,None,0,1,()))

    def test_all_operation_and_payload_pairs(self):
        for op in range(8):
            for payload in range(2):
                h=decode_header((op<<21)|(payload<<20)|0x0900)
                valid = op in (0,2,3) or (op==1 and payload==1)
                self.assertEqual(h.valid,valid,(op,payload))
                self.assertEqual(h.errors,() if valid else ('reserved_op',))
                if not valid:
                    self.assertEqual((h.sequence,h.sequence_low,h.ack_request),(None,None,None))

    def test_zero_sequence_and_command_target_are_dropped(self):
        for word in (0,0x100000,0x300000):
            h=decode_header(word);self.assertFalse(h.valid);self.assertEqual(h.errors,('zero_sequence',))
        for op in (2,3):
            for payload in (0,1):
                for low in range(8):
                    h=decode_header((op<<21)|(payload<<20)|(low<<8))
                    self.assertEqual(h.errors,('zero_ack_request',))
        self.assertTrue(decode_header(0x400800).valid)  # low sequence zero itself is legal

    def test_reserved_bits_are_ignored_on_receive(self):
        for high in range(8):
            for low in range(256):
                self.assertEqual(decode_header(0x100100|(high<<17)|low),decode_header(0x100100))
        for low in range(256):
            self.assertEqual(decode_header(0x5FFF00|low),decode_header(0x5FFF00))

    def test_explicit_field_domain_against_bit_positions(self):
        for seq in range(1,512):
            for payload,replay,op in ((False,False,0),(True,False,0),(True,True,1)):
                # Independent per-bit construction, not a call to the decoder.
                bits=[0]*24
                for index in range(9):bits[8+index]=(seq>>index)&1
                bits[20]=int(payload);bits[21]=op
                expected=sum(value*2**index for index,value in enumerate(bits))
                word=encode_explicit(seq,payload=payload,replay=replay)
                self.assertEqual(word,expected)
                self.assertEqual(decode_header(expected).sequence,seq)

    def test_command_field_domain_against_bit_positions(self):
        for target in range(1,512):
            for low in range(8):
                for payload,request in ((False,False),(True,False),(False,True),(True,True)):
                    bits=[0]*24
                    for index in range(9):bits[11+index]=(target>>index)&1
                    for index in range(3):bits[8+index]=(low>>index)&1
                    bits[20]=int(payload);bits[21]=int(request);bits[22]=1
                    expected=sum(value*2**index for index,value in enumerate(bits))
                    self.assertEqual(encode_command(low,target,payload=payload,request=request),expected)
                    h=decode_header(expected)
                    self.assertEqual((h.sequence_low,h.ack_request,h.payload,h.op),(low,target,payload,3 if request else 2))

    def test_invalid_api_values_do_not_truncate(self):
        for value in (-1,1<<24):
            with self.assertRaises(ValueError):decode_header(value)
        for value in (True,1.0,'1',None):
            with self.assertRaises(TypeError):decode_header(value)
            with self.assertRaises(TypeError):encode_explicit(value,payload=True)
        for seq in (0,512,-1):
            with self.assertRaises(ValueError):encode_explicit(seq,payload=True)
            with self.assertRaises(ValueError):encode_command(0,seq,payload=False)
        for low in (-1,8):
            with self.assertRaises(ValueError):encode_command(low,1,payload=False)
        with self.assertRaises(ValueError):encode_explicit(1,payload=False,replay=True)
        for flag in (0,1,None,'yes'):
            with self.assertRaises(TypeError):encode_explicit(1,payload=flag)
            with self.assertRaises(TypeError):encode_explicit(1,payload=True,replay=flag)
            with self.assertRaises(TypeError):encode_command(0,1,payload=True,request=flag)

if __name__=='__main__':unittest.main()
