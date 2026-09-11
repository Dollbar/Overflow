"""Four real-channel startup integration expectations, using prior-edge levels.

Run: python3 verification/rtl/startup_vectors.py --ports 4 --width 4 --wait 0
Output: 12-bit stimulus and packed connection/publisher/bank state hex columns.
Next: compare upli_credit_startup_tb at 640/6400 ps; this has no payload queues.
"""

import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.upli_connection import UpliConnection
from model.ualink.upli_credit import Account, Beat, CreditInitMonitor, UpliCreditLedger
from model.ualink.upli_credit_initialization import InitialCreditPublisher
from verification.rtl.initialization_vectors import InitialProfile, packed_outputs

CHANNEL_ORDER = ("req", "orig_data", "rd_rsp", "wr_rsp")


def stimuli(profile):
    longest = max(sum(max(1, (cap+3)//4) for cap in profile.capacities[p*5:p*5+5])
                  for p in range(profile.ports))
    for ordering in ("orig_first", "comp_first", "together"):
        yield 0
        yield 0
        first, half = {"orig_first":(6, 5), "comp_first":(5, 6), "together":(7, 7)}[ordering]
        for _ in range(5):
            yield first << 9
        for _ in range(longest+5):
            yield half << 9
        for _ in range(longest+8):
            yield 7 << 9
        for port in range(profile.ports):
            for account in range(5):
                for trial in range(9):
                    vc = account if account < 4 else trial % 4
                    yield (7 << 9) | (15 << 5) | (port << 3) | (vc << 1) | int(account == 4)
        for _ in range(8):
            yield 4 << 9  # ready may fall; established promises and done remain high
    # Error-directed local send events near initial completion, followed by reset.
    for cut in (0, 1, 3, 6, longest//2, longest+3, longest+6, longest+12):
        yield 0
        for cycle in range(cut+1):
            yield (7 << 9) | ((15 << 5) if cycle == cut else 0) | 2
    yield 0
    for _ in range(longest+20):
        yield 7 << 9


def vectors(profile, waits=False):
    connection = UpliConnection(completer_waits=waits)
    publishers = [InitialCreditPublisher(profile.capacities, profile.ports, profile.width, ch) for ch in CHANNEL_ORDER]
    accounts = [[Account(p, ch, None if a == 4 else a) for p in range(profile.ports) for a in range(5)] for ch in CHANNEL_ORDER]
    banks = [UpliCreditLedger(dict(zip(keys, profile.capacities)), profile.ports) for keys in accounts]
    monitors = [CreditInitMonitor(profile.ports) for _ in CHANNEL_ORDER]
    channel_bits = profile.ports*5*profile.width+33
    for stimulus in stimuli(profile):
        reset = not bool(stimulus & (1 << 11))
        old_connection = connection.signals
        result = 0
        for ch_index, (channel, publisher, bank, keys, monitor) in enumerate(zip(CHANNEL_ORDER, publishers, banks, accounts, monitors)):
            old = publisher.outputs
            done = [(p, channel) for p in range(profile.ports) if old.done & (1 << p)]
            beats = [Beat((stimulus >> 3) & 3, channel, (stimulus >> 1) & 3, bool(stimulus & 1))] if stimulus & (1 << (ch_index+5)) else []
            error = 0
            try:
                bank.step(old_connection, returns=old.returns, init_done=done, beats=beats, reset=reset)
            except ValueError:
                error = 1  # local diagnostic test, not a legal transaction or wire RAS
            monitor.step(credit_slots=[(r.port, channel) for r in old.returns], done_slots=done, reset=reset)
            next_publication = publisher.step(old_connection, reset=reset)
            balances = sum(bank.balance(a) << (i*profile.width) for i, a in enumerate(keys))
            confirmed = sum(int(bank.initialized(p, channel)) << p for p in range(profile.ports))
            chunk = (packed_outputs(next_publication) << (profile.ports*5*profile.width+5)) | (balances << 5) | (confirmed << 1) | error
            result |= chunk << (ch_index*channel_bits)
        signals = connection.step(not reset, bool(stimulus & (1 << 10)), bool(stimulus & (1 << 9)))
        flags = (int(signals.orig_req) << 3) | (int(signals.comp_ack) << 2) | (int(signals.comp_req) << 1) | int(signals.orig_ack)
        yield stimulus, result | (flags << (4*channel_bits))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, default=1)
    parser.add_argument("--width", type=int, default=4)
    parser.add_argument("--uniform-capacity", type=int)
    parser.add_argument("--pattern", choices=("standard", "staggered"), default="standard")
    parser.add_argument("--wait", type=int, choices=(0, 1), default=0)
    args = parser.parse_args()
    profile = InitialProfile(args.ports, args.width, 2, args.uniform_capacity, args.pattern)
    for stimulus, result in vectors(profile, bool(args.wait)):
        print(f"{stimulus:03x} {result:x}")


if __name__ == "__main__":
    main()
