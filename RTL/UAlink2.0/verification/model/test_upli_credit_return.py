"""Normal credit queue tests catch metadata loss, wrong batch and edge bypass."""

import unittest
import random

from model.ualink.upli_credit import Beat, CreditReturn

try:
    from model.ualink.upli_credit_return import CreditReturnQueue
except ModuleNotFoundError as error:
    if error.name != "model.ualink.upli_credit_return":
        raise
    CreditReturnQueue = None


class CreditReturnTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(CreditReturnQueue, "normal return queue is not implemented")

    def test_saved_pool_vc_is_replayed(self):
        queue = CreditReturnQueue(1, 4)
        queue.step(Beat(0, "req", 3, True))
        self.assertEqual(queue.step(enable_mask=1).returns, (CreditReturn(0, "req", 3, True, 0),))

    def test_different_vc_or_pool_never_coalesce(self):
        queue = CreditReturnQueue(1, 5)
        for vc, pool in ((2, True), (3, True), (3, False), (3, False), (2, True)):
            queue.step(Beat(0, "req", vc, pool))
        expected = [(2, True, 0), (3, True, 0), (3, False, 1), (2, True, 0)]
        for vc, pool, encoded in expected:
            self.assertEqual(queue.step(enable_mask=1).returns, (CreditReturn(0, "req", vc, pool, encoded),))
        self.assertEqual(queue.pending, (0,))

    def test_batch_lengths_one_to_four_and_split_tail(self):
        for count, encoded in ((1, 0), (2, 1), (3, 2), (4, 3)):
            with self.subTest(count=count):
                queue = CreditReturnQueue(1, 8)
                for _ in range(count+4):
                    queue.step(Beat(0, "req", 1, False))
                self.assertEqual(queue.step(enable_mask=1).returns, (CreditReturn(0, "req", 1, False, 3),))
                self.assertEqual(queue.step(enable_mask=1).returns, (CreditReturn(0, "req", 1, False, encoded),))

    def test_new_retirement_cannot_bypass_an_empty_queue(self):
        queue = CreditReturnQueue(1, 1)
        event = queue.step(Beat(0, "req", 2, False), enable_mask=15)
        self.assertTrue(event.accepted)
        self.assertEqual(event.returns, ())
        self.assertEqual(queue.pending, (1,))
        self.assertEqual(queue.step(enable_mask=1).returns, (CreditReturn(0, "req", 2, False, 0),))
        self.assertEqual(queue.step(enable_mask=15).returns, ())

    def test_full_plus_drain_does_not_accept_on_same_edge(self):
        queue = CreditReturnQueue(1, 5)
        for _ in range(5):
            self.assertTrue(queue.step(Beat(0, "req", 3, True)).accepted)
        self.assertFalse(queue.ready(0))
        event = queue.step(Beat(0, "req", 2, False), enable_mask=1)
        self.assertFalse(event.accepted)
        self.assertEqual(event.returns, (CreditReturn(0, "req", 3, True, 3),))
        self.assertEqual(queue.pending, (1,))
        self.assertTrue(queue.ready(0))

    def test_simultaneous_drain_and_append_preserves_old_tail(self):
        queue = CreditReturnQueue(1, 5)
        for vc in (1, 1, 2, 3):
            queue.step(Beat(0, "req", vc, False))
        event = queue.step(Beat(0, "req", 0, True), enable_mask=1)
        self.assertTrue(event.accepted)
        self.assertEqual(event.returns, (CreditReturn(0, "req", 1, False, 1),))
        for vc, pool in ((2, False), (3, False), (0, True)):
            self.assertEqual(queue.step(enable_mask=1).returns, (CreditReturn(0, "req", vc, pool, 0),))

    def test_masked_ports_hold_and_enabled_ports_return_together(self):
        queue = CreditReturnQueue(4, 3)
        for port in range(4):
            queue.step(Beat(port, "req", port, bool(port & 1)))
        self.assertEqual(queue.step(enable_mask=10).returns,
                         (CreditReturn(1, "req", 1, True, 0), CreditReturn(3, "req", 3, True, 0)))
        self.assertEqual(queue.pending, (1, 0, 1, 0))
        self.assertEqual(queue.step(enable_mask=5).returns,
                         (CreditReturn(0, "req", 0, False, 0), CreditReturn(2, "req", 2, False, 0)))

    def test_non_power_of_two_and_depth_boundaries_do_not_overrun(self):
        for ports in (1, 2, 4):
            for depth in (1, 2, 3, 4, 5, 8, 16):
                with self.subTest(ports=ports, depth=depth):
                    queue = CreditReturnQueue(ports, depth)
                    for port in range(ports):
                        for _ in range(depth):
                            self.assertTrue(queue.step(Beat(port, "req", 0, False)).accepted)
                        self.assertFalse(queue.step(Beat(port, "req", 0, False)).accepted)
                    self.assertEqual(queue.pending, (depth,)*ports)
                    totals = [0]*ports
                    for _ in range(16):
                        for grant in queue.step(enable_mask=15).returns:
                            totals[grant.port] += grant.encoded_count+1
                    self.assertEqual(totals, [depth]*ports)
                    self.assertEqual(queue.pending, (0,)*ports)

    def test_unused_port_cannot_alias_valid_port_or_block_other_drain(self):
        queue = CreditReturnQueue(1, 2)
        queue.step(Beat(0, "req", 2, True))
        for port in (1, 2, 3):
            self.assertFalse(queue.ready(port))
            self.assertFalse(queue.step(Beat(port, "req", 0, False)).accepted)
        event = queue.step(Beat(3, "req", 3, True), enable_mask=15)
        self.assertFalse(event.accepted)
        self.assertEqual(event.returns, (CreditReturn(0, "req", 2, True, 0),))

    def test_reset_discards_pending_and_registered_outputs(self):
        queue = CreditReturnQueue(2, 4)
        queue.step(Beat(0, "req", 1, True))
        queue.step(Beat(1, "req", 3, False), enable_mask=1)
        self.assertTrue(queue.outputs)
        event = queue.step(retired=object(), enable_mask=-1, reset=True)
        self.assertFalse(event.accepted)
        self.assertEqual((queue.pending, queue.outputs), ((0, 0), ()))
        self.assertEqual(queue.step(enable_mask=15).returns, ())

    def test_each_channel_keeps_its_own_identity(self):
        for channel in ("req", "orig_data", "rd_rsp", "wr_rsp"):
            with self.subTest(channel=channel):
                queue = CreditReturnQueue(1, 2, channel)
                queue.step(Beat(0, channel, 3, True))
                self.assertEqual(queue.step(enable_mask=1).returns, (CreditReturn(0, channel, 3, True, 0),))

    def test_invalid_configuration_is_rejected(self):
        for kwargs in ({"num_ports":0}, {"num_ports":3}, {"num_ports":True},
                       {"depth":0}, {"depth":17}, {"depth":True}, {"channel":"invalid"}):
            args = dict(num_ports=1, depth=4)
            args.update(kwargs)
            with self.subTest(kwargs=kwargs), self.assertRaises((TypeError, ValueError)):
                CreditReturnQueue(**args)

    def test_bad_input_does_not_partially_drain_valid_queues(self):
        queue = CreditReturnQueue(1, 4)
        queue.step(Beat(0, "req", 2, True))
        for kwargs in ({"retired":True}, {"retired":Beat(0, "rd_rsp", 0, False)},
                       {"retired":Beat(0, "req", 4, False)}, {"retired":Beat(-1, "req", 0, False)},
                       {"retired":Beat(0, "req", 1, 1)}, {"enable_mask":16}, {"enable_mask":True}, {"reset":1}):
            args = dict(enable_mask=1)
            args.update(kwargs)
            with self.subTest(kwargs=kwargs), self.assertRaises((ValueError, TypeError)):
                queue.step(**args)
            self.assertEqual((queue.pending, queue.outputs), ((1,), ()))

    def test_receipt_sender_pipeline_conserves_each_physical_account(self):
        # Returning newly accepted metadata on the same edge, wrong pool VC,
        # or deleting a token twice breaks independent ownership/balance checks.
        from model.ualink.upli_connection import ConnectionSignals
        from model.ualink.upli_credit import Account, UpliCreditLedger
        from model.ualink.upli_credit_initialization import InitialCreditPublisher
        from model.ualink.upli_receipt import UpliReceiptQueue
        connected = ConnectionSignals(True, True, True, True)
        for ports in (1, 2, 4):
            for channel in ("req", "orig_data", "rd_rsp", "wr_rsp"):
                with self.subTest(ports=ports, channel=channel):
                    capacities = {Account(p, channel, None if a == 4 else a):4 for p in range(ports) for a in range(5)}
                    sender = UpliCreditLedger(capacities, ports)
                    receiver = UpliReceiptQueue(capacities, ports)
                    publisher = InitialCreditPublisher((4,)*(ports*5), ports, channel=channel)
                    queue = CreditReturnQueue(ports, 5, channel)
                    for _ in range(12):
                        old = publisher.outputs
                        done = [(p, channel) for p in range(ports) if old.done & (1 << p)]
                        sender.step(connected, returns=old.returns, init_done=done)
                        publisher.step(connected)
                    self.assertTrue(all(sender.initialized(p, channel) for p in range(ports)))
                    held, enqueued = [], [[] for _ in range(ports)]
                    candidate = None
                    rng = random.Random(0x52504351+ports)
                    received_count = 0
                    for cycle in range(800):
                        batches = []
                        for grant in queue.outputs:
                            amount = grant.encoded_count+1
                            members = tuple(enqueued[grant.port][:amount])
                            self.assertEqual(len(members), amount)
                            for token in members:
                                self.assertEqual((token.beat.port, token.beat.channel, token.beat.vc, token.beat.pool),
                                                 (grant.port, grant.channel, grant.vc, grant.pool))
                            batches.append(members)
                            del enqueued[grant.port][:amount]
                        beat = None
                        if cycle < 500 and rng.randrange(5):
                            port, vc, pool = rng.randrange(ports), rng.randrange(4), bool(rng.randrange(2))
                            if sender.balance(Account(port, channel, None if pool else vc)):
                                beat = Beat(port, channel, vc, pool)
                        if candidate is None:
                            candidate = next((token for due, token in held if due <= cycle), None)
                        accept = candidate is not None and queue.ready(candidate.beat.port)
                        sender.step(connected, returns=queue.outputs, beats=() if beat is None else (beat,))
                        received = receiver.step(connected, beats=() if beat is None else (beat,),
                                                 retire=(candidate,) if accept else (), batches=batches)
                        event = queue.step(None if candidate is None else candidate.beat,
                                           enable_mask=15 if cycle >= 500 else rng.randrange(16))
                        self.assertEqual(event.accepted, accept)
                        if accept:
                            held = [(due, token) for due, token in held if token is not candidate]
                            enqueued[candidate.beat.port].append(candidate)
                            candidate = None
                        for token in received.receipts:
                            held.append((cycle+1+rng.randrange(7), token))
                            received_count += 1
                        for account, capacity in capacities.items():
                            self.assertEqual(sender.balance(account)+receiver.occupancy(account), capacity)
                        for port in range(ports):
                            flying = sum(g.encoded_count+1 for g in queue.outputs if g.port == port)
                            self.assertEqual(queue.pending[port]+flying, len(enqueued[port]))
                    self.assertGreater(received_count, 100)
                    self.assertIsNone(candidate)
                    self.assertEqual((held, enqueued, queue.pending, queue.outputs), ([], [[] for _ in range(ports)], (0,)*ports, ()))
                    self.assertTrue(all(sender.balance(a) == c and receiver.occupancy(a) == 0 for a, c in capacities.items()))


if __name__ == "__main__":
    unittest.main()
