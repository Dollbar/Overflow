import pytest

from kdlink_model.pcs import (
    SCRAMBLER_INITIAL_STATE,
    decode_flit_blocks,
    descramble_word,
    encode_flit_blocks,
    scramble_word,
)


def test_640_bit_flit_round_trip_through_ten_66_bit_blocks() -> None:
    flit = int.from_bytes(bytes(range(80)), "little")
    blocks = encode_flit_blocks(flit)
    assert len(blocks) == 10
    assert all(block & 0b11 == 0b01 for block in blocks)
    assert decode_flit_blocks(blocks) == flit


def test_pcs_rejects_invalid_sync_header() -> None:
    blocks = list(encode_flit_blocks(0x1234))
    blocks[4] ^= 0b11
    with pytest.raises(ValueError, match="invalid PCS"):
        decode_flit_blocks(tuple(blocks))


def test_scrambler_round_trip_preserves_continuous_lane_state() -> None:
    tx_state = SCRAMBLER_INITIAL_STATE
    rx_state = SCRAMBLER_INITIAL_STATE
    for word in (0, 0x0123456789ABCDEF, 0xFFFFFFFFFFFFFFFF, 0xA5A55A5AF00F0FF0):
        scrambled, tx_state = scramble_word(word, tx_state)
        recovered, rx_state = descramble_word(scrambled, rx_state)
        assert recovered == word
        assert rx_state == tx_state
