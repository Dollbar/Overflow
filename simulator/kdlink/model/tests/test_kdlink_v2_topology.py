import pytest

from kdlink_model.topology import is_permutation, route_direct, select_plane


def test_direct_kdswitch_route_maps_node_to_port() -> None:
    route = route_direct(3, 29, 7)
    assert route.ingress_port == 3
    assert route.egress_port == 29
    assert route.plane_id == 7


def test_plane_selection_stripes_and_masks_failed_plane() -> None:
    assert [select_plane(0, chunk) for chunk in range(8)] == list(range(8))
    mask_without_plane_three = 0xF7
    assert 3 not in [select_plane(0, chunk, mask_without_plane_three) for chunk in range(32)]
    with pytest.raises(RuntimeError, match="no active"):
        select_plane(0, 0, 0)


def test_permutation_contract() -> None:
    destinations = [(node + 1) % 32 for node in range(32)]
    assert is_permutation(destinations)
    assert not is_permutation([1] * 32)
