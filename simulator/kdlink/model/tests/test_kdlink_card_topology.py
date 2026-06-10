import pytest

from kdlink_model.card_topology import (
    MAX_CARD_SLOTS,
    NODES_PER_LEAF,
    SUPPORTED_NPUS_PER_CARD,
    CardDescriptor,
    CardDirectory,
    compact_card_layout,
    homogeneous_card_layout,
)


@pytest.mark.parametrize("npus_per_card", SUPPORTED_NPUS_PER_CARD)
def test_all_homogeneous_card_profiles_round_trip(npus_per_card: int) -> None:
    directory = CardDirectory(homogeneous_card_layout(npus_per_card))
    observed = set()
    for slot_id in range(NODES_PER_LEAF // npus_per_card):
        for local_npu in range(npus_per_card):
            for plane_id in range(8):
                for slice_id in range(2):
                    endpoint = directory.endpoint_index(slot_id, local_npu, plane_id, slice_id)
                    location, observed_plane, observed_slice = directory.decode_endpoint(endpoint)
                    assert location.slot_id == slot_id
                    assert location.local_npu == local_npu
                    assert location.node_id == slot_id * npus_per_card + local_npu
                    assert observed_plane == plane_id
                    assert observed_slice == slice_id
                    observed.add(endpoint)
    assert observed == set(range(512))


def test_mixed_card_layout_covers_every_node_without_alias() -> None:
    counts = (8, 8, 4, 4, 2, 2, 1, 1, 1, 1)
    descriptors = []
    base_node = 0
    for slot_id, npu_count in enumerate(counts):
        descriptors.append(CardDescriptor(slot_id, base_node, npu_count))
        base_node += npu_count
    directory = CardDirectory(descriptors)
    assert base_node == 32
    assert {directory.node_location(node).slot_id for node in range(32)} == set(range(10))
    assert [directory.node_location(node).local_npu for node in range(8)] == list(range(8))
    assert [directory.node_location(node).local_npu for node in range(30, 32)] == [0, 0]


@pytest.mark.parametrize("npu_count", [1, 2, 3, 14, 28, 31, 32])
def test_compact_partial_leaf_layout_maps_only_requested_npus(npu_count: int) -> None:
    descriptors = compact_card_layout(npu_count)
    directory = CardDirectory(descriptors)
    assert sum(descriptor.npu_count for descriptor in descriptors) == npu_count
    assert tuple(descriptor.base_node_id for descriptor in descriptors) == tuple(
        sum(item.npu_count for item in descriptors[:index]) for index in range(len(descriptors))
    )
    for node_id in range(NODES_PER_LEAF):
        assert directory.node_active(node_id) == (node_id < npu_count)
        if node_id < npu_count:
            location = directory.node_location(node_id)
            for plane_id in range(8):
                for slice_id in range(2):
                    endpoint = directory.endpoint_index(
                        location.slot_id, location.local_npu, plane_id, slice_id
                    )
                    decoded, observed_plane, observed_slice = directory.decode_endpoint(endpoint)
                    assert decoded == location
                    assert observed_plane == plane_id
                    assert observed_slice == slice_id
        else:
            with pytest.raises(ValueError, match="not mapped"):
                directory.node_location(node_id)


@pytest.mark.parametrize("npu_count", [0, 33])
def test_compact_partial_leaf_layout_rejects_out_of_range_population(npu_count: int) -> None:
    with pytest.raises(ValueError, match="from 1 through 32"):
        compact_card_layout(npu_count)


@pytest.mark.parametrize(
    "descriptors, message",
    [
        ((), "at least one"),
        ((CardDescriptor(32, 0, 1),), "32-slot"),
        ((CardDescriptor(0, 0, 3),), "power-of-two"),
        ((CardDescriptor(0, 31, 2),), "exceeds"),
        ((CardDescriptor(0, 0, 4), CardDescriptor(0, 4, 4)), "duplicate"),
        ((CardDescriptor(0, 0, 8), CardDescriptor(1, 7, 8)), "overlap"),
    ],
)
def test_invalid_card_layouts_are_rejected(
    descriptors: tuple[CardDescriptor, ...], message: str
) -> None:
    with pytest.raises(ValueError, match=message):
        CardDirectory(descriptors)


def test_prepare_commit_is_atomic_and_epoch_checked() -> None:
    directory = CardDirectory()
    before = tuple(directory.node_location(node) for node in range(32))
    directory.prepare(homogeneous_card_layout(8), topology_epoch=1)
    assert tuple(directory.node_location(node) for node in range(32)) == before
    with pytest.raises(RuntimeError, match="quiescent"):
        directory.commit(quiescent=False)
    directory.commit(quiescent=True)
    assert directory.active_epoch == 1
    assert directory.node_location(31).slot_id == 3
    assert directory.node_location(31).local_npu == 7
    directory.prepare(homogeneous_card_layout(2), topology_epoch=1)
    with pytest.raises(RuntimeError, match="stale"):
        directory.commit(quiescent=True)


def test_epoch_wrap_and_partial_population_are_supported() -> None:
    directory = CardDirectory(topology_epoch=0xFFFF)
    directory.prepare((CardDescriptor(31, 0, 1),), topology_epoch=0)
    directory.commit(quiescent=True)
    assert directory.active_epoch == 0
    assert directory.node_active(0)
    assert not directory.node_active(1)
    assert directory.node_location(0).slot_id == 31
    with pytest.raises(ValueError, match="not mapped"):
        directory.node_location(1)


def test_card_presence_and_reset_only_affect_owned_nodes() -> None:
    directory = CardDirectory(homogeneous_card_layout(8))
    directory.set_card_state(2, present=False)
    assert [directory.node_active(node) for node in range(32)] == [
        not 16 <= node < 24 for node in range(32)
    ]
    directory.set_card_state(2, present=True, reset_done=False)
    assert not any(directory.node_active(node) for node in range(16, 24))
    directory.set_card_state(2, reset_done=True)
    assert all(directory.node_active(node) for node in range(32))
    with pytest.raises(ValueError, match="32-slot"):
        directory.set_card_state(MAX_CARD_SLOTS, present=False)
