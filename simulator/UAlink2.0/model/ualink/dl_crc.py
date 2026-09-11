"""WP03 CRC mathematics; wire serialization is NOT frozen (see A19).

Input: 640 DL octets in Figure 2-4 order, bit 0 first in each octet.
Output: polynomial coefficients, integer bit i is the coefficient of x**i.
No PCS sync headers, scrambler or FEC bits are included. This function does
not pack a transmit CRC or classify a received flit as protocol-valid.
"""


def dl_crc_polynomial(flit: bytes | bytearray) -> int:
    """Return the complemented 32-bit remainder, zeroing the four CRC octets.

    Source: L 200G 2.0 §2.3.7 and Appendix A's polynomial procedure. Initial
    all-ones LFSR state implements complementing the first 32 input bits in
    the augmented-polynomial formulation. Tests independently use long
    division, not this recurrence. No caller buffer is modified.
    """
    if not isinstance(flit, (bytes, bytearray)):
        raise TypeError("flit must be bytes or bytearray")
    if len(flit) != 640:
        raise ValueError("DL CRC requires exactly 640 octets including the CRC field")
    remainder = 0xFFFFFFFF
    for offset, octet in enumerate(flit):
        if offset >= 636:
            octet = 0
        for bit_index in range(8):
            feedback = (remainder >> 31) ^ ((octet >> bit_index) & 1)
            remainder = (remainder << 1) & 0xFFFFFFFF
            if feedback:
                remainder ^= 0x04C11DB7
    return remainder ^ 0xFFFFFFFF
