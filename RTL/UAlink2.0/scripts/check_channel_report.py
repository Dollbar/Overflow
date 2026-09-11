"""Check channel-level physical report contents; provenance is separately hashed.

Run: python3 scripts/check_channel_report.py report.log --ports 1 --width 32
     --credit-width 4 --cap-hex 50132 --return-depth 4 --macro-view slow --period-ns 0.640
Output: bounded JSON summary or nonzero rejection. Next verify all declared corners.
The memory views are abstract assumptions, not characterized SRAM signoff.
"""

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import re
import sys


def check_channel_report(text, *, ports, width, credit_width, cap_hex, return_depth, macro_view, period_ns):
    if any(type(v) is not int for v in (ports, width, credit_width, return_depth)):
        raise ValueError("numeric profile parameters must be integers")
    if ports not in (1, 2, 4) or width < 1 or not 3 <= credit_width <= 16 or not 1 <= return_depth <= 16:
        raise ValueError("invalid channel profile")
    if not isinstance(cap_hex, str) or not re.fullmatch(r"[0-9a-fA-F]+", cap_hex):
        raise ValueError("capacity must be unsigned hexadecimal digits")
    value = int(cap_hex, 16)
    if value >= (1 << (ports*5*credit_width)) or macro_view not in ("fast", "typical", "slow") or period_ns not in ("0.640", "6.400"):
        raise ValueError("truncated capacity or undeclared timing mode")
    cap_hex = format(value, "x")
    if re.search(r"\(VIOLATED\)|^\s*(?:Warning:|Error:|FAIL\b)|\bunconstrained\b", text, re.M | re.I):
        raise ValueError("timing violation, diagnostic or unconstrained endpoint")
    profiles = re.findall(r"^CHANNEL_PROFILE ports=(\d+) width=(\d+) credit_width=(\d+) cap_hex=(\S+) return_depth=(\d+) macro_view=(\S+)$", text, re.M)
    if profiles != [(str(ports), str(width), str(credit_width), cap_hex, str(return_depth), macro_view)]:
        raise ValueError("missing, ambiguous or different channel profile")
    if re.findall(r"^CHANNEL_LIBRARY name=(\S+)$", text, re.M) != [f"kd28_sram_{macro_view}"]:
        raise ValueError("missing or mislabeled actual macro library")
    inventory, data_pins, address_pins, banked = Counter(), 0, 0, False
    for slot in range(ports*5):
        depth = (value >> (slot*credit_width)) & ((1 << credit_width)-1)
        if depth == 0:
            continue
        md, mw, ab = next((d, w, a) for d, w, a in ((256, 32, 8), (512, 64, 9), (1024, 128, 10), (2048, 256, 11)) if depth <= d or d == 2048)
        banks = (depth+md-1)//md
        macros = banks*((((width+3+7)//8)*8+mw-1)//mw)
        inventory[f"KD28_SRAM_SDP_{md}X{mw}"] += macros
        data_pins += macros*mw
        address_pins += macros*ab
        banked |= banks > 1
    reported = re.findall(r"^CHANNEL_MACRO cell=(\S+) count=(\d+)$", text, re.M)
    if len({name for name, _ in reported}) != len(reported) or dict((name, int(n)) for name, n in reported) != dict(inventory):
        raise ValueError("wrong or incomplete actual per-account macro inventory")
    macro_total = sum(inventory.values())
    pins = re.findall(r"^CHANNEL_PINS write_clocks=(\d+) read_clocks=(\d+) read_outputs=(\d+) write_data=(\d+) read_address=(\d+) write_address=(\d+)$", text, re.M)
    if pins != [tuple(map(str, (macro_total, macro_total, data_pins, data_pins, address_pins, address_pins)))]:
        raise ValueError("missing actual macro clocks or interface pins")
    slacks = {}
    for kind, name in (("max", "setup_slack_ns"), ("min", "hold_slack_ns")):
        values = re.findall(rf"^worst slack {kind}\s+(\S+)\s*$", text, re.M)
        if len(values) != 1:
            raise ValueError("missing or duplicated global slack")
        slacks[name] = float(values[0])
        if not math.isfinite(slacks[name]) or slacks[name] < 0:
            raise ValueError("negative or nonfinite global slack")
    paths = {}
    for name, minimum, maximum in re.findall(r"^CHANNEL_PATH (\S+) min_slack_ns=(\S+) max_slack_ns=(\S+)$", text, re.M):
        if name in paths:
            raise ValueError("duplicated path class")
        entry = dict(hold_slack_ns=float(minimum), setup_slack_ns=float(maximum))
        if any(not math.isfinite(v) or v < 0 or v+1e-6 < slacks[k] for k, v in entry.items()):
            raise ValueError("invalid path slack or inconsistent units")
        paths[name] = entry
    expected = {"control_to_register"}
    if macro_total:
        expected |= {"register_to_macro", "input_to_macro", "macro_to_register", "selection_to_head", "register_to_head", "consumer_to_register"}
    if banked:
        expected.add("bank_select_to_register")
    if set(paths) != expected:
        raise ValueError("missing or unexpected channel timing class")
    if re.findall(r"^PASS (\S+) setup/hold at period_ns=(\S+); (.+)$", text, re.M) != [("channel", period_ns, "synthetic macro budget only")]:
        raise ValueError("missing, mismatched or duplicated channel completion")
    return dict(slacks, ports=ports, width=width, cap_hex=cap_hex, macro_cells=macro_total,
                macro_inventory=dict(inventory), macro_view=macro_view, period_ns=float(period_ns),
                paths=paths, scope="actual_cells_with_synthetic_memory_channel_prelayout_budget")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    for name in ("ports", "width", "credit-width", "return-depth"):
        parser.add_argument("--"+name, type=int, required=True)
    parser.add_argument("--cap-hex", required=True)
    parser.add_argument("--macro-view", choices=("fast", "typical", "slow"), required=True)
    parser.add_argument("--period-ns", choices=("0.640", "6.400"), required=True)
    args = vars(parser.parse_args())
    path = args.pop("report")
    try:
        result = check_channel_report(path.read_text(), **args)
    except (OSError, ValueError) as error:
        print(f"FAIL channel report: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
