"""Million-scale KDLink address, route, group-directory, and plane reference model."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence


SCALE_SCHEMA = 4
SCALE_ROUTE_CONTEXT_MESSAGE_TYPE = 8
SCALE_GLOBAL_COMMIT_MESSAGE_TYPE = 9
SCALE_DOMAIN_BITS = 15
SCALE_NODE_BITS = 5
SCALE_ENDPOINT_BITS = SCALE_DOMAIN_BITS + SCALE_NODE_BITS
SCALE_MAX_DOMAINS = 1 << SCALE_DOMAIN_BITS
SCALE_NODES_PER_DOMAIN = 1 << SCALE_NODE_BITS
SCALE_MAX_ENDPOINTS = SCALE_MAX_DOMAINS * SCALE_NODES_PER_DOMAIN
SCALE_MAX_ROUTE_STAGES = 5


def _put(value: int, field: int, lsb: int, width: int) -> int:
    if not 0 <= field < (1 << width):
        raise ValueError(f"field at bit {lsb} exceeds {width} bits")
    return value | (field << lsb)


def _get(value: int, lsb: int, width: int) -> int:
    return (value >> lsb) & ((1 << width) - 1)


@dataclass(frozen=True)
class ScaleEndpoint:
    """A 15-bit leaf-domain identifier plus a 5-bit local node identifier."""

    domain_id: int
    local_node: int

    def validate(self) -> None:
        if not 0 <= self.domain_id < SCALE_MAX_DOMAINS:
            raise ValueError("domain is outside the 15-bit address space")
        if not 0 <= self.local_node < SCALE_NODES_PER_DOMAIN:
            raise ValueError("node is outside the 32-node leaf domain")

    def encode(self) -> int:
        self.validate()
        return (self.domain_id << SCALE_NODE_BITS) | self.local_node

    @classmethod
    def decode(cls, value: int) -> "ScaleEndpoint":
        if not 0 <= value < SCALE_MAX_ENDPOINTS:
            raise ValueError("global endpoint is outside the 20-bit address space")
        return cls(domain_id=value >> SCALE_NODE_BITS, local_node=value & 0x1F)


@dataclass(frozen=True)
class ScaleDeploymentTopology:
    """Dense deployment of any population from one NPU through the 20-bit limit."""

    total_npus: int

    def validate(self) -> None:
        if not 1 <= self.total_npus <= SCALE_MAX_ENDPOINTS:
            raise ValueError("deployment NPU count must be from 1 through 1048576")

    @property
    def leaf_count(self) -> int:
        self.validate()
        return (self.total_npus + SCALE_NODES_PER_DOMAIN - 1) // SCALE_NODES_PER_DOMAIN

    @property
    def final_leaf_npu_count(self) -> int:
        self.validate()
        return self.total_npus - ((self.leaf_count - 1) * SCALE_NODES_PER_DOMAIN)

    @property
    def inter_domain_route_stages(self) -> int:
        return 0 if self.leaf_count == 1 else scale_route_stage_count(self.leaf_count)

    def leaf_npu_count(self, domain_id: int) -> int:
        if not 0 <= domain_id < self.leaf_count:
            raise ValueError("leaf domain is outside the active deployment")
        if domain_id == self.leaf_count - 1:
            return self.final_leaf_npu_count
        return SCALE_NODES_PER_DOMAIN

    def leaf_member_mask(self, domain_id: int) -> int:
        return (1 << self.leaf_npu_count(domain_id)) - 1

    def endpoint_for_ordinal(self, ordinal: int) -> ScaleEndpoint:
        self.validate()
        if not 0 <= ordinal < self.total_npus:
            raise ValueError("NPU ordinal is outside the active deployment")
        return ScaleEndpoint.decode(ordinal)

    def contains_endpoint(self, endpoint: ScaleEndpoint) -> bool:
        endpoint.validate()
        return endpoint.encode() < self.total_npus

    def ordinal_for_endpoint(self, endpoint: ScaleEndpoint) -> int:
        if not self.contains_endpoint(endpoint):
            raise ValueError("endpoint is outside the active deployment")
        return endpoint.encode()


@dataclass(frozen=True)
class ScaleRouteContext:
    """Schema-4 packet-scoped route metadata."""

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
    route_depth: int = 1
    reserved: int = 0

    def validate(self) -> None:
        ScaleEndpoint(self.source_domain, self.source_node).validate()
        ScaleEndpoint(self.destination_domain, self.destination_node).validate()
        if not 0 <= self.topology_epoch < (1 << 16):
            raise ValueError("topology epoch exceeds 16 bits")
        if not 1 <= self.domain_hop_limit < (1 << 8):
            raise ValueError("domain hop limit must be from 1 through 255")
        if not 0 <= self.logical_plane < 8:
            raise ValueError("logical plane exceeds three bits")
        if not 1 <= self.slice_mask < 4:
            raise ValueError("slice mask must enable at least one bonded slice")
        if self.route_policy != 0:
            raise ValueError("only deterministic escape policy is implemented")
        if not 1 <= self.packet_flit_count <= 16:
            raise ValueError("packet flit count must be from 1 through 16")
        if not 0 <= self.expected_packet_sequence < (1 << 12):
            raise ValueError("packet sequence exceeds 12 bits")
        if not 0 <= self.global_transaction_id < (1 << 64):
            raise ValueError("global transaction identifier exceeds 64 bits")
        if not 0 <= self.group_id < (1 << 32):
            raise ValueError("group identifier exceeds 32 bits")
        if not 0 <= self.logical_vc <= 5:
            raise ValueError("logical VC must be from VC0 through VC5")
        if not 1 <= self.route_depth <= SCALE_MAX_ROUTE_STAGES:
            raise ValueError("route depth must be from one through five")
        if self.reserved != 0:
            raise ValueError("reserved route-context bits must be zero")

    def encode(self) -> int:
        self.validate()
        value = 0
        value = _put(value, self.source_domain, 0, 15)
        value = _put(value, self.destination_domain, 15, 15)
        value = _put(value, self.source_node, 30, 5)
        value = _put(value, self.destination_node, 35, 5)
        value = _put(value, self.topology_epoch, 40, 16)
        value = _put(value, self.domain_hop_limit, 56, 8)
        value = _put(value, self.logical_plane, 64, 3)
        value = _put(value, self.slice_mask, 67, 2)
        value = _put(value, self.route_policy, 69, 3)
        value = _put(value, self.packet_flit_count, 72, 5)
        value = _put(value, self.expected_packet_sequence, 77, 12)
        value = _put(value, self.global_transaction_id, 89, 64)
        value = _put(value, self.group_id, 153, 32)
        value = _put(value, self.logical_vc, 185, 3)
        value = _put(value, self.route_depth, 188, 3)
        value = _put(value, self.reserved, 191, 321)
        return value

    @classmethod
    def decode(cls, value: int) -> "ScaleRouteContext":
        if not 0 <= value < (1 << 512):
            raise ValueError("route context exceeds 512 bits")
        return cls(
            source_domain=_get(value, 0, 15),
            destination_domain=_get(value, 15, 15),
            source_node=_get(value, 30, 5),
            destination_node=_get(value, 35, 5),
            topology_epoch=_get(value, 40, 16),
            domain_hop_limit=_get(value, 56, 8),
            logical_plane=_get(value, 64, 3),
            slice_mask=_get(value, 67, 2),
            route_policy=_get(value, 69, 3),
            packet_flit_count=_get(value, 72, 5),
            expected_packet_sequence=_get(value, 77, 12),
            global_transaction_id=_get(value, 89, 64),
            group_id=_get(value, 153, 32),
            logical_vc=_get(value, 185, 3),
            route_depth=_get(value, 188, 3),
            reserved=_get(value, 191, 321),
        )


@dataclass(frozen=True)
class ScaleGlobalCommit:
    """Schema-4 exact-once destination commit message payload."""

    source_domain: int
    destination_domain: int
    source_node: int
    destination_node: int
    topology_epoch: int
    global_transaction_id: int
    status: int
    reserved: int = 0

    def validate(self) -> None:
        ScaleEndpoint(self.source_domain, self.source_node).validate()
        ScaleEndpoint(self.destination_domain, self.destination_node).validate()
        if not 0 <= self.topology_epoch < (1 << 16):
            raise ValueError("topology epoch exceeds 16 bits")
        if not 0 <= self.global_transaction_id < (1 << 64):
            raise ValueError("global transaction identifier exceeds 64 bits")
        if not 0 <= self.status <= 2:
            raise ValueError("global commit status is reserved")
        if self.reserved != 0:
            raise ValueError("reserved global-commit bits must be zero")

    def encode(self) -> int:
        self.validate()
        value = 0
        value = _put(value, self.source_domain, 0, 15)
        value = _put(value, self.destination_domain, 15, 15)
        value = _put(value, self.source_node, 30, 5)
        value = _put(value, self.destination_node, 35, 5)
        value = _put(value, self.topology_epoch, 40, 16)
        value = _put(value, self.global_transaction_id, 56, 64)
        value = _put(value, self.status, 120, 2)
        value = _put(value, self.reserved, 122, 390)
        return value

    @classmethod
    def decode(cls, value: int) -> "ScaleGlobalCommit":
        if not 0 <= value < (1 << 512):
            raise ValueError("global commit exceeds 512 bits")
        return cls(
            source_domain=_get(value, 0, 15),
            destination_domain=_get(value, 15, 15),
            source_node=_get(value, 30, 5),
            destination_node=_get(value, 35, 5),
            topology_epoch=_get(value, 40, 16),
            global_transaction_id=_get(value, 56, 64),
            status=_get(value, 120, 2),
            reserved=_get(value, 122, 390),
        )


def scale_route_stage_count(domain_count: int) -> int:
    if not 2 <= domain_count <= SCALE_MAX_DOMAINS:
        raise ValueError("domain count must be from 2 through 32768")
    significant_bits = (domain_count - 1).bit_length()
    return max(1, (significant_bits + 2) // 3)


def scale_route_digits(destination_domain: int, domain_count: int) -> tuple[int, ...]:
    stage_count = scale_route_stage_count(domain_count)
    if not 0 <= destination_domain < domain_count:
        raise ValueError("destination domain is outside the active topology")
    return tuple((destination_domain >> (3 * (stage_count - stage - 1))) & 0x7 for stage in range(stage_count))


@dataclass(frozen=True)
class ScaleStageForward:
    stage_index: int
    egress: int
    context: ScaleRouteContext
    final_stage: bool
    escape_rank: int


def forward_scale_route_stage(
    context: ScaleRouteContext,
    *,
    domain_count: int,
    stage_index: int,
    active_egress_mask: int,
) -> ScaleStageForward:
    context.validate()
    digits = scale_route_digits(context.destination_domain, domain_count)
    if context.route_depth != len(digits):
        raise ValueError("route depth does not match the active topology")
    if not 0 <= stage_index < len(digits):
        raise ValueError("route stage index is outside the active topology")
    egress = digits[stage_index]
    if not active_egress_mask & (1 << egress):
        raise RuntimeError("selected route-stage egress is inactive")
    remaining_stages = len(digits) - stage_index
    if context.domain_hop_limit <= remaining_stages:
        raise RuntimeError("domain hop limit cannot reach the destination leaf")
    forwarded = ScaleRouteContext(**{
        **context.__dict__,
        "domain_hop_limit": context.domain_hop_limit - 1,
    })
    return ScaleStageForward(
        stage_index=stage_index,
        egress=egress,
        context=forwarded,
        final_stage=stage_index == len(digits) - 1,
        escape_rank=stage_index + 1,
    )


@dataclass(frozen=True)
class DistributedGroupNode:
    group_id: int
    topology_epoch: int
    level: int
    prefix: tuple[int, ...]
    child_mask: int
    local_member_mask: int
    subtree_member_count: int
    root_endpoint: int


class DistributedGroupDirectory:
    """Builds bounded eight-child state for a sparse or full logical group."""

    def __init__(self, domain_count: int) -> None:
        self.domain_count = domain_count
        self.depth = scale_route_stage_count(domain_count)
        self._groups: dict[tuple[int, int], dict[tuple[int, tuple[int, ...]], DistributedGroupNode]] = {}

    def configure(
        self,
        group_id: int,
        members: Sequence[ScaleEndpoint],
        topology_epoch: int,
        root: ScaleEndpoint,
    ) -> None:
        if not 0 <= group_id < (1 << 32):
            raise ValueError("group identifier exceeds 32 bits")
        if not 0 <= topology_epoch < (1 << 16):
            raise ValueError("topology epoch exceeds 16 bits")
        normalized = tuple(sorted(set(members), key=lambda endpoint: endpoint.encode()))
        if not normalized or len(normalized) != len(members):
            raise ValueError("group membership must be nonempty and unique")
        root.validate()
        if root not in normalized:
            raise ValueError("group root must be a member")
        if any(member.domain_id >= self.domain_count for member in normalized):
            raise ValueError("group member is outside the active topology")
        child_masks: dict[tuple[int, tuple[int, ...]], int] = {}
        subtree_counts: dict[tuple[int, tuple[int, ...]], int] = {}
        leaf_masks: dict[tuple[int, tuple[int, ...]], int] = {}
        for member in normalized:
            digits = scale_route_digits(member.domain_id, self.domain_count)
            for level, digit in enumerate(digits):
                key = (level, digits[:level])
                child_masks[key] = child_masks.get(key, 0) | (1 << digit)
                subtree_counts[key] = subtree_counts.get(key, 0) + 1
            leaf_key = (self.depth, digits)
            leaf_masks[leaf_key] = leaf_masks.get(leaf_key, 0) | (1 << member.local_node)
            subtree_counts[leaf_key] = subtree_counts.get(leaf_key, 0) + 1
        nodes: dict[tuple[int, tuple[int, ...]], DistributedGroupNode] = {}
        for key in set(child_masks) | set(leaf_masks):
            level, prefix = key
            nodes[key] = DistributedGroupNode(
                group_id=group_id,
                topology_epoch=topology_epoch,
                level=level,
                prefix=prefix,
                child_mask=child_masks.get(key, 0),
                local_member_mask=leaf_masks.get(key, 0),
                subtree_member_count=subtree_counts[key],
                root_endpoint=root.encode(),
            )
        self._groups[(group_id, topology_epoch)] = nodes

    def lookup(self, group_id: int, topology_epoch: int, level: int, prefix: Sequence[int]) -> DistributedGroupNode:
        group = self._groups.get((group_id, topology_epoch))
        if group is None:
            raise KeyError("group generation is not configured")
        node = group.get((level, tuple(prefix)))
        if node is None:
            raise KeyError("group has no member in this hierarchy node")
        return node


def select_scale_plane(global_transaction_id: int, active_plane_mask: int, allow_adaptive: bool = True) -> int:
    if not allow_adaptive:
        if not active_plane_mask & 0x1:
            raise RuntimeError("deterministic escape plane is inactive")
        return 0
    adaptive = [plane for plane in range(1, 8) if active_plane_mask & (1 << plane)]
    if adaptive:
        return adaptive[global_transaction_id % len(adaptive)]
    if active_plane_mask & 0x1:
        return 0
    raise RuntimeError("no active KDLink plane")
