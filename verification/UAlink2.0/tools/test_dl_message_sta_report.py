"""Synthetic report parser fixtures; these are not EDA/timing evidence."""
import unittest

from scripts.check_dl_message_sta_report import check_report


GOOD = '''Path Group: DL_MESSAGE
Path Type: max
Path Type: min
worst slack max 0.000000010
worst slack min 0.010000000
PASS dl_message_arbiter setup/hold at period_ns=0.640; prelayout budget only
'''


class DLMessageSTAReportTests(unittest.TestCase):
    def test_exact_profiles(self):
        self.assertEqual(check_report(GOOD)['period_ns'], 0.640)
        self.assertEqual(check_report(GOOD.replace('0.640;', '6.400;'))['period_ns'], 6.400)

    def test_any_negative_setup_or_hold(self):
        for old, new in (('0.000000010', '-0.000000001'), ('0.010000000', '-0.000000001')):
            with self.subTest(old=old), self.assertRaises(ValueError):
                check_report(GOOD.replace(old, new))

    def test_nonfinite(self):
        for value in ('nan', 'inf', '-inf'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                check_report(GOOD.replace('0.000000010', value))

    def test_diagnostics_and_electrical_violations(self):
        for tail in ('Warning: missing clock\n', 'Error: unresolved cell\n',
                     'max_capacitance (VIOLATED)\n', 'unconstrained endpoints\n',
                     'FAIL stale report\n'):
            with self.subTest(tail=tail), self.assertRaises(ValueError):
                check_report(GOOD+tail)

    def test_missing_or_duplicate_slack(self):
        with self.assertRaises(ValueError):
            check_report(GOOD.replace('worst slack min 0.010000000\n', ''))
        with self.assertRaises(ValueError):
            check_report(GOOD+'worst slack max 1.0\n')

    def test_wrong_completion_or_mode(self):
        for old, new in (('dl_message_arbiter', 'burst_sender'), ('0.640;', '1.000;'),
                         ('PASS dl_message_arbiter', 'INCOMPLETE dl_message_arbiter')):
            with self.subTest(new=new), self.assertRaises(ValueError):
                check_report(GOOD.replace(old, new))
        with self.assertRaises(ValueError):
            check_report(GOOD+GOOD.splitlines()[-1]+'\n')

    def test_missing_actual_path_details(self):
        for line in ('Path Type: min\n', 'Path Type: max\n', 'Path Group: DL_MESSAGE\n'):
            with self.subTest(line=line), self.assertRaises(ValueError):
                check_report(GOOD.replace(line, ''))


if __name__ == '__main__':
    unittest.main()
