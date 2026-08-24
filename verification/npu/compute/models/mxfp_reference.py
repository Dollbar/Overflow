#!/usr/bin/env python3
"""Deterministic OCP MXFP4/MXFP8 decode and block-dot reference vectors."""

from __future__ import annotations

import argparse
import math
import struct
from pathlib import Path


MXFP4_E2M1 = 0
MXFP8_E4M3 = 1


def f32_bits(value: float) -> int:
    try:
        return struct.unpack(">I", struct.pack(">f", value))[0]
    except OverflowError:
        return 0xFF800000 if math.copysign(1.0, value) < 0 else 0x7F800000


def scale_value(scale: int) -> float:
    if scale == 0xFF:
        return math.nan
    return math.ldexp(1.0, scale - 127)


def decode_element(raw: int, fmt: int) -> float:
    if fmt == MXFP4_E2M1:
        raw &= 0xF
        sign = -1.0 if raw & 0x8 else 1.0
        exponent = (raw >> 1) & 0x3
        fraction = raw & 0x1
        if exponent == 0:
            return sign * math.ldexp(float(fraction), -1)
        return sign * math.ldexp(1.0 + fraction / 2.0, exponent - 1)
    if fmt == MXFP8_E4M3:
        raw &= 0xFF
        sign = -1.0 if raw & 0x80 else 1.0
        exponent = (raw >> 3) & 0xF
        fraction = raw & 0x7
        if exponent == 0xF and fraction == 0x7:
            return math.nan
        if exponent == 0:
            return sign * math.ldexp(fraction / 8.0, -6)
        return sign * math.ldexp(1.0 + fraction / 8.0, exponent - 7)
    return math.nan


def decode_mx(raw: int, fmt: int, scale: int) -> float:
    element = decode_element(raw, fmt)
    shared = scale_value(scale)
    return element * shared


def block_dot(a: list[int], b: list[int], a_fmt: int, b_fmt: int,
              a_scale: int, b_scale: int) -> float:
    if len(a) != 32 or len(b) != 32:
        raise ValueError("MX block dot requires exactly 32 elements")
    products = [decode_element(x, a_fmt) * decode_element(y, b_fmt)
                for x, y in zip(a, b)]
    if any(math.isnan(value) for value in products):
        return math.nan
    return sum(products) * scale_value(a_scale) * scale_value(b_scale)


def vectors() -> list[tuple[int, int, int, int, int]]:
    cases: list[tuple[int, int, int, int, int]] = []
    raw_values = {
        MXFP4_E2M1: [0x0, 0x1, 0x2, 0x3, 0x7, 0x8, 0xF],
        MXFP8_E4M3: [0x00, 0x01, 0x07, 0x08, 0x38, 0x7E, 0x7F, 0xFF],
    }
    for fmt, values in raw_values.items():
        for scale in (0x00, 0x7E, 0x7F, 0x80, 0xFE, 0xFF):
            for raw in values:
                value = decode_mx(raw, fmt, scale)
                bits = 0x7FC00000 if math.isnan(value) else f32_bits(value)
                cases.append((fmt, raw, scale, bits, int(math.isnan(value))))
    return cases


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii") as stream:
        for fmt, raw, scale, bits, is_nan in vectors():
            stream.write(f"{fmt:01x}{raw:02x}{scale:02x}{bits:08x}{is_nan:01x}\n")


if __name__ == "__main__":
    main()
