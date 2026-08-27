import json
from pathlib import Path

import pytest

from kdlink_model.scale import (
    DistributedGroupDirectory,
    SCALE_MAX_ENDPOINTS,
    SCALE_NODES_PER_DOMAIN,
    ScaleDeploymentTopology,
    ScaleEndpoint,
    ScaleGlobalCommit,
    ScaleRouteContext,
    forward_scale_route_stage,
    scale_route_digits,
    scale_route_stage_count,
    select_scale_plane,
)


ROOT = Path(__file__).parents[4]


def sample_scale_context(**updates: int) -> ScaleRouteContext:
    values = {
        "source_domain": 0,
        "destination_domain": 32767,
        "source_node": 31,
        "destination_node": 0,
        "topology_epoch": 0xA55A,
        "domain_hop_limit": 6,
        "logical_plane": 7,
        "slice_mask": 3,
        "route_policy": 0,
        "packet_flit_count": 16,
        "expected_packet_sequence": 4095,
        "global_transaction_id": 0xFEDCBA9876543210,
        "group_id": 0x89ABCDEF,
        "logical_vc": 5,
        "route_depth": 5,
    }
    values.update(updates)
    return ScaleRouteContext(**values)


def test_all_million_scale_endpoint_addresses_round_trip() -> None:
    for encoded in range(SCALE_MAX_ENDPOINTS):
        assert ScaleEndpoint.decode(encoded).encode() == encoded
    with pytest.raises(ValueError, match="20-bit"):
        ScaleEndpoint.decode(SCALE_MAX_ENDPOINTS)


@pytest.mark.parametrize(
    ("total_npus", "leaf_count", "final_leaf_npus"),
    [
        (2, 1, 2),
        (3, 1, 3),
        (33, 2, 1),
        (78, 3, 14),
        (15132, 473, 28),
    ],
)
def test_irregular_deployments_have_contiguous_addresses_and_partial_final_leaf(
    total_npus: int, leaf_count: int, final_leaf_npus: int
) -> None:
    topology = ScaleDeploymentTopology(total_npus)
    assert topology.leaf_count == leaf_count
    assert topology.final_leaf_npu_count == final_leaf_npus
    assert topology.inter_domain_route_stages == (0 if leaf_count == 1 else scale_route_stage_count(leaf_count))
    assert topology.leaf_member_mask(leaf_count - 1) == (1 << final_leaf_npus) - 1
    for ordinal in range(total_npus):
        endpoint = topology.endpoint_for_ordinal(ordinal)
        assert topology.contains_endpoint(endpoint)
        assert topology.ordinal_for_endpoint(endpoint) == ordinal
        assert endpoint.local_node < topology.leaf_npu_count(endpoint.domain_id)
    with pytest.raises(ValueError, match="ordinal"):
        topology.endpoint_for_ordinal(total_npus)
    if final_leaf_npus < SCALE_NODES_PER_DOMAIN:
        first_inactive = ScaleEndpoint(leaf_count - 1, final_leaf_npus)
        assert not topology.contains_endpoint(first_inactive)
        with pytest.raises(ValueError, match="outside"):
            topology.ordinal_for_endpoint(first_inactive)


@pytest.mark.parametrize(
    "total_npus",
    [1, 2, 3, 31, 32, 33, 63, 64, 65, 78, 511, 512, 513, 1023, 1024, 1025, 15132, SCALE_MAX_ENDPOINTS - 1, SCALE_MAX_ENDPOINTS],
)
def test_population_boundaries_preserve_leaf_capacity(total_npus: int) -> None:
    topology = ScaleDeploymentTopology(total_npus)
    assert sum(topology.leaf_npu_count(domain) for domain in range(topology.leaf_count)) == total_npus
    assert 1 <= topology.final_leaf_npu_count <= SCALE_NODES_PER_DOMAIN
    assert topology.endpoint_for_ordinal(total_npus - 1).encode() == total_npus - 1
    if topology.leaf_count > 1:
        assert len(scale_route_digits(topology.leaf_count - 1, topology.leaf_count)) == topology.inter_domain_route_stages


@pytest.mark.parametrize("total_npus", [0, SCALE_MAX_ENDPOINTS + 1])
def test_deployment_rejects_population_outside_global_capacity(total_npus: int) -> None:
    with pytest.raises(ValueError, match="deployment NPU count"):
        ScaleDeploymentTopology(total_npus).validate()


@pytest.mark.parametrize("total_npus", [33, 78, 15132])
def test_irregular_multileaf_group_contains_every_active_npu_only(total_npus: int) -> None:
    topology = ScaleDeploymentTopology(total_npus)
    members = [topology.endpoint_for_ordinal(ordinal) for ordinal in range(total_npus)]
    directory = DistributedGroupDirectory(topology.leaf_count)
    directory.configure(0x13579BDF, members, 0x2468, members[0])
    root = directory.lookup(0x13579BDF, 0x2468, 0, ())
    assert root.subtree_member_count == total_npus
    last_domain = topology.leaf_count - 1
    last_digits = scale_route_digits(last_domain, topology.leaf_count)
    leaf = directory.lookup(0x13579BDF, 0x2468, topology.inter_domain_route_stages, last_digits)
    assert leaf.local_member_mask == topology.leaf_member_mask(last_domain)
    assert leaf.subtree_member_count == topology.final_leaf_npu_count


def test_schema_four_route_context_round_trip_is_bit_exact() -> None:
    context = sample_scale_context()
    encoded = context.encode()
    assert encoded.bit_length() <= 512
    assert ScaleRouteContext.decode(encoded) == context
    ScaleRouteContext.decode(encoded).validate()


def test_schema_four_global_commit_round_trip_and_reserved_status() -> None:
    commit = ScaleGlobalCommit(
        source_domain=32767,
        destination_domain=16384,
        source_node=31,
        destination_node=17,
        topology_epoch=0xBEEF,
        global_transaction_id=0x0123456789ABCDEF,
        status=2,
    )
    encoded = commit.encode()
    assert encoded.bit_length() <= 512
    assert ScaleGlobalCommit.decode(encoded) == commit
    with pytest.raises(ValueError, match="reserved"):
        ScaleGlobalCommit(**{**commit.__dict__, "status": 3}).encode()


@pytest.mark.parametrize(
    ("updates", "message"),
    [
        ({"source_domain": 32768}, "15-bit"),
        ({"topology_epoch": 65536}, "16 bits"),
        ({"domain_hop_limit": 0}, "hop limit"),
        ({"slice_mask": 0}, "slice mask"),
        ({"route_policy": 1}, "policy"),
        ({"logical_vc": 6}, "logical VC"),
        ({"route_depth": 0}, "route depth"),
        ({"route_depth": 6}, "route depth"),
        ({"reserved": 1}, "reserved"),
    ],
)
def test_schema_four_context_rejects_invalid_fields(updates: dict[str, int], message: str) -> None:
    with pytest.raises(ValueError, match=message):
        sample_scale_context(**updates).encode()


@pytest.mark.parametrize(
    ("domain_count", "destination", "expected"),
    [
        (8, 7, (7,)),
        (64, 63, (7, 7)),
        (512, 511, (7, 7, 7)),
        (1024, 1023, (1, 7, 7, 7)),
        (4096, 4095, (7, 7, 7, 7)),
        (8192, 8191, (1, 7, 7, 7, 7)),
        (32768, 32767, (7, 7, 7, 7, 7)),
    ],
)
def test_route_profiles_use_minimum_radix_eight_depth(
    domain_count: int, destination: int, expected: tuple[int, ...]
) -> None:
    assert scale_route_stage_count(domain_count) == len(expected)
    assert scale_route_digits(destination, domain_count) == expected


def test_all_32768_destinations_cross_five_monotonic_stages() -> None:
    for destination in range(32768):
        context = sample_scale_context(destination_domain=destination)
        digits = scale_route_digits(destination, 32768)
        previous_rank = 0
        for stage_index, expected_egress in enumerate(digits):
            forwarded = forward_scale_route_stage(
                context,
                domain_count=32768,
                stage_index=stage_index,
                active_egress_mask=0xFF,
            )
            assert forwarded.egress == expected_egress
            assert forwarded.escape_rank > previous_rank
            assert forwarded.final_stage == (stage_index == 4)
            previous_rank = forwarded.escape_rank
            context = forwarded.context


def test_scale_stage_rejects_inactive_egress_short_hop_and_wrong_depth() -> None:
    with pytest.raises(RuntimeError, match="inactive"):
        forward_scale_route_stage(
            sample_scale_context(), domain_count=32768, stage_index=0, active_egress_mask=0x7F
        )
    with pytest.raises(RuntimeError, match="cannot reach"):
        forward_scale_route_stage(
            sample_scale_context(domain_hop_limit=5), domain_count=32768, stage_index=0, active_egress_mask=0xFF
        )
    with pytest.raises(ValueError, match="route depth"):
        forward_scale_route_stage(
            sample_scale_context(route_depth=4), domain_count=32768, stage_index=0, active_egress_mask=0xFF
        )


def test_distributed_group_directory_uses_only_local_masks() -> None:
    members = [
        ScaleEndpoint(0, 0),
        ScaleEndpoint(0, 31),
        ScaleEndpoint(4096, 3),
        ScaleEndpoint(32767, 17),
    ]
    directory = DistributedGroupDirectory(32768)
    directory.configure(0x1234, members, 0x55AA, members[0])
    root = directory.lookup(0x1234, 0x55AA, 0, ())
    assert root.child_mask == 0b10000011
    assert root.subtree_member_count == 4
    leaf = directory.lookup(0x1234, 0x55AA, 5, (0, 0, 0, 0, 0))
    assert leaf.child_mask == 0
    assert leaf.local_member_mask == (1 << 0) | (1 << 31)
    assert leaf.subtree_member_count == 2


def test_plane_selection_has_deterministic_escape_fallback() -> None:
    assert select_scale_plane(5, 0b10101010) in (1, 3, 5, 7)
    assert select_scale_plane(5, 0b00000001) == 0
    for mask in range(2, 256):
        assert select_scale_plane(5, mask) != 0
    assert select_scale_plane(5, 0b00000001, allow_adaptive=False) == 0
    with pytest.raises(RuntimeError, match="escape"):
        select_scale_plane(5, 0b00000010, allow_adaptive=False)


def test_million_scale_configuration_matches_frozen_capacity() -> None:
    config = json.loads((ROOT / "simulator" / "kdlink" / "config" / "million_scale.json").read_text())
    assert config["scale_schema"] == 4
    assert config["domain_identifier_bits"] == 15
    assert config["global_endpoint_bits"] == 20
    assert config["maximum_domains"] == 32768
    assert config["maximum_global_endpoints"] == 1048576
    assert config["minimum_global_endpoints"] == 1
    assert config["maximum_route_stages"] == 5
    assert config["partial_leaf_population_supported"]
    assert config["validated_irregular_total_npus"] == [2, 3, 33, 78, 15132]
    assert config["distributed_group_child_mask_bits"] == 8
    assert config["legacy_schema_3_compatible"]
    assert not config["monolithic_million_endpoint_rtl"]
