#!/usr/bin/env python3
"""Reproduce ANALYTICAL sizing results for the proposed OwerFlow NPU."""

from __future__ import annotations

import math
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "npu_arch_proposed.yaml"
SYSTEM_CONFIG = ROOT / "config" / "system_baseline.yaml"


def main() -> int:
    cfg = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))
    system = yaml.safe_load(SYSTEM_CONFIG.read_text(encoding="utf-8"))

    org = cfg["organization"]
    clocks = cfg["clocks"]
    tensor = cfg["tensor"]
    vector = cfg["vector"]
    sram = cfg["sram"]
    hbm = cfg["hbm"]
    noc = cfg["noc"]
    dma = cfg["dma"]
    assumptions = cfg["assumptions"]

    tiles = org["tensor_tiles_per_npu"]
    macs_per_cycle = (
        tiles
        * tensor["array_rows_per_tile"]
        * tensor["array_columns_per_tile"]
        * tensor["mxfp4_mxfp8_macs_per_array_cell_per_cycle"]
    )
    operations_per_cycle = macs_per_cycle * assumptions["mac_counts_as_operations"]
    tensor_pflops = operations_per_cycle * clocks["tensor_hz"] / 1e15

    fp8_vector_tflops = (
        tiles
        * vector["fp8_lanes_per_tile"]
        * vector["fma_per_lane_per_cycle"]
        * assumptions["mac_counts_as_operations"]
        * clocks["vector_hz"]
        / 1e12
    )
    private_sram_mib = tiles * sram["tile_private_mib"]
    shared_sram_mib = org["pods_per_npu"] * sram["pod_shared_mib"]

    tile_port_gbs = (
        noc["tile_data_port_bits_per_cycle"] / 8 * clocks["noc_hz"] / 1e9
    )
    pod_hbm_port_gbs = (
        noc["pod_hbm_data_port_bits_per_cycle"] / 8 * clocks["noc_hz"] / 1e9
    )
    interpod_edge_gbs = (
        noc["interpod_data_lanes_per_direction"]
        * noc["interpod_data_lane_bits_per_cycle"]
        / 8
        * clocks["noc_hz"]
        / 1e9
    )
    mesh_bisection_gbs = org["pod_rows"] * interpod_edge_gbs

    target_partition_gbs = hbm["target_payload_gbyte_per_second_per_partition"]
    stress_bdp_bytes = (
        target_partition_gbs
        * 1e9
        * assumptions["hbm_round_trip_latency_ns_stress"]
        * 1e-9
    )
    required_beats = math.ceil(stress_bdp_bytes / dma["data_beat_bytes"])
    provisioned_bytes = (
        dma["outstanding_data_beats_per_engine"] * dma["data_beat_bytes"]
    )

    active_parameters = system["workload"]["design_active_parameters_per_token"]
    npu_count = system["system"]["logical_npu_count"]
    target_tokens = system["system"]["target_decode_tokens_per_second"]
    ops_per_token = active_parameters * assumptions["mac_counts_as_operations"]
    weight_bytes_per_token = active_parameters * assumptions["weight_bits"] / 8
    system_tops = ops_per_token * target_tokens / 1e12
    per_npu_tops = system_tops / npu_count
    per_npu_weight_gbs = weight_bytes_per_token * target_tokens / npu_count / 1e9
    peak_balance_op_per_byte = (
        tensor_pflops * 1e15 / (hbm["target_aggregate_tbyte_per_second"] * 1e12)
    )
    decode_intensity = assumptions["mac_counts_as_operations"] / (
        assumptions["weight_bits"] / 8
    )
    reuse_to_balance = peak_balance_op_per_byte / decode_intensity

    assert org["pods_per_npu"] == org["pod_rows"] * org["pod_columns"]
    assert tiles == org["pods_per_npu"] * org["tensor_tiles_per_pod"]
    assert org["hbm_partitions_per_npu"] == org["pods_per_npu"]
    assert tensor_pflops >= tensor["target_pflops_equivalent"]
    assert pod_hbm_port_gbs >= target_partition_gbs
    assert provisioned_bytes >= stress_bdp_bytes
    assert dma["outstanding_data_beats_per_engine"] >= required_beats

    print(f"EVIDENCE={cfg['evidence_level']} STATUS={cfg['status']}")
    print(f"TENSOR_MACS_PER_CYCLE={macs_per_cycle:,}")
    print(f"TENSOR_PEAK_PFLOPS_EQ={tensor_pflops:.6f}")
    print(f"VECTOR_FP8_PEAK_TFLOPS={fp8_vector_tflops:.3f}")
    print(
        f"SRAM_MIB_PRIVATE={private_sram_mib} "
        f"SHARED={shared_sram_mib} TOTAL={private_sram_mib + shared_sram_mib}"
    )
    print(
        f"NOC_GBPS_TILE={tile_port_gbs:.0f} POD_HBM={pod_hbm_port_gbs:.0f} "
        f"INTERPOD_EDGE={interpod_edge_gbs:.0f} BISECTION={mesh_bisection_gbs:.0f}"
    )
    print(
        f"DMA_STRESS_BDP_BYTES={stress_bdp_bytes:.0f} "
        f"REQUIRED_BEATS={required_beats} PROVISIONED_BYTES={provisioned_bytes}"
    )
    print(
        f"OF5P6T_50TOK_SYSTEM_TOPS={system_tops:.3f} "
        f"PER_NPU_TOPS={per_npu_tops:.3f} PER_NPU_WEIGHT_GBPS={per_npu_weight_gbs:.3f}"
    )
    print(
        f"PEAK_BALANCE_OP_PER_BYTE={peak_balance_op_per_byte:.3f} "
        f"DECODE_OP_PER_BYTE={decode_intensity:.3f} REUSE_TO_BALANCE={reuse_to_balance:.3f}"
    )
    print("NPU_PROPOSAL_ANALYTICAL_CHECK_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
