"""Literal Basic message vectors, independent ownership and physical-time checks.
Run: python3 -m unittest verification.model.test_dl_basic_message -v
Outputs: directed test results; next: integrate source admission with actual DL RTL.
"""
import unittest
from model.ualink.dl_message_scheduler import DLMessageArbiter, Message

try:
    from model.ualink.dl_basic_message import DLBasicController
except ModuleNotFoundError:
    DLBasicController = None


class DLBasicMessageTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(DLBasicController, 'Basic lifecycle model is missing')

    def test_literal_request_and_response_words(self):
        c=DLBasicController(device_id=0x155,device_type=1,port=0xABC,folding=True,tx_ready_advertised=True)
        for request,kind,word in [(lambda:c.request_rate(3125),4,0x0C350100),
                                 (c.request_device_id,5,0xA1550140),
                                 (c.request_port,6,0x8ABC0180),
                                 (lambda:c.request_tx_ready(symbols_valid=True),1,0x40)]:
            self.assertTrue(request());self.assertEqual(c.offers(),{kind:word})
            self.assertEqual(c.commit(kind,now_ps=0),word)
            self.assertEqual(c.receive((kind<<6)|0x1000,now_ps=0),'ack')
        self.assertEqual(c.completed_requests,4)

    def test_one_local_request_across_all_basic_types(self):
        c=DLBasicController();self.assertTrue(c.request_rate(31250))
        self.assertFalse(c.request_device_id());self.assertFalse(c.request_port())
        self.assertEqual(c.receive(0x1100,now_ps=1),'unmatched_ack')
        self.assertEqual(c.offers(),{4:0x7A120100});c.commit(4,now_ps=2)
        self.assertFalse(c.request_port());self.assertEqual(c.receive(0x1140,now_ps=3),'unmatched_ack')
        self.assertEqual(c.receive(0xBEEF1100,now_ps=4),'ack')
        self.assertTrue(c.request_port());self.assertEqual(c.completed_requests,1)

    def test_rate_ack_waits_for_actual_pacing_limit(self):
        c=DLBasicController();c.set_tx_limit(31250)
        self.assertEqual(c.receive(0x0C350100,now_ps=100),'request')
        self.assertEqual(c.peer_rate,3125);self.assertEqual(c.offers(),{})
        self.assertIsNone(c.commit(4,now_ps=200));c.set_tx_limit(3126)
        self.assertEqual(c.offers(),{});c.set_tx_limit(3125)
        self.assertEqual(c.offers(),{4:0x1100})
        self.assertEqual(c.commit(4,now_ps=300),0x1100)
        self.assertEqual(c.response_latencies_ps,[200]);self.assertEqual(c.deadline_misses,0)

    def test_concurrent_same_type_requests_are_independent(self):
        a=DLBasicController();b=DLBasicController()
        a.request_rate(3125);b.request_rate(15625)
        aw=a.commit(4,now_ps=0);bw=b.commit(4,now_ps=0)
        self.assertEqual(a.receive(bw,now_ps=50),'request');self.assertEqual(b.receive(aw,now_ps=50),'request')
        a.set_tx_limit(15625);b.set_tx_limit(3125)
        self.assertEqual(a.commit(4,now_ps=100),0x1100)
        self.assertEqual(b.commit(4,now_ps=100),0x1100)
        self.assertTrue(a.local_pending and b.local_pending)
        self.assertEqual(a.receive(0x1100,now_ps=150),'ack');self.assertEqual(b.receive(0x1100,now_ps=150),'ack')
        self.assertFalse(a.local_pending or b.local_pending)

    def test_stable_source_head_when_remote_request_arrives(self):
        c=DLBasicController();c.request_rate(31250);head=c.offers()
        c.receive(0x0C350100,now_ps=0);c.set_tx_limit(3125)
        self.assertEqual(c.offers(),head)
        self.assertEqual(c.commit(4,now_ps=1),0x7A120100)
        self.assertEqual(c.offers(),{4:0x1100});c.commit(4,now_ps=2)
        self.assertTrue(c.local_pending);self.assertFalse(c.remote_pending)

    def test_other_type_response_progresses_while_local_waits(self):
        c=DLBasicController(port=27);c.request_rate(31250);c.commit(4,now_ps=0)
        c.receive(0x80070180,now_ps=20)
        self.assertEqual(c.peer_port,7);self.assertEqual(c.offers(),{6:0x801B1180})
        c.commit(6,now_ps=30);self.assertTrue(c.local_pending)
        self.assertEqual(c.completed_requests,0)

    def test_id_request_and_ack_advertise_the_sender(self):
        a=DLBasicController(device_id=3,device_type=1);b=DLBasicController(device_id=9,device_type=0)
        a.request_device_id();b.receive(a.commit(5,now_ps=0),now_ps=10)
        self.assertEqual(b.peer_device,(1,3));self.assertEqual(b.offers(),{5:0x80091140})
        a.receive(b.commit(5,now_ps=20),now_ps=30);self.assertEqual(a.peer_device,(0,9))

    def test_unconfigured_id_and_port_are_zero_invalid(self):
        c=DLBasicController(device_type=1)
        c.receive(0xA0010140,now_ps=0);self.assertEqual(c.commit(5,now_ps=1),0x20001140)
        c.receive(0x80050180,now_ps=2);self.assertEqual(c.commit(6,now_ps=3),0x1180)
        c.receive(0x03FF0140,now_ps=4);self.assertIsNone(c.peer_device)

    def test_reserved_fields_are_ignored_and_generated_as_zero(self):
        c=DLBasicController(port=1)
        self.assertEqual(c.receive(0xF001EF83,now_ps=0),'request')
        self.assertEqual(c.peer_port,1);self.assertEqual(c.commit(6,now_ps=1),0x80011180)
        c.request_rate(3125);c.commit(4,now_ps=2)
        self.assertEqual(c.receive(0xFFFFFE03 | 0x1100,now_ps=3),'ack')

    def test_noop_never_creates_ack_or_completes_request(self):
        c=DLBasicController();c.request_rate(3125);c.commit(4,now_ps=0)
        self.assertEqual(c.receive(0xFFFFFE03,now_ps=1),'noop')
        self.assertEqual(c.offers(),{});self.assertTrue(c.local_pending)

    def test_tx_ready_requires_capability_and_valid_symbols(self):
        c=DLBasicController(folding=True,tx_ready_advertised=True)
        self.assertFalse(c.request_tx_ready(symbols_valid=False));self.assertTrue(c.request_tx_ready(symbols_valid=True))
        c.commit(1,now_ps=0);self.assertEqual(c.receive(0x1040,now_ps=1),'ack')
        c.receive(0x40,now_ps=2);self.assertEqual(c.commit(1,now_ps=3),0x1040)
        d=DLBasicController(folding=True);self.assertFalse(d.request_tx_ready(symbols_valid=True))
        self.assertEqual(d.receive(0x40,now_ps=0),'request')
        e=DLBasicController();self.assertEqual(e.receive(0x40,now_ps=0),'unsupported')

    def test_exact_one_microsecond_and_fractional_cycle_boundary(self):
        for delay,miss in [(1_000_000,0),(1_000_001,1),(156*6400,0),(157*6400,1)]:
            with self.subTest(delay=delay):
                c=DLBasicController();c.receive(0x180,now_ps=91)
                c.commit(6,now_ps=91+delay)
                self.assertEqual(c.response_latencies_ps,[delay]);self.assertEqual(c.deadline_misses,miss)

    def test_deadline_reports_once_without_fabricated_recovery(self):
        c=DLBasicController();c.receive(0x100|(3125<<16),now_ps=0)
        c.advance_to(1_000_001);c.advance_to(10_000_000)
        self.assertEqual(c.deadline_misses,1);self.assertTrue(c.remote_pending)
        self.assertEqual(c.offers(),{});c.set_tx_limit(3125)
        self.assertEqual(c.commit(4,now_ps=20_000_000),0x1100);self.assertEqual(c.deadline_misses,1)
        c.request_port();c.commit(6,now_ps=20_000_001);c.advance_to(10**12)
        self.assertTrue(c.local_pending);self.assertEqual(c.completed_requests,0)

    def test_remote_overlap_rejected_without_overwriting_first_reply(self):
        c=DLBasicController(port=12);c.receive(0x180,now_ps=0)
        self.assertEqual(c.receive(0x140,now_ps=1),'remote_overlap')
        self.assertEqual(c.offers(),{6:0x800C1180});self.assertEqual(c.protocol_errors,1)

    def test_global_reset_clears_both_ownerships_and_offers(self):
        c=DLBasicController();c.request_port();c.receive(0x140,now_ps=0)
        c.reset();self.assertFalse(c.local_pending or c.remote_pending)
        self.assertEqual(c.offers(),{});self.assertIsNone(c.peer_device)
        self.assertEqual(c.receive(0x1180,now_ps=1),'unmatched_ack')

    def test_invalid_arguments_and_unhandled_sources(self):
        for kwargs in [dict(device_id=1024),dict(port=4096),dict(device_type=2),dict(folding=1),dict(tx_ready_advertised=True)]:
            with self.assertRaises(ValueError):DLBasicController(**kwargs)
        c=DLBasicController()
        for value in [-1,65536,True]:
            with self.assertRaises(ValueError):c.request_rate(value)
        for value in [-1,2**32,True]:
            with self.assertRaises(ValueError):c.receive(value,now_ps=0)
        self.assertEqual(c.receive(0x104,now_ps=1),'unhandled')
        with self.assertRaises(ValueError):c.advance_to(0)

    def test_actual_arbiter_uart_lock_and_independent_ack_elapsed_time(self):
        for segment_ps in (6400,32000):
            c=DLBasicController(port=8);arb=DLMessageArbiter()
            words=tuple([0xF8000004]+list(range(32)))
            self.assertTrue(arb.offer(Message((1,0),words)))
            beat=arb.tick();self.assertEqual(beat.word,words[0])
            receive_at=1;c.receive(0x180,now_ps=receive_at)
            self.assertTrue(arb.offer(Message((0,6),(c.offers()[6],))))
            observed=[];ack_at=None
            for n in range(1,35):
                beat=arb.tick()
                if beat is None:continue
                if beat.source==(1,0):observed.append(beat.word)
                else:
                    ack_at=n*segment_ps;self.assertEqual(beat.word,c.commit(6,now_ps=ack_at));break
            self.assertEqual(observed,list(words[1:]));self.assertEqual(ack_at,33*segment_ps)
            independent_miss=int(ack_at-receive_at>1_000_000)
            self.assertEqual(c.deadline_misses,independent_miss)
            self.assertEqual(independent_miss,int(segment_ps==32000))


if __name__=='__main__':unittest.main()
