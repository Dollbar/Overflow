#!/usr/bin/env python3
"""Generate deterministic bit-exact FP32 vector-unit reference data."""

from __future__ import annotations

import argparse
import random
from fractions import Fraction
from pathlib import Path


RNE = 0
RTZ = 1
RUP = 2
RDN = 3
FP32_CANONICAL_NAN = 0x7FC00000
FP32_POSITIVE_INF = 0x7F800000
FP32_MAX_FINITE = 0x7F7FFFFF


def decode_fp32(bits: int) -> tuple[str, int, Fraction]:
    sign = (bits >> 31) & 1
    exponent = (bits >> 23) & 0xFF
    fraction = bits & 0x7FFFFF
    if exponent == 0:
        if fraction == 0:
            return "zero", sign, Fraction(0)
        value = Fraction(fraction, 1 << 23) * Fraction(1, 1 << 126)
    elif exponent == 0xFF:
        return ("inf" if fraction == 0 else "nan"), sign, Fraction(0)
    else:
        significand = Fraction((1 << 23) | fraction, 1 << 23)
        unbiased = exponent - 127
        value = significand * (Fraction(1 << unbiased) if unbiased >= 0 else Fraction(1, 1 << -unbiased))
    return "finite", sign, -value if sign else value


def floor_log2(value: Fraction) -> int:
    exponent = value.numerator.bit_length() - value.denominator.bit_length()
    if exponent >= 0:
        if value.numerator < (value.denominator << exponent):
            exponent -= 1
    elif (value.numerator << -exponent) < value.denominator:
        exponent -= 1
    return exponent


def should_increment(main: int, remainder: int, denominator: int, rounding: int, sign: int) -> bool:
    if remainder == 0:
        return False
    if rounding == RNE:
        doubled = remainder << 1
        return doubled > denominator or (doubled == denominator and (main & 1) != 0)
    if rounding == RUP:
        return sign == 0
    if rounding == RDN:
        return sign == 1
    return False


def overflow_result(sign: int, rounding: int) -> int:
    to_inf = rounding == RNE or (rounding == RUP and sign == 0) or (rounding == RDN and sign == 1)
    magnitude = FP32_POSITIVE_INF if to_inf else FP32_MAX_FINITE
    return (sign << 31) | magnitude


def round_fraction_to_fp32(value: Fraction, rounding: int, zero_sign: int = 0) -> int:
    if value == 0:
        return zero_sign << 31
    sign = int(value < 0)
    magnitude = abs(value)
    exponent = floor_log2(magnitude)
    if exponent >= -126:
        scale = 23 - exponent
        numerator = magnitude.numerator << scale if scale >= 0 else magnitude.numerator
        denominator = magnitude.denominator if scale >= 0 else magnitude.denominator << -scale
        main, remainder = divmod(numerator, denominator)
        if should_increment(main, remainder, denominator, rounding, sign):
            main += 1
        if main == (1 << 24):
            main >>= 1
            exponent += 1
        if exponent > 127:
            return overflow_result(sign, rounding)
        return (sign << 31) | ((exponent + 127) << 23) | (main & 0x7FFFFF)

    numerator = magnitude.numerator << 149
    main, remainder = divmod(numerator, magnitude.denominator)
    if should_increment(main, remainder, magnitude.denominator, rounding, sign):
        main += 1
    if main >= (1 << 23):
        return (sign << 31) | (1 << 23)
    return (sign << 31) | main


def multiply_fp32(a_bits: int, b_bits: int, invalid_in: int, rounding: int) -> tuple[int, int]:
    a_kind, a_sign, a_value = decode_fp32(a_bits)
    b_kind, b_sign, b_value = decode_fp32(b_bits)
    sign = a_sign ^ b_sign
    invalid = int(invalid_in != 0)
    if a_kind == "nan" or b_kind == "nan":
        return FP32_CANONICAL_NAN, invalid
    if (a_kind == "inf" and b_kind == "zero") or (a_kind == "zero" and b_kind == "inf"):
        return FP32_CANONICAL_NAN, 1
    if a_kind == "inf" or b_kind == "inf":
        return (sign << 31) | FP32_POSITIVE_INF, invalid
    if a_kind == "zero" or b_kind == "zero":
        return sign << 31, invalid
    return round_fraction_to_fp32(a_value * b_value, rounding), invalid


def decode_fp8(bits: int, fmt: int) -> tuple[str, int, Fraction]:
    sign = (bits >> 7) & 1
    fraction_width, bias = (3, 7) if fmt == 0 else (2, 15)
    exponent_width = 7 - fraction_width
    exponent_mask = (1 << exponent_width) - 1
    exponent = (bits >> fraction_width) & exponent_mask
    fraction = bits & ((1 << fraction_width) - 1)
    if exponent == 0:
        if fraction == 0:
            return "zero", sign, Fraction(0)
        value = Fraction(fraction, 1 << fraction_width) * Fraction(1, 1 << (bias - 1))
    elif fmt == 0 and exponent == exponent_mask and fraction == (1 << fraction_width) - 1:
        return "nan", sign, Fraction(0)
    elif fmt == 1 and exponent == exponent_mask:
        return ("inf" if fraction == 0 else "nan"), sign, Fraction(0)
    else:
        unbiased = exponent - bias
        value = Fraction((1 << fraction_width) | fraction, 1 << fraction_width)
        value *= Fraction(1 << unbiased) if unbiased >= 0 else Fraction(1, 1 << -unbiased)
    return "finite", sign, -value if sign else value


def fp8_to_fp32_bits(bits: int, fmt: int) -> int:
    kind, sign, value = decode_fp8(bits, fmt)
    if kind == "nan":
        return FP32_CANONICAL_NAN
    if kind == "inf":
        return (sign << 31) | FP32_POSITIVE_INF
    return round_fraction_to_fp32(value, RNE, sign)


def fp32_to_fp8_bits(bits: int, fmt: int, rounding: int) -> tuple[int, int, int]:
    kind, sign, value = decode_fp32(bits)
    fraction_width, bias = (3, 7) if fmt == 0 else (2, 15)
    exponent_mask = (1 << (7 - fraction_width)) - 1
    max_exponent = 8 if fmt == 0 else 15
    max_fraction = 6 if fmt == 0 else (1 << fraction_width) - 1
    max_finite = (sign << 7) | ((exponent_mask if fmt == 0 else exponent_mask - 1) << fraction_width) | max_fraction
    if kind == "nan":
        return (0x7F if fmt == 0 else 0x7E), 0, 0
    if kind == "inf":
        if fmt == 1:
            return (sign << 7) | 0x7C, 0, 0
        return max_finite, 1, 0
    if kind == "zero":
        return sign << 7, 0, 0

    magnitude = abs(value)
    exponent = floor_log2(magnitude)
    inexact = 0
    if exponent >= 1 - bias:
        scale = fraction_width - exponent
        numerator = magnitude.numerator << scale if scale >= 0 else magnitude.numerator
        denominator = magnitude.denominator if scale >= 0 else magnitude.denominator << -scale
        main, remainder = divmod(numerator, denominator)
        inexact = int(remainder != 0)
        if should_increment(main, remainder, denominator, rounding, sign):
            main += 1
        if main == (1 << (fraction_width + 1)):
            main >>= 1
            exponent += 1
        fraction = main & ((1 << fraction_width) - 1)
        if exponent > max_exponent or (fmt == 0 and exponent == max_exponent and fraction == 7):
            return max_finite, 1, inexact
        encoded = (sign << 7) | ((exponent + bias) << fraction_width) | fraction
        return encoded, 0, inexact

    min_subnormal_exponent = 1 - bias - fraction_width
    scale = -min_subnormal_exponent
    numerator = magnitude.numerator << scale
    main, remainder = divmod(numerator, magnitude.denominator)
    inexact = int(remainder != 0)
    if should_increment(main, remainder, magnitude.denominator, rounding, sign):
        main += 1
    if main >= (1 << fraction_width):
        return (sign << 7) | (1 << fraction_width), 0, inexact
    return (sign << 7) | main, 0, inexact


def ordered_compare(a_bits: int, b_bits: int) -> tuple[int, int, int, int, int, int, int, int]:
    a_kind, _, _ = decode_fp32(a_bits)
    b_kind, _, _ = decode_fp32(b_bits)
    unordered = int(a_kind == "nan" or b_kind == "nan")
    if unordered:
        equal = less = greater = 0
    else:
        a_zero = (a_bits & 0x7FFFFFFF) == 0
        b_zero = (b_bits & 0x7FFFFFFF) == 0
        equal = int(a_bits == b_bits or (a_zero and b_zero))
        if equal:
            less = greater = 0
        elif ((a_bits ^ b_bits) >> 31) != 0:
            less = (a_bits >> 31) & 1
            greater = 1 - less
        elif (a_bits >> 31) == 0:
            less = int((a_bits & 0x7FFFFFFF) < (b_bits & 0x7FFFFFFF))
            greater = 1 - less
        else:
            less = int((a_bits & 0x7FFFFFFF) > (b_bits & 0x7FFFFFFF))
            greater = 1 - less
    if a_kind == "nan" and b_kind == "nan":
        minimum = maximum = FP32_CANONICAL_NAN
    elif a_kind == "nan":
        minimum = maximum = b_bits
    elif b_kind == "nan":
        minimum = maximum = a_bits
    elif equal:
        if (a_bits & 0x7FFFFFFF) == 0 and (b_bits & 0x7FFFFFFF) == 0:
            minimum = 0x80000000 if ((a_bits | b_bits) >> 31) else 0
            maximum = 0 if (((a_bits & b_bits) >> 31) == 0) else 0x80000000
        else:
            minimum = maximum = a_bits
    elif less:
        minimum, maximum = a_bits, b_bits
    else:
        minimum, maximum = b_bits, a_bits
    return equal, less, int(equal or less), greater, int(equal or greater), unordered, minimum, maximum


def directed_pairs() -> list[tuple[int, int]]:
    return [
        (0x3F800000, 0x40000000), (0xBF800000, 0x40000000),
        (0x00000000, 0xFF800000), (0x80000000, 0x7F800000),
        (0x7F800000, 0x3F800000), (0xFF800000, 0xBF800000),
        (0x7FC00001, 0x3F800000), (0x7F800001, 0xFFC00001),
        (0x00000001, 0x3F800000), (0x007FFFFF, 0x3F800001),
        (0x00800000, 0x3F000000), (0x00800000, 0x00800000),
        (0x7F7FFFFF, 0x40000000), (0xFF7FFFFF, 0x40000000),
        (0x3F800001, 0x3F800001), (0x3F7FFFFF, 0x3F7FFFFF),
        (0x00000000, 0x80000000), (0x80000000, 0x00000000),
    ]


def write_mul_vectors(path: Path, count: int, rng: random.Random) -> None:
    transactions: list[tuple[int, int, int, int]] = []
    for a_bits, b_bits in directed_pairs():
        for rounding in range(4):
            transactions.append((a_bits, b_bits, rounding & 3, rounding))
    while len(transactions) < count:
        transactions.append((rng.getrandbits(32), rng.getrandbits(32), rng.randrange(4), rng.randrange(4)))
    lines = []
    for a_bits, b_bits, invalid_in, rounding in transactions[:count]:
        result, invalid_out = multiply_fp32(a_bits, b_bits, invalid_in, rounding)
        packed = (((((a_bits << 32) | b_bits) << 2 | invalid_in) << 2 | rounding) << 32 | result) << 1 | invalid_out
        lines.append(f"{packed:026x}\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(lines), encoding="ascii")


def write_compare_vectors(path: Path, count: int, rng: random.Random) -> None:
    pairs = directed_pairs()
    while len(pairs) < count:
        pairs.append((rng.getrandbits(32), rng.getrandbits(32)))
    lines = []
    for a_bits, b_bits in pairs[:count]:
        equal, less, less_equal, greater, greater_equal, unordered, minimum, maximum = ordered_compare(a_bits, b_bits)
        flags = (equal << 5) | (less << 4) | (less_equal << 3) | (greater << 2) | (greater_equal << 1) | unordered
        packed = (((a_bits << 32) | b_bits) << 6 | flags) << 64 | (minimum << 32) | maximum
        lines.append(f"{packed:034x}\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(lines), encoding="ascii")


def write_fp8_to_fp32_vectors(path: Path) -> None:
    lines = []
    for fmt in range(2):
        for data in range(256):
            packed = (((data << 1) | fmt) << 32) | fp8_to_fp32_bits(data, fmt)
            lines.append(f"{packed:011x}\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(lines), encoding="ascii")


def write_fp32_to_fp8_vectors(path: Path, count: int, rng: random.Random) -> None:
    directed = [
        0x00000000, 0x80000000, 0x00000001, 0x80000001,
        0x3F800000, 0xBF800000, 0x3F880000, 0x3F900000,
        0x3B000000, 0x3A800000, 0x38800000, 0x37800000,
        0x43DF8000, 0x43E00000, 0x43E10000, 0xC3E10000,
        0x475F8000, 0x47600000, 0x47610000, 0xC7610000,
        0x7F7FFFFF, 0xFF7FFFFF, 0x7F800000, 0xFF800000,
        0x7FC00001, 0xFFC00001,
    ]
    transactions: list[tuple[int, int, int]] = []
    for bits in directed:
        for fmt in range(2):
            for rounding in range(4):
                transactions.append((bits, fmt, rounding))
    while len(transactions) < count:
        transactions.append((rng.getrandbits(32), rng.randrange(2), rng.randrange(4)))
    lines = []
    for bits, fmt, rounding in transactions[:count]:
        result, overflow, inexact = fp32_to_fp8_bits(bits, fmt, rounding)
        packed = (((((bits << 1) | fmt) << 2 | rounding) << 8 | result) << 1 | overflow) << 1 | inexact
        lines.append(f"{packed:012x}\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(lines), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mul-output", type=Path, required=True)
    parser.add_argument("--compare-output", type=Path, required=True)
    parser.add_argument("--fp8-to-fp32-output", type=Path)
    parser.add_argument("--fp32-to-fp8-output", type=Path)
    parser.add_argument("--count", type=int, default=4096)
    args = parser.parse_args()
    rng = random.Random(0x564543544F525F4650)
    write_mul_vectors(args.mul_output, args.count, rng)
    write_compare_vectors(args.compare_output, args.count, rng)
    if args.fp8_to_fp32_output is not None:
        write_fp8_to_fp32_vectors(args.fp8_to_fp32_output)
    if args.fp32_to_fp8_output is not None:
        write_fp32_to_fp8_vectors(args.fp32_to_fp8_output, args.count, rng)


if __name__ == "__main__":
    main()
