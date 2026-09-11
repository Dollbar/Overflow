"""Run python3 verification/tl_tx_qualification/run_header_visibility.py --label NEW
[--widths 8 9 10 11 12 13 14 15 16] [--fault payload|has_data].
Compare frozen masked-input channels with actual raw-profile channels, including
every public output and all eight next-state bits with arbitrary inputs/state.
Outputs source snapshots, audited D/Q graphs, BLIF and CEC/reset logs under
build/verification/tl_tx_qualification/NEW. Next prove FIFO composition and run
production regressions/STA; this local identity is not full-IP signoff.
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

REFERENCE = '6839cac6a0e789fdef41787ae6da3e8546e896b2'
NAMES = ('tl_tx_channels.v', 'tl_tx_packer_core.v', 'tl_credit_admission.v',
         'tl_control_decode.v', 'tl_control_tenure.v')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--widths', type=int, nargs='+', choices=range(8, 17), default=list(range(8, 17)))
    parser.add_argument('--fault', choices=('payload', 'has_data'))
    parser.add_argument('--rtl-root', type=Path, default=ROOT / 'rtl', help='optional isolated candidate RTL tree')
    args = parser.parse_args()
    need(args.label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    need(len(args.widths) == len(set(args.widths)), 'duplicate width')
    stage = ROOT / 'build/verification/tl_tx_qualification' / args.label
    stage.mkdir(parents=True, exist_ok=False)
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    reference = {name: subprocess.check_output(
        ['git', 'show', f'{REFERENCE}:rtl/tl/{name}'], cwd=ROOT).decode() for name in NAMES}
    # Preserve the frozen public interface in both wrappers. Only the source
    # qualification sees unmasked words on the gate side.
    header = reference['tl_tx_channels.v'].split(');', 1)[0]
    header = header.replace('module tl_tx_channels ', 'module header_visibility ', 1)
    port_names = list(dict.fromkeys(re.findall(r'\b[io]_[a-zA-Z0-9_]+\b', header)))
    snapshots = {}
    for side in ('gold', 'gate'):
        folder = stage / 'sources' / side
        folder.mkdir(parents=True)
        snapshots[side] = []
        for name in NAMES:
            content = reference[name] if side == 'gold' else (args.rtl_root.resolve() / 'tl' / name).read_text()
            if side == 'gate' and name == 'tl_tx_channels.v' and args.fault:
                old, new = {
                    'payload': ('!RAW_HEADERS||i_header_valid[selected_class]', "1'b1"),
                    'has_data': ('(!RAW_HEADERS||i_header_valid[lane])&&', ''),
                }[args.fault]
                alternatives = [old, old.replace('!RAW_HEADERS', '(RAW_HEADERS==0)')]
                sites = [site for site in alternatives if site in content]
                need(len(sites) == 1, 'actual mutation site missing or ambiguous')
                old = sites[0]
                need(content.count(old) == 1, 'actual mutation site changed')
                content = content.replace(old, new)
            path = folder / name
            path.write_text(content)
            snapshots[side].append(path)
        wrapper = header + ');\nwire [511:0] visible_headers,visible_tags;\n'
        for lane in range(2):
            for name in ('headers', 'tags'):
                wrapper += f"assign visible_{name}[{lane*256}+:256]=i_header_valid[{lane}]?i_{name}[{lane*256}+:256]:256'd0;\n"
        params = '.WIDTH(WIDTH)' + (',.RAW_HEADERS(1)' if side == 'gate' else '')
        connections = []
        for name in port_names:
            value = 'visible_' + name[2:] if side == 'gold' and name in ('i_headers', 'i_tags') else name
            connections.append(f'.{name}({value})')
        wrapper += f'tl_tx_channels #({params}) Impl_Inst(' + ','.join(connections) + ');\nendmodule\n'
        path = folder / 'header_visibility.v'
        path.write_text(wrapper)
        snapshots[side].append(path)
    result = dict(complete=False, reference_commit=REFERENCE, fault=args.fault,
                  scope='all channel outputs and eight next-state bits; arbitrary state and inputs',
                  sources={str(p): sha(p) for paths in snapshots.values() for p in paths},
                  results=[], full_goal_complete=False)
    dump(stage / 'results.json', result)
    for width in args.widths:
        folder = stage / f'w{width}'
        folder.mkdir()
        layouts, ports = {}, {}
        row = dict(width=width, reset=[], qualified=False)
        result['results'].append(row)
        for side in ('gold', 'gate'):
            script = '\n'.join(f'read_verilog "{p}"' for p in snapshots[side])
            script += f'\nchparam -set WIDTH {width} header_visibility\nprep -top header_visibility -flatten\ntechmap\nopt -full\ndffunmap\nopt_clean\ncheck -assert\nwrite_json "{folder}/{side}_original.json"\n'
            (folder / f'{side}_prepare.ys').write_text(script)
            prepared = execute(['yosys', '-Q', '-T', '-s', str(folder / f'{side}_prepare.ys')], folder / f'{side}_prepare.log', 120)
            row[f'{side}_prepare'] = prepared
            dump(stage / 'results.json', result)
            need(prepared['exit'] == 0, 'actual profile elaboration failed')
            graph = json.loads((folder / f'{side}_original.json').read_text())['modules']['header_visibility']
            qs = {b for c in graph['cells'].values() if c['type'] == '$_DFF_P_' for b in c['connections']['Q']}
            fields = sorted(n for n, wire in graph['netnames'].items() if not wire.get('hide_name')
                            and re.search(r'(?:^|\.)r_', n) and any(b in qs for b in wire['bits'])
                            and all(b in qs or b in ('0', '1') for b in wire['bits']))
            cut, layout = observe(graph, fields)
            need(audit_cut(graph, cut, layout) == 8, 'actual state inventory changed')
            layouts[side] = layout['aliases']
            ports[side] = {n: (p['direction'], len(p['bits'])) for n, p in cut['ports'].items()}
            cut['attributes'].pop('top', None)
            dump(folder / f'{side}_state.json', layout)
            dump(folder / f'{side}_cut.json', dict(modules={'step': cut}))
            pref = next(bits for name, bits in layout['aliases'].items() if name.endswith('r_prefer_fc'))
            need(len(pref) == 1, 'single preference FF required')
            output_proofs = ''.join(f' -prove {n} 0' for n, p in graph['ports'].items() if p['direction'] == 'output')
            script = f'read_json "{folder}/{side}_cut.json"\nhierarchy -check -top step\ncheck -assert\nwrite_blif "{folder}/{side}_raw.blif"\nsat -set i_rstn 0 -prove n_state 8\'d{1 << pref[0]}{output_proofs} -verify\n'
            (folder / f'{side}_reset.ys').write_text(script)
            reset = execute(['yosys', '-Q', '-T', '-s', str(folder / f'{side}_reset.ys')], folder / f'{side}_reset.log', 120)
            reset['passed'] = reset['exit'] == 0 and (folder / f'{side}_reset.log').read_text().count('SAT proof finished - no model found: SUCCESS!') == 1
            row['reset'].append(reset)
            need(reset['passed'], 'independent reset check failed')
            live, audit = prune_dead_names((folder / f'{side}_raw.blif').read_text())
            (folder / f'{side}.blif').write_text(live)
            dump(folder / f'{side}_prune.json', audit)
        need(layouts['gold'] == layouts['gate'] and ports['gold'] == ports['gate'], 'complete state/port correspondence changed')
        command = f'cec -T 120 -v "{folder}/gold.blif" "{folder}/gate.blif"'
        (folder / 'command.txt').write_text(command + '\n')
        proof = execute(['stdbuf', '-oL', '-eL', 'yosys-abc', '-c', command], folder / 'cec.log', 150)
        status = outcome(proof, (folder / 'cec.log').read_text())
        row.update(proof=proof, status=status, qualified=status == ('different' if args.fault else 'equivalent'))
        dump(stage / 'results.json', result)
        print(width, status, proof, flush=True)
    result['complete'] = all(row['qualified'] for row in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
