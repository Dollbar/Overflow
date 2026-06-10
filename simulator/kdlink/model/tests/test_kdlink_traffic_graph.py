import json
from pathlib import Path

import pytest

from kdlink_model.inference_workload import InferenceWorkload
from kdlink_model.traffic_graph import compile_traffic_graph


ROOT = Path(__file__).parents[4]


def test_local_tensor_and_cross_leaf_pipeline_bytes_propagate_separately() -> None:
    workload = InferenceWorkload(
        name="propagation",
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
    )
    graph = compile_traffic_graph(workload)
    assert graph.route_tier_count == 1
    prefill_tensor, prefill_pipeline = graph.stages[0].demands
    assert prefill_tensor.tier_crossing_fractions == (0.0,)
    assert prefill_pipeline.tier_crossing_fractions == (pytest.approx(1.0 / 7.0),)
    assert prefill_pipeline.tier_transmitted_bytes[0] == pytest.approx(
        prefill_pipeline.total_transmitted_bytes / 7.0
    )
    assert len(prefill_pipeline.resource_group_load_fractions[0]) == 2
    assert sum(prefill_pipeline.resource_group_load_fractions[0]) == pytest.approx(1.0)
    assert sum(prefill_pipeline.resource_group_load_fractions[1]) == pytest.approx(1.0)


def test_uniform_expert_traffic_reaches_only_required_hierarchy_depth() -> None:
    workload = InferenceWorkload(
        name="expert_depth",
        total_npus=2048,
        npus_per_card=8,
        layers=8,
        hidden_size=1024,
        activation_bytes=2,
        prompt_tokens=16,
        generation_tokens=4,
        batch_size=1,
        microbatch_size=1,
        tensor_parallel=1,
        pipeline_parallel=1,
        expert_parallel=64,
        data_parallel=32,
        experts=64,
        expert_top_k=2,
        moe_layer_count=8,
    )
    graph = compile_traffic_graph(workload)
    demand = graph.stages[0].demands[0]
    assert demand.axis == "expert"
    assert demand.tier_crossing_fractions[0] > 0.0
    assert demand.tier_crossing_fractions[1] == 0.0
    assert sum(demand.tier_transmitted_bytes) <= demand.total_transmitted_bytes


def test_million_endpoint_graph_remains_a_small_set_of_compressed_demands() -> None:
    values = json.loads(
        (ROOT / "simulator" / "kdlink" / "config" / "inference_dense.json").read_text()
    )
    workload = InferenceWorkload.from_dict(values["workload"])
    graph = compile_traffic_graph(workload)
    assert graph.total_npus == 1048576
    assert graph.physical_card_count == 262144
    assert graph.route_tier_count == 5
    assert sum(len(stage.demands) for stage in graph.stages) == 4
    assert graph.stages[0].demands[0].tier_crossing_fractions == (0.0,) * 5


def test_distributed_million_endpoint_experts_reach_tier_five() -> None:
    values = json.loads(
        (ROOT / "simulator" / "kdlink" / "config" / "inference_moe.json").read_text()
    )
    workload = InferenceWorkload.from_dict(values["workload"])
    graph = compile_traffic_graph(workload)
    expert = next(
        demand for demand in graph.stages[0].demands if demand.axis == "expert"
    )
    assert expert.tier_crossing_fractions[-1] == 1.0
    assert all(fraction == 1.0 for fraction in expert.tier_crossing_fractions)
    for tier_index, loads in enumerate(expert.resource_group_load_fractions):
        assert len(loads) == 32768 // (8**tier_index)
        assert sum(loads) == pytest.approx(1.0)
