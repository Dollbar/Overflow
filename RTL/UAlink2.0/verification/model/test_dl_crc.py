"""WP03 arithmetic tests. Passing these does NOT approve wire CRC ordering."""

import random
import unittest
import zlib

try:
    from model.ualink.dl_crc import dl_crc_polynomial
except ModuleNotFoundError as error:
    if error.name != "model.ualink.dl_crc":
        raise
    dl_crc_polynomial = None


def polynomial_oracle(flit):
    """Test-only Appendix A long division, independent of an LFSR recurrence."""
    sequence = [(octet >> bit) & 1 for octet in flit[:636] + bytes(4) for bit in range(8)]
    for index in range(32):
        sequence[index] ^= 1
    dividend = int("".join(str(bit) for bit in sequence), 2) << 32
    divisor = sum(1 << power for power in (32, 26, 23, 22, 16, 12, 11, 10, 8, 7, 5, 4, 2, 1, 0))
    while dividend.bit_length() >= divisor.bit_length():
        dividend ^= divisor << (dividend.bit_length() - divisor.bit_length())
    return dividend ^ 0xFFFFFFFF


def appendix_flit():
    """Literal fixture from L Figure 2-4 and Appendix A, not a DUT packer."""
    flit = bytearray(640)
    flit[624:627] = bytes.fromhex("00ff4f")
    return flit


class DlCrcTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(dl_crc_polynomial, "WP03 CRC mathematics is not implemented")

    def test_appendix_numeric_pair_with_explicit_integer_conventions(self):
        # Catches omitted output reflection when returning polynomial coefficients.
        flit = appendix_flit()
        self.assertEqual(zlib.crc32(flit), 0x4009BC57)
        self.assertEqual(polynomial_oracle(flit), 0xEA3D9002)
        self.assertEqual(dl_crc_polynomial(flit), 0xEA3D9002)

    def test_exact_640_byte_coverage_not_636_byte_fcs(self):
        flit = appendix_flit()
        omitted_tail = int(f"{zlib.crc32(flit[:636]):032b}"[::-1], 2)
        self.assertNotEqual(dl_crc_polynomial(flit), omitted_tail)

    def test_crc_field_is_zeroed_without_mutating_caller_input(self):
        flit = appendix_flit()
        flit[-4:] = bytes.fromhex("12345678")
        before = bytes(flit)
        self.assertEqual(dl_crc_polynomial(flit), 0xEA3D9002)
        self.assertEqual(bytes(flit), before)

    def test_every_received_crc_bit_is_excluded_from_recalculation(self):
        for bit in range(32):
            flit = appendix_flit()
            flit[636 + bit // 8] ^= 1 << (bit % 8)
            with self.subTest(bit=bit):
                self.assertEqual(dl_crc_polynomial(flit), 0xEA3D9002)

    def test_bad_length_or_non_byte_container_is_rejected(self):
        for length in (0, 1, 4, 636, 639, 641, 1280):
            with self.subTest(length=length), self.assertRaises(ValueError):
                dl_crc_polynomial(bytes(length))
        for value in (640, None, "0" * 640, [0] * 640):
            with self.subTest(kind=type(value).__name__), self.assertRaises(TypeError):
                dl_crc_polynomial(value)

    def test_asymmetric_inputs_match_independent_long_division(self):
        for flit in (bytes(640), bytes([255]) * 640,
                     bytes(index % 256 for index in range(640)),
                     bytes((index * 37 + 11) % 256 for index in range(640))):
            with self.subTest(prefix=flit[:8].hex()):
                self.assertEqual(dl_crc_polynomial(flit), polynomial_oracle(flit))

    def test_seeded_random_inputs_cross_check_two_independent_methods(self):
        rng = random.Random(0x55414C)
        for trial in range(128):
            flit = rng.randbytes(640)
            library_coefficients = int(f"{zlib.crc32(flit[:636] + bytes(4)):032b}"[::-1], 2)
            with self.subTest(trial=trial):
                self.assertEqual(dl_crc_polynomial(flit), polynomial_oracle(flit))
                self.assertEqual(dl_crc_polynomial(flit), library_coefficients)

    def test_every_non_crc_bit_changes_result_and_matches_library_oracle(self):
        # All 5088 positions: header, segment headers and payload; no wire checker implied.
        original = appendix_flit()
        for bit in range(5088):
            flit = bytearray(original)
            flit[bit // 8] ^= 1 << (bit % 8)
            expected = int(f"{zlib.crc32(flit):032b}"[::-1], 2)
            with self.subTest(bit=bit):
                actual = dl_crc_polynomial(flit)
                self.assertEqual(actual, expected)
                self.assertNotEqual(actual, 0xEA3D9002)


if __name__ == "__main__":
    unittest.main()
