"""Fail-closed integrated-memory evidence parsing, not mocked EDA execution.

Run: python3 -m unittest verification.tools.test_storage_report -v
Output: parser test results; failure is nonzero, no EDA run is claimed.
Next: validate actual OpenSTA reports with source/netlist/dependency hashes.
"""

import unittest

try:
    from scripts.check_storage_report import check_storage_report
except ImportError:
    check_storage_report = None


GOOD = """STORAGE_PROFILE depth=5 width=32 macro_view=slow
STORAGE_LIBRARY name=kd28_sram_slow
STORAGE_MACRO cell=KD28_SRAM_SDP_256X32 count=1
STORAGE_PINS write_clocks=1 read_clocks=1 read_outputs=32 write_data=32 read_address=8 write_address=8
STORAGE_PATH register_to_macro min_slack_ns=0.030000 max_slack_ns=0.040000
STORAGE_PATH input_to_macro min_slack_ns=0.020000 max_slack_ns=0.030000
STORAGE_PATH macro_to_register min_slack_ns=0.080000 max_slack_ns=0.010000
worst slack max 0.010000
worst slack min 0.020000
PASS storage setup/hold at period_ns=0.640; synthetic macro budget only
"""


class StorageReportTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(check_storage_report, "integrated storage report gate is missing")

    def check(self, text, **options):
        return check_storage_report(text, **dict(depth=5, width=32, macro_view="slow", **options))

    def test_accepts_declared_macro_paths_and_separate_evidence_level(self):
        result = self.check(GOOD)
        self.assertEqual(result["macro_cells"], 1)
        self.assertEqual(result["setup_slack_ns"], 0.01)
        self.assertEqual(result["paths"]["input_to_macro"]["hold_slack_ns"], 0.02)
        self.assertEqual(result["scope"], "actual_cells_with_synthetic_memory_prelayout_budget")

    def test_rejects_missing_zero_wrong_or_extra_macro_inventory(self):
        for text in (GOOD.replace("count=1", "count=0"), GOOD.replace("count=1", "count=2"),
                     GOOD.replace("SDP_256X32", "SP_256X32"), GOOD.replace("SDP_256X32", "SDP_512X64"),
                     GOOD.replace("STORAGE_MACRO cell=KD28_SRAM_SDP_256X32 count=1\n", ""),
                     GOOD + "STORAGE_MACRO cell=KD28_SRAM_SDP_256X32 count=1\n"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.check(text)

    def test_rejects_missing_macro_interface_pins(self):
        for field in ("write_clocks=1", "read_clocks=1", "read_outputs=32", "write_data=32", "read_address=8", "write_address=8"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.check(GOOD.replace(field, field.split("=")[0] + "=0"))

    def test_rejects_missing_duplicate_or_negative_path_classes(self):
        lines = [line for line in GOOD.splitlines(True) if line.startswith("STORAGE_PATH")]
        for line in lines:
            for text in (GOOD.replace(line, ""), GOOD + line, GOOD.replace(line, line.replace("min_slack_ns=0.", "min_slack_ns=-0.")),
                         GOOD.replace(line, line.replace("max_slack_ns=0.", "max_slack_ns=-0."))):
                with self.subTest(text=text), self.assertRaises(ValueError):
                    self.check(text)

    def test_rejects_nonfinite_global_and_path_results(self):
        for value in ("nan", "inf", "-inf", "oops", "1e309"):
            for old in ("max_slack_ns=0.010000", "worst slack max 0.010000", "worst slack min 0.020000"):
                with self.subTest(value=value, old=old), self.assertRaises(ValueError):
                    self.check(GOOD.replace(old, old.rsplit("0.", 1)[0] + value))

    def test_rejects_diagnostics_and_unconstrained_paths(self):
        for line in ("Warning: macro has no timing", "Error: link failed", "FAIL storage STA", "unconstrained endpoint", "0.020 (VIOLATED)"):
            with self.subTest(line=line), self.assertRaises(ValueError):
                self.check(GOOD + line + "\n")

    def test_rejects_wrong_profile_mode_or_controller_report(self):
        for text in (GOOD.replace("depth=5", "depth=16"), GOOD.replace("width=32", "width=40"),
                     GOOD.replace("macro_view=slow", "macro_view=typical"), GOOD.replace("0.640", "1.000"),
                     GOOD.replace("PASS storage", "PASS receive"), GOOD.replace("synthetic macro budget only", "prelayout budget only"),
                     GOOD + GOOD, ""):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.check(text)

    def test_requires_banked_selection_path_and_counts_width_tiles(self):
        text = GOOD.replace("depth=5 width=32", "depth=2049 width=520").replace("SDP_256X32 count=1", "SDP_2048X256 count=6")
        text = text.replace("write_clocks=1 read_clocks=1 read_outputs=32 write_data=32 read_address=8 write_address=8",
                            "write_clocks=6 read_clocks=6 read_outputs=1536 write_data=1536 read_address=66 write_address=66")
        with self.assertRaises(ValueError):
            check_storage_report(text, depth=2049, width=520, macro_view="slow")
        text += "STORAGE_PATH bank_select_to_register min_slack_ns=0.050000 max_slack_ns=0.020000\n"
        self.assertEqual(check_storage_report(text, depth=2049, width=520, macro_view="slow")["macro_cells"], 6)

    def test_rejects_wrong_units_when_path_is_worse_than_global(self):
        with self.assertRaises(ValueError):
            self.check(GOOD.replace("max_slack_ns=0.010000", "max_slack_ns=0.00000000001"))

    def test_rejects_missing_or_mislabeled_loaded_macro_library(self):
        for text in (GOOD.replace("STORAGE_LIBRARY name=kd28_sram_slow\n", ""),
                     GOOD.replace("name=kd28_sram_slow", "name=kd28_sram_fast")):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.check(text)

    def test_accepts_each_macro_class_and_reference_period(self):
        for depth, width, cell, count, bits, addresses in (
                (1, 8, "256X32", 1, 32, 8), (257, 40, "512X64", 1, 64, 9),
                (513, 128, "1024X128", 1, 128, 10), (1025, 520, "2048X256", 3, 768, 33)):
            text = GOOD.replace("depth=5 width=32", f"depth={depth} width={width}")
            text = text.replace("SDP_256X32 count=1", f"SDP_{cell} count={count}")
            text = text.replace("write_clocks=1 read_clocks=1 read_outputs=32 write_data=32 read_address=8 write_address=8",
                                f"write_clocks={count} read_clocks={count} read_outputs={bits} write_data={bits} read_address={addresses} write_address={addresses}")
            text = text.replace("0.640", "6.400")
            with self.subTest(depth=depth):
                self.assertEqual(check_storage_report(text, depth=depth, width=width, macro_view="slow")["period_ns"], 6.4)

    def test_rejects_invalid_caller_configuration(self):
        for d, w, view in ((0, 32, "slow"), (65536, 32, "slow"), (True, 32, "slow"), (5, 7, "slow"), (5, 32, "ssg")):
            with self.subTest(depth=d, width=w, view=view), self.assertRaises(ValueError):
                check_storage_report(GOOD, depth=d, width=w, macro_view=view)


if __name__ == "__main__":
    unittest.main()
