"""Analytical payload and encoded-line performance contract for KDLink."""

from __future__ import annotations

from dataclasses import dataclass

from .constants import (
    NUM_NODES,
    NUM_PLANES,
    PAYLOAD_WIDTH,
    PCS_BLOCK_WIDTH,
    PCS_BLOCKS_PER_FLIT,
    SLICE_CLOCK_HZ,
    SLICES_PER_PORT,
)


@dataclass(frozen=True)
class FabricPerformance:
    payload_gbyte_s_per_slice_per_direction: float
    payload_gbyte_s_per_bonded_port_per_direction: float
    payload_gbyte_s_per_npu_per_direction: float
    payload_gbyte_s_per_npu_full_duplex: float
    encoded_gbyte_s_per_slice_per_direction: float
    payload_encoding_efficiency: float
    plane_payload_gbyte_s_per_direction: float
    system_payload_gbyte_s_per_direction: float
    ring_allreduce_tensor_gbyte_s_per_npu: float


def fabric_performance(
    clock_hz: float = SLICE_CLOCK_HZ,
    nodes: int = NUM_NODES,
    planes: int = NUM_PLANES,
    slices_per_port: int = SLICES_PER_PORT,
) -> FabricPerformance:
    if clock_hz <= 0 or nodes <= 1 or planes <= 0 or slices_per_port <= 0:
        raise ValueError("fabric performance parameters must be positive")
    slice_payload = PAYLOAD_WIDTH * clock_hz / 8.0 / 1.0e9
    bonded_payload = slice_payload * slices_per_port
    npu_payload = bonded_payload * planes
    encoded_slice = PCS_BLOCK_WIDTH * PCS_BLOCKS_PER_FLIT * clock_hz / 8.0 / 1.0e9
    ring_factor = 2.0 * (nodes - 1) / nodes
    return FabricPerformance(
        payload_gbyte_s_per_slice_per_direction=slice_payload,
        payload_gbyte_s_per_bonded_port_per_direction=bonded_payload,
        payload_gbyte_s_per_npu_per_direction=npu_payload,
        payload_gbyte_s_per_npu_full_duplex=2.0 * npu_payload,
        encoded_gbyte_s_per_slice_per_direction=encoded_slice,
        payload_encoding_efficiency=slice_payload / encoded_slice,
        plane_payload_gbyte_s_per_direction=bonded_payload * nodes,
        system_payload_gbyte_s_per_direction=npu_payload * nodes,
        ring_allreduce_tensor_gbyte_s_per_npu=npu_payload / ring_factor,
    )
