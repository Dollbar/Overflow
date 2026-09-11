"""Synthetic report-gate fixtures, deliberately separate from actual EDA evidence."""
import unittest

from scripts.check_uart_tx_sta_report import check_report


SOURCE = '''UART_TX_PROFILE target=source depth=0 macro_view=none
Path Group: UART_TX
Path Type: max
Path Type: min
worst slack max 0.001000001
worst slack min 0.010000000
tns max 0.000000000
PASS dl_uart_tx_source setup/hold at period_ns=0.640; prelayout budget only
'''
PATH = SOURCE.replace('target=source depth=0 macro_view=none', 'target=path depth=128 macro_view=slow').replace('dl_uart_tx_source', 'dl_uart_tx_path')+'''UART_TX_LIBRARY name=kd28_sram_slow
UART_TX_MACRO cell=KD28_SRAM_SDP_256X32 count=1
UART_TX_PINS write_clocks=1 read_clocks=1 read_outputs=32 write_data=32 read_address=8 write_address=8
UART_TX_PATH register_to_macro min_slack_ns=0.01 max_slack_ns=0.02
UART_TX_PATH input_to_macro min_slack_ns=0.01 max_slack_ns=0.02
UART_TX_PATH macro_to_register min_slack_ns=0.01 max_slack_ns=0.02
'''


class UARTTxSTAReportTests(unittest.TestCase):
    def test_source_profiles(self):
        for period in ('0.640', '6.400'):
            self.assertEqual(check_report(SOURCE.replace('0.640;', period+';'), target='source')['period_ns'], float(period))

    def test_real_memory_profile_inventory_required(self):
        self.assertEqual(check_report(PATH, target='path', depth=128, macro_view='slow')['macro_count'], 1)
        for fragment in ('UART_TX_LIBRARY name=kd28_sram_slow\n', 'UART_TX_MACRO cell=KD28_SRAM_SDP_256X32 count=1\n'):
            with self.subTest(fragment=fragment), self.assertRaises(ValueError):
                check_report(PATH.replace(fragment, ''), target='path', depth=128, macro_view='slow')

    def test_wrong_profile_or_clock_rejected(self):
        for old, new in (('dl_uart_tx_source', 'dl_message_arbiter'), ('UART_TX\n', 'DL_MESSAGE\n'),
                         ('0.640;', '1.000;'), ('depth=0', 'depth=1'), ('macro_view=none', 'macro_view=slow')):
            with self.subTest(new=new), self.assertRaises(ValueError):
                check_report(SOURCE.replace(old, new), target='source')
        with self.assertRaises(ValueError):
            check_report(PATH, target='source')

    def test_missing_duplicate_fields_and_completion(self):
        for line in SOURCE.splitlines(keepends=True):
            with self.subTest(line=line), self.assertRaises(ValueError):
                check_report(SOURCE.replace(line, ''), target='source')
            if not line.startswith('Path '):
                with self.subTest(duplicate=line), self.assertRaises(ValueError):
                    check_report(SOURCE+line, target='source')

    def test_negative_and_nonfinite_slacks(self):
        for field in ('0.001000001', '0.010000000'):
            for value in ('-0.000000001', 'nan', 'inf', '-inf'):
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    check_report(SOURCE.replace(field, value), target='source')

    def test_diagnostics_electrical_and_tns(self):
        for bad in ('Warning: missing clock', 'Error: missing model', 'unconstrained endpoints',
                    'max_capacitance (VIOLATED)', 'max_slew (VIOLATED)', 'FAIL incomplete'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                check_report(SOURCE+bad+'\n', target='source')
        for value in ('-0.000000001', 'nan', '1.0'):
            with self.subTest(tns=value), self.assertRaises(ValueError):
                check_report(SOURCE.replace('tns max 0.000000000', 'tns max '+value), target='source')

    def test_memory_view_class_count_and_pin_shape(self):
        for old, new in (('macro_view=slow', 'macro_view=fast'), ('name=kd28_sram_slow', 'name=kd28_sram_fast'),
                         ('256X32', '512X64'), ('count=1', 'count=2'), ('read_outputs=32', 'read_outputs=31'),
                         ('write_clocks=1', 'write_clocks=0'), ('write_data=32', 'write_data=31'),
                         ('read_address=8', 'read_address=7'), ('write_address=8', 'write_address=7')):
            with self.subTest(new=new), self.assertRaises(ValueError):
                check_report(PATH.replace(old, new), target='path', depth=128, macro_view='slow')

    def test_memory_path_missing_duplicate_and_negative(self):
        for kind in ('register_to_macro', 'input_to_macro', 'macro_to_register'):
            line=next(x+'\n' for x in PATH.splitlines() if x.startswith('UART_TX_PATH '+kind+' '))
            for text in (PATH.replace(line, ''), PATH+line, PATH.replace(line, line.replace('min_slack_ns=0.01', 'min_slack_ns=-0.01'))):
                with self.subTest(kind=kind), self.assertRaises(ValueError):
                    check_report(text, target='path', depth=128, macro_view='slow')

    def test_profile_argument_contract(self):
        for kwargs in ({'target':'source','depth':128}, {'target':'source','macro_view':'fast'},
                       {'target':'path'}, {'target':'path','depth':0,'macro_view':'slow'},
                       {'target':'path','depth':4096,'macro_view':'slow'}, {'target':'other'}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                check_report(SOURCE, **kwargs)


if __name__ == '__main__':
    unittest.main()
