"""Deterministic inference-parallel rank placement on KDLink endpoints."""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

from .scale import SCALE_MAX_ENDPOINTS, SCALE_MAX_ROUTE_STAGES, SCALE_NODES_PER_DOMAIN


PARALLEL_AXES = ("tensor", "expert", "pipeline", "data")
TRAFFIC_PATTERNS = ("ring", "uniform", "adjacent")


@dataclass(frozen=True)
class ParallelCoordinate:
    """One dense endpoint coordinate in TP, EP, PP, and DP order."""

    tensor: int
    expert: int
    pipeline: int
    data: int


@dataclass(frozen=True)
class AxisCrossing:
    """Exact hierarchy-boundary crossing statistics for one parallel axis."""

    axis: str
    tier_index: int
    pattern: str
    crossing_fraction: float
    communication_group_count: int
    active_communication_groups: int
    maximum_group_crossing_fraction: float


@dataclass(frozen=True)
class AxisResourceLoads:
    """Normalized source-side load distribution across one hierarchy resource tier."""

    axis: str
    tier_index: int
    pattern: str
    resource_group_count: int
    crossing_units: int
    load_fractions: tuple[float, ...]


@dataclass(frozen=True)
class ParallelPlacement:
    """Dense rank mapping with an explicit fastest-to-slowest axis order."""

    total_npus: int
    tensor_parallel: int
    pipeline_parallel: int
    expert_parallel: int
    data_parallel: int
    axis_order: tuple[str, ...] = ("tensor", "expert", "pipeline", "data")

    def validate(self) -> None:
        dimensions = (
            self.tensor_parallel,
            self.pipeline_parallel,
            self.expert_parallel,
            self.data_parallel,
        )
        if not 1 <= self.total_npus <= SCALE_MAX_ENDPOINTS:
            raise ValueError("parallel placement exceeds the KDLink endpoint space")
        if any(dimension < 1 for dimension in dimensions):
            raise ValueError("parallel dimensions must be positive")
        if (
            len(self.axis_order) != len(PARALLEL_AXES)
            or set(self.axis_order) != set(PARALLEL_AXES)
        ):
            raise ValueError("parallel axis order must contain every axis exactly once")
        if (
            self.tensor_parallel
            * self.pipeline_parallel
            * self.expert_parallel
            * self.data_parallel
            != self.total_npus
        ):
            raise ValueError("parallel dimensions must exactly cover every active NPU")

    def axis_size(self, axis: str) -> int:
        self.validate()
        sizes = {
            "tensor": self.tensor_parallel,
            "expert": self.expert_parallel,
            "pipeline": self.pipeline_parallel,
            "data": self.data_parallel,
        }
        if axis not in sizes:
            raise ValueError("unknown parallel axis")
        return sizes[axis]

    def axis_stride(self, axis: str) -> int:
        self.validate()
        if axis not in PARALLEL_AXES:
            raise ValueError("unknown parallel axis")
        stride = 1
        for ordered_axis in self.axis_order:
            if ordered_axis == axis:
                return stride
            stride *= self.axis_size(ordered_axis)
        raise AssertionError("validated axis order did not contain requested axis")

    def coordinate(self, ordinal: int) -> ParallelCoordinate:
        self.validate()
        if not 0 <= ordinal < self.total_npus:
            raise ValueError("parallel ordinal is outside the active placement")
        coordinates = {}
        quotient = ordinal
        for axis in self.axis_order:
            coordinates[axis] = quotient % self.axis_size(axis)
            quotient //= self.axis_size(axis)
        return ParallelCoordinate(
            coordinates["tensor"],
            coordinates["expert"],
            coordinates["pipeline"],
            coordinates["data"],
        )

    def ordinal(self, coordinate: ParallelCoordinate) -> int:
        self.validate()
        if not 0 <= coordinate.tensor < self.tensor_parallel:
            raise ValueError("tensor coordinate is outside the placement")
        if not 0 <= coordinate.expert < self.expert_parallel:
            raise ValueError("expert coordinate is outside the placement")
        if not 0 <= coordinate.pipeline < self.pipeline_parallel:
            raise ValueError("pipeline coordinate is outside the placement")
        if not 0 <= coordinate.data < self.data_parallel:
            raise ValueError("data coordinate is outside the placement")
        coordinate_values = {
            "tensor": coordinate.tensor,
            "expert": coordinate.expert,
            "pipeline": coordinate.pipeline,
            "data": coordinate.data,
        }
        return sum(
            coordinate_values[axis] * self.axis_stride(axis) for axis in PARALLEL_AXES
        )

    def communication_group_count(self, axis: str) -> int:
        return self.total_npus // self.axis_size(axis)

    def communication_group_span(self, axis: str) -> int:
        size = self.axis_size(axis)
        return (size - 1) * self.axis_stride(axis) + 1

    def _group_bases(self, axis: str):
        size = self.axis_size(axis)
        stride = self.axis_stride(axis)
        prefix_count = self.total_npus // (size * stride)
        for prefix in range(prefix_count):
            prefix_base = prefix * size * stride
            for suffix in range(stride):
                yield prefix_base + suffix

    @lru_cache(maxsize=None)
    def axis_crossing(self, axis: str, tier_index: int, pattern: str) -> AxisCrossing:
        """Count exact traffic crossings without materializing endpoint or packet objects."""

        size = self.axis_size(axis)
        stride = self.axis_stride(axis)
        if not 1 <= tier_index <= SCALE_MAX_ROUTE_STAGES:
            raise ValueError("tier index is outside the KDLink hierarchy")
        if pattern not in TRAFFIC_PATTERNS:
            raise ValueError("unknown parallel communication pattern")
        group_count = self.communication_group_count(axis)
        if size == 1:
            return AxisCrossing(axis, tier_index, pattern, 0.0, group_count, 0, 0.0)

        lower_group_endpoints = SCALE_NODES_PER_DOMAIN * (8 ** (tier_index - 1))
        crossing_units = 0
        total_units = 0
        active_groups = 0
        maximum_group_fraction = 0.0
        for base in self._group_bases(axis):
            if pattern == "uniform":
                block_counts: dict[int, int] = {}
                for member in range(size):
                    block = (base + member * stride) // lower_group_endpoints
                    block_counts[block] = block_counts.get(block, 0) + 1
                group_total = size * (size - 1)
                group_crossing = group_total - sum(
                    count * (count - 1) for count in block_counts.values()
                )
            elif pattern == "ring":
                group_total = size
                group_crossing = 0
                previous = base + (size - 1) * stride
                for member in range(size):
                    current = base + member * stride
                    if previous // lower_group_endpoints != current // lower_group_endpoints:
                        group_crossing += 1
                    previous = current
            else:
                group_total = size - 1
                group_crossing = 0
                previous = base
                for member in range(1, size):
                    current = base + member * stride
                    if previous // lower_group_endpoints != current // lower_group_endpoints:
                        group_crossing += 1
                    previous = current
            crossing_units += group_crossing
            total_units += group_total
            if group_crossing:
                active_groups += 1
            group_fraction = group_crossing / group_total
            maximum_group_fraction = max(maximum_group_fraction, group_fraction)
        return AxisCrossing(
            axis=axis,
            tier_index=tier_index,
            pattern=pattern,
            crossing_fraction=crossing_units / total_units,
            communication_group_count=group_count,
            active_communication_groups=active_groups,
            maximum_group_crossing_fraction=maximum_group_fraction,
        )

    @lru_cache(maxsize=None)
    def leaf_source_loads(self, axis: str, pattern: str) -> tuple[float, ...]:
        """Return normalized injection load by 32-endpoint leaf for one operation."""

        size = self.axis_size(axis)
        stride = self.axis_stride(axis)
        if pattern not in TRAFFIC_PATTERNS:
            raise ValueError("unknown parallel communication pattern")
        leaf_count = (self.total_npus + SCALE_NODES_PER_DOMAIN - 1) // SCALE_NODES_PER_DOMAIN
        loads = [0] * leaf_count
        for base in self._group_bases(axis):
            source_count = size if pattern != "adjacent" else size - 1
            for member in range(source_count):
                source = base + member * stride
                loads[source // SCALE_NODES_PER_DOMAIN] += 1
        total = sum(loads)
        if total == 0:
            return (0.0,) * leaf_count
        return tuple(load / total for load in loads)

    @lru_cache(maxsize=None)
    def axis_resource_loads(
        self, axis: str, tier_index: int, pattern: str
    ) -> AxisResourceLoads:
        """Map crossing traffic onto source-side radix resource groups exactly."""

        size = self.axis_size(axis)
        stride = self.axis_stride(axis)
        if not 1 <= tier_index <= SCALE_MAX_ROUTE_STAGES:
            raise ValueError("tier index is outside the KDLink hierarchy")
        if pattern not in TRAFFIC_PATTERNS:
            raise ValueError("unknown parallel communication pattern")
        lower_group_endpoints = SCALE_NODES_PER_DOMAIN * (8 ** (tier_index - 1))
        resource_group_endpoints = lower_group_endpoints * 8
        resource_group_count = (
            self.total_npus + resource_group_endpoints - 1
        ) // resource_group_endpoints
        loads = [0] * resource_group_count
        if size == 1:
            return AxisResourceLoads(
                axis,
                tier_index,
                pattern,
                resource_group_count,
                0,
                tuple(float(load) for load in loads),
            )

        for base in self._group_bases(axis):
            if pattern == "uniform":
                members = [base + member * stride for member in range(size)]
                lower_counts: dict[int, int] = {}
                for endpoint in members:
                    lower_group = endpoint // lower_group_endpoints
                    lower_counts[lower_group] = lower_counts.get(lower_group, 0) + 1
                for source in members:
                    source_lower = source // lower_group_endpoints
                    crossing_destinations = size - lower_counts[source_lower]
                    loads[source // resource_group_endpoints] += crossing_destinations
            elif pattern == "ring":
                for member in range(size):
                    source = base + member * stride
                    destination = base + ((member + 1) % size) * stride
                    if source // lower_group_endpoints != destination // lower_group_endpoints:
                        loads[source // resource_group_endpoints] += 1
            else:
                for member in range(size - 1):
                    source = base + member * stride
                    destination = base + (member + 1) * stride
                    if source // lower_group_endpoints != destination // lower_group_endpoints:
                        loads[source // resource_group_endpoints] += 1
        total = sum(loads)
        fractions = (
            tuple(load / total for load in loads)
            if total
            else tuple(float(load) for load in loads)
        )
        return AxisResourceLoads(
            axis=axis,
            tier_index=tier_index,
            pattern=pattern,
            resource_group_count=resource_group_count,
            crossing_units=total,
            load_fractions=fractions,
        )
