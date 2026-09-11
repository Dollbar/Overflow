"""Passive normal OrigData trace checker using independent absolute deadlines.

Shares value types, not scheduling/admission code, with UpliBurstSender. Does
not validate credit balances, command/address legality or recovery truncation.
"""

from copy import deepcopy

from .upli_burst import BurstData, BurstRequest
from .upli_tdm import UpliTdm


class UpliBurstMonitor:
    """Check one normal burst per port and all required data slots, even idle."""

    def __init__(self, num_ports: int):
        self._tdm = UpliTdm(num_ports)
        self.num_ports = num_ports
        self._cycle = 0
        self._pending = {}  # port -> (VC, remaining offsets, absolute due cycle)

    def _identity(self, port, vc, pool):
        if type(port) is not int or type(vc) is not int or type(pool) is not bool:
            raise TypeError("port/VC must be integers and Pool must be boolean")
        if not 0 <= port < self.num_ports or not 0 <= vc < 4:
            raise ValueError("port or VC outside the active interface range")

    def step(self, request=None, data=None, reset: bool = False) -> None:
        """Inspect observed wire metadata; a rejected edge does not advance time."""
        if type(reset) is not bool:
            raise TypeError("reset must be a boolean")
        if reset:
            self._tdm.step(reset=True)
            self._pending, self._cycle = {}, 0
            return
        if request is not None:
            if not isinstance(request, BurstRequest):
                raise TypeError("request metadata must be BurstRequest")
            self._identity(request.port, request.vc, request.pool)
            if request.num_beats is not None:
                if type(request.num_beats) is not int:
                    raise TypeError("ReqNumBeats must be an integer encoding")
                if not 0 <= request.num_beats <= 3:
                    raise ValueError("ReqNumBeats must fit two bits")
        if data is not None:
            if not isinstance(data, BurstData):
                raise TypeError("OrigData metadata must be BurstData")
            self._identity(data.port, data.vc, data.pool)
            if type(data.offset) is not int or type(data.last) is not bool:
                raise TypeError("Offset must be integer and Last must be boolean")
            if not 0 <= data.offset <= 3:
                raise ValueError("OrigDataOffset must fit two bits")
        pending = dict(self._pending)
        due = [port for port, (_, _, deadline) in pending.items() if deadline <= self._cycle]
        if len(due) > 1:
            raise ValueError("multiple bursts cannot be due on one physical OrigData bus")
        starts = request is not None and request.num_beats is not None
        if starts and request.port in pending:
            raise ValueError("new data request overlaps an unfinished burst on its port")
        expected = None
        if due:
            port = due[0]
            vc, offsets, deadline = pending[port]
            if deadline != self._cycle:
                raise ValueError("an earlier mandatory data deadline was missed")
            expected = port, vc, offsets[0], len(offsets) == 1
        if starts:
            if due:
                raise ValueError("new first data and previous data cannot share one bus slot")
            expected = request.port, request.vc, 0, request.num_beats == 0
        if expected is None:
            if data is not None:
                raise ValueError("OrigData has no corresponding request or scheduled burst")
        elif data is None or (data.port, data.vc, data.offset, data.last) != expected:
            raise ValueError("missing or incorrect scheduled OrigData port/VC/offset/Last")
        if due:
            port = due[0]
            vc, offsets, deadline = pending[port]
            if len(offsets) == 1:
                del pending[port]
            else:
                pending[port] = vc, offsets[1:], deadline + self.num_ports
        if starts and request.num_beats:
            pending[request.port] = (request.vc, tuple(range(1, request.num_beats + 1)),
                                     self._cycle + self.num_ports)
        observed = []
        if request is not None:
            observed.append(("req", request.port))
        if data is not None:
            observed.append(("orig_data", data.port))
        tdm = deepcopy(self._tdm)
        tdm.step(observed)
        self._tdm, self._pending = tdm, pending
        self._cycle += 1
