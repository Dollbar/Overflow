"""Check complete framed streams against independent whole-Flit codec outputs.
Run: python3 [-O] -m unittest verification.model.test_rs_frame_control -v
Output: cycle-reference assertions. Next: actual controller plus real formatter RTL.
"""
import random
import unittest
from model.ualink import rs_block_codec as codec
try:
    from model.ualink import rs_frame_control as frame
except ImportError:
    frame=None

class FrameControlTests(unittest.TestCase):
    def setUp(self):self.assertIsNotNone(frame,'RS frame control not implemented')
    def expected(self,cmd,payload=None):
        if cmd.kind==0:return codec.encode_data_flit(payload)
        return codec.encode_control_flit({1:'idle',2:'local_fault',3:'remote_fault',4:'power_down'}[cmd.kind],marker={0:None,1:'am',2:'ram'}[cmd.marker],am_next_count=cmd.count if cmd.marker==2 else None,link_resiliency=cmd.resiliency,pl_id=cmd.pl_id)
    def test_reset_and_idle(self):
        for n in (1,2,4,8):
            e=frame.FrameEngine(n);o=e.tick();self.assertTrue(o.command_ready);self.assertFalse(o.active or o.output_valid or o.data_ready or o.frame_completed);self.assertEqual(o.blocks,());self.assertEqual(e.index,0)
            o=e.tick(command=frame.FrameCommand(1),data=bytes(8*n),reset=True);self.assertFalse(o.command_ready or o.command_accepted or o.output_valid or o.data_ready);self.assertFalse(e.active)
    def test_command_cycle_does_not_consume_first_data(self):
        for n in (1,2,4,8):
            e=frame.FrameEngine(n);data=bytes(range(8*n));o=e.tick(command=frame.FrameCommand(0),data=data)
            self.assertTrue(o.command_accepted);self.assertFalse(o.output_valid or o.data_consumed);self.assertTrue(e.active);self.assertEqual(e.index,0)
            o=e.tick(data=data);self.assertTrue(o.data_consumed);self.assertEqual(o.index,0);self.assertEqual(o.blocks,codec.encode_data_flit(data+bytes(640-len(data)))[:n])
    def test_all_data_bytes_exactly_once(self):
        for n in (1,2,4,8):
            payload=bytes((i*37+11)%256 for i in range(640));e=frame.FrameEngine(n);cmd=frame.FrameCommand(0);e.tick(command=cmd);got=[];done=[]
            for index in range(0,80,n):
                o=e.tick(data=payload[index*8:(index+n)*8]);self.assertTrue(o.output_valid and o.output_taken and o.data_consumed);self.assertEqual(o.index,index);self.assertEqual(o.last,index==80-n);done.append(o.frame_completed);got.extend(o.blocks)
            self.assertEqual(tuple(got),self.expected(cmd,payload));self.assertEqual(codec.decode_data_flit(got),payload);self.assertEqual(done,[False]*(80//n-1)+[True]);self.assertFalse(e.active);self.assertEqual(e.index,0)
    def test_all_control_sequences_and_metadata(self):
        for n in (1,2,4,8):
            for kind in range(1,5):
                for marker in range(3):
                    if kind==4 and marker==2:continue
                    for lr in (False,True):
                        for pl in (0,1):
                            cmd=frame.FrameCommand(kind,marker,137,lr,pl);e=frame.FrameEngine(n);self.assertTrue(e.tick(command=cmd).command_accepted);got=[]
                            for index in range(0,80,n):
                                o=e.tick(data=bytes([99])*(8*n));self.assertTrue(o.output_valid and o.output_taken);self.assertFalse(o.data_ready or o.data_consumed);self.assertEqual(o.metadata,cmd);self.assertEqual(o.index,index);got.extend(o.blocks)
                            self.assertEqual(tuple(got),self.expected(cmd));self.assertFalse(e.active)
    def test_all_ram_count_bytes_and_full_eighty_blocks(self):
        for n in (1,2,4,8):
            for kind in (1,2,3):
                for count in range(256):
                    cmd=frame.FrameCommand(kind,2,count,True,count%2);e=frame.FrameEngine(n);e.tick(command=cmd);got=[]
                    for _ in range(80//n):got.extend(e.tick().blocks)
                    self.assertEqual(len(got),80);self.assertEqual(tuple(got),self.expected(cmd));self.assertEqual(got[0].payload,0x78+sum(count<<(8*j) for j in range(1,8)))
    def test_metadata_cannot_change_during_frame(self):
        for n in (1,2,4,8):
            cmd=frame.FrameCommand(2,2,53,True,1);e=frame.FrameEngine(n);e.tick(command=cmd);got=[]
            for index in range(0,80,n):
                other=frame.FrameCommand((index//n)%5,0,255,False,0);o=e.tick(command=other if index<80-n else None);self.assertFalse(o.command_accepted);self.assertEqual(o.metadata,cmd);self.assertEqual(e.metadata,cmd);got.extend(o.blocks)
            self.assertEqual(tuple(got),self.expected(cmd))
    def test_data_source_wait_holds_index(self):
        for n in (1,2,4,8):
            e=frame.FrameEngine(n);cmd=frame.FrameCommand(0);e.tick(command=cmd)
            for _ in range(7):
                o=e.tick();self.assertTrue(o.active and o.data_ready);self.assertFalse(o.output_valid or o.output_taken or o.last or o.frame_completed);self.assertEqual(e.index,0);self.assertEqual(o.blocks,())
            self.assertTrue(e.tick(data=bytes(8*n)).data_consumed);self.assertEqual(e.index,n)
    def test_backpressure_and_source_hold_preserve_output(self):
        for n in (1,2,4,8):
            for kind in (0,1,2,3,4):
                cmd=frame.FrameCommand(kind,0);e=frame.FrameEngine(n);e.tick(command=cmd);data=bytes([71])*(8*n);first=e.outputs(data=data,ready=False)
                for _ in range(5):
                    o=e.tick(command=frame.FrameCommand(1,1),data=data,ready=False);self.assertTrue(o.output_valid);self.assertFalse(o.output_taken or o.data_ready or o.data_consumed or o.command_ready or o.command_accepted);self.assertEqual(o.blocks,first.blocks);self.assertEqual(e.index,0);self.assertEqual(e.metadata,cmd)
                self.assertTrue(e.tick(data=data).output_taken);self.assertEqual(e.index,n)
    def test_last_group_stall_cannot_finish_or_accept(self):
        for n in (1,2,4,8):
            e=frame.FrameEngine(n);old=frame.FrameCommand(3,1,0,True,1);new=frame.FrameCommand(0);e.tick(command=old)
            for _ in range(80//n-1):e.tick()
            for _ in range(3):
                o=e.tick(command=new,ready=False);self.assertTrue(o.last and o.output_valid);self.assertFalse(o.frame_completed or o.command_ready or o.command_accepted);self.assertEqual(e.index,80-n);self.assertEqual(e.metadata,old)
    def test_last_data_group_missing_cannot_finish_or_accept(self):
        for n in (1,2,4,8):
            e=frame.FrameEngine(n);e.tick(command=frame.FrameCommand(0))
            for _ in range(80//n-1):e.tick(data=bytes(8*n))
            o=e.tick(command=frame.FrameCommand(1));self.assertTrue(o.data_ready);self.assertFalse(o.output_valid or o.last or o.frame_completed or o.command_ready or o.command_accepted);self.assertEqual(e.index,80-n)
            o=e.tick(command=frame.FrameCommand(1),data=bytes(8*n));self.assertTrue(o.last and o.frame_completed and o.command_accepted and o.data_consumed)
    def test_last_commit_accepts_next_frame_without_gap(self):
        for n in (1,2,4,8):
            e=frame.FrameEngine(n);a=frame.FrameCommand(2,1,0,True,1);b=frame.FrameCommand(3,2,94,False,0);e.tick(command=a);got=[]
            for index in range(0,80,n):
                o=e.tick(command=b if index==80-n else None);got.extend(o.blocks)
                if index==80-n:self.assertTrue(o.frame_completed and o.command_ready and o.command_accepted);self.assertEqual(o.metadata,a)
            self.assertTrue(e.active);self.assertEqual(e.index,0);self.assertEqual(e.metadata,b);self.assertEqual(tuple(got),self.expected(a));o=e.tick();self.assertTrue(o.output_valid);self.assertEqual(o.blocks,self.expected(b)[:n])
    def test_invalid_command_combinations_are_rejected(self):
        for kind in range(8):
            for marker in range(4):
                cmd=frame.FrameCommand(kind,marker);valid=kind<5 and marker<3 and not(kind==0 and marker!=0) and not(kind==4 and marker==2);e=frame.FrameEngine(8);o=e.tick(command=cmd)
                self.assertTrue(o.command_ready);self.assertEqual(o.command_accepted,valid);self.assertEqual(o.command_rejected,not valid);self.assertEqual(e.active,valid)
    def test_invalid_command_on_completion_does_not_corrupt_old_frame(self):
        for n in (1,2,4,8):
            e=frame.FrameEngine(n);cmd=frame.FrameCommand(4,1,0,False,1);e.tick(command=cmd)
            for _ in range(80//n-1):e.tick()
            o=e.tick(command=frame.FrameCommand(0,1));self.assertTrue(o.frame_completed and o.command_ready and o.command_rejected);self.assertFalse(o.command_accepted);self.assertEqual(o.blocks,self.expected(cmd)[80-n:]);self.assertFalse(e.active)
    def test_reset_midframe_and_at_completion_has_priority(self):
        for n in (1,2,4,8):
            for offset in (0,1,80//n-1):
                e=frame.FrameEngine(n);e.tick(command=frame.FrameCommand(2,2,173,True,1))
                for _ in range(offset):e.tick()
                o=e.tick(command=frame.FrameCommand(3),data=bytes(8*n),reset=True);self.assertFalse(o.active or o.output_valid or o.output_taken or o.frame_completed or o.command_ready or o.command_accepted or o.command_rejected or o.data_ready);self.assertEqual(o.blocks,());self.assertFalse(e.active);self.assertEqual(e.index,0);self.assertEqual(e.metadata,frame.FrameCommand())
    def test_outputs_are_pure_and_idle_metadata_is_not_valid(self):
        e=frame.FrameEngine(4);cmd=frame.FrameCommand(3,2,99,True,1);e.tick(command=cmd);state=(e.active,e.index,e.metadata)
        self.assertEqual(e.outputs(),e.outputs());self.assertEqual((e.active,e.index,e.metadata),state)
        for _ in range(20):e.tick()
        o=e.outputs();self.assertIsNone(o.metadata);self.assertEqual(o.index,0);self.assertEqual(e.metadata,cmd);self.assertFalse(o.output_valid)
    def test_continuous_mixed_frames_with_random_stalls(self):
        for n in (1,2,4,8):
            rng=random.Random(901+n);commands=[frame.FrameCommand(0),frame.FrameCommand(2,2,6,True,1),frame.FrameCommand(1,1),frame.FrameCommand(0),frame.FrameCommand(4,1,0,False,1)]*8;payloads=[bytes(rng.randrange(256) for _ in range(640)) for _ in commands];e=frame.FrameEngine(n);current=0;next_cmd=1;offset=0;got=[];completions=0;held_data=None;e.tick(command=commands[0])
            for cycle in range(20000):
                if current==len(commands):break
                if held_data is None and commands[current].kind==0 and cycle%7!=0:held_data=payloads[current][offset*8:(offset+n)*8]
                ready=cycle%5!=0;command=commands[next_cmd] if next_cmd<len(commands) else None;o=e.tick(command=command,data=held_data,ready=ready)
                if o.data_consumed:held_data=None
                if o.output_taken:got.extend(o.blocks);offset+=n
                if o.frame_completed:
                    self.assertEqual(offset,80);self.assertEqual(tuple(got),self.expected(commands[current],payloads[current]));current+=1;completions+=1;offset=0;got=[]
                if o.command_accepted:next_cmd+=1
            self.assertEqual(completions,len(commands));self.assertEqual(next_cmd,len(commands));self.assertFalse(e.active)
    def test_invalid_bus_shapes_are_explicit_model_errors(self):
        for n in (0,3,5,16,-1,True,2.0):
            with self.assertRaises(ValueError):frame.FrameEngine(n)
        e=frame.FrameEngine(2)
        for cmd in (1,{},frame.FrameCommand(-1),frame.FrameCommand(8),frame.FrameCommand(0,4),frame.FrameCommand(1,0,256),frame.FrameCommand(1,0,0,1),frame.FrameCommand(1,0,0,False,2),frame.FrameCommand(True)):
            with self.assertRaises(ValueError):e.tick(command=cmd)
        for data in (b'',bytes(15),bytes(17),bytearray(16),1):
            with self.assertRaises(ValueError):e.tick(data=data)
        for kwargs in ({'ready':1},{'reset':0}):
            with self.assertRaises(ValueError):e.tick(**kwargs)

if __name__=='__main__':unittest.main()
