"""Normative arithmetic/buffer checks for the whole-message UART reference.

Run: python3 -m unittest verification.model.test_uart_credit -v
Output: unittest results; retained experiment snapshots are recorded separately.
Next: validate cycle scheduling and reset handshake before using this as UART RTL.
"""
from dataclasses import FrozenInstanceError
import random
import unittest

from model.ualink.uart_credit import UARTStreamFlowControl, UARTTransport


def active(**kwargs):
    end = UARTStreamFlowControl(**kwargs)
    end.release_reset()
    end.set_channel4_enabled(True)
    return end


class UARTCreditTests(unittest.TestCase):
    def test_initial_release_and_repeated_release(self):
        end = UARTStreamFlowControl()
        self.assertTrue(end.in_reset)
        self.assertFalse(end.channel4_enabled)
        self.assertEqual((end.tx_fill, end.rx_fill, end.tx_counter, end.rx_counter,
                          end.latest_fc, end.available_credits), (0, 0, 0, 0, 0, 0))
        self.assertIsNone(end.transmit())
        self.assertIsNone(end.credit_snapshot())
        end.release_reset()
        self.assertFalse(end.in_reset)
        self.assertEqual(end.rx_counter, 128)
        end.set_channel4_enabled(True)
        self.assertEqual(end.credit_snapshot(), 128)
        self.assertTrue(end.receive_transport(UARTTransport((99,))))
        self.assertEqual(end.read(), 99)
        end.release_reset()
        self.assertEqual(end.rx_counter, 129)

    def test_offline_staging_discard_and_reenable(self):
        end = UARTStreamFlowControl(tx_depth=2, rx_depth=2)
        end.release_reset()
        self.assertTrue(end.write(7))
        end.apply_credit_update(2)
        self.assertIsNone(end.transmit())
        self.assertFalse(end.receive_transport(UARTTransport((8,))))
        self.assertEqual((end.tx_fill, end.rx_fill), (1, 0))
        self.assertIsNone(end.credit_snapshot())
        end.set_channel4_enabled(True)
        self.assertEqual(end.transmit().payload, (7,))
        end.receive_transport(UARTTransport((9,)))
        end.set_channel4_enabled(False)
        self.assertEqual(end.read(), 9)
        self.assertIsNone(end.credit_snapshot())
        end.set_channel4_enabled(True)
        self.assertEqual(end.credit_snapshot(), 3)

    def test_zero_credit_empty_and_all_length_bounds(self):
        for credits in (0, 1, 2, 31, 32, 33, 4095):
            for fill in (0, 1, 2, 31, 32, 33, 128):
                with self.subTest(credits=credits, fill=fill):
                    end = active()
                    for word in range(fill):
                        self.assertTrue(end.write(word))
                    end.apply_credit_update(credits)
                    count = min(credits, fill, 32)
                    self.assertEqual(end.next_transport_length(), count or None)
                    message = end.transmit()
                    if not count:
                        self.assertIsNone(message)
                    else:
                        self.assertEqual(message.payload, tuple(range(count)))
                        self.assertEqual(message.length_field, count-1)
                        self.assertEqual(message.total_word_count, count+1)
                    self.assertEqual(end.tx_counter, count)
                    self.assertEqual(end.tx_fill, fill-count)
                    self.assertEqual(end.available_credits, credits-count)

    def test_header_uses_neither_buffer_slot_nor_credit(self):
        sender = active(tx_depth=1)
        receiver = active(rx_depth=1)
        sender.apply_credit_update(receiver.credit_snapshot())
        self.assertTrue(sender.write(0xFFFFFFFF))
        message = sender.transmit()
        self.assertEqual((message.length_field, message.total_word_count), (0, 2))
        self.assertEqual((sender.tx_counter, sender.available_credits), (1, 0))
        self.assertTrue(receiver.receive_transport(message))
        self.assertEqual((receiver.rx_fill, receiver.rx_counter), (1, 1))
        self.assertEqual(receiver.read(), 0xFFFFFFFF)
        self.assertEqual(receiver.credit_snapshot(), 2)

    def test_full_buffers_and_atomic_overflow_rejection(self):
        end = active(tx_depth=2, rx_depth=2)
        self.assertTrue(end.write(1))
        self.assertTrue(end.write(2))
        self.assertFalse(end.write(3))
        self.assertEqual(end.tx_fill, 2)
        self.assertTrue(end.receive_transport(UARTTransport((4,))))
        with self.assertRaises(BufferError):
            end.receive_transport(UARTTransport((5, 6)))
        self.assertEqual((end.rx_fill, end.rx_counter), (1, 2))
        self.assertTrue(end.receive_transport(UARTTransport((7,))))
        self.assertEqual([end.read(), end.read(), end.read()], [4, 7, None])
        self.assertEqual(end.rx_counter, 4)
        end.apply_credit_update(2)
        self.assertEqual(end.transmit().payload, (1, 2))

    def test_credit_update_replaces_latest_and_duplicate_is_idempotent(self):
        end = active()
        for word in range(8):
            end.write(word)
        end.apply_credit_update(3)
        self.assertEqual(end.transmit().payload, (0, 1, 2))
        end.apply_credit_update(3)
        self.assertEqual(end.available_credits, 0)
        self.assertIsNone(end.transmit())
        end.apply_credit_update(5)
        self.assertEqual((end.latest_fc, end.available_credits), (5, 2))
        self.assertEqual(end.transmit().payload, (3, 4))

    def test_transmit_counter_and_advertisement_wrap(self):
        end = active(tx_depth=32)
        end.apply_credit_update(4095)
        sent = 0
        while sent < 4095:
            count = min(32, 4095-sent)
            for word in range(sent, sent+count):
                self.assertTrue(end.write(word))
            message = end.transmit()
            self.assertEqual(message.payload, tuple(range(sent, sent+count)))
            sent += count
        self.assertEqual((end.tx_counter, end.available_credits), (4095, 0))
        end.apply_credit_update(1)
        self.assertEqual(end.available_credits, 2)
        end.write(4095)
        end.write(4096)
        self.assertEqual(end.transmit().payload, (4095, 4096))
        self.assertEqual((end.tx_counter, end.available_credits), (1, 0))

    def test_receive_counter_wrap_and_empty_reads(self):
        end = active(rx_depth=1)
        for word in range(4095):
            end.receive_transport(UARTTransport((word,)))
            self.assertEqual(end.read(), word)
        self.assertEqual(end.rx_counter, 0)
        self.assertEqual(end.credit_snapshot(), 0)
        for _ in range(4):
            self.assertIsNone(end.read())
        self.assertEqual(end.rx_counter, 0)
        end.receive_transport(UARTTransport((9,)))
        self.assertEqual(end.rx_counter, 0)
        self.assertEqual(end.read(), 9)
        self.assertEqual(end.rx_counter, 1)

    def test_reset_flushes_and_discards_without_implicit_handshake(self):
        end = active()
        end.write(1)
        end.receive_transport(UARTTransport((2, 3)))
        end.apply_credit_update(128)
        end.transmit()
        end.read()
        end.reset()
        self.assertFalse(end.write(4))
        self.assertFalse(end.receive_transport(UARTTransport((5,))))
        end.apply_credit_update(77)
        self.assertEqual((end.tx_fill, end.rx_fill, end.tx_counter, end.rx_counter,
                          end.latest_fc), (0, 0, 0, 0, 0))
        self.assertFalse(end.channel4_enabled)
        self.assertIsNone(end.read())
        end.release_reset()
        self.assertEqual(end.rx_counter, 128)
        self.assertEqual(end.available_credits, 0)

    def test_credit_snapshots_and_length_queries_are_observations(self):
        end = active()
        end.write(0)
        end.apply_credit_update(1)
        for _ in range(8):
            self.assertEqual(end.credit_snapshot(), 128)
            self.assertEqual(end.next_transport_length(), 1)
        self.assertEqual((end.tx_fill, end.rx_fill, end.tx_counter, end.rx_counter), (1, 0, 0, 128))

    def test_payload_is_owned_immutable_and_validated(self):
        values = [1, 2]
        message = UARTTransport(values)
        values[0] = 99
        self.assertEqual(message.payload, (1, 2))
        with self.assertRaises(FrozenInstanceError):
            message.payload = (7,)
        for payload in ((), list(range(33)), (True,), (-1,), (1 << 32,), ('1',), 'abc', iter([1])):
            with self.subTest(payload=repr(payload)), self.assertRaises(ValueError):
                UARTTransport(payload)

    def test_invalid_local_api_arguments_leave_state_intact(self):
        for depth in (0, -1, 4096, True, 1.0, '128'):
            for key in ('tx_depth', 'rx_depth'):
                with self.subTest(key=key, depth=depth), self.assertRaises(ValueError):
                    UARTStreamFlowControl(**{key: depth})
        end = active()
        end.write(10)
        end.receive_transport(UARTTransport((11,)))
        end.apply_credit_update(20)
        for word in (-1, 1 << 32, True, 1.0, '1', None):
            with self.assertRaises(ValueError):
                end.write(word)
        for value in (-1, 4096, True, 1.0, '1', None):
            with self.assertRaises(ValueError):
                end.apply_credit_update(value)
        for value in (0, 1, 'yes', None):
            with self.assertRaises(ValueError):
                end.set_channel4_enabled(value)
        with self.assertRaises(ValueError):
            end.receive_transport((12,))
        self.assertTrue(end.channel4_enabled)
        self.assertEqual((end.tx_fill, end.rx_fill, end.tx_counter, end.rx_counter,
                          end.latest_fc), (1, 1, 0, 128, 20))
        self.assertEqual(end.transmit().payload, (10,))
        self.assertEqual(end.read(), 11)

    def test_research_capacity_limits_and_independent_directions(self):
        for depth in (1, 4095):
            end = active(tx_depth=depth, rx_depth=depth)
            self.assertEqual(end.credit_snapshot(), depth)
        left, right = active(tx_depth=3, rx_depth=5), active(tx_depth=7, rx_depth=2)
        left.apply_credit_update(right.credit_snapshot())
        right.apply_credit_update(left.credit_snapshot())
        for value in (1, 2, 3):
            left.write(value)
        for value in (10, 11, 12, 13, 14, 15):
            right.write(value)
        self.assertTrue(right.receive_transport(left.transmit()))
        self.assertTrue(left.receive_transport(right.transmit()))
        self.assertEqual((left.tx_fill, left.rx_fill, left.available_credits), (1, 5, 0))
        self.assertEqual((right.tx_fill, right.rx_fill, right.available_credits), (1, 2, 0))
        self.assertEqual(right.read(), 1)
        left.apply_credit_update(right.credit_snapshot())
        self.assertEqual(left.transmit().payload, (3,))
        self.assertIsNone(right.transmit())

    def test_bidirectional_delayed_credit_conservation_across_wraps(self):
        for seed in (17, 29, 101):
            with self.subTest(seed=seed):
                rng = random.Random(seed)
                ends = [active(tx_depth=47, rx_depth=67), active(tx_depth=61, rx_depth=43)]
                depths = [67, 43]
                written = [[], []]
                sent = [0, 0]
                reads = [0, 0]
                advertised_reads = [0, 0]
                for direction in (0, 1):
                    ends[direction].apply_credit_update(ends[1-direction].credit_snapshot())

                def advertise(receiver):
                    ends[1-receiver].apply_credit_update(ends[receiver].credit_snapshot())
                    advertised_reads[receiver] = reads[receiver]

                def transfer(sender):
                    receiver = 1-sender
                    # Unbounded integer conservation is independent of the DUT's modulo arithmetic.
                    available = depths[receiver]+advertised_reads[receiver]-sent[sender]
                    count = min(available, len(written[sender])-sent[sender], 32)
                    self.assertEqual(ends[sender].available_credits, available)
                    message = ends[sender].transmit()
                    if count:
                        self.assertIsNotNone(message)
                        self.assertEqual(message.payload, tuple(written[sender][sent[sender]:sent[sender]+count]))
                        self.assertTrue(ends[receiver].receive_transport(message))
                        sent[sender] += count
                    else:
                        self.assertIsNone(message)

                def consume(receiver, count):
                    sender = 1-receiver
                    for _ in range(count):
                        word = ends[receiver].read()
                        if reads[receiver] < sent[sender]:
                            self.assertEqual(word, written[sender][reads[receiver]])
                            reads[receiver] += 1
                        else:
                            self.assertIsNone(word)

                def check():
                    for end in (0, 1):
                        self.assertEqual(ends[end].tx_fill, len(written[end])-sent[end])
                        self.assertEqual(ends[end].rx_fill, sent[1-end]-reads[end])
                        self.assertEqual(ends[end].tx_counter, sent[end] % 4096)
                        self.assertEqual(ends[end].rx_counter, (depths[end]+reads[end]) % 4096)
                        self.assertLessEqual(ends[end].rx_fill, depths[end])

                for _ in range(3000):
                    for end in (0, 1):
                        for _ in range(rng.randrange(25)):
                            word = (end << 31) | len(written[end])
                            if ends[end].write(word):
                                written[end].append(word)
                        if rng.random() < 0.7:
                            transfer(end)
                        consume(end, rng.randrange(21))
                        if rng.random() < 0.18:
                            advertise(end)
                    check()
                # Drain all staged traffic with real reads and subsequent credit delivery.
                for _ in range(200):
                    for end in (0, 1):
                        consume(end, 67)
                        advertise(end)
                        transfer(1-end)
                    check()
                    if all(reads[1-end] == len(written[end]) for end in (0, 1)):
                        break
                for end in (0, 1):
                    self.assertEqual((sent[end], reads[1-end]), (len(written[end]), len(written[end])))
                    self.assertGreater(sent[end], 8192)


if __name__ == '__main__':
    unittest.main()
