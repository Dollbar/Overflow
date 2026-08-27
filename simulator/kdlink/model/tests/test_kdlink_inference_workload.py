import json
from pathlib import Path

import pytest

from kdlink_model.inference_workload import InferenceWorkload, compile_inference_stages


ROOT = Path(__file__).parents[4]


def small_workload(**overrides) -> InferenceWorkload:
    values = {
        "name": "small_dense",
        "total_npus": 64,
        "npus_per_card": 4,
        "layers": 8,
        "hidden_size": 1024,
        "activation_bytes": 2,
        "prompt_tokens": 16,
        "generation_tokens": 4,
        "batch_size": 2,
        "microbatch_size": 1,
        "tensor_parallel": 8,
        "pipeline_parallel": 8,
        "expert_parallel": 1,
        "data_parallel": 1,
        "prefill_compute_us_per_layer": 2.0,
        "decode_compute_us_per_layer": 1.0,
    }
    values.update(overrides)
    return InferenceWorkload(**values)


def test_dense_workload_compiles_prefill_and_decode_without_per_token_objects() -> None:
    workload = small_workload()
    stages = compile_inference_stages(workload)
    assert workload.physical_card_count == 16
    assert [stage.name for stage in stages] == ["prefill", "decode"]
    assert [operation.operation for operation in stages[0].communications] == [
        "all_reduce",
        "point_to_point",
    ]
    assert stages[0].communications[0].payload_bytes_per_participant == 32768
    assert stages[0].communications[0].repetitions == 4
    assert stages[1].communications[0].repetitions == 16


def test_moe_and_remote_kv_compile_explicit_hotspot_traffic() -> None:
    workload = small_workload(
        total_npus=512,
        tensor_parallel=8,
        pipeline_parallel=8,
        expert_parallel=8,
        data_parallel=1,
        experts=64,
        expert_top_k=2,
        moe_layer_count=8,
        moe_imbalance_factor=1.75,
        remote_kv_fraction=0.25,
        remote_kv_bytes_per_token=4096,
        remote_kv_axis="expert",
    )
    stages = compile_inference_stages(workload)
    expert_operations = [
        operation
        for stage in stages
        for operation in stage.communications
        if operation.axis == "expert"
    ]
    assert len(expert_operations) == 5
    assert expert_operations[0].imbalance_factor == 1.75
    assert expert_operations[-1].name == "decode_remote_kv"


@pytest.mark.parametrize("operation", ("all_reduce", "reduce_scatter", "all_gather"))
def test_tensor_collective_selection_is_explicit(operation: str) -> None:
    stages = compile_inference_stages(small_workload(tensor_collective=operation))
    assert stages[0].communications[0].operation == operation
    assert stages[1].communications[0].operation == operation


def test_all_example_configs_are_explicit_planning_inputs_and_validate() -> None:
    for name in (
        "inference_dense.json",
        "inference_moe.json",
        "inference_failure.json",
        "inference_serving.json",
    ):
        values = json.loads((ROOT / "simulator" / "kdlink" / "config" / name).read_text())
        assert values["planning_example_only"] is True
        workload = InferenceWorkload.from_dict(values["workload"])
        workload.validate()


@pytest.mark.parametrize(
    ("overrides", "message"),
    (
        ({"total_npus": 65}, "exactly cover"),
        ({"npus_per_card": 3}, "unsupported"),
        ({"batch_size": 3, "microbatch_size": 2}, "microbatches"),
        ({"layers": 9}, "divide evenly"),
        ({"compute_network_overlap": 1.1}, "overlap"),
        ({"tensor_collective": "broadcast"}, "collective"),
        ({"remote_kv_fraction": 0.5}, "bytes"),
    ),
)
def test_invalid_inference_workload_contracts_are_rejected(overrides, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        small_workload(**overrides).validate()
