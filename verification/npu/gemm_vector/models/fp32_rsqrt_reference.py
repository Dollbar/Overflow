#!/usr/bin/env python3
"""Generate deterministic vectors for the LayerNorm/RMSNorm FP32 rsqrt unit."""

from __future__ import annotations

import argparse
import math
import random
import struct
from pathlib import Path


FP32_CANONICAL_NAN = 0x7FC00000
FP32_POSITIVE_INFINITY = 0x7F800000
EVEN_ANCHORS_Q23 = (
    0x800000, 0x7C2DA1, 0x78ADF7, 0x7575FB, 0x727C97, 0x6FBA41,
    0x6D28A5, 0x6AC267, 0x6882F6, 0x666666, 0x646956, 0x6288D1,
    0x60C248, 0x5F1376, 0x5D7A5D, 0x5BF53A, 0x5A827A,
)
ODD_ANCHORS_Q23 = (
    0x5A827A, 0x57CEAA, 0x555555, 0x530EB0, 0x50F44E, 0x4F00D9,
    0x4D2FD9, 0x4B7D83, 0x49E69D, 0x486861, 0x47006B, 0x45ACA4,
    0x446B3C, 0x433A99, 0x421953, 0x410629, 0x400000,
)


def float_to_bits(value: float) -> int:
    return struct.unpack(">I", struct.pack(">f", value))[0]


def bits_to_float(bits: int) -> float:
    return struct.unpack(">f", struct.pack(">I", bits & 0xFFFFFFFF))[0]


def rsqrt_approx_bits(data_bits: int, invalid_in: int) -> tuple[int, int]:
    sign = (data_bits >> 31) & 1
    exponent = (data_bits >> 23) & 0xFF
    fraction = data_bits & 0x7FFFFF
    magnitude = data_bits & 0x7FFFFFFF
    invalid = int(bool(invalid_in))

    if exponent == 0xFF and fraction != 0:
        return FP32_CANONICAL_NAN, 1
    if sign and magnitude != 0:
        return FP32_CANONICAL_NAN, 1
    if magnitude == 0:
        return FP32_POSITIVE_INFINITY, 1
    if exponent == 0:
        return FP32_POSITIVE_INFINITY, 1
    if exponent == 0xFF:
        return 0, invalid

    unbiased_exponent = exponent - 127
    exponent_odd = unbiased_exponent & 1
    anchors = ODD_ANCHORS_Q23 if exponent_odd else EVEN_ANCHORS_Q23
    segment = fraction >> 19
    remainder = (fraction >> 7) & 0xFFF
    high = anchors[segment]
    low = anchors[segment + 1]
    product = (high - low) * remainder
    truncated = product >> 12
    tail = product & 0xFFF
    increment = int(tail > 0x800 or (tail == 0x800 and (truncated & 1)))
    interpolated = high - truncated - increment

    exponent_half_floor = unbiased_exponent // 2
    if interpolated == 0x800000:
        biased_exponent = 127 - exponent_half_floor
        fraction_out = 0
    else:
        biased_exponent = 126 - exponent_half_floor
        fraction_out = (interpolated << 1) & 0x7FFFFF
    return (biased_exponent << 23) | fraction_out, invalid


def directed_inputs() -> list[tuple[int, int]]:
    values = [
        0.0, -0.0, 2.0**-126, 2.0**-100, 2.0**-20, 1.0e-5,
        0.25, 0.5, 0.99999994, 1.0, 1.0001, 1.0625, 1.5, 2.0,
        3.0, 4.0, 16.0, 256.0, 65536.0, 2.0**100,
    ]
    vectors = [(float_to_bits(value), 0) for value in values]
    vectors.extend(
        [
            (0x7F7FFFFF, 0),
            (0x7F800000, 0),
            (0xFF800000, 0),
            (0x7FC00001, 0),
            (0xFFC12345, 0),
            (float_to_bits(1.0), 1),
            (float_to_bits(3.0), 1),
            (0x00000001, 0),
            (0x007FFFFF, 0),
            (0x80000001, 0),
            (float_to_bits(-1.0), 0),
            (float_to_bits(-16.0), 0),
        ]
    )
    return vectors


def generate_inputs(count: int, seed: int) -> list[tuple[int, int]]:
    rng = random.Random(seed)
    vectors = directed_inputs()
    while len(vectors) < count:
        selection = rng.randrange(12)
        if selection < 9:
            exponent = rng.randrange(1, 255)
            fraction = rng.randrange(1 << 23)
            bits = (exponent << 23) | fraction
        elif selection == 9:
            bits = rng.randrange(1 << 23)
        elif selection == 10:
            bits = 0x80000000 | rng.getrandbits(31)
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
            expected_bits, invalid_out = rsqrt_approx_bits(data_bits, invalid_in)
            packed = (
                (data_bits << 34)
                | ((invalid_in & 1) << 33)
                | (expected_bits << 1)
                | (invalid_out & 1)
            )
            handle.write(f"{packed:017x}\n")

            exponent = (data_bits >> 23) & 0xFF
            if (data_bits >> 31) == 0 and 0 < exponent < 0xFF:
                value = bits_to_float(data_bits)
                approximate = bits_to_float(expected_bits)
                exact = 1.0 / math.sqrt(value)
                absolute_error = abs(approximate - exact)
                relative_error = absolute_error / exact
                maximum_absolute_error = max(maximum_absolute_error, absolute_error)
                maximum_relative_error = max(maximum_relative_error, relative_error)
                measured_count += 1

    if maximum_relative_error > 0.005:
        raise RuntimeError(
            f"relative error {maximum_relative_error:.8f} exceeds 0.5% contract"
        )
    print(
        "Generated "
        f"{len(vectors)} fp32_rsqrt_pipeline vectors; measured={measured_count} "
        f"max_relative_error={maximum_relative_error:.8f} "
        f"max_absolute_error={maximum_absolute_error:.8e}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--count", type=int, default=4096)
    parser.add_argument("--seed", type=int, default=0xA5A7)
    args = parser.parse_args()
    write_vectors(args.output, args.count, args.seed)


if __name__ == "__main__":
    main()
