"""Versioned eight-card KDLink-v2 chassis topology and digital fault state."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from .constants import NUM_NODES, NUM_PLANES


CARD_SLOTS = 8
NPUS_PER_CARD = 4
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
    """Map 32 NPU endpoints onto eight card slots and eight switch planes."""

    def __init__(self) -> None:
        self.cards = [CardSlot(slot_id=index) for index in range(CARD_SLOTS)]
        self.plane_enable = [True] * NUM_PLANES
        self.links = [SliceLink() for _ in range(NUM_NODES * SLICES_PER_NPU)]

    @staticmethod
    def endpoint_index(slot_id: int, local_npu: int, plane_id: int, slice_id: int) -> int:
        if not 0 <= slot_id < CARD_SLOTS:
            raise ValueError("slot is outside the eight-card chassis")
        if not 0 <= local_npu < NPUS_PER_CARD:
            raise ValueError("local NPU is outside the card")
        if not 0 <= plane_id < NUM_PLANES:
            raise ValueError("plane is outside the baseboard")
        if not 0 <= slice_id < SLICES_PER_PORT:
            raise ValueError("slice is outside the bonded port")
        node_id = slot_id * NPUS_PER_CARD + local_npu
        return node_id * SLICES_PER_NPU + plane_id * SLICES_PER_PORT + slice_id

    @staticmethod
    def decode_endpoint(endpoint_index: int) -> EndpointLocation:
        if not 0 <= endpoint_index < NUM_NODES * SLICES_PER_NPU:
            raise ValueError("endpoint slice is outside the chassis")
        node_id, bank_id = divmod(endpoint_index, SLICES_PER_NPU)
        plane_id, slice_id = divmod(bank_id, SLICES_PER_PORT)
        slot_id, local_npu = divmod(node_id, NPUS_PER_CARD)
        return EndpointLocation(slot_id, local_npu, node_id, plane_id, slice_id, endpoint_index)

    def endpoint_available(self, endpoint_index: int) -> bool:
        location = self.decode_endpoint(endpoint_index)
        return (
            self.cards[location.slot_id].active
            and self.plane_enable[location.plane_id]
            and self.links[endpoint_index].state is LinkState.UP
        )

    def remove_card(self, slot_id: int) -> None:
        if not 0 <= slot_id < CARD_SLOTS:
            raise ValueError("slot is outside the eight-card chassis")
        self.cards[slot_id].present = False

    def disable_plane(self, plane_id: int) -> None:
        if not 0 <= plane_id < NUM_PLANES:
            raise ValueError("plane is outside the baseboard")
        self.plane_enable[plane_id] = False

    def fail_lane(self, endpoint_index: int, lane_id: int) -> None:
        if not 0 <= lane_id < PCS_LANES:
            raise ValueError("lane is outside the slice")
        self.decode_endpoint(endpoint_index)
        self.links[endpoint_index].lane_up[lane_id] = False
