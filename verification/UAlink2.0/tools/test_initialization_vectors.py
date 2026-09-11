"""Exercise asymmetric initialization fixtures rather than synchronized ports."""

import unittest

from verification.rtl import initialization_vectors as adapter
from verification.rtl.credit_vectors import Profile


class InitialProfileTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(hasattr(adapter, "InitialProfile"), "asymmetric initialization profile is missing")

    def test_staggered_capacities_have_zero_pool_only_and_vc_only_ports(self):
        # Repeating the old equal-duration pattern would fail this literal layout.
        profile = adapter.InitialProfile(4, 3, 2, pattern="staggered")
        expected = (0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 2, 0, 0, 0, 4, 5, 6, 7, 0)
        self.assertEqual(profile.capacities, expected)
        self.assertEqual(profile.packed_capacities, sum(c << (3*i) for i, c in enumerate(expected)))

    def test_default_profile_preserves_existing_vectors(self):
        for ports in (1, 2, 4):
            for capacity in (None, 0, 8):
                with self.subTest(ports=ports, capacity=capacity):
                    old = Profile(ports, 4, 2, capacity)
                    new = adapter.InitialProfile(ports, 4, 2, capacity)
                    self.assertEqual(list(adapter.vectors(old)), list(adapter.vectors(new)))

    def test_asymmetric_vector_contains_each_distinct_completion_stage(self):
        # Forcing all four done bits to wait for the slowest port fails these bins.
        profile = adapter.InitialProfile(4, 3, 2, pattern="staggered")
        done_masks = {result & 15 for stimulus, result in adapter.vectors(profile) if stimulus == 3}
        self.assertEqual(done_masks, {0, 5, 7, 15})

    def test_ambiguous_or_unknown_pattern_is_rejected(self):
        for kwargs in ({"pattern":"unknown"}, {"pattern":"staggered", "uniform_capacity":0}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                adapter.InitialProfile(4, 3, 2, **kwargs)


if __name__ == "__main__":
    unittest.main()
