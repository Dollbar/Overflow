"""Configurable card packing for one fixed 32-NPU KDLink leaf domain."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable


NODES_PER_LEAF = 32
MAX_CARD_SLOTS = 32
DEFAULT_NPUS_PER_CARD = 4
SUPPORTED_NPUS_PER_CARD = (1, 2, 4, 8, 16, 32)
PLANES_PER_NPU = 8
SLICES_PER_PORT = 2
SLICES_PER_NPU = PLANES_PER_NPU * SLICES_PER_PORT


@dataclass(frozen=True)
class CardDescriptor:
    """Stable node range owned by one physical card slot."""

    slot_id: int
    base_node_id: int
    npu_count: int

    @property
    def node_limit(self) -> int:
        return self.base_node_id + self.npu_count

    @property
    def npu_count_code(self) -> int:
        return self.npu_count.bit_length() - 1


@dataclass(frozen=True)
class CardNodeLocation:
    """Resolved physical-card location for one leaf node."""

    slot_id: int
    local_npu: int
    node_id: int
    npu_count: int


def homogeneous_card_layout(npus_per_card: int) -> tuple[CardDescriptor, ...]:
    """Build one of the six complete homogeneous 32-NPU layouts."""

    if npus_per_card not in SUPPORTED_NPUS_PER_CARD:
        raise ValueError("NPU count per card must be one of 1, 2, 4, 8, 16, or 32")
    return tuple(
        CardDescriptor(slot_id, slot_id * npus_per_card, npus_per_card)
        for slot_id in range(NODES_PER_LEAF // npus_per_card)
    )


def compact_card_layout(npu_count: int) -> tuple[CardDescriptor, ...]:
    """Pack an arbitrary one-through-32 NPU partial leaf into supported card profiles."""

    if not 1 <= npu_count <= NODES_PER_LEAF:
        raise ValueError("partial leaf NPU count must be from 1 through 32")
    descriptors: list[CardDescriptor] = []
    base_node_id = 0
    remaining = npu_count
    for card_npu_count in reversed(SUPPORTED_NPUS_PER_CARD):
        if card_npu_count <= remaining:
            descriptors.append(
                CardDescriptor(
                    slot_id=len(descriptors),
                    base_node_id=base_node_id,
                    npu_count=card_npu_count,
                )
            )
            base_node_id += card_npu_count
            remaining -= card_npu_count
    return tuple(descriptors)


def _validate_layout(
    descriptors: Iterable[CardDescriptor],
) -> tuple[tuple[CardDescriptor, ...], tuple[CardNodeLocation | None, ...]]:
    normalized = tuple(sorted(descriptors, key=lambda item: item.slot_id))
    if not normalized:
        raise ValueError("card layout must contain at least one configured slot")
    owners: list[CardNodeLocation | None] = [None] * NODES_PER_LEAF
    observed_slots: set[int] = set()
    for descriptor in normalized:
        if not 0 <= descriptor.slot_id < MAX_CARD_SLOTS:
            raise ValueError("card slot is outside the 32-slot leaf domain")
        if descriptor.slot_id in observed_slots:
            raise ValueError("card layout contains a duplicate slot")
        observed_slots.add(descriptor.slot_id)
        if descriptor.npu_count not in SUPPORTED_NPUS_PER_CARD:
            raise ValueError("card NPU count is not a supported power-of-two profile")
        if not 0 <= descriptor.base_node_id < NODES_PER_LEAF:
            raise ValueError("card base node is outside the 32-NPU leaf domain")
        if descriptor.node_limit > NODES_PER_LEAF:
            raise ValueError("card node range exceeds the 32-NPU leaf domain")
        for local_npu in range(descriptor.npu_count):
            node_id = descriptor.base_node_id + local_npu
            if owners[node_id] is not None:
                raise ValueError("card node ranges overlap")
            owners[node_id] = CardNodeLocation(
                descriptor.slot_id,
                local_npu,
                node_id,
                descriptor.npu_count,
            )
    return normalized, tuple(owners)


def _epoch_is_newer(candidate: int, active: int) -> bool:
    if not 0 <= candidate < (1 << 16) or not 0 <= active < (1 << 16):
        raise ValueError("topology epoch must be a 16-bit value")
    delta = (candidate - active) & 0xFFFF
    return delta != 0 and delta < 0x8000


class CardDirectory:
    """Atomic active/shadow card directory with stable node ownership."""

    def __init__(
        self,
        descriptors: Iterable[CardDescriptor] | None = None,
        topology_epoch: int = 0,
    ) -> None:
        active, owners = _validate_layout(
            homogeneous_card_layout(DEFAULT_NPUS_PER_CARD)
            if descriptors is None
            else descriptors
        )
        if not 0 <= topology_epoch < (1 << 16):
            raise ValueError("topology epoch must be a 16-bit value")
        self.active_descriptors = active
        self.active_owners = owners
        self.active_epoch = topology_epoch
        self.shadow_descriptors: tuple[CardDescriptor, ...] | None = None
        self.shadow_owners: tuple[CardNodeLocation | None, ...] | None = None
        self.shadow_epoch: int | None = None
        self.card_present = [True] * MAX_CARD_SLOTS
        self.card_reset_done = [True] * MAX_CARD_SLOTS

    def prepare(self, descriptors: Iterable[CardDescriptor], topology_epoch: int) -> None:
        normalized, owners = _validate_layout(descriptors)
        if not 0 <= topology_epoch < (1 << 16):
            raise ValueError("topology epoch must be a 16-bit value")
        self.shadow_descriptors = normalized
        self.shadow_owners = owners
        self.shadow_epoch = topology_epoch

    def commit(self, *, quiescent: bool) -> None:
        if self.shadow_descriptors is None or self.shadow_owners is None or self.shadow_epoch is None:
            raise RuntimeError("card directory has no prepared layout")
        if not quiescent:
            raise RuntimeError("card directory commit requires a quiescent leaf domain")
        if not _epoch_is_newer(self.shadow_epoch, self.active_epoch):
            raise RuntimeError("card directory topology epoch is stale")
        self.active_descriptors = self.shadow_descriptors
        self.active_owners = self.shadow_owners
        self.active_epoch = self.shadow_epoch
        self.shadow_descriptors = None
        self.shadow_owners = None
        self.shadow_epoch = None

    def node_location(self, node_id: int) -> CardNodeLocation:
        if not 0 <= node_id < NODES_PER_LEAF:
            raise ValueError("node is outside the 32-NPU leaf domain")
        location = self.active_owners[node_id]
        if location is None:
            raise ValueError("node is not mapped to a configured card")
        return location

    def set_card_state(
        self,
        slot_id: int,
        *,
        present: bool | None = None,
        reset_done: bool | None = None,
    ) -> None:
        if not 0 <= slot_id < MAX_CARD_SLOTS:
            raise ValueError("card slot is outside the 32-slot leaf domain")
        if present is not None:
            self.card_present[slot_id] = present
        if reset_done is not None:
            self.card_reset_done[slot_id] = reset_done

    def node_active(self, node_id: int) -> bool:
        try:
            location = self.node_location(node_id)
        except ValueError:
            return False
        return self.card_present[location.slot_id] and self.card_reset_done[location.slot_id]

    def endpoint_index(
        self,
        slot_id: int,
        local_npu: int,
        plane_id: int,
        slice_id: int,
    ) -> int:
        descriptor = next(
            (entry for entry in self.active_descriptors if entry.slot_id == slot_id),
            None,
        )
        if descriptor is None:
            raise ValueError("card slot is not configured in the active layout")
        if not 0 <= local_npu < descriptor.npu_count:
            raise ValueError("local NPU is outside the configured card")
        if not 0 <= plane_id < PLANES_PER_NPU:
            raise ValueError("plane is outside the leaf domain")
        if not 0 <= slice_id < SLICES_PER_PORT:
            raise ValueError("slice is outside the bonded port")
        node_id = descriptor.base_node_id + local_npu
        return node_id * SLICES_PER_NPU + plane_id * SLICES_PER_PORT + slice_id

    def decode_endpoint(self, endpoint_index: int) -> tuple[CardNodeLocation, int, int]:
        if not 0 <= endpoint_index < NODES_PER_LEAF * SLICES_PER_NPU:
            raise ValueError("endpoint slice is outside the leaf domain")
        node_id, bank_id = divmod(endpoint_index, SLICES_PER_NPU)
        plane_id, slice_id = divmod(bank_id, SLICES_PER_PORT)
        return self.node_location(node_id), plane_id, slice_id
