"""KDLink 64b/66b data-block codec for one 640-bit logical flit."""

from __future__ import annotations

from .constants import FLIT_WIDTH, PCS_BLOCK_DATA_WIDTH, PCS_BLOCK_WIDTH, PCS_BLOCKS_PER_FLIT


DATA_SYNC_HEADER = 0b01
SCRAMBLER_MASK = (1 << 58) - 1
SCRAMBLER_INITIAL_STATE = SCRAMBLER_MASK


def encode_flit_blocks(flit: int) -> tuple[int, ...]:
    if flit < 0 or flit >= (1 << FLIT_WIDTH):
        raise ValueError("flit does not fit the KDLink logical width")
    mask = (1 << PCS_BLOCK_DATA_WIDTH) - 1
    return tuple((((flit >> (index * PCS_BLOCK_DATA_WIDTH)) & mask) << 2) | DATA_SYNC_HEADER
                 for index in range(PCS_BLOCKS_PER_FLIT))


def decode_flit_blocks(blocks: tuple[int, ...]) -> int:
    if len(blocks) != PCS_BLOCKS_PER_FLIT:
        raise ValueError("incorrect PCS block count")
    flit = 0
    for index, block in enumerate(blocks):
        if block < 0 or block >= (1 << PCS_BLOCK_WIDTH) or block & 0b11 != DATA_SYNC_HEADER:
            raise ValueError("invalid PCS data block")
        flit |= (block >> 2) << (index * PCS_BLOCK_DATA_WIDTH)
    return flit


def scramble_word(word: int, state: int = SCRAMBLER_INITIAL_STATE) -> tuple[int, int]:
    if word < 0 or word >= (1 << PCS_BLOCK_DATA_WIDTH):
        raise ValueError("word does not fit a PCS data block")
    if state < 0 or state > SCRAMBLER_MASK:
        raise ValueError("scrambler state does not fit 58 bits")
    output = 0
    for bit_index in range(PCS_BLOCK_DATA_WIDTH):
        scrambled_bit = ((word >> bit_index) & 1) ^ ((state >> 38) & 1) ^ ((state >> 57) & 1)
        output |= scrambled_bit << bit_index
        state = ((state << 1) | scrambled_bit) & SCRAMBLER_MASK
    return output, state


def descramble_word(word: int, state: int = SCRAMBLER_INITIAL_STATE) -> tuple[int, int]:
    if word < 0 or word >= (1 << PCS_BLOCK_DATA_WIDTH):
        raise ValueError("word does not fit a PCS data block")
    if state < 0 or state > SCRAMBLER_MASK:
        raise ValueError("descrambler state does not fit 58 bits")
    output = 0
    for bit_index in range(PCS_BLOCK_DATA_WIDTH):
        scrambled_bit = (word >> bit_index) & 1
        output_bit = scrambled_bit ^ ((state >> 38) & 1) ^ ((state >> 57) & 1)
        output |= output_bit << bit_index
        state = ((state << 1) | scrambled_bit) & SCRAMBLER_MASK
    return output, state
