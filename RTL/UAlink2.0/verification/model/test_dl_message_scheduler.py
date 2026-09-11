"""Independent source-order and ownership tests for the DL scheduling model."""
import importlib
import unittest


# Literal normative catalog: independent of the model's lookup tables.
SOURCES = ((0, 0), (0, 1), (0, 4), (0, 5), (0, 6), (8, 0), (8, 4), (1, 0), (1, 1), (1, 6), (1, 7))


class DLMessageSchedulerTests(unittest.TestCase):
    def setUp(self):
        try:
            self.api = importlib.import_module("model.ualink.dl_message_scheduler")
        except ModuleNotFoundError:
            self.fail("DL message scheduler implementation is missing")
        self.arbiter = self.api.DLMessageArbiter()

    def message(self, source, tag="", words=None):
        if words is None:
            words = (0xA0, 0xA1) if source == (1, 0) else (0xB0,)
        return self.api.Message(source, words, tag)

    def test_two_level_order_not_flat_source_priority(self):
        for source in SOURCES:
            self.assertTrue(self.arbiter.offer(self.message(source)))
        expected = ((0, 0), (8, 0), (1, 0), (1, 0), (0, 1), (8, 4),
                    (1, 1), (0, 4), (1, 6), (0, 5), (1, 7), (0, 6))
        actual = tuple(self.arbiter.tick().source for _ in expected)
        self.assertEqual(actual, expected)
        self.assertIsNone(self.arbiter.tick())

    def test_uart_transport_locks_all_other_message_sources(self):
        words = tuple(range(33))
        self.assertTrue(self.arbiter.offer(self.message((1, 0), "transport", words)))
        first = self.arbiter.tick()
        self.assertEqual((first.source, first.word, first.index, first.last), ((1, 0), 0, 0, False))
        for source in ((0, 4), (8, 4), (1, 1), (1, 6), (1, 7)):
            self.assertTrue(self.arbiter.offer(self.message(source, "arrived_during_transport")))
        for index in range(1, 33):
            beat = self.arbiter.tick()
            self.assertEqual((beat.source, beat.word, beat.index, beat.last, beat.tag),
                             ((1, 0), index, index, index == 32, "transport"))
        self.assertEqual(self.arbiter.tick().source, (0, 4))
        self.assertEqual(self.arbiter.tick().source, (8, 4))
        self.assertEqual(self.arbiter.tick().source, (1, 1))

    def test_continuously_pending_sources_have_group_and_local_fairness(self):
        for source in SOURCES:
            self.assertTrue(self.arbiter.offer(self.message(source)))
        completions = dict.fromkeys(SOURCES, 0)
        opportunities = 0
        while sum(completions.values()) < 60 and opportunities < 100:
            beat = self.arbiter.tick()
            self.assertIsNotNone(beat)
            opportunities += 1
            if beat.last:
                completions[beat.source] += 1
                self.assertTrue(self.arbiter.offer(self.message(beat.source)))
        self.assertEqual(opportunities, 65)
        self.assertEqual(completions, {(0, 0): 4, (0, 1): 4, (0, 4): 4, (0, 5): 4, (0, 6): 4,
                                      (8, 0): 10, (8, 4): 10, (1, 0): 5, (1, 1): 5, (1, 6): 5, (1, 7): 5})

    def test_no_segment_opportunity_does_not_consume_or_rotate(self):
        for source in ((0, 4), (8, 4), (1, 0)):
            self.assertTrue(self.arbiter.offer(self.message(source)))
        for _ in range(7):
            self.assertIsNone(self.arbiter.tick(segment_available=False))
        self.assertEqual(self.arbiter.pending(), 3)
        self.assertEqual(self.arbiter.tick().source, (0, 4))
        self.assertEqual(self.arbiter.tick().source, (8, 4))
        self.assertEqual(self.arbiter.tick().index, 0)
        for _ in range(7):
            self.assertIsNone(self.arbiter.tick(segment_available=False))
        final = self.arbiter.tick()
        self.assertEqual((final.source, final.index, final.last), ((1, 0), 1, True))

    def test_reset_discards_active_and_waiting_messages_and_restarts_priority(self):
        self.assertTrue(self.arbiter.offer(self.message((1, 0))))
        self.arbiter.tick()
        self.assertTrue(self.arbiter.offer(self.message((8, 4))))
        self.assertIsNone(self.arbiter.tick(segment_available=False, reset=True))
        self.assertEqual(self.arbiter.pending(), 0)
        self.assertIsNone(self.arbiter.tick())
        self.assertTrue(self.arbiter.offer(self.message((1, 1))))
        self.assertTrue(self.arbiter.offer(self.message((0, 4))))
        self.assertEqual(self.arbiter.tick().source, (0, 4))

    def test_queue_capacity_counts_active_message_and_preserves_rejected_offer(self):
        arbiter = self.api.DLMessageArbiter(queue_depth=1)
        self.assertTrue(arbiter.offer(self.message((1, 0), "first")))
        arbiter.tick()
        self.assertFalse(arbiter.offer(self.message((1, 0), "rejected")))
        self.assertEqual(arbiter.pending((1, 0)), 1)
        self.assertEqual(arbiter.tick().tag, "first")
        self.assertIsNone(arbiter.tick())
        self.assertTrue(arbiter.offer(self.message((1, 0), "second")))
        self.assertEqual(arbiter.tick().tag, "second")

    def test_payload_is_immutable_after_offer(self):
        words = [0x12345678, 0xDEADBEEF]
        message = self.message((1, 0), "owned", words)
        self.assertTrue(self.arbiter.offer(message))
        words[:] = [0, 0, 0]
        self.assertEqual(self.arbiter.tick().word, 0x12345678)
        self.assertEqual(self.arbiter.tick().word, 0xDEADBEEF)
        self.assertEqual(self.arbiter.pending(), 0)

    def test_empty_scheduler_does_not_invent_noop_messages(self):
        for _ in range(20):
            self.assertIsNone(self.arbiter.tick())
        self.assertEqual(self.arbiter.pending(), 0)

    def test_reject_reserved_source_and_bad_word_width(self):
        for source in ((0, 2), (8, 1), (1, 4), (2, 0), (True, 0), (0, False), (0,), "basic"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                self.message(source, words=(0,))
        for word in (-1, 1 << 32, True, 1.5, "word"):
            with self.subTest(word=word), self.assertRaises(ValueError):
                self.message((0, 4), words=(word,))
        self.assertEqual(self.message((0, 4), words=(0xFFFFFFFF,)).words, (0xFFFFFFFF,))

    def test_only_uart_transport_can_span_words_and_has_two_to_thirty_three(self):
        for source in SOURCES:
            if source != (1, 0):
                with self.subTest(source=source), self.assertRaises(ValueError):
                    self.message(source, words=(0, 1))
        for words in ((), (0,), tuple(range(34))):
            with self.subTest(length=len(words)), self.assertRaises(ValueError):
                self.message((1, 0), words=words)
        self.assertEqual(len(self.message((1, 0), words=tuple(range(33))).words), 33)

    def test_reject_invalid_queue_depth_and_control_arguments(self):
        for depth in (0, -1, True, 1.5):
            with self.subTest(depth=depth), self.assertRaises(ValueError):
                self.api.DLMessageArbiter(queue_depth=depth)
        for argument in (0, 1, None, "yes"):
            with self.subTest(argument=argument), self.assertRaises(ValueError):
                self.arbiter.tick(segment_available=argument)
        with self.assertRaises(ValueError):
            self.arbiter.tick(reset=1)

    def test_same_source_messages_keep_fifo_order(self):
        for tag in ("a", "b"):
            self.assertTrue(self.arbiter.offer(self.message((0, 4), tag)))
        self.assertFalse(self.arbiter.offer(self.message((0, 4), "full")))
        self.assertEqual(self.arbiter.tick().tag, "a")
        self.assertTrue(self.arbiter.offer(self.message((0, 4), "c")))
        self.assertEqual([self.arbiter.tick().tag, self.arbiter.tick().tag], ["b", "c"])


if __name__ == "__main__":
    unittest.main()
