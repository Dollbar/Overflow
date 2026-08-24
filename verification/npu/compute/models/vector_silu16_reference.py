#!/usr/bin/env python3
"""Generate deterministic bit-exact vectors for vector_silu16."""

from __future__ import annotations

import argparse
import math
import random
import struct
from pathlib import Path

from vector_gelu16_reference import sigmoid_approx_bits
from vector_fp_reference import RNE, multiply_fp32


LANES = 16
FP32_NEGATIVE_INFINITY = 0xFF800000


def float_to_bits(value: float) -> int:
    return struct.unpack(">I", struct.pack(">f", value))[0]


def bits_to_float(bits: int) -> float:
    return struct.unpack(">f", struct.pack(">I", bits & 0xFFFFFFFF))[0]


def silu_bits(data_bits: int, invalid_in: int) -> tuple[int, int]:
    probability, probability_invalid = sigmoid_approx_bits(
        data_bits, invalid_in
    )
    final_operand = 0 if data_bits == FP32_NEGATIVE_INFINITY else data_bits
    return multiply_fp32(
        final_operand, probability, probability_invalid, RNE
    )


def directed_vectors() -> list[tuple[list[int], int, int, int, int]]:
    vector0 = [float_to_bits(0.0)] * LANES
    vector1 = [float_to_bits(0.25 * (lane - 8)) for lane in range(LANES)]
    vector2 = [float_to_bits(float(lane - 8)) for lane in range(LANES)]
    vector3 = [float_to_bits(-12.0 + 1.5 * lane) for lane in range(LANES)]
    vector4 = [
        0x00000000, 0x80000000, 0x00000001, 0x80000001,
        0x00800000, 0x80800000, 0x3F800000, 0xBF800000,
        0x40000000, 0xC0000000, 0x7F7FFFFF, 0xFF7FFFFF,
        0x7F800000, 0xFF800000, 0x7FC00001, 0xFFC12345,
    ]
    return [
        (vector0, 0x0000, 0x0000, 0x30, 0),
        (vector0, 0x0000, 0xFFFF, 0x31, 0),
        (vector1, 0x0000, 0xFFFF, 0x32, 0),
        (vector2, 0x0000, 0xFFFF, 0x33, 1),
        (vector3, 0x0000, 0x5555, 0x34, 0),
        (vector4, 0x0000, 0xFFFF, 0x35, 0),
        (vector4, 0x8421, 0x8421, 0x36, 1),
        (vector4, 0x8000, 0x00FF, 0x37, 0),
    ]


def generate_vectors(
    count: int, seed: int
) -> list[tuple[list[int], int, int, int, int]]:
    vectors = directed_vectors()
    rng = random.Random(seed)
    while len(vectors) < count:
        values = [float_to_bits(rng.uniform(-16.0, 16.0)) for _ in range(LANES)]
        lane_mask = rng.randrange(1 << LANES)
        if rng.randrange(32) == 0:
            lane_mask = 0
        invalid_mask = rng.randrange(1 << LANES) if rng.randrange(16) == 0 else 0
        vectors.append(
            (values, invalid_mask, lane_mask, rng.randrange(256), rng.randrange(2))
        )
    return vectors[:count]


def pack_lanes(values: list[int]) -> int:
    packed = 0
    for lane, value in enumerate(values):
        packed |= (value & 0xFFFFFFFF) << (lane * 32)
    return packed


def write_vectors(output: Path, count: int, seed: int) -> None:
    vectors = generate_vectors(count, seed)
    maximum_absolute_error = 0.0
    measured = 0
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="ascii") as handle:
        for data, invalid, mask, tag, last in vectors:
            result = [0] * LANES
            result_invalid = 0
            for lane in range(LANES):
                if (mask >> lane) & 1:
                    result[lane], lane_invalid = silu_bits(
                        data[lane], (invalid >> lane) & 1
                    )
                    result_invalid |= lane_invalid << lane

                    value = bits_to_float(data[lane])
                    if math.isfinite(value) and not ((invalid >> lane) & 1):
                        if value < 0.0:
                            exponential = math.exp(value)
                            exact = value * exponential / (1.0 + exponential)
                        else:
                            exact = value / (1.0 + math.exp(-value))
                        approximate = bits_to_float(result[lane])
                        maximum_absolute_error = max(
                            maximum_absolute_error, abs(approximate - exact)
                        )
                        measured += 1

            empty = int(mask == 0)
            packed = pack_lanes(data)
            packed = (packed << 16) | invalid
            packed = (packed << 16) | mask
            packed = (packed << 8) | tag
            packed = (packed << 1) | last
            packed = (packed << 512) | pack_lanes(result)
            packed = (packed << 16) | result_invalid
            packed = (packed << 1) | empty
            handle.write(f"{packed:0271x}\n")

    if maximum_absolute_error > 0.01:
        raise RuntimeError(
            f"SiLU absolute error {maximum_absolute_error:.8f} exceeds 0.01"
        )
    print(
        f"Generated {len(vectors)} vector_silu16 vectors; measured={measured} "
        f"max_absolute_error={maximum_absolute_error:.8f}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--count", type=int, default=512)
    parser.add_argument("--seed", type=int, default=0x5110)
    args = parser.parse_args()
    write_vectors(args.output, args.count, args.seed)


if __name__ == "__main__":
    main()
