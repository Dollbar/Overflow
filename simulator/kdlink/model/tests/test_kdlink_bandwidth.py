import json
from pathlib import Path

import pytest

from kdlink_model.bandwidth import (
    BALANCED_OVERSUBSCRIPTION,
    NONBLOCKING_OVERSUBSCRIPTION,
    REFERENCE_RTT_CYCLES,
    BandwidthTierPolicy,
    BandwidthTrafficDemand,
    plan_hierarchical_bandwidth,
    reference_tier_policies,
)
from kdlink_model.scale import SCALE_MAX_ENDPOINTS


ROOT = Path(__file__).parents[4]


def test_full_scale_nonblocking_plan_preserves_bonded_injection_at_every_tier() -> None:
    plan = plan_hierarchical_bandwidth(SCALE_MAX_ENDPOINTS)
    assert plan.route_tier_count == 5
    assert [tier.covered_leaf_domains_per_group for tier in plan.tiers] == [8, 64, 512, 4096, 32768]
    assert [tier.covered_npus_per_group for tier in plan.tiers] == [256, 2048, 16384, 131072, 1048576]
    assert [tier.required_link_equivalents_per_plane_per_group for tier in plan.tiers] == [
        256,
        2048,
        16384,
        131072,
        1048576,
    ]
    assert all(tier.payload_gbyte_s_per_link_per_direction == 128.0 for tier in plan.tiers)
    assert all(tier.survives_one_link_equivalent_failure for tier in plan.tiers)


def test_full_scale_balanced_plan_applies_explicit_tier_oversubscription() -> None:
    policies = reference_tier_policies(BALANCED_OVERSUBSCRIPTION)
    plan = plan_hierarchical_bandwidth(SCALE_MAX_ENDPOINTS, policies=policies)
    assert [tier.required_link_equivalents_per_plane_per_group for tier in plan.tiers] == [
        256,
        1024,
        4096,
        16384,
        65536,
    ]
    for tier, ratio in zip(plan.tiers, BALANCED_OVERSUBSCRIPTION, strict=True):
        assert tier.offered_gbyte_s_per_plane_per_group / tier.required_gbyte_s_per_plane_per_group == ratio


@pytest.mark.parametrize(
    ("total_npus", "leaf_count", "route_tiers", "top_group_npus"),
    [
        (2, 1, 0, None),
        (3, 1, 0, None),
        (33, 2, 1, 33),
        (78, 3, 1, 78),
        (15132, 473, 3, 15132),
    ],
)
def test_irregular_population_bandwidth_plan_matches_active_route_depth(
    total_npus: int, leaf_count: int, route_tiers: int, top_group_npus: int | None
) -> None:
    plan = plan_hierarchical_bandwidth(total_npus)
    assert plan.leaf_count == leaf_count
    assert plan.route_tier_count == route_tiers
    assert len(plan.tiers) == route_tiers
    if top_group_npus is not None:
        assert plan.tiers[-1].covered_npus_per_group == top_group_npus


def test_single_slice_degraded_plan_halves_link_rate_without_changing_link_count() -> None:
    bonded = plan_hierarchical_bandwidth(15132)
    degraded = plan_hierarchical_bandwidth(15132, active_slices_per_port=1)
    assert [tier.required_link_equivalents_per_plane_per_group for tier in degraded.tiers] == [
        tier.required_link_equivalents_per_plane_per_group for tier in bonded.tiers
    ]
    for bonded_tier, degraded_tier in zip(bonded.tiers, degraded.tiers, strict=True):
        assert bonded_tier.payload_gbyte_s_per_link_per_direction == 128.0
        assert degraded_tier.payload_gbyte_s_per_link_per_direction == 64.0
        assert degraded_tier.required_gbyte_s_per_plane_per_group == bonded_tier.required_gbyte_s_per_plane_per_group / 2


def test_traffic_fraction_and_reduction_are_explicit_not_hidden_in_route_capacity() -> None:
    worst_case = plan_hierarchical_bandwidth(78)
    reduced = plan_hierarchical_bandwidth(
        78,
        traffic_demand=BandwidthTrafficDemand(
            "ideal_in_network_reduce",
            cross_tier_fraction=0.5,
            reduction_factor=3.0,
        ),
    )
    assert reduced.tiers[0].offered_gbyte_s_per_plane_per_group == pytest.approx(
        worst_case.tiers[0].offered_gbyte_s_per_plane_per_group / 6.0
    )
    assert reduced.tiers[0].required_link_equivalents_per_plane_per_group == 13


def test_each_tier_accepts_an_independent_traffic_matrix_entry() -> None:
    demands = tuple(
        BandwidthTrafficDemand(f"tier_{index + 1}", fraction, reduction)
        for index, (fraction, reduction) in enumerate(
            zip((1.0, 0.5, 0.25), (1.0, 2.0, 4.0), strict=True)
        )
    )
    plan = plan_hierarchical_bandwidth(15132, traffic_demand=demands)
    worst_case = plan_hierarchical_bandwidth(15132)
    assert [tier.traffic_demand_name for tier in plan.tiers] == ["tier_1", "tier_2", "tier_3"]
    assert [tier.cross_tier_fraction for tier in plan.tiers] == [1.0, 0.5, 0.25]
    assert [tier.reduction_factor for tier in plan.tiers] == [1.0, 2.0, 4.0]
    assert plan.tiers[0].required_gbyte_s_per_plane_per_group == worst_case.tiers[0].required_gbyte_s_per_plane_per_group
    assert plan.tiers[1].required_gbyte_s_per_plane_per_group == worst_case.tiers[1].required_gbyte_s_per_plane_per_group / 4.0
    assert plan.tiers[2].required_gbyte_s_per_plane_per_group == worst_case.tiers[2].required_gbyte_s_per_plane_per_group / 16.0


def test_reference_rtt_drives_per_link_and_aggregate_bdp() -> None:
    plan = plan_hierarchical_bandwidth(SCALE_MAX_ENDPOINTS)
    assert [tier.round_trip_cycles for tier in plan.tiers] == list(REFERENCE_RTT_CYCLES)
    assert [tier.bdp_bytes_per_link for tier in plan.tiers] == [1792, 3072, 4352, 5632, 6912]
    assert plan.tiers[0].bdp_bytes_per_plane_per_group == 458752
    assert plan.tiers[-1].bdp_bytes_per_plane_per_group == 7247757312
    assert plan.tiers[-1].bdp_bytes_all_planes_per_group == 57982058496


def test_networkwide_link_count_includes_one_spare_per_plane_per_group() -> None:
    plan = plan_hierarchical_bandwidth(SCALE_MAX_ENDPOINTS)
    assert [tier.group_count for tier in plan.tiers] == [4096, 512, 64, 8, 1]
    assert plan.tiers[0].networkwide_installed_link_equivalents == 4096 * 257 * 8
    assert plan.tiers[-1].networkwide_installed_link_equivalents == 1048577 * 8


def test_failure_and_plane_degradation_are_visible_in_the_contract() -> None:
    no_spare = plan_hierarchical_bandwidth(
        33,
        policies=reference_tier_policies(spare_link_equivalents_per_plane=0),
    )
    eight_planes = plan_hierarchical_bandwidth(15132, active_planes=8)
    seven_planes = plan_hierarchical_bandwidth(15132, active_planes=7)
    assert not no_spare.tiers[0].survives_one_link_equivalent_failure
    assert seven_planes.tiers[-1].networkwide_installed_link_equivalents * 8 == (
        eight_planes.tiers[-1].networkwide_installed_link_equivalents * 7
    )
    assert seven_planes.tiers[-1].required_gbyte_s_per_plane_per_group == (
        eight_planes.tiers[-1].required_gbyte_s_per_plane_per_group
    )


@pytest.mark.parametrize(
    ("call", "message"),
    [
        (lambda: reference_tier_policies((1.0,)), "five tiers"),
        (lambda: reference_tier_policies((0.5,) * 5), "at least one"),
        (lambda: reference_tier_policies(rtt_cycles=(1, 2, 3, 4)), "five tiers"),
        (lambda: plan_hierarchical_bandwidth(33, active_planes=0), "plane count"),
        (lambda: plan_hierarchical_bandwidth(33, active_slices_per_port=3), "slice count"),
        (lambda: plan_hierarchical_bandwidth(33, clock_hz=0), "clock"),
        (
            lambda: plan_hierarchical_bandwidth(
                33, policies=(BandwidthTierPolicy(1.0, 14, 1),)[:0]
            ),
            "does not cover",
        ),
        (
            lambda: plan_hierarchical_bandwidth(
                33, traffic_demand=BandwidthTrafficDemand("invalid", 1.1, 1.0)
            ),
            "fraction",
        ),
        (
            lambda: plan_hierarchical_bandwidth(15132, traffic_demand=()),
            "traffic demand does not cover",
        ),
    ],
)
def test_invalid_bandwidth_contracts_are_rejected(call, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        call()


def test_machine_readable_bandwidth_contract_matches_model_defaults() -> None:
    config = json.loads((ROOT / "simulator" / "kdlink" / "config" / "million_scale.json").read_text())
    contract = config["hierarchical_bandwidth_contract"]
    assert contract["evidence_level"] == "ANALYTICAL"
    assert contract["slice_payload_gbyte_s_per_direction"] == 64
    assert contract["bonded_port_payload_gbyte_s_per_direction"] == 128
    assert contract["npu_payload_gbyte_s_per_direction"] == 1024
    assert contract["mandatory_dimensioning_traffic"] == "worst_case_cross_tier"
    assert contract["traffic_profiles"]["worst_case_cross_tier"] == {
        "cross_tier_fraction": [1, 1, 1, 1, 1],
        "reduction_factor": [1, 1, 1, 1, 1],
    }
    assert contract["reference_rtt_cycles_by_tier"] == list(REFERENCE_RTT_CYCLES)
    assert contract["oversubscription_profiles"]["nonblocking"] == list(NONBLOCKING_OVERSUBSCRIPTION)
    assert contract["oversubscription_profiles"]["balanced_example"] == list(BALANCED_OVERSUBSCRIPTION)
