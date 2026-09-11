"""Reject incomplete channel physical reports; fixtures do not claim EDA runs."""

import unittest

try:
    from scripts.check_channel_report import check_channel_report
except ImportError:
    check_channel_report = None


GOOD = """CHANNEL_PROFILE ports=1 width=32 credit_width=4 cap_hex=50132 return_depth=4 macro_view=slow
CHANNEL_LIBRARY name=kd28_sram_slow
CHANNEL_MACRO cell=KD28_SRAM_SDP_256X32 count=8
CHANNEL_PINS write_clocks=8 read_clocks=8 read_outputs=256 write_data=256 read_address=64 write_address=64
CHANNEL_PATH register_to_macro min_slack_ns=0.030 max_slack_ns=0.040
CHANNEL_PATH input_to_macro min_slack_ns=0.020 max_slack_ns=0.030
CHANNEL_PATH macro_to_register min_slack_ns=0.080 max_slack_ns=0.010
CHANNEL_PATH selection_to_head min_slack_ns=0.030 max_slack_ns=0.020
CHANNEL_PATH register_to_head min_slack_ns=0.030 max_slack_ns=0.020
CHANNEL_PATH consumer_to_register min_slack_ns=0.030 max_slack_ns=0.020
CHANNEL_PATH control_to_register min_slack_ns=0.030 max_slack_ns=0.020
worst slack max 0.010
worst slack min 0.020
PASS channel setup/hold at period_ns=0.640; synthetic macro budget only
"""


class ChannelReportTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(check_channel_report, "channel report checker is not implemented")

    def check(self, text, **options):
        args = dict(ports=1, width=32, credit_width=4, cap_hex="50132", return_depth=4,
                    macro_view="slow", period_ns="0.640")
        args.update(options)
        return check_channel_report(text, **args)

    def test_accepts_complete_actual_channel_paths(self):
        result = self.check(GOOD)
        self.assertEqual(result["macro_cells"], 8)
        self.assertEqual(result["setup_slack_ns"], .01)
        self.assertEqual(result["paths"]["selection_to_head"]["setup_slack_ns"], .02)

    def test_rejects_any_missing_or_duplicate_path(self):
        for line in GOOD.splitlines(True):
            if line.startswith("CHANNEL_PATH"):
                for text in (GOOD.replace(line, ""), GOOD+line):
                    with self.subTest(line=line), self.assertRaises(ValueError):
                        self.check(text)

    def test_rejects_wrong_inventory_class_or_missing_pins(self):
        for before, after in (("count=8", "count=0"), ("count=8", "count=1"), ("SDP_256X32", "SDP_512X64"),
                              ("write_clocks=8", "write_clocks=0"), ("read_address=64", "read_address=0")):
            with self.subTest(before=before), self.assertRaises(ValueError):
                self.check(GOOD.replace(before, after))

    def test_rejects_wrong_profile_period_or_loaded_view(self):
        for before, after in (("ports=1", "ports=2"), ("cap_hex=50132", "cap_hex=11111"),
                              ("name=kd28_sram_slow", "name=kd28_sram_fast"), ("period_ns=0.640", "period_ns=6.400"),
                              ("return_depth=4", "return_depth=1"), ("PASS channel", "PASS storage")):
            with self.subTest(before=before), self.assertRaises(ValueError):
                self.check(GOOD.replace(before, after))

    def test_rejects_negative_nonfinite_diagnostic_and_inconsistent_units(self):
        for text in (GOOD.replace("max_slack_ns=0.010", "max_slack_ns=-0.010"),
                     GOOD.replace("worst slack max 0.010", "worst slack max nan"),
                     GOOD.replace("max_slack_ns=0.010", "max_slack_ns=1e-11"),
                     GOOD+"Warning: bad clock\n", GOOD+"unconstrained\n", GOOD+"FAIL final check\n", GOOD+GOOD):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.check(text)

    def test_mixed_macro_classes_and_bank_path_are_required(self):
        text = GOOD.replace("width=32 credit_width=4 cap_hex=50132", "width=520 credit_width=12 cap_hex=801201101001")
        text = text.replace("CHANNEL_MACRO cell=KD28_SRAM_SDP_256X32 count=8", "CHANNEL_MACRO cell=KD28_SRAM_SDP_256X32 count=17\nCHANNEL_MACRO cell=KD28_SRAM_SDP_512X64 count=9\nCHANNEL_MACRO cell=KD28_SRAM_SDP_1024X128 count=5\nCHANNEL_MACRO cell=KD28_SRAM_SDP_2048X256 count=6")
        text = text.replace("write_clocks=8 read_clocks=8 read_outputs=256 write_data=256 read_address=64 write_address=64", "write_clocks=37 read_clocks=37 read_outputs=3296 write_data=3296 read_address=333 write_address=333")
        options = dict(width=520, credit_width=12, cap_hex="801201101001")
        with self.assertRaises(ValueError):
            self.check(text, **options)
        text += "CHANNEL_PATH bank_select_to_register min_slack_ns=0.030 max_slack_ns=0.020\n"
        self.assertEqual(self.check(text, **options)["macro_cells"], 37)

    def test_zero_profile_does_not_require_nonexistent_storage_paths(self):
        text = GOOD.replace("cap_hex=50132", "cap_hex=0")
        text = "\n".join(line for line in text.splitlines() if not line.startswith("CHANNEL_MACRO") and
                         (not line.startswith("CHANNEL_PATH") or "control_to_register" in line))+"\n"
        text = text.replace("write_clocks=8 read_clocks=8 read_outputs=256 write_data=256 read_address=64 write_address=64", "write_clocks=0 read_clocks=0 read_outputs=0 write_data=0 read_address=0 write_address=0")
        self.assertEqual(self.check(text, cap_hex="0")["macro_cells"], 0)


if __name__ == "__main__":
    unittest.main()
