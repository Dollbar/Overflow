"""Validate RX identity, then reuse the strict macro/timing report schema.

Run: python3 scripts/check_uart_rx_sta_report.py REPORT --depth 128 --macro-view slow
Outputs: bounded JSON slacks/inventory or nonzero diagnostic.
Next: bind the report to source/netlist/library hashes; this is not provenance.
"""
import argparse
import json
from pathlib import Path
import re
import sys

if __package__ in (None, ''):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts.check_uart_tx_sta_report import check_report as check_shared


def check_report(text, *, target='path', depth=None, macro_view=None):
    if target != 'path':
        raise ValueError('RX supports the integrated path profile only')
    if re.search(r'UART_TX|uart_tx', text):
        raise ValueError('TX or mixed-direction report cannot establish RX timing')
    if 'UART_RX_PROFILE' not in text or 'dl_uart_rx_path' not in text:
        raise ValueError('missing actual RX profile or top')
    canonical = text.replace('UART_RX', 'UART_TX').replace('dl_uart_rx_path', 'dl_uart_tx_path')
    result = check_shared(canonical, target=target, depth=depth, macro_view=macro_view)
    return dict(result, direction='rx')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('report', type=Path)
    p.add_argument('--depth', type=int, required=True)
    p.add_argument('--macro-view', choices=('fast', 'typical', 'slow'), required=True)
    args = p.parse_args()
    try:
        print(json.dumps(check_report(args.report.read_text(), depth=args.depth, macro_view=args.macro_view)))
    except (OSError, ValueError) as error:
        print(f'FAIL UART RX STA report: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
