"""Receiver ownership/replay tests; expectations use independently kept metadata."""

import random
import unittest

from model.ualink.upli_connection import ConnectionSignals
from model.ualink.upli_credit import Account, Beat, CreditReturn, UpliCreditLedger

try:
    from model.ualink.upli_receipt import Receipt, UpliReceiptQueue
except ModuleNotFoundError as error:
    if error.name != "model.ualink.upli_receipt":
        raise
    UpliReceiptQueue = None


class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(UpliReceiptQueue, "UPLI receiver receipt model not implemented")
        self.connected = ConnectionSignals(True, True, True, True)
        self.pool = Account(0, "req", None)

    def receive(self, queue, *beats):
        return tuple(queue.step(self.connected, beats=(beat,)).receipts[0] for beat in beats)

    def test_saved_pool_vc_and_dedicated_metadata_are_replayed(self):
        queue = UpliReceiptQueue({self.pool: 2, Account(0, "req", 1): 1}, 1)
        tokens = self.receive(queue, Beat(0, "req", 3, True), Beat(0, "req", 0, True),
                              Beat(0, "req", 1, False))
        queue.step(self.connected, retire=tokens)
        for token, expected in zip(tokens, (CreditReturn(0, "req", 3, True, 0),
                                           CreditReturn(0, "req", 0, True, 0),
                                           CreditReturn(0, "req", 1, False, 0))):
            result = queue.step(self.connected, batches=((token,),))
            self.assertEqual(result.returns, (expected,))
        self.assertEqual(queue.occupancy(self.pool), 0)
        self.assertEqual(queue.occupancy(Account(0, "req", 1)), 0)

    def test_one_through_four_equal_receipts_form_count_minus_one_batch(self):
        for count, encoded in ((1, 0), (2, 1), (3, 2), (4, 3)):
            with self.subTest(count=count):
                queue = UpliReceiptQueue({self.pool: 4}, 1)
                tokens = self.receive(queue, *(Beat(0, "req", 2, True) for _ in range(count)))
                queue.step(self.connected, retire=tokens)
                result = queue.step(self.connected, batches=(tokens,))
                self.assertEqual(result.returns, (CreditReturn(0, "req", 2, True, encoded),))
                self.assertEqual(queue.occupancy(self.pool), 0)

    def test_mixed_vc_pool_port_or_channel_cannot_share_a_batch(self):
        variants = (Beat(0, "req", 2, True), Beat(0, "req", 1, False),
                    Beat(1, "req", 1, True), Beat(0, "rd_rsp", 1, True))
        for other in variants:
            account = Account(other.port, other.channel, None if other.pool else other.vc)
            queue = UpliReceiptQueue({self.pool: 2, account: 2}, 2)
            tokens = self.receive(queue, Beat(0, "req", 1, True), other)
            queue.step(self.connected, retire=tokens)
            with self.subTest(other=other), self.assertRaises(ValueError):
                queue.step(self.connected, batches=(tokens,))
            self.assertEqual(queue.returnable, tokens)

    def test_return_requires_prior_retirement_not_a_same_edge_bypass(self):
        queue = UpliReceiptQueue({self.pool: 1}, 1)
        token, = self.receive(queue, Beat(0, "req", 0, True))
        for retire in ((), (token,)):
            with self.subTest(retire=bool(retire)), self.assertRaises(ValueError):
                queue.step(self.connected, retire=retire, batches=((token,),))
            self.assertEqual(queue.returnable, ())
        queue.step(self.connected, retire=(token,))
        self.assertEqual(queue.returnable, (token,))

    def test_double_retirement_and_duplicate_return_are_rejected_atomically(self):
        queue = UpliReceiptQueue({self.pool: 1}, 1)
        token, = self.receive(queue, Beat(0, "req", 2, True))
        with self.assertRaises(ValueError):
            queue.step(self.connected, retire=(token, token))
        self.assertEqual(queue.returnable, ())
        queue.step(self.connected, retire=(token,))
        with self.assertRaises(ValueError):
            queue.step(self.connected, retire=(token,))
        with self.assertRaises(ValueError):
            queue.step(self.connected, batches=((token, token),))
        self.assertEqual(queue.returnable, (token,))
        queue.step(self.connected, batches=((token,),))
        with self.assertRaises(ValueError):
            queue.step(self.connected, batches=((token,),))
        self.assertEqual(queue.occupancy(self.pool), 0)

    def test_pool_capacity_is_shared_by_vcs_and_includes_retired_receipts(self):
        queue = UpliReceiptQueue({self.pool: 2}, 1)
        tokens = self.receive(queue, Beat(0, "req", 0, True), Beat(0, "req", 3, True))
        queue.step(self.connected, retire=tokens)
        with self.assertRaises(ValueError):
            queue.step(self.connected, beats=(Beat(0, "req", 1, True),))
        self.assertEqual(queue.occupancy(self.pool), 2)
        with self.assertRaises(ValueError):
            queue.step(self.connected, beats=(Beat(0, "req", 0, False),))

    def test_full_account_cannot_reuse_same_edge_returned_slot(self):
        queue = UpliReceiptQueue({self.pool: 1}, 1)
        token, = self.receive(queue, Beat(0, "req", 0, True))
        queue.step(self.connected, retire=(token,))
        with self.assertRaises(ValueError):
            queue.step(self.connected, batches=((token,),), beats=(Beat(0, "req", 1, True),))
        self.assertEqual(queue.returnable, (token,))
        queue.step(self.connected, batches=((token,),))
        new, = self.receive(queue, Beat(0, "req", 1, True))
        self.assertEqual(new.beat.vc, 1)

    def test_different_ports_and_channels_can_return_without_tdm(self):
        beats = (Beat(0, "req", 3, True), Beat(3, "req", 1, False),
                 Beat(1, "orig_data", 2, True), Beat(2, "rd_rsp", 0, True),
                 Beat(2, "wr_rsp", 0, False))
        capacities = {Account(b.port, b.channel, None if b.pool else b.vc): 1 for b in beats}
        queue = UpliReceiptQueue(capacities, 4)
        tokens = self.receive(queue, *beats)
        queue.step(self.connected, retire=tokens)
        result = queue.step(self.connected, batches=tuple((t,) for t in tokens))
        self.assertEqual(result.returns, (CreditReturn(0, "req", 3, True, 0),
                                         CreditReturn(3, "req", 1, False, 0),
                                         CreditReturn(1, "orig_data", 2, True, 0),
                                         CreditReturn(2, "rd_rsp", 0, True, 0),
                                         CreditReturn(2, "wr_rsp", 0, False, 0)))

    def test_returns_require_the_credit_returners_direction_for_all_channels(self):
        for channel, allowed in (("req", ConnectionSignals(False, False, True, True)),
                                 ("orig_data", ConnectionSignals(False, False, True, True)),
                                 ("rd_rsp", ConnectionSignals(True, True, False, False)),
                                 ("wr_rsp", ConnectionSignals(True, True, False, False))):
            queue = UpliReceiptQueue({Account(0, channel, None): 1}, 1)
            token, = self.receive(queue, Beat(0, channel, 2, True))
            queue.step(self.connected, retire=(token,))
            wrong = ConnectionSignals(allowed.comp_req, allowed.orig_ack, allowed.orig_req, allowed.comp_ack)
            with self.subTest(channel=channel), self.assertRaises(ValueError):
                queue.step(wrong, batches=((token,),))
            self.assertEqual(queue.step(allowed, batches=((token,),)).returns,
                             (CreditReturn(0, channel, 2, True, 0),))

    def test_beats_require_both_connected_directions(self):
        queue = UpliReceiptQueue({self.pool: 1}, 1)
        for connection in (ConnectionSignals(False, False, False, False),
                           ConnectionSignals(True, True, False, False),
                           ConnectionSignals(False, False, True, True)):
            with self.subTest(connection=connection), self.assertRaises(ValueError):
                queue.step(connection, beats=(Beat(0, "req", 0, True),))
            self.assertEqual(queue.occupancy(self.pool), 0)

    def test_equal_looking_foreign_or_stale_tokens_never_alias_new_receipts(self):
        queue = UpliReceiptQueue({self.pool: 1}, 1)
        old, = self.receive(queue, Beat(0, "req", 0, True))
        other = UpliReceiptQueue({self.pool: 1}, 1)
        foreign, = self.receive(other, Beat(0, "req", 0, True))
        queue.step(None, reset=True)
        current, = self.receive(queue, Beat(0, "req", 0, True))
        for bad in (old, foreign, Receipt(current.beat), None):
            with self.subTest(kind=type(bad).__name__), self.assertRaises((TypeError, ValueError)):
                queue.step(self.connected, retire=(bad,))
        queue.step(self.connected, retire=(current,))
        self.assertEqual(queue.returnable, (current,))

    def test_incoming_bus_and_return_bus_multiplicity_are_enforced(self):
        queue = UpliReceiptQueue({self.pool: 3, Account(1, "req", None): 1}, 2)
        with self.assertRaises(ValueError):
            queue.step(self.connected, beats=(Beat(0, "req", 0, True), Beat(1, "req", 0, True)))
        tokens = self.receive(queue, Beat(0, "req", 0, True), Beat(0, "req", 1, True))
        queue.step(self.connected, retire=tokens)
        with self.assertRaises(ValueError):
            queue.step(self.connected, batches=((tokens[0],), (tokens[1],)))
        self.assertEqual(queue.returnable, tokens)

    def test_empty_or_oversized_return_batch_is_not_encoded(self):
        queue = UpliReceiptQueue({self.pool: 5}, 1)
        tokens = self.receive(queue, *(Beat(0, "req", 0, True) for _ in range(5)))
        queue.step(self.connected, retire=tokens)
        for batch in ((), tokens):
            with self.subTest(count=len(batch)), self.assertRaises(ValueError):
                queue.step(self.connected, batches=(batch,))
        self.assertEqual(queue.occupancy(self.pool), 5)

    def test_unrelated_receive_retire_and_return_can_share_an_edge(self):
        queue = UpliReceiptQueue({self.pool: 3}, 1)
        first, second = self.receive(queue, Beat(0, "req", 0, True), Beat(0, "req", 1, True))
        queue.step(self.connected, retire=(first,))
        result = queue.step(self.connected, beats=(Beat(0, "req", 2, True),),
                            retire=(second,), batches=((first,),))
        self.assertEqual(result.returns, (CreditReturn(0, "req", 0, True, 0),))
        self.assertEqual(result.receipts[0].beat, Beat(0, "req", 2, True))
        self.assertEqual(queue.returnable, (second,))
        self.assertEqual(queue.occupancy(self.pool), 2)

    def test_reset_ignores_invalid_business_and_discards_all_ownership(self):
        queue = UpliReceiptQueue({self.pool: 2}, 1)
        first, second = self.receive(queue, Beat(0, "req", 0, True), Beat(0, "req", 1, True))
        queue.step(self.connected, retire=(first,))
        result = queue.step(None, reset=True, beats=(None,), retire=(None,), batches=(None,))
        self.assertEqual((result.receipts, result.returns, queue.returnable), ((), (), ()))
        self.assertEqual(queue.occupancy(self.pool), 0)
        with self.assertRaises(ValueError):
            queue.step(self.connected, retire=(second,))

    def test_bad_configuration_or_event_does_not_silently_coerce(self):
        for ports in (0, 3, 8, True, 1.0):
            with self.subTest(ports=ports), self.assertRaises((TypeError, ValueError)):
                UpliReceiptQueue({}, ports)
        for caps in ({self.pool: -1}, {self.pool: True}, {Account(True, "req", 0): 1},
                     {Account(0, "bad", 0): 1}, {Account(0, "req", 4): 1}, {"bad": 1}):
            with self.subTest(caps=caps), self.assertRaises((TypeError, ValueError)):
                UpliReceiptQueue(caps, 1)
        queue = UpliReceiptQueue({self.pool: 1}, 1)
        for beat in (None, Beat(1, "req", 0, True), Beat(0, "bad", 0),
                     Beat(0, "req", True, True), Beat(0, "req", 0, 1)):
            with self.subTest(beat=beat), self.assertRaises((TypeError, ValueError)):
                queue.step(self.connected, beats=(beat,))
            self.assertEqual(queue.occupancy(self.pool), 0)
        with self.assertRaises(TypeError):
            queue.step(None)
        with self.assertRaises(TypeError):
            queue.step(self.connected, reset=1)

    def test_seeded_sender_receiver_conservation_and_literal_vc_replay(self):
        # This zero-flight, req-only fixture checks credit ownership, not transactions.
        rng = random.Random(0x52454356)
        for ports in (1, 2, 4):
            caps = {Account(port, "req", None): 4 for port in range(ports)}
            ledger = UpliCreditLedger(caps, ports)
            queue = UpliReceiptQueue(caps, ports)
            slots = tuple((port, "req") for port in range(ports))
            ledger.step(self.connected, returns=tuple(CreditReturn(p, "req", 0, True, 3) for p in range(ports)))
            ledger.step(self.connected, init_done=slots)
            ledger.step(self.connected, init_done=slots)
            held, completed = [], []  # Independently retained (token, port, VC) metadata.
            for cycle in range(1200):
                port = cycle % ports
                send = ledger.balance(Account(port, "req", None)) > 0 and rng.randrange(2) == 0
                done = held.pop(rng.randrange(len(held))) if held and rng.randrange(2) == 0 else None
                release = completed.pop(rng.randrange(len(completed))) if completed and rng.randrange(2) == 0 else None
                vc = rng.randrange(4)
                beats = (Beat(port, "req", vc, True),) if send else ()
                result = queue.step(self.connected, beats=beats, retire=(done[0],) if done else (),
                                    batches=((release[0],),) if release else ())
                expected = (CreditReturn(release[1], "req", release[2], True, 0),) if release else ()
                self.assertEqual(result.returns, expected)
                ledger.step(self.connected, beats=beats, returns=result.returns)
                if send:
                    held.append((result.receipts[0], port, vc))
                if done:
                    completed.append(done)
                for account in caps:
                    self.assertEqual(ledger.balance(account) + queue.occupancy(account), 4)


if __name__ == "__main__":
    unittest.main()
