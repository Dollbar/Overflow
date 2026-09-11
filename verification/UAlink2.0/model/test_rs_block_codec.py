"""Independent literal fields and complete RS Flit content checks.
Run: python3 [-O] -m unittest verification.model.test_rs_block_codec -v
Output: model tests; next use the qualified reference for actual RS formatter RTL.
"""
import unittest
try:
    from model.ualink import rs_block_codec as codec
except ImportError:
    codec=None

class BlockCodecTests(unittest.TestCase):
    def setUp(self):self.assertIsNotNone(codec,'RS block codec not implemented')
    def test_literal_data_and_sync(self):
        b=codec.encode_block('data',bytes.fromhex('0011223344556677'))
        self.assertEqual((b.sync_header,b.payload),(1,0x7766554433221100))
        self.assertEqual(codec.decode_block(codec.Block(1,0xFEDCBA9876543210)),('data',bytes.fromhex('1032547698badcfe')))
    def test_literal_idle_and_error_seven_bit_fields(self):
        self.assertEqual(codec.encode_block('idle'),codec.Block(2,0x1E))
        self.assertEqual(codec.encode_block('error'),codec.Block(2,0x3C78F1E3C78F1E1E))
        self.assertEqual(codec.decode_block(codec.Block(2,0x1E)),('idle',b''))
        self.assertEqual(codec.decode_block(codec.Block(2,0x3C78F1E3C78F1E1E)),('error',b''))
    def test_start_seven_bytes_and_order(self):
        data=bytes.fromhex('01020304050607');b=codec.encode_block('start',data)
        self.assertEqual(b,codec.Block(2,0x0706050403020178));self.assertEqual(codec.decode_block(b),('start',data))
    def test_mixed_supported_control_codes_preserved(self):
        for mask in range(1,255):
            codes=bytes(0x1E if mask&(1<<i) else 0 for i in range(8))
            word=0x1E+sum(c<<(8+7*i) for i,c in enumerate(codes))
            self.assertEqual(codec.encode_block('control',codes),codec.Block(2,word))
            self.assertEqual(codec.decode_block(codec.Block(2,word)),('control',codes))
    def test_fault_ordered_set_codes(self):
        for code in (1,2,3):
            b=codec.encode_block('fault',bytes((0,0,code)))
            self.assertEqual(b,codec.Block(2,0x4B+(code<<24)));self.assertEqual(codec.decode_block(b),('fault',bytes((0,0,code))))
    def test_powerdown_block(self):
        self.assertEqual(codec.encode_block('power_down'),codec.Block(2,0xFF))
        self.assertEqual(codec.decode_block(codec.Block(2,0xFF)),('power_down',b''))
    def test_all_data_payload_positions(self):
        for bit in range(5120):
            payload=(1<<bit).to_bytes(640,'little');blocks=codec.encode_data_flit(payload)
            self.assertEqual(len(blocks),80);self.assertTrue(all(b.sync_header==1 for b in blocks))
            self.assertEqual([(i,b.payload) for i,b in enumerate(blocks) if b.payload],[(bit//64,1<<(bit%64))])
            self.assertEqual(codec.decode_data_flit(blocks),payload)
    def test_data_flit_all_byte_values_and_reverse_independent(self):
        payload=bytes(i%256 for i in range(640));blocks=codec.encode_data_flit(payload);self.assertEqual(len(blocks),80)
        self.assertEqual(blocks[0],codec.Block(1,0x0706050403020100));self.assertEqual(blocks[79],codec.Block(1,0x7F7E7D7C7B7A7978))
        literal=tuple(codec.Block(1,sum(((8*i+j)%256)<<(8*j) for j in range(8))) for i in range(80))
        self.assertEqual(codec.decode_data_flit(literal),payload)
    def test_plain_control_flits_all_eighty_blocks(self):
        expected={'idle':0x1E,'local_fault':0x0100004B,'remote_fault':0x0200004B,'power_down':0xFF}
        for kind,word in expected.items():
            for lr in (False,True):
                blocks=codec.encode_control_flit(kind,link_resiliency=lr,pl_id=1)
                self.assertEqual(blocks,(codec.Block(2,word),)*80)
    def test_am_start_first_eight_and_resiliency_tail(self):
        base={'idle':0x1E,'local_fault':0x0100004B,'remote_fault':0x0200004B}
        for kind,word in base.items():
            for lr in (False,True):
                for pl in (0,1):
                    blocks=codec.encode_control_flit(kind,marker='am',link_resiliency=lr,pl_id=pl)
                    self.assertEqual(blocks[:8],(codec.Block(2,0x78),)*8)
                    self.assertEqual(blocks[8:79],(codec.Block(2,word),)*71)
                    self.assertEqual(blocks[79],codec.Block(2,0x78+(pl<<56)) if lr else codec.Block(2,word))
    def test_all_ram_count_bytes_first_block_only(self):
        for kind,word in [('idle',0x1E),('local_fault',0x0100004B),('remote_fault',0x0200004B)]:
            for count in range(256):
                blocks=codec.encode_control_flit(kind,marker='ram',am_next_count=count,link_resiliency=True,pl_id=1)
                self.assertEqual(blocks[0],codec.Block(2,0x78+sum(count<<(8*j) for j in range(1,8))))
                self.assertEqual(blocks[1:8],(codec.Block(2,0x78),)*7)
                self.assertEqual(blocks[8:79],(codec.Block(2,word),)*71)
                self.assertEqual(blocks[-1],codec.Block(2,0x0100000000000078))
    def test_unscheduled_ram_sentinel(self):
        blocks=codec.encode_control_flit('idle',marker='ram')
        self.assertEqual(blocks[0],codec.Block(2,0xFFFFFFFFFFFFFF78));self.assertEqual(blocks[-1],codec.Block(2,0x1E))
    def test_powerdown_start_tail_unconditional(self):
        for lr in (False,True):
            for pl in (0,1):
                blocks=codec.encode_control_flit('power_down',marker='am',link_resiliency=lr,pl_id=pl)
                self.assertEqual(blocks[:8],(codec.Block(2,0x78),)*8);self.assertEqual(blocks[8:79],(codec.Block(2,0xFF),)*71)
                self.assertEqual(blocks[-1],codec.Block(2,0x78+(pl<<56)))
    def test_decoder_rejects_bad_sync_width_and_types(self):
        for h,p in [(0,0),(3,0),(True,0),(1,-1),(1,2**64),(1,True),(1,1.0),(2,'0')]:
            with self.subTest(h=h,p=p),self.assertRaises(ValueError):codec.decode_block(codec.Block(h,p))
        for b in (None,(1,0),1):
            with self.assertRaises(ValueError):codec.decode_block(b)
    def test_decoder_rejects_every_fault_reserved_bit(self):
        for bit in list(range(8,24))+list(range(32,64)):
            with self.subTest(bit=bit),self.assertRaises(ValueError):codec.decode_block(codec.Block(2,0x0100004B|(1<<bit)))
        for code in (0,4,255):
            with self.assertRaises(ValueError):codec.decode_block(codec.Block(2,0x4B+(code<<24)))
    def test_decoder_rejects_unsupported_and_mixed_codes(self):
        for block_type in (0,0x2D,0x33,0x55,0x66,0x87):
            with self.assertRaises(ValueError):codec.decode_block(codec.Block(2,block_type))
        for i in range(8):
            with self.assertRaises(ValueError):codec.decode_block(codec.Block(2,0x1E+(1<<(8+7*i))))
        for bit in range(8,64):
            with self.assertRaises(ValueError):codec.decode_block(codec.Block(2,0xFF+(1<<bit)))
    def test_bad_primitive_arguments_are_not_discarded(self):
        for kind,data in [('unknown',b''),('data',b'123'),('start',bytes(8)),('fault',bytes(3)),('fault',bytes((1,0,1))),('idle',b'x'),('error',b'x'),('power_down',b'x'),('data',bytearray(8)),('data','abcdefgh')]:
            with self.subTest(kind=kind,data=data),self.assertRaises(ValueError):codec.encode_block(kind,data)
    def test_control_configuration_validation(self):
        for args in [dict(kind='data'),dict(kind='error'),dict(kind='idle',marker='bad'),dict(kind='power_down',marker='ram'),dict(kind='idle',am_next_count=0),dict(kind='idle',marker='am',am_next_count=0),dict(kind='idle',marker='ram',am_next_count=-1),dict(kind='idle',marker='ram',am_next_count=256),dict(kind='idle',marker='ram',am_next_count=True),dict(kind='idle',pl_id=2),dict(kind='idle',pl_id=True),dict(kind='idle',link_resiliency=1)]:
            with self.subTest(args=args),self.assertRaises(ValueError):codec.encode_control_flit(**args)
    def test_data_flit_bad_lengths_and_control_contamination(self):
        for data in (b'',bytes(639),bytes(641),bytearray(640)):
            with self.assertRaises(ValueError):codec.encode_data_flit(data)
        valid=(codec.Block(1,0),)*80
        for blocks in (valid[:-1],valid+valid[:1],None):
            with self.assertRaises(ValueError):codec.decode_data_flit(blocks)
        for position in range(80):
            bad=list(valid);bad[position]=codec.Block(2,0x1E)
            with self.subTest(position=position),self.assertRaises(ValueError):codec.decode_data_flit(bad)

if __name__=='__main__':unittest.main()
