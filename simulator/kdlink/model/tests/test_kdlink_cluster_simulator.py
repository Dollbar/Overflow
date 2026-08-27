import json
from dataclasses import replace
from pathlib import Path

import pytest

from kdlink_model.cluster_simulator import (
    ResourceKey,
    ResourceScheduler,
    evaluate_serving,
    simulate_inference,
)
from kdlink_model.constants import VC_ROLE_ALL_TO_ALL_V, VC_ROLE_COLLECTIVE
from kdlink_model.inference_workload import InferenceWorkload
from kdlink_model.network_resources import NetworkSimulationPolicy, build_hierarchy_resources
from kdlink_model.simulation_metrics import render_simulation_summary, simulation_result_dict


ROOT = Path(__file__).parents[4]


def pipeline_workload() -> InferenceWorkload:
    return InferenceWorkload(
        name="pipeline_cluster",
        total_npus=64,
        npus_per_card=4,
        layers=8,
        hidden_size=1024,
        activation_bytes=2,
        prompt_tokens=16,
        generation_tokens=4,
        batch_size=2,
        microbatch_size=1,
        tensor_parallel=8,
        pipeline_parallel=8,
        expert_parallel=1,
        data_parallel=1,
        prefill_compute_us_per_layer=2.0,
        decode_compute_us_per_layer=1.0,
        compute_network_overlap=0.5,
    )


def remote_data_workload() -> InferenceWorkload:
    return InferenceWorkload(
        name="remote_data",
        total_npus=2048,
        npus_per_card=4,
        layers=1,
        hidden_size=1024,
        activation_bytes=2,
        prompt_tokens=1,
        generation_tokens=8,
        batch_size=1,
        microbatch_size=1,
        tensor_parallel=1,
        pipeline_parallel=1,
        expert_parallel=1,
        data_parallel=2048,
        remote_kv_fraction=1.0,
        remote_kv_bytes_per_token=1048576,
        remote_kv_axis="data",
    )


def test_cluster_simulator_accounts_for_leaf_and_interdomain_resources() -> None:
    result = simulate_inference(pipeline_workload())
    assert result.evidence_level == "FUNCTIONAL_SIM"
    assert result.capacity_evidence_level == "ANALYTICAL"
    assert [metric.tier_index for metric in result.tier_metrics] == [0, 1]
    assert result.tier_metrics[0].total_transmitted_bytes > (
        result.tier_metrics[1].total_transmitted_bytes
    )
    assert result.ttft_microseconds > 0.0
    assert result.decode_microseconds_per_token > 0.0
    assert result.generated_tokens_per_second > 0.0
    assert result.generated_tokens_per_second == pytest.approx(
        result.tokens_per_second_per_data_parallel_replica
    )
    assert result.cluster_generated_tokens_per_second == pytest.approx(
        result.generated_tokens_per_second * result.data_parallel_replicas
    )


def test_balanced_oversubscription_increases_high_tier_completion_time() -> None:
    workload = remote_data_workload()
    nonblocking = simulate_inference(
        workload, NetworkSimulationPolicy(profile="nonblocking")
    )
    balanced = simulate_inference(
        workload, NetworkSimulationPolicy(profile="balanced")
    )
    assert nonblocking.tier_metrics[-1].capacity_gbyte_s_per_group == pytest.approx(
        2.0 * balanced.tier_metrics[-1].capacity_gbyte_s_per_group
    )
    assert balanced.total_microseconds > nonblocking.total_microseconds


def test_slice_and_plane_degradation_reduce_service_capacity() -> None:
    workload = remote_data_workload()
    baseline = simulate_inference(
        workload, NetworkSimulationPolicy(active_planes=8, active_slices_per_port=1)
    )
    bonded = simulate_inference(
        workload, NetworkSimulationPolicy(active_planes=8, active_slices_per_port=2)
    )
    plane_degraded = simulate_inference(
        workload, NetworkSimulationPolicy(active_planes=7, active_slices_per_port=1)
    )
    assert bonded.tier_metrics[-1].capacity_gbyte_s_per_group == pytest.approx(
        2.0 * baseline.tier_metrics[-1].capacity_gbyte_s_per_group
    )
    assert bonded.total_microseconds < baseline.total_microseconds
    assert plane_degraded.total_microseconds > baseline.total_microseconds


def test_per_tier_slice_policy_upgrades_only_the_selected_local_tier() -> None:
    policy = NetworkSimulationPolicy(
        active_slices_by_tier=(2, 1, 1, 1, 1, 1)
    )
    resources = build_hierarchy_resources(2048, policy)
    assert resources[0].active_slices_per_port == 2
    assert resources[0].capacity_gbyte_s_all_planes_per_group == pytest.approx(
        2.0
        * build_hierarchy_resources(2048, NetworkSimulationPolicy())[0]
        .capacity_gbyte_s_all_planes_per_group
    )
    assert all(resource.active_slices_per_port == 1 for resource in resources[1:])


def test_local_slice_upgrade_improves_local_workload_but_not_remote_bottleneck() -> None:
    local = InferenceWorkload(
        name="local_tensor",
        total_npus=32,
        npus_per_card=4,
        layers=1,
        hidden_size=4096,
        activation_bytes=2,
        prompt_tokens=256,
        generation_tokens=8,
        batch_size=8,
        microbatch_size=1,
        tensor_parallel=32,
        pipeline_parallel=1,
        expert_parallel=1,
        data_parallel=1,
    )
    baseline = NetworkSimulationPolicy()
    local_bonded = NetworkSimulationPolicy(
        active_slices_by_tier=(2, 1, 1, 1, 1, 1)
    )
    assert simulate_inference(local, local_bonded).total_microseconds < simulate_inference(
        local, baseline
    ).total_microseconds
    assert simulate_inference(
        remote_data_workload(), local_bonded
    ).total_microseconds == pytest.approx(
        simulate_inference(remote_data_workload(), baseline).total_microseconds
    )


def test_per_tier_oversubscription_changes_only_selected_tier_capacity() -> None:
    baseline = build_hierarchy_resources(2048, NetworkSimulationPolicy())
    modified = build_hierarchy_resources(
        2048,
        NetworkSimulationPolicy(oversubscription_by_tier=(1.0, 2.0, 1.0, 1.0, 1.0)),
    )
    assert modified[1].capacity_gbyte_s_all_planes_per_group == pytest.approx(
        baseline[1].capacity_gbyte_s_all_planes_per_group
    )
    assert modified[2].capacity_gbyte_s_all_planes_per_group == pytest.approx(
        baseline[2].capacity_gbyte_s_all_planes_per_group / 2.0
    )


def test_resource_scheduler_calibrates_service_and_separates_group_direction() -> None:
    scheduler = ResourceScheduler()
    key = ResourceKey(1, 0, 0, "up")
    start, finish, queue = scheduler.schedule(
        key, VC_ROLE_COLLECTIVE, 0.0, 64_000.0, 64.0
    )
    assert (start, finish, queue) == pytest.approx((0.0, 1.0, 0.0))
    different_group = scheduler.schedule(
        ResourceKey(1, 1, 0, "up"),
        VC_ROLE_COLLECTIVE,
        0.0,
        64_000.0,
        64.0,
    )
    different_direction = scheduler.schedule(
        ResourceKey(1, 0, 0, "down"),
        VC_ROLE_COLLECTIVE,
        0.0,
        64_000.0,
        64.0,
    )
    assert different_group == pytest.approx((0.0, 1.0, 0.0))
    assert different_direction == pytest.approx((0.0, 1.0, 0.0))


def test_logical_vcs_share_the_same_physical_resource() -> None:
    scheduler = ResourceScheduler()
    key = ResourceKey(0, 0, 0, "up")
    scheduler.schedule(key, VC_ROLE_COLLECTIVE, 0.0, 64_000.0, 64.0)
    start, finish, queue = scheduler.schedule(
        key, VC_ROLE_ALL_TO_ALL_V, 0.0, 64_000.0, 64.0
    )
    assert (start, finish, queue) == pytest.approx((1.0, 2.0, 1.0))
    assert scheduler.vc_transmitted_bytes[(key, VC_ROLE_COLLECTIVE)] == 64_000.0
    assert scheduler.vc_transmitted_bytes[(key, VC_ROLE_ALL_TO_ALL_V)] == 64_000.0


def test_burst_serving_reports_tail_queue_and_spaced_arrivals_do_not() -> None:
    workload = remote_data_workload()
    single = simulate_inference(workload)
    burst = evaluate_serving(workload, request_count=8, arrival_interval_microseconds=0.0)
    spaced = evaluate_serving(
        workload,
        request_count=8,
        arrival_interval_microseconds=single.total_microseconds * 2.0,
    )
    assert burst.scheduling_model == "FCFS_CLUSTER_BATCH"
    assert burst.latency_p99_microseconds > burst.latency_p50_microseconds
    assert burst.queue_p95_microseconds > 0.0
    assert any(metric.overloaded for metric in burst.serving_tiers)
    assert all(
        metric.offered_load is None
        for metric in burst.serving_tiers
        if metric.maximum_queue_microseconds > 0.0
    )
    assert spaced.queue_p99_microseconds == pytest.approx(0.0)


def test_single_serving_request_matches_single_run_latency_and_throughput() -> None:
    workload = pipeline_workload()
    single = simulate_inference(workload)
    serving = evaluate_serving(workload, request_count=1)
    assert serving.latency_p50_microseconds == pytest.approx(single.total_microseconds)
    assert serving.ttft_p50_microseconds == pytest.approx(single.ttft_microseconds)
    assert serving.tokens_per_second_per_data_parallel_replica == pytest.approx(
        single.tokens_per_second_per_data_parallel_replica
    )


def test_moe_hot_group_skew_increases_peak_without_creating_bytes() -> None:
    values = json.loads(
        (ROOT / "simulator" / "kdlink" / "config" / "inference_serving.json").read_text()
    )
    workload = InferenceWorkload.from_dict(values["workload"])
    policy = NetworkSimulationPolicy.from_dict(values["network"])
    uniform = simulate_inference(replace(workload, moe_imbalance_factor=1.0), policy)
    skewed = simulate_inference(workload, policy)
    assert skewed.tier_metrics[1].peak_resource_service_microseconds > (
        uniform.tier_metrics[1].peak_resource_service_microseconds
    )
    assert skewed.tier_metrics[1].total_transmitted_bytes == pytest.approx(
        uniform.tier_metrics[1].total_transmitted_bytes
    )


@pytest.mark.parametrize(
    "policy",
    (
        NetworkSimulationPolicy(active_planes_by_tier=(8, 8)),
        NetworkSimulationPolicy(active_slices_by_tier=(1, 1, 1, 1, 1, 3)),
        NetworkSimulationPolicy(oversubscription_by_tier=(1.0, 1.0)),
    ),
)
def test_invalid_per_tier_policy_vectors_are_rejected(policy) -> None:
    with pytest.raises(ValueError):
        policy.validate()


def test_resources_compress_one_million_endpoints_into_six_resource_classes() -> None:
    resources = build_hierarchy_resources(1048576, NetworkSimulationPolicy())
    assert [resource.group_count for resource in resources] == [32768, 4096, 512, 64, 8, 1]
    assert sum(resource.group_count for resource in resources) == 37449
    assert len(resources) == 6


def test_result_serialization_is_stable_and_labels_evidence() -> None:
    result = simulate_inference(pipeline_workload())
    values = simulation_result_dict(result)
    summary = render_simulation_summary(result)
    assert values["capacity_evidence_level"] == "ANALYTICAL"
    assert values["stages"][0]["name"] == "prefill"
    assert "bottleneck_tier=" in summary
    assert "capacity_evidence=ANALYTICAL" in summary


def test_machine_contract_declares_compressed_inference_evidence_boundary() -> None:
    values = json.loads(
        (ROOT / "simulator" / "kdlink" / "config" / "million_scale.json").read_text()
    )["cluster_inference_simulation_contract"]
    assert values["evidence_level"] == "FUNCTIONAL_SIM"
    assert values["capacity_evidence_level"] == "ANALYTICAL"
    assert values["resource_classes"] == [
        "leaf",
        "tier_1",
        "tier_2",
        "tier_3",
        "tier_4",
        "tier_5",
    ]
    assert values["default_current_baseline_active_slices"] == 1
    assert values["leaf_reference_rtt_cycles"] == 8
    assert values["resource_schedule_key"] == [
        "tier",
        "group",
        "plane",
        "direction",
    ]
    assert values["serving_schedule"] == "FCFS_CLUSTER_BATCH"
    assert values["throughput_scopes"] == [
        "per_data_parallel_replica",
        "cluster_total",
    ]
    assert values["vc_priority_arbitration_modelled"] is False
    assert values["not_request_stage_interleaved"] is True
    assert values["not_packet_or_cycle_accurate_at_full_scale"] is True
