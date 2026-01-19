"""Packet-level dual-slice striping and receive reordering model."""

from __future__ import annotations

from dataclasses import dataclass, field

from .constants import PACKET_SEQUENCE_MODULUS, SLICES_PER_PORT


@dataclass
class BondedPortDistributor:
    active_mask: int = (1 << SLICES_PER_PORT) - 1
    next_index: int = 0

    def active_slices(self) -> tuple[int, ...]:
        return tuple(index for index in range(SLICES_PER_PORT) if self.active_mask & (1 << index))

    def assign(self, packet_seq: int) -> int:
        if not 0 <= packet_seq < PACKET_SEQUENCE_MODULUS:
            raise ValueError("packet sequence is outside the KDLink sequence space")
        active = self.active_slices()
        if not active:
            raise RuntimeError("bonded port has no active slice")
        selected = active[self.next_index % len(active)]
        self.next_index = (self.next_index + 1) % len(active)
        return selected

    def disable(self, slice_id: int) -> None:
        if not 0 <= slice_id < SLICES_PER_PORT:
            raise ValueError("invalid slice")
        self.active_mask &= ~(1 << slice_id)
        self.next_index = 0


@dataclass
class BondedPortReorder:
    expected_seq: int = 0
    pending: dict[int, bytes] = field(default_factory=dict)

    def accept(self, packet_seq: int, payload: bytes) -> list[tuple[int, bytes]]:
        if not 0 <= packet_seq < PACKET_SEQUENCE_MODULUS:
            raise ValueError("packet sequence is outside the KDLink sequence space")
        if packet_seq in self.pending:
            raise RuntimeError("duplicate packet in reorder window")
        distance = (packet_seq - self.expected_seq) % PACKET_SEQUENCE_MODULUS
        if distance >= PACKET_SEQUENCE_MODULUS // 2:
            raise RuntimeError("stale packet outside reorder window")
        self.pending[packet_seq] = payload
        released: list[tuple[int, bytes]] = []
        while self.expected_seq in self.pending:
            sequence = self.expected_seq
            released.append((sequence, self.pending.pop(sequence)))
            self.expected_seq = (self.expected_seq + 1) % PACKET_SEQUENCE_MODULUS
        return released
