"""C 2.5/2.6/2.7.8 normal OrigData burst scheduling and credit reservation.

Descriptors assume payload is already staged. No command/address decoder,
physical payload FIFO, response scheduler or exceptional burst termination.
"""

from copy import deepcopy
from dataclasses import dataclass

from .upli_connection import ConnectionSignals
from .upli_credit import Account, Beat, UpliCreditLedger


@dataclass(frozen=True)
class BurstRequest:
    """Internal candidate, not a full UPLI wire request or a new ready signal."""

    port: int
    vc: int
    pool: bool = False
    num_beats: int | None = None  # None: read-class, no OrigData transfer.
    data_pools: tuple[bool, ...] = ()  # Preselected allocation; not wire fields.


@dataclass(frozen=True)
class BurstData:
    port: int
    vc: int
    pool: bool
    offset: int
    last: bool


@dataclass(frozen=True)
class BurstEvents:
    request: BurstRequest | None
    data: BurstData | None

    @property
    def accepted(self) -> bool:
        return self.request is not None

    @property
    def beats(self) -> tuple[Beat, ...]:
        events = []
        if self.request is not None:
            req = self.request
            events.append(Beat(req.port, "req", req.vc, req.pool))
        if self.data is not None:
            data = self.data
            events.append(Beat(data.port, "orig_data", data.vc, data.pool))
        return tuple(events)


class UpliBurstSender:
    """One burst per independent port, with no new-credit/init bypass."""

    def __init__(self, capacities, num_ports: int, init_stable_cycles: int = 2):
        self._credits = UpliCreditLedger(capacities, num_ports, init_stable_cycles)
        self.num_ports = num_ports
        self._phase = None
        self._active: dict[int, tuple[BurstRequest, int]] = {}

    @property
    def next_port(self) -> int | None:
        return self._phase

    def balance(self, account: Account) -> int:
        return self._credits.balance(account)

    def initialized(self, port: int, channel: str) -> bool:
        return self._credits.initialized(port, channel)

    def reserved(self, account: Account) -> int:
        self._credits.balance(account)  # Validate even zero/unconfigured accounts.
        if account.channel != "orig_data" or account.port not in self._active:
            return 0
        request, offset = self._active[account.port]
        if account.vc is not None and account.vc != request.vc:
            return 0
        return request.data_pools[offset:].count(account.vc is None)

    def available(self, account: Account) -> int:
        return self.balance(account) - self.reserved(account)

    def _validate_request(self, request):
        if not isinstance(request, BurstRequest):
            raise TypeError("request must be a BurstRequest candidate")
        if type(request.vc) is not int or type(request.pool) is not bool:
            raise TypeError("VC must be integer and Pool must be boolean")
        self._credits.balance(Account(request.port, "req", request.vc))
        if not isinstance(request.data_pools, tuple) or any(type(p) is not bool for p in request.data_pools):
            raise TypeError("data_pools must be an immutable tuple of booleans")
        if request.num_beats is None:
            if request.data_pools:
                raise ValueError("a read-class request cannot reserve OrigData")
        else:
            if type(request.num_beats) is not int:
                raise TypeError("ReqNumBeats encoding must be an integer")
            if not 0 <= request.num_beats < 4:
                raise ValueError("ReqNumBeats encoding must fit two bits")
            if len(request.data_pools) != request.num_beats + 1:
                raise ValueError("each OrigData beat needs a declared credit allocation")

    def _eligible(self, connection, request, phase):
        if not connection.beats_enabled or request.port != phase:
            return False
        if not self.initialized(request.port, "req"):
            return False
        req_account = Account(request.port, "req", None if request.pool else request.vc)
        if self.available(req_account) < 1:
            return False
        if request.num_beats is None:
            return True
        if request.port in self._active or not self.initialized(request.port, "orig_data"):
            return False
        for pool in (False, True):
            account = Account(request.port, "orig_data", None if pool else request.vc)
            if self.available(account) < request.data_pools.count(pool):
                return False
        return True

    def step(self, connection: ConnectionSignals, request=None, returns=(), init_done=(),
             reset: bool = False) -> BurstEvents:
        """Emit this edge's legal beats, or decline a blocked candidate.

        Active data is mandatory in its slot. Any invalid credit/trace event
        rejects the entire edge without spending, releasing or advancing time.
        """
        if type(reset) is not bool:
            raise TypeError("reset must be a boolean")
        if reset:
            self._credits.step(None, reset=True)
            self._active, self._phase = {}, None
            return BurstEvents(None, None)
        if not isinstance(connection, ConnectionSignals):
            raise TypeError("a stable ConnectionSignals snapshot is required")
        if request is not None:
            self._validate_request(request)
        phase = self._phase
        current = request.port if phase is None and request is not None else phase
        active, selected, data = dict(self._active), None, None
        if current in self._active:
            old, offset = self._active[current]
            last = offset == old.num_beats
            data = BurstData(current, old.vc, old.data_pools[offset], offset, last)
            if last:
                del active[current]
            else:
                active[current] = old, offset + 1
        if request is not None and self._eligible(connection, request, current):
            selected = request
            if phase is None:
                phase = request.port
            if request.num_beats is not None:
                data = BurstData(request.port, request.vc, request.data_pools[0], 0, request.num_beats == 0)
                if request.num_beats:
                    active[request.port] = request, 1
        events = BurstEvents(selected, data)
        credits = deepcopy(self._credits)
        credits.step(connection, returns=returns, beats=events.beats, init_done=init_done)
        self._credits, self._active = credits, active
        self._phase = None if phase is None else (phase + 1) % self.num_ports
        return events
