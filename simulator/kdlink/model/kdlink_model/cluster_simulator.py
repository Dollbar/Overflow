"""Sparse hierarchical event simulation for large KDLink inference clusters."""

from __future__ import annotations

from dataclasses import dataclass, field
from math import ceil

from .constants import (
    VC_ROLE_ALL_TO_ALL_V,
    VC_ROLE_COLLECTIVE,
    VC_ROLE_POINT_TO_POINT,
)
from .inference_workload import InferenceWorkload
from .network_resources import (
    HierarchyResource,
    NetworkSimulationPolicy,
    build_hierarchy_resources,
)
from .traffic_graph import InferenceTrafficGraph, TrafficDemand, compile_traffic_graph


@dataclass(frozen=True)
class ResourceKey:
    """One independently scheduled full-duplex hierarchy resource."""

    tier_index: int
    group_index: int
    plane_index: int
    direction: str


@dataclass
class ResourceScheduler:
    """Sparse work-conserving FCFS scheduler shared by all logical VCs."""

    available_microseconds: dict[ResourceKey, float] = field(default_factory=dict)
    busy_microseconds: dict[ResourceKey, float] = field(default_factory=dict)
    transmitted_bytes: dict[ResourceKey, float] = field(default_factory=dict)
    maximum_queue_microseconds: dict[ResourceKey, float] = field(default_factory=dict)
    vc_transmitted_bytes: dict[tuple[ResourceKey, int], float] = field(
        default_factory=dict
    )

    def schedule(
        self,
        key: ResourceKey,
        virtual_channel: int,
        release_microseconds: float,
        transmitted_bytes: float,
        capacity_gbyte_s: float,
    ) -> tuple[float, float, float]:
        """Reserve one physical resource and return start, finish, and queue time."""

        if transmitted_bytes < 0.0 or capacity_gbyte_s <= 0.0:
            raise ValueError("resource service request is invalid")
        start = max(release_microseconds, self.available_microseconds.get(key, 0.0))
        service = transmitted_bytes / (capacity_gbyte_s * 1.0e9) * 1.0e6
        finish = start + service
        queue = start - release_microseconds
        self.available_microseconds[key] = finish
        self.busy_microseconds[key] = self.busy_microseconds.get(key, 0.0) + service
        self.transmitted_bytes[key] = (
            self.transmitted_bytes.get(key, 0.0) + transmitted_bytes
        )
        self.maximum_queue_microseconds[key] = max(
            queue, self.maximum_queue_microseconds.get(key, 0.0)
        )
        vc_key = (key, virtual_channel)
        self.vc_transmitted_bytes[vc_key] = (
            self.vc_transmitted_bytes.get(vc_key, 0.0) + transmitted_bytes
        )
        return start, finish, queue


@dataclass(frozen=True)
class DemandTierTiming:
    """Service and latency contribution at one hierarchy tier."""

    tier_index: int
    virtual_channel: int
    active_resource_groups: int
    active_planes: int
    transmitted_bytes: float
    average_group_bytes: float
    peak_group_bytes: float
    capacity_gbyte_s_per_group: float
    service_microseconds: float
    maximum_queue_microseconds: float
    protocol_latency_microseconds: float
    completion_microseconds: float


@dataclass(frozen=True)
class DemandSimulation:
    """Timing result for one compressed communication cohort."""

    name: str
    operation: str
    axis: str
    release_microseconds: float
    start_microseconds: float
    finish_microseconds: float
    queue_microseconds: float
    bottleneck_tier: int
    tier_timings: tuple[DemandTierTiming, ...]


@dataclass(frozen=True)
class StageSimulation:
    """Compute/network overlap and communication timing for one inference stage."""

    name: str
    start_microseconds: float
    finish_microseconds: float
    compute_microseconds: float
    network_microseconds: float
    overlapped_microseconds: float
    demands: tuple[DemandSimulation, ...]


@dataclass(frozen=True)
class TierSimulationMetric:
    """Physical-resource utilization and byte accounting for one hierarchy tier."""

    tier_index: int
    group_count: int
    active_planes: int
    active_slices_per_port: int
    capacity_gbyte_s_per_group: float
    total_transmitted_bytes: float
    average_resource_service_microseconds: float
    peak_resource_service_microseconds: float
    maximum_queue_microseconds: float
    mean_utilization: float
    peak_resource_utilization: float
    overloaded: bool

    @property
    def average_group_service_microseconds(self) -> float:
        """Compatibility alias for the earlier aggregate field name."""

        return self.average_resource_service_microseconds

    @property
    def peak_group_service_microseconds(self) -> float:
        """Compatibility alias for reports created by the initial simulator."""

        return self.peak_resource_service_microseconds

    @property
    def peak_group_utilization(self) -> float:
        """Compatibility alias for reports created by the initial simulator."""

        return self.peak_resource_utilization


@dataclass(frozen=True)
class ClusterSimulationResult:
    """End-to-end analytical-capacity functional simulation result."""

    evidence_level: str
    capacity_evidence_level: str
    workload_name: str
    total_npus: int
    physical_card_count: int
    data_parallel_replicas: int
    network_profile: str
    active_planes: int
    active_slices_per_port: int
    active_planes_by_tier: tuple[int, ...]
    active_slices_by_tier: tuple[int, ...]
    total_microseconds: float
    ttft_microseconds: float
    decode_microseconds_per_token: float
    generated_tokens_per_second: float
    tokens_per_second_per_data_parallel_replica: float
    cluster_generated_tokens_per_second: float
    maximum_queue_microseconds: float
    bottleneck_tier: int
    stages: tuple[StageSimulation, ...]
    tier_metrics: tuple[TierSimulationMetric, ...]


@dataclass(frozen=True)
class ServingRequestResult:
    """Latency observations for one FCFS cluster-batch request."""

    request_index: int
    arrival_microseconds: float
    finish_microseconds: float
    latency_microseconds: float
    ttft_microseconds: float
    maximum_queue_microseconds: float


@dataclass(frozen=True)
class ServingTierMetric:
    """Offered load and measured resource utilization for a serving run."""

    tier_index: int
    offered_load: float | None
    mean_utilization: float
    peak_resource_utilization: float
    maximum_queue_microseconds: float
    overloaded: bool


@dataclass(frozen=True)
class ServingEvaluationResult:
    """Tail-latency and throughput result for deterministic request arrivals."""

    evidence_level: str
    capacity_evidence_level: str
    scheduling_model: str
    workload_name: str
    request_count: int
    arrival_interval_microseconds: float
    makespan_microseconds: float
    latency_p50_microseconds: float
    latency_p95_microseconds: float
    latency_p99_microseconds: float
    ttft_p50_microseconds: float
    ttft_p95_microseconds: float
    ttft_p99_microseconds: float
    queue_p50_microseconds: float
    queue_p95_microseconds: float
    queue_p99_microseconds: float
    tokens_per_second_per_data_parallel_replica: float
    cluster_generated_tokens_per_second: float
    requests: tuple[ServingRequestResult, ...]
    tier_metrics: tuple[TierSimulationMetric, ...]
    serving_tiers: tuple[ServingTierMetric, ...]


def _tier_bytes(demand: TrafficDemand, tier_index: int) -> float:
    if tier_index == 0:
        return demand.total_transmitted_bytes
    return demand.tier_transmitted_bytes[tier_index - 1]


def _virtual_channel(operation: str) -> int:
    if operation == "all_to_all_v":
        return VC_ROLE_ALL_TO_ALL_V
    if operation == "point_to_point":
        return VC_ROLE_POINT_TO_POINT
    return VC_ROLE_COLLECTIVE


def _skew_load_fractions(
    fractions: tuple[float, ...], imbalance_factor: float
) -> tuple[float, ...]:
    """Apply a bounded hot-group skew while preserving total traffic."""

    total = sum(fractions)
    if total <= 0.0 or imbalance_factor == 1.0:
        return fractions
    hottest = max(range(len(fractions)), key=fractions.__getitem__)
    hot_load = min(total, fractions[hottest] * imbalance_factor)
    other_total = total - fractions[hottest]
    if other_total <= 0.0:
        return fractions
    remainder = total - hot_load
    return tuple(
        hot_load
        if index == hottest
        else fraction * remainder / other_total
        for index, fraction in enumerate(fractions)
    )


def _simulate_demand(
    demand: TrafficDemand,
    release_microseconds: float,
    resources: tuple[HierarchyResource, ...],
    scheduler: ResourceScheduler,
) -> DemandSimulation:
    virtual_channel = _virtual_channel(demand.operation)
    tier_timings = []
    demand_start = release_microseconds
    demand_finish = release_microseconds
    demand_queue = 0.0
    for resource in resources:
        transmitted = _tier_bytes(demand, resource.tier_index)
        if transmitted <= 0.0:
            continue
        fractions = demand.resource_group_load_fractions[resource.tier_index]
        if len(fractions) != resource.group_count:
            raise ValueError("traffic group loads do not match hierarchy resources")
        fractions = _skew_load_fractions(fractions, demand.imbalance_factor)
        active_groups = sum(fraction > 0.0 for fraction in fractions)
        average_group_bytes = transmitted / active_groups
        peak_group_bytes = transmitted * max(fractions)
        capacity_per_plane = resource.capacity_gbyte_s_per_plane_per_group
        tier_finish = release_microseconds
        tier_start = release_microseconds
        tier_queue = 0.0
        for group_index, fraction in enumerate(fractions):
            group_bytes = transmitted * fraction
            if group_bytes <= 0.0:
                continue
            plane_bytes = group_bytes / resource.active_planes
            for plane_index in range(resource.active_planes):
                for direction in ("up", "down"):
                    start, finish, queue = scheduler.schedule(
                        ResourceKey(
                            resource.tier_index,
                            group_index,
                            plane_index,
                            direction,
                        ),
                        virtual_channel,
                        release_microseconds,
                        plane_bytes,
                        capacity_per_plane,
                    )
                    tier_start = max(tier_start, start)
                    tier_finish = max(tier_finish, finish)
                    tier_queue = max(tier_queue, queue)
        protocol_latency = (
            resource.round_trip_microseconds
            * demand.latency_rounds_per_repetition
            * demand.repetitions
        )
        service = (
            peak_group_bytes
            / (resource.capacity_gbyte_s_all_planes_per_group * 1.0e9)
            * 1.0e6
        )
        completion = tier_finish - release_microseconds + protocol_latency
        tier_timings.append(
            DemandTierTiming(
                tier_index=resource.tier_index,
                virtual_channel=virtual_channel,
                active_resource_groups=active_groups,
                active_planes=resource.active_planes,
                transmitted_bytes=transmitted,
                average_group_bytes=average_group_bytes,
                peak_group_bytes=peak_group_bytes,
                capacity_gbyte_s_per_group=(
                    resource.capacity_gbyte_s_all_planes_per_group
                ),
                service_microseconds=service,
                maximum_queue_microseconds=tier_queue,
                protocol_latency_microseconds=protocol_latency,
                completion_microseconds=completion,
            )
        )
        demand_start = max(demand_start, tier_start)
        demand_finish = max(demand_finish, tier_finish + protocol_latency)
        demand_queue = max(demand_queue, tier_queue)
    if not tier_timings:
        raise ValueError("traffic demand has no active KDLink resource")
    bottleneck = max(tier_timings, key=lambda timing: timing.completion_microseconds)
    return DemandSimulation(
        name=demand.name,
        operation=demand.operation,
        axis=demand.axis,
        release_microseconds=release_microseconds,
        start_microseconds=demand_start,
        finish_microseconds=demand_finish,
        queue_microseconds=demand_queue,
        bottleneck_tier=bottleneck.tier_index,
        tier_timings=tuple(tier_timings),
    )


def _simulate_request(
    graph: InferenceTrafficGraph,
    arrival_microseconds: float,
    resources: tuple[HierarchyResource, ...],
    scheduler: ResourceScheduler,
) -> tuple[tuple[StageSimulation, ...], float, float, float]:
    stage_results = []
    current_time = arrival_microseconds
    maximum_queue = 0.0
    for stage in graph.stages:
        stage_start = current_time
        network_cursor = stage_start
        demand_results = []
        for demand in stage.demands:
            result = _simulate_demand(demand, network_cursor, resources, scheduler)
            demand_results.append(result)
            network_cursor = result.finish_microseconds
            maximum_queue = max(maximum_queue, result.queue_microseconds)
        network_time = network_cursor - stage_start
        overlapped = graph.compute_network_overlap * min(
            stage.compute_microseconds, network_time
        )
        stage_elapsed = stage.compute_microseconds + network_time - overlapped
        stage_finish = stage_start + stage_elapsed
        current_time = stage_finish
        stage_results.append(
            StageSimulation(
                name=stage.name,
                start_microseconds=stage_start,
                finish_microseconds=stage_finish,
                compute_microseconds=stage.compute_microseconds,
                network_microseconds=network_time,
                overlapped_microseconds=overlapped,
                demands=tuple(demand_results),
            )
        )
    prefill_finish = next(
        (
            stage.finish_microseconds
            for stage in stage_results
            if stage.name == "prefill"
        ),
        arrival_microseconds,
    )
    return tuple(stage_results), current_time, prefill_finish, maximum_queue


def _summarize_tiers(
    resources: tuple[HierarchyResource, ...],
    scheduler: ResourceScheduler,
    observation_microseconds: float,
    logical_bytes_by_tier: tuple[float, ...],
) -> tuple[TierSimulationMetric, ...]:
    denominator = observation_microseconds if observation_microseconds > 0.0 else 1.0
    metrics = []
    for resource in resources:
        busy = [
            value
            for key, value in scheduler.busy_microseconds.items()
            if key.tier_index == resource.tier_index
        ]
        queues = [
            value
            for key, value in scheduler.maximum_queue_microseconds.items()
            if key.tier_index == resource.tier_index
        ]
        physical_resource_count = (
            resource.group_count * resource.active_planes * 2
        )
        total_busy = sum(busy)
        average_service = total_busy / physical_resource_count
        peak_service = max(busy, default=0.0)
        mean_utilization = average_service / denominator
        peak_utilization = peak_service / denominator
        metrics.append(
            TierSimulationMetric(
                tier_index=resource.tier_index,
                group_count=resource.group_count,
                active_planes=resource.active_planes,
                active_slices_per_port=resource.active_slices_per_port,
                capacity_gbyte_s_per_group=(
                    resource.capacity_gbyte_s_all_planes_per_group
                ),
                total_transmitted_bytes=logical_bytes_by_tier[resource.tier_index],
                average_resource_service_microseconds=average_service,
                peak_resource_service_microseconds=peak_service,
                maximum_queue_microseconds=max(queues, default=0.0),
                mean_utilization=mean_utilization,
                peak_resource_utilization=peak_utilization,
                overloaded=peak_utilization > 1.0,
            )
        )
    return tuple(metrics)


def _logical_bytes_for_requests(
    graph: InferenceTrafficGraph, request_count: int
) -> tuple[float, ...]:
    logical = []
    for tier_index in range(graph.route_tier_count + 1):
        logical.append(
            request_count
            * sum(
                _tier_bytes(demand, tier_index)
                for stage in graph.stages
                for demand in stage.demands
            )
        )
    return tuple(logical)


def simulate_traffic_graph(
    graph: InferenceTrafficGraph,
    workload: InferenceWorkload,
    policy: NetworkSimulationPolicy,
) -> ClusterSimulationResult:
    """Simulate one cluster batch on independent hierarchy resources."""

    workload.validate()
    policy.validate()
    if graph.total_npus != workload.total_npus:
        raise ValueError("traffic graph and workload populations do not match")
    resources = build_hierarchy_resources(graph.total_npus, policy)
    scheduler = ResourceScheduler()
    stages, total_time, prefill_finish, maximum_queue = _simulate_request(
        graph, 0.0, resources, scheduler
    )
    tier_metrics = _summarize_tiers(
        resources,
        scheduler,
        total_time,
        _logical_bytes_for_requests(graph, 1),
    )
    active_metrics = [
        metric for metric in tier_metrics if metric.total_transmitted_bytes > 0.0
    ]
    bottleneck_tier = (
        max(active_metrics, key=lambda metric: metric.peak_resource_utilization).tier_index
        if active_metrics
        else 0
    )
    decode_duration = max(0.0, total_time - prefill_finish)
    generated_tokens = workload.batch_size * workload.generation_tokens
    per_replica = generated_tokens / (total_time / 1.0e6) if total_time else 0.0
    return ClusterSimulationResult(
        evidence_level="FUNCTIONAL_SIM",
        capacity_evidence_level="ANALYTICAL",
        workload_name=graph.workload_name,
        total_npus=graph.total_npus,
        physical_card_count=graph.physical_card_count,
        data_parallel_replicas=workload.data_parallel,
        network_profile=policy.profile,
        active_planes=policy.active_planes,
        active_slices_per_port=policy.active_slices_per_port,
        active_planes_by_tier=tuple(
            policy.planes_for_tier(tier_index) for tier_index in range(len(resources))
        ),
        active_slices_by_tier=tuple(
            policy.slices_for_tier(tier_index) for tier_index in range(len(resources))
        ),
        total_microseconds=total_time,
        ttft_microseconds=prefill_finish,
        decode_microseconds_per_token=(
            decode_duration / workload.generation_tokens
            if workload.generation_tokens
            else 0.0
        ),
        generated_tokens_per_second=per_replica,
        tokens_per_second_per_data_parallel_replica=per_replica,
        cluster_generated_tokens_per_second=per_replica * workload.data_parallel,
        maximum_queue_microseconds=maximum_queue,
        bottleneck_tier=bottleneck_tier,
        stages=stages,
        tier_metrics=tier_metrics,
    )


def _percentile(values: tuple[float, ...], percentile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(1, ceil(percentile * len(ordered)))
    return ordered[rank - 1]


def evaluate_serving(
    workload: InferenceWorkload,
    policy: NetworkSimulationPolicy | None = None,
    request_count: int = 32,
    arrival_interval_microseconds: float = 0.0,
) -> ServingEvaluationResult:
    """Evaluate deterministic FCFS cluster-batch arrivals on shared resources."""

    if request_count < 1:
        raise ValueError("serving request count must be positive")
    if arrival_interval_microseconds < 0.0:
        raise ValueError("arrival interval must be nonnegative")
    selected_policy = NetworkSimulationPolicy() if policy is None else policy
    graph = compile_traffic_graph(workload)
    resources = build_hierarchy_resources(graph.total_npus, selected_policy)
    scheduler = ResourceScheduler()
    requests = []
    for request_index in range(request_count):
        arrival = request_index * arrival_interval_microseconds
        _, finish, prefill_finish, maximum_queue = _simulate_request(
            graph, arrival, resources, scheduler
        )
        requests.append(
            ServingRequestResult(
                request_index=request_index,
                arrival_microseconds=arrival,
                finish_microseconds=finish,
                latency_microseconds=finish - arrival,
                ttft_microseconds=prefill_finish - arrival,
                maximum_queue_microseconds=maximum_queue,
            )
        )
    makespan = max(request.finish_microseconds for request in requests)
    tier_metrics = _summarize_tiers(
        resources,
        scheduler,
        makespan,
        _logical_bytes_for_requests(graph, request_count),
    )
    arrival_window = arrival_interval_microseconds * request_count
    serving_tiers = []
    for metric in tier_metrics:
        offered_load = (
            metric.peak_resource_service_microseconds / arrival_window
            if arrival_window > 0.0
            else None
        )
        serving_tiers.append(
                ServingTierMetric(
                    tier_index=metric.tier_index,
                offered_load=offered_load,
                mean_utilization=metric.mean_utilization,
                peak_resource_utilization=metric.peak_resource_utilization,
                maximum_queue_microseconds=metric.maximum_queue_microseconds,
                overloaded=(
                    offered_load > 1.0
                    if offered_load is not None
                    else metric.peak_resource_service_microseconds > 0.0
                ),
            )
        )
    latencies = tuple(request.latency_microseconds for request in requests)
    ttfts = tuple(request.ttft_microseconds for request in requests)
    queues = tuple(request.maximum_queue_microseconds for request in requests)
    generated_tokens = (
        request_count * workload.batch_size * workload.generation_tokens
    )
    per_replica = generated_tokens / (makespan / 1.0e6) if makespan else 0.0
    return ServingEvaluationResult(
        evidence_level="FUNCTIONAL_SIM",
        capacity_evidence_level="ANALYTICAL",
        scheduling_model="FCFS_CLUSTER_BATCH",
        workload_name=workload.name,
        request_count=request_count,
        arrival_interval_microseconds=arrival_interval_microseconds,
        makespan_microseconds=makespan,
        latency_p50_microseconds=_percentile(latencies, 0.50),
        latency_p95_microseconds=_percentile(latencies, 0.95),
        latency_p99_microseconds=_percentile(latencies, 0.99),
        ttft_p50_microseconds=_percentile(ttfts, 0.50),
        ttft_p95_microseconds=_percentile(ttfts, 0.95),
        ttft_p99_microseconds=_percentile(ttfts, 0.99),
        queue_p50_microseconds=_percentile(queues, 0.50),
        queue_p95_microseconds=_percentile(queues, 0.95),
        queue_p99_microseconds=_percentile(queues, 0.99),
        tokens_per_second_per_data_parallel_replica=per_replica,
        cluster_generated_tokens_per_second=per_replica * workload.data_parallel,
        requests=tuple(requests),
        tier_metrics=tier_metrics,
        serving_tiers=tuple(serving_tiers),
    )


def simulate_inference(
    workload: InferenceWorkload,
    policy: NetworkSimulationPolicy | None = None,
) -> ClusterSimulationResult:
    """Compile and simulate one workload using the selected capacity profile."""

    selected_policy = NetworkSimulationPolicy() if policy is None else policy
    return simulate_traffic_graph(
        compile_traffic_graph(workload), workload, selected_policy
    )
