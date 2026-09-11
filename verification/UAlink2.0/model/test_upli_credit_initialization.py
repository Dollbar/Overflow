"""Initial publication tests: catch wrong quantities, timing, direction and replay."""

import unittest

from model.ualink.upli_connection import ConnectionSignals
from model.ualink.upli_credit import Account, CreditInitMonitor, UpliCreditLedger

try:
    from model.ualink.upli_credit_initialization import InitialCreditPublisher
except ModuleNotFoundError as error:
    if error.name != "model.ualink.upli_credit_initialization":
        raise
    InitialCreditPublisher = None


class InitialCreditTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(InitialCreditPublisher, "initial credit publisher is not implemented")
        self.connected = ConnectionSignals(True, True, True, True)

    @staticmethod
    def observed(event):
        return (tuple((r.port, r.vc, r.pool, r.encoded_count) for r in event.returns), event.done)

    def test_literal_batches_and_first_done_are_not_coincident(self):
        # Decrementing by encoded rather than actual amount, or early done, fails.
        dut = InitialCreditPublisher((0, 1, 3, 4, 5), 1)
        expected = [
            ((), 0), (((0, 1, False, 0),), 0), (((0, 2, False, 2),), 0),
            (((0, 3, False, 3),), 0), (((0, 0, True, 3),), 0),
            (((0, 0, True, 0),), 0), ((), 1), ((), 1),
        ]
        self.assertEqual([self.observed(dut.step(self.connected)) for _ in expected], expected)

    def test_zero_capacity_publishes_nothing_but_completes(self):
        dut = InitialCreditPublisher((0,)*20, 4, width=3)
        for cycle in range(8):
            event = dut.step(self.connected)
            self.assertEqual(event.returns, ())
            self.assertEqual(event.done, 0 if cycle < 5 else 15)

    def test_all_four_encoded_batch_lengths(self):
        dut = InitialCreditPublisher((1, 2, 3, 4, 0), 1)
        self.assertEqual([dut.step(self.connected).returns[0].encoded_count for _ in range(4)], [0, 1, 2, 3])

    def test_ports_complete_independently_and_return_together(self):
        dut = InitialCreditPublisher((1, 1, 1, 1, 1, 8, 8, 8, 8, 8), 2)
        events = [dut.step(self.connected) for _ in range(12)]
        self.assertEqual([r.port for r in events[0].returns], [0, 1])
        self.assertEqual([e.done for e in events], [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 3, 3])
        self.assertEqual(sum(r.encoded_count+1 for e in events for r in e.returns if r.port == 0), 5)
        self.assertEqual(sum(r.encoded_count+1 for e in events for r in e.returns if r.port == 1), 40)

    def test_only_returners_direction_can_start_publication(self):
        orig_only = ConnectionSignals(True, True, False, False)
        comp_only = ConnectionSignals(False, False, True, True)
        for channel, allowed, wrong in (("req", comp_only, orig_only), ("orig_data", comp_only, orig_only),
                                        ("rd_rsp", orig_only, comp_only), ("wr_rsp", orig_only, comp_only)):
            with self.subTest(channel=channel):
                dut = InitialCreditPublisher((1,)*5, 1, channel=channel)
                for _ in range(7):
                    self.assertEqual(self.observed(dut.step(wrong)), ((), 0))
                event = dut.step(allowed)
                self.assertEqual(len(event.returns), 1)
                self.assertEqual((event.returns[0].channel, event.returns[0].vc), (channel, 0))
                self.assertEqual(event.done, 0)

    def test_reset_at_every_phase_discards_old_publication(self):
        for reset_cycle in range(15):
            with self.subTest(reset_cycle=reset_cycle):
                dut = InitialCreditPublisher((5,)*5, 1)
                for _ in range(reset_cycle):
                    dut.step(self.connected)
                self.assertEqual(self.observed(dut.step(None, reset=True)), ((), 0))
                self.assertEqual(self.observed(dut.step(None, reset=True)), ((), 0))
                self.assertEqual(self.observed(dut.step(self.connected)), (((0, 0, False, 3),), 0))

    def test_completed_publication_is_never_replayed_without_reset(self):
        dut = InitialCreditPublisher((1,)*5, 1)
        events = [dut.step(self.connected) for _ in range(100)]
        self.assertEqual(sum(len(e.returns) for e in events), 5)
        self.assertTrue(all(e.done == 1 and not e.returns for e in events[5:]))

    def test_illegal_connection_withdrawal_is_rejected_without_advancing(self):
        dut = InitialCreditPublisher((8,)*5, 1)
        first = dut.step(self.connected)
        with self.assertRaises(ValueError):
            dut.step(ConnectionSignals())
        self.assertEqual(dut.outputs, first)
        second = dut.step(self.connected)
        self.assertEqual(self.observed(second), (((0, 0, False, 3),), 0))
        self.assertEqual(dut.step(self.connected).returns[0].vc, 1)

    def test_maximum_capacity_totals_and_tail_do_not_wrap(self):
        dut = InitialCreditPublisher((0, 0, 0, 0, 65535), 1, width=16)
        amounts = []
        for _ in range(16390):
            event = dut.step(self.connected)
            amounts.extend(r.encoded_count+1 for r in event.returns)
        self.assertEqual((len(amounts), sum(amounts), amounts[-1]), (16384, 65535, 3))
        self.assertEqual(event.done, 1)

    def test_registered_outputs_feed_ledger_on_following_edge(self):
        # Using fresh outputs on the same edge would credit the sender early.
        for channel in ("req", "orig_data", "rd_rsp", "wr_rsp"):
            dut = InitialCreditPublisher((1, 2, 3, 4, 5)*4, 4, channel=channel)
            capacities = {Account(p, channel, None if a == 4 else a): c
                          for p in range(4) for a, c in enumerate((1, 2, 3, 4, 5))}
            ledger = UpliCreditLedger(capacities, 4)
            monitor = CreditInitMonitor(4)
            for cycle in range(12):
                old = dut.outputs
                done = tuple((p, channel) for p in range(4) if old.done & (1 << p))
                ledger.step(self.connected, returns=old.returns, init_done=done)
                monitor.step(credit_slots=[(r.port, r.channel) for r in old.returns], done_slots=done)
                dut.step(self.connected)
                if cycle == 0:
                    self.assertTrue(all(ledger.balance(a) == 0 for a in capacities))
                if cycle == 7:
                    self.assertFalse(ledger.initialized(0, channel))
            self.assertTrue(all(ledger.balance(a) == cap for a, cap in capacities.items()))
            self.assertTrue(all(ledger.initialized(p, channel) for p in range(4)))

    def test_invalid_configuration_never_truncates_values(self):
        for kwargs in ({"num_ports":3}, {"num_ports":True}, {"width":2}, {"width":17},
                       {"width":True}, {"channel":"bad"}, {"capacities":(0,)*4},
                       {"capacities":(0, 0, 0, 0, 16)}, {"capacities":(0, 0, 0, 0, -1)},
                       {"capacities":(0, 0, 0, 0, True)}):
            args = dict(capacities=(1,)*5, num_ports=1)
            args.update(kwargs)
            with self.subTest(kwargs=kwargs), self.assertRaises((TypeError, ValueError)):
                InitialCreditPublisher(**args)

    def test_invalid_step_type_does_not_change_state(self):
        dut = InitialCreditPublisher((1,)*5, 1)
        for connection, reset in ((True, False), (self.connected, 1), (None, False)):
            with self.assertRaises(TypeError):
                dut.step(connection, reset=reset)
            self.assertEqual(self.observed(dut.outputs), ((), 0))

    def test_constructor_copies_capacities_before_publication(self):
        capacities = [1]*5
        dut = InitialCreditPublisher(capacities, 1)
        capacities[0] = 8
        self.assertEqual(dut.step(self.connected).returns[0].encoded_count, 0)


if __name__ == "__main__":
    unittest.main()
