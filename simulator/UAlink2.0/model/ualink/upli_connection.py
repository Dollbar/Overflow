"""C 4.1-4.3 registered, synchronous UPLI connection reference controller."""

from dataclasses import dataclass


@dataclass(frozen=True)
class ConnectionSignals:
    """Stable local interface levels, NOT permission to change clock frequency."""

    orig_req: bool = False
    comp_ack: bool = False
    comp_req: bool = False
    orig_ack: bool = False

    def __post_init__(self):
        if any(type(value) is not bool for value in (self.orig_req, self.comp_ack, self.comp_req, self.orig_ack)):
            raise TypeError("connection levels must be booleans")

    @property
    def orig_connected(self) -> bool:
        return self.orig_req and self.comp_ack

    @property
    def comp_connected(self) -> bool:
        return self.comp_req and self.orig_ack

    @property
    def beats_enabled(self) -> bool:
        return self.orig_connected and self.comp_connected


class UpliConnection:
    """One local UPLI interface, with one-cycle reset clearing/registered ACK.

    Readiness requests new connections; it cannot retract a prior acceptance
    promise. The surrounding platform must retain that capability until reset.
    """

    def __init__(self, min_reset_cycles: int = 1, completer_waits: bool = False):
        if type(min_reset_cycles) is not int:
            raise TypeError("min_reset_cycles must be an integer")
        if min_reset_cycles < 1:
            raise ValueError("at least one synchronous reset edge is required")
        if type(completer_waits) is not bool:
            raise TypeError("completer_waits must be a boolean")
        self.min_reset_cycles = min_reset_cycles
        self.completer_waits = completer_waits
        self.signals = ConnectionSignals()
        self._reset_low_cycles = 0
        self._reset_n = False

    def step(self, reset_n: bool, orig_ready: bool, comp_ready: bool) -> ConnectionSignals:
        """Sample one rising edge and return the next cycle's stable levels."""
        if any(type(value) is not bool for value in (reset_n, orig_ready, comp_ready)):
            raise TypeError("reset and readiness levels must be booleans")
        if not reset_n:
            self._reset_low_cycles += 1
            self._reset_n = False
            self.signals = ConnectionSignals()
        elif not self._reset_n:
            if self._reset_low_cycles < self.min_reset_cycles:
                raise ValueError("UPLI reset has not met the selected minimum hold")
            self._reset_n = True
            self._reset_low_cycles = 0
            self.signals = ConnectionSignals()
        else:
            previous = self.signals
            self.signals = ConnectionSignals(
                orig_req=previous.orig_req or orig_ready,
                comp_ack=previous.comp_ack or (comp_ready and previous.orig_req),
                comp_req=previous.comp_req or (comp_ready and (not self.completer_waits or previous.orig_connected)),
                orig_ack=previous.orig_ack or (orig_ready and previous.comp_req),
            )
        return self.signals
