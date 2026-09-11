"""Common 2.6 initial credit publication, one UPLI channel per instance.

The reference pre-expands immutable per-port publication schedules instead of
sharing an RTL remaining-counter state machine. step returns registered levels
for the following sampling edge; consumers must use the previous outputs.
"""

from dataclasses import dataclass

from .upli_connection import ConnectionSignals
from .upli_credit import CHANNELS, CreditReturn


@dataclass(frozen=True)
class InitialCreditSignals:
    returns: tuple[CreditReturn, ...] = ()
    done: int = 0


class InitialCreditPublisher:
    """Advertise actual configured receiver resources once per interface reset.

    Each zero-capacity account occupies one idle scanning cycle. A nonzero
    account emits consecutive batches of up to four, then advances to the next
    account. VC0..3 precede the shared pool; the pool's initial VC field is zero.
    Legal connections stay asserted until reset; withdrawal is a model error,
    not an invented on-wire recovery protocol.
    """

    def __init__(self, capacities, num_ports, width=4, channel="req"):
        if type(num_ports) is not int or type(width) is not int:
            raise TypeError("port count and width must be integers")
        if num_ports not in (1, 2, 4) or not 3 <= width <= 16:
            raise ValueError("requires ports 1/2/4 and local credit width 3..16")
        if channel not in CHANNELS:
            raise ValueError("unknown UPLI channel")
        capacities = tuple(capacities)
        if len(capacities) != num_ports*5:
            raise ValueError("requires five capacity values per port")
        for capacity in capacities:
            if type(capacity) is not int:
                raise TypeError("capacity must be an integer")
            if not 0 <= capacity < (1 << width):
                raise ValueError("capacity does not fit declared width")
        schedules = []
        for port in range(num_ports):
            sequence = []
            for account, capacity in enumerate(capacities[port*5:port*5+5]):
                if capacity == 0:
                    sequence.append(None)
                for start in range(0, capacity, 4):
                    sequence.append(CreditReturn(port, channel, 0 if account == 4 else account,
                                                 account == 4, min(4, capacity-start)-1))
            schedules.append(tuple(sequence))
        self._channel = channel
        self._schedules = tuple(schedules)
        self._positions = (0,)*num_ports
        self._connected_once = False
        self._outputs = InitialCreditSignals()

    @property
    def outputs(self):
        """Current stable registered output levels; no advancement on read."""
        return self._outputs

    def step(self, connection, reset=False):
        if type(reset) is not bool:
            raise TypeError("reset must be a boolean")
        if reset:
            self._positions = (0,)*len(self._schedules)
            self._connected_once = False
            self._outputs = InitialCreditSignals()
            return self._outputs
        if not isinstance(connection, ConnectionSignals):
            raise TypeError("a stable ConnectionSignals snapshot is required")
        allowed = (connection.comp_connected if self._channel in ("req", "orig_data")
                   else connection.orig_connected)
        if self._connected_once and not allowed:
            raise ValueError("credit direction cannot withdraw before UPLI reset")
        if not allowed:
            return self._outputs
        returns, positions, done = [], [], 0
        for port, (position, sequence) in enumerate(zip(self._positions, self._schedules)):
            if position == len(sequence):
                done |= 1 << port
                positions.append(position)
            else:
                event = sequence[position]
                if event is not None:
                    returns.append(event)
                positions.append(position+1)
        self._positions = tuple(positions)
        self._connected_once = True
        self._outputs = InitialCreditSignals(tuple(returns), done)
        return self._outputs
