"""UART reset sequence checks against literal wire/count/time requirements.

Run: python3 -m unittest verification.model.test_uart_reset -v
Outputs: directed and peer/data-path checks; next: independently compare reset RTL.
"""
from collections import deque
from dataclasses import FrozenInstanceError
import random
import unittest

try:
    from model.ualink.uart_reset import UARTResetSequencer
except ModuleNotFoundError:
    UARTResetSequencer=None
from model.ualink.uart_credit import UARTStreamFlowControl,UARTTransport
from model.ualink.uart_rx_path import UARTRxPath
from model.ualink.dl_message_scheduler import DLMessageArbiter,Message


def running():
    seq=UARTResetSequencer();seq.release_reset();return seq


def send_request(test,seq,all_streams=False):
    test.assertTrue(seq.request(all_streams=all_streams))
    test.assertEqual([seq.service().word for _ in range(40)],[0]*40)
    test.assertEqual(seq.service().word,0x1184 if all_streams else 0x184)


def peer_exchange(test,seed,drop_first_success=False):
    """Two real reset references and RX framing models with ordered delayed wires."""
    rng=random.Random(seed);ends=[running(),running()];receivers=[UARTRxPath(),UARTRxPath()]
    wires=[deque(),deque()];noops=[0,0];requests=[0,0];responses=[0,0];blocked=[0,0];discarded=[0,0]
    dropped=0;max_disabled=0
    for i in range(2):
        receivers[i].tick(reset=True);receivers[i].tick()
        receivers[i].tick(word=(31<<27)|4)
        for j in range((i+1)*7):receivers[i].tick(word=0xA000+i*100+j)
        test.assertTrue(ends[i].request(all_streams=bool(i)))
    for tick in range(50000):
        for i,seq in enumerate(ends):
            seq.advance_ps(1_000_000)
            word=wires[i].popleft()[1] if wires[i] and wires[i][0][0]<=tick else None
            out=receivers[i].tick(word=word,stream_reset=seq.stream_disabled)
            discarded[i]+=int(out.payload_discard)
            test.assertFalse(out.error)
            if out.reset_request:seq.receive_request(all_streams=out.request_all)
            if out.reset_response:seq.receive_response(status=out.response_status,all_streams=out.response_all)
            if seq.stream_disabled:
                held=receivers[i].observe(stream_reset=True)
                test.assertEqual((held.fw_valid,held.rx_fill,held.rx_counter),(False,0,0))
        for i,seq in enumerate(ends):
            was_blocked=seq.block_messages;blocked[i]+=int(was_blocked)
            message=seq.service(segment_available=rng.randrange(4)!=0)
            if message is None:continue
            if was_blocked:test.assertIn(message.kind,('noop','request'))
            if message.kind=='noop':
                noops[i]+=1;test.assertEqual(message.word,0)
            elif message.kind=='request':
                requests[i]+=1;test.assertEqual(noops[i],40*requests[i]);test.assertFalse(seq.block_messages)
            else:
                responses[i]+=1
                test.assertEqual(message.word & 0xFFFFEFFF,0x1C4)
                if drop_first_success and i==1 and dropped==0:
                    dropped+=1;continue
            peer=1-i;delivery=tick+1+rng.randrange(7)
            if wires[peer]:delivery=max(delivery,wires[peer][-1][0]+1)
            wires[peer].append((delivery,message.word))
        max_disabled=max(max_disabled,sum(e.stream_disabled for e in ends))
        if not any(e.stream_disabled for e in ends) and not any(wires):break
    else:test.fail('fair peer service did not complete reset exchange')
    for rx in receivers:
        rx.tick();test.assertEqual((rx.observe().rx_fill,rx.observe().remaining,rx.observe().rx_counter),(0,0,128))
    test.assertEqual(max_disabled,2)
    test.assertEqual(requests,[2,1] if drop_first_success else [1,1])
    test.assertEqual(responses,[1,2] if drop_first_success else [1,1])
    test.assertEqual([e.retries for e in ends],[1,0] if drop_first_success else [0,0])
    return dict(seed=seed,dropped_success=bool(drop_first_success),ticks=tick+1,noops=noops,requests=requests,
                responses=responses,retries=[e.retries for e in ends],discarded_payload=discarded,
                blocked_observations=blocked,completed=True)


class UARTResetTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(UARTResetSequencer,'UART reset sequence reference is missing')

    def test_global_release_does_not_invent_a_handshake(self):
        seq=UARTResetSequencer()
        self.assertTrue(seq.stream_disabled and seq.block_messages)
        self.assertIsNone(seq.offer());self.assertIsNone(seq.service())
        self.assertFalse(seq.request())
        self.assertFalse(seq.receive_request())
        seq.release_reset()
        self.assertFalse(seq.stream_disabled or seq.block_messages or seq.waiting)
        self.assertIsNone(seq.offer());seq.release_reset();self.assertIsNone(seq.service())

    def test_exact_forty_committed_noops_then_request(self):
        seq=running();self.assertTrue(seq.request())
        for index in range(40):
            self.assertTrue(seq.stream_disabled and seq.block_messages)
            self.assertEqual((seq.offer().kind,seq.offer().word),('noop',0))
            self.assertEqual(seq.service().word,0)
        self.assertEqual((seq.offer().kind,seq.offer().word),('request',0x184))
        self.assertTrue(seq.block_messages);seq.service()
        self.assertTrue(seq.waiting and seq.stream_disabled);self.assertFalse(seq.block_messages)
        self.assertIsNone(seq.offer())

    def test_observation_and_stalled_service_do_not_count(self):
        seq=running();seq.request(all_streams=True)
        for _ in range(100):
            self.assertEqual(seq.offer().word,0);self.assertIsNone(seq.service(False))
        self.assertEqual([seq.service().word for _ in range(40)],[0]*40)
        for _ in range(100):self.assertIsNone(seq.service(False))
        self.assertEqual(seq.service().word,0x1184)

    def test_timeout_starts_only_after_actual_request_send(self):
        seq=running();seq.request();seq.advance_ps(20_000_000_000)
        self.assertEqual([seq.service().word for _ in range(40)],[0]*40)
        seq.advance_ps(20_000_000_000)
        self.assertEqual(seq.retries,0);self.assertEqual(seq.offer().word,0x184)
        seq.service();seq.advance_ps(9_999_999_999)
        self.assertTrue(seq.waiting);self.assertIsNone(seq.offer())
        seq.advance_ps(1);self.assertEqual(seq.retries,1);self.assertEqual(seq.offer().word,0)

    def test_timeout_repeats_full_sequence_and_rearms(self):
        seq=running();send_request(self,seq,all_streams=True)
        for retry in range(1,4):
            seq.advance_ps(10_000_000_000)
            self.assertEqual(seq.retries,retry);self.assertTrue(seq.stream_disabled and seq.block_messages)
            self.assertEqual([seq.service().word for _ in range(40)],[0]*40)
            self.assertEqual(seq.service().word,0x1184)
            self.assertTrue(seq.waiting)

    def test_only_success_in_wait_resumes_uart(self):
        seq=running();self.assertFalse(seq.receive_response(status=0))
        seq.request();self.assertFalse(seq.receive_response(status=0))
        for _ in range(40):seq.service()
        self.assertFalse(seq.receive_response(status=0));seq.service()
        for status in range(1,8):
            self.assertFalse(seq.receive_response(status=status));self.assertTrue(seq.stream_disabled)
        self.assertTrue(seq.receive_response(status=0));self.assertFalse(seq.stream_disabled or seq.waiting)
        seq.advance_ps(20_000_000_000);self.assertEqual(seq.retries,0)

    def test_remote_request_holds_until_response_commits(self):
        seq=running();self.assertTrue(seq.receive_request())
        self.assertTrue(seq.stream_disabled);self.assertFalse(seq.block_messages)
        self.assertEqual((seq.offer().kind,seq.offer().word),('response',0x1C4))
        seq.advance_ps(30_000_000_000);self.assertEqual(seq.retries,0)
        for _ in range(20):self.assertIsNone(seq.service(False));self.assertTrue(seq.stream_disabled)
        self.assertEqual(seq.service().word,0x1C4);self.assertFalse(seq.stream_disabled)

    def test_stream_scope_and_reserved_status(self):
        seq=running();self.assertFalse(seq.receive_request(stream_id=3));self.assertFalse(seq.stream_disabled)
        self.assertTrue(seq.receive_request(stream_id=7,all_streams=True))
        self.assertEqual(seq.service().word,0x11C4)
        send_request(self,seq)
        self.assertFalse(seq.receive_response(status=0,stream_id=7))
        self.assertTrue(seq.receive_response(status=0,stream_id=7,all_streams=True))
        self.assertFalse(seq.stream_disabled)

    def test_each_peer_request_keeps_its_response_scope_and_order(self):
        seq=running()
        for _ in range(5):seq.receive_request(all_streams=True);seq.receive_request()
        for word in [0x11C4,0x1C4]*5:
            self.assertTrue(seq.stream_disabled)
            self.assertEqual(seq.service().word,word)
        self.assertFalse(seq.stream_disabled);self.assertIsNone(seq.service())

    def test_peer_request_does_not_interrupt_local_runout(self):
        seq=running();seq.request(all_streams=True)
        for _ in range(13):self.assertEqual(seq.service().word,0)
        self.assertTrue(seq.receive_request())
        self.assertEqual([seq.service().word for _ in range(27)],[0]*27)
        self.assertEqual(seq.service().word,0x1184)
        self.assertEqual(seq.service().word,0x1C4)
        self.assertTrue(seq.stream_disabled and seq.waiting)
        self.assertTrue(seq.receive_response(status=0));self.assertFalse(seq.stream_disabled)

    def test_success_does_not_cancel_pending_remote_response(self):
        seq=running();send_request(self,seq);seq.receive_request(all_streams=True)
        self.assertTrue(seq.receive_response(status=0));self.assertFalse(seq.waiting)
        self.assertTrue(seq.stream_disabled);self.assertEqual(seq.service().word,0x11C4)
        self.assertFalse(seq.stream_disabled)

    def test_busy_firmware_request_is_rejected_without_restart(self):
        seq=running();seq.request()
        for _ in range(39):seq.service()
        self.assertFalse(seq.request(all_streams=True));self.assertEqual(seq.service().word,0)
        self.assertEqual(seq.service().word,0x184);seq.advance_ps(9_999_999_999)
        self.assertFalse(seq.request());seq.advance_ps(1)
        self.assertEqual(seq.retries,1)

    def test_global_reset_cancels_each_phase_and_pending_response(self):
        for steps in (0,17,40,41):
            seq=running();seq.request(all_streams=True);seq.receive_request()
            for _ in range(steps):seq.service()
            seq.reset();self.assertTrue(seq.stream_disabled and seq.block_messages)
            self.assertFalse(seq.waiting);self.assertIsNone(seq.offer())
            seq.advance_ps(50_000_000_000);seq.release_reset()
            self.assertFalse(seq.stream_disabled);self.assertEqual(seq.retries,0);self.assertIsNone(seq.service())

    def test_invalid_events_are_atomic_and_message_is_immutable(self):
        seq=running();seq.request()
        for _ in range(40):seq.service()
        before=seq.offer()
        with self.assertRaises(FrozenInstanceError):before.word=0
        for value in (True,-1,1.5,'1',None):
            with self.assertRaises(ValueError):seq.advance_ps(value)
        for value in (0,1,None,'yes'):
            for call in (lambda:seq.request(all_streams=value),lambda:seq.receive_request(all_streams=value),lambda:seq.service(value)):
                with self.assertRaises(ValueError):call()
        for value in (True,-1,8,1.5,None):
            with self.assertRaises(ValueError):seq.receive_request(stream_id=value)
            with self.assertRaises(ValueError):seq.receive_response(status=value)
        self.assertEqual(seq.offer(),before);self.assertEqual(seq.retries,0)
        self.assertEqual(seq.service().word,0x184);seq.advance_ps(9_999_999_999);self.assertTrue(seq.waiting)

    def test_existing_buffers_and_credits_follow_disable_release(self):
        seq=running();flow=UARTStreamFlowControl(tx_depth=4,rx_depth=4)
        flow.release_reset();flow.set_channel4_enabled(True);flow.apply_credit_update(4)
        flow.write(10);flow.transmit();flow.write(20);flow.receive_transport(UARTTransport((30,31)));flow.read()
        self.assertEqual((flow.tx_fill,flow.rx_fill,flow.tx_counter,flow.rx_counter,flow.latest_fc),(1,1,1,5,4))
        seq.request()
        # Integration contract: stream reset flushes data but preserves channel management state.
        enabled=flow.channel4_enabled;flow.reset();flow.set_channel4_enabled(enabled)
        for _ in range(41):
            self.assertTrue(seq.stream_disabled);self.assertFalse(flow.write(99))
            self.assertFalse(flow.receive_transport(UARTTransport((98,))))
            flow.apply_credit_update(77);self.assertIsNone(flow.transmit());seq.service()
        self.assertEqual((flow.tx_fill,flow.rx_fill,flow.tx_counter,flow.rx_counter,flow.latest_fc),(0,0,0,0,0))
        self.assertTrue(seq.receive_response(status=0));flow.release_reset()
        self.assertTrue(flow.channel4_enabled);self.assertEqual(flow.credit_snapshot(),4)
        flow.write(100);self.assertIsNone(flow.transmit())
        flow.apply_credit_update(1);self.assertEqual(flow.transmit().payload,(100,))

    def test_forty_noops_flush_every_original_payload_remainder(self):
        for remaining in range(33):
            with self.subTest(remaining=remaining):
                sender=running();peer=running();rx=UARTRxPath();rx.tick(reset=True);rx.tick()
                rx.tick(word=(31<<27)|4)
                for index in range(32-remaining):rx.tick(word=0xA000+index)
                sender.request();events=0
                for index in range(41):
                    message=sender.service();out=rx.tick(word=message.word)
                    self.assertFalse(out.error or out.reset_response)
                    if out.reset_request:
                        self.assertEqual(index,40);events+=1;peer.receive_request(all_streams=out.request_all)
                self.assertEqual(events,1);self.assertTrue(peer.stream_disabled)
                rx.tick(stream_reset=peer.stream_disabled)
                self.assertEqual((rx.observe(stream_reset=True).rx_fill,rx.observe().remaining),(0,0))
                reply=peer.service();self.assertEqual(reply.word,0x1C4)
                self.assertTrue(sender.receive_response(status=0));rx.tick()
                self.assertEqual((rx.observe().rx_fill,rx.observe().rx_counter),(0,128))

    def test_queued_rate_notification_waits_for_request_commit(self):
        seq=running();normal=DLMessageArbiter()
        self.assertTrue(normal.offer(Message((0,4),(0x100,),tag='rate')))
        self.assertTrue(seq.request());wire=[]
        for _ in range(41):
            if seq.block_messages:
                wire.append(seq.service().word)
            else:
                beat=normal.tick();wire.append(None if beat is None else beat.word)
        self.assertEqual(wire,[0]*40+[0x184])
        self.assertEqual(normal.pending(),1)
        self.assertFalse(seq.block_messages);self.assertTrue(seq.stream_disabled)
        beat=normal.tick();self.assertEqual((beat.source,beat.word,beat.tag),((0,4),0x100,'rate'))
        self.assertEqual(normal.pending(),0)

    def test_simultaneous_peer_reset_with_stalls_and_delays(self):
        for seed in (17,29,101):
            with self.subTest(seed=seed):peer_exchange(self,seed)

    def test_lost_response_requires_full_retry_then_converges(self):
        for seed in (17,29,101):
            with self.subTest(seed=seed):peer_exchange(self,seed,drop_first_success=True)


if __name__=='__main__':unittest.main()
