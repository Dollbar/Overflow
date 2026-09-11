"""Literal packing and model-adapter checks, separate from protocol tests."""

import unittest

try:
    from verification.rtl.credit_vectors import Profile, Stimulus, Oracle, vectors
except ImportError:
    Profile = Stimulus = Oracle = vectors = None


class CreditVectorTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(Profile, "credit vector adapter not implemented")

    def test_literal_packing(self):
        self.assertEqual(Stimulus().packed(), 7 << 34)
        self.assertEqual(Stimulus(rstn=0, credit_connected=0, beats_connected=0,
                                  send_valid=1, send_port=2, send_vc=3, send_pool=1).packed(), 55)

    def test_profile_capacities(self):
        p = Profile(2, 3, 2)
        self.assertEqual(p.capacities, (0, 1, 3, 4, 7, 7, 4, 3, 1, 0))
        self.assertEqual(p.packed_capacities & 0x7fff, 0x78c8)

    def test_invalid_profiles(self):
        for args in ((3, 4, 2), (1, 2, 2), (1, 17, 2), (1, 4, 1), (1, 4, 16)):
            with self.subTest(args=args), self.assertRaises(ValueError):
                Profile(*args)

    def test_atomic_error_and_reset(self):
        oracle = Oracle(Profile(1, 4, 2))
        # VC1 capacity one; VC0 capacity zero. A failure cannot initialize either.
        self.assertEqual(oracle.step(Stimulus(valid=1, vc=1)), (16, 0, 0))
        self.assertEqual(oracle.step(Stimulus(valid=1, vc=0, init_done=1)), (16, 0, 1))
        self.assertEqual(oracle.step(Stimulus(init_done=1)), (16, 0, 0))
        self.assertEqual(oracle.step(Stimulus(init_done=1)), (16, 1, 0))
        self.assertEqual(oracle.step(Stimulus(rstn=0, valid=15, init_done=15)), (0, 0, 0))

    def test_full_return_and_send_net_zero(self):
        oracle = Oracle(Profile(1, 4, 2))
        oracle.step(Stimulus(valid=1, vc=1))
        oracle.step(Stimulus(init_done=1))
        oracle.step(Stimulus(init_done=1))
        self.assertEqual(oracle.step(Stimulus(valid=1, vc=1, send_valid=1, send_vc=1)), (16, 1, 0))

    def test_unused_port_and_invalid_fields(self):
        oracle = Oracle(Profile(1, 4, 2))
        self.assertEqual(oracle.step(Stimulus(valid=8)), (0, 0, 1))
        self.assertEqual(oracle.step(Stimulus(init_done=8)), (0, 0, 1))
        self.assertEqual(oracle.step(Stimulus(pool=15, vc=255, num=255, send_port=3)), (0, 0, 0))

    def test_vectors_repeat_and_have_errors(self):
        p = Profile(2, 4, 3)
        first = list(vectors(p))
        self.assertEqual(first, list(vectors(p)))
        self.assertGreater(len(first), 2048)
        self.assertEqual(first[0][1:], (0, 0, 0))
        self.assertTrue(any(row[-1] == 1 for row in first))

    def test_uniform_synthesis_profile(self):
        p = Profile(2, 4, 2, uniform_capacity=8)
        self.assertEqual(p.capacities, (8,) * 10)
        self.assertEqual(p.packed_capacities, 0x8888888888)
        self.assertGreater(len(list(vectors(p))), 2048)
        for cap in (-1, 16, True):
            with self.subTest(cap=cap), self.assertRaises(ValueError):
                Profile(1, 4, 2, uniform_capacity=cap)


if __name__ == "__main__":
    unittest.main()
