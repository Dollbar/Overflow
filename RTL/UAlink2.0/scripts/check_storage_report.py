"""Validate integrated-storage report contents; provenance needs separate hashes.

Run: python3 scripts/check_storage_report.py reports/storage_sta.log --depth 5
     --width 32 --macro-view slow
Output: bounded JSON summary or nonzero with a diagnostic.
Next: verify netlist/dependency identities and remaining declared timing views.
This is an actual-cell plus synthetic-memory prelayout budget, not silicon signoff.
"""

import argparse
import json
import math
from pathlib import Path
import re
import sys


def check_storage_report(text, *, depth, width, macro_view):
    if type(depth) is not int or not 1 <= depth <= 65535:
        raise ValueError("depth must be 1..65535")
    if type(width) is not int or width < 8 or width % 8:
        raise ValueError("width must be a positive byte multiple")
    if macro_view not in ("fast", "typical", "slow"):
        raise ValueError("undeclared synthetic macro view")
    if re.search(r"\(VIOLATED\)|^\s*(?:Warning:|Error:|FAIL\b)|\bunconstrained\b", text, re.M | re.I):
        raise ValueError("timing violation, diagnostic or unconstrained path")
    profiles = re.findall(r"^STORAGE_PROFILE depth=(\d+) width=(\d+) macro_view=(\S+)$", text, re.M)
    if profiles != [(str(depth), str(width), macro_view)]:
        raise ValueError("missing, ambiguous or mismatched storage profile")
    libraries = re.findall(r"^STORAGE_LIBRARY name=(\S+)$", text, re.M)
    if libraries != [f"kd28_sram_{macro_view}"]:
        raise ValueError("missing or mislabeled loaded macro library")
    macro_depth, macro_width, address_bits = next(
        (d, w, a) for d, w, a in ((256, 32, 8), (512, 64, 9), (1024, 128, 10), (2048, 256, 11))
        if depth <= d or d == 2048)
    banks = (depth + macro_depth - 1) // macro_depth
    macros = banks * ((width + macro_width - 1) // macro_width)
    inventory = re.findall(r"^STORAGE_MACRO cell=(\S+) count=(\d+)$", text, re.M)
    if inventory != [(f"KD28_SRAM_SDP_{macro_depth}X{macro_width}", str(macros))]:
        raise ValueError("missing or unexpected fixed SRAM macro inventory")
    pins = re.findall(r"^STORAGE_PINS write_clocks=(\d+) read_clocks=(\d+) read_outputs=(\d+) write_data=(\d+) read_address=(\d+) write_address=(\d+)$", text, re.M)
    expected_pins = tuple(map(str, (macros, macros, macros * macro_width, macros * macro_width,
                                  macros * address_bits, macros * address_bits)))
    if pins != [expected_pins]:
        raise ValueError("incomplete fixed macro clock/data/address interface")
    slacks = {}
    for kind, name in (("max", "setup_slack_ns"), ("min", "hold_slack_ns")):
        values = re.findall(rf"^worst slack {kind}\s+(\S+)\s*$", text, re.M)
        if len(values) != 1:
            raise ValueError("missing or ambiguous global slack")
        value = float(values[0])
        if not math.isfinite(value) or value < 0:
            raise ValueError("negative or nonfinite global slack")
        slacks[name] = value
    paths = {}
    for kind, minimum, maximum in re.findall(r"^STORAGE_PATH (\S+) min_slack_ns=(\S+) max_slack_ns=(\S+)$", text, re.M):
        if kind in paths:
            raise ValueError("duplicate timing path class")
        entry = {"hold_slack_ns": float(minimum), "setup_slack_ns": float(maximum)}
        for name, value in entry.items():
            if not math.isfinite(value) or value < 0 or value + 0.000001 < slacks[name]:
                raise ValueError("invalid path slack or inconsistent units")
        paths[kind] = entry
    expected_paths = {"register_to_macro", "input_to_macro", "macro_to_register"}
    if banks > 1:
        expected_paths.add("bank_select_to_register")
    if set(paths) != expected_paths:
        raise ValueError("missing or unexpected macro path classes")
    completions = re.findall(r"^PASS (\S+) setup/hold at period_ns=(\S+); (.+)$", text, re.M)
    if len(completions) != 1 or completions[0][0] != "storage" or completions[0][1] not in ("0.640", "6.400") or completions[0][2] != "synthetic macro budget only":
        raise ValueError("missing or ambiguous synthetic-budget completion")
    return dict(slacks, depth=depth, width=width, macro_view=macro_view, macro_cells=macros,
                period_ns=float(completions[0][1]), paths=paths,
                scope="actual_cells_with_synthetic_memory_prelayout_budget")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--depth", type=int, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--macro-view", choices=("fast", "typical", "slow"), required=True)
    args = parser.parse_args()
    try:
        result = check_storage_report(args.report.read_text(), depth=args.depth, width=args.width, macro_view=args.macro_view)
    except (ValueError, OSError) as error:
        print(f"FAIL storage report: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
