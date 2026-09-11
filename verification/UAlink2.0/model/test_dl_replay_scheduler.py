"""LLR scheduling vectors and two automated event-level peers.
Run: python3 -m unittest verification.model.test_dl_replay_scheduler -v
Output: unittest results. Next: PHY group adaptation, watchdog and RTL.
"""
from collections import deque
import random
import json
import unittest
from model.ualink.dl_replay_header import decode_header, encode_command, encode_explicit
try:
    from model.ualink.dl_replay_scheduler import DLReplayScheduler
except ModuleNotFoundError as error:
    if error.name != 'model.ualink.dl_replay_scheduler': raise
    DLReplayScheduler = None


def request(s, target):
    return s.receive(encode_command(0,target,payload=False,request=True))


class ReplaySchedulerTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(DLReplayScheduler, 'LLR scheduler not implemented')

    def test_idle_nop_and_seventh_flit_explicit(self):
        s = DLReplayScheduler()
        for slot in range(1,50):
            f = s.send(codeword_group=slot//3); h = decode_header(f.header)
            self.assertEqual(h.op, 0 if slot % 7 == 0 else 2)
            self.assertIsNone(f.payload); self.assertFalse(f.accepted_input); self.assertFalse(f.replayed)
            self.assertEqual(s.tx.state.last_sequence, 511); self.assertEqual(h.sequence if h.op == 0 else h.ack_request, 511)

    def test_payload_sequence_and_current_ack(self):
        s = DLReplayScheduler(); s.receive(encode_explicit(1,payload=True),payload=b'in')
        for n in range(1,15):
            f = s.send(codeword_group=n,payload=bytes([n])); h = decode_header(f.header)
            self.assertTrue(f.accepted_input); self.assertEqual(f.payload, bytes([n])); self.assertEqual(f.sequence,n)
            self.assertEqual(h.sequence if h.op == 0 else h.sequence_low, n if h.op == 0 else n&7)
            if h.op == 2: self.assertEqual(h.ack_request,1)

    def test_request_captures_on_actual_first_send_then_stays_frozen(self):
        s = DLReplayScheduler(); s.receive(encode_explicit(3,payload=True),payload=b'wrong')
        self.assertEqual(s.state.replay_requests,3); self.assertEqual(s.state.request_sequence,0)
        s.receive(encode_explicit(1,payload=True),payload=b'one')
        f = s.send(codeword_group=0); self.assertEqual((decode_header(f.header).op,decode_header(f.header).ack_request),(3,2))
        s.receive(encode_explicit(2,payload=True),payload=b'two')
        self.assertEqual(decode_header(s.send(codeword_group=1).header).ack_request,2)
        s.receive(encode_explicit(3,payload=True),payload=b'three')
        self.assertEqual(decode_header(s.send(codeword_group=2).header).ack_request,2)
        self.assertEqual(s.state.replay_requests,0)

    def test_three_requests_cannot_share_fec_group(self):
        s = DLReplayScheduler(); s.receive(encode_explicit(2,payload=True),payload=b'wrong')
        ops = [decode_header(s.send(codeword_group=g).header).op for g in (0,0,0,1,1,2)]
        self.assertEqual(ops,[3,2,2,3,2,3]); self.assertEqual(s.state.replay_requests,0)

    def test_explicit_due_defers_first_request_capture(self):
        s = DLReplayScheduler()
        for _ in range(6): s.send(codeword_group=0)
        s.receive(encode_explicit(2,payload=True),payload=b'wrong')
        self.assertEqual(decode_header(s.send(codeword_group=1).header).op,0)
        self.assertEqual(s.state.replay_requests,3); self.assertEqual(s.state.request_sequence,0)
        s.receive(encode_explicit(1,payload=True),payload=b'one')
        self.assertEqual(decode_header(s.send(codeword_group=1).header).ack_request,2)

    def test_first_replay_wins_and_last_replay_remains_replay(self):
        s = DLReplayScheduler()
        for n in range(8): s.send(codeword_group=n,payload=bytes([n]))
        request(s,1); s.receive(encode_explicit(2,payload=True),payload=b'wrong')
        frames = [s.send(codeword_group=10+i,payload=b'blocked') for i in range(8)]
        self.assertTrue(frames[0].first_replay); self.assertTrue(all(f.replayed for f in frames))
        self.assertTrue(all(not f.accepted_input for f in frames)); self.assertEqual([f.payload for f in frames],[bytes([n]) for n in range(8)])
        self.assertEqual(decode_header(frames[0].header).op,1); self.assertEqual(decode_header(frames[-1].header).op,1)
        self.assertFalse(s.tx.state.replay); self.assertEqual(s.state.explicit_count,7)

    def test_single_replay_uses_explicit_replay_header(self):
        s = DLReplayScheduler(); s.send(codeword_group=0,payload=b'a'); request(s,1)
        f = s.send(codeword_group=1); self.assertTrue(f.first_replay); self.assertEqual(f.header,0x300100)
        self.assertFalse(s.tx.state.replay)

    def test_pending_request_reassigns_three_not_append(self):
        s = DLReplayScheduler(replay_limit=1); s.receive(encode_explicit(2,payload=True),payload=b'wrong')
        s.send(codeword_group=0); self.assertEqual(s.state.replay_requests,2)
        s.receive(encode_explicit(3,payload=True),payload=b'wrong'); self.assertEqual(s.state.replay_requests,3)
        self.assertEqual(decode_header(s.send(codeword_group=0).header).op,2); self.assertEqual(s.state.replay_requests,3)
        s.receive(encode_explicit(1,payload=True),payload=b'one')
        self.assertEqual(decode_header(s.send(codeword_group=1).header).ack_request,2)

    def test_full_buffer_sends_nop_and_preserves_offered_payload(self):
        s = DLReplayScheduler(capacity=1); s.send(codeword_group=0,payload=b'a')
        f = s.send(codeword_group=0,payload=b'b'); self.assertFalse(f.accepted_input); self.assertIsNone(f.payload); self.assertEqual(f.sequence,1)
        s.receive(encode_command(0,1,payload=False))
        f = s.send(codeword_group=1,payload=b'b'); self.assertTrue(f.accepted_input); self.assertEqual(f.payload,b'b'); self.assertEqual(f.sequence,2)

    def test_received_header_not_debug_sequence_controls_delivery(self):
        a = DLReplayScheduler(); b = DLReplayScheduler()
        f = a.send(codeword_group=0,payload=b'data')
        e = b.receive(f.header,payload=f.payload); self.assertEqual(e.payload,b'data'); self.assertTrue(e.receiver.deliver_payload)
        e = b.receive(f.header,payload=f.payload); self.assertIsNone(e.payload)

    def test_crc_error_drops_content_and_blocks_ack_processing(self):
        s = DLReplayScheduler(); s.send(codeword_group=0,payload=b'out')
        e = s.receive(encode_command(1,1,payload=True),payload=b'in',crc_ok=False)
        self.assertIsNone(e.payload); self.assertEqual(len(s.tx.buffer),1); self.assertEqual(s.rx.state.bad_crc_count,1)

    def test_rejected_payload_still_releases_acknowledged_tx_content(self):
        s = DLReplayScheduler(); s.send(codeword_group=0,payload=b'out')
        e = s.receive(encode_command(3,1,payload=True),payload=b'wrong')
        self.assertIsNone(e.payload); self.assertFalse(e.receiver.accepted)
        self.assertEqual([x.payload for x in e.command.acknowledged],[b'out']); self.assertEqual(s.tx.buffer,())

    def test_discard_is_one_event_for_both_receivers(self):
        s = DLReplayScheduler(replay_limit=1); s.send(codeword_group=0,payload=b'a'); request(s,1)
        s.receive(encode_explicit(2,payload=True),payload=b'wrong'); count = s.tx.state.ignore_count
        e = s.discard_ingress(); self.assertEqual(s.tx.state.ignore_count,count-1); self.assertEqual(e.receiver.request_replays,3)
        self.assertEqual(s.state.replay_requests,3); self.assertEqual(s.rx.state.bad_crc_count,1)

    def test_reset_and_api_errors_do_not_advance_time(self):
        s = DLReplayScheduler(capacity=3,replay_limit=7); s.send(codeword_group=4,payload=b'a')
        old=(s.state,s.tx.state,s.rx.state,s.tx.buffer)
        for group in (-1,3):
            with self.assertRaises(ValueError): s.send(codeword_group=group,payload=b'b')
        for group in (True,1.0,None):
            with self.assertRaises(TypeError): s.send(codeword_group=group)
        with self.assertRaises(TypeError): s.send(codeword_group=5,payload=bytearray(b'b'))
        with self.assertRaises(ValueError): s.receive(encode_explicit(1,payload=True))
        with self.assertRaises(ValueError): s.receive(encode_explicit(511,payload=False),payload=b'bad')
        with self.assertRaises(TypeError): s.receive(0,crc_ok=1)
        self.assertEqual((s.state,s.tx.state,s.rx.state,s.tx.buffer),old)
        s.reset(); self.assertEqual(s.state,DLReplayScheduler().state); self.assertEqual(s.tx.capacity,3); self.assertEqual(s.rx.replay_limit,7)

    def test_two_automatic_peers_ordered_content_and_recovery(self):
        for seed, capacity, group_span, delay in ((5,1,1,1),(17,17,3,4),(41,255,8,7),(113,3,5,2)):
            rng = random.Random(seed); peers = [DLReplayScheduler(capacity=capacity),DLReplayScheduler(capacity=capacity)]
            offered = [[bytes([side])+n.to_bytes(4,'big') for n in range(1100)] for side in range(2)]
            sent=[0,0]; delivered=[[],[]]; pipes=[deque(),deque()]; corrupt=[0,0]; replayed=[0,0]; request_groups=[[],[]]
            for slot in range(80000):
                for side in range(2):
                    while pipes[side] and pipes[side][0][0] <= slot:
                        _,header,payload,good = pipes[side].popleft()
                        result = peers[side].receive(header,payload=payload,crc_ok=good)
                        if result.payload is not None: delivered[side].append(result.payload)
                for side in range(2):
                    payload = offered[side][sent[side]] if sent[side] < 1100 else None
                    frame = peers[side].send(codeword_group=slot//group_span,payload=payload)
                    sent[side] += int(frame.accepted_input); replayed[side] += int(frame.replayed)
                    if decode_header(frame.header).op == 3:
                        group = slot//group_span
                        if request_groups[side]: self.assertGreater(group,request_groups[side][-1])
                        request_groups[side].append(group)
                    good = not (slot < 4000 and rng.randrange(25) == 0)
                    corrupt[side] += int(not good)
                    pipes[1-side].append((slot+delay,frame.header,frame.payload,good))
                    self.assertLessEqual(peers[side].tx.resident_count,capacity)
                    self.assertEqual(delivered[side],offered[1-side][:len(delivered[side])])
                if all(len(d)==1100 for d in delivered) and all(not p.tx.buffer and not p.tx.scheduled for p in peers) and all(all(item[2] is None for item in pipe) for pipe in pipes): break
            else: self.fail(('peers stalled',seed,sent,[len(x) for x in delivered]))
            for side in range(2):
                self.assertEqual(delivered[side],offered[1-side]); self.assertGreater(corrupt[side],0); self.assertGreater(replayed[side],0)
                self.assertGreater(len(request_groups[side]),0)
            print('PEER ' + json.dumps(dict(seed=seed,capacity=capacity,group_span=group_span,delay=delay,slots=slot+1,accepted=sent,delivered=[len(x) for x in delivered],bad_crc=corrupt,replayed=replayed,requests=[len(x) for x in request_groups]),sort_keys=True))

if __name__ == '__main__': unittest.main()
