"""Stable serialization and text reporting for KDLink cluster simulation results."""

from __future__ import annotations

from dataclasses import asdict

from .cluster_simulator import ClusterSimulationResult, ServingEvaluationResult


def simulation_result_dict(result: ClusterSimulationResult) -> dict:
    """Return a machine-readable result without host or generated-file paths."""

    return asdict(result)


def serving_result_dict(result: ServingEvaluationResult) -> dict:
    """Return stable machine-readable serving metrics."""

    return asdict(result)


def render_simulation_summary(result: ClusterSimulationResult) -> str:
    """Render a compact human-readable capacity and bottleneck summary."""

    lines = [
        f"workload={result.workload_name}",
        (
            f"population={result.total_npus} NPUs, "
            f"cards={result.physical_card_count}, profile={result.network_profile}, "
            f"planes_by_tier={result.active_planes_by_tier}, "
            f"slices_by_tier={result.active_slices_by_tier}"
        ),
        (
            f"total_us={result.total_microseconds:.3f}, "
            f"ttft_us={result.ttft_microseconds:.3f}, "
            f"decode_us/token={result.decode_microseconds_per_token:.3f}, "
            "tokens/s/DP-replica="
            f"{result.tokens_per_second_per_data_parallel_replica:.3f}, "
            f"cluster_tokens/s={result.cluster_generated_tokens_per_second:.3f}, "
            f"max_queue_us={result.maximum_queue_microseconds:.3f}"
        ),
        f"bottleneck_tier={result.bottleneck_tier}",
        "tier groups planes slices capacity_GBps/group transmitted_GB mean_util "
        "peak_resource_util overloaded",
    ]
    for metric in result.tier_metrics:
        lines.append(
            f"{metric.tier_index:>4} "
            f"{metric.group_count:>6} "
            f"{metric.active_planes:>6} "
            f"{metric.active_slices_per_port:>6} "
            f"{metric.capacity_gbyte_s_per_group:>20.3f} "
            f"{metric.total_transmitted_bytes / 1.0e9:>14.6f} "
            f"{metric.mean_utilization:>9.6f} "
            f"{metric.peak_resource_utilization:>18.6f} "
            f"{str(metric.overloaded):>10}"
        )
    lines.append(
        f"evidence={result.evidence_level}, capacity_evidence={result.capacity_evidence_level}"
    )
    return "\n".join(lines)


def render_serving_summary(result: ServingEvaluationResult) -> str:
    """Render serving throughput, tail latency, queueing, and offered load."""

    lines = [
        f"workload={result.workload_name}",
        (
            f"requests={result.request_count}, "
            f"arrival_interval_us={result.arrival_interval_microseconds:.3f}, "
            f"scheduling={result.scheduling_model}"
        ),
        (
            f"latency_us[p50,p95,p99]=[{result.latency_p50_microseconds:.3f},"
            f"{result.latency_p95_microseconds:.3f},"
            f"{result.latency_p99_microseconds:.3f}]"
        ),
        (
            f"ttft_us[p50,p95,p99]=[{result.ttft_p50_microseconds:.3f},"
            f"{result.ttft_p95_microseconds:.3f},"
            f"{result.ttft_p99_microseconds:.3f}]"
        ),
        (
            f"queue_us[p50,p95,p99]=[{result.queue_p50_microseconds:.3f},"
            f"{result.queue_p95_microseconds:.3f},"
            f"{result.queue_p99_microseconds:.3f}]"
        ),
        (
            "tokens/s/DP-replica="
            f"{result.tokens_per_second_per_data_parallel_replica:.3f}, "
            f"cluster_tokens/s={result.cluster_generated_tokens_per_second:.3f}"
        ),
        "tier offered_load mean_util peak_resource_util max_queue_us overloaded",
    ]
    for metric in result.serving_tiers:
        offered_load = (
            "burst"
            if metric.offered_load is None
            else f"{metric.offered_load:.6f}"
        )
        lines.append(
            f"{metric.tier_index:>4} "
            f"{offered_load:>12} "
            f"{metric.mean_utilization:>9.6f} "
            f"{metric.peak_resource_utilization:>18.6f} "
            f"{metric.maximum_queue_microseconds:>12.3f} "
            f"{str(metric.overloaded):>10}"
        )
    lines.append(
        f"evidence={result.evidence_level}, capacity_evidence={result.capacity_evidence_level}"
    )
    return "\n".join(lines)
