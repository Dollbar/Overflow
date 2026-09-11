"""UPLI sender/initialization checks; not a receiver receipt-return engine."""

import random
import unittest

try:
    from model.ualink.upli_connection import ConnectionSignals
    from model.ualink.upli_credit import Account, Beat, CreditReturn, CreditInitMonitor, UpliCreditLedger
except ModuleNotFoundError as error:
    if error.name not in ("model.ualink.upli_connection", "model.ualink.upli_credit"):
        raise
    UpliCreditLedger = None


class CreditTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(UpliCreditLedger, "UPLI credit model not implemented")
        self.connected = ConnectionSignals(True, True, True, True)
        self.account = Account(0, "req", 0)
        self.ledger = UpliCreditLedger({self.account: 4}, num_ports=1)

    def initialize(self, ledger, grants, slots):
        ledger.step(self.connected, returns=grants)
        ledger.step(self.connected, init_done=slots)
        ledger.step(self.connected, init_done=slots)

    def test_initial_balances_are_zero_and_uncredited_send_is_rejected(self):
        self.assertEqual(self.ledger.balance(self.account), 0)
        with self.assertRaises(ValueError):
            self.ledger.step(self.connected, beats=(Beat(0, "req", 0),))

    def test_return_encoding_is_count_plus_one(self):
        for encoding, expected in ((0, 1), (1, 2), (2, 3), (3, 4)):
            ledger = UpliCreditLedger({self.account: 4}, num_ports=1)
            ledger.step(self.connected, returns=(CreditReturn(0, "req", 0, False, encoding),))
            self.assertEqual(ledger.balance(self.account), expected)

    def test_invalid_return_contents_are_ignored_when_valid_low(self):
        self.ledger.step(ConnectionSignals(False, False, False, False),
                         returns=(CreditReturn(99, "bad", None, None, None, valid=False),))
        self.assertEqual(self.ledger.balance(self.account), 0)

    def test_multiple_ports_and_channels_return_simultaneously_without_tdm(self):
        keys = (Account(0, "req", 0), Account(3, "req", 2), Account(2, "rd_rsp", None))
        ledger = UpliCreditLedger({key: 4 for key in keys}, num_ports=4)
        ledger.step(self.connected, returns=(CreditReturn(0, "req", 0, False, 0),
                                             CreditReturn(3, "req", 2, False, 1),
                                             CreditReturn(2, "rd_rsp", 1, True, 3)))
        self.assertEqual([ledger.balance(key) for key in keys], [1, 2, 4])

    def test_credit_direction_depends_on_returner_not_beat_sender(self):
        for channel, allowed in (("req", ConnectionSignals(False, False, True, True)),
                                 ("orig_data", ConnectionSignals(False, False, True, True)),
                                 ("rd_rsp", ConnectionSignals(True, True, False, False)),
                                 ("wr_rsp", ConnectionSignals(True, True, False, False))):
            key = Account(0, channel, 0)
            ledger = UpliCreditLedger({key: 2}, num_ports=1)
            with self.subTest(channel=channel):
                ledger.step(allowed, returns=(CreditReturn(0, channel, 0, False, 0),))
                self.assertEqual(ledger.balance(key), 1)
                wrong = ConnectionSignals(allowed.comp_req, allowed.orig_ack, allowed.orig_req, allowed.comp_ack)
                with self.assertRaises(ValueError):
                    ledger.step(wrong, returns=(CreditReturn(0, channel, 0, False, 0),))

    def test_beats_need_both_directions_even_with_credit_and_init_complete(self):
        self.initialize(self.ledger, (CreditReturn(0, "req", 0, False, 3),), ((0, "req"),))
        with self.assertRaises(ValueError):
            self.ledger.step(ConnectionSignals(False, False, True, True), beats=(Beat(0, "req", 0),))
        self.assertEqual(self.ledger.balance(self.account), 4)

    def test_pool_credit_is_shared_across_vcs_not_a_separate_pool_per_vc(self):
        pool = Account(0, "req", None)
        ledger = UpliCreditLedger({pool: 4, self.account: 1}, num_ports=1)
        self.initialize(ledger, (CreditReturn(0, "req", 3, True, 3),), ((0, "req"),))
        for vc in (0, 1, 2, 3):
            ledger.step(self.connected, beats=(Beat(0, "req", vc, True),))
        self.assertEqual(ledger.balance(pool), 0)
        self.assertEqual(ledger.balance(self.account), 0)
        with self.assertRaises(ValueError):
            ledger.step(self.connected, beats=(Beat(0, "req", 1, True),))

    def test_new_return_credit_is_not_bypassed_into_same_edge_send(self):
        self.ledger.step(self.connected, init_done=((0, "req"),))
        self.ledger.step(self.connected, init_done=((0, "req"),))
        with self.assertRaises(ValueError):
            self.ledger.step(self.connected, returns=(CreditReturn(0, "req", 0, False, 0),),
                             beats=(Beat(0, "req", 0),))
        self.assertEqual(self.ledger.balance(self.account), 0)

    def test_simultaneous_spend_and_return_use_net_bounded_balance(self):
        self.initialize(self.ledger, (CreditReturn(0, "req", 0, False, 2),), ((0, "req"),))
        self.ledger.step(self.connected, returns=(CreditReturn(0, "req", 0, False, 1),),
                         beats=(Beat(0, "req", 0),))
        self.assertEqual(self.ledger.balance(self.account), 4)

    def test_overflow_and_duplicate_bus_events_do_not_partially_update(self):
        for grants in ((CreditReturn(0, "req", 0, False, 3), CreditReturn(0, "req", 0, False, 0)),
                       (CreditReturn(0, "req", 0, False, 4),), (CreditReturn(1, "req", 0, False, 0),)):
            with self.subTest(grants=grants), self.assertRaises((TypeError, ValueError)):
                self.ledger.step(self.connected, returns=grants)
            self.assertEqual(self.ledger.balance(self.account), 0)
        self.initialize(self.ledger, (CreditReturn(0, "req", 0, False, 3),), ((0, "req"),))
        with self.assertRaises(ValueError):
            self.ledger.step(self.connected, returns=(CreditReturn(0, "req", 0, False, 0),))
        with self.assertRaises(ValueError):
            self.ledger.step(self.connected, beats=(Beat(0, "req", 0), Beat(0, "req", 0)))
        self.assertEqual(self.ledger.balance(self.account), 4)

    def test_initial_done_requires_consecutive_samples_and_is_sticky_after_confirmation(self):
        self.ledger.step(self.connected, returns=(CreditReturn(0, "req", 0, False, 3),))
        self.ledger.step(self.connected, init_done=((0, "req"),))
        self.assertFalse(self.ledger.initialized(0, "req"))
        self.ledger.step(self.connected)
        self.ledger.step(self.connected, init_done=((0, "req"),))
        self.assertFalse(self.ledger.initialized(0, "req"))
        self.ledger.step(self.connected, init_done=((0, "req"),))
        self.ledger.step(self.connected, beats=(Beat(0, "req", 0),))
        self.assertTrue(self.ledger.initialized(0, "req"))
        self.assertEqual(self.ledger.balance(self.account), 3)

    def test_no_same_cycle_init_confirmation_bypass(self):
        self.ledger.step(self.connected, returns=(CreditReturn(0, "req", 0, False, 3),))
        self.ledger.step(self.connected, init_done=((0, "req"),))
        with self.assertRaises(ValueError):
            self.ledger.step(self.connected, init_done=((0, "req"),), beats=(Beat(0, "req", 0),))
        self.assertFalse(self.ledger.initialized(0, "req"))
        self.ledger.step(self.connected, init_done=((0, "req"),))
        self.assertTrue(self.ledger.initialized(0, "req"))

    def test_initial_done_filter_is_per_port_and_channel_and_parameterized(self):
        ledger = UpliCreditLedger({}, num_ports=4, init_stable_cycles=3)
        for _ in range(2):
            ledger.step(self.connected, init_done=((0, "req"), (3, "rd_rsp")))
        self.assertFalse(ledger.initialized(0, "req"))
        ledger.step(self.connected, init_done=((3, "rd_rsp"),))
        self.assertTrue(ledger.initialized(3, "rd_rsp"))
        self.assertFalse(ledger.initialized(0, "req"))
        self.assertFalse(ledger.initialized(3, "req"))

    def test_reset_discards_credit_and_init_state_ignoring_same_cycle_business(self):
        self.initialize(self.ledger, (CreditReturn(0, "req", 0, False, 3),), ((0, "req"),))
        self.ledger.step(None, reset=True, returns=(None,), beats=(None,))
        self.assertEqual(self.ledger.balance(self.account), 0)
        self.assertFalse(self.ledger.initialized(0, "req"))

    def test_bad_capacities_and_filter_parameters_are_rejected(self):
        for capacities in ({self.account: -1}, {self.account: True}, {Account(0, "req", 4): 1},
                           {Account(4, "req", 0): 1}, {Account(0, "bad", 0): 1}):
            with self.subTest(capacities=capacities), self.assertRaises((TypeError, ValueError)):
                UpliCreditLedger(capacities, num_ports=4)
        for threshold in (0, 1, True, 2.0):
            with self.subTest(threshold=threshold), self.assertRaises((TypeError, ValueError)):
                UpliCreditLedger({}, num_ports=1, init_stable_cycles=threshold)

    def test_receiver_monitor_checks_done_timing_but_allows_normal_returns_after_done(self):
        monitor = CreditInitMonitor(4)
        slot = (3, "rd_rsp")
        with self.assertRaises(ValueError):
            monitor.step(credit_slots=(slot,), done_slots=(slot,))
        monitor.step(credit_slots=(slot,))
        monitor.step(done_slots=(slot,))
        monitor.step(credit_slots=(slot,), done_slots=(slot,))
        with self.assertRaises(ValueError):
            monitor.step()
        monitor.step(reset=True)
        monitor.step()

    def test_randomized_pool_conservation_across_vcs(self):
        # Independent resource count: free+in-flight stays four across grants/spends.
        rng = random.Random(0x55504C49)
        pool = Account(0, "req", None)
        ledger = UpliCreditLedger({pool: 4}, num_ports=1)
        self.initialize(ledger, (CreditReturn(0, "req", 0, True, 3),), ((0, "req"),))
        free, in_flight = 4, []
        for _ in range(1000):
            spend = free > 0 and rng.randrange(2) == 0
            release = bool(in_flight) and rng.randrange(2) == 0
            grants = (CreditReturn(0, "req", in_flight.pop(0), True, 0),) if release else ()
            vc = rng.randrange(4)
            beats = (Beat(0, "req", vc, True),) if spend else ()
            ledger.step(self.connected, returns=grants, beats=beats)
            if spend:
                in_flight.append(vc)
            free += int(release) - int(spend)
            self.assertEqual(ledger.balance(pool), free)
            self.assertEqual(free + len(in_flight), 4)

    def test_randomized_all_accounts_conserve_resources_for_each_station_mode(self):
        # Test-only receiver token list preserves actual VC even for shared pool returns.
        # The production ledger does not use this scoreboard to calculate balances.
        for ports in (1, 2, 4):
            rng = random.Random(0x43524544 + ports)
            channels = ("req", "orig_data", "rd_rsp", "wr_rsp")
            keys = [Account(port, channel, vc) for port in range(ports)
                    for channel in channels for vc in (0, 1, 2, 3, None)]
            ledger = UpliCreditLedger({key: 4 for key in keys}, num_ports=ports)
            for account_vc in (0, 1, 2, 3, None):
                ledger.step(self.connected, returns=tuple(
                    CreditReturn(port, channel, 0 if account_vc is None else account_vc,
                                 account_vc is None, 3)
                    for port in range(ports) for channel in channels))
            slots = tuple((port, channel) for port in range(ports) for channel in channels)
            ledger.step(self.connected, init_done=slots)
            ledger.step(self.connected, init_done=slots)
            free = {key: 4 for key in keys}
            pending = {slot: [] for slot in slots}
            for cycle in range(500):
                grants, sends = [], []
                for slot in slots:
                    if pending[slot] and rng.randrange(2) == 0:
                        vc, pool = pending[slot].pop(0)
                        grants.append(CreditReturn(*slot, vc, pool, 0))
                for channel in channels:
                    port, vc, pool = rng.randrange(ports), rng.randrange(4), bool(rng.randrange(2))
                    key = Account(port, channel, None if pool else vc)
                    if free[key] and rng.randrange(2) == 0:
                        sends.append(Beat(port, channel, vc, pool))
                ledger.step(self.connected, returns=grants, beats=sends)
                for grant in grants:
                    free[Account(grant.port, grant.channel, None if grant.pool else grant.vc)] += 1
                for beat in sends:
                    pending[(beat.port, beat.channel)].append((beat.vc, beat.pool))
                    free[Account(beat.port, beat.channel, None if beat.pool else beat.vc)] -= 1
                held = {key: 0 for key in keys}
                for (port, channel), tokens in pending.items():
                    for vc, pool in tokens:
                        held[Account(port, channel, None if pool else vc)] += 1
                for key in keys:
                    with self.subTest(ports=ports, cycle=cycle, account=key):
                        self.assertEqual(ledger.balance(key), free[key])
                        self.assertEqual(free[key] + held[key], 4)


if __name__ == "__main__":
    unittest.main()
