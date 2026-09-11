"""Run python3 verification/tl_tx_qualification/run_storage_visibility.py --label NEW
--top fifo|buffered [--kd28-root PATH] [--widths 8 16] [--depths 1 2 3].
FIFO checks both the default profile and raw output followed by validity masking;
buffered checks actual integrated RTL against frozen 6839cac, exposing all SRAM
transactions and allowing arbitrary common read data. Every FF is observed.
Outputs source snapshots, graph/state inventories and CEC/reset logs under
build/verification/tl_tx_qualification/NEW. Next independent regressions and
actual production mapping; this is RTL correspondence, not mapped signoff.
"""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'verification/tl_partition_mapping'))
sys.path.insert(0, str(ROOT / 'verification/tl_prepared_partition'))
sys.path.insert(0, str(ROOT / 'verification/tl_tx_prepared'))
from run_cec import dump, execute, need, sha, prune_dead_names
from mapped_state import observe, audit_cut
from run_partitioned_cec import outcome
from run_header_visibility import REFERENCE


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--top', required=True, choices=('fifo', 'buffered'))
    parser.add_argument('--kd28-root', type=Path)
    parser.add_argument('--rtl-root', type=Path, default=ROOT / 'rtl', help='optional isolated candidate RTL tree')
    parser.add_argument('--widths', type=int, nargs='+', choices=range(8, 17), default=[8, 16])
    parser.add_argument('--depths', type=int, nargs='+', choices=(1, 2, 3, 5, 129, 257), default=[1, 2, 3])
    args = parser.parse_args()
    need(args.label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    need(len(set(args.widths)) == len(args.widths) and len(set(args.depths)) == len(args.depths), 'duplicate configuration')
    need(args.top != 'buffered' or args.kd28_root, 'buffered proof needs authorized SRAM mapping')
    stage = ROOT / 'build/verification/tl_tx_qualification' / args.label
    stage.mkdir(parents=True, exist_ok=False)
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    paths = ['rtl/upli/upli_receive_fifo.v']
    deps = []
    if args.top == 'buffered':
        paths += ['rtl/upli/upli_receive_storage.v']
        paths += ['rtl/tl/' + n + '.v' for n in ('tl_tx_buffered', 'tl_tx_data_fifo',
                  'tl_tx_channels', 'tl_tx_packer_core', 'tl_credit_admission',
                  'tl_control_decode', 'tl_control_tenure')]
        deps = [args.kd28_root / 'Library/models/kd28/sram/rtl/kd28_sram_blackboxes.v',
                args.kd28_root / 'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v']
    snapshots = {}
    for side in ('gold', 'gate'):
        folder = stage / 'sources' / side
        folder.mkdir(parents=True)
        snapshots[side] = []
        for name in paths:
            content = subprocess.check_output(['git', 'show', f'{REFERENCE}:{name}'], cwd=ROOT) if side == 'gold' else (args.rtl_root.resolve() / Path(name).relative_to('rtl')).read_bytes()
            path = folder / Path(name).name
            path.write_bytes(content)
            snapshots[side].append(path)
    result = dict(complete=False, reference_commit=REFERENCE, top=args.top,
                  scope='all actual FF transitions and public/SRAM transaction outputs; no control cuts',
                  sources={str(p): sha(p) for p in deps + sum(snapshots.values(), [])},
                  results=[], full_goal_complete=False)
    configs = [(w, d, None) for w in args.widths for d in args.depths] if args.top == 'buffered' else [(w, d, raw) for w in (8, 32, 512) for d in args.depths for raw in (0, 1)]
    for width, depth, raw in configs:
        folder = stage / f'w{width}_d{depth}' / (f'raw{raw}' if raw is not None else 'buffered')
        folder.mkdir(parents=True)
        top = 'visibility_fifo' if args.top == 'fifo' else 'tl_tx_buffered'
        row = dict(width=width, depth=depth, raw=raw, reset=[], qualified=False)
        result['results'].append(row)
        layouts, ports = {}, {}
        for side in ('gold', 'gate'):
            script = ''
            if deps:
                script += f'read_verilog -lib "{deps[0]}"\nread_verilog "{deps[1]}"\n'
            script += '\n'.join(f'read_verilog "{p}"' for p in snapshots[side]) + '\n'
            if args.top == 'fifo':
                header = snapshots['gold'][0].read_text().split(');', 1)[0].replace('module upli_receive_fifo ', 'module visibility_fifo ', 1)
                names = list(dict.fromkeys(re.findall(r'\b[io]_[a-zA-Z0-9_]+\b', header)))
                use_raw = side == 'gate' and raw == 1
                params = '.C_DEPTH(C_DEPTH),.C_DATA_WIDTH(C_DATA_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH)' + (',.C_ZERO_INVALID(0)' if use_raw else '')
                wrapper = header + ');\nwire [C_DATA_WIDTH-1:0] raw_data;\n'
                if use_raw:
                    wrapper += "assign o_read_data=o_read_valid?raw_data:{C_DATA_WIDTH{1'b0}};\n"
                connections = [f'.{n}({"raw_data" if use_raw and n == "o_read_data" else n})' for n in names]
                wrapper += f'upli_receive_fifo #({params}) Impl_Inst(' + ','.join(connections) + ');\nendmodule\n'
                (folder / f'{side}_wrapper.v').write_text(wrapper)
                script += f'read_verilog "{folder}/{side}_wrapper.v"\nchparam -set C_DATA_WIDTH {width} -set C_DEPTH {depth} {top}\n'
            else:
                script += f'chparam -set WIDTH {width} -set HEADER_DEPTH {depth} -set BANK_DEPTH {depth} {top}\n'
            script += f'prep -top {top} -flatten\n'
            if deps:
                script += f'write_json "{folder}/{side}_macro_graph.json"\nexpose -evert {top}/t:KD28_SRAM_*\n'
            script += f'techmap\nopt -full\ndffunmap\nopt_clean\ncheck -assert\nwrite_json "{folder}/{side}_original.json"\n'
            (folder / f'{side}_prepare.ys').write_text(script)
            prepared = execute(['yosys', '-Q', '-T', '-s', str(folder / f'{side}_prepare.ys')], folder / f'{side}_prepare.log', 180)
            row[f'{side}_prepare'] = prepared
            dump(stage / 'results.json', result)
            need(prepared['exit'] == 0, 'actual composition elaboration failed')
            graph = json.loads((folder / f'{side}_original.json').read_text())['modules'][top]
            if args.top == 'fifo' and side == 'gate' and raw == 1:
                need(graph['netnames']['raw_data']['bits'] == graph['netnames']['Impl_Inst.reg_head']['bits'], 'raw profile does not expose retained head')
            qs = {b for c in graph['cells'].values() if c['type'] == '$_DFF_P_' for b in c['connections']['Q']}
            fields = sorted(n for n, wire in graph['netnames'].items() if not wire.get('hide_name')
                            and re.search(r'(?:^|\.)(?:r_|reg_|cnt_|read_bank_q)', n)
                            and any(b in qs for b in wire['bits']) and all(b in qs or b in ('0', '1') for b in wire['bits']))
            cut, layout = observe(graph, fields)
            audit_cut(graph, cut, layout)
            layouts[side] = layout['aliases']
            ports[side] = {n: (p['direction'], len(p['bits'])) for n, p in cut['ports'].items()}
            cut['attributes'].pop('top', None)
            dump(folder / f'{side}_state.json', layout)
            dump(folder / f'{side}_cut.json', dict(modules={'step': cut}))
            expected = 0
            for name, bits in layout['aliases'].items():
                if name.endswith('r_prefer_fc'):
                    need(len(bits) == 1, 'single preference FF required')
                    expected |= 1 << bits[0]
            # Reconnect public aliases after D/Q observation before BLIF export.
            # Without this, shared macro address aliases can be emitted twice.
            # The exact original cut above remains independently audited.
            script = f'read_json "{folder}/{side}_cut.json"\nhierarchy -check -top step\nopt_clean -purge\ncheck -assert\nwrite_blif "{folder}/{side}_raw.blif"\nsat -set i_rstn 0 -prove n_state {layout["state_bits"]}\'d{expected} -verify\n'
            (folder / f'{side}_reset.ys').write_text(script)
            reset = execute(['yosys', '-Q', '-T', '-s', str(folder / f'{side}_reset.ys')], folder / f'{side}_reset.log', 180)
            reset['passed'] = reset['exit'] == 0 and (folder / f'{side}_reset.log').read_text().count('SAT proof finished - no model found: SUCCESS!') == 1
            row['reset'].append(reset)
            need(reset['passed'], 'independent complete reset-state check failed')
            live, audit = prune_dead_names((folder / f'{side}_raw.blif').read_text())
            (folder / f'{side}.blif').write_text(live)
            dump(folder / f'{side}_prune.json', audit)
        need(layouts['gold'] == layouts['gate'] and ports['gold'] == ports['gate'], 'complete state/port relation differs')
        command = f'cec -T 120 -v "{folder}/gold.blif" "{folder}/gate.blif"'
        (folder / 'command.txt').write_text(command + '\n')
        proof = execute(['stdbuf', '-oL', '-eL', 'yosys-abc', '-c', command], folder / 'cec.log', 150)
        status = outcome(proof, (folder / 'cec.log').read_text())
        row.update(proof=proof, status=status, qualified=status == 'equivalent',
                   state_bits=layout['state_bits'], outputs=sum(bits for direction, bits in ports['gate'].values() if direction == 'output'))
        dump(stage / 'results.json', result)
        print(width, depth, raw, status, proof, flush=True)
    result['complete'] = len(result['results']) == len(configs) and all(r['qualified'] for r in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
