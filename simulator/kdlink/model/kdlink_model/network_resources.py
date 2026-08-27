"""KDLink hierarchy resource capacities for inference traffic simulation."""

from __future__ import annotations

from dataclasses import dataclass
from math import ceil

from .bandwidth import BALANCED_OVERSUBSCRIPTION, NONBLOCKING_OVERSUBSCRIPTION, REFERENCE_RTT_CYCLES
from .scale import SCALE_NODES_PER_DOMAIN, ScaleDeploymentTopology


NETWORK_PROFILES = ("nonblocking", "balanced")


@dataclass(frozen=True)
class NetworkSimulationPolicy:
    """Explicit line, plane, oversubscription, and latency assumptions."""

    profile: str = "nonblocking"
    active_planes: int = 8
    active_slices_per_port: int = 1
    active_planes_by_tier: tuple[int, ...] | None = None
    active_slices_by_tier: tuple[int, ...] | None = None
    oversubscription_by_tier: tuple[float, ...] | None = None
    logical_clock_hz: float = 1.0e9
    leaf_rtt_cycles: int = 8
    rtt_cycles: tuple[int, ...] = REFERENCE_RTT_CYCLES

    @classmethod
    def from_dict(cls, values: dict) -> "NetworkSimulationPolicy":
        copied = dict(values)
        for name in (
            "active_planes_by_tier",
            "active_slices_by_tier",
            "oversubscription_by_tier",
            "rtt_cycles",
        ):
            if name in copied and copied[name] is not None:
                copied[name] = tuple(copied[name])
        return cls(**copied)

    def validate(self) -> None:
        if self.profile not in NETWORK_PROFILES:
            raise ValueError("unknown KDLink network profile")
        if not 1 <= self.active_planes <= 8:
            raise ValueError("active plane count must be from one through eight")
        if not 1 <= self.active_slices_per_port <= 2:
            raise ValueError("active slice count must be one or two")
        if self.active_planes_by_tier is not None and (
            len(self.active_planes_by_tier) != 6
            or any(not 1 <= count <= 8 for count in self.active_planes_by_tier)
        ):
            raise ValueError("per-tier plane vector must contain six values from one through eight")
        if self.active_slices_by_tier is not None and (
            len(self.active_slices_by_tier) != 6
            or any(not 1 <= count <= 2 for count in self.active_slices_by_tier)
        ):
            raise ValueError("per-tier slice vector must contain six values from one through two")
        if self.oversubscription_by_tier is not None and (
            len(self.oversubscription_by_tier) != 5
            or any(ratio < 1.0 for ratio in self.oversubscription_by_tier)
        ):
            raise ValueError(
                "per-tier oversubscription vector must contain five values at least one"
            )
        if self.logical_clock_hz <= 0.0:
            raise ValueError("logical network clock must be positive")
        if self.leaf_rtt_cycles < 1:
            raise ValueError("leaf RTT must be positive")
        if len(self.rtt_cycles) != 5 or any(cycle < 1 for cycle in self.rtt_cycles):
            raise ValueError("network RTT vector must contain five positive tiers")

    def planes_for_tier(self, tier_index: int) -> int:
        self.validate()
        return (
            self.active_planes
            if self.active_planes_by_tier is None
            else self.active_planes_by_tier[tier_index]
        )

    def slices_for_tier(self, tier_index: int) -> int:
        self.validate()
        return (
            self.active_slices_per_port
            if self.active_slices_by_tier is None
            else self.active_slices_by_tier[tier_index]
        )

    def oversubscription(self) -> tuple[float, ...]:
        self.validate()
        if self.oversubscription_by_tier is not None:
            return self.oversubscription_by_tier
        return (
            NONBLOCKING_OVERSUBSCRIPTION
            if self.profile == "nonblocking"
            else BALANCED_OVERSUBSCRIPTION
        )


@dataclass(frozen=True)
class HierarchyResource:
    """Aggregate service capacity for one distributed hierarchy group."""

    tier_index: int
    group_count: int
    covered_npus_per_group: int
    active_planes: int
    active_slices_per_port: int
    capacity_gbyte_s_per_plane_per_group: float
    capacity_gbyte_s_all_planes_per_group: float
    payload_gbyte_s_per_link_per_direction: float
    installed_link_equivalents_per_plane_per_group: int
    oversubscription_ratio: float
    round_trip_cycles: int
    round_trip_microseconds: float


def build_hierarchy_resources(
    total_npus: int, policy: NetworkSimulationPolicy
) -> tuple[HierarchyResource, ...]:
    """Build capacity resources from the released analytical bandwidth contract."""

    policy.validate()
    topology = ScaleDeploymentTopology(total_npus)
    topology.validate()
    ratios = policy.oversubscription()
    leaf_planes = policy.planes_for_tier(0)
    leaf_slices = policy.slices_for_tier(0)
    link_payload_gbyte_s = 64.0 * leaf_slices
    leaf_group_npus = min(total_npus, 32)
    leaf = HierarchyResource(
        tier_index=0,
        group_count=ceil(total_npus / 32),
        covered_npus_per_group=leaf_group_npus,
        active_planes=leaf_planes,
        active_slices_per_port=leaf_slices,
        capacity_gbyte_s_per_plane_per_group=leaf_group_npus * link_payload_gbyte_s,
        capacity_gbyte_s_all_planes_per_group=(
            leaf_group_npus * link_payload_gbyte_s * leaf_planes
        ),
        payload_gbyte_s_per_link_per_direction=link_payload_gbyte_s,
        installed_link_equivalents_per_plane_per_group=leaf_group_npus + 1,
        oversubscription_ratio=1.0,
        round_trip_cycles=policy.leaf_rtt_cycles,
        round_trip_microseconds=policy.leaf_rtt_cycles / policy.logical_clock_hz * 1.0e6,
    )
    interdomain = []
    for tier_index in range(1, topology.inter_domain_route_stages + 1):
        maximum_leaves_per_group = 8**tier_index
        covered_leaves = min(topology.leaf_count, maximum_leaves_per_group)
        covered_npus = min(total_npus, covered_leaves * SCALE_NODES_PER_DOMAIN)
        group_count = ceil(topology.leaf_count / maximum_leaves_per_group)
        planes = policy.planes_for_tier(tier_index)
        slices = policy.slices_for_tier(tier_index)
        link_payload = 64.0 * slices
        ratio = ratios[tier_index - 1]
        capacity_per_plane = covered_npus * link_payload / ratio
        required_links = ceil(covered_npus / ratio)
        interdomain.append(
            HierarchyResource(
                tier_index=tier_index,
                group_count=group_count,
                covered_npus_per_group=covered_npus,
                active_planes=planes,
                active_slices_per_port=slices,
                capacity_gbyte_s_per_plane_per_group=capacity_per_plane,
                capacity_gbyte_s_all_planes_per_group=capacity_per_plane * planes,
                payload_gbyte_s_per_link_per_direction=link_payload,
                installed_link_equivalents_per_plane_per_group=required_links + 1,
                oversubscription_ratio=ratio,
                round_trip_cycles=policy.rtt_cycles[tier_index - 1],
                round_trip_microseconds=(
                    policy.rtt_cycles[tier_index - 1]
                    / policy.logical_clock_hz
                    * 1.0e6
                ),
            )
        )
    return (leaf, *interdomain)
