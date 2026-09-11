"""UART RX framing, exact capacity, reset run-out and firmware credit behavior.

Run: python3 -m unittest verification.model.test_uart_rx_path -v
Outputs: unittest results; next: real SRAM RTL and independently scored traffic.
"""
import random
import unittest

try:
    from model.ualink.uart_rx_path import UARTRxPath
except ModuleNotFoundError:
    UARTRxPath = None
from model.ualink.uart_credit import UARTStreamFlowControl, UARTTransport


def header(count, stream=0, reserved=0):
    return ((count-1) << 27) | (stream << 9) | 4 | reserved


class UARTRxPathTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(UARTRxPath, 'UART RX cycle implementation is missing')

    def active(self, depth=128):
        end = UARTRxPath(depth)
        end.tick(reset=True)
        before = end.tick()
        self.assertFalse(before.initialized)
        self.assertTrue(end.observe().initialized)
        self.assertEqual(end.observe().rx_counter, depth)
        return end

    def drain(self, end, **kwargs):
        words = []
        for _ in range(end.depth+8):
            out = end.tick(fw_ready=True, **kwargs)
            if out.fw_valid:
                words.append(out.fw_word)
            if not end.observe(**kwargs).rx_fill:
                break
        self.assertEqual(end.observe(**kwargs).rx_fill, 0)
        return words

    def test_reset_release_and_reads_initialize_once(self):
        end = UARTRxPath()
        out = end.tick(word=header(1), fw_ready=True, reset=True)
        self.assertFalse(any(vars(out).values()))
        self.assertEqual(end.observe().rx_counter, 0)
        end.tick()
        self.assertEqual(end.observe().rx_counter, 128)
        for _ in range(5):
            self.assertFalse(end.tick(fw_ready=True).fw_valid)
        self.assertEqual(end.observe().rx_counter, 128)

    def test_header_never_stored_and_reserved_fields_are_ignored(self):
        for reserved in (0, 3, 0x7FFF000 | 3):
            with self.subTest(reserved=reserved):
                end = self.active(1)
                out = end.tick(word=header(1, reserved=reserved))
                self.assertTrue(out.header)
                self.assertFalse(out.payload_write)
                self.assertEqual(end.observe().rx_fill, 0)
                out = end.tick(word=0xDEADBEEF)
                self.assertTrue(out.payload_write and out.done)
                self.assertEqual((end.observe().rx_fill, end.observe().rx_counter), (1, 1))
                self.assertEqual(self.drain(end), [0xDEADBEEF])
                self.assertEqual(end.observe().rx_counter, 2)

    def test_every_length_and_control_looking_payload_remains_opaque(self):
        for count in range(1, 33):
            with self.subTest(count=count):
                end = self.active()
                payload = ([4, 0x44, 0x184, 0x1C4, 0x1204, 0, 0xFFFFFFFF]*5)[:count]
                end.tick(word=header(count))
                for index, word in enumerate(payload):
                    for _ in range(index % 3):
                        held = end.tick()
                        self.assertEqual(held.remaining, count-index)
                    out = end.tick(word=word)
                    self.assertTrue(out.payload_write)
                    self.assertFalse(out.header or out.credit_valid or out.reset_request or out.reset_response or out.other_valid)
                    self.assertEqual(out.done, index == count-1)
                self.assertEqual(self.drain(end), payload)

    def test_exact_capacity_and_atomic_header_rejection(self):
        for depth in (1, 31, 32, 33, 128, 129):
            with self.subTest(depth=depth):
                end = self.active(depth)
                expected = []
                while len(expected) < depth:
                    count = min(32, depth-len(expected))
                    self.assertFalse(end.tick(word=header(count)).error)
                    for _ in range(count):
                        word = len(expected)+0x1000
                        self.assertTrue(end.tick(word=word).payload_write)
                        expected.append(word)
                self.assertEqual(end.observe().rx_fill, depth)
                out = end.tick(word=header(2))
                self.assertTrue(out.error)
                for word in (0xAA, 0xBB):
                    out = end.tick(word=word)
                    self.assertTrue(out.payload_discard)
                    self.assertFalse(out.payload_write or out.error)
                self.assertEqual(self.drain(end), expected)

    def test_same_edge_read_does_not_supply_header_admission_space(self):
        end = self.active(1)
        end.tick(word=header(1))
        end.tick(word=77)
        for _ in range(3):
            end.tick()
        self.assertTrue(end.observe().fw_valid)
        out = end.tick(word=header(1), fw_ready=True)
        self.assertTrue(out.fw_valid and out.error)
        self.assertEqual(out.fw_word, 77)
        out = end.tick(word=88)
        self.assertTrue(out.payload_discard)
        self.assertEqual((end.observe().rx_fill, end.observe().rx_counter), (0, 2))

    def test_offline_discards_silently_and_latches_across_empty_cycles(self):
        end = self.active()
        end.tick(word=header(3))
        self.assertTrue(end.tick(word=10).payload_write)
        out = end.tick(enabled=False)
        self.assertTrue(out.dropping)
        self.assertFalse(out.error)
        for word in (11, 12):
            self.assertTrue(end.tick(word=word).payload_discard)
        self.assertEqual(self.drain(end, enabled=False), [10])
        end.tick(word=header(2), enabled=False)
        self.assertTrue(end.tick(word=1).payload_discard)
        self.assertTrue(end.tick(word=2).payload_discard)
        self.assertEqual(end.observe().rx_fill, 0)

    def test_stream_reset_flushes_storage_but_preserves_payload_runout(self):
        end = self.active()
        end.tick(word=header(4))
        end.tick(word=10)
        out = end.tick(stream_reset=True)
        self.assertEqual(out.rx_fill, 0)
        self.assertEqual(end.observe().remaining, 3)
        self.assertEqual(end.observe().rx_counter, 0)
        end.tick()  # Release initializes capacity; old payload remains discarded.
        for word in (0x184, 0x1C4, 0x44):
            out = end.tick(word=word)
            self.assertTrue(out.payload_discard)
            self.assertFalse(out.reset_request or out.reset_response or out.credit_valid)
        self.assertEqual(end.observe().rx_counter, 128)
        self.assertEqual(end.observe().remaining, 0)
        end.tick(word=header(1))
        end.tick(word=99)
        self.assertEqual(self.drain(end), [99])

    def test_header_seen_during_reset_or_initialization_is_run_out(self):
        for held_reset in (False, True):
            with self.subTest(held_reset=held_reset):
                end = UARTRxPath()
                end.tick(reset=True)
                out = end.tick(word=header(2), stream_reset=held_reset)
                self.assertTrue(out.header)
                self.assertFalse(out.error)
                end.tick()
                for word in (20, 30):
                    self.assertTrue(end.tick(word=word).payload_discard)
                self.assertEqual(end.observe().rx_fill, 0)

    def test_credit_and_reset_decoding_offline_and_during_stream_reset(self):
        end = self.active()
        for value in (0, 1, 128, 4095):
            out = end.tick(word=(value << 20) | 0xFF003 | 0x44, enabled=False)
            self.assertTrue(out.credit_valid)
            self.assertEqual(out.credit_value, value)
            self.assertFalse(out.other_valid)
        out = end.tick(word=0x184, stream_reset=True)
        self.assertTrue(out.reset_request)
        self.assertFalse(out.request_all)
        out = end.tick(word=0x1F84, stream_reset=True)
        self.assertTrue(out.reset_request and out.request_all)
        for status in range(8):
            out = end.tick(word=0x1C4 | (status << 13), stream_reset=True)
            self.assertTrue(out.reset_response)
            self.assertEqual(out.response_status, status)
        self.assertFalse(end.tick(word=0x44, stream_reset=True).credit_valid)

    def test_unallocated_transport_stream_drops_without_losing_next_header(self):
        end = self.active()
        for stream in range(1, 8):
            end.tick(word=header(2, stream=stream))
            self.assertTrue(end.tick(word=0x184).payload_discard)
            self.assertTrue(end.tick(word=0x44).payload_discard)
            self.assertTrue(end.tick(word=0x184).reset_request)
        for word in (0, 0x40, 0x120, 0xDEAD000C, 0x84, 0x244):
            out = end.tick(word=word)
            self.assertTrue(out.other_valid)
            self.assertEqual(out.other_word, word)
        self.assertEqual(end.observe().rx_fill, 0)

    def test_complete_messages_match_independent_event_reference_through_wrap(self):
        for seed in (17, 29, 101):
            with self.subTest(seed=seed):
                rng = random.Random(seed)
                end = self.active()
                reference = UARTStreamFlowControl()
                reference.release_reset()
                reference.set_channel4_enabled(True)
                read_count = 0
                for _ in range(350):
                    payload = tuple(rng.getrandbits(32) for _ in range(rng.randint(1, 32)))
                    end.tick(word=header(len(payload)))
                    for word in payload:
                        out = end.tick(word=word)
                        self.assertTrue(out.payload_write)
                    self.assertTrue(reference.receive_transport(UARTTransport(payload)))
                    self.assertEqual(end.observe().rx_fill, reference.rx_fill)
                    words = self.drain(end)
                    self.assertEqual(words, [reference.read() for _ in payload])
                    read_count += len(words)
                    self.assertEqual(end.observe().rx_counter, (128+read_count) % 4096)
                    self.assertEqual(end.observe().rx_counter, reference.rx_counter)
                self.assertGreater(read_count, 4096)

    def test_research_depth_and_invalid_api(self):
        for depth in (1, 4095):
            self.assertEqual(self.active(depth).observe().rx_counter, depth)
        for depth in (0, 4096, True, 1.0, '128'):
            with self.assertRaises((TypeError, ValueError)):
                UARTRxPath(depth)
        end = self.active()
        before = end.observe()
        for kwargs in ({'word': True}, {'word': -1}, {'word': 1 << 32}, {'word': '4'},
                       {'enabled': 1}, {'stream_reset': 0}, {'fw_ready': None}, {'reset': 1}):
            with self.subTest(kwargs=kwargs), self.assertRaises((TypeError, ValueError)):
                end.tick(**kwargs)
            self.assertEqual(end.observe(), before)


if __name__ == '__main__':
    unittest.main()
