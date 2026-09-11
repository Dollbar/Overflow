"""Check mapping diagnostics against actual used cell types; fixtures are not EDA."""
import unittest
from scripts.check_uart_tx_mapping import check_mapping_diagnostics

WARNING = "Warning: Malformed liberty file - cannot find pin 'SESI+!SED' in cell 'SCAN_TEST' - skipping.\n"


class UARTTxMappingDiagnosticTests(unittest.TestCase):
    def test_exact_unused_skip_recorded(self):
        r = check_mapping_diagnostics(WARNING*3, {'DFQD2BWP40P140', 'AND2D1BWP40P140'})
        self.assertEqual(r['diagnostic_count'], 3)
        self.assertEqual(r['skipped_unused_cells'], ['SCAN_TEST'])

    def test_used_skipped_cell_is_blocking(self):
        with self.assertRaises(ValueError):
            check_mapping_diagnostics(WARNING, {'SCAN_TEST', 'DFQD2BWP40P140'})

    def test_unknown_diagnostic_is_blocking(self):
        for line in ('Warning: undriven state', 'ERROR: unresolved cell', 'Error: bad expression', 'FAIL incomplete'):
            with self.subTest(line=line), self.assertRaises(ValueError):
                check_mapping_diagnostics(WARNING+line+'\n', {'DFQD2BWP40P140'})

    def test_not_exact_skip_is_blocking(self):
        for line in (WARNING.replace(' - skipping.', ''), WARNING.replace('cannot find pin', 'cannot map pin')):
            with self.subTest(line=line), self.assertRaises(ValueError):
                check_mapping_diagnostics(line, {'DFQD2BWP40P140'})

    def test_no_diagnostics_empty_inventory_rejected(self):
        self.assertEqual(check_mapping_diagnostics('', {'DFQD2BWP40P140'})['diagnostic_count'], 0)
        with self.assertRaises(ValueError):
            check_mapping_diagnostics(WARNING, set())


if __name__ == '__main__':
    unittest.main()
