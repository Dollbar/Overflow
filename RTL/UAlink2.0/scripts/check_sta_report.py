"""Reject incomplete STA, negative slack, warnings or library-limit violations.

Run: python3 scripts/check_sta_report.py reports/credit_sta_<configuration>.log
Append --design initialization, return, receive or burst_control for those tops.
Output: bounded JSON summary on stdout; diagnostic and nonzero exit on failure.
Next: review only a fresh report bound to the netlist/source identity in evidence.
This parser validates a report's contents, not its provenance or physical signoff.
"""

import argparse
import json
import math
from pathlib import Path
import re
import sys


def check_report(text, design="credit"):
    if design not in ("credit", "initialization", "return", "receive", "burst_control", "control_partition", "prepared_partition"):
        raise ValueError("unknown STA design profile")
    if re.search(r"\(VIOLATED\)|^\s*(?:Warning:|Error:|FAIL\b)|\bunconstrained\b", text, re.MULTILINE | re.IGNORECASE):
        raise ValueError("STA contains a violation, tool diagnostic or unconstrained path")
    values = {}
    for kind, name in (("max", "setup_slack_ns"), ("min", "hold_slack_ns")):
        matches = re.findall(rf"^worst slack {kind}\s+(\S+)\s*$", text, re.MULTILINE)
        if len(matches) != 1:
            raise ValueError(f"expected exactly one worst slack {kind} result")
        value = float(matches[0])
        if not math.isfinite(value) or value < 0:
            raise ValueError(f"invalid or negative {name}")
        values[name] = value
    completions = re.findall(r"^PASS (\S+) setup/hold at period_ns=(\S+); prelayout budget only$", text, re.MULTILINE)
    if len(completions) != 1 or completions[0][0] != design or completions[0][1] not in ("0.640", "6.400"):
        raise ValueError("missing or ambiguous declared-mode completion marker")
    return dict(values, period_ns=float(completions[0][1]), diagnostic_gate="passed", scope="prelayout_report_contents_only")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--design", choices=("credit", "initialization", "return", "receive", "burst_control", "control_partition", "prepared_partition"), default="credit")
    args = parser.parse_args()
    try:
        result = check_report(args.report.read_text(), design=args.design)
    except (OSError, ValueError) as error:
        print(f"FAIL STA report gate: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
