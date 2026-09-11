"""Common 2.6 normal-return metadata queue; not a payload buffer or wire decoder.

Deque state is independent of the RTL slot-shift implementation. A returned
event is a newly registered bus level sampled by its peer on the following edge.
"""

from collections import deque
from dataclasses import dataclass

from .upli_credit import Beat, CHANNELS, CreditReturn


@dataclass(frozen=True)
class ReturnStep:
    accepted: bool = False
    returns: tuple[CreditReturn, ...] = ()


class CreditReturnQueue:
    """Accept saved retired-beat metadata; combine only equal adjacent records.

    enable_mask reserves next-cycle output slots, not cancellation of previously
    driven returns. Capacity excludes an already registered in-flight batch.
    """

    def __init__(self, num_ports, depth, channel="req"):
        if type(num_ports) is not int or type(depth) is not int:
            raise TypeError("port count and depth must be integers")
        if num_ports not in (1, 2, 4) or not 1 <= depth <= 16:
            raise ValueError("requires ports 1/2/4 and depth 1..16")
        if channel not in CHANNELS:
            raise ValueError("unknown UPLI channel")
        self._channel = channel
        self._depth = depth
        self._queues = [deque() for _ in range(num_ports)]
        self._outputs = ()

    def ready(self, port):
        if type(port) is not int:
            raise TypeError("port must be an integer")
        if not 0 <= port < 4:
            raise ValueError("physical metadata port must fit two bits")
        return port < len(self._queues) and len(self._queues[port]) < self._depth

    @property
    def pending(self):
        return tuple(len(queue) for queue in self._queues)

    @property
    def outputs(self):
        return self._outputs

    def step(self, retired=None, enable_mask=0, reset=False):
        if type(reset) is not bool:
            raise TypeError("reset must be a boolean")
        if reset:
            self._queues = [deque() for _ in self._queues]
            self._outputs = ()
            return ReturnStep()
        if type(enable_mask) is not int:
            raise TypeError("enable mask must be an integer")
        if not 0 <= enable_mask < 16:
            raise ValueError("enable mask must fit four ports")
        accepted = False
        if retired is not None:
            if not isinstance(retired, Beat):
                raise TypeError("retirement must carry saved Beat metadata")
            if retired.channel != self._channel:
                raise ValueError("retirement belongs to another channel")
            if type(retired.vc) is not int or type(retired.pool) is not bool:
                raise TypeError("VC must be integer and pool must be boolean")
            if not 0 <= retired.vc < 4:
                raise ValueError("saved VC must fit two bits, including pool returns")
            accepted = self.ready(retired.port)
        # Validation is complete before the first queue or output mutation.
        grants = []
        for port, queue in enumerate(self._queues):
            if enable_mask & (1 << port) and queue:
                head, amount = queue[0], 0
                while queue and queue[0] == head and amount < 4:
                    queue.popleft()
                    amount += 1
                grants.append(CreditReturn(port, self._channel, head.vc, head.pool, amount-1))
        if accepted:
            self._queues[retired.port].append(retired)
        self._outputs = tuple(grants)
        return ReturnStep(accepted, self._outputs)
