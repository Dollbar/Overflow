"""Configurable sparse HBM functional and cycle-accounted simulation model."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
import heapq
from pathlib import Path
from typing import Deque, Iterable

import yaml


HBM_OK = "OK"
HBM_ECC_CORRECTED = "ECC_CORRECTED"
HBM_ECC_UNCORRECTABLE = "ECC_UNCORRECTABLE"
HBM_DATA_ERROR = "DATA_ERROR"


@dataclass(frozen=True)
class HBMConfig:
    partitions: int
    capacity_bytes_per_partition: int
    logical_clock_hz: int
    beat_bytes: int
    maximum_transaction_bytes: int
    payload_bytes_per_cycle_per_partition: int
    read_latency_cycles: int
    write_latency_cycles: int
    max_outstanding_per_partition: int
    channels_per_partition: int = 16
    pseudo_channels_per_channel: int = 2
    bank_groups_per_pseudo_channel: int = 4
    banks_per_bank_group: int = 4
    row_bytes: int = 2048
    bank_interleave_bytes: int = 128
    timing_model_enabled: bool = False
    scheduler_policy: str = "fifo"
    max_issues_per_partition_per_cycle: int = 0
    activate_cycles: int = 14
    precharge_cycles: int = 14
    minimum_row_active_cycles: int = 32
    column_to_column_cycles: int = 4
    row_to_row_cycles: int = 4
    four_activate_window_cycles: int = 16
    read_to_write_cycles: int = 8
    write_to_read_cycles: int = 12
    refresh_enabled: bool = False
    refresh_interval_cycles: int = 3900
    refresh_duration_cycles: int = 160
    refresh_stagger_cycles: int = 1
    ecc_enabled: bool = True
    correctable_bits_per_beat: int = 1
    event_log_depth: int = 4096

    @classmethod
    def from_yaml(cls, path: str | Path, profile: str = "nominal") -> "HBMConfig":
        document = yaml.safe_load(Path(path).read_text(encoding="ascii"))
        if document.get("schema_version") not in (1, 2):
            raise ValueError("unsupported HBM configuration schema")

        values: dict[str, object] = {}
        for section in ("hbm", "geometry", "timing", "refresh", "ecc", "observability"):
            values.update(document.get(section, {}))

        if profile != "nominal":
            profiles = document.get("profiles", {})
            if profile == "stress" and "stress_overrides" in document and not profiles.get(profile):
                values.update(document.get("stress_overrides", {}))
            elif profile in profiles:
                override = profiles[profile]
                for section in ("hbm", "geometry", "timing", "refresh", "ecc", "observability"):
                    values.update(override.get(section, {}))
                values.update({key: value for key, value in override.items() if not isinstance(value, dict)})
            else:
                available = ", ".join(sorted(name for name in profiles if name != "stress"))
                raise ValueError(
                    f"HBM profile must be nominal or stress or one of: {available}"
                )

        config = cls(**values)
        config.validate()
        return config

    @property
    def logical_cycle_ns(self) -> float:
        return 1.0e9 / self.logical_clock_hz

    @property
    def total_capacity_bytes(self) -> int:
        return self.partitions * self.capacity_bytes_per_partition

    @property
    def pseudo_channels_per_partition(self) -> int:
        return self.channels_per_partition * self.pseudo_channels_per_channel

    @property
    def banks_per_pseudo_channel(self) -> int:
        return self.bank_groups_per_pseudo_channel * self.banks_per_bank_group

    @property
    def banks_per_partition(self) -> int:
        return self.pseudo_channels_per_partition * self.banks_per_pseudo_channel

    @property
    def payload_bytes_per_second_per_partition(self) -> int:
        return self.payload_bytes_per_cycle_per_partition * self.logical_clock_hz

    @property
    def aggregate_payload_bytes_per_second(self) -> int:
        return self.partitions * self.payload_bytes_per_second_per_partition

    @property
    def read_latency_ns(self) -> float:
        return self.read_latency_cycles * self.logical_cycle_ns

    @property
    def write_latency_ns(self) -> float:
        return self.write_latency_cycles * self.logical_cycle_ns

    def validate(self) -> None:
        positive = (
            self.partitions,
            self.capacity_bytes_per_partition,
            self.logical_clock_hz,
            self.beat_bytes,
            self.maximum_transaction_bytes,
            self.payload_bytes_per_cycle_per_partition,
            self.read_latency_cycles,
            self.write_latency_cycles,
            self.max_outstanding_per_partition,
            self.channels_per_partition,
            self.pseudo_channels_per_channel,
            self.bank_groups_per_pseudo_channel,
            self.banks_per_bank_group,
            self.row_bytes,
            self.bank_interleave_bytes,
            self.activate_cycles,
            self.precharge_cycles,
            self.minimum_row_active_cycles,
            self.column_to_column_cycles,
            self.row_to_row_cycles,
            self.four_activate_window_cycles,
            self.read_to_write_cycles,
            self.write_to_read_cycles,
            self.refresh_interval_cycles,
            self.refresh_duration_cycles,
            self.event_log_depth,
        )
        if any(value <= 0 for value in positive):
            raise ValueError("positive HBM configuration values must be greater than zero")
        if self.max_issues_per_partition_per_cycle < 0:
            raise ValueError("maximum issue count must be non-negative")
        if self.refresh_stagger_cycles < 0 or self.correctable_bits_per_beat < 0:
            raise ValueError("refresh stagger and ECC correction width must be non-negative")
        if self.scheduler_policy not in ("fifo", "fr_fcfs"):
            raise ValueError("scheduler policy must be fifo or fr_fcfs")
        if self.capacity_bytes_per_partition % self.beat_bytes:
            raise ValueError("partition capacity must be a whole number of beats")
        if self.maximum_transaction_bytes % self.beat_bytes:
            raise ValueError("maximum transaction size must be a whole number of beats")
        if self.row_bytes % self.beat_bytes or self.bank_interleave_bytes % self.beat_bytes:
            raise ValueError("row and bank interleave sizes must be beat aligned")
        if self.bank_interleave_bytes > self.row_bytes:
            raise ValueError("bank interleave size cannot exceed row size")
        if self.refresh_enabled and self.refresh_duration_cycles >= self.refresh_interval_cycles:
            raise ValueError("refresh duration must be shorter than the refresh interval")


@dataclass(frozen=True)
class HBMAddress:
    partition: int
    channel: int
    pseudo_channel: int
    bank_group: int
    bank: int
    row: int
    column_byte: int
    linear_bank: int


@dataclass(frozen=True)
class HBMRequest:
    partition: int
    address: int
    length: int
    tag: int
    write_data: bytes | None = None
    byte_enable: bytes | None = None
    qos: int = 0

    @property
    def is_write(self) -> bool:
        return self.write_data is not None


@dataclass(frozen=True)
class HBMResponse:
    partition: int
    tag: int
    is_write: bool
    data: bytes
    completion_cycle: int
    status: str = HBM_OK
    corrected_bits: int = 0
    address: int = 0


@dataclass(frozen=True)
class HBMEvent:
    cycle: int
    kind: str
    partition: int
    tag: int | None = None
    address: int | None = None
    detail: str = ""


@dataclass
class HBMStats:
    accepted_requests: int = 0
    accepted_read_bytes: int = 0
    accepted_write_bytes: int = 0
    issued_requests: int = 0
    completed_requests: int = 0
    backpressure_events: int = 0
    disabled_partition_events: int = 0
    row_hits: int = 0
    row_misses: int = 0
    row_conflicts: int = 0
    refresh_commands: int = 0
    refresh_blocked_cycles: int = 0
    read_write_turnarounds: int = 0
    corrected_responses: int = 0
    uncorrectable_responses: int = 0
    first_issue_cycle: int | None = None
    last_issue_cycle: int | None = None

    @property
    def accepted_payload_bytes(self) -> int:
        return self.accepted_read_bytes + self.accepted_write_bytes


@dataclass
class _BankState:
    open_row: int | None = None
    ready_cycle: int = 0
    active_since_cycle: int = 0


@dataclass
class _PartitionState:
    enabled: bool = True
    refresh_until_cycle: int = 0
    next_refresh_cycle: int = 0
    command_ready_cycle: int = 0
    last_operation_write: bool | None = None


class HBMModel:
    """Models large HBM capacity sparsely while accounting for logical cycles."""

    def __init__(self, config: HBMConfig):
        config.validate()
        self.config = config
        self.cycle = 0
        self.stats = HBMStats()
        self._pending: list[Deque[tuple[int, HBMRequest]]] = [
            deque() for _ in range(config.partitions)
        ]
        self._outstanding = [0] * config.partitions
        self._tokens = [0] * config.partitions
        self._last_completion_cycle = [0] * config.partitions
        self._inflight: list[tuple[int, int, HBMRequest]] = []
        self._responses: Deque[HBMResponse] = deque()
        self._events: Deque[HBMEvent] = deque(maxlen=config.event_log_depth)
        self._storage: dict[tuple[int, int], int] = {}
        self._fault_masks: dict[tuple[int, int], tuple[int, bool]] = {}
        self._sequence = 0
        self._banks = [
            [_BankState() for _ in range(config.banks_per_partition)]
            for _ in range(config.partitions)
        ]
        self._activate_history: list[Deque[int]] = [
            deque() for _ in range(config.partitions)
        ]
        self._partition_state = [
            _PartitionState(
                next_refresh_cycle=config.refresh_interval_cycles
                + partition * config.refresh_stagger_cycles
            )
            for partition in range(config.partitions)
        ]

    @property
    def idle(self) -> bool:
        return not self._inflight and all(not queue for queue in self._pending)

    def outstanding(self, partition: int) -> int:
        self._validate_partition(partition)
        return self._outstanding[partition]

    def pending(self, partition: int) -> int:
        self._validate_partition(partition)
        return len(self._pending[partition])

    def can_accept(self, partition: int) -> bool:
        self._validate_partition(partition)
        return (
            self._partition_state[partition].enabled
            and self._outstanding[partition] < self.config.max_outstanding_per_partition
        )

    def decode_address(self, partition: int, address: int) -> HBMAddress:
        self._validate_partition(partition)
        if not 0 <= address < self.config.capacity_bytes_per_partition:
            raise ValueError("address is outside the logical HBM partition capacity")
        interleave = self.config.bank_interleave_bytes
        line = address // interleave
        linear_bank = line % self.config.banks_per_partition
        row_span_lines = self.config.row_bytes // interleave
        row = (line // self.config.banks_per_partition) // row_span_lines
        column_line = (line // self.config.banks_per_partition) % row_span_lines
        column_byte = column_line * interleave + address % interleave
        banks_per_pc = self.config.banks_per_pseudo_channel
        pc_linear = linear_bank // banks_per_pc
        bank_in_pc = linear_bank % banks_per_pc
        channel = pc_linear // self.config.pseudo_channels_per_channel
        pseudo_channel = pc_linear % self.config.pseudo_channels_per_channel
        bank_group = bank_in_pc // self.config.banks_per_bank_group
        bank = bank_in_pc % self.config.banks_per_bank_group
        return HBMAddress(
            partition=partition,
            channel=channel,
            pseudo_channel=pseudo_channel,
            bank_group=bank_group,
            bank=bank,
            row=row,
            column_byte=column_byte,
            linear_bank=linear_bank,
        )

    def submit_read(self, partition: int, address: int, length: int, tag: int, qos: int = 0) -> bool:
        return self._submit(HBMRequest(partition, address, length, tag, qos=qos))

    def submit_write(
        self,
        partition: int,
        address: int,
        data: bytes,
        tag: int,
        byte_enable: bytes | None = None,
        qos: int = 0,
    ) -> bool:
        return self._submit(
            HBMRequest(partition, address, len(data), tag, bytes(data), byte_enable, qos)
        )

    def pop_response(self) -> HBMResponse | None:
        return self._responses.popleft() if self._responses else None

    def drain_responses(self) -> list[HBMResponse]:
        responses = list(self._responses)
        self._responses.clear()
        return responses

    def drain_events(self) -> list[HBMEvent]:
        events = list(self._events)
        self._events.clear()
        return events

    def set_partition_enabled(self, partition: int, enabled: bool) -> None:
        self._validate_partition(partition)
        self._partition_state[partition].enabled = enabled
        self._record("partition_enabled" if enabled else "partition_disabled", partition)

    def request_refresh(self, partition: int) -> None:
        self._validate_partition(partition)
        self._partition_state[partition].next_refresh_cycle = min(
            self._partition_state[partition].next_refresh_cycle,
            self.cycle + 1,
        )

    def inject_bit_errors(
        self,
        partition: int,
        address: int,
        bit_positions: Iterable[int],
        *,
        persistent: bool = False,
    ) -> None:
        self._validate_partition(partition)
        for bit_position in bit_positions:
            if bit_position < 0:
                raise ValueError("bit positions must be non-negative")
            byte_address = address + bit_position // 8
            if byte_address >= self.config.capacity_bytes_per_partition:
                raise ValueError("fault injection exceeds partition capacity")
            key = (partition, byte_address)
            previous_mask, previous_persistent = self._fault_masks.get(key, (0, False))
            self._fault_masks[key] = (
                previous_mask ^ (1 << (bit_position % 8)),
                persistent or previous_persistent,
            )
        self._record("fault_injected", partition, address=address)

    def clear_faults(self, partition: int | None = None) -> None:
        if partition is None:
            self._fault_masks.clear()
            return
        self._validate_partition(partition)
        for key in [key for key in self._fault_masks if key[0] == partition]:
            del self._fault_masks[key]

    def tick(self, cycles: int = 1) -> None:
        if cycles < 0:
            raise ValueError("cycles must be non-negative")
        for _ in range(cycles):
            self.cycle += 1
            self._complete_due_requests()
            for partition in range(self.config.partitions):
                self._service_refresh(partition)
                self._replenish_tokens(partition)
                self._issue_partition(partition)

    def run_until_idle(self, max_cycles: int = 1_000_000) -> int:
        start_cycle = self.cycle
        while not self.idle:
            if self.cycle - start_cycle >= max_cycles:
                raise TimeoutError("HBM model did not become idle")
            self.tick()
        return self.cycle - start_cycle

    def _submit(self, request: HBMRequest) -> bool:
        self._validate_request(request)
        partition = request.partition
        if not self._partition_state[partition].enabled:
            self.stats.backpressure_events += 1
            self.stats.disabled_partition_events += 1
            self._record("backpressure_disabled", partition, request.tag, request.address)
            return False
        if not self.can_accept(partition):
            self.stats.backpressure_events += 1
            self._record("backpressure_full", partition, request.tag, request.address)
            return False
        self._sequence += 1
        self._pending[partition].append((self._sequence, request))
        self._outstanding[partition] += 1
        self.stats.accepted_requests += 1
        if request.is_write:
            self.stats.accepted_write_bytes += request.length
        else:
            self.stats.accepted_read_bytes += request.length
        self._record("accepted", partition, request.tag, request.address)
        return True

    def _validate_partition(self, partition: int) -> None:
        if not 0 <= partition < self.config.partitions:
            raise ValueError("partition is outside the configured HBM range")

    def _validate_request(self, request: HBMRequest) -> None:
        self._validate_partition(request.partition)
        if request.length <= 0 or request.length % self.config.beat_bytes:
            raise ValueError("request length must be a positive whole number of beats")
        if request.length > self.config.maximum_transaction_bytes:
            raise ValueError("request length exceeds the configured maximum")
        if request.address < 0 or request.address % self.config.beat_bytes:
            raise ValueError("request address must be beat aligned")
        if request.address + request.length > self.config.capacity_bytes_per_partition:
            raise ValueError("request exceeds the logical HBM partition capacity")
        if request.write_data is not None and len(request.write_data) != request.length:
            raise ValueError("write data length does not match the request length")
        if request.byte_enable is not None:
            if not request.is_write:
                raise ValueError("byte enable is valid only for writes")
            if len(request.byte_enable) != request.length:
                raise ValueError("byte enable length does not match the write length")
            if any(value not in (0, 1) for value in request.byte_enable):
                raise ValueError("byte enable entries must be zero or one")
        if request.qos < 0:
            raise ValueError("QoS must be non-negative")

    def _service_refresh(self, partition: int) -> None:
        if not self.config.refresh_enabled:
            return
        state = self._partition_state[partition]
        if self.cycle < state.refresh_until_cycle:
            self.stats.refresh_blocked_cycles += 1
            return
        if self.cycle >= state.next_refresh_cycle:
            state.refresh_until_cycle = self.cycle + self.config.refresh_duration_cycles
            state.next_refresh_cycle += self.config.refresh_interval_cycles
            state.command_ready_cycle = max(state.command_ready_cycle, state.refresh_until_cycle)
            for bank in self._banks[partition]:
                bank.open_row = None
                bank.ready_cycle = max(bank.ready_cycle, state.refresh_until_cycle)
            self.stats.refresh_commands += 1
            self.stats.refresh_blocked_cycles += 1
            self._record("refresh", partition, detail=f"until={state.refresh_until_cycle}")

    def _replenish_tokens(self, partition: int) -> None:
        token_capacity = max(
            self.config.maximum_transaction_bytes,
            self.config.payload_bytes_per_cycle_per_partition + self.config.beat_bytes - 1,
        )
        self._tokens[partition] = min(
            token_capacity,
            self._tokens[partition] + self.config.payload_bytes_per_cycle_per_partition,
        )

    def _select_request(self, partition: int) -> tuple[int, HBMRequest] | None:
        queue = self._pending[partition]
        if not queue:
            return None
        if self.config.scheduler_policy == "fifo" or not self.config.timing_model_enabled:
            return queue[0]
        entries = list(queue)
        best_index = 0
        best_key: tuple[int, int, int, int, int] | None = None
        for index, (sequence, request) in enumerate(entries):
            if any(
                self._requests_conflict(older_request, request)
                for _, older_request in entries[:index]
            ):
                continue
            decoded = self.decode_address(partition, request.address)
            bank = self._banks[partition][decoded.linear_bank]
            row_hit = int(bank.open_row == decoded.row)
            ready = max(bank.ready_cycle, self._partition_state[partition].command_ready_cycle)
            key = (int(ready > self.cycle), -row_hit, ready, -request.qos, sequence)
            if best_key is None or key < best_key:
                best_key = key
                best_index = index
        queue.rotate(-best_index)
        selected = queue[0]
        queue.rotate(best_index)
        return selected

    @staticmethod
    def _requests_conflict(older: HBMRequest, newer: HBMRequest) -> bool:
        if not (older.is_write or newer.is_write):
            return False
        return (
            older.address < newer.address + newer.length
            and newer.address < older.address + older.length
        )

    def _remove_selected(self, partition: int, sequence: int) -> HBMRequest:
        queue = self._pending[partition]
        for index, (candidate_sequence, request) in enumerate(queue):
            if candidate_sequence == sequence:
                queue.rotate(-index)
                queue.popleft()
                queue.rotate(index)
                return request
        raise RuntimeError("selected HBM request disappeared from the queue")

    def _issue_partition(self, partition: int) -> None:
        state = self._partition_state[partition]
        if not state.enabled or self.cycle < state.refresh_until_cycle:
            return
        issue_limit = self.config.max_issues_per_partition_per_cycle or (1 << 30)
        issued = 0
        while issued < issue_limit:
            selected = self._select_request(partition)
            if selected is None:
                return
            sequence, request = selected
            if self._tokens[partition] < request.length:
                return
            extra_latency = 0
            if self.config.timing_model_enabled:
                decoded = self.decode_address(partition, request.address)
                bank = self._banks[partition][decoded.linear_bank]
                if self.cycle < max(bank.ready_cycle, state.command_ready_cycle):
                    return
                if state.last_operation_write is not None and state.last_operation_write != request.is_write:
                    turnaround = (
                        self.config.write_to_read_cycles
                        if state.last_operation_write
                        else self.config.read_to_write_cycles
                    )
                    state.command_ready_cycle = self.cycle + turnaround
                    state.last_operation_write = request.is_write
                    self.stats.read_write_turnarounds += 1
                    return
                needs_activate = bank.open_row != decoded.row
                if needs_activate:
                    history = self._activate_history[partition]
                    while history and history[0] + self.config.four_activate_window_cycles <= self.cycle:
                        history.popleft()
                    if history and history[-1] + self.config.row_to_row_cycles > self.cycle:
                        state.command_ready_cycle = history[-1] + self.config.row_to_row_cycles
                        return
                    if len(history) >= 4:
                        state.command_ready_cycle = history[0] + self.config.four_activate_window_cycles
                        return
                if bank.open_row is None:
                    self.stats.row_misses += 1
                    extra_latency = self.config.activate_cycles
                    bank.active_since_cycle = self.cycle
                elif bank.open_row == decoded.row:
                    self.stats.row_hits += 1
                else:
                    self.stats.row_conflicts += 1
                    active_wait = max(
                        0,
                        bank.active_since_cycle
                        + self.config.minimum_row_active_cycles
                        - self.cycle,
                    )
                    extra_latency = active_wait + self.config.precharge_cycles + self.config.activate_cycles
                    bank.active_since_cycle = self.cycle + active_wait + self.config.precharge_cycles
                if needs_activate:
                    self._activate_history[partition].append(self.cycle + max(0, extra_latency - self.config.activate_cycles))
                bank.open_row = decoded.row
                bank.ready_cycle = self.cycle + max(
                    self.config.column_to_column_cycles,
                    extra_latency + self.config.row_to_row_cycles,
                )
                state.last_operation_write = request.is_write

            request = self._remove_selected(partition, sequence)
            self._tokens[partition] -= request.length
            latency = (
                self.config.write_latency_cycles if request.is_write else self.config.read_latency_cycles
            ) + extra_latency
            completion_cycle = max(
                self.cycle + latency,
                self._last_completion_cycle[partition],
            )
            self._last_completion_cycle[partition] = completion_cycle
            heapq.heappush(self._inflight, (completion_cycle, sequence, request))
            self.stats.issued_requests += 1
            if self.stats.first_issue_cycle is None:
                self.stats.first_issue_cycle = self.cycle
            self.stats.last_issue_cycle = self.cycle
            self._record("issued", partition, request.tag, request.address, f"done={completion_cycle}")
            issued += 1

    def _apply_write(self, request: HBMRequest) -> None:
        assert request.write_data is not None
        enables = request.byte_enable or bytes([1]) * request.length
        for offset, (value, enabled) in enumerate(zip(request.write_data, enables)):
            if not enabled:
                continue
            key = (request.partition, request.address + offset)
            if value:
                self._storage[key] = value
            else:
                self._storage.pop(key, None)
            fault = self._fault_masks.get(key)
            if fault is not None and not fault[1]:
                del self._fault_masks[key]

    def _read_with_ecc(self, request: HBMRequest) -> tuple[bytes, str, int]:
        clean = bytearray(
            self._storage.get((request.partition, request.address + offset), 0)
            for offset in range(request.length)
        )
        observed = bytearray(clean)
        transient_keys: list[tuple[int, int]] = []
        errors_per_beat = [0] * (request.length // self.config.beat_bytes)
        for offset in range(request.length):
            key = (request.partition, request.address + offset)
            fault = self._fault_masks.get(key)
            if fault is None:
                continue
            mask, persistent = fault
            observed[offset] ^= mask
            errors_per_beat[offset // self.config.beat_bytes] += mask.bit_count()
            if not persistent:
                transient_keys.append(key)
        for key in transient_keys:
            self._fault_masks.pop(key, None)
        total_errors = sum(errors_per_beat)
        if total_errors == 0:
            return bytes(clean), HBM_OK, 0
        if self.config.ecc_enabled and all(
            count <= self.config.correctable_bits_per_beat for count in errors_per_beat
        ):
            self.stats.corrected_responses += 1
            return bytes(clean), HBM_ECC_CORRECTED, total_errors
        if self.config.ecc_enabled:
            self.stats.uncorrectable_responses += 1
            return bytes(observed), HBM_ECC_UNCORRECTABLE, 0
        self.stats.uncorrectable_responses += 1
        return bytes(observed), HBM_DATA_ERROR, 0

    def _complete_due_requests(self) -> None:
        while self._inflight and self._inflight[0][0] <= self.cycle:
            completion_cycle, _, request = heapq.heappop(self._inflight)
            if request.is_write:
                self._apply_write(request)
                data, status, corrected_bits = b"", HBM_OK, 0
            else:
                data, status, corrected_bits = self._read_with_ecc(request)
            self._outstanding[request.partition] -= 1
            self.stats.completed_requests += 1
            self._responses.append(
                HBMResponse(
                    partition=request.partition,
                    tag=request.tag,
                    is_write=request.is_write,
                    data=data,
                    completion_cycle=completion_cycle,
                    status=status,
                    corrected_bits=corrected_bits,
                    address=request.address,
                )
            )
            self._record("completed", request.partition, request.tag, request.address, status)

    def _record(
        self,
        kind: str,
        partition: int,
        tag: int | None = None,
        address: int | None = None,
        detail: str = "",
    ) -> None:
        self._events.append(HBMEvent(self.cycle, kind, partition, tag, address, detail))
