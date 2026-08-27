"""Compile inference communications into compressed KDLink hierarchy traffic."""

from __future__ import annotations

from dataclasses import dataclass

from .inference_workload import InferenceStageSpec, InferenceWorkload, compile_inference_stages
from .parallel_mapping import ParallelPlacement
from .scale import ScaleDeploymentTopology


@dataclass(frozen=True)
class TrafficDemand:
    """One communication cohort with exact per-tier byte propagation."""

    name: str
    operation: str
    axis: str
    axis_size: int
    repetitions: int
    payload_bytes_per_participant: int
    total_transmitted_bytes: float
    tier_crossing_fractions: tuple[float, ...]
    tier_transmitted_bytes: tuple[float, ...]
    resource_group_load_fractions: tuple[tuple[float, ...], ...]
    latency_rounds_per_repetition: int
    imbalance_factor: float


@dataclass(frozen=True)
class TrafficStage:
    """One inference stage containing concurrently releasable traffic cohorts."""

    name: str
    compute_microseconds: float
    demands: tuple[TrafficDemand, ...]


@dataclass(frozen=True)
class InferenceTrafficGraph:
    """Bounded traffic graph independent of endpoint and token object counts."""

    workload_name: str
    total_npus: int
    physical_card_count: int
    route_tier_count: int
    compute_network_overlap: float
    stages: tuple[TrafficStage, ...]


def _operation_contract(operation: str, axis_size: int) -> tuple[float, str, int]:
    if axis_size < 2:
        raise ValueError("traffic operation requires at least two participants")
    if operation == "all_reduce":
        return 2.0 * (axis_size - 1) / axis_size, "ring", 2 * (axis_size - 1)
    if operation in ("reduce_scatter", "all_gather"):
        return (axis_size - 1) / axis_size, "ring", axis_size - 1
    if operation == "all_to_all_v":
        return (axis_size - 1) / axis_size, "uniform", axis_size - 1
    if operation == "point_to_point":
        return (axis_size - 1) / axis_size, "adjacent", 1
    raise ValueError("unsupported inference communication operation")


def _compile_demand(
    stage: InferenceStageSpec,
    communication,
    placement: ParallelPlacement,
    route_tier_count: int,
) -> TrafficDemand:
    axis_size = placement.axis_size(communication.axis)
    network_factor, pattern, latency_rounds = _operation_contract(
        communication.operation, axis_size
    )
    total_transmitted = (
        communication.payload_bytes_per_participant
        * placement.total_npus
        * network_factor
        * communication.repetitions
    )
    crossings = tuple(
        placement.axis_crossing(communication.axis, tier_index, pattern)
        for tier_index in range(1, route_tier_count + 1)
    )
    fractions = tuple(crossing.crossing_fraction for crossing in crossings)
    resource_loads = tuple(
        placement.axis_resource_loads(communication.axis, tier_index, pattern)
        for tier_index in range(1, route_tier_count + 1)
    )
    return TrafficDemand(
        name=f"{stage.name}:{communication.name}",
        operation=communication.operation,
        axis=communication.axis,
        axis_size=axis_size,
        repetitions=communication.repetitions,
        payload_bytes_per_participant=communication.payload_bytes_per_participant,
        total_transmitted_bytes=total_transmitted,
        tier_crossing_fractions=fractions,
        tier_transmitted_bytes=tuple(total_transmitted * fraction for fraction in fractions),
        resource_group_load_fractions=(
            placement.leaf_source_loads(communication.axis, pattern),
            *(loads.load_fractions for loads in resource_loads),
        ),
        latency_rounds_per_repetition=latency_rounds,
        imbalance_factor=communication.imbalance_factor,
    )


def compile_traffic_graph(workload: InferenceWorkload) -> InferenceTrafficGraph:
    """Compile workload stages without creating per-NPU, per-token, or per-packet objects."""

    workload.validate()
    placement = workload.placement
    topology = ScaleDeploymentTopology(workload.total_npus)
    topology.validate()
    compiled_stages = []
    for stage in compile_inference_stages(workload):
        demands = tuple(
            _compile_demand(stage, communication, placement, topology.inter_domain_route_stages)
            for communication in stage.communications
        )
        compiled_stages.append(TrafficStage(stage.name, stage.compute_microseconds, demands))
    return InferenceTrafficGraph(
        workload_name=workload.name,
        total_npus=workload.total_npus,
        physical_card_count=workload.physical_card_count,
        route_tier_count=topology.inter_domain_route_stages,
        compute_network_overlap=workload.compute_network_overlap,
        stages=tuple(compiled_stages),
    )
