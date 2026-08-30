"""Golden deterministic-XY model for the eight-Pod NPU Mesh."""

from __future__ import annotations

from dataclasses import dataclass
import random
from typing import Iterable


ROWS = 2
COLUMNS = 4
PODS = ROWS * COLUMNS
DATA_LANES = 2
DATA_LANE_PAYLOAD_BITS = 1024
CONTROL_PAYLOAD_BITS = 128
LOGICAL_NOC_HZ = 2_000_000_000
DATA_PACKET_FLITS = 32
CONTROL_PACKET_FLITS = 4
DATA_FLIT_BYTES = DATA_LANE_PAYLOAD_BITS // 8
HBM_PARTITION_GBPS = 625
MAX_NONLOCAL_FRACTION = 0.20


@dataclass(frozen=True)
class DirectedLink:
    """One directed edge between adjacent Pod routers."""

    source: int
    destination: int


@dataclass(frozen=True)
class TrafficFlow:
    """One payload demand routed from source to destination."""

    source: int
    destination: int
    payload_bytes: int


def validate_pod(pod_id: int) -> None:
    """Reject Pod identities outside the fixed two-by-four geometry."""

    if not 0 <= pod_id < PODS:
        raise ValueError(f"pod_id {pod_id} is outside 0..{PODS - 1}")


def coordinates(pod_id: int) -> tuple[int, int]:
    """Return column and row for one Pod identity."""

    validate_pod(pod_id)
    return pod_id % COLUMNS, pod_id // COLUMNS


def pod_id(column: int, row: int) -> int:
    """Return the Pod identity for one legal coordinate."""

    if not 0 <= column < COLUMNS or not 0 <= row < ROWS:
        raise ValueError(f"coordinate ({column}, {row}) is outside the Mesh")
    return row * COLUMNS + column


def route_xy(source: int, destination: int) -> tuple[int, ...]:
    """Return the deterministic horizontal-first XY Pod sequence."""

    source_column, source_row = coordinates(source)
    destination_column, destination_row = coordinates(destination)
    route = [source]
    column = source_column
    row = source_row
    while column != destination_column:
        column += 1 if destination_column > column else -1
        route.append(pod_id(column, row))
    while row != destination_row:
        row += 1 if destination_row > row else -1
        route.append(pod_id(column, row))
    return tuple(route)


def route_links(source: int, destination: int) -> tuple[DirectedLink, ...]:
    """Return directed links traversed by one deterministic route."""

    route = route_xy(source, destination)
    return tuple(
        DirectedLink(first, second) for first, second in zip(route, route[1:])
    )


def directed_links() -> frozenset[DirectedLink]:
    """Enumerate all twenty legal directed Mesh links."""

    links: set[DirectedLink] = set()
    for row in range(ROWS):
        for column in range(COLUMNS):
            current = pod_id(column, row)
            if column + 1 < COLUMNS:
                east = pod_id(column + 1, row)
                links.add(DirectedLink(current, east))
                links.add(DirectedLink(east, current))
            if row + 1 < ROWS:
                south = pod_id(column, row + 1)
                links.add(DirectedLink(current, south))
                links.add(DirectedLink(south, current))
    return frozenset(links)


def accumulate_link_bytes(flows: Iterable[TrafficFlow]) -> dict[DirectedLink, int]:
    """Accumulate payload bytes on every link used by a traffic set."""

    loads = {link: 0 for link in directed_links()}
    for flow in flows:
        if flow.payload_bytes < 0:
            raise ValueError("payload_bytes must be non-negative")
        for link in route_links(flow.source, flow.destination):
            loads[link] += flow.payload_bytes
    return loads


def hotspot_flows(destination: int, payload_bytes: int) -> tuple[TrafficFlow, ...]:
    """Return one simultaneous-style demand from every other Pod to a hotspot."""

    validate_pod(destination)
    return tuple(
        TrafficFlow(source, destination, payload_bytes)
        for source in range(PODS)
        if source != destination
    )


def transpose_flows(payload_bytes: int) -> tuple[TrafficFlow, ...]:
    """Return the fixed three-bit complement permutation for eight Pods."""

    return tuple(
        TrafficFlow(source, source ^ (PODS - 1), payload_bytes)
        for source in range(PODS)
    )


def uniform_random_flows(
    count: int,
    payload_bytes: int,
    seed: int,
) -> tuple[TrafficFlow, ...]:
    """Generate reproducible non-local uniform-random demands."""

    if count < 0:
        raise ValueError("count must be non-negative")
    generator = random.Random(seed)
    flows: list[TrafficFlow] = []
    for _ in range(count):
        source = generator.randrange(PODS)
        destination = generator.randrange(PODS - 1)
        if destination >= source:
            destination += 1
        flows.append(TrafficFlow(source, destination, payload_bytes))
    return tuple(flows)


def analytical_payload_rates() -> dict[str, float]:
    """Calculate decimal payload rates at the declared logical clock."""

    lane_gbytes_per_second = DATA_LANE_PAYLOAD_BITS * LOGICAL_NOC_HZ / 8 / 1e9
    edge_gbytes_per_second = lane_gbytes_per_second * DATA_LANES
    return {
        "data_lane_gbytes_per_second": lane_gbytes_per_second,
        "directed_edge_gbytes_per_second": edge_gbytes_per_second,
        "middle_bisection_gbytes_per_second": edge_gbytes_per_second * ROWS,
        "control_gbytes_per_second": CONTROL_PAYLOAD_BITS * LOGICAL_NOC_HZ / 8 / 1e9,
        "maximum_data_packet_bytes": DATA_PACKET_FLITS * DATA_FLIT_BYTES,
        "maximum_nonlocal_hbm_gbytes_per_second": (
            PODS * HBM_PARTITION_GBPS * MAX_NONLOCAL_FRACTION
        ),
    }
