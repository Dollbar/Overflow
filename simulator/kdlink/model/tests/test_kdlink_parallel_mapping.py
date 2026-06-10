import pytest

from kdlink_model.parallel_mapping import ParallelCoordinate, ParallelPlacement


def test_parallel_coordinate_round_trip_uses_tensor_fastest_dense_order() -> None:
    placement = ParallelPlacement(256, 8, 8, 1, 4)
    placement.validate()
    assert placement.coordinate(0) == ParallelCoordinate(0, 0, 0, 0)
    assert placement.coordinate(63) == ParallelCoordinate(7, 0, 7, 0)
    assert placement.coordinate(64) == ParallelCoordinate(0, 0, 0, 1)
    for ordinal in (0, 1, 31, 32, 63, 64, 127, 255):
        assert placement.ordinal(placement.coordinate(ordinal)) == ordinal


def test_exact_axis_crossing_keeps_local_tensor_traffic_below_tier_one() -> None:
    placement = ParallelPlacement(64, 8, 8, 1, 1)
    tensor = placement.axis_crossing("tensor", 1, "ring")
    pipeline = placement.axis_crossing("pipeline", 1, "adjacent")
    assert tensor.crossing_fraction == 0.0
    assert tensor.active_communication_groups == 0
    assert pipeline.crossing_fraction == pytest.approx(1.0 / 7.0)
    assert pipeline.active_communication_groups == 8


def test_strided_data_axis_crosses_lower_tiers_but_not_its_enclosing_group() -> None:
    placement = ParallelPlacement(256, 8, 8, 1, 4)
    assert placement.axis_stride("data") == 64
    assert placement.communication_group_span("data") == 193
    assert placement.axis_crossing("data", 1, "uniform").crossing_fraction == 1.0
    assert placement.axis_crossing("data", 2, "uniform").crossing_fraction == 0.0


def test_explicit_axis_order_can_distribute_experts_across_high_tiers() -> None:
    placement = ParallelPlacement(
        2048,
        8,
        8,
        4,
        8,
        axis_order=("tensor", "pipeline", "data", "expert"),
    )
    assert placement.axis_stride("expert") == 512
    assert placement.axis_crossing("expert", 1, "uniform").crossing_fraction == 1.0
    assert placement.axis_crossing("expert", 2, "uniform").crossing_fraction == 1.0


def test_resource_loads_preserve_crossing_traffic_and_physical_group_count() -> None:
    placement = ParallelPlacement(
        2048,
        1,
        1,
        64,
        32,
        axis_order=("tensor", "pipeline", "data", "expert"),
    )
    tier_one = placement.axis_resource_loads("expert", 1, "uniform")
    tier_two = placement.axis_resource_loads("expert", 2, "uniform")
    assert tier_one.resource_group_count == 8
    assert tier_two.resource_group_count == 1
    assert sum(tier_one.load_fractions) == pytest.approx(1.0)
    assert sum(tier_two.load_fractions) == pytest.approx(1.0)
    assert tier_one.crossing_units > 0


def test_adjacent_leaf_injection_excludes_the_last_non_sender() -> None:
    placement = ParallelPlacement(33, 1, 33, 1, 1)
    leaf_loads = placement.leaf_source_loads("pipeline", "adjacent")
    assert leaf_loads == pytest.approx((1.0, 0.0))


def test_irregular_population_parallel_mapping_has_no_padding_rank() -> None:
    placement = ParallelPlacement(15132, 3, 13, 1, 388)
    placement.validate()
    assert placement.ordinal(placement.coordinate(15131)) == 15131
    assert placement.communication_group_count("pipeline") == 1164
    with pytest.raises(ValueError, match="outside"):
        placement.coordinate(15132)


@pytest.mark.parametrize(
    "placement",
    (
        ParallelPlacement(64, 8, 8, 1, 2),
        ParallelPlacement(64, 0, 8, 1, 8),
        ParallelPlacement(1048577, 1, 1, 1, 1048577),
    ),
)
def test_invalid_parallel_placements_are_rejected(placement: ParallelPlacement) -> None:
    with pytest.raises(ValueError):
        placement.validate()
