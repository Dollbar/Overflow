#!/usr/bin/env python3
"""Generate deterministic bit-exact vectors for vector_norm16."""

from __future__ import annotations

import argparse
import math
import random
import struct
from pathlib import Path

from fp32_rsqrt_reference import rsqrt_approx_bits


LANES = 16
FP32_ONE = 0x3F800000
RECIPROCAL_COUNT = (
    0x00000000,
    0x3F800000,
    0x3F000000,
    0x3EAAAAAB,
    0x3E800000,
    0x3E4CCCCD,
    0x3E2AAAAB,
    0x3E124925,
    0x3E000000,
    0x3DE38E39,
    0x3DCCCCCD,
    0x3DBA2E8C,
    0x3DAAAAAB,
    0x3D9D89D9,
    0x3D924925,
    0x3D888889,
    0x3D800000,
)


def float_to_bits(value: float) -> int:
    return struct.unpack(">I", struct.pack(">f", value))[0]


def bits_to_float(bits: int) -> float:
    return struct.unpack(">f", struct.pack(">I", bits & 0xFFFFFFFF))[0]


def fp32_add_bits(a_bits: int, b_bits: int) -> int:
    return float_to_bits(bits_to_float(a_bits) + bits_to_float(b_bits))


def fp32_mul_bits(a_bits: int, b_bits: int) -> int:
    return float_to_bits(bits_to_float(a_bits) * bits_to_float(b_bits))


def fp32_negate(bits: int) -> int:
    return bits ^ 0x80000000


def reduce_sum_tree(values: list[int]) -> int:
    level = values
    while len(level) > 1:
        level = [
            fp32_add_bits(level[index], level[index + 1])
            for index in range(0, len(level), 2)
        ]
    return level[0]


def norm_approx(
    data: list[int],
    invalid_mask: int,
    gamma: list[int],
    beta: list[int],
    epsilon: int,
    lane_mask: int,
    rms_mode: int,
    affine_enable: int,
    beta_enable: int,
) -> tuple[list[int], int, int]:
    active_count = lane_mask.bit_count()
    if active_count == 0:
        return [0] * LANES, 0, 1

    masked_data = [
        data[lane] if (lane_mask >> lane) & 1 else 0 for lane in range(LANES)
    ]
    input_sum = reduce_sum_tree(masked_data)
    mean = fp32_mul_bits(input_sum, RECIPROCAL_COUNT[active_count])
    centered = []
    for lane in range(LANES):
        if rms_mode:
            centered.append(data[lane])
        else:
            centered.append(fp32_add_bits(data[lane], fp32_negate(mean)))

    squares = [
        fp32_mul_bits(centered[lane], centered[lane])
        if (lane_mask >> lane) & 1
        else 0
        for lane in range(LANES)
    ]
    square_sum = reduce_sum_tree(squares)
    variance = fp32_mul_bits(square_sum, RECIPROCAL_COUNT[active_count])
    variance_epsilon = fp32_add_bits(variance, epsilon)
    inverse_stddev, rsqrt_invalid = rsqrt_approx_bits(variance_epsilon, 0)

    result = []
    for lane in range(LANES):
        normalized = fp32_mul_bits(centered[lane], inverse_stddev)
        scale = gamma[lane] if affine_enable else FP32_ONE
        offset = beta[lane] if affine_enable and beta_enable else 0
        scaled = fp32_mul_bits(normalized, scale)
        result.append(fp32_add_bits(scaled, offset))

    transaction_invalid = int(bool(invalid_mask & lane_mask) or rsqrt_invalid)
    output_invalid = lane_mask if transaction_invalid else 0
    for lane in range(LANES):
        if not ((lane_mask >> lane) & 1):
            result[lane] = 0
    return result, output_invalid, 0


def directed_vectors() -> list[tuple[list[float], int, list[float], list[float], float, int, int, int, int, int, int]]:
    ones = [1.0] * LANES
    zeros = [0.0] * LANES
    return [
        (zeros, 0, ones, zeros, 1.0e-5, 0x0000, 0, 1, 1, 0x10, 0),
        (zeros, 0, ones, zeros, 1.0e-5, 0xFFFF, 0, 1, 1, 0x11, 0),
        ([float(lane) for lane in range(LANES)], 0, ones, zeros, 1.0e-5, 0xFFFF, 0, 1, 1, 0x12, 0),
        ([float(lane) for lane in range(LANES)], 0, ones, zeros, 1.0e-5, 0xFFFF, 1, 1, 0, 0x13, 0),
        ([2.0] * LANES, 0, [0.5] * LANES, [0.25] * LANES, 1.0e-5, 0x5555, 0, 1, 1, 0x14, 0),
        ([-3.0, -1.0, 1.0, 3.0] * 4, 0, ones, zeros, 1.0e-4, 0x00FF, 0, 0, 0, 0x15, 1),
        ([-3.0, -1.0, 1.0, 3.0] * 4, 0, [1.25] * LANES, [0.5] * LANES, 1.0e-4, 0x00FF, 1, 1, 1, 0x16, 0),
        ([0.25 * (lane - 8) for lane in range(LANES)], 0x0004, ones, zeros, 1.0e-5, 0x00FF, 0, 1, 1, 0x17, 0),
        ([0.25 * (lane - 8) for lane in range(LANES)], 0x8000, ones, zeros, 1.0e-5, 0x00FF, 1, 1, 0, 0x18, 1),
        ([4.0 if lane == 7 else -0.25 for lane in range(LANES)], 0, ones, zeros, 1.0e-6, 0x0080, 0, 1, 1, 0x19, 0),
    ]


def generate_vectors(count: int, seed: int):
    vectors = directed_vectors()
    rng = random.Random(seed)
    while len(vectors) < count:
        data = [rng.uniform(-4.0, 4.0) for _ in range(LANES)]
        gamma = [rng.uniform(0.5, 1.5) for _ in range(LANES)]
        beta = [rng.uniform(-0.5, 0.5) for _ in range(LANES)]
        lane_mask = rng.randrange(1 << LANES)
        if rng.randrange(32) == 0:
            lane_mask = 0
        invalid = rng.randrange(1 << LANES) if rng.randrange(20) == 0 else 0
        vectors.append(
            (
                data,
                invalid,
                gamma,
                beta,
                10.0 ** rng.uniform(-6.0, -3.0),
                lane_mask,
                rng.randrange(2),
                rng.randrange(2),
                rng.randrange(2),
                rng.randrange(256),
                rng.randrange(2),
            )
        )
    return vectors[:count]


def pack_lanes(values: list[int]) -> int:
    packed = 0
    for lane, value in enumerate(values):
        packed |= (value & 0xFFFFFFFF) << (lane * 32)
    return packed


def write_vectors(output: Path, count: int, seed: int) -> None:
    vectors = generate_vectors(count, seed)
    output.parent.mkdir(parents=True, exist_ok=True)
    maximum_absolute_error = 0.0
    measured = 0
    with output.open("w", encoding="ascii") as handle:
        for (
            data_values,
            invalid,
            gamma_values,
            beta_values,
            epsilon_value,
            lane_mask,
            rms_mode,
            affine_enable,
            beta_enable,
            tag,
            last,
        ) in vectors:
            data = [float_to_bits(value) for value in data_values]
            gamma = [float_to_bits(value) for value in gamma_values]
            beta = [float_to_bits(value) for value in beta_values]
            epsilon = float_to_bits(epsilon_value)
            result, result_invalid, empty = norm_approx(
                data,
                invalid,
                gamma,
                beta,
                epsilon,
                lane_mask,
                rms_mode,
                affine_enable,
                beta_enable,
            )

            packed = pack_lanes(data)
            packed = (packed << 16) | invalid
            packed = (packed << 512) | pack_lanes(gamma)
            packed = (packed << 512) | pack_lanes(beta)
            packed = (packed << 32) | epsilon
            packed = (packed << 16) | lane_mask
            packed = (packed << 8) | tag
            packed = (packed << 1) | last
            packed = (packed << 1) | rms_mode
            packed = (packed << 1) | affine_enable
            packed = (packed << 1) | beta_enable
            packed = (packed << 512) | pack_lanes(result)
            packed = (packed << 16) | result_invalid
            packed = (packed << 1) | empty
            handle.write(f"{packed:0536x}\n")

            if lane_mask and not (invalid & lane_mask):
                active = [lane for lane in range(LANES) if (lane_mask >> lane) & 1]
                active_values = [data_values[lane] for lane in active]
                mean = sum(active_values) / len(active_values)
                centered = data_values if rms_mode else [value - mean for value in data_values]
                second_moment = sum(centered[lane] ** 2 for lane in active) / len(active)
                inv_stddev = 1.0 / math.sqrt(second_moment + epsilon_value)
                for lane in active:
                    exact = centered[lane] * inv_stddev
                    if affine_enable:
                        exact *= gamma_values[lane]
                        if beta_enable:
                            exact += beta_values[lane]
                    approximate = bits_to_float(result[lane])
                    maximum_absolute_error = max(maximum_absolute_error, abs(approximate - exact))
                measured += 1

    if maximum_absolute_error > 0.03:
        raise RuntimeError(
            f"normalization absolute error {maximum_absolute_error:.8f} exceeds 0.03 contract"
        )
    print(
        f"Generated {len(vectors)} vector_norm16 vectors; measured={measured} "
        f"max_absolute_error={maximum_absolute_error:.8f}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--count", type=int, default=512)
    parser.add_argument("--seed", type=int, default=0xA04D)
    args = parser.parse_args()
    write_vectors(args.output, args.count, args.seed)


if __name__ == "__main__":
    main()
