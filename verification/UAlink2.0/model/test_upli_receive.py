"""Independent receive-channel contracts, including literal credit conservation."""

from collections import deque
import random
import unittest

from model.ualink.upli_connection import ConnectionSignals
from model.ualink.upli_credit import Account, Beat, CHANNELS, UpliCreditLedger
from model.ualink.upli_receive import ReceivedBeat, UpliReceiveChannel


CONNECTED = ConnectionSignals(True, True, True, True)


def initialized(capacities, ports=1, **options):
    receiver = UpliReceiveChannel(capacities, ports, **options)
    for _ in range(sum(capacities) + 20):
        receiver.step(CONNECTED)
        if receiver.outputs.done == (1 << ports)-1:
            return receiver
    raise AssertionError("initial credit publication did not finish")


class ReceiveChannelTests(unittest.TestCase):
    def test_parameter_contract_and_zero_storage(self):
        for ports in (1, 2, 4):
            receiver = initialized([0]*(ports*5), ports)
            self.assertEqual(receiver.outputs.counts, (0,)*(ports*5))
            self.assertEqual(receiver.outputs.pending, (0,)*ports)
            for port in range(4):
                for account in range(8):
                    self.assertIsNone(receiver.peek(port, account).received)
                    self.assertFalse(receiver.peek(port, account).ready)
        for capacities, ports, options, error in (
            ([1]*5, 3, {}, ValueError), ([1]*4, 1, {}, ValueError),
            ([True]*5, 1, {}, TypeError), ([-1]*5, 1, {}, ValueError),
            ([65536]*5, 1, {"credit_width": 16}, ValueError),
            ([16]*5, 1, {}, ValueError), ([1]*5, True, {}, TypeError),
            ([1]*5, 1, {"payload_width": 0}, ValueError),
            ([1]*5, 1, {"payload_width": True}, TypeError),
            ([1]*5, 1, {"return_depth": 17}, ValueError),
            ([1]*5, 1, {"channel": "invalid"}, ValueError),
        ):
            with self.subTest(options=options, ports=ports, capacities=capacities):
                with self.assertRaises(error):
                    UpliReceiveChannel(capacities, ports, **options)

    def test_initial_capacities_exact_and_independent_ports(self):
        capacities = (0, 0, 0, 0, 3, 9, 2, 0, 0, 0)
        receiver = UpliReceiveChannel(capacities, 2)
        totals, last_grant, first_done = [0]*10, [-1]*2, [None]*2
        for cycle in range(30):
            receiver.step(CONNECTED)
            for grant in receiver.outputs.returns:
                totals[5*grant.port + (4 if grant.pool else grant.vc)] += grant.encoded_count+1
                last_grant[grant.port] = cycle
                self.assertIsNone(first_done[grant.port])
            for port in range(2):
                if receiver.outputs.done & (1 << port) and first_done[port] is None:
                    first_done[port] = cycle
                    self.assertGreater(cycle, last_grant[port])
        self.assertEqual(tuple(totals), capacities)
        self.assertLess(first_done[0], first_done[1])

    def test_direction_first_all_channels_and_no_ingress_ready(self):
        for channel in CHANNELS:
            with self.subTest(channel=channel):
                receiver = UpliReceiveChannel([2, 0, 0, 0, 0], 1, channel=channel)
                only_return = (ConnectionSignals(False, False, True, True)
                               if channel in ("req", "orig_data")
                               else ConnectionSignals(True, True, False, False))
                item = ReceivedBeat(Beat(0, channel, 0), 0x53)
                for _ in range(10):
                    result = receiver.step(only_return, incoming=item)
                    self.assertEqual(result.diagnostic, 2)
                    self.assertFalse(result.accepted)
                self.assertEqual(receiver.outputs.done, 1)
                self.assertEqual(receiver.outputs.counts[0], 0)
                self.assertTrue(receiver.step(CONNECTED, incoming=item).accepted)

    def test_one_port_returns_normally_while_other_port_still_initializes(self):
        receiver = UpliReceiveChannel([0, 0, 0, 0, 1, 63, 0, 0, 0, 0], 2, credit_width=6)
        for _ in range(6):
            receiver.step(CONNECTED)
        self.assertEqual(receiver.outputs.done, 1)
        item = ReceivedBeat(Beat(0, "req", 3, True), 0x53)
        receiver.step(CONNECTED, incoming=item)
        receiver.step(CONNECTED)
        receiver.step(CONNECTED)
        self.assertEqual(receiver.step(CONNECTED, consumer=(0, 4), consume=True).retired, item)
        receiver.step(CONNECTED)
        grants = receiver.outputs.returns
        self.assertEqual([(grant.port, grant.vc, grant.pool, grant.encoded_count) for grant in grants],
                         [(0, 3, True, 0), (1, 0, False, 3)])
        self.assertEqual(receiver.outputs.done, 1)

    def test_early_ingress_and_zero_capacity_are_diagnostic_not_credit(self):
        receiver = UpliReceiveChannel([1, 0, 0, 0, 0], 1)
        item = ReceivedBeat(Beat(0, "req", 0), 3)
        self.assertEqual(receiver.step(CONNECTED, incoming=item).diagnostic, 3)
        for _ in range(10):
            receiver.step(CONNECTED)
        self.assertEqual(receiver.step(CONNECTED, incoming=ReceivedBeat(Beat(0, "req", 1), 5)).diagnostic, 4)
        self.assertEqual(receiver.step(CONNECTED, incoming=ReceivedBeat(Beat(3, "req", 0), 7)).diagnostic, 1)
        self.assertEqual(receiver.outputs.counts, (0,)*5)

    def test_literal_sram_latency_pool_metadata_and_padding(self):
        receiver = initialized([0, 0, 0, 0, 3], payload_width=13)
        item = ReceivedBeat(Beat(0, "req", 3, True), 0x1353)
        self.assertEqual(receiver.storage_width, 16)
        self.assertTrue(receiver.step(CONNECTED, incoming=item).accepted)
        self.assertIsNone(receiver.peek(0, 4).received)
        receiver.step(CONNECTED)
        self.assertIsNone(receiver.peek(0, 4).received)
        receiver.step(CONNECTED)
        self.assertEqual(receiver.peek(0, 4).received, item)
        self.assertTrue(receiver.peek(0, 4).ready)
        result = receiver.step(CONNECTED, consumer=(0, 4), consume=True)
        self.assertEqual(result.retired, item)
        self.assertEqual(receiver.outputs.counts, (0,)*5)
        self.assertEqual(receiver.outputs.pending, (1,))
        self.assertEqual(receiver.outputs.returns, ())
        receiver.step(CONNECTED)
        grant, = receiver.outputs.returns
        self.assertEqual((grant.vc, grant.pool, grant.encoded_count), (3, True, 0))

    def test_full_does_not_borrow_same_edge_consumer_capacity(self):
        receiver = initialized([1, 0, 0, 0, 0])
        first, second = (ReceivedBeat(Beat(0, "req", 0), value) for value in (11, 22))
        receiver.step(CONNECTED, incoming=first)
        receiver.step(CONNECTED)
        receiver.step(CONNECTED)
        result = receiver.step(CONNECTED, incoming=second, consumer=(0, 0), consume=True)
        self.assertFalse(result.accepted)
        self.assertEqual(result.diagnostic, 4)
        self.assertEqual(result.retired, first)
        self.assertTrue(receiver.step(CONNECTED, incoming=second).accepted)

    def test_return_queue_backpressure_keeps_payload_and_original_metadata(self):
        receiver = initialized([0, 0, 0, 0, 3], return_depth=1)
        items = [ReceivedBeat(Beat(0, "req", vc, True), 100+vc) for vc in (2, 1, 3)]
        for item in items:
            receiver.step(CONNECTED, incoming=item)
        for _ in range(3):
            receiver.step(CONNECTED)
        self.assertEqual(receiver.step(CONNECTED, consumer=(0, 4), consume=True).retired, items[0])
        self.assertEqual(receiver.peek(0, 4).received, items[1])
        self.assertFalse(receiver.peek(0, 4).ready)
        self.assertIsNone(receiver.step(CONNECTED, consumer=(0, 4), consume=True).retired)
        self.assertEqual(receiver.outputs.counts[4], 2)
        self.assertEqual(receiver.outputs.returns[0].vc, 2)
        self.assertEqual(receiver.step(CONNECTED, consumer=(0, 4), consume=True).retired, items[1])
        self.assertEqual(receiver.peek(0, 4).received, items[2])

    def test_nonuniform_account_order_and_pool_accepts_every_vc(self):
        receiver = initialized([3, 2, 0, 1, 5]*2, 2)
        expected = {(port, account): deque() for port in range(2) for account in range(5)}
        for port in range(2):
            for vc, pool in ((3, False), (0, False), (1, False), (0, True), (1, True), (2, True), (3, True)):
                item = ReceivedBeat(Beat(port, "req", vc, pool), port*100+len(expected[port, 4])+vc)
                self.assertTrue(receiver.step(CONNECTED, incoming=item).accepted)
                expected[port, 4 if pool else vc].append(item)
        for _ in range(4):
            receiver.step(CONNECTED)
        for port, account in reversed(tuple(expected)):
            while expected[port, account]:
                result = receiver.step(CONNECTED, consumer=(port, account), consume=True)
                if result.retired is not None:
                    self.assertEqual(result.retired, expected[port, account].popleft())
        self.assertEqual(receiver.outputs.counts, (0,)*10)

    def test_input_validation_is_atomic_and_reset_overrides(self):
        receiver = initialized([2]*5)
        for kwargs, error in (
            ({"incoming": 1}, TypeError),
            ({"incoming": ReceivedBeat(Beat(0, "req", 0), True)}, TypeError),
            ({"incoming": ReceivedBeat(Beat(0, "req", 0), 1 << 32)}, ValueError),
            ({"incoming": ReceivedBeat(Beat(4, "req", 0), 1)}, ValueError),
            ({"incoming": ReceivedBeat(Beat(0, "req", 4), 1)}, ValueError),
            ({"incoming": ReceivedBeat(Beat(0, "rd_rsp", 0), 1)}, ValueError),
            ({"incoming": ReceivedBeat(Beat(0, "req", 0, 1), 1)}, TypeError),
            ({"consumer": (0, 8)}, ValueError), ({"consumer": (True, 0)}, TypeError),
            ({"consume": 1}, TypeError), ({"reset": 1}, TypeError),
        ):
            before = receiver.outputs
            with self.subTest(kwargs=kwargs), self.assertRaises(error):
                receiver.step(CONNECTED, **kwargs)
            self.assertEqual(receiver.outputs, before)
        before = receiver.outputs
        with self.assertRaises(ValueError):
            receiver.step(ConnectionSignals(True, True, False, True))
        self.assertEqual(receiver.outputs, before)
        result = receiver.step(None, incoming=object(), consumer="bad", consume=7, reset=True)
        self.assertFalse(result.accepted)
        self.assertEqual(receiver.outputs.done, 0)
        self.assertEqual(receiver.outputs.returns, ())

    def test_reset_clears_unread_pending_cache_and_registered_returns(self):
        for delay in range(6):
            receiver = initialized([3]*5)
            receiver.step(CONNECTED, incoming=ReceivedBeat(Beat(0, "req", 2), 0xCAFE))
            for _ in range(delay):
                receiver.step(CONNECTED, consumer=(0, 2), consume=True)
            receiver.step(None, reset=True)
            for _ in range(12):
                receiver.step(CONNECTED, consumer=(0, 2), consume=True)
                self.assertEqual(receiver.outputs.counts, (0,)*5)
                self.assertEqual(receiver.outputs.pending, (0,))
                self.assertIsNone(receiver.peek(0, 2).received)

    def test_independent_sender_ledger_and_payload_scoreboard(self):
        for ports in (1, 2, 4):
            for channel in CHANNELS:
                with self.subTest(ports=ports, channel=channel):
                    self._exercise_closed_loop(ports, channel)

    def _exercise_closed_loop(self, ports, channel):
        rng = random.Random(6100+ports+CHANNELS.index(channel))
        capacities = tuple((port+account*2) % 6 for port in range(ports) for account in range(5))
        accounts = [Account(port, channel, None if account == 4 else account)
                    for port in range(ports) for account in range(5)]
        receiver = UpliReceiveChannel(capacities, ports, return_depth=1, channel=channel)
        sender = UpliCreditLedger(dict(zip(accounts, capacities)), ports)
        for _ in range(25):
            signals = receiver.outputs
            sender.step(CONNECTED, returns=signals.returns,
                        init_done=[(port, channel) for port in range(ports) if signals.done & (1 << port)])
            receiver.step(CONNECTED)
        self.assertEqual([sender.balance(account) for account in accounts], list(capacities))
        saved, owed = [deque() for _ in capacities], [deque() for _ in range(ports)]
        accepted = retired = 0
        for cycle in range(1600):
            for grant in receiver.outputs.returns:
                for _ in range(grant.encoded_count+1):
                    self.assertEqual(owed[grant.port].popleft(), Beat(grant.port, channel, grant.vc, grant.pool))
            incoming = None
            if cycle < 1000 and rng.randrange(4):
                slot = rng.randrange(len(accounts))
                account = accounts[slot]
                if sender.balance(account):
                    incoming = ReceivedBeat(Beat(account.port, channel, rng.randrange(4) if account.vc is None else account.vc,
                                                 account.vc is None), cycle+1)
            selected = rng.randrange(len(accounts)) if cycle < 1000 else (cycle-1000) % len(accounts)
            consumer = divmod(selected, 5)
            sender.step(CONNECTED, returns=receiver.outputs.returns,
                        beats=() if incoming is None else (incoming.beat,))
            result = receiver.step(CONNECTED, incoming, consumer, cycle >= 1000 or bool(rng.randrange(3)))
            self.assertEqual(result.diagnostic, 0)
            if result.retired is not None:
                self.assertEqual(saved[selected].popleft(), result.retired)
                owed[result.retired.beat.port].append(result.retired.beat)
                retired += 1
            if incoming is not None:
                self.assertTrue(result.accepted)
                beat = incoming.beat
                saved[5*beat.port + (4 if beat.pool else beat.vc)].append(incoming)
                accepted += 1
            self.assertEqual(receiver.outputs.counts, tuple(map(len, saved)))
            for slot, account in enumerate(accounts):
                pending = sum((None if beat.pool else beat.vc) == account.vc for beat in owed[account.port])
                self.assertEqual(sender.balance(account)+len(saved[slot])+pending, capacities[slot])
        self.assertGreater(accepted, 50)
        self.assertEqual(accepted, retired)
        self.assertTrue(all(not items for items in owed))
        self.assertEqual([sender.balance(account) for account in accounts], list(capacities))


if __name__ == "__main__":
    unittest.main()
