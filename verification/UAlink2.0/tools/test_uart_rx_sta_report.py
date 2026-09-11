"""RX STA report must bind RX identity before shared strict timing checks."""
import unittest
from scripts.check_uart_rx_sta_report import check_report

class UARTRxSTAReportTests(unittest.TestCase):
    def report(self):
        return '''UART_RX_PROFILE target=path depth=128 macro_view=slow
UART_RX_LIBRARY name=kd28_sram_slow
UART_RX_MACRO cell=KD28_SRAM_SDP_256X32 count=1
UART_RX_PINS write_clocks=1 read_clocks=1 read_outputs=32 write_data=32 read_address=8 write_address=8
UART_RX_PATH register_to_macro min_slack_ns=0.011 max_slack_ns=0.021
UART_RX_PATH input_to_macro min_slack_ns=0.012 max_slack_ns=0.022
UART_RX_PATH macro_to_register min_slack_ns=0.013 max_slack_ns=0.023
Path Group: UART_RX
Path Type: min
Path Type: max
worst slack max 0.020
worst slack min 0.010
tns max 0.000
PASS dl_uart_rx_path setup/hold at period_ns=0.640; prelayout budget only
'''
    def check(self,text):
        return check_report(text,target='path',depth=128,macro_view='slow')
    def test_rx_valid(self):
        self.assertEqual(self.check(self.report())['setup_ns'],0.020)
    def test_wrong_or_mixed_direction(self):
        for text in (self.report().replace('UART_RX','UART_TX').replace('uart_rx','uart_tx'),self.report()+'UART_TX_PROFILE target=source depth=0 macro_view=none\n',self.report().replace('dl_uart_rx_path','dl_uart_tx_path')):
            with self.subTest(text=text),self.assertRaises(ValueError):self.check(text)
    def test_missing_macro_and_negative_hold(self):
        for text in (self.report().replace('UART_RX_PATH input_to_macro','MISSING input_to_macro'),self.report().replace('min_slack_ns=0.012','min_slack_ns=-0.012'),self.report().replace('count=1','count=2'),self.report().replace('worst slack min 0.010','worst slack min nan')):
            with self.subTest(text=text),self.assertRaises(ValueError):self.check(text)
    def test_source_profile_rejected(self):
        with self.assertRaises(ValueError):check_report(self.report(),target='source')

if __name__=='__main__':unittest.main()
