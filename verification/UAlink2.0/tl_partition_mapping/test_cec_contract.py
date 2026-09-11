"""Run: python3 -m unittest discover -s verification/tl_partition_mapping -p 'test_*.py'.
Produces unittest results only. Next run the real mapped positive/fault matrices.
"""
import unittest

from run_cec import prune_dead_names


class ProofConeContract(unittest.TestCase):
    def test_next_state_and_clock_remain_roots_even_without_output_fanout(self):
        source = """.model roots
.inputs clock data reset
.outputs out
.names data out
1 1
.names data reset next
10 1
.names clock latch_clock
1 1
.latch next state re latch_clock 2
.names undriven_dead unused_alias
1 1
.end
"""
        cleaned, metadata = prune_dead_names(source)
        self.assertIn(".names data reset next\n10 1", cleaned)
        self.assertIn(".names clock latch_clock\n1 1", cleaned)
        self.assertIn(".latch next state re latch_clock 2", cleaned)
        self.assertNotIn("undriven_dead", cleaned)
        self.assertEqual(metadata["removed_dead_names"], 1)

    def test_undriven_state_input_cannot_be_discarded_as_unused_output_logic(self):
        source = ".model missing\n.inputs clock data\n.outputs data\n.latch missing state re clock 2\n.end\n"
        with self.assertRaisesRegex(ValueError, "undriven live BLIF cone"):
            prune_dead_names(source)

    def test_multiple_driver_cannot_hide_behind_name_reuse(self):
        source = ".model double\n.inputs data\n.outputs out\n.names data out\n1 1\n.names out\n1\n.end\n"
        with self.assertRaisesRegex(ValueError, "duplicate BLIF driver"):
            prune_dead_names(source)


if __name__ == "__main__":
    unittest.main()
