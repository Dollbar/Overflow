"""Fail-closed STA report gate: real text parsing, no mocked EDA success."""

import unittest

try:
    from scripts.check_sta_report import check_report
except ImportError:
    check_report = None


GOOD = """worst slack max 0.010000
worst slack min 0.020000
tns max 0.000000
PASS credit setup/hold at period_ns=0.640; prelayout budget only
"""


class StaReportTests(unittest.TestCase):
    def test_prepared_partition_rejects_old_top_or_negative_report(self):
        text = GOOD.replace("PASS credit ", "PASS prepared_partition ")
        try:
            result = check_report(text, design="prepared_partition")
        except ValueError as error:
            self.fail(f"prepared metadata top profile missing: {error}")
        self.assertEqual(result["setup_slack_ns"], 0.01)
        for bad in (GOOD.replace("PASS credit ", "PASS control_partition "),
                    text.replace("0.020000", "-0.000001")):
            with self.assertRaises(ValueError):
                check_report(bad, design="prepared_partition")

    def test_control_partition_requires_complete_matching_profile(self):
        text = GOOD.replace("PASS credit ", "PASS control_partition ")
        try:
            result = check_report(text, design="control_partition")
        except ValueError as error:
            self.fail(f"control partition STA profile is missing: {error}")
        self.assertEqual(result["setup_slack_ns"], 0.01)
        for bad in (GOOD, text.replace("0.010000", "-0.010000"),
                    "\n".join(text.splitlines()[:3])):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                check_report(bad, design="control_partition")

    def setUp(self):
        self.assertIsNotNone(check_report, "STA diagnostic gate is missing")

    def test_accepts_positive_slacks(self):
        result = check_report(GOOD)
        self.assertEqual(result["setup_slack_ns"], 0.01)
        self.assertEqual(result["hold_slack_ns"], 0.02)
        self.assertEqual(result["period_ns"], 0.64)

    def test_rejects_negative_setup_or_hold(self):
        for text in (GOOD.replace("0.010000", "-0.000001"), GOOD.replace("0.020000", "-0.000001")):
            with self.subTest(text=text), self.assertRaises(ValueError):
                check_report(text)

    def test_rejects_library_violation_with_green_slacks(self):
        for kind in ("max slew", "max capacitance", "min pulse width", "min period"):
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                check_report(GOOD + f"{kind}\nU1/Z 0.02 0.03 -0.01 (VIOLATED)\n")

    def test_rejects_tool_warning_error_and_unconstrained_paths(self):
        for line in ("Warning: missing timing arc", "Error: link failed", "FAIL credit STA", "unconstrained endpoint U1/D"):
            with self.subTest(line=line), self.assertRaises(ValueError):
                check_report(GOOD + line + "\n")

    def test_rejects_empty_truncated_and_duplicate_results(self):
        for text in ("", "\n".join(GOOD.splitlines()[:2]), GOOD.replace("worst slack min 0.020000\n", ""), GOOD + GOOD):
            with self.subTest(text=text), self.assertRaises(ValueError):
                check_report(text)

    def test_rejects_nonfinite_or_malformed_slacks(self):
        for value in ("nan", "inf", "-inf", "not-a-number", "1e309"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                check_report(GOOD.replace("0.010000", value))

    def test_rejects_undeclared_period(self):
        with self.assertRaises(ValueError):
            check_report(GOOD.replace("0.640", "1.000"))

    def test_accepts_reference_mode_and_zero_boundary(self):
        result = check_report(GOOD.replace("0.640", "6.400").replace("0.010000", "0.000000"))
        self.assertEqual(result["period_ns"], 6.4)
        self.assertEqual(result["setup_slack_ns"], 0.0)

    def test_initialization_report_requires_explicit_matching_design(self):
        text = GOOD.replace("PASS credit ", "PASS initialization ")
        try:
            result = check_report(text, design="initialization")
        except TypeError as error:
            self.fail(f"explicit STA design selection is missing: {error}")
        self.assertEqual(result["setup_slack_ns"], 0.01)
        with self.assertRaises(ValueError):
            check_report(text)
        with self.assertRaises(ValueError):
            check_report(GOOD, design="initialization")

    def test_design_selection_cannot_accept_unknown_or_mixed_completion(self):
        try:
            check_report(GOOD, design="credit")
        except TypeError as error:
            self.fail(f"explicit STA design selection is missing: {error}")
        with self.assertRaises(ValueError):
            check_report(GOOD, design="anything")
        with self.assertRaises(ValueError):
            check_report(GOOD + "PASS initialization setup/hold at period_ns=0.640; prelayout budget only\n")

    def test_receive_controller_report_requires_its_explicit_profile(self):
        text = GOOD.replace("PASS credit ", "PASS receive ")
        try:
            result = check_report(text, design="receive")
        except ValueError as error:
            self.fail(f"receive controller STA profile is missing: {error}")
        self.assertEqual(result["setup_slack_ns"], 0.01)
        with self.assertRaises(ValueError):
            check_report(text, design="return")
        with self.assertRaises(ValueError):
            check_report(GOOD, design="receive")

    def test_return_queue_report_requires_its_explicit_profile(self):
        text = GOOD.replace("PASS credit ", "PASS return ")
        try:
            result = check_report(text, design="return")
        except ValueError as error:
            self.fail(f"normal return STA profile is missing: {error}")
        self.assertEqual(result["hold_slack_ns"], 0.02)
        with self.assertRaises(ValueError):
            check_report(text, design="initialization")
        with self.assertRaises(ValueError):
            check_report(GOOD, design="return")

    def test_burst_control_report_requires_its_explicit_profile(self):
        text = GOOD.replace("PASS credit ", "PASS burst_control ")
        result = check_report(text, design="burst_control")
        self.assertEqual(result["setup_slack_ns"], 0.01)
        with self.assertRaises(ValueError):
            check_report(text, design="credit")
        with self.assertRaises(ValueError):
            check_report(GOOD, design="burst_control")


if __name__ == "__main__":
    unittest.main()
