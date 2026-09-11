"""C Table 2-21 and 3.1.1 parity checks; no Switch Core poison decision."""

import unittest

try:
    from model.ualink.upli_parity import even_parity, check_orig_data, check_credit
except ModuleNotFoundError as error:
    if error.name != "model.ualink.upli_parity":
        raise
    even_parity = None


class ParityTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(even_parity, "UPLI parity model not implemented")

    def test_even_parity_exhaustive_bytes_and_width_checks(self):
        for value in range(256):
            self.assertEqual(even_parity(value, 8), value.bit_count() % 2)
        for value, width in ((-1, 8), (256, 8), (0, 0), (True, 1), (1.0, 8)):
            with self.subTest(value=value, width=width), self.assertRaises((TypeError, ValueError)):
                even_parity(value, width)

    def test_valid_parity_checked_during_idle_and_invalid_data_is_ignored(self):
        self.assertEqual(check_orig_data(False, None, None, None, 0, None, None, None), frozenset())
        self.assertEqual(check_orig_data(False, None, None, None, 1, None, None, None), frozenset({"valid"}))
        self.assertEqual(check_orig_data(True, 0, 0, 0, 0, 0, 0, 0), frozenset({"valid"}))

    def test_all_512_data_bit_errors_are_checked_even_if_byte_mask_is_zero(self):
        for bit in range(512):
            with self.subTest(bit=bit):
                self.assertEqual(check_orig_data(True, 1 << bit, 0, 0, 1, 0, 0, 0),
                                 frozenset({"data" + str(bit // 64)}))

    def test_all_eight_data_parity_bits_are_individually_checked(self):
        for group in range(8):
            self.assertEqual(check_orig_data(True, 0, 0, 0, 1, 1 << group, 0, 0),
                             frozenset({"data" + str(group)}))
        self.assertEqual(check_orig_data(True, (1 << 512) - 1, (1 << 64) - 1, 0, 1, 0, 0, 0), frozenset())

    def test_byte_enable_bits_and_its_parity_have_separate_protection(self):
        for bit in range(64):
            self.assertEqual(check_orig_data(True, 0, 1 << bit, 0, 1, 0, 0, 0), frozenset({"byte_enable"}))
        self.assertEqual(check_orig_data(True, 0, 0, 0, 1, 0, 1, 0), frozenset({"byte_enable"}))

    def test_control_fields_and_control_parity_detect_errors_separately(self):
        for bit in range(9):
            self.assertEqual(check_orig_data(True, 0, 0, 1 << bit, 1, 0, 0, 0), frozenset({"control"}))
        self.assertEqual(check_orig_data(True, 0, 0, 0, 1, 0, 0, 1), frozenset({"control"}))

    def test_credit_valid_vector_parity_checked_on_all_16_masks_including_idle(self):
        for mask in range(16):
            parity = mask.bit_count() % 2
            self.assertEqual(check_credit(mask, 0, 0, 0, parity, 0), frozenset())
            self.assertEqual(check_credit(mask, 0, 0, 0, parity ^ 1, 0), frozenset({"valid"}))
        self.assertEqual(check_credit(0, None, None, None, 0, None), frozenset())

    def test_inactive_port_credit_controls_remain_protected_when_another_port_is_valid(self):
        # Port0 valid, but all four ports' VC/Num/Pool fields enter the same parity group.
        for bit in range(20):
            vector = 1 << bit
            self.assertEqual(check_credit(1, vector & 255, (vector >> 8) & 255, vector >> 16, 1, 0),
                             frozenset({"control"}))
        self.assertEqual(check_credit(1, 0, 0, 0, 1, 1), frozenset({"control"}))

    def test_active_out_of_range_inputs_are_not_truncated(self):
        with self.assertRaises(ValueError):
            check_orig_data(True, 1 << 512, 0, 0, 1, 0, 0, 0)
        with self.assertRaises(ValueError):
            check_credit(16, 0, 0, 0, 0, 0)
        with self.assertRaises(ValueError):
            check_credit(1, 256, 0, 0, 1, 0)


if __name__ == "__main__":
    unittest.main()
