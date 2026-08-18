"""Helpers for deterministic little-endian protocol bit fields."""

from __future__ import annotations


def get_bits(value: int, lsb: int, width: int) -> int:
    return (value >> lsb) & ((1 << width) - 1)


def put_bits(value: int, field: int, lsb: int, width: int) -> int:
    mask = ((1 << width) - 1) << lsb
    if field < 0 or field >= (1 << width):
        raise ValueError(f"field value {field} does not fit in {width} bits")
    return (value & ~mask) | (field << lsb)


def int_to_le_bytes(value: int, width_bits: int) -> bytes:
    if width_bits % 8:
        raise ValueError("width must be byte aligned")
    return value.to_bytes(width_bits // 8, byteorder="little", signed=False)


def le_bytes_to_int(data: bytes) -> int:
    return int.from_bytes(data, byteorder="little", signed=False)
