"""Reject incomplete, wrong-profile or violating DL arbiter timing reports.

Run: python3 scripts/check_dl_message_sta_report.py ACTUAL_REPORT.log
Outputs: strict JSON slacks or a nonzero failure; no provenance is inferred.
Next: bind the accepted report to exact source/netlist/library identities.
"""
import argparse
import json
import math
from pathlib import Path
import re
import sys


def check_report(text):
    if re.search(r'\(VIOLATED\)|^\s*(?:Warning:|Error:|FAIL\b)|\bunconstrained\b',
                 text, re.M | re.I):
        raise ValueError('violating, diagnostic or unconstrained report')
    result = {}
    for mode, key in (('max', 'setup_ns'), ('min', 'hold_ns')):
        matches = re.findall(rf'^worst slack {mode}\s+(\S+)\s*$', text, re.M)
        if len(matches) != 1:
            raise ValueError(f'missing/duplicate {mode} slack')
        value = float(matches[0])
        if not math.isfinite(value) or value < 0:
            raise ValueError(f'negative/nonfinite {key}')
        result[key] = value
    endings = re.findall(r'^PASS (\S+) setup/hold at period_ns=(\S+); prelayout budget only$', text, re.M)
    if len(endings) != 1 or endings[0][0] != 'dl_message_arbiter' or endings[0][1] not in ('0.640', '6.400'):
        raise ValueError('missing/duplicate/wrong-profile completion')
    if 'Path Type: max' not in text or 'Path Type: min' not in text or 'Path Group: DL_MESSAGE' not in text:
        raise ValueError('missing actual min/max path details or clock group')
    return {**result, 'period_ns': float(endings[0][1]), 'scope': 'prelayout_report_contents_only'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(check_report(args.report.read_text())))
    except (OSError, ValueError) as error:
        print(f'FAIL DL message STA report: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
