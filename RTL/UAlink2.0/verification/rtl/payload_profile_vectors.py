"""Independent nonuniform/zero/high-credit and split-init sender traces.

Run through run_payload_profiles.py; its metadata supplies real DUT capacities.
Outputs: the established four-column input/event/state vector format. Next:
compare real banks plus payload, not just parameter elaboration. No wire fields
or production model behavior is added by these test-only scenario helpers.
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from verification.rtl.burst_payload_vectors import Oracle
from model.ualink.upli_burst_payload import UpliBurstPayload
from model.ualink.upli_credit import Account, CreditReturn


def capacities(ports, width, kind):
    maximum = (1 << width)-1
    result = {}
    for p in range(ports):
        req = (0, 1, 2+p % 2, 4+p % 3, maximum)
        data = (1+p % 3, 0, 3-p % 2, maximum, 2)
        for ch, counts in (("req", req), ("orig_data", data)):
            for vc, count in zip((0, 1, 2, 3, None), counts):
                result[Account(p, ch, vc)] = 0 if kind == "zero" else count
    return result


class ProfileOracle(Oracle):
    def __init__(self, ports, width, kind, init_cycles):
        super().__init__(ports, width, 96, init_cycles)
        self.capacities = capacities(ports, width, kind)
        self.sender = UpliBurstPayload(self.capacities, ports, request_width=96,
                                       init_stable_cycles=init_cycles)
        self.kind = kind

    def fill(self, high_limit=None):
        """Actual return batches only; no direct deposit into the sender model."""
        while True:
            grants = []
            for p in range(self.ports):
                for ch in ("req", "orig_data"):
                    for vc in (0, 1, 2, 3, None):
                        account = Account(p, ch, vc)
                        cap = self.capacities[account]
                        target = min(cap, high_limit) if high_limit is not None else cap
                        missing = target-self.sender.balance(account)
                        if missing > 0:
                            grants.append(CreditReturn(p, ch, vc or 0, vc is None, min(4, missing)-1))
                            break
            if not grants:
                break
            self.emit(returns=grants)

    def aligned(self, candidate):
        while self.sender.next_port is not None and self.sender.next_port != candidate.request.port:
            self.emit()
        return self.emit(candidate)

    def drain(self, overlay=False):
        for _ in range(4*self.ports):
            request = (self.candidate(self.sender.next_port or 0, 3, True)
                       if overlay else None)
            self.emit(request)
        assert all(self.sender.reserved(Account(p, "orig_data", vc)) == 0
                   for p in range(self.ports) for vc in (0, 1, 2, 3, None))

    def initialize(self, first, high_limit=None):
        self.emit(reset=True)
        self.emit(credit_connected=False, beats_connected=False)
        self.fill(high_limit)
        first_done = [(p, first) for p in range(self.ports)]
        read = self.candidate(0, 3, True)
        write = self.candidate(0, 3, True, 3, 0)
        for _ in range(self.init_cycles):
            assert not self.emit(read, init=first_done).control.accepted
        result = self.aligned(read)
        assert result.control.accepted == (first == "req" and self.kind != "zero")
        assert not self.aligned(write).control.accepted
        all_done = [(p, ch) for p in range(self.ports) for ch in ("req", "orig_data")]
        for _ in range(self.init_cycles):
            assert not self.emit(write, init=all_done).control.accepted
        result = self.aligned(write)
        assert result.control.accepted == (self.kind != "zero")
        if self.kind != "zero":
            # Four credits are reserved, but the first edge debits only one.
            before = min(self.capacities[Account(0, "orig_data", 3)], high_limit or (1 << self.width))
            assert self.sender.balance(Account(0, "orig_data", 3)) == before-1
            assert self.sender.reserved(Account(0, "orig_data", 3)) == 3
        self.drain(overlay=self.kind != "zero")


def generate(ports, width, kind, init_cycles=2):
    oracle = ProfileOracle(ports, width, kind, init_cycles)
    # Both orders are tested; the second fill crosses the top counter bit on
    # actual debit (2^(width-1) -> 2^(width-1)-1), then real batches refill it.
    oracle.initialize("req")
    oracle.initialize("orig_data", high_limit=1 << (width-1))
    oracle.fill()
    cases = 0
    for p in range(ports):
        for vc in range(4):
            for num in range(4):
                for pools in range(1 << (num+1)):
                    for req_pool in (False, True):
                        oracle.fill()
                        candidate = oracle.candidate(p, vc, req_pool, num, pools)
                        need_pool = pools.bit_count()
                        expected = (oracle.capacities[Account(p, "req", None if req_pool else vc)] > 0
                                    and oracle.capacities[Account(p, "orig_data", None)] >= need_pool
                                    and oracle.capacities[Account(p, "orig_data", vc)] >= num+1-need_pool)
                        assert oracle.aligned(candidate).control.accepted == expected
                        oracle.drain(overlay=expected)
                        cases += 1
    oracle.fill()
    for p in range(ports):
        for ch in ("req", "orig_data"):
            for vc in (0, 1, 2, 3, None):
                assert oracle.sender.balance(Account(p, ch, vc)) == oracle.capacities[Account(p, ch, vc)]
    oracle.emit(reset=True)
    for _ in range(4*ports):
        assert not oracle.emit(oracle.candidate(0, 3, True, 3, 0)).control.accepted
    result = {"rows": oracle.rows, "requests": oracle.requests, "data": oracle.data,
              "read_overlays": oracle.overlays, "allocation_cases": cases,
              "ports": ports, "credit_width": width, "kind": kind, "init_cycles": init_cycles}
    print(result, file=sys.stderr)
    return result
