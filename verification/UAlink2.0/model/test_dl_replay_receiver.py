"""Event-level receiver tests independent of a modulo-based implementation.
Run: python3 -m unittest verification.model.test_dl_replay_receiver -v
Next: compose with the real TxReplay/ACK scheduler and bounded ingress buffers.
"""
import random
import unittest
from model.ualink.dl_replay_header import encode_command, encode_explicit
try:
    from model.ualink.dl_replay_receiver import DLReplayReceiver
except ModuleNotFoundError as error:
    if error.name != 'model.ualink.dl_replay_receiver': raise
    DLReplayReceiver=None


def explicit(seq, payload=True):
    return (0x100000 if payload else 0) | (seq<<8)


class ReplayReceiverTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(DLReplayReceiver,'LLR receiver not implemented')

    def test_reset_defaults_and_no_implicit_time(self):
        r=DLReplayReceiver();self.assertEqual((r.state.last_sequence,r.state.bad_crc_count,r.state.unexpected_count,r.state.ambiguous,r.state.replay),(511,0,0,False,False))
        r.receive(explicit(2));r.receive(0,crc_ok=False);r.reset()
        self.assertEqual(r.state,DLReplayReceiver().state)
        old=r.state
        for _ in range(200):self.assertEqual(r.state,old)

    def test_expected_payload_and_nop(self):
        r=DLReplayReceiver();e=r.receive(explicit(511,False));self.assertTrue(e.accepted);self.assertFalse(e.deliver_payload)
        e=r.receive(explicit(1));self.assertTrue(e.deliver_payload);self.assertEqual(e.sequence,1)
        e=r.receive(explicit(1,False));self.assertTrue(e.accepted);self.assertEqual(r.state.last_sequence,1)
        self.assertEqual(e.request_replays,0)

    def test_entire_valid_sequence_ring_wraps_without_zero(self):
        r=DLReplayReceiver()
        for i in range(1,1025):
            seq=(i-1)%511+1
            e=r.receive(explicit(seq));self.assertTrue(e.deliver_payload,(i,e));self.assertEqual(r.state.last_sequence,seq)

    def test_compressed_sequence_across_wrap(self):
        r=DLReplayReceiver()
        for i in range(1,1030):
            seq=(i-1)%511+1
            e=r.receive(encode_command(seq&7,511,payload=True))
            self.assertTrue(e.deliver_payload,(i,e));self.assertEqual(e.sequence,seq)
        last=r.state.last_sequence;e=r.receive(encode_command(last&7,511,payload=False))
        self.assertTrue(e.accepted);self.assertFalse(e.deliver_payload);self.assertEqual(e.sequence,last)

    def test_equal_low_payload_means_eight_encoded_steps(self):
        r=DLReplayReceiver();r.receive(explicit(1));e=r.receive(encode_command(1,3,payload=True))
        self.assertEqual(e.sequence,9);self.assertFalse(e.accepted);self.assertEqual(r.state.last_sequence,1);self.assertEqual(e.request_replays,3)

    def test_reconstructed_zero_is_unexpected_not_remapped_to_one(self):
        r=DLReplayReceiver()
        for seq in range(1,505):r.receive(explicit(seq))
        e=r.receive(encode_command(0,1,payload=True));self.assertEqual(e.sequence,0);self.assertFalse(e.accepted);self.assertEqual(r.state.last_sequence,504)

    def test_seventh_bad_flit_sets_ambiguous_and_saturates(self):
        r=DLReplayReceiver()
        for n in range(1,13):
            e=r.receive(explicit(1),crc_ok=False)
            self.assertEqual(r.state.bad_crc_count,min(n,7));self.assertEqual(r.state.ambiguous,n>=7)
            self.assertEqual(r.state.unexpected_count,0);self.assertFalse(r.state.replay);self.assertEqual(e.request_replays,0)
        self.assertEqual(r.state.last_sequence,511)

    def test_reserved_operation_is_an_invalid_ingress_flit(self):
        for word in (0x800100,0xE00100,0x200100):
            r=DLReplayReceiver();e=r.receive(word)
            self.assertFalse(e.accepted);self.assertIsNone(e.command);self.assertEqual(e.reason,'invalid_flit');self.assertEqual(r.state.bad_crc_count,1)

    def test_zero_fields_log_and_drop_without_bad_crc_increment(self):
        for word in (0,0x100000,0x300000,0x400100,0x700700):
            r=DLReplayReceiver();r.receive(0,crc_ok=False);old=r.state;e=r.receive(word)
            self.assertFalse(e.accepted);self.assertIsNone(e.command);self.assertEqual(r.state,old);self.assertIn(e.reason,('zero_sequence','zero_ack_request'))

    def test_unexpected_explicit_starts_replay_without_advancing(self):
        r=DLReplayReceiver();r.receive(0,crc_ok=False);e=r.receive(explicit(3))
        self.assertEqual(e.request_replays,3);self.assertEqual(r.state.last_sequence,511);self.assertEqual(r.state.unexpected_count,0);self.assertEqual(r.state.bad_crc_count,1);self.assertTrue(r.state.replay)

    def test_command_cannot_end_replay_even_with_expected_sequence(self):
        r=DLReplayReceiver();r.receive(explicit(2));e=r.receive(encode_command(1,5,payload=True))
        self.assertFalse(e.accepted);self.assertEqual(r.state.unexpected_count,1);self.assertTrue(r.state.replay);self.assertIsNotNone(e.command);self.assertEqual(e.command.ack_request,5)
        e=r.receive(explicit(1));self.assertTrue(e.deliver_payload);self.assertFalse(r.state.replay);self.assertEqual(r.state.unexpected_count,0)

    def test_ambiguous_without_replay_does_not_trust_command(self):
        r=DLReplayReceiver()
        for _ in range(7):r.receive(0,crc_ok=False)
        e=r.receive(encode_command(1,3,payload=True));self.assertFalse(e.accepted);self.assertEqual(e.request_replays,0);self.assertFalse(r.state.replay);self.assertEqual(r.state.unexpected_count,0);self.assertTrue(r.state.ambiguous)
        e=r.receive(explicit(1));self.assertTrue(e.deliver_payload);self.assertEqual(r.state.bad_crc_count,0);self.assertFalse(r.state.ambiguous)

    def test_matching_explicit_nop_can_restore_sync(self):
        r=DLReplayReceiver();r.receive(explicit(2))
        for _ in range(7):r.receive(0,crc_ok=False)
        e=r.receive(explicit(511,False));self.assertTrue(e.accepted);self.assertFalse(e.deliver_payload);self.assertEqual(r.state,DLReplayReceiver().state)

    def test_default_retry_limit_counts_exact_received_events(self):
        r=DLReplayReceiver();self.assertEqual(r.replay_limit,50);r.receive(explicit(2))
        for n in range(1,50):
            e=r.receive(encode_command(1,1,payload=True));self.assertEqual(e.request_replays,0);self.assertEqual(r.state.unexpected_count,n)
        e=r.receive(encode_command(1,1,payload=True));self.assertEqual(e.request_replays,3);self.assertEqual(r.state.unexpected_count,0)
        self.assertTrue(r.state.replay);self.assertEqual(r.state.last_sequence,511)

    def test_retry_limit_zero_one_and_255(self):
        for limit in (0,1,255):
            r=DLReplayReceiver(replay_limit=limit);r.receive(explicit(2))
            for n in range(1,max(1,limit)+1):
                e=r.receive(explicit(3));self.assertEqual(e.request_replays,3 if n==max(1,limit) else 0)
            self.assertEqual(r.state.unexpected_count,0)

    def test_bad_flits_during_replay_share_retry_counter(self):
        r=DLReplayReceiver(replay_limit=3);r.receive(explicit(2))
        for n in range(1,7):
            e=r.receive(0,crc_ok=False);self.assertEqual(e.request_replays,3 if n%3==0 else 0);self.assertEqual(r.state.bad_crc_count,n)
        self.assertEqual(r.state.unexpected_count,0)

    def test_classified_backpressure_drop_does_not_advance_sequence(self):
        r=DLReplayReceiver(replay_limit=2);e=r.discard_for_backpressure();self.assertEqual(e.reason,'backpressure');self.assertIsNone(e.command);self.assertFalse(e.accepted);self.assertEqual(r.state.bad_crc_count,1)
        r.receive(explicit(2));e=r.discard_for_backpressure();self.assertEqual(e.request_replays,0);e=r.discard_for_backpressure();self.assertEqual(e.request_replays,3);self.assertEqual(r.state.last_sequence,511)

    def test_ack_or_request_forwarding_is_independent_of_enqueue(self):
        for request in (False,True):
            r=DLReplayReceiver();e=r.receive(encode_command(3,7,payload=True,request=request))
            self.assertFalse(e.accepted);self.assertIsNotNone(e.command);self.assertEqual(e.command.op,3 if request else 2);self.assertEqual(e.command.ack_request,7);self.assertEqual(e.request_replays,3)
            r.reset();e=r.receive(encode_command(1,7,payload=True,request=request),crc_ok=False);self.assertIsNone(e.command)

    def test_reprogram_limit_waits_for_next_received_event(self):
        r=DLReplayReceiver(replay_limit=10);r.receive(explicit(2))
        for _ in range(3):r.receive(explicit(3))
        old=r.state;r.configure_replay_limit(2);self.assertEqual(r.state,old);e=r.receive(explicit(3));self.assertEqual(e.request_replays,3)

    def test_invalid_api_has_no_state_side_effect(self):
        for value in (-1,256):
            with self.assertRaises(ValueError):DLReplayReceiver(replay_limit=value)
        for value in (True,1.0,None):
            with self.assertRaises(TypeError):DLReplayReceiver(replay_limit=value)
        r=DLReplayReceiver();r.receive(explicit(2));old=r.state
        for value in (-1,1<<24):
            with self.assertRaises(ValueError):r.receive(value)
        for value in (0,1,None):
            with self.assertRaises(TypeError):r.receive(explicit(1),crc_ok=value)
        with self.assertRaises(ValueError):r.configure_replay_limit(256)
        self.assertEqual(r.state,old);self.assertEqual(r.replay_limit,50)

    def test_seeded_ordered_stream_survives_errors_and_recovers(self):
        for seed in (5,17,41,113):
            rng=random.Random(seed);r=DLReplayReceiver(replay_limit=9);delivered=[];requests=0
            for slot in range(3000):
                seq=len(delivered)%511+1;roll=rng.randrange(10)
                if roll==0:
                    e=r.discard_for_backpressure()
                elif roll in (1,2):
                    e=r.receive(explicit(seq),crc_ok=False)
                elif roll==3:
                    wrong=(seq+10)%511+1;e=r.receive(explicit(wrong))
                else:
                    word=explicit(seq) if slot%7==0 else encode_command(seq&7,511,payload=True)
                    e=r.receive(word)
                    if e.deliver_payload:
                        self.assertEqual(e.sequence,seq);delivered.append(seq)
                requests+=e.request_replays//3
                self.assertEqual(r.state.last_sequence,delivered[-1] if delivered else 511)
            self.assertGreater(len(delivered),350);self.assertGreater(requests,50)
            self.assertEqual(delivered,[(i%511)+1 for i in range(len(delivered))])

if __name__=='__main__':unittest.main()
