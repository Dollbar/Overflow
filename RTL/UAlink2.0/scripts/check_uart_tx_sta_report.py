"""Reject incomplete, wrong-profile and violating UART source/path STA reports.

Run: python3 scripts/check_uart_tx_sta_report.py REPORT --target source
Path: add --target path --depth 128 --macro-view slow instead of source.
Outputs: bounded JSON slacks/inventory or nonzero diagnostic.
Next: bind report to actual netlist/library hashes; report content is not provenance.
"""
import argparse
import json
import math
from pathlib import Path
import re
import sys


def check_report(text, *, target, depth=None, macro_view=None):
    if target not in ('source', 'path'):
        raise ValueError('unknown UART target')
    if target == 'source' and (depth is not None or macro_view is not None):
        raise ValueError('source has no SRAM depth/view')
    if target == 'path' and (type(depth) is not int or not 1 <= depth <= 4095 or macro_view not in ('fast', 'typical', 'slow')):
        raise ValueError('path requires depth1..4095 and exact synthetic view')
    if re.search(r'\(VIOLATED\)|^\s*(?:Warning:|Error:|FAIL\b)|\bunconstrained\b', text, re.M | re.I):
        raise ValueError('diagnostic, electrical/timing violation or unconstrained path')
    profiles = re.findall(r'^UART_TX_PROFILE target=(\S+) depth=(\d+) macro_view=(\S+)$', text, re.M)
    if profiles != [(target, str(depth or 0), macro_view or 'none')]:
        raise ValueError('missing/duplicate/wrong UART profile')
    top = 'dl_uart_tx_'+target
    endings = re.findall(r'^PASS (\S+) setup/hold at period_ns=(\S+); prelayout budget only$', text, re.M)
    if len(endings) != 1 or endings[0][0] != top or endings[0][1] not in ('0.640', '6.400'):
        raise ValueError('missing/duplicate/wrong top or clock completion')
    if any(x not in text for x in ('Path Group: UART_TX', 'Path Type: min', 'Path Type: max')):
        raise ValueError('missing real min/max paths or clock group')
    result = dict(target=target, period_ns=float(endings[0][1]), scope='prelayout_report_contents_only')
    for mode, key in (('max', 'setup_ns'), ('min', 'hold_ns')):
        values = re.findall(rf'^worst slack {mode}\s+(\S+)\s*$', text, re.M)
        if len(values) != 1 or not math.isfinite(float(values[0])) or float(values[0]) < 0:
            raise ValueError('missing/duplicate/negative/nonfinite global slack')
        result[key] = float(values[0])
    tns = re.findall(r'^tns max\s+(\S+)\s*$', text, re.M)
    if len(tns) != 1 or float(tns[0]) != 0:
        raise ValueError('missing/duplicate/nonzero/nonfinite TNS')
    if target == 'source':
        if re.search(r'^UART_TX_(?:LIBRARY|MACRO|PINS|PATH)\b', text, re.M):
            raise ValueError('source report contains unexpected SRAM profile')
        return result
    macro_depth, macro_width, address_bits = next((d, w, a) for d, w, a in
        ((256, 32, 8), (512, 64, 9), (1024, 128, 10), (2048, 256, 11)) if depth <= d or d == 2048)
    count = (depth+macro_depth-1)//macro_depth
    if re.findall(r'^UART_TX_LIBRARY name=(\S+)$', text, re.M) != ['kd28_sram_'+macro_view]:
        raise ValueError('missing/duplicate/wrong loaded synthetic library')
    if re.findall(r'^UART_TX_MACRO cell=(\S+) count=(\d+)$', text, re.M) != [(f'KD28_SRAM_SDP_{macro_depth}X{macro_width}', str(count))]:
        raise ValueError('missing/duplicate/wrong macro class or count')
    pins = re.findall(r'^UART_TX_PINS write_clocks=(\d+) read_clocks=(\d+) read_outputs=(\d+) write_data=(\d+) read_address=(\d+) write_address=(\d+)$', text, re.M)
    if pins != [tuple(map(str, (count, count, count*macro_width, count*macro_width, count*address_bits, count*address_bits)))]:
        raise ValueError('missing/duplicate/wrong macro pin shape')
    paths = {}
    for kind, minimum, maximum in re.findall(r'^UART_TX_PATH (\S+) min_slack_ns=(\S+) max_slack_ns=(\S+)$', text, re.M):
        if kind in paths:
            raise ValueError('duplicate macro path class')
        item = {'hold_ns': float(minimum), 'setup_ns': float(maximum)}
        if any(not math.isfinite(v) or v < 0 or v+1e-9 < result[k] for k, v in item.items()):
            raise ValueError('negative/nonfinite/inconsistent macro path slack')
        paths[kind] = item
    required = {'register_to_macro', 'input_to_macro', 'macro_to_register'}
    if count > 1:
        required.add('bank_select_to_register')
    if set(paths) != required:
        raise ValueError('missing or unexpected macro path class')
    return dict(result, depth=depth, macro_view=macro_view, macro_count=count, paths=paths,
                scope='actual_standard_cells_with_synthetic_memory_prelayout_report_contents')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('report', type=Path)
    p.add_argument('--target', choices=('source', 'path'), required=True)
    p.add_argument('--depth', type=int)
    p.add_argument('--macro-view', choices=('fast', 'typical', 'slow'))
    args = p.parse_args()
    try:
        print(json.dumps(check_report(args.report.read_text(), target=args.target, depth=args.depth, macro_view=args.macro_view)))
    except (OSError, ValueError) as error:
        print(f'FAIL UART TX STA report: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
