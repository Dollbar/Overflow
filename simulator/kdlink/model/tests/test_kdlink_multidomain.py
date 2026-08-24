import json
from pathlib import Path

import pytest

from kdlink_model.multidomain import (
    CollectiveOpcode,
    CollectivePhase,
    GlobalCommitTracker,
    GlobalEndpoint,
    GlobalTransactionSource,
    GroupTable,
    RouteContext,
    escape_dependencies_are_acyclic,
    execute_hierarchical_collective,
    forward_at_route_stage,
    forward_at_spine,
    hierarchical_route_digits,
    remote_payload_efficiency,
    route_multidomain,
    schedule_hierarchical_collective,
    select_uplink,
)


ROOT = Path(__file__).parents[4]


def sample_context(**updates: int) -> RouteContext:
    values = {
        "source_domain": 0,
        "destination_domain": 7,
        "source_node": 31,
        "destination_node": 0,
        "topology_epoch": 19,
        "domain_hop_limit": 2,
        "logical_plane": 7,
        "slice_mask": 3,
        "route_policy": 0,
        "packet_flit_count": 16,
        "expected_packet_sequence": 4095,
        "global_transaction_id": 0xFEDCBA9876543210,
        "group_id": 0x89ABCDEF,
        "logical_vc": 4,
    }
    values.update(updates)
    return RouteContext(**values)


def test_global_endpoint_round_trip_covers_address_boundaries() -> None:
    for endpoint in (GlobalEndpoint(0, 0), GlobalEndpoint(1, 31), GlobalEndpoint(255, 31)):
        assert GlobalEndpoint.decode(endpoint.encode()) == endpoint
    with pytest.raises(ValueError, match="13-bit"):
        GlobalEndpoint.decode(8192)


def test_route_context_round_trip_is_bit_exact() -> None:
    context = sample_context()
    encoded = context.encode()
    assert encoded.bit_length() <= 512
    assert RouteContext.decode(encoded) == context
    RouteContext.decode(encoded).validate()


@pytest.mark.parametrize(
    ("updates", "message"),
    [
        ({"domain_hop_limit": 0}, "hop limit"),
        ({"slice_mask": 0}, "slice mask"),
        ({"route_policy": 1}, "policy"),
        ({"packet_flit_count": 0}, "flit count"),
        ({"packet_flit_count": 17}, "flit count"),
        ({"logical_vc": 6}, "logical VC"),
        ({"reserved": 1}, "reserved"),
    ],
)
def test_route_context_rejects_invalid_contract(updates: dict[str, int], message: str) -> None:
    with pytest.raises(ValueError, match=message):
        sample_context(**updates).encode()


def test_local_route_does_not_consume_an_uplink() -> None:
    route = route_multidomain(
        GlobalEndpoint(3, 1),
        GlobalEndpoint(3, 30),
        domain_count=8,
        uplink_count=4,
        active_uplink_mask=0xF,
        global_transaction_id=9,
    )
    assert route.local
    assert route.uplink is None
    assert route.domain_hops == 0


def test_two_domain_route_uses_one_direct_hop() -> None:
    route = route_multidomain(
        GlobalEndpoint(0, 31),
        GlobalEndpoint(1, 0),
        domain_count=2,
        uplink_count=2,
        active_uplink_mask=0b11,
        global_transaction_id=5,
    )
    assert not route.local
    assert route.uplink == 1
    assert route.spine is None
    assert route.domain_hops == 1


@pytest.mark.parametrize("domain_count", [4, 8])
def test_multidomain_route_selects_a_spine(domain_count: int) -> None:
    route = route_multidomain(
        GlobalEndpoint(0, 7),
        GlobalEndpoint(domain_count - 1, 29),
        domain_count=domain_count,
        uplink_count=4,
        active_uplink_mask=0b1101,
        global_transaction_id=4,
    )
    assert route.uplink in (0, 2, 3)
    assert route.spine == route.uplink
    assert route.domain_hops == 2


def test_uplink_mask_removes_failed_paths() -> None:
    assert [select_uplink(index, 0b1010, 4) for index in range(4)] == [1, 3, 1, 3]
    with pytest.raises(RuntimeError, match="no active"):
        select_uplink(0, 0, 4)


def test_route_context_overhead_is_explicit() -> None:
    assert remote_payload_efficiency(1) == 0.5
    assert remote_payload_efficiency(16) == pytest.approx(16 / 17)


def test_multidomain_configuration_matches_model_contract() -> None:
    config = json.loads((ROOT / "simulator" / "kdlink" / "config" / "multidomain.json").read_text())
    assert config["route_schema"] == 3
    assert config["route_context_message_type"] == 8
    assert config["route_context_logical_vc_bits"] == [165, 163]
    assert config["nodes_per_domain"] == 32
    assert config["maximum_domains"] == 256
    assert config["validated_domain_profiles"] == [2, 4, 8, 16, 32, 64, 128, 256]
    assert config["rtl_validated_domain_profiles"] == [2, 4, 8, 16, 32, 64, 128, 256]
    assert config["production_context_ack_barrier"] == "implemented"
    assert config["bonded_route_transport"] == "validated"
    assert config["intermediate_spine_routing"] == "radix8_one_to_three_stage_implemented"
    assert config["global_commit"] == "implemented_and_route_reset_validated"
    assert len(config["hierarchical_collectives"]) == 6


@pytest.mark.parametrize("domain_count", [4, 8])
def test_spine_forwards_every_domain_and_decrements_hop(domain_count: int) -> None:
    for destination_domain in range(domain_count):
        forwarded = forward_at_spine(
            sample_context(destination_domain=destination_domain, domain_hop_limit=2),
            domain_count=domain_count,
            active_domain_mask=(1 << domain_count) - 1,
        )
        assert forwarded.egress_domain == destination_domain
        assert forwarded.context.domain_hop_limit == 1
        assert forwarded.escape_stages == ("leaf_up", "spine", "leaf_down")
    assert escape_dependencies_are_acyclic(domain_count)


def test_spine_rejects_inactive_and_exhausted_routes() -> None:
    with pytest.raises(RuntimeError, match="inactive"):
        forward_at_spine(sample_context(destination_domain=3), domain_count=4, active_domain_mask=0b0111)
    with pytest.raises(RuntimeError, match="exhausted"):
        forward_at_spine(
            sample_context(destination_domain=3, domain_hop_limit=1),
            domain_count=4,
            active_domain_mask=0b1111,
        )


@pytest.mark.parametrize(
    ("domain_count", "destination", "digits"),
    [
        (8, 7, (7,)),
        (16, 15, (1, 7)),
        (32, 31, (3, 7)),
        (64, 63, (7, 7)),
        (128, 127, (1, 7, 7)),
        (256, 255, (3, 7, 7)),
    ],
)
def test_radix_eight_hierarchy_covers_every_scale(
    domain_count: int, destination: int, digits: tuple[int, ...]
) -> None:
    assert hierarchical_route_digits(destination, domain_count) == digits
    route = route_multidomain(
        GlobalEndpoint(0, 0),
        GlobalEndpoint(destination, 31),
        domain_count=domain_count,
        uplink_count=4,
        active_uplink_mask=0xF,
        global_transaction_id=destination,
    )
    assert route.route_digits == digits
    assert route.domain_hops == len(digits) + 1
    assert escape_dependencies_are_acyclic(domain_count)


@pytest.mark.parametrize("domain_count", [16, 32, 64, 128, 256])
def test_every_domain_routes_through_monotonic_stages(domain_count: int) -> None:
    for destination in range(domain_count):
        digits = hierarchical_route_digits(destination, domain_count)
        context = sample_context(destination_domain=destination, domain_hop_limit=len(digits) + 1)
        for stage_index, expected_egress in enumerate(digits):
            forwarded = forward_at_route_stage(
                context,
                domain_count=domain_count,
                stage_index=stage_index,
                active_egress_mask=0xFF,
            )
            assert forwarded.egress == expected_egress
            assert forwarded.context.domain_hop_limit == context.domain_hop_limit - 1
            assert forwarded.final_stage == (stage_index == len(digits) - 1)
            context = forwarded.context


def test_route_stage_rejects_failed_egress_and_short_hop_budget() -> None:
    with pytest.raises(RuntimeError, match="inactive"):
        forward_at_route_stage(
            sample_context(destination_domain=63, domain_hop_limit=3),
            domain_count=64,
            stage_index=0,
            active_egress_mask=0x7F,
        )
    with pytest.raises(RuntimeError, match="cannot reach"):
        forward_at_route_stage(
            sample_context(destination_domain=255, domain_hop_limit=3),
            domain_count=256,
            stage_index=0,
            active_egress_mask=0xFF,
        )


def test_global_commit_survives_lost_ack_and_route_reset_exactly_once() -> None:
    source = GlobalTransactionSource(timeout_cycles=2)
    destination = GlobalCommitTracker(history_depth=8)
    endpoint = GlobalEndpoint(3, 17)
    source.begin(0x1234, 7)
    first = source.next_send()
    assert first is not None and first.retry_count == 0
    first_commit = destination.commit(endpoint, first.transaction_id, first.topology_epoch)
    assert first_commit.deliver and first_commit.acknowledge
    source.route_reset(8)
    destination.route_reset()
    retry = source.next_send()
    assert retry is not None and retry.retry_count == 1 and retry.topology_epoch == 8
    retry_commit = destination.commit(endpoint, retry.transaction_id, retry.topology_epoch)
    assert not retry_commit.deliver and retry_commit.acknowledge
    duplicate_commit = destination.commit(endpoint, retry.transaction_id, retry.topology_epoch)
    assert not duplicate_commit.deliver and duplicate_commit.acknowledge
    assert source.commit(retry.transaction_id, retry.topology_epoch)
    assert source.outstanding == ()
    assert not source.commit(retry.transaction_id, retry.topology_epoch)


def test_global_commit_timeout_replays_without_route_reset() -> None:
    source = GlobalTransactionSource(timeout_cycles=2)
    source.begin(99, 4)
    assert source.next_send().retry_count == 0
    source.tick()
    source.tick()
    assert source.next_send().retry_count == 1
    assert not source.commit(99, 3)
    assert source.commit(99, 4)


def test_source_backpressures_an_occupied_replay_window_slot() -> None:
    source = GlobalTransactionSource()
    source.begin(1, 4)
    with pytest.raises(RuntimeError, match="slot is occupied"):
        source.begin(17, 4)


def test_group_table_is_epoch_exact() -> None:
    table = GroupTable()
    table.configure(0x55, [0, 7, 63, 255], 19)
    assert table.lookup(0x55, 19) == (0, 7, 63, 255)
    with pytest.raises(KeyError, match="epoch"):
        table.lookup(0x55, 20)


@pytest.mark.parametrize("opcode", list(CollectiveOpcode))
def test_all_six_operations_have_explicit_hierarchical_phases(opcode: CollectiveOpcode) -> None:
    commands = schedule_hierarchical_collective(
        opcode,
        local_domain=0,
        group_members=(0, 8, 63, 255),
        source_domain=0,
        destination_domain=255,
    )
    assert commands[0].phase == CollectivePhase.LEAF_PREPARE
    assert commands[-2].phase == CollectivePhase.LEAF_FINISH
    assert commands[-1].phase == CollectivePhase.COMPLETE
    remotes = [command.destination_domain for command in commands if command.phase == CollectivePhase.INTERDOMAIN]
    assert remotes == ([255] if opcode == CollectiveOpcode.POINT_TO_POINT else [8, 63, 255])


def test_six_operation_data_semantics_across_four_domains() -> None:
    members = (0, 8, 63, 255)
    vectors = {member: (index, index + 1, index + 2, index + 3) for index, member in enumerate(members)}
    reduced = execute_hierarchical_collective(CollectiveOpcode.ALL_REDUCE, vectors, members)
    assert reduced[255] == (6, 10, 14, 18)
    scattered = execute_hierarchical_collective(CollectiveOpcode.REDUCE_SCATTER, vectors, members)
    assert scattered == {0: (6,), 8: (10,), 63: (14,), 255: (18,)}
    gathered = execute_hierarchical_collective(
        CollectiveOpcode.ALL_GATHER,
        {member: (index,) for index, member in enumerate(members)},
        members,
    )
    assert gathered[63] == (0, 1, 2, 3)
    matrix = {
        source: {destination: (source, destination) for destination in members}
        for source in members
    }
    for opcode in (CollectiveOpcode.ALL_TO_ALL, CollectiveOpcode.ALL_TO_ALL_V):
        exchanged = execute_hierarchical_collective(opcode, matrix, members)
        assert exchanged[255][8] == (8, 255)
    point = execute_hierarchical_collective(
        CollectiveOpcode.POINT_TO_POINT,
        vectors,
        members,
        source_domain=8,
        destination_domain=255,
    )
    assert point == {255: vectors[8]}
