"""Audit Yosys unsupported Liberty pin skips against actual mapped cell inventory.

Run: python3 scripts/check_uart_tx_mapping.py MAP.log MAPPED.json --top dl_uart_tx_source
Outputs: exact skipped-but-unused cell list, or nonzero failure.
Next: actual full mapped equivalence and STA; this check does not prove functionality.
"""
import argparse
import json
from pathlib import Path
import re
import sys


def check_mapping_diagnostics(text, used_cell_types):
    if not used_cell_types:
        raise ValueError('empty actual mapped inventory')
    warnings = re.findall(r'^\s*((?:Warning:|ERROR:|Error:|FAIL\b).*)$', text, re.M)
    skipped = set()
    for line in warnings:
        match = re.fullmatch(r"Warning: Malformed liberty file - cannot find pin '[^']+' in cell '([^']+)' - skipping\.", line)
        if not match:
            raise ValueError('unreviewed mapping diagnostic: '+line)
        skipped.add(match[1])
    if skipped & set(used_cell_types):
        raise ValueError('actual mapped netlist uses skipped Liberty cells: '+','.join(sorted(skipped & set(used_cell_types))))
    return dict(diagnostic_count=len(warnings), skipped_unused_cells=sorted(skipped),
                used_cell_types=sorted(used_cell_types), used_skipped_cells=[],
                scope='only exact unsupported Liberty pin skips verified absent from actual mapped cells')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('log', type=Path)
    p.add_argument('netlist', type=Path)
    p.add_argument('--top', choices=('dl_uart_tx_source', 'dl_uart_tx_path'), required=True)
    args = p.parse_args()
    try:
        cells = json.loads(args.netlist.read_text())['modules'][args.top]['cells']
        print(json.dumps(check_mapping_diagnostics(args.log.read_text(), {c['type'] for c in cells.values()})))
    except (OSError, ValueError, KeyError) as error:
        print(f'FAIL UART mapping diagnostic: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
