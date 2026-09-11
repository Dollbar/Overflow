"""Regression guards for receive-channel stimulus boundaries, not RTL evidence."""

import unittest

from verification.rtl.receive_channel_vectors import vectors


class ReceiveChannelVectorTests(unittest.TestCase):
    def test_single_bit_payload_even_in_diagnostic_injections(self):
        rows = list(vectors(1, 1, 9, (257, 0, 0, 0, 0), 16, "orig_data"))
        self.assertGreater(len(rows), 3000)
        for stimulus, _, _ in rows:
            self.assertLess(stimulus, 1 << 19)

    def test_nonuniform_initial_normal_parallel_handoff_is_exercised(self):
        rows = vectors(2, 13, 6, (0, 0, 0, 0, 1, 63, 0, 0, 0, 0), 4, "req")
        observed = False
        for _, _, after in rows:
            done = (after >> (13+9)) & 15
            valid = (after >> (13+33)) & 15
            pool = (after >> (13+29)) & 15
            observed |= done == 1 and valid == 3 and pool == 1
        self.assertTrue(observed)

    def test_zero_capacity_profile_never_accepts_a_payload(self):
        rows = list(vectors(4, 5, 3, (0,)*20, 1, "wr_rsp"))
        self.assertGreater(len(rows), 3000)
        self.assertTrue(all(not ((after >> 3) & 1) for _, _, after in rows))


if __name__ == "__main__":
    unittest.main()
