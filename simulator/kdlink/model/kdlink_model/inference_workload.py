"""Inference workload contract compiled into bounded communication stages."""

from __future__ import annotations

from dataclasses import dataclass

from .parallel_mapping import PARALLEL_AXES, ParallelPlacement
from .scale import SCALE_MAX_ENDPOINTS


COMMUNICATION_OPERATIONS = (
    "all_reduce",
    "reduce_scatter",
    "all_gather",
    "all_to_all_v",
    "point_to_point",
)
SUPPORTED_NPUS_PER_CARD = (1, 2, 4, 8, 16, 32)


@dataclass(frozen=True)
class CommunicationSpec:
    """One repeated inference communication operation shared by all matching groups."""

    name: str
    operation: str
    axis: str
    payload_bytes_per_participant: int
    repetitions: int
    imbalance_factor: float = 1.0

    def validate(self, placement: ParallelPlacement) -> None:
        if not self.name:
            raise ValueError("communication name must be nonempty")
        if self.operation not in COMMUNICATION_OPERATIONS:
            raise ValueError("unsupported inference communication operation")
        if self.axis not in PARALLEL_AXES:
            raise ValueError("communication axis is invalid")
        if placement.axis_size(self.axis) < 2:
            raise ValueError("communication axis must contain at least two ranks")
        if self.payload_bytes_per_participant < 1 or self.repetitions < 1:
            raise ValueError("communication payload and repetition count must be positive")
        if self.imbalance_factor < 1.0:
            raise ValueError("communication imbalance factor must be at least one")


@dataclass(frozen=True)
class InferenceStageSpec:
    """One dependency-ordered prefill or decode stage."""

    name: str
    compute_microseconds: float
    communications: tuple[CommunicationSpec, ...]

    def validate(self, placement: ParallelPlacement) -> None:
        if not self.name:
            raise ValueError("inference stage name must be nonempty")
        if self.compute_microseconds < 0.0:
            raise ValueError("stage compute time must be nonnegative")
        for communication in self.communications:
            communication.validate(placement)


@dataclass(frozen=True)
class InferenceWorkload:
    """Validated workload and its compressed communication schedule."""

    name: str
    total_npus: int
    npus_per_card: int
    layers: int
    hidden_size: int
    activation_bytes: int
    prompt_tokens: int
    generation_tokens: int
    batch_size: int
    microbatch_size: int
    tensor_parallel: int
    pipeline_parallel: int
    expert_parallel: int
    data_parallel: int
    axis_order: tuple[str, ...] = ("tensor", "expert", "pipeline", "data")
    experts: int = 1
    expert_top_k: int = 1
    moe_layer_count: int = 0
    tensor_collective: str = "all_reduce"
    tp_collectives_per_layer: int = 2
    prefill_compute_us_per_layer: float = 0.0
    decode_compute_us_per_layer: float = 0.0
    moe_imbalance_factor: float = 1.0
    remote_kv_fraction: float = 0.0
    remote_kv_bytes_per_token: int = 0
    remote_kv_axis: str = "data"
    compute_network_overlap: float = 0.0
    planning_example_only: bool = True

    @classmethod
    def from_dict(cls, values: dict) -> "InferenceWorkload":
        copied = dict(values)
        if "axis_order" in copied:
            copied["axis_order"] = tuple(copied["axis_order"])
        return cls(**copied)

    @property
    def placement(self) -> ParallelPlacement:
        return ParallelPlacement(
            total_npus=self.total_npus,
            tensor_parallel=self.tensor_parallel,
            pipeline_parallel=self.pipeline_parallel,
            expert_parallel=self.expert_parallel,
            data_parallel=self.data_parallel,
            axis_order=self.axis_order,
        )

    @property
    def microbatch_count(self) -> int:
        return self.batch_size // self.microbatch_size

    @property
    def physical_card_count(self) -> int:
        return (self.total_npus + self.npus_per_card - 1) // self.npus_per_card

    def validate(self) -> None:
        if not self.name:
            raise ValueError("workload name must be nonempty")
        if not 1 <= self.total_npus <= SCALE_MAX_ENDPOINTS:
            raise ValueError("workload NPU count exceeds the current KDLink endpoint space")
        if self.npus_per_card not in SUPPORTED_NPUS_PER_CARD:
            raise ValueError("workload uses an unsupported NPU-per-card profile")
        integer_fields = (
            self.layers,
            self.hidden_size,
            self.activation_bytes,
            self.prompt_tokens,
            self.generation_tokens,
            self.batch_size,
            self.microbatch_size,
            self.tp_collectives_per_layer,
        )
        if any(value < 1 for value in integer_fields):
            raise ValueError("workload dimensions must be positive")
        if self.batch_size % self.microbatch_size:
            raise ValueError("batch size must divide into complete microbatches")
        self.placement.validate()
        if self.layers % self.pipeline_parallel:
            raise ValueError("layers must divide evenly across pipeline ranks")
        if self.tensor_collective not in ("all_reduce", "reduce_scatter", "all_gather"):
            raise ValueError("tensor collective is unsupported")
        if not 0 <= self.moe_layer_count <= self.layers:
            raise ValueError("MoE layer count is outside the model")
        if self.moe_layer_count and self.moe_layer_count % self.pipeline_parallel:
            raise ValueError("MoE layers must divide evenly across pipeline ranks")
        if self.experts < 1 or not 1 <= self.expert_top_k <= self.experts:
            raise ValueError("expert topology or top-k is invalid")
        if self.moe_layer_count and self.expert_parallel < 2:
            raise ValueError("MoE communication requires multiple expert ranks")
        if self.expert_parallel > self.experts:
            raise ValueError("expert parallel ranks exceed the expert count")
        if self.prefill_compute_us_per_layer < 0.0 or self.decode_compute_us_per_layer < 0.0:
            raise ValueError("compute latency must be nonnegative")
        if self.moe_imbalance_factor < 1.0:
            raise ValueError("MoE imbalance factor must be at least one")
        if not 0.0 <= self.remote_kv_fraction <= 1.0:
            raise ValueError("remote KV fraction must be from zero through one")
        if self.remote_kv_fraction and self.remote_kv_bytes_per_token < 1:
            raise ValueError("remote KV bytes must be positive when remote KV is enabled")
        if self.remote_kv_axis not in PARALLEL_AXES:
            raise ValueError("remote KV axis is invalid")
        if self.remote_kv_fraction and self.placement.axis_size(self.remote_kv_axis) < 2:
            raise ValueError("remote KV axis must contain multiple ranks")
        if not 0.0 <= self.compute_network_overlap <= 1.0:
            raise ValueError("compute-network overlap must be from zero through one")


def compile_inference_stages(workload: InferenceWorkload) -> tuple[InferenceStageSpec, ...]:
    """Compile prefill and decode into compressed, dependency-ordered operations."""

    workload.validate()
    placement = workload.placement
    layers_per_stage = workload.layers // workload.pipeline_parallel
    microbatches = workload.microbatch_count
    prefill_payload = (
        workload.microbatch_size
        * workload.prompt_tokens
        * workload.hidden_size
        * workload.activation_bytes
    )
    decode_payload = workload.microbatch_size * workload.hidden_size * workload.activation_bytes
    prefill_operations: list[CommunicationSpec] = []
    decode_operations: list[CommunicationSpec] = []

    if workload.tensor_parallel > 1:
        prefill_operations.append(
            CommunicationSpec(
                "prefill_tensor_reduce",
                workload.tensor_collective,
                "tensor",
                prefill_payload,
                layers_per_stage * workload.tp_collectives_per_layer * microbatches,
            )
        )
        decode_operations.append(
            CommunicationSpec(
                "decode_tensor_reduce",
                workload.tensor_collective,
                "tensor",
                decode_payload,
                layers_per_stage
                * workload.tp_collectives_per_layer
                * microbatches
                * workload.generation_tokens,
            )
        )

    if workload.pipeline_parallel > 1:
        prefill_operations.append(
            CommunicationSpec(
                "prefill_pipeline_activation",
                "point_to_point",
                "pipeline",
                prefill_payload,
                microbatches,
            )
        )
        decode_operations.append(
            CommunicationSpec(
                "decode_pipeline_activation",
                "point_to_point",
                "pipeline",
                decode_payload,
                microbatches * workload.generation_tokens,
            )
        )

    if workload.moe_layer_count:
        moe_layers_per_stage = workload.moe_layer_count // workload.pipeline_parallel
        prefill_expert_payload = prefill_payload * workload.expert_top_k
        decode_expert_payload = decode_payload * workload.expert_top_k
        for suffix in ("dispatch", "return"):
            prefill_operations.append(
                CommunicationSpec(
                    f"prefill_expert_{suffix}",
                    "all_to_all_v",
                    "expert",
                    prefill_expert_payload,
                    moe_layers_per_stage * microbatches,
                    workload.moe_imbalance_factor,
                )
            )
            decode_operations.append(
                CommunicationSpec(
                    f"decode_expert_{suffix}",
                    "all_to_all_v",
                    "expert",
                    decode_expert_payload,
                    moe_layers_per_stage * microbatches * workload.generation_tokens,
                    workload.moe_imbalance_factor,
                )
            )

    if workload.remote_kv_fraction:
        remote_kv_payload = round(
            workload.microbatch_size
            * workload.generation_tokens
            * workload.remote_kv_bytes_per_token
            * workload.remote_kv_fraction
        )
        if remote_kv_payload:
            decode_operations.append(
                CommunicationSpec(
                    "decode_remote_kv",
                    "all_to_all_v",
                    workload.remote_kv_axis,
                    remote_kv_payload,
                    microbatches,
                )
            )

    pipeline_fill = microbatches + workload.pipeline_parallel - 1
    prefill_compute = layers_per_stage * workload.prefill_compute_us_per_layer * pipeline_fill
    decode_compute = (
        layers_per_stage
        * workload.decode_compute_us_per_layer
        * pipeline_fill
        * workload.generation_tokens
    )
    stages = (
        InferenceStageSpec("prefill", prefill_compute, tuple(prefill_operations)),
        InferenceStageSpec("decode", decode_compute, tuple(decode_operations)),
    )
    for stage in stages:
        stage.validate(placement)
    return stages
