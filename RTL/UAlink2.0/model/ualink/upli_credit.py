"""C 2.6/4.3 sender credit arithmetic and independent receiver-init monitor.

Not a receiver receipt queue, burst scheduler, TL credit loop or RAS engine.
The capacity bound cannot detect every forged or wrong-VC pool credit return.
"""

from dataclasses import dataclass

from .upli_connection import ConnectionSignals


CHANNELS = ("req", "orig_data", "rd_rsp", "wr_rsp")


def _ports(num_ports):
    if type(num_ports) is not int:
        raise TypeError("num_ports must be an integer")
    if num_ports not in (1, 2, 4):
        raise ValueError("a UPLI station has one, two or four ports")
    return num_ports


def _slot(port, channel, num_ports):
    if type(port) is not int:
        raise TypeError("port must be an integer")
    if not 0 <= port < num_ports or channel not in CHANNELS:
        raise ValueError("unknown port or UPLI channel")
    return port, channel


def _vc(vc):
    if type(vc) is not int:
        raise TypeError("VC must be an integer")
    if not 0 <= vc < 4:
        raise ValueError("VC must be in the range 0..3")
    return vc


def _credit_connected(connection, channel):
    # Request/data CREDIT RETURNS travel from Completer to Originator.
    return connection.comp_connected if channel in ("req", "orig_data") else connection.orig_connected


@dataclass(frozen=True)
class Account:
    port: int
    channel: str
    vc: int | None  # None is the ONE shared pool; not one pool per VC.


@dataclass(frozen=True)
class CreditReturn:
    port: int
    channel: str
    vc: int
    pool: bool
    encoded_count: int
    valid: bool = True


@dataclass(frozen=True)
class Beat:
    port: int
    channel: str
    vc: int
    pool: bool = False


class UpliCreditLedger:
    """An explicit-capacity sender model. No same-edge credit/init bypass.

    Failed steps leave state unchanged for reproducible diagnosis. Hardware
    error recovery is a different contract and is not specified by exceptions.
    """

    def __init__(self, capacities, num_ports: int, init_stable_cycles: int = 2):
        self.num_ports = _ports(num_ports)
        if type(init_stable_cycles) is not int:
            raise TypeError("init_stable_cycles must be an integer")
        if init_stable_cycles < 2:
            raise ValueError("CreditInitDone must be confirmed for more than one cycle")
        self.init_stable_cycles = init_stable_cycles
        self._capacities = dict(capacities)
        for account, capacity in self._capacities.items():
            self._check_account(account)
            if type(capacity) is not int:
                raise TypeError("capacity must be an integer")
            if capacity < 0:
                raise ValueError("capacity cannot be negative")
        self._balances = {account: 0 for account in self._capacities}
        self._streaks = {}
        self._initialized = set()

    def _check_account(self, account):
        if not isinstance(account, Account):
            raise TypeError("capacity/balance key must be an Account")
        _slot(account.port, account.channel, self.num_ports)
        if account.vc is not None:
            _vc(account.vc)

    def _event_account(self, event):
        _slot(event.port, event.channel, self.num_ports)
        _vc(event.vc)
        if type(event.pool) is not bool:
            raise TypeError("pool indication must be a boolean")
        return Account(event.port, event.channel, None if event.pool else event.vc)

    def balance(self, account: Account) -> int:
        self._check_account(account)
        return self._balances.get(account, 0)

    def initialized(self, port: int, channel: str) -> bool:
        return _slot(port, channel, self.num_ports) in self._initialized

    def step(self, connection: ConnectionSignals, returns=(), beats=(), init_done=(), reset: bool = False) -> None:
        """Consume events at this edge using the provided pre-edge connection levels."""
        if type(reset) is not bool:
            raise TypeError("reset must be a boolean")
        if reset:
            self._balances = {account: 0 for account in self._capacities}
            self._streaks = {}
            self._initialized = set()
            return
        if not isinstance(connection, ConnectionSignals):
            raise TypeError("a stable ConnectionSignals snapshot is required")
        balances = dict(self._balances)
        seen_returns = set()
        for grant in returns:
            if not isinstance(grant, CreditReturn) or type(grant.valid) is not bool:
                raise TypeError("credit events need a boolean valid field")
            if not grant.valid:
                continue
            account = self._event_account(grant)
            slot = (grant.port, grant.channel)
            if slot in seen_returns:
                raise ValueError("one channel/port can return only one encoded credit batch per cycle")
            seen_returns.add(slot)
            if not _credit_connected(connection, grant.channel):
                raise ValueError("credit-return direction is not connected")
            if type(grant.encoded_count) is not int:
                raise TypeError("credit count encoding must be an integer")
            if not 0 <= grant.encoded_count <= 3:
                raise ValueError("credit count encoding must fit two bits")
            balances[account] = balances.get(account, 0) + grant.encoded_count + 1
        seen_beats = set()
        for beat in beats:
            if not isinstance(beat, Beat):
                raise TypeError("beat events must be Beat instances")
            account = self._event_account(beat)
            if beat.channel in seen_beats:
                raise ValueError("one UPLI channel carries at most one beat each cycle")
            seen_beats.add(beat.channel)
            if not connection.beats_enabled or (beat.port, beat.channel) not in self._initialized:
                raise ValueError("beat requires both connections and prior credit-init confirmation")
            if self._balances.get(account, 0) < 1:
                raise ValueError("beat has no pre-edge credit; a new return cannot be bypassed")
            balances[account] -= 1
        for account, amount in balances.items():
            if not 0 <= amount <= self._capacities.get(account, 0):
                raise ValueError("credit balance exceeds the configured receiver capacity")
        high = {_slot(port, channel, self.num_ports) for port, channel in init_done}
        streaks, initialized = dict(self._streaks), set(self._initialized)
        for port in range(self.num_ports):
            for channel in CHANNELS:
                slot = (port, channel)
                if slot in initialized:
                    continue
                if slot in high and not _credit_connected(connection, channel):
                    raise ValueError("initial credit status received before its direction connected")
                streaks[slot] = streaks.get(slot, 0) + 1 if slot in high else 0
                if streaks[slot] >= self.init_stable_cycles:
                    initialized.add(slot)
        self._balances, self._streaks, self._initialized = balances, streaks, initialized


class CreditInitMonitor:
    """Receiver signal legality, separate from sender-side glitch filtering."""

    def __init__(self, num_ports: int):
        self.num_ports = _ports(num_ports)
        self._asserted = set()

    def step(self, credit_slots=(), done_slots=(), reset: bool = False) -> None:
        if type(reset) is not bool:
            raise TypeError("reset must be a boolean")
        if reset:
            self._asserted = set()
            return
        credits = {_slot(port, channel, self.num_ports) for port, channel in credit_slots}
        done = {_slot(port, channel, self.num_ports) for port, channel in done_slots}
        if not self._asserted.issubset(done):
            raise ValueError("receiver CreditInitDone deasserted before reset")
        if (done - self._asserted) & credits:
            raise ValueError("first CreditInitDone must be later than the final initial credit")
        self._asserted = done
