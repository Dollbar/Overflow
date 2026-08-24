"""Hierarchical KDLink route-context and topology reference model."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import IntEnum
from typing import Mapping, Sequence


ROUTE_SCHEMA_VERSION = 3
ROUTE_CONTEXT_MESSAGE_TYPE = 8
MAX_DOMAINS = 256
NODES_PER_DOMAIN = 32
MAX_PACKET_FLITS = 16

ROUTE_SOURCE_DOMAIN_LSB = 0
ROUTE_DESTINATION_DOMAIN_LSB = 8
ROUTE_SOURCE_NODE_LSB = 16
ROUTE_DESTINATION_NODE_LSB = 21
ROUTE_TOPOLOGY_EPOCH_LSB = 26
ROUTE_DOMAIN_HOP_LIMIT_LSB = 34
ROUTE_LOGICAL_PLANE_LSB = 42
ROUTE_SLICE_MASK_LSB = 45
ROUTE_POLICY_LSB = 47
ROUTE_PACKET_FLIT_COUNT_LSB = 50
ROUTE_EXPECTED_PACKET_SEQUENCE_LSB = 55
ROUTE_GLOBAL_TRANSACTION_ID_LSB = 67
ROUTE_GROUP_ID_LSB = 131
ROUTE_LOGICAL_VC_LSB = 163
ROUTE_RESERVED_LSB = 166

ROUTE_RESERVED_WIDTH = 512 - ROUTE_RESERVED_LSB


def _put(value: int, field: int, lsb: int, width: int) -> int:
    if not 0 <= field < (1 << width):
        raise ValueError(f"field at bit {lsb} exceeds {width} bits")
    return value | (field << lsb)


def _get(value: int, lsb: int, width: int) -> int:
    return (value >> lsb) & ((1 << width) - 1)


@dataclass(frozen=True)
class GlobalEndpoint:
    domain_id: int
    local_node: int

    def validate(self) -> None:
        if not 0 <= self.domain_id < MAX_DOMAINS:
            raise ValueError("domain is outside the 8-bit address space")
        if not 0 <= self.local_node < NODES_PER_DOMAIN:
            raise ValueError("node is outside the 32-node leaf domain")

    def encode(self) -> int:
        self.validate()
        return (self.domain_id << 5) | self.local_node

    @classmethod
    def decode(cls, value: int) -> "GlobalEndpoint":
        if not 0 <= value < (MAX_DOMAINS * NODES_PER_DOMAIN):
            raise ValueError("global endpoint is outside the 13-bit address space")
        return cls(domain_id=value >> 5, local_node=value & 0x1F)


@dataclass(frozen=True)
class RouteContext:
    source_domain: int
    destination_domain: int
    source_node: int
    destination_node: int
    topology_epoch: int
    domain_hop_limit: int
    logical_plane: int
    slice_mask: int
    route_policy: int
    packet_flit_count: int
    expected_packet_sequence: int
    global_transaction_id: int
    group_id: int = 0
    logical_vc: int = 0
    reserved: int = 0

    def validate(self) -> None:
        GlobalEndpoint(self.source_domain, self.source_node).validate()
        GlobalEndpoint(self.destination_domain, self.destination_node).validate()
        if not 0 <= self.topology_epoch < 256:
            raise ValueError("topology epoch exceeds 8 bits")
        if not 1 <= self.domain_hop_limit < 256:
            raise ValueError("domain hop limit must be from 1 through 255")
        if not 0 <= self.logical_plane < 8:
            raise ValueError("logical plane is outside the eight-plane topology")
        if not 1 <= self.slice_mask < 4:
            raise ValueError("slice mask must enable at least one bonded slice")
        if self.route_policy != 0:
            raise ValueError("only deterministic route policy zero is implemented")
        if not 1 <= self.packet_flit_count <= MAX_PACKET_FLITS:
            raise ValueError("packet flit count must be from 1 through 16")
        if not 0 <= self.expected_packet_sequence < 4096:
            raise ValueError("packet sequence exceeds 12 bits")
        if not 0 <= self.global_transaction_id < (1 << 64):
            raise ValueError("global transaction identifier exceeds 64 bits")
        if not 0 <= self.group_id < (1 << 32):
            raise ValueError("group identifier exceeds 32 bits")
        if not 0 <= self.logical_vc <= 5:
            raise ValueError("logical VC must be from zero through five")
        if self.reserved != 0:
            raise ValueError("route-context reserved bits must be zero")

    def encode(self) -> int:
        self.validate()
        value = 0
        value = _put(value, self.source_domain, ROUTE_SOURCE_DOMAIN_LSB, 8)
        value = _put(value, self.destination_domain, ROUTE_DESTINATION_DOMAIN_LSB, 8)
        value = _put(value, self.source_node, ROUTE_SOURCE_NODE_LSB, 5)
        value = _put(value, self.destination_node, ROUTE_DESTINATION_NODE_LSB, 5)
        value = _put(value, self.topology_epoch, ROUTE_TOPOLOGY_EPOCH_LSB, 8)
        value = _put(value, self.domain_hop_limit, ROUTE_DOMAIN_HOP_LIMIT_LSB, 8)
        value = _put(value, self.logical_plane, ROUTE_LOGICAL_PLANE_LSB, 3)
        value = _put(value, self.slice_mask, ROUTE_SLICE_MASK_LSB, 2)
        value = _put(value, self.route_policy, ROUTE_POLICY_LSB, 3)
        value = _put(value, self.packet_flit_count, ROUTE_PACKET_FLIT_COUNT_LSB, 5)
        value = _put(value, self.expected_packet_sequence, ROUTE_EXPECTED_PACKET_SEQUENCE_LSB, 12)
        value = _put(value, self.global_transaction_id, ROUTE_GLOBAL_TRANSACTION_ID_LSB, 64)
        value = _put(value, self.group_id, ROUTE_GROUP_ID_LSB, 32)
        value = _put(value, self.logical_vc, ROUTE_LOGICAL_VC_LSB, 3)
        value = _put(value, self.reserved, ROUTE_RESERVED_LSB, ROUTE_RESERVED_WIDTH)
        return value

    @classmethod
    def decode(cls, value: int) -> "RouteContext":
        if not 0 <= value < (1 << 512):
            raise ValueError("route-context payload exceeds 512 bits")
        return cls(
            source_domain=_get(value, ROUTE_SOURCE_DOMAIN_LSB, 8),
            destination_domain=_get(value, ROUTE_DESTINATION_DOMAIN_LSB, 8),
            source_node=_get(value, ROUTE_SOURCE_NODE_LSB, 5),
            destination_node=_get(value, ROUTE_DESTINATION_NODE_LSB, 5),
            topology_epoch=_get(value, ROUTE_TOPOLOGY_EPOCH_LSB, 8),
            domain_hop_limit=_get(value, ROUTE_DOMAIN_HOP_LIMIT_LSB, 8),
            logical_plane=_get(value, ROUTE_LOGICAL_PLANE_LSB, 3),
            slice_mask=_get(value, ROUTE_SLICE_MASK_LSB, 2),
            route_policy=_get(value, ROUTE_POLICY_LSB, 3),
            packet_flit_count=_get(value, ROUTE_PACKET_FLIT_COUNT_LSB, 5),
            expected_packet_sequence=_get(value, ROUTE_EXPECTED_PACKET_SEQUENCE_LSB, 12),
            global_transaction_id=_get(value, ROUTE_GLOBAL_TRANSACTION_ID_LSB, 64),
            group_id=_get(value, ROUTE_GROUP_ID_LSB, 32),
            logical_vc=_get(value, ROUTE_LOGICAL_VC_LSB, 3),
            reserved=_get(value, ROUTE_RESERVED_LSB, ROUTE_RESERVED_WIDTH),
        )


@dataclass(frozen=True)
class MultidomainRoute:
    source: GlobalEndpoint
    destination: GlobalEndpoint
    local: bool
    uplink: int | None
    spine: int | None
    domain_hops: int
    route_digits: tuple[int, ...] = ()


@dataclass(frozen=True)
class SpineForward:
    egress_domain: int
    context: RouteContext
    escape_stages: tuple[str, ...]


class CollectiveOpcode(IntEnum):
    REDUCE_SCATTER = 0
    ALL_GATHER = 1
    ALL_REDUCE = 2
    ALL_TO_ALL = 3
    ALL_TO_ALL_V = 4
    POINT_TO_POINT = 5


class CollectivePhase(IntEnum):
    LEAF_PREPARE = 0
    INTERDOMAIN = 1
    LEAF_FINISH = 2
    COMPLETE = 3


@dataclass(frozen=True)
class RouteStageForward:
    stage_index: int
    egress: int
    context: RouteContext
    final_stage: bool


@dataclass(frozen=True)
class GlobalSend:
    transaction_id: int
    topology_epoch: int
    retry_count: int


@dataclass
class _SourceTransaction:
    topology_epoch: int
    retry_count: int = 0
    age: int = 0
    send_pending: bool = True


class GlobalTransactionSource:
    """Retains source transactions until a destination-global commit arrives."""

    def __init__(self, *, timeout_cycles: int = 8, maximum_retries: int = 15, slot_count: int = 16) -> None:
        if timeout_cycles < 1 or maximum_retries < 1:
            raise ValueError("timeout and maximum retries must be positive")
        self.timeout_cycles = timeout_cycles
        self.maximum_retries = maximum_retries
        self.slot_count = slot_count
        self._outstanding: dict[int, _SourceTransaction] = {}

    @property
    def outstanding(self) -> tuple[int, ...]:
        return tuple(sorted(self._outstanding))

    def begin(self, transaction_id: int, topology_epoch: int) -> None:
        if not 0 <= transaction_id < (1 << 64):
            raise ValueError("global transaction identifier exceeds 64 bits")
        if not 0 <= topology_epoch < 256:
            raise ValueError("topology epoch exceeds 8 bits")
        if transaction_id in self._outstanding:
            raise RuntimeError("transaction is already outstanding")
        if any(existing % self.slot_count == transaction_id % self.slot_count for existing in self._outstanding):
            raise RuntimeError("transaction replay-window slot is occupied")
        self._outstanding[transaction_id] = _SourceTransaction(topology_epoch)

    def next_send(self) -> GlobalSend | None:
        for transaction_id in sorted(self._outstanding):
            transaction = self._outstanding[transaction_id]
            if transaction.send_pending:
                transaction.send_pending = False
                transaction.age = 0
                return GlobalSend(transaction_id, transaction.topology_epoch, transaction.retry_count)
        return None

    def tick(self) -> None:
        for transaction in self._outstanding.values():
            if transaction.send_pending:
                continue
            transaction.age += 1
            if transaction.age >= self.timeout_cycles:
                if transaction.retry_count >= self.maximum_retries:
                    raise TimeoutError("global transaction exhausted its retry budget")
                transaction.retry_count += 1
                transaction.age = 0
                transaction.send_pending = True

    def route_reset(self, topology_epoch: int) -> None:
        if not 0 <= topology_epoch < 256:
            raise ValueError("topology epoch exceeds 8 bits")
        for transaction in self._outstanding.values():
            transaction.topology_epoch = topology_epoch
            transaction.retry_count += 1
            transaction.age = 0
            transaction.send_pending = True

    def commit(self, transaction_id: int, topology_epoch: int) -> bool:
        transaction = self._outstanding.get(transaction_id)
        if transaction is None or transaction.topology_epoch != topology_epoch:
            return False
        del self._outstanding[transaction_id]
        return True


@dataclass(frozen=True)
class DestinationCommit:
    deliver: bool
    acknowledge: bool


class GlobalCommitTracker:
    """Suppresses replayed destination commits while re-acknowledging them."""

    def __init__(self, *, history_depth: int = 16) -> None:
        if history_depth < 1:
            raise ValueError("history depth must be positive")
        self.history_depth = history_depth
        self._history: dict[int, tuple[int, int, int]] = {}

    def commit(self, source: GlobalEndpoint, transaction_id: int, topology_epoch: int) -> DestinationCommit:
        source.validate()
        if not 0 <= topology_epoch < 256:
            raise ValueError("topology epoch exceeds 8 bits")
        identity = (source.domain_id, source.local_node, transaction_id)
        index = transaction_id % self.history_depth
        if self._history.get(index) == identity:
            return DestinationCommit(deliver=False, acknowledge=True)
        self._history[index] = identity
        return DestinationCommit(deliver=True, acknowledge=True)

    def route_reset(self) -> None:
        """A route reset intentionally preserves committed transaction history."""


@dataclass(frozen=True)
class CollectiveCommand:
    phase: CollectivePhase
    destination_domain: int | None


class GroupTable:
    def __init__(self) -> None:
        self._groups: dict[int, tuple[int, tuple[int, ...]]] = {}

    def configure(self, group_id: int, members: Sequence[int], topology_epoch: int) -> None:
        normalized = tuple(sorted(set(members)))
        if not normalized or any(not 0 <= member < MAX_DOMAINS for member in normalized):
            raise ValueError("group membership must contain valid domains")
        if len(normalized) != len(members):
            raise ValueError("group membership contains duplicate domains")
        if not 0 <= topology_epoch < 256:
            raise ValueError("topology epoch exceeds 8 bits")
        self._groups[group_id] = (topology_epoch, normalized)

    def lookup(self, group_id: int, topology_epoch: int) -> tuple[int, ...]:
        configured = self._groups.get(group_id)
        if configured is None or configured[0] != topology_epoch:
            raise KeyError("group is absent or belongs to another topology epoch")
        return configured[1]


def hierarchical_route_digits(destination_domain: int, domain_count: int) -> tuple[int, ...]:
    if not 2 <= domain_count <= MAX_DOMAINS:
        raise ValueError("hierarchical routing requires from 2 through 256 domains")
    if not 0 <= destination_domain < domain_count:
        raise ValueError("destination domain is outside the instantiated topology")
    if domain_count <= 8:
        return (destination_domain & 0x7,)
    if domain_count <= 64:
        return ((destination_domain >> 3) & 0x7, destination_domain & 0x7)
    return ((destination_domain >> 6) & 0x3, (destination_domain >> 3) & 0x7, destination_domain & 0x7)


def forward_at_route_stage(
    context: RouteContext,
    *,
    domain_count: int,
    stage_index: int,
    active_egress_mask: int,
) -> RouteStageForward:
    context.validate()
    digits = hierarchical_route_digits(context.destination_domain, domain_count)
    if not 0 <= stage_index < len(digits):
        raise ValueError("route stage index is outside the topology depth")
    egress = digits[stage_index]
    if not active_egress_mask & (1 << egress):
        raise RuntimeError("selected hierarchical egress is inactive")
    if context.domain_hop_limit <= len(digits) - stage_index:
        raise RuntimeError("domain hop limit cannot reach the destination leaf")
    return RouteStageForward(
        stage_index=stage_index,
        egress=egress,
        context=replace(context, domain_hop_limit=context.domain_hop_limit - 1),
        final_stage=stage_index == len(digits) - 1,
    )


def schedule_hierarchical_collective(
    opcode: CollectiveOpcode,
    *,
    local_domain: int,
    group_members: Sequence[int],
    source_domain: int | None = None,
    destination_domain: int | None = None,
) -> tuple[CollectiveCommand, ...]:
    members = tuple(sorted(set(group_members)))
    if not members or any(not 0 <= member < MAX_DOMAINS for member in members):
        raise ValueError("collective group contains an invalid domain")
    if opcode == CollectiveOpcode.POINT_TO_POINT:
        if source_domain not in members or destination_domain not in members:
            raise ValueError("point-to-point endpoints must belong to the group")
        if local_domain not in (source_domain, destination_domain):
            raise ValueError("local domain is not a point-to-point endpoint")
        interdomain = (
            (CollectiveCommand(CollectivePhase.INTERDOMAIN, destination_domain),)
            if local_domain == source_domain
            else ()
        )
    else:
        if local_domain not in members:
            raise ValueError("local domain is not a collective group member")
        interdomain = tuple(
            CollectiveCommand(CollectivePhase.INTERDOMAIN, member)
            for member in members
            if member != local_domain
        )
    return (
        CollectiveCommand(CollectivePhase.LEAF_PREPARE, None),
        *interdomain,
        CollectiveCommand(CollectivePhase.LEAF_FINISH, None),
        CollectiveCommand(CollectivePhase.COMPLETE, None),
    )


def execute_hierarchical_collective(
    opcode: CollectiveOpcode,
    payloads: Mapping[int, Sequence[int] | Mapping[int, Sequence[int]]],
    members: Sequence[int],
    *,
    source_domain: int | None = None,
    destination_domain: int | None = None,
) -> dict[int, tuple[int, ...] | dict[int, tuple[int, ...]]]:
    ordered = tuple(sorted(members))
    if set(payloads) != set(ordered):
        raise ValueError("payload domains must exactly match group membership")
    if opcode in (CollectiveOpcode.REDUCE_SCATTER, CollectiveOpcode.ALL_REDUCE):
        vectors = [tuple(payloads[member]) for member in ordered]
        if not vectors or len({len(vector) for vector in vectors}) != 1:
            raise ValueError("reduction vectors must have equal length")
        reduced = tuple(sum(vector[index] for vector in vectors) for index in range(len(vectors[0])))
        if opcode == CollectiveOpcode.ALL_REDUCE:
            return {member: reduced for member in ordered}
        if len(reduced) % len(ordered):
            raise ValueError("reduce-scatter vector must divide evenly across domains")
        width = len(reduced) // len(ordered)
        return {member: reduced[index * width : (index + 1) * width] for index, member in enumerate(ordered)}
    if opcode == CollectiveOpcode.ALL_GATHER:
        gathered = tuple(value for member in ordered for value in payloads[member])
        return {member: gathered for member in ordered}
    if opcode in (CollectiveOpcode.ALL_TO_ALL, CollectiveOpcode.ALL_TO_ALL_V):
        result: dict[int, dict[int, tuple[int, ...]]] = {member: {} for member in ordered}
        for source in ordered:
            outbound = payloads[source]
            if not isinstance(outbound, Mapping) or set(outbound) != set(ordered):
                raise ValueError("all-to-all payload must map every destination")
            for destination in ordered:
                result[destination][source] = tuple(outbound[destination])
        return result
    if opcode == CollectiveOpcode.POINT_TO_POINT:
        if source_domain not in ordered or destination_domain not in ordered:
            raise ValueError("point-to-point endpoints must belong to the group")
        return {destination_domain: tuple(payloads[source_domain])}
    raise ValueError("unsupported collective opcode")


def select_uplink(global_transaction_id: int, active_uplink_mask: int, uplink_count: int) -> int:
    if not 1 <= uplink_count <= 8:
        raise ValueError("uplink count must be from 1 through 8")
    active = tuple(index for index in range(uplink_count) if active_uplink_mask & (1 << index))
    if not active:
        raise RuntimeError("no active inter-domain uplink")
    return active[global_transaction_id % len(active)]


def route_multidomain(
    source: GlobalEndpoint,
    destination: GlobalEndpoint,
    *,
    domain_count: int,
    uplink_count: int,
    active_uplink_mask: int,
    global_transaction_id: int,
) -> MultidomainRoute:
    source.validate()
    destination.validate()
    if not 1 <= domain_count <= MAX_DOMAINS:
        raise ValueError("domain count must be from 1 through 256")
    if source.domain_id >= domain_count or destination.domain_id >= domain_count:
        raise ValueError("endpoint domain is outside the instantiated topology")
    if source.domain_id == destination.domain_id:
        return MultidomainRoute(source, destination, True, None, None, 0)
    uplink = select_uplink(global_transaction_id, active_uplink_mask, uplink_count)
    if domain_count == 2:
        return MultidomainRoute(source, destination, False, uplink, None, 1)
    spine_count = min(uplink_count, 8)
    digits = hierarchical_route_digits(destination.domain_id, domain_count)
    return MultidomainRoute(source, destination, False, uplink, uplink % spine_count, len(digits) + 1, digits)


def remote_payload_efficiency(packet_flits: int) -> float:
    if not 1 <= packet_flits <= MAX_PACKET_FLITS:
        raise ValueError("packet flit count must be from 1 through 16")
    return packet_flits / (packet_flits + 1)


def forward_at_spine(
    context: RouteContext,
    *,
    domain_count: int,
    active_domain_mask: int,
) -> SpineForward:
    context.validate()
    if domain_count not in (4, 8):
        raise ValueError("the RTL spine implements only four-domain and eight-domain profiles")
    if context.destination_domain >= domain_count:
        raise ValueError("destination domain is outside the active spine profile")
    if not active_domain_mask & (1 << context.destination_domain):
        raise RuntimeError("destination domain is inactive")
    if context.domain_hop_limit <= 1:
        raise RuntimeError("domain hop limit is exhausted at the spine")
    return SpineForward(
        egress_domain=context.destination_domain,
        context=replace(context, domain_hop_limit=context.domain_hop_limit - 1),
        escape_stages=("leaf_up", "spine", "leaf_down"),
    )


def escape_dependencies_are_acyclic(domain_count: int) -> bool:
    if not 2 <= domain_count <= MAX_DOMAINS:
        raise ValueError("escape proof requires from 2 through 256 domains")
    depth = len(hierarchical_route_digits(domain_count - 1, domain_count))
    ranks = tuple(range(depth + 2))
    return all(source < destination for source, destination in zip(ranks, ranks[1:]))
