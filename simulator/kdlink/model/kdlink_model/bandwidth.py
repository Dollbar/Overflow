"""Analytical per-tier bandwidth and buffering contract for scaled KDLink fabrics."""

from __future__ import annotations

from dataclasses import dataclass
from math import ceil
from typing import Sequence

from .constants import NUM_PLANES, PAYLOAD_WIDTH, SLICE_CLOCK_HZ, SLICES_PER_PORT
from .scale import SCALE_MAX_ENDPOINTS, SCALE_NODES_PER_DOMAIN, ScaleDeploymentTopology


RADIX = 8
MAX_BANDWIDTH_TIERS = 5
REFERENCE_RTT_CYCLES = (14, 24, 34, 44, 54)
NONBLOCKING_OVERSUBSCRIPTION = (1.0, 1.0, 1.0, 1.0, 1.0)
BALANCED_OVERSUBSCRIPTION = (1.0, 2.0, 4.0, 8.0, 16.0)


@dataclass(frozen=True)
class BandwidthTrafficDemand:
    """Traffic crossing and optional in-network reduction assumptions."""

    name: str
    cross_tier_fraction: float = 1.0
    reduction_factor: float = 1.0

    def validate(self) -> None:
        if not self.name:
            raise ValueError("traffic demand name must be nonempty")
        if not 0.0 <= self.cross_tier_fraction <= 1.0:
            raise ValueError("cross-tier traffic fraction must be from zero through one")
        if self.reduction_factor < 1.0:
            raise ValueError("traffic reduction factor must be at least one")


@dataclass(frozen=True)
class BandwidthTierPolicy:
    """Capacity, latency, and failure policy for one leaf-up aggregation tier."""

    oversubscription_ratio: float
    round_trip_cycles: int
    spare_link_equivalents_per_plane: int = 1

    def validate(self) -> None:
        if self.oversubscription_ratio < 1.0:
            raise ValueError("oversubscription ratio must be at least one")
        if self.round_trip_cycles < 1:
            raise ValueError("round-trip cycles must be positive")
        if self.spare_link_equivalents_per_plane < 0:
            raise ValueError("spare link equivalents must be nonnegative")


@dataclass(frozen=True)
class BandwidthTierResult:
    """Calculated capacity and buffering for one active hierarchy tier."""

    tier_index: int
    covered_leaf_domains_per_group: int
    covered_npus_per_group: int
    group_count: int
    active_planes: int
    active_slices_per_port: int
    traffic_demand_name: str
    cross_tier_fraction: float
    reduction_factor: float
    payload_gbyte_s_per_link_per_direction: float
    offered_gbyte_s_per_plane_per_group: float
    required_gbyte_s_per_plane_per_group: float
    required_link_equivalents_per_plane_per_group: int
    installed_link_equivalents_per_plane_per_group: int
    networkwide_installed_link_equivalents: int
    round_trip_cycles: int
    bdp_bytes_per_link: int
    bdp_bytes_per_plane_per_group: int
    bdp_bytes_all_planes_per_group: int
    survives_one_link_equivalent_failure: bool


@dataclass(frozen=True)
class HierarchicalBandwidthPlan:
    """Complete analytical bandwidth plan for an active KDLink deployment."""

    total_npus: int
    leaf_count: int
    route_tier_count: int
    traffic_demands: tuple[BandwidthTrafficDemand, ...]
    tiers: tuple[BandwidthTierResult, ...]


def reference_tier_policies(
    oversubscription: Sequence[float] = NONBLOCKING_OVERSUBSCRIPTION,
    *,
    rtt_cycles: Sequence[int] = REFERENCE_RTT_CYCLES,
    spare_link_equivalents_per_plane: int = 1,
) -> tuple[BandwidthTierPolicy, ...]:
    """Build the five-tier reference policy from explicit planning vectors."""

    if len(oversubscription) != MAX_BANDWIDTH_TIERS or len(rtt_cycles) != MAX_BANDWIDTH_TIERS:
        raise ValueError("bandwidth policy vectors must contain five tiers")
    policies = tuple(
        BandwidthTierPolicy(ratio, cycles, spare_link_equivalents_per_plane)
        for ratio, cycles in zip(oversubscription, rtt_cycles, strict=True)
    )
    for policy in policies:
        policy.validate()
    return policies


def plan_hierarchical_bandwidth(
    total_npus: int,
    *,
    policies: Sequence[BandwidthTierPolicy] | None = None,
    traffic_demand: BandwidthTrafficDemand | Sequence[BandwidthTrafficDemand] | None = None,
    active_planes: int = NUM_PLANES,
    active_slices_per_port: int = SLICES_PER_PORT,
    clock_hz: float = SLICE_CLOCK_HZ,
) -> HierarchicalBandwidthPlan:
    """Calculate link equivalents and BDP without claiming a physical implementation."""

    topology = ScaleDeploymentTopology(total_npus)
    topology.validate()
    selected_policies = tuple(reference_tier_policies() if policies is None else policies)
    if len(selected_policies) < topology.inter_domain_route_stages:
        raise ValueError("bandwidth policy does not cover every active route tier")
    for policy in selected_policies:
        policy.validate()
    if traffic_demand is None:
        demands = (BandwidthTrafficDemand("worst_case_cross_tier"),) * topology.inter_domain_route_stages
    elif isinstance(traffic_demand, BandwidthTrafficDemand):
        demands = (traffic_demand,) * topology.inter_domain_route_stages
    else:
        demands = tuple(traffic_demand)
    if len(demands) < topology.inter_domain_route_stages:
        raise ValueError("traffic demand does not cover every active route tier")
    for demand in demands:
        demand.validate()
    if not 1 <= active_planes <= NUM_PLANES:
        raise ValueError("active plane count is outside the KDLink interface")
    if not 1 <= active_slices_per_port <= SLICES_PER_PORT:
        raise ValueError("active slice count is outside the bonded KDLink port")
    if clock_hz <= 0:
        raise ValueError("logical interface clock must be positive")
    link_payload_gbyte_s = PAYLOAD_WIDTH * clock_hz / 8.0 / 1.0e9 * active_slices_per_port
    results: list[BandwidthTierResult] = []
    for tier_offset in range(topology.inter_domain_route_stages):
        tier_index = tier_offset + 1
        policy = selected_policies[tier_offset]
        demand = demands[tier_offset]
        maximum_leaves_per_group = RADIX**tier_index
        covered_leaves = min(topology.leaf_count, maximum_leaves_per_group)
        covered_npus = min(total_npus, covered_leaves * SCALE_NODES_PER_DOMAIN)
        group_count = ceil(topology.leaf_count / maximum_leaves_per_group)
        offered = (
            covered_npus
            * link_payload_gbyte_s
            * demand.cross_tier_fraction
            / demand.reduction_factor
        )
        required = offered / policy.oversubscription_ratio
        required_links = ceil(required / link_payload_gbyte_s)
        installed_links = required_links + policy.spare_link_equivalents_per_plane
        rtt_seconds = policy.round_trip_cycles / clock_hz
        bdp_per_link = ceil(link_payload_gbyte_s * 1.0e9 * rtt_seconds)
        bdp_per_plane = ceil(required * 1.0e9 * rtt_seconds)
        surviving_links = max(0, installed_links - 1)
        results.append(
            BandwidthTierResult(
                tier_index=tier_index,
                covered_leaf_domains_per_group=covered_leaves,
                covered_npus_per_group=covered_npus,
                group_count=group_count,
                active_planes=active_planes,
                active_slices_per_port=active_slices_per_port,
                traffic_demand_name=demand.name,
                cross_tier_fraction=demand.cross_tier_fraction,
                reduction_factor=demand.reduction_factor,
                payload_gbyte_s_per_link_per_direction=link_payload_gbyte_s,
                offered_gbyte_s_per_plane_per_group=offered,
                required_gbyte_s_per_plane_per_group=required,
                required_link_equivalents_per_plane_per_group=required_links,
                installed_link_equivalents_per_plane_per_group=installed_links,
                networkwide_installed_link_equivalents=group_count * installed_links * active_planes,
                round_trip_cycles=policy.round_trip_cycles,
                bdp_bytes_per_link=bdp_per_link,
                bdp_bytes_per_plane_per_group=bdp_per_plane,
                bdp_bytes_all_planes_per_group=bdp_per_plane * active_planes,
                survives_one_link_equivalent_failure=(
                    surviving_links * link_payload_gbyte_s >= required
                ),
            )
        )
    return HierarchicalBandwidthPlan(
        total_npus=total_npus,
        leaf_count=topology.leaf_count,
        route_tier_count=topology.inter_domain_route_stages,
        traffic_demands=demands[: topology.inter_domain_route_stages],
        tiers=tuple(results),
    )


def maximum_supported_population() -> HierarchicalBandwidthPlan:
    """Return the nonblocking worst-case reference plan at the address-space limit."""

    return plan_hierarchical_bandwidth(SCALE_MAX_ENDPOINTS)
