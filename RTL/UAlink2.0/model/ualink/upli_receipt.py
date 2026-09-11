"""C 2.6 receiver VC/Pool ownership and normal credit playback model.

Initial credit publication, sender balances, TDM and transaction/burst legality
remain separate checks. Exceptions diagnose a trace; they are not wire errors.
"""

from dataclasses import dataclass

from .upli_connection import ConnectionSignals
from .upli_credit import Account, Beat, CHANNELS, CreditReturn


@dataclass(frozen=True, eq=False)
class Receipt:
    """Identity-based local token: equal-looking or old tokens are not aliases."""

    beat: Beat


@dataclass(frozen=True)
class ReceiptEvents:
    receipts: tuple[Receipt, ...]
    returns: tuple[CreditReturn, ...]


class UpliReceiptQueue:
    """Retain original metadata until an eligible return batch is emitted.

    Capacity counts all received-but-not-returned tokens. No same-edge return
    slot reuse or retirement bypass; these are conservative pipeline choices.
    """

    def __init__(self, capacities, num_ports: int):
        if type(num_ports) is not int:
            raise TypeError("num_ports must be an integer")
        if num_ports not in (1, 2, 4):
            raise ValueError("a UPLI station has one, two or four ports")
        self.num_ports = num_ports
        self._capacities = dict(capacities)
        for account, capacity in self._capacities.items():
            self._check_account(account)
            if type(capacity) is not int:
                raise TypeError("capacity must be an integer")
            if capacity < 0:
                raise ValueError("capacity cannot be negative")
        self._records: dict[Receipt, bool] = {}

    def _check_account(self, account):
        if not isinstance(account, Account):
            raise TypeError("account key must be an Account")
        if type(account.port) is not int:
            raise TypeError("port must be an integer")
        if not 0 <= account.port < self.num_ports or account.channel not in CHANNELS:
            raise ValueError("unknown port or UPLI channel")
        if account.vc is not None:
            if type(account.vc) is not int:
                raise TypeError("VC must be an integer")
            if not 0 <= account.vc < 4:
                raise ValueError("VC must be in the range 0..3")

    def _account(self, beat):
        if not isinstance(beat, Beat):
            raise TypeError("received events must be Beat instances")
        if type(beat.pool) is not bool:
            raise TypeError("pool indication must be a boolean")
        if type(beat.vc) is not int:
            raise TypeError("VC must be an integer")
        if not 0 <= beat.vc < 4:
            raise ValueError("VC must be in the range 0..3 even for pool beats")
        account = Account(beat.port, beat.channel, None if beat.pool else beat.vc)
        self._check_account(account)
        return account

    def _require_owned(self, token):
        if type(token) is not Receipt:
            raise TypeError("resource events require Receipt tokens")
        if token not in self._records:
            raise ValueError("receipt is foreign, stale, forged or already returned")

    def occupancy(self, account: Account) -> int:
        """All held and retired tokens using this physical buffer account."""
        self._check_account(account)
        return sum(self._account(token.beat) == account for token in self._records)

    @property
    def returnable(self) -> tuple[Receipt, ...]:
        """Eligible tokens in receive order; scheduling policy is external."""
        return tuple(token for token, retired in self._records.items() if retired)

    def step(self, connection: ConnectionSignals, beats=(), retire=(), batches=(),
             reset: bool = False) -> ReceiptEvents:
        """Validate an edge against pre-edge state, then atomically update it."""
        if type(reset) is not bool:
            raise TypeError("reset must be a boolean")
        if reset:
            self._records = {}
            return ReceiptEvents((), ())
        if not isinstance(connection, ConnectionSignals):
            raise TypeError("a stable ConnectionSignals snapshot is required")
        records = dict(self._records)
        returned, return_slots, grants = set(), set(), []
        for members in batches:
            batch = tuple(members)
            if not 1 <= len(batch) <= 4:
                raise ValueError("a return batch contains one to four receipts")
            for token in batch:
                self._require_owned(token)
                if token in returned or not self._records[token]:
                    raise ValueError("receipt must be uniquely returned and retired before this edge")
                returned.add(token)
            beat = batch[0].beat
            if any(token.beat != beat for token in batch):
                raise ValueError("one batch must share the saved port, channel, VC and pool")
            slot = (beat.port, beat.channel)
            if slot in return_slots:
                raise ValueError("one port/channel has only one return bus per cycle")
            return_slots.add(slot)
            allowed = (connection.comp_connected if beat.channel in ("req", "orig_data")
                       else connection.orig_connected)
            if not allowed:
                raise ValueError("credit-return direction is not connected")
            grants.append(CreditReturn(beat.port, beat.channel, beat.vc, beat.pool, len(batch) - 1))
            for token in batch:
                del records[token]
        retired = set()
        for token in retire:
            self._require_owned(token)
            if token in retired or self._records[token]:
                raise ValueError("a held receipt can be retired only once")
            retired.add(token)
            records[token] = True
        channels, receipts = set(), []
        for beat in beats:
            account = self._account(beat)
            if beat.channel in channels:
                raise ValueError("one UPLI channel carries at most one beat per cycle")
            channels.add(beat.channel)
            if not connection.beats_enabled:
                raise ValueError("beat requires both connected directions")
            if self.occupancy(account) >= self._capacities.get(account, 0):
                raise ValueError("no pre-edge receiver buffer space for this account")
            token = Receipt(beat)
            records[token] = False
            receipts.append(token)
        self._records = records
        return ReceiptEvents(tuple(receipts), tuple(grants))
