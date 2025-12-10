#!/usr/bin/env python3
"""Generate deterministic vectors for the Softmax-domain FP32 exp approximation."""

from __future__ import annotations

import argparse
import math
import random
import struct
from pathlib import Path


FP32_CANONICAL_NAN = 0x7FC00000
FP32_ONE = 0x3F800000
FP32_NEGATIVE_SIXTEEN = 0xC1800000
LOG2_E_Q16 = 94548
ANCHORS_Q23 = (
    0x800000,
    0x7A92BF,
    0x756063,
    0x70666F,
    0x6BA27E,
    0x671246,
    0x62B395,
    0x5E8452,
    0x5A827A,
    0x56AC1F,
    0x52FF6B,
    0x4F7A99,
    0x4C1BF8,
    0x48E1EA,
    0x45CAE1,
    0x42D562,
    0x400000,
)


def float_to_bits(value: float) -> int:
    return struct.unpack(">I", struct.pack(">f", value))[0]


def bits_to_float(bits: int) -> float:
    return struct.unpack(">f", struct.pack(">I", bits & 0xFFFFFFFF))[0]


def exp_approx_bits(data_bits: int, invalid_in: int) -> tuple[int, int]:
    sign = (data_bits >> 31) & 1
    exponent = (data_bits >> 23) & 0xFF
    fraction = data_bits & 0x7FFFFF
    magnitude = data_bits & 0x7FFFFFFF
    is_nan = exponent == 0xFF and fraction != 0
    is_inf = exponent == 0xFF and fraction == 0
    is_zero = magnitude == 0
    positive_nonzero = sign == 0 and not is_zero
    below_range = sign == 1 and magnitude > (FP32_NEGATIVE_SIXTEEN & 0x7FFFFFFF)

    invalid = int(bool(invalid_in))
    if is_nan:
        return FP32_CANONICAL_NAN, 1
    if is_inf:
        if sign:
            return 0, invalid
        return FP32_ONE, 1
    if is_zero:
        return FP32_ONE, invalid
    if positive_nonzero:
        return FP32_ONE, 1
    if below_range:
        return 0, invalid

    magnitude_q16 = 0
    if 111 <= exponent <= 131:
        significand = (1 << 23) | fraction
        magnitude_q16 = significand >> (134 - exponent)

    range_product = magnitude_q16 * LOG2_E_Q16
    range_increment = int(
        ((range_product >> 15) & 1) != 0
        and ((range_product & 0x7FFF) != 0 or ((range_product >> 16) & 1) != 0)
    )
    range_q16 = (range_product >> 16) + range_increment
    integer_part = range_q16 >> 16
    fraction_part = range_q16 & 0xFFFF
    segment = fraction_part >> 12
    remainder = fraction_part & 0xFFF
    high = ANCHORS_Q23[segment]
    low = ANCHORS_Q23[segment + 1]
    interpolation_product = (high - low) * remainder
    interpolation_increment = int(
        ((interpolation_product >> 11) & 1) != 0
        and (
            (interpolation_product & 0x7FF) != 0
            or ((interpolation_product >> 12) & 1) != 0
        )
    )
    correction = (interpolation_product >> 12) + interpolation_increment
    interpolated = high - correction

    if fraction_part == 0:
        significand = interpolated
        biased_exponent = 127 - integer_part
    else:
        significand = (interpolated << 1) & 0xFFFFFF
        biased_exponent = 126 - integer_part
    result = ((biased_exponent & 0xFF) << 23) | (significand & 0x7FFFFF)
    return result, invalid


def directed_inputs() -> list[tuple[int, int]]:
    values = [
        0.0,
        -0.0,
        -2.0**-20,
        -2.0**-16,
        -0.001,
        -0.03125,
        -0.0625,
        -0.5,
        -1.0,
        -2.0,
        -4.0,
        -8.0,
        -15.5,
        -15.999,
        -16.0,
        -16.001,
        -20.0,
        2.0**-20,
        0.5,
        1.0,
    ]
    vectors = [(float_to_bits(value), 0) for value in values]
    vectors.extend(
        [
            (0xFF800000, 0),
            (0x7F800000, 0),
            (0x7FC00001, 0),
            (0xFFC12345, 0),
            (float_to_bits(-1.0), 1),
            (float_to_bits(-16.0), 1),
            (0x80000001, 0),
            (0x00000001, 0),
        ]
    )
    return vectors


def generate_inputs(count: int, seed: int) -> list[tuple[int, int]]:
    rng = random.Random(seed)
    vectors = directed_inputs()
    while len(vectors) < count:
        selection = rng.randrange(10)
        if selection < 7:
            value = -16.0 * rng.random()
            bits = float_to_bits(value)
        elif selection == 7:
            bits = float_to_bits(-16.0 - 64.0 * rng.random())
        elif selection == 8:
            bits = float_to_bits(16.0 * rng.random())
        else:
            bits = rng.getrandbits(32)
        vectors.append((bits, int(rng.randrange(32) == 0)))
    return vectors[:count]


def write_vectors(output: Path, count: int, seed: int) -> None:
    vectors = generate_inputs(count, seed)
    output.parent.mkdir(parents=True, exist_ok=True)
    maximum_relative_error = 0.0
    maximum_absolute_error = 0.0
    measured_count = 0
    with output.open("w", encoding="ascii") as handle:
        for data_bits, invalid_in in vectors:
            expected_bits, invalid_out = exp_approx_bits(data_bits, invalid_in)
            packed = (
                (data_bits << 34)
                | ((invalid_in & 1) << 33)
                | (expected_bits << 1)
                | (invalid_out & 1)
            )
            handle.write(f"{packed:017x}\n")

            value = bits_to_float(data_bits)
            if math.isfinite(value) and -16.0 <= value <= 0.0:
                approximate = bits_to_float(expected_bits)
                exact = math.exp(value)
                absolute_error = abs(approximate - exact)
                relative_error = absolute_error / exact
                maximum_absolute_error = max(maximum_absolute_error, absolute_error)
                maximum_relative_error = max(maximum_relative_error, relative_error)
                measured_count += 1

    if maximum_relative_error > 0.01:
        raise RuntimeError(
            f"relative error {maximum_relative_error:.8f} exceeds 1% contract"
        )
    print(
        "Generated "
        f"{len(vectors)} fp32_exp_approx vectors; measured={measured_count} "
        f"max_relative_error={maximum_relative_error:.8f} "
        f"max_absolute_error={maximum_absolute_error:.8e}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--count", type=int, default=4096)
    parser.add_argument("--seed", type=int, default=0xE4A3)
    args = parser.parse_args()
    write_vectors(args.output, args.count, args.seed)


if __name__ == "__main__":
    main()
