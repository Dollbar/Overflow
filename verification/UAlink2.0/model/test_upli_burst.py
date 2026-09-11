"""Credit-reserving sender checks, with literal timing and allocation oracles."""

from itertools import product
from collections import deque
import random
import unittest

from model.ualink.upli_connection import ConnectionSignals
from model.ualink.upli_credit import Account, CreditReturn
from model.ualink.upli_receipt import UpliReceiptQueue

try:
    from model.ualink.upli_burst import BurstData, BurstRequest, UpliBurstSender
except ModuleNotFoundError as error:
    if error.name != "model.ualink.upli_burst":
        raise
    UpliBurstSender = None


class BurstSenderTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(UpliBurstSender, "UPLI burst sender model not implemented")
        self.connected = ConnectionSignals(True, True, True, True)

    def initialized_sender(self, capacities, ports=1):
        sender = UpliBurstSender(capacities, ports)
        for account, count in capacities.items():
            while count:
                batch = min(count, 4)
                sender.step(self.connected, returns=(CreditReturn(account.port, account.channel,
                            0 if account.vc is None else account.vc, account.vc is None, batch - 1),))
                count -= batch
        slots = tuple((p, ch) for p in range(ports) for ch in ("req", "orig_data"))
        sender.step(self.connected, init_done=slots)
        sender.step(self.connected, init_done=slots)
        return sender

    def test_complete_burst_requires_request_and_every_data_credit(self):
        request = BurstRequest(0, 3, True, 2, (False, True, False))
        req, data, pool = Account(0, "req", None), Account(0, "orig_data", 3), Account(0, "orig_data", None)
        for amounts in ((0, 2, 1), (1, 1, 1), (1, 2, 0)):
            sender = self.initialized_sender(dict(zip((req, data, pool), amounts)))
            result = sender.step(self.connected, request)
            self.assertFalse(result.accepted, amounts)
            self.assertIsNone(result.data)
            self.assertIsNone(sender.next_port)
            self.assertEqual(tuple(sender.balance(a) for a in (req, data, pool)), amounts)
        sender = self.initialized_sender({req: 1, data: 2, pool: 1})
        result = sender.step(self.connected, request)
        self.assertTrue(result.accepted)
        self.assertEqual(result.data, BurstData(0, 3, False, 0, False))
        self.assertEqual((sender.balance(data), sender.reserved(data), sender.available(data)), (1, 1, 0))
        self.assertEqual((sender.balance(pool), sender.reserved(pool), sender.available(pool)), (1, 1, 0))

    def test_all_lengths_pool_patterns_vcs_and_start_ports(self):
        # Literal encoding/length pairs prevent a shared count decoder masking off-by-one.
        for ports in (1, 2, 4):
            for port in range(ports):
                for vc in range(4):
                    for encoded, count in ((0, 1), (1, 2), (2, 3), (3, 4)):
                        for pattern in product((False, True), repeat=count):
                            for req_pool in (False, True):
                                req = Account(port, "req", None if req_pool else vc)
                                dedicated, pool = Account(port, "orig_data", vc), Account(port, "orig_data", None)
                                capacities = {req: 1, dedicated: pattern.count(False), pool: pattern.count(True)}
                                sender = self.initialized_sender(capacities, ports)
                                request = BurstRequest(port, vc, req_pool, encoded, pattern)
                                for cycle in range((count - 1) * ports + 1):
                                    event = sender.step(self.connected, request if cycle == 0 else None)
                                    self.assertEqual(event.accepted, cycle == 0)
                                    if cycle % ports == 0:
                                        offset = cycle // ports
                                        self.assertEqual(event.data, BurstData(port, vc, pattern[offset], offset, offset == count - 1))
                                    else:
                                        self.assertIsNone(event.data)
                                    for account in capacities:
                                        self.assertEqual(sender.available(account) + sender.reserved(account), sender.balance(account))
                                self.assertEqual([sender.balance(a) for a in capacities], [0, 0, 0])
                                self.assertEqual([sender.reserved(a) for a in capacities], [0, 0, 0])

    def test_blocked_candidate_cannot_establish_phase_and_idle_cycles_advance_it(self):
        key = Account(3, "req", 0)
        sender = self.initialized_sender({key: 2}, ports=4)
        self.assertFalse(sender.step(self.connected, BurstRequest(2, 0)).accepted)
        self.assertIsNone(sender.next_port)
        self.assertTrue(sender.step(self.connected, BurstRequest(3, 0)).accepted)
        self.assertEqual(sender.next_port, 0)
        sender.step(self.connected)
        self.assertEqual(sender.next_port, 1)
        self.assertFalse(sender.step(self.connected, BurstRequest(3, 0)).accepted)
        self.assertFalse(sender.step(self.connected, BurstRequest(3, 0)).accepted)
        self.assertTrue(sender.step(self.connected, BurstRequest(3, 0)).accepted)

    def test_same_port_new_data_request_waits_until_old_last_has_been_sent(self):
        sender = self.initialized_sender({Account(0, "req", 0): 2, Account(0, "orig_data", 0): 3})
        first, second = BurstRequest(0, 0, False, 1, (False, False)), BurstRequest(0, 0, False, 0, (False,))
        self.assertTrue(sender.step(self.connected, first).accepted)
        ending = sender.step(self.connected, second)
        self.assertFalse(ending.accepted)
        self.assertEqual(ending.data, BurstData(0, 0, False, 1, True))
        self.assertTrue(sender.step(self.connected, second).accepted)

    def test_read_can_overlap_previous_write_data_on_a_different_vc(self):
        sender = self.initialized_sender({Account(0, "req", 3): 1, Account(0, "req", 1): 1,
                                          Account(0, "orig_data", 3): 2})
        sender.step(self.connected, BurstRequest(0, 3, False, 1, (False, False)))
        event = sender.step(self.connected, BurstRequest(0, 1))
        self.assertTrue(event.accepted)
        self.assertEqual(event.request.vc, 1)
        self.assertEqual(event.data, BurstData(0, 3, False, 1, True))

    def test_independent_ports_interleave_bursts_in_their_own_slots(self):
        caps = {Account(p, ch, None): 4 for p in (0, 1) for ch in ("req", "orig_data")}
        sender = self.initialized_sender(caps, ports=4)
        requests = {0: BurstRequest(0, 2, True, 2, (True,) * 3),
                    1: BurstRequest(1, 3, True, 1, (True,) * 2)}
        expected = {0: BurstData(0, 2, True, 0, False), 1: BurstData(1, 3, True, 0, False),
                    4: BurstData(0, 2, True, 1, False), 5: BurstData(1, 3, True, 1, True),
                    8: BurstData(0, 2, True, 2, True)}
        for cycle in range(9):
            event = sender.step(self.connected, requests.get(cycle))
            self.assertEqual(event.data, expected.get(cycle), cycle)
            self.assertEqual(event.accepted, cycle in requests)

    def test_request_and_data_init_must_both_be_confirmed_before_launch(self):
        req, data = Account(0, "req", 0), Account(0, "orig_data", 0)
        request = BurstRequest(0, 0, False, 0, (False,))
        for confirmed in ((), ((0, "req"),), ((0, "orig_data"),)):
            sender = UpliBurstSender({req: 1, data: 1}, 1)
            sender.step(self.connected, returns=(CreditReturn(0, "req", 0, False, 0),
                                                CreditReturn(0, "orig_data", 0, False, 0)))
            sender.step(self.connected, init_done=confirmed)
            sender.step(self.connected, init_done=confirmed)
            self.assertFalse(sender.step(self.connected, request).accepted)
        sender = UpliBurstSender({req: 1, data: 1}, 1)
        sender.step(self.connected, returns=(CreditReturn(0, "req", 0, False, 0),
                                            CreditReturn(0, "orig_data", 0, False, 0)))
        slots = ((0, "req"), (0, "orig_data"))
        sender.step(self.connected, init_done=slots)
        self.assertFalse(sender.step(self.connected, request, init_done=slots).accepted)
        self.assertTrue(sender.step(self.connected, request).accepted)

    def test_new_return_credit_does_not_bypass_launch_admission(self):
        req, data = Account(0, "req", 0), Account(0, "orig_data", 0)
        sender = UpliBurstSender({req: 1, data: 1}, 1)
        slots = ((0, "req"), (0, "orig_data"))
        sender.step(self.connected, init_done=slots)
        sender.step(self.connected, init_done=slots)
        request = BurstRequest(0, 0, False, 0, (False,))
        event = sender.step(self.connected, request, returns=(CreditReturn(0, "req", 0, False, 0),
                                                             CreditReturn(0, "orig_data", 0, False, 0)))
        self.assertFalse(event.accepted)
        self.assertEqual(sender.balance(data), 1)
        self.assertTrue(sender.step(self.connected, request).accepted)

    def test_reserved_unsent_data_is_not_debited_twice_when_a_credit_returns(self):
        data = Account(0, "orig_data", None)
        sender = self.initialized_sender({Account(0, "req", None): 1, data: 3})
        sender.step(self.connected, BurstRequest(0, 2, True, 2, (True,) * 3))
        sender.step(self.connected, returns=(CreditReturn(0, "orig_data", 2, True, 0),))
        self.assertEqual((sender.balance(data), sender.reserved(data), sender.available(data)), (2, 1, 1))
        sender.step(self.connected)
        self.assertEqual((sender.balance(data), sender.reserved(data), sender.available(data)), (1, 0, 1))

    def test_bad_credit_edge_does_not_consume_active_data_or_advance_phase(self):
        data = Account(1, "orig_data", 0)
        sender = self.initialized_sender({Account(1, "req", 0): 1, data: 2}, ports=2)
        sender.step(self.connected, BurstRequest(1, 0, False, 1, (False, False)))
        sender.step(self.connected)
        before = sender.next_port, sender.balance(data), sender.reserved(data)
        with self.assertRaises(ValueError):
            sender.step(self.connected, returns=(CreditReturn(1, "orig_data", 0, False, 4),))
        self.assertEqual((sender.next_port, sender.balance(data), sender.reserved(data)), before)
        self.assertEqual(sender.step(self.connected).data, BurstData(1, 0, False, 1, True))

    def test_reset_flushes_reservations_balances_and_phase_without_emitting(self):
        data = Account(0, "orig_data", 0)
        sender = self.initialized_sender({Account(0, "req", 0): 1, data: 4})
        sender.step(self.connected, BurstRequest(0, 0, False, 3, (False,) * 4))
        event = sender.step(None, request=object(), returns=(None,), init_done=(None,), reset=True)
        self.assertEqual((event.request, event.data, sender.next_port), (None, None, None))
        self.assertEqual((sender.balance(data), sender.reserved(data)), (0, 0))
        self.assertFalse(sender.initialized(0, "orig_data"))
        self.assertIsNone(sender.step(self.connected).data)

    def test_no_request_is_issued_before_both_connections(self):
        sender = self.initialized_sender({Account(0, "req", 0): 1})
        for connection in (ConnectionSignals(False, False, False, False),
                           ConnectionSignals(True, True, False, False),
                           ConnectionSignals(False, False, True, True)):
            self.assertFalse(sender.step(connection, BurstRequest(0, 0)).accepted)
        self.assertTrue(sender.step(self.connected, BurstRequest(0, 0)).accepted)

    def test_illegal_descriptors_and_parameters_are_rejected_without_state_changes(self):
        for ports in (0, 3, True):
            with self.assertRaises((ValueError, TypeError)):
                UpliBurstSender({}, ports)
        sender = self.initialized_sender({Account(0, "req", 0): 1})
        requests = (object(), BurstRequest(1, 0), BurstRequest(0, True), BurstRequest(0, 0, 1),
                    BurstRequest(0, 0, False, True, (False, False)),
                    BurstRequest(0, 0, False, 4, (False,) * 5),
                    BurstRequest(0, 0, False, 1, (False,)),
                    BurstRequest(0, 0, False, None, (False,)),
                    BurstRequest(0, 0, False, 0, (0,)), BurstRequest(0, 0, False, 0, [False]))
        for request in requests:
            with self.subTest(request=request), self.assertRaises((ValueError, TypeError)):
                sender.step(self.connected, request)
            self.assertEqual(sender.balance(Account(0, "req", 0)), 1)
            self.assertIsNone(sender.next_port)
        with self.assertRaises(TypeError):
            sender.step(None)
        with self.assertRaises(TypeError):
            sender.step(self.connected, reset=1)

    def test_multichannel_receipts_and_delayed_returns_preserve_burst_credit_ownership(self):
        from model.ualink.upli_burst_monitor import UpliBurstMonitor
        self.observed_modes = []
        for ports in (1, 2, 4):
            rng = random.Random(0x42555253 + ports)
            capacities = {Account(p, ch, vc): 4 for p in range(ports)
                          for ch in ("req", "orig_data") for vc in (None, 0, 1, 2, 3)}
            sender = self.initialized_sender(capacities, ports)
            receiver, monitor = UpliReceiptQueue(capacities, ports), UpliBurstMonitor(ports)
            candidates = {p: deque() for p in range(ports)}
            for p in range(ports):
                for vc in range(4):
                    for encoded, count in ((0, 1), (1, 2), (2, 3), (3, 4)):
                        for req_pool in (False, True):
                            for pattern in ((False,) * count, (True,) * count,
                                            tuple(i % 2 == 1 for i in range(count))):
                                candidates[p].append(BurstRequest(p, vc, req_pool, encoded, pattern))
                                candidates[p].append(BurstRequest(p, (vc + 1) % 4, not req_pool))
            expected_active, held, flights, metadata = {}, [], [], {}
            requests_seen = data_seen = 0
            batch_sizes = set()
            for cycle in range(10000):
                # Independent TDM schedule begins at the last port, not fixed zero.
                port = (ports - 1 + cycle) % ports
                candidate = candidates[port][0] if candidates[port] else None
                arriving = tuple(grant for due, grant in flights if due == cycle)
                flights = [(due, grant) for due, grant in flights if due != cycle]
                outgoing = sender.step(self.connected, candidate, returns=arriving)
                if cycle == 0:
                    self.assertTrue(outgoing.accepted)
                if outgoing.accepted:
                    self.assertEqual(outgoing.request, candidates[port].popleft())
                    requests_seen += 1
                    if candidate.num_beats is not None:
                        self.assertNotIn(port, expected_active)
                        expected_active[port] = [candidate.vc, candidate.data_pools, 0]
                if port in expected_active:
                    vc, pattern, offset = expected_active[port]
                    self.assertEqual(outgoing.data, BurstData(port, vc, pattern[offset], offset,
                                                              offset == len(pattern) - 1))
                    data_seen += 1
                    if offset == len(pattern) - 1:
                        del expected_active[port]
                    else:
                        expected_active[port][2] += 1
                else:
                    self.assertIsNone(outgoing.data)
                monitor.step(outgoing.request, outgoing.data)
                retired = tuple(token for due, token in held if due == cycle)
                held = [(due, token) for due, token in held if due != cycle]
                # One metadata-homogeneous batch per port/channel; no TDM gate.
                selected = {}
                for token in receiver.returnable:
                    original = metadata[token]
                    slot = original.port, original.channel
                    if slot not in selected:
                        selected[slot] = [token]
                    elif metadata[selected[slot][0]] == original and len(selected[slot]) < 4:
                        selected[slot].append(token)
                batches = tuple(tuple(group) for group in selected.values())
                expected_returns = []
                for batch in batches:
                    original = metadata[batch[0]]
                    expected_returns.append(CreditReturn(original.port, original.channel, original.vc,
                                                         original.pool, len(batch) - 1))
                    batch_sizes.add(len(batch))
                received = receiver.step(self.connected, beats=outgoing.beats, retire=retired, batches=batches)
                self.assertEqual(received.returns, tuple(expected_returns))
                for token, original in zip(received.receipts, outgoing.beats):
                    metadata[token] = original
                    held.append((cycle + rng.randint(1, 5), token))
                for batch in batches:
                    for token in batch:
                        del metadata[token]
                flights.extend((cycle + 2, grant) for grant in received.returns)
                for account, capacity in capacities.items():
                    in_flight = sum(g.encoded_count + 1 for _, g in flights
                                    if Account(g.port, g.channel, None if g.pool else g.vc) == account)
                    self.assertEqual(sender.balance(account) + receiver.occupancy(account) + in_flight, capacity)
                    self.assertEqual(sender.available(account) + sender.reserved(account), sender.balance(account))
                    self.assertGreaterEqual(sender.available(account), 0)
                if not any(candidates.values()) and not expected_active and not held and not flights and not metadata:
                    break
            else:
                self.fail("finite, fairly retired workload did not drain")
            self.assertEqual(requests_seen, 192 * ports)
            self.assertEqual(data_seen, 240 * ports)
            self.assertGreaterEqual(len(batch_sizes), 2)
            self.assertTrue(all(sender.balance(a) == 4 for a in capacities))
            self.observed_modes.append({"ports": ports, "cycles_including_drain": cycle + 1,
                                        "requests": requests_seen, "data_beats": data_seen,
                                        "observed_batch_sizes": sorted(batch_sizes)})


if __name__ == "__main__":
    unittest.main()
