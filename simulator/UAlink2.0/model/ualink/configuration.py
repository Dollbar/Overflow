"""WP01 configuration arithmetic for Common 2.0 + Manageability 1.0.

These checks are necessary, not sufficient, for a deployable profile. In
particular, they do not assign management/security PortNum identities or prove
that a switch supports every required bifurcation mode at this instance size.
"""

from collections.abc import Sequence
from dataclasses import dataclass


def _checked_index(index: int, limit: int) -> int:
    """Reject unused/noninteger encodings instead of truncating or aliasing."""
    if type(index) is not int:
        raise TypeError("an internal index must be an integer, not a boolean")
    if not 0 <= index < limit:
        raise ValueError("internal index is outside the configured resource count")
    return index


@dataclass(frozen=True)
class StationLayout:
    """One device's immutable selected-mode, fully populated station layout.

    Lane ordering is a contiguous internal modeling convention. Constructing a
    second layout does not perform or authorize live hardware reconfiguration.
    """

    num_stations: int
    bifurcation: str

    def __post_init__(self) -> None:
        if type(self.num_stations) is not int:
            raise TypeError("num_stations must be an integer, not a boolean")
        if self.num_stations < 1:
            raise ValueError("num_stations must be positive")
        if not isinstance(self.bifurcation, str):
            raise TypeError("bifurcation must be a symbolic string")
        if self.bifurcation not in ("x4", "2x2", "4x1"):
            raise ValueError("bifurcation must be x4, 2x2 or 4x1")
        if self.num_ports > 1024:
            raise ValueError("Manageability 1.0 permits at most 1024 ports per device")

    @property
    def ports_per_station(self) -> int:
        return {"x4": 1, "2x2": 2, "4x1": 4}[self.bifurcation]

    @property
    def lanes_per_port(self) -> int:
        return 4 // self.ports_per_station

    @property
    def num_lanes(self) -> int:
        return 4 * self.num_stations

    @property
    def num_ports(self) -> int:
        return self.ports_per_station * self.num_stations

    @property
    def station_index_width(self) -> int:
        """Internal RTL-friendly width, not a protocol identifier field width."""
        return max(1, (self.num_stations - 1).bit_length())

    def split_port_index(self, index: int) -> tuple[int, int]:
        """Return (station index, station-local port) from an internal index."""
        return divmod(_checked_index(index, self.num_ports), self.ports_per_station)

    def lane_assignment(self, index: int) -> tuple[int, int, int]:
        """Return (station index, local port, lane in port) in model ordering."""
        station, station_lane = divmod(_checked_index(index, self.num_lanes), 4)
        port, port_lane = divmod(station_lane, self.lanes_per_port)
        return station, port, port_lane


def validate_pod(accelerators: Sequence[StationLayout], switches: Sequence[StationLayout]) -> None:
    """Check count/topology prerequisites for a switched Pod test fixture.

    C §2.4: same Pod bifurcation, equal accelerator port counts, and each
    physical switch has at least as many ports as there are accelerators.
    M §1.4: at most 1024 accelerators and 1024 physical switches. Nonempty
    device lists are a fixture precondition, not an additional protocol SHALL.
    This is not route-table, reachability, ID uniqueness or security validation.
    """
    if not isinstance(accelerators, Sequence) or not isinstance(switches, Sequence):
        raise TypeError("Pod device lists must be sequences of StationLayout")
    if not 1 <= len(accelerators) <= 1024 or not 1 <= len(switches) <= 1024:
        raise ValueError("this managed switched-Pod fixture needs 1..1024 devices per role")
    devices = tuple(accelerators) + tuple(switches)
    if any(not isinstance(device, StationLayout) for device in devices):
        raise TypeError("each device must be a validated StationLayout")
    if any(device.bifurcation != accelerators[0].bifurcation for device in devices):
        raise ValueError("all stations in a Pod must use the same bifurcation")
    if any(device.num_ports != accelerators[0].num_ports for device in accelerators):
        raise ValueError("all accelerators in a Pod must have equal port counts")
    if any(device.num_ports < len(accelerators) for device in switches):
        raise ValueError("a physical switch needs at least one port per accelerator")
