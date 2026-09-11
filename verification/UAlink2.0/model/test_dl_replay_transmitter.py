"""Independent ring-list and actual retained-content checks for the LLR Tx model.
Run: python3 -m unittest verification.model.test_dl_replay_transmitter -v
Output: unittest results. Next: compose with complete flit scheduling and timing.
"""
import copy
import unittest
from model.ualink.dl_replay_header import encode_command
from model.ualink.dl_replay_receiver import DLReplayReceiver
try:
    from model.ualink.dl_replay_transmitter import DLReplayTransmitter
except ModuleNotFoundError as error:
    if error.name != 'model.ualink.dl_replay_transmitter': raise
    DLReplayTransmitter = None


def command(target, request=False):
    return encode_command(0, target, payload=False, request=request)


def advance(t, count):
    for i in range(count):
        e = t.enqueue(i.to_bytes(4, 'big'))
        t.receive(command(e.sequence))


class ReplayTransmitterTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(DLReplayTransmitter, 'LLR transmitter not implemented')

    def test_reset_and_no_implicit_time(self):
        t = DLReplayTransmitter(capacity=3)
        self.assertEqual((t.state.last_sequence, t.state.last_ack, t.state.ignore_count, t.state.replay, t.state.first_replay), (511,511,0,False,False))
        self.assertEqual(t.buffer, ()); self.assertEqual(t.scheduled, ()); self.assertEqual(t.resident_count, 0)
        t.enqueue(b'one'); t.receive(command(1, True)); old = t.state
        for _ in range(100): self.assertEqual(t.state, old)
        t.reset(); self.assertEqual(t.state, DLReplayTransmitter().state); self.assertEqual(t.capacity, 3)
        self.assertEqual(t.buffer, ()); self.assertEqual(t.scheduled, ())

    def test_content_and_capacity_are_real(self):
        t = DLReplayTransmitter(capacity=2)
        a = t.enqueue(bytes(range(256))); b = t.enqueue(b'\x00\xff')
        self.assertEqual((a.sequence, b.sequence), (1,2)); self.assertEqual(a.payload, bytes(range(256)))
        self.assertEqual(t.buffer, (a,b)); self.assertFalse(t.can_enqueue); old = t.state
        self.assertIsNone(t.enqueue(b'blocked')); self.assertEqual(t.state, old); self.assertEqual(t.resident_count, 2)
        e = t.receive(command(1)); self.assertEqual(e.acknowledged, (a,)); self.assertTrue(t.can_enqueue)
        c = t.enqueue(b'three'); self.assertEqual(c.sequence, 3); self.assertEqual(t.buffer, (b,c))

    def test_protocol_outstanding_limit_independent_of_capacity(self):
        t = DLReplayTransmitter(capacity=300)
        for n in range(255): self.assertIsNotNone(t.enqueue(bytes([n])))
        self.assertFalse(t.can_enqueue); self.assertIsNone(t.enqueue(b'256')); self.assertEqual(t.resident_count, 255)
        t.receive(command(1)); self.assertIsNotNone(t.enqueue(b'256')); self.assertEqual(t.state.last_sequence, 256)

    def test_sequence_wrap_uses_one_not_zero(self):
        t = DLReplayTransmitter()
        for n in range(1100):
            e = t.enqueue(n.to_bytes(4, 'big')); self.assertEqual(e.sequence, n % 511 + 1)
            ack = t.receive(command(e.sequence)); self.assertEqual(ack.acknowledged, (e,))
        self.assertEqual(t.resident_count, 0)

    def test_ack_includes_target_and_duplicate_is_valid(self):
        t = DLReplayTransmitter(); entries = [t.enqueue(bytes([n])) for n in range(5)]
        e = t.receive(command(3)); self.assertEqual(e.reason, 'ack'); self.assertEqual(e.acknowledged, tuple(entries[:3]))
        e = t.receive(command(3)); self.assertEqual(e.reason, 'ack'); self.assertEqual(e.acknowledged, ())
        self.assertEqual(t.buffer, tuple(entries[3:])); self.assertEqual(t.state.last_ack, 3)

    def test_ack_outside_live_window_does_not_mutate_buffer(self):
        t = DLReplayTransmitter(); [t.enqueue(bytes([n])) for n in range(5)]; t.receive(command(3))
        old = t.buffer
        for target in (1,2,6,255,256,510,511):
            e = t.receive(command(target)); self.assertEqual(e.reason, 'unexpected_ack'); self.assertEqual(t.buffer, old); self.assertEqual(t.state.last_ack, 3)

    def test_request_does_not_implicitly_ack(self):
        t = DLReplayTransmitter(); entries = [t.enqueue(bytes([n])) for n in range(5)]
        e = t.receive(command(3, True)); self.assertTrue(e.replay_started); self.assertEqual(e.acknowledged, ())
        self.assertEqual(t.buffer, tuple(entries)); self.assertEqual(t.state.last_ack, 511); self.assertEqual(t.scheduled, tuple(entries[2:]))
        self.assertEqual(t.state.ignore_count, 12); self.assertTrue(t.state.first_replay); self.assertFalse(t.can_enqueue)
        old = t.state; self.assertIsNone(t.enqueue(b'blocked')); self.assertEqual(t.state, old)

    def test_request_outside_live_window_ignored(self):
        t = DLReplayTransmitter(); [t.enqueue(bytes([n])) for n in range(5)]; t.receive(command(3))
        for target in (1,2,3,6,255,256,510,511):
            e = t.receive(command(target, True)); self.assertEqual(e.reason, 'unexpected_request'); self.assertFalse(t.state.replay); self.assertEqual(t.state.ignore_count, 0)

    def test_empty_buffer_duplicate_ack_but_no_request(self):
        t = DLReplayTransmitter()
        self.assertEqual(t.receive(command(511)).reason, 'ack')
        for target in (1,255,256,511):
            self.assertEqual(t.receive(command(target, True)).reason, 'unexpected_request')
            self.assertIsNone(t.next_replay())

    def test_replay_content_and_first_marker_until_last(self):
        t = DLReplayTransmitter(); entries = [t.enqueue(bytes([n,255-n])) for n in range(5)]
        t.receive(command(2, True))
        for i, entry in enumerate(entries[1:]):
            e = t.next_replay(); self.assertEqual(e.entry, entry); self.assertEqual(e.first_replay, i == 0)
            self.assertEqual(t.state.replay, i != 3); self.assertFalse(t.state.first_replay)
        self.assertIsNone(t.next_replay()); self.assertEqual(t.buffer, tuple(entries)); self.assertEqual(t.state.last_sequence, 5)
        self.assertTrue(t.can_enqueue)

    def test_ignore_decrements_before_current_request(self):
        t = DLReplayTransmitter(); t.enqueue(b'a'); t.receive(command(1, True))
        for n in range(1,12):
            e = t.receive(command(1, True)); self.assertEqual(e.reason, 'request_ignored'); self.assertEqual(t.state.ignore_count, 12-n)
        e = t.receive(command(1, True)); self.assertTrue(e.replay_started); self.assertEqual(t.state.ignore_count, 12)

    def test_all_ingress_events_age_ignore(self):
        t = DLReplayTransmitter(); t.enqueue(b'a'); t.receive(command(1, True))
        events = [(0x000100,True), (0,True), (0x800100,True), (command(1,True),False), (0x600000,True)]
        for n, (word, crc) in enumerate(events, 1):
            e = t.receive(word, crc_ok=crc); self.assertFalse(e.replay_started); self.assertEqual(t.state.ignore_count, 12-n)
        t.discard_ingress(); self.assertEqual(t.state.ignore_count, 6)
        for _ in range(20): t.discard_ingress()
        self.assertEqual(t.state.ignore_count, 0)

    def test_crc_or_encoding_error_cannot_release_or_schedule(self):
        for word, crc_ok in ((command(1),False), (command(1,True),False), (0x600000,True), (0x400000,True), (0xE00100,True)):
            t = DLReplayTransmitter(); a = t.enqueue(b'a'); old = t.state
            e = t.receive(word, crc_ok=crc_ok)
            self.assertEqual(e.reason, 'invalid_flit'); self.assertEqual(e.acknowledged, ())
            self.assertFalse(e.replay_started); self.assertEqual(t.buffer, (a,)); self.assertEqual(t.state, old)

    def test_ack_is_not_suppressed_by_request_ignore(self):
        t = DLReplayTransmitter(); a = t.enqueue(b'a'); t.enqueue(b'b'); t.receive(command(1, True))
        e = t.receive(command(1)); self.assertEqual(e.acknowledged, (a,)); self.assertEqual(t.state.ignore_count, 11); self.assertEqual(t.state.last_ack, 1)

    def test_ack_during_replay_retains_scheduled_content_and_capacity(self):
        t = DLReplayTransmitter(capacity=4); entries = [t.enqueue(bytes([n])) for n in range(4)]
        t.receive(command(1, True)); self.assertEqual(t.next_replay().entry, entries[0])
        e = t.receive(command(4)); self.assertEqual(e.acknowledged, tuple(entries)); self.assertEqual(t.buffer, ())
        self.assertEqual(t.resident_count, 3); self.assertIsNone(t.enqueue(b'blocked'))
        for i, entry in enumerate(entries[1:]):
            self.assertEqual(t.next_replay().entry, entry); self.assertEqual(t.resident_count, 2-i)
        self.assertEqual(t.enqueue(b'next').sequence, 5)

    def test_new_request_after_ignore_replaces_schedule(self):
        t = DLReplayTransmitter(); entries = [t.enqueue(bytes([n])) for n in range(5)]
        t.receive(command(3, True)); t.next_replay()
        for _ in range(11): t.discard_ingress()
        e = t.receive(command(1, True)); self.assertTrue(e.replay_started); self.assertEqual(t.scheduled, tuple(entries))
        first = t.next_replay(); self.assertEqual(first.entry, entries[0]); self.assertTrue(first.first_replay)

    def test_illegal_api_has_no_side_effects(self):
        for capacity in (0,-1):
            with self.assertRaises(ValueError): DLReplayTransmitter(capacity=capacity)
        for capacity in (True,1.5,None):
            with self.assertRaises(TypeError): DLReplayTransmitter(capacity=capacity)
        t = DLReplayTransmitter(); t.enqueue(b'a'); t.receive(command(1, True)); old = t.state
        for payload in (None,bytearray(b'a'),'a',1):
            with self.assertRaises(TypeError): t.enqueue(payload)
        for word in (-1,1 << 24):
            with self.assertRaises(ValueError): t.receive(word)
        for crc in (0,1,None):
            with self.assertRaises(TypeError): t.receive(command(1), crc_ok=crc)
        self.assertEqual(t.state, old)

    def test_independent_ring_list_window_matrix(self):
        # The oracle uses ordered members of a concrete ring; no modulo window formula.
        ring = list(range(1,512))
        for ack in (1,2,254,255,256,510,511):
            base = DLReplayTransmitter(); advance(base, 0 if ack == 511 else ack)
            following = ring[ring.index(ack)+1:] + ring[:ring.index(ack)+1]
            for count in (0,1,2,254,255):
                filled = copy.deepcopy(base)
                for n in range(count): filled.enqueue(n.to_bytes(2, 'big'))
                live = following[:count]
                for target in ring:
                    t = copy.copy(filled)
                    e = t.receive(command(target))
                    self.assertEqual(e.reason == 'ack', target in [ack]+live, (ack,count,target,'ack'))
                    expected = live[:live.index(target)+1] if target in live else []
                    self.assertEqual([x.sequence for x in e.acknowledged], expected)
                    t = copy.copy(filled); e = t.receive(command(target, True))
                    self.assertEqual(e.replay_started, target in live, (ack,count,target,'req'))
                    self.assertEqual([x.sequence for x in t.scheduled], live[live.index(target):] if target in live else [])

    def test_receiver_rejection_still_processes_ack(self):
        rx = DLReplayReceiver(); tx = DLReplayTransmitter(); a = tx.enqueue(b'a')
        word = encode_command(3,1,payload=True)
        result = rx.receive(word); self.assertFalse(result.deliver_payload); self.assertIsNotNone(result.command)
        self.assertEqual(tx.receive(word).acknowledged, (a,)); self.assertEqual(tx.buffer, ())

    def test_receiver_requests_recover_actual_retained_contents(self):
        rx = DLReplayReceiver(); tx = DLReplayTransmitter(); delivered = []
        sent = [tx.enqueue(n.to_bytes(4, 'big')) for n in range(12)]
        for n, entry in enumerate(sent):
            e = rx.receive(0x100000 | entry.sequence << 8, crc_ok=n != 2)
            if e.deliver_payload: delivered.append(entry.payload)
        self.assertEqual(delivered, [x.payload for x in sent[:2]])
        tx.receive(command(2)); self.assertTrue(tx.receive(command(3, True)).replay_started)
        while tx.state.replay:
            replay = tx.next_replay(); entry = replay.entry
            e = rx.receive(0x300000 | entry.sequence << 8)
            if e.deliver_payload: delivered.append(entry.payload)
        self.assertEqual(delivered, [x.payload for x in sent]); tx.receive(command(12)); self.assertEqual(tx.resident_count, 0)

if __name__ == '__main__': unittest.main()
