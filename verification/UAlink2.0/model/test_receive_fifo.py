"""Independent FIFO behavior tests; no access to implementation-private state."""

import importlib.util
import random
import unittest
from collections import deque

if importlib.util.find_spec("model.ualink.receive_fifo") is not None:
    from model.ualink.receive_fifo import ReceiveFifo
else:
    ReceiveFifo = None


class ReceiveFifoTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(ReceiveFifo, "ReceiveFifo model has not been implemented")

    def test_sram_read_latency_has_no_incoming_bypass(self):
        # An early bypass or an extra read-result delay breaks these literal views.
        fifo = ReceiveFifo(5, 8)
        self.assertTrue(fifo.step(0x53).accepted)
        self.assertEqual((fifo.outputs.valid, fifo.outputs.data, fifo.outputs.count), (False, 0, 1))
        fifo.step()
        self.assertEqual((fifo.outputs.valid, fifo.outputs.data, fifo.outputs.count), (False, 0, 1))
        fifo.step()
        self.assertEqual((fifo.outputs.valid, fifo.outputs.data, fifo.outputs.count), (True, 0x53, 1))
        self.assertEqual(fifo.step(consume=True).consumed, 0x53)
        self.assertEqual((fifo.outputs.ready, fifo.outputs.valid, fifo.outputs.data, fifo.outputs.count), (True, False, 0, 0))

    def test_capacity_includes_pending_and_visible_words(self):
        # Counting only SRAM-resident words would accept an extra word.
        for depth in (1, 2, 3, 5, 16, 256, 257, 513, 1025, 2049):
            with self.subTest(depth=depth):
                fifo = ReceiveFifo(depth)
                for value in range(depth):
                    self.assertTrue(fifo.step(value).accepted)
                self.assertFalse(fifo.outputs.ready)
                self.assertFalse(fifo.step(99999).accepted)
                for _ in range(5):
                    fifo.step()
                    self.assertEqual((fifo.outputs.ready, fifo.outputs.count), (False, depth))

    def test_full_queue_cannot_borrow_same_edge_consumption(self):
        fifo = ReceiveFifo(1)
        fifo.step(0x31)
        fifo.step()
        fifo.step()
        event = fifo.step(0x92, consume=True)
        self.assertEqual((event.accepted, event.consumed, fifo.outputs.count), (False, 0x31, 0))
        self.assertTrue(fifo.step(0x92).accepted)
        fifo.step()
        fifo.step()
        self.assertEqual(fifo.step(consume=True).consumed, 0x92)

    def test_backpressure_preserves_head_and_fifo_order(self):
        fifo = ReceiveFifo(5)
        for value in (0x57, 0x13, 0x88, 0x42, 0x65):
            fifo.step(value)
        for _ in range(100):
            fifo.step()
            self.assertEqual((fifo.outputs.data, fifo.outputs.count), (0x57, 5))
        got = []
        for _ in range(16):
            event = fifo.step(consume=True)
            if event.consumed is not None:
                got.append(event.consumed)
        self.assertEqual(got, [0x57, 0x13, 0x88, 0x42, 0x65])

    def test_two_cache_slots_sustain_one_read_each_cycle(self):
        # Serializing request and result would introduce gaps after the cache drains.
        fifo = ReceiveFifo(16)
        for value in range(16):
            fifo.step(value)
        for _ in range(4):
            fifo.step()
        for value in range(16):
            self.assertTrue(fifo.outputs.valid)
            self.assertEqual(fifo.step(consume=True).consumed, value)
        self.assertFalse(fifo.outputs.valid)

    def test_steady_reads_and_writes_are_both_one_word_per_cycle(self):
        # A hidden every-other-cycle read bubble breaks literal consecutive words.
        for depth in (4, 5, 16):
            fifo = ReceiveFifo(depth)
            for word in range(depth):
                fifo.step(word)
            for _ in range(4):
                fifo.step()
            first = fifo.step(depth, consume=True)
            self.assertEqual((first.accepted, first.consumed), (False, 0))
            for word in range(1, 257):
                event = fifo.step(word+depth-1, consume=True)
                self.assertEqual((event.accepted, event.consumed, fifo.outputs.count), (True, word, depth-1))

    def test_simultaneous_write_read_does_not_replace_old_head(self):
        fifo = ReceiveFifo(5)
        for word in (31, 72, 46):
            fifo.step(word)
        event = fifo.step(91, consume=True)
        self.assertEqual((event.accepted, event.consumed, fifo.outputs.count), (True, 31, 3))
        observed = []
        for _ in range(10):
            result = fifo.step(consume=True)
            if result.consumed is not None:
                observed.append(result.consumed)
        self.assertEqual(observed, [72, 46, 91])

    def test_reset_cancels_unread_pending_and_cached_data(self):
        for wait in range(5):
            fifo = ReceiveFifo(3)
            fifo.step(0xDEAD)
            for _ in range(wait):
                fifo.step()
            event = fifo.step(data="ignored", consume="ignored", reset=True)
            self.assertEqual((event.accepted, event.consumed), (False, None))
            for _ in range(6):
                self.assertIsNone(fifo.step(consume=True).consumed)
                self.assertEqual((fifo.outputs.count, fifo.outputs.data), (0, 0))
            fifo.step(0xBEEF)
            fifo.step()
            fifo.step()
            self.assertEqual(fifo.step(consume=True).consumed, 0xBEEF)

    def test_random_transfers_conserve_external_scoreboard(self):
        for depth in (1, 2, 3, 5, 16, 257, 2049):
            fifo = ReceiveFifo(depth, 40)
            rng, expected = random.Random(0x52584651+depth), deque()
            for cycle in range(4000):
                data = rng.getrandbits(40) if rng.randrange(5) else None
                consume, reset = bool(rng.randrange(2)), cycle % 521 == 0
                before = fifo.outputs
                event = fifo.step(data, consume, reset)
                if reset:
                    expected.clear()
                    self.assertFalse(event.accepted)
                    self.assertIsNone(event.consumed)
                else:
                    self.assertEqual(event.accepted, data is not None and before.ready)
                    self.assertEqual(event.consumed, before.data if consume and before.valid else None)
                    if event.consumed is not None:
                        self.assertEqual(event.consumed, expected.popleft())
                    if event.accepted:
                        expected.append(data)
                self.assertEqual(fifo.outputs.count, len(expected))
            for _ in range(depth+8):
                event = fifo.step(consume=True)
                if event.consumed is not None:
                    self.assertEqual(event.consumed, expected.popleft())
            self.assertEqual((len(expected), fifo.outputs.count), (0, 0))

    def test_invalid_input_does_not_corrupt_pending_word(self):
        fifo = ReceiveFifo(3, 8)
        fifo.step(0x6D)
        for bad in ({"data":-1}, {"data":256}, {"data":True}, {"consume":1}, {"reset":1}):
            before = fifo.outputs
            with self.assertRaises((TypeError, ValueError)):
                fifo.step(**bad)
            self.assertEqual(fifo.outputs, before)
        fifo.step()
        fifo.step()
        self.assertEqual(fifo.step(consume=True).consumed, 0x6D)

    def test_illegal_shape_cannot_silently_change_capacity(self):
        for depth, width in ((0, 8), (65536, 8), (-1, 8), (True, 8), (3, 0), (3, 7), (3, 17), (3, True)):
            with self.subTest(depth=depth, width=width), self.assertRaises((TypeError, ValueError)):
                ReceiveFifo(depth, width)
        fifo = ReceiveFifo(65535, 520)
        self.assertTrue(fifo.step((1 << 520)-1).accepted)
        fifo.step()
        fifo.step()
        self.assertEqual(fifo.step(consume=True).consumed, (1 << 520)-1)


if __name__ == "__main__":
    unittest.main()
