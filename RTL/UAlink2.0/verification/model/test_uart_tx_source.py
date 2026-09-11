"""Reservation and actual DWORD ownership tests for the UART TX source.

Run: python3 -m unittest verification.model.test_uart_tx_source -v
Outputs: directed and integrated model test results.
Next: compare RTL vectors and prove the complete staged-state relation.
"""
from collections import deque
import random
import unittest

from model.ualink.dl_message_scheduler import DLMessageArbiter, Message
from model.ualink.uart_credit import UARTStreamFlowControl
from model.ualink.uart_tx_source import UARTTxSource


def staged(words, credit=None):
    source = UARTTxSource()
    source.tick(credit_valid=True, credit_value=len(words) if credit is None else credit)
    source.tick(payload_fill=len(words))
    for word in words:
        source.tick(payload_valid=True, payload_word=word)
    return source


def drain(source):
    words = []
    while source.observe().pending:
        out = source.tick(take=True)
        words.append(out.word)
    return words


class UARTTxSourceTests(unittest.TestCase):
    def test_empty_initial_state_and_one_edge_credit_visibility(self):
        source = UARTTxSource()
        self.assertFalse(source.observe().busy)
        source.tick(payload_fill=9, credit_valid=True, credit_value=5)
        self.assertFalse(source.observe().busy)
        source.tick(payload_fill=9)
        self.assertEqual(source.observe().reserved_words, 5)
        self.assertTrue(source.observe().payload_ready)
        self.assertFalse(source.observe().pending)

    def test_all_payload_is_staged_before_header(self):
        source = UARTTxSource()
        source.tick(credit_valid=True, credit_value=32)
        source.tick(payload_fill=32)
        for index in range(32):
            for _ in range(index % 3):
                source.tick(payload_fill=0)
                self.assertFalse(source.observe().pending)
            out = source.tick(payload_valid=True, payload_word=0x1000+index)
            self.assertTrue(out.payload_ready)
            self.assertFalse(out.pending)
            self.assertEqual(source.observe().staged_words, index+1)
        self.assertTrue(source.observe().pending)
        self.assertFalse(source.observe().payload_ready)
        self.assertEqual(source.observe().word, 0xF8000004)
        self.assertEqual(source.observe().word_count, 33)
        self.assertEqual(drain(source), [0xF8000004]+list(range(0x1000, 0x1020)))
        self.assertEqual(source.observe().tx_counter, 32)

    def test_header_does_not_release_storage_or_charge_credit(self):
        source = staged([0xDEADBEEF])
        out = source.tick(take=True)
        self.assertEqual((out.word, out.word_index, out.word_count), (4, 0, 2))
        self.assertFalse(out.done)
        self.assertEqual((source.observe().staged_words, source.observe().tx_counter), (1, 0))
        out = source.tick(take=True)
        self.assertEqual((out.word, out.word_index), (0xDEADBEEF, 1))
        self.assertTrue(out.done)
        self.assertEqual((source.observe().busy, source.observe().staged_words,
                          source.observe().reserved_words, source.observe().tx_counter), (False, 0, 0, 1))

    def test_reserved_length_survives_new_updates_and_fill_changes(self):
        source = UARTTxSource()
        source.tick(credit_valid=True, credit_value=2)
        source.tick(payload_fill=99)
        source.tick(payload_valid=True, payload_word=10, credit_valid=True, credit_value=200)
        source.tick(payload_valid=True, payload_word=11, payload_fill=4095)
        for _ in range(4):
            source.tick(payload_valid=True, payload_word=99, payload_fill=4095)
            self.assertEqual(source.observe().reserved_words, 2)
            self.assertFalse(source.observe().payload_ready)
        self.assertEqual(drain(source), [0x08000004, 10, 11])
        source.tick(payload_fill=1)
        self.assertEqual(source.observe().reserved_words, 1)

    def test_disabled_before_header_and_active_fault_pause(self):
        source = staged([10, 11])
        snapshot = source.observe()
        self.assertFalse(source.observe(enabled=False).pending)
        self.assertFalse(source.observe(enabled=False).error)
        source.tick(enabled=False, take=True)
        self.assertEqual(source.observe(), snapshot)
        source.tick(take=True)
        before = source.observe()
        for _ in range(3):
            out = source.tick(enabled=False, take=True)
            self.assertTrue(out.error)
            self.assertFalse(out.pending)
            self.assertEqual((out.word, out.word_count, out.word_index), (0, 0, 0))
        self.assertEqual(source.observe(), before)
        self.assertEqual(drain(source), [10, 11])

    def test_disabled_staging_retains_credit_and_payload(self):
        source = UARTTxSource()
        source.tick(credit_valid=True, credit_value=3)
        source.tick(payload_fill=3)
        source.tick(payload_valid=True, payload_word=1)
        out = source.tick(enabled=False, payload_valid=True, payload_word=99)
        self.assertFalse(out.payload_ready)
        self.assertEqual(source.observe().staged_words, 1)
        source.tick(payload_valid=True, payload_word=2)
        source.tick(payload_valid=True, payload_word=3)
        self.assertEqual(drain(source), [0x10000004, 1, 2, 3])

    def test_reset_in_staging_and_after_every_message_word(self):
        for words_taken in range(5):
            source = staged([1, 2, 3])
            for _ in range(words_taken):
                source.tick(take=True)
            out = source.tick(reset=True, take=True, payload_valid=True,
                              payload_word=99, credit_valid=True, credit_value=200)
            self.assertFalse(any(vars(out).values()))
            self.assertFalse(any(vars(source.observe()).values()))
            source.tick(payload_fill=99)
            self.assertFalse(source.observe().busy)
        source = UARTTxSource()
        source.tick(credit_valid=True, credit_value=5)
        source.tick(payload_fill=5)
        source.tick(payload_valid=True, payload_word=7)
        source.tick(reset=True)
        self.assertFalse(source.observe().busy)
        self.assertEqual(source.observe().staged_words, 0)

    def test_invalid_take_does_not_consume_but_other_events_proceed(self):
        source = UARTTxSource()
        out = source.tick(take=True, credit_valid=True, credit_value=2)
        self.assertTrue(out.error)
        self.assertEqual(source.observe().latest_fc, 2)
        source.tick(payload_fill=2)
        out = source.tick(take=True, payload_valid=True, payload_word=5)
        self.assertTrue(out.error)
        self.assertEqual(source.observe().staged_words, 1)
        self.assertEqual(source.observe().tx_counter, 0)
        source.tick(payload_valid=True, payload_word=6)
        self.assertEqual(drain(source), [0x08000004, 5, 6])

    def test_boundaries_and_counter_wrap_match_whole_message_reference(self):
        rng = random.Random(17)
        source = UARTTxSource()
        reference = UARTStreamFlowControl(tx_depth=128)
        reference.release_reset()
        reference.set_channel4_enabled(True)
        sent = 0
        next_word = 0
        fifo = deque()
        for _ in range(500):
            for _ in range(rng.randrange(1, 65)):
                if reference.write(next_word):
                    fifo.append(next_word)
                    next_word += 1
            fill = len(fifo)
            credits = rng.randrange(1, 65)
            fc = (sent+credits) % 4096
            source.tick(credit_valid=True, credit_value=fc)
            reference.apply_credit_update(fc)
            source.tick(payload_fill=fill)
            count = min(fill, credits, 32)
            self.assertEqual(source.observe().reserved_words, count)
            for _ in range(count):
                source.tick(payload_valid=True, payload_word=fifo.popleft())
            actual = drain(source)
            expected = reference.transmit()
            self.assertEqual(actual, [(expected.length_field << 27) | 4]+list(expected.payload))
            sent += count
            self.assertEqual(source.observe().tx_counter, reference.tx_counter)
            self.assertEqual(reference.tx_fill, len(fifo))
        self.assertGreater(sent, 4096)

    def test_arbiter_handoff_is_noninterleaved_and_stall_safe(self):
        source = staged(list(range(32)))
        arbiter = DLMessageArbiter()
        self.assertTrue(arbiter.offer(Message((1, 0), (0xF8000004, *range(32)))))
        for msg in [Message((0, 0), (0x1111,)), Message((8, 4), (0x2222,)), Message((1, 1), (0x3333,))]:
            self.assertTrue(arbiter.offer(msg))
        uart_cycles = []
        all_beats = []
        for cycle in range(80):
            opportunity = cycle % 5 != 2
            beat = arbiter.tick(segment_available=opportunity)
            take = beat is not None and beat.source == (1, 0)
            out = source.tick(take=take)
            if take:
                self.assertEqual((out.word, out.word_index, out.done), (beat.word, beat.index, beat.last))
                uart_cycles.append(cycle)
            if beat:
                all_beats.append(beat)
        self.assertEqual(len(uart_cycles), 33)
        positions = [i for i, beat in enumerate(all_beats) if beat.source == (1, 0)]
        self.assertEqual(positions, list(range(positions[0], positions[0]+33)))
        self.assertEqual((source.observe().tx_counter, source.observe().staged_words), (32, 0))

    def test_strict_input_validation_is_atomic(self):
        source = staged([1, 2])
        before = source.observe()
        for args in ({'enabled': 1}, {'reset': 0}, {'take': 'yes'}, {'payload_fill': 4096},
                     {'payload_fill': -1}, {'payload_valid': 1}, {'payload_word': True},
                     {'payload_word': 1 << 32}, {'credit_valid': 1}, {'credit_value': 4096}):
            with self.subTest(args=args), self.assertRaises(ValueError):
                source.tick(**args)
            self.assertEqual(source.observe(), before)


if __name__ == '__main__':
    unittest.main()
