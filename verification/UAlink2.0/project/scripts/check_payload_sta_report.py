"""Run: python3 scripts/check_payload_sta_report.py ACTUAL_REPORT.log.

Outputs: JSON slacks on success, nonzero diagnostic on incomplete/failed STA.
Next: verify source/library/netlist identity; this content gate alone cannot
prove provenance, routed timing, real macro behavior or complete IP signoff.
"""
import argparse
import json
import math
from pathlib import Path
import re
import sys


def check_report(text):
    if re.search(r"\(VIOLATED\)|^\s*(?:Warning:|Error:|FAIL\b)|\bunconstrained\b",
                 text, re.MULTILINE | re.IGNORECASE):
        raise ValueError("STA contains a violation, diagnostic or unconstrained path")
    result = {}
    for mode, name in (("max", "setup_slack_ns"), ("min", "hold_slack_ns")):
        matches = re.findall(rf"^worst slack {mode}\s+(\S+)\s*$", text, re.MULTILINE)
        if len(matches) != 1:
            raise ValueError(f"missing/duplicate worst slack {mode}")
        value = float(matches[0])
        if not math.isfinite(value) or value < 0:
            raise ValueError(f"negative/nonfinite {name}")
        result[name] = value
    endings = re.findall(r"^PASS (\S+) setup/hold at period_ns=(\S+); prelayout budget only$",
                         text, re.MULTILINE)
    if len(endings) != 1 or endings[0][0] != "burst_sender" or endings[0][1] not in ("0.640", "6.400"):
        raise ValueError("missing or wrong-profile/mode completion")
    return dict(result, period_ns=float(endings[0][1]), scope="prelayout_report_contents_only")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(check_report(args.report.read_text()), sort_keys=True))
    except (OSError, ValueError) as error:
        print(f"FAIL payload STA report: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
