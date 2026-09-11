"""Run python3 verification/tl_tx_prepared/test_timing_report.py.
Outputs parser qualification results; next audit actual source-bound STA reports.
"""
import unittest


def fixture():
    lines=['TX_PREPARED_PROFILE width=8 header_depth=2 bank_depth=3 macro_view=slow period_ns=0.640',
           'TX_PREPARED_LIBRARY name=kd28_sram_slow',
           'TX_PREPARED_MACRO cell=KD28_SRAM_SDP_256X32 count=64',
           'TX_PREPARED_PINS write_clocks=64 read_clocks=64 read_outputs=2048 write_data=2048 read_address=512 write_address=512']
    for name in ('input_to_register','register_to_register','register_to_output','register_to_macro','input_to_macro','macro_to_register'):
        lines.append(f'TX_PREPARED_PATH {name} min_slack_ns=0.01 max_slack_ns=0.1')
    lines+=['worst slack max 0.1','worst slack min 0.01','TX_PREPARED_COMPLETE actual_cells=1 synthetic_memory=1',
            'PASS tx_prepared setup/hold at period_ns=0.640; synthetic macro budget only']
    return '\n'.join(lines)+'\n'


class TimingReportTests(unittest.TestCase):
    def check(self,text,exit_code=0):
        from timing_report import measure
        return measure(text,width=8,view='slow',period='0.640',exit_code=exit_code)

    def test_complete_positive_budget(self):self.assertTrue(self.check(fixture())['timing_closed'])

    def test_negative_measurement_is_not_closure(self):
        text=fixture().replace('worst slack max 0.1','worst slack max -0.2').replace('PASS tx_prepared setup/hold at period_ns=0.640; synthetic macro budget only','FAIL tx_prepared STA: Negative setup or hold slack')
        self.assertFalse(self.check(text,1)['timing_closed'])

    def test_missing_macro_rejected(self):
        with self.assertRaises(ValueError):self.check(fixture().replace('count=64','count=63'))

    def test_missing_pin_rejected(self):
        with self.assertRaises(ValueError):self.check(fixture().replace('read_outputs=2048','read_outputs=2047'))

    def test_missing_path_rejected(self):
        text='\n'.join(l for l in fixture().splitlines() if not l.startswith('TX_PREPARED_PATH macro_to_register'))
        with self.assertRaises(ValueError):self.check(text)

    def test_wrong_mode_rejected(self):
        with self.assertRaises(ValueError):self.check(fixture().replace('period_ns=0.640','period_ns=6.400'))

    def test_wrong_view_rejected(self):
        with self.assertRaises(ValueError):self.check(fixture().replace('kd28_sram_slow','kd28_sram_fast'))

    def test_nonfinite_rejected(self):
        with self.assertRaises(ValueError):self.check(fixture().replace('worst slack max 0.1','worst slack max nan'))

    def test_tool_error_rejected(self):
        with self.assertRaises(ValueError):self.check(fixture()+'Error: unresolved macro\n',1)

    def test_unconstrained_rejected(self):
        with self.assertRaises(ValueError):self.check(fixture()+'Warning: unconstrained endpoint\n')

    def test_missing_completion_rejected(self):
        with self.assertRaises(ValueError):self.check(fixture().replace('TX_PREPARED_COMPLETE','BROKEN_COMPLETE'))

    def test_negative_cannot_have_success_exit(self):
        with self.assertRaises(ValueError):self.check(fixture().replace('worst slack min 0.01','worst slack min -0.1'))


if __name__=='__main__':unittest.main()
