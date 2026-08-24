#!/usr/bin/env python3
"""Generate deterministic bit-exact vectors for vector_softmax16."""

from __future__ import annotations

import argparse
import math
import random
import struct
from pathlib import Path

from fp32_exp_reference import exp_approx_bits
from fp32_recip_reference import reciprocal_approx_bits


LANES = 16


def float_to_bits(value: float) -> int:
    return struct.unpack(">I", struct.pack(">f", value))[0]


def bits_to_float(bits: int) -> float:
    return struct.unpack(">f", struct.pack(">I", bits & 0xFFFFFFFF))[0]


def fp32_add_bits(a_bits: int, b_bits: int) -> int:
    return float_to_bits(bits_to_float(a_bits) + bits_to_float(b_bits))


def fp32_mul_bits(a_bits: int, b_bits: int) -> int:
    return float_to_bits(bits_to_float(a_bits) * bits_to_float(b_bits))


def reduce_sum_tree(values: list[int]) -> int:
    level = values
    while len(level) > 1:
        level = [
            fp32_add_bits(level[index], level[index + 1])
            for index in range(0, len(level), 2)
        ]
    return level[0]


def softmax_approx(
    data_bits: list[int], invalid_mask: int, lane_mask: int
) -> tuple[list[int], int, int]:
    active = [lane for lane in range(LANES) if (lane_mask >> lane) & 1]
    if not active:
        return [0] * LANES, 0, 1

    maximum_bits = max(active, key=lambda lane: bits_to_float(data_bits[lane]))
    maximum = data_bits[maximum_bits]
    exp_values: list[int] = []
    for lane in range(LANES):
        if (lane_mask >> lane) & 1:
            negative_maximum = maximum ^ 0x80000000
            shifted = fp32_add_bits(data_bits[lane], negative_maximum)
            exp_value, _ = exp_approx_bits(shifted, 0)
            exp_values.append(exp_value)
        else:
            exp_values.append(0)

    denominator = reduce_sum_tree(exp_values)
    reciprocal, _ = reciprocal_approx_bits(denominator, 0)
    results = [
        fp32_mul_bits(exp_values[lane], reciprocal)
        if (lane_mask >> lane) & 1
        else 0
        for lane in range(LANES)
    ]
    transaction_invalid = int(bool(invalid_mask & lane_mask))
    output_invalid = lane_mask if transaction_invalid else 0
    return results, output_invalid, 0


def directed_vectors() -> list[tuple[list[float], int, int, int, int]]:
    return [
        ([0.0] * LANES, 0x0000, 0x0000, 0x10, 0),
        ([0.0] * LANES, 0x0000, 0x0001, 0x11, 0),
        ([0.0] * LANES, 0x0000, 0xFFFF, 0x12, 0),
        ([float(lane) for lane in range(LANES)], 0x0000, 0xFFFF, 0x13, 0),
        ([float(-lane) for lane in range(LANES)], 0x0000, 0xFFFF, 0x14, 0),
        ([2.0] * LANES, 0x0000, 0x5555, 0x15, 0),
        ([8.0 if lane == 7 else -8.0 for lane in range(LANES)], 0x0000, 0xFFFF, 0x16, 1),
        ([3.0, -2.0, 1.0, -4.0] * 4, 0x0004, 0x00FF, 0x17, 0),
        ([3.0, -2.0, 1.0, -4.0] * 4, 0x8000, 0x00FF, 0x18, 0),
        ([0.25 * (lane - 8) for lane in range(LANES)], 0x8001, 0x8001, 0x19, 1),
        ([1.0e-5 * lane for lane in range(LANES)], 0x0000, 0xFFFF, 0x1A, 0),
        ([-12.0 + 1.5 * lane for lane in range(LANES)], 0x0000, 0x0FF0, 0x1B, 0),
    ]


def generate_vectors(
    count: int, seed: int
) -> list[tuple[list[int], int, int, int, int]]:
    vectors = [
        ([float_to_bits(value) for value in values], invalid, mask, tag, last)
        for values, invalid, mask, tag, last in directed_vectors()
    ]
    rng = random.Random(seed)
    while len(vectors) < count:
        values = [float_to_bits(rng.uniform(-12.0, 12.0)) for _ in range(LANES)]
        mask = rng.randrange(1 << LANES)
        if rng.randrange(32) == 0:
            mask = 0
        invalid = rng.randrange(1 << LANES) if rng.randrange(16) == 0 else 0
        vectors.append((values, invalid, mask, rng.randrange(256), rng.randrange(2)))
    return vectors[:count]


def pack_lanes(values: list[int]) -> int:
    packed = 0
    for lane, value in enumerate(values):
        packed |= (value & 0xFFFFFFFF) << (32 * lane)
    return packed


def write_vectors(output: Path, count: int, seed: int) -> None:
    vectors = generate_vectors(count, seed)
    output.parent.mkdir(parents=True, exist_ok=True)
    maximum_absolute_error = 0.0
    maximum_sum_error = 0.0
    measured = 0
    with output.open("w", encoding="ascii") as handle:
        for data, invalid, mask, tag, last in vectors:
            result, result_invalid, empty = softmax_approx(data, invalid, mask)
            packed = pack_lanes(data)
            packed = (packed << 16) | invalid
            packed = (packed << 16) | mask
            packed = (packed << 8) | tag
            packed = (packed << 1) | last
            packed = (packed << 512) | pack_lanes(result)
            packed = (packed << 16) | result_invalid
            packed = (packed << 1) | empty
            handle.write(f"{packed:0271x}\n")

            if mask and not (invalid & mask):
                active = [lane for lane in range(LANES) if (mask >> lane) & 1]
                maximum = max(bits_to_float(data[lane]) for lane in active)
                exact_values = [
                    math.exp(bits_to_float(data[lane]) - maximum)
                    if lane in active
                    else 0.0
                    for lane in range(LANES)
                ]
                denominator = sum(exact_values)
                approximate_sum = 0.0
                for lane in active:
                    approximate = bits_to_float(result[lane])
                    exact = exact_values[lane] / denominator
                    maximum_absolute_error = max(
                        maximum_absolute_error, abs(approximate - exact)
                    )
                    approximate_sum += approximate
                maximum_sum_error = max(maximum_sum_error, abs(approximate_sum - 1.0))
                measured += 1

    if maximum_absolute_error > 0.005 or maximum_sum_error > 0.01:
        raise RuntimeError(
            f"softmax error exceeds contract: abs={maximum_absolute_error:.8f} "
            f"sum={maximum_sum_error:.8f}"
        )
    print(
        f"Generated {len(vectors)} vector_softmax16 vectors; measured={measured} "
        f"max_absolute_error={maximum_absolute_error:.8f} "
        f"max_sum_error={maximum_sum_error:.8f}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--count", type=int, default=512)
    parser.add_argument("--seed", type=int, default=0x50F7)
    args = parser.parse_args()
    write_vectors(args.output, args.count, args.seed)


if __name__ == "__main__":
    main()
