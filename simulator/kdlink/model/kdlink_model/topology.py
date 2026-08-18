"""Eight-plane direct KDSwitch topology and route contract."""

from __future__ import annotations

from dataclasses import dataclass

from .constants import NUM_NODES, NUM_PLANES


@dataclass(frozen=True)
class FabricRoute:
    src_node: int
    dst_node: int
    plane_id: int
    ingress_port: int
    egress_port: int


def active_planes(plane_mask: int) -> tuple[int, ...]:
    return tuple(index for index in range(NUM_PLANES) if plane_mask & (1 << index))


def select_plane(flow_id: int, chunk_id: int, plane_mask: int = (1 << NUM_PLANES) - 1) -> int:
    planes = active_planes(plane_mask)
    if not planes:
        raise RuntimeError("no active KDLink plane")
    return planes[(flow_id ^ chunk_id) % len(planes)]


def route_direct(src_node: int, dst_node: int, plane_id: int) -> FabricRoute:
    if not 0 <= src_node < NUM_NODES or not 0 <= dst_node < NUM_NODES:
        raise ValueError("node is outside the 32-node topology")
    if not 0 <= plane_id < NUM_PLANES:
        raise ValueError("plane is outside the eight-plane topology")
    if src_node == dst_node:
        raise ValueError("fabric route cannot target its ingress node")
    return FabricRoute(src_node, dst_node, plane_id, src_node, dst_node)


def is_permutation(destinations: list[int]) -> bool:
    return len(destinations) == NUM_NODES and sorted(destinations) == list(range(NUM_NODES))
