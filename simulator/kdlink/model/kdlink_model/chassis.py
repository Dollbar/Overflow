"""Configurable-card KDLink leaf-domain topology and digital fault state."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from .card_topology import (
    DEFAULT_NPUS_PER_CARD,
    MAX_CARD_SLOTS,
    CardDescriptor,
    CardDirectory,
    homogeneous_card_layout,
)
from .constants import NUM_NODES, NUM_PLANES


CARD_SLOTS = MAX_CARD_SLOTS
NPUS_PER_CARD = DEFAULT_NPUS_PER_CARD
SLICES_PER_PORT = 2
SLICES_PER_NPU = NUM_PLANES * SLICES_PER_PORT
PCS_LANES = 10


class LinkState(str, Enum):
    DOWN = "down"
    TRAINING = "training"
    UP = "up"
    DEGRADED = "degraded"


@dataclass(frozen=True)
class EndpointLocation:
    slot_id: int
    local_npu: int
    node_id: int
    plane_id: int
    slice_id: int
    endpoint_index: int


@dataclass
class SliceLink:
    admin_up: bool = True
    lane_up: list[bool] = field(default_factory=lambda: [True] * PCS_LANES)
    training_complete: bool = True

    @property
    def state(self) -> LinkState:
        available = sum(self.lane_up)
        if not self.admin_up or available == 0:
            return LinkState.DOWN
        if available != PCS_LANES:
            return LinkState.DEGRADED
        if not self.training_complete:
            return LinkState.TRAINING
        return LinkState.UP


@dataclass
class CardSlot:
    slot_id: int
    present: bool = True
    reset_done: bool = True

    @property
    def active(self) -> bool:
        return self.present and self.reset_done


class ChassisTopology:
    """Map 32 NPU endpoints onto configurable card slots and eight switch planes."""

    def __init__(
        self,
        npus_per_card: int = DEFAULT_NPUS_PER_CARD,
        descriptors: tuple[CardDescriptor, ...] | None = None,
    ) -> None:
        layout = homogeneous_card_layout(npus_per_card) if descriptors is None else descriptors
        self.directory = CardDirectory(layout)
        self.cards = [CardSlot(slot_id=index) for index in range(CARD_SLOTS)]
        self.plane_enable = [True] * NUM_PLANES
        self.links = [SliceLink() for _ in range(NUM_NODES * SLICES_PER_NPU)]

    def endpoint_index(self, slot_id: int, local_npu: int, plane_id: int, slice_id: int) -> int:
        return self.directory.endpoint_index(slot_id, local_npu, plane_id, slice_id)

    def decode_endpoint(self, endpoint_index: int) -> EndpointLocation:
        location, plane_id, slice_id = self.directory.decode_endpoint(endpoint_index)
        return EndpointLocation(
            location.slot_id,
            location.local_npu,
            location.node_id,
            plane_id,
            slice_id,
            endpoint_index,
        )

    def endpoint_available(self, endpoint_index: int) -> bool:
        location = self.decode_endpoint(endpoint_index)
        return (
            self.directory.node_active(location.node_id)
            and self.cards[location.slot_id].active
            and self.plane_enable[location.plane_id]
            and self.links[endpoint_index].state is LinkState.UP
        )

    def remove_card(self, slot_id: int) -> None:
        if not 0 <= slot_id < CARD_SLOTS:
            raise ValueError("slot is outside the 32-slot leaf domain")
        self.cards[slot_id].present = False
        self.directory.set_card_state(slot_id, present=False)

    def disable_plane(self, plane_id: int) -> None:
        if not 0 <= plane_id < NUM_PLANES:
            raise ValueError("plane is outside the baseboard")
        self.plane_enable[plane_id] = False

    def fail_lane(self, endpoint_index: int, lane_id: int) -> None:
        if not 0 <= lane_id < PCS_LANES:
            raise ValueError("lane is outside the slice")
        self.decode_endpoint(endpoint_index)
        self.links[endpoint_index].lane_up[lane_id] = False
