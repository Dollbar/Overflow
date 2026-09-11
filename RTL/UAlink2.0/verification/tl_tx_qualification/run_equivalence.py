"""Run python3 verification/tl_tx_qualification/run_equivalence.py --label NEW_LABEL
[--widths 8 9 10 11 12 13 14 15 16] [--tops tl_tx_packer tl_tx_channels]
[--replace FILE --expect-different]. Compare all public outputs and every actual
FF next-state bit against frozen 1f917a1 RTL, plus independent reset SAT.
Outputs exact source snapshots, D/Q graphs, BLIF and proof logs. Next actual
integrated regressions and current production mapping/STA; no full-IP signoff.
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--widths', type=int, nargs='+', choices=range(8, 17), default=list(range(8, 17)))
    parser.add_argument('--tops', nargs='+', choices=('tl_tx_packer', 'tl_tx_channels'), default=['tl_tx_packer', 'tl_tx_channels'])
    parser.add_argument('--replace', type=Path)
    parser.add_argument('--expect-different', action='store_true')
    args = parser.parse_args()
    need(args.label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    need(len(args.widths) == len(set(args.widths)) and len(args.tops) == len(set(args.tops)), 'duplicate configuration')
    need(not args.expect_different or args.replace, 'negative must use an actual RTL replacement')
    base = ROOT / 'build/verification/tl_tx_qualification'
    reference_commit = '1f917a1381277a080a700849d638d39b766c665a'
    stage = base / args.label
    stage.mkdir(parents=True, exist_ok=False)
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    source_names = ['tl_tx_packer.v', 'tl_tx_channels.v', 'tl_credit_admission.v', 'tl_control_decode.v', 'tl_control_tenure.v']
    # Fetch the frozen reference from local Git objects, so a fresh clone does
    # not depend on manually retained build directories or copied old RTL.
    reference_sources = {name: subprocess.check_output(
        ['git', 'show', f'{reference_commit}:rtl/tl/{name}'], cwd=ROOT)
        for name in source_names}
    snapshots = {}
    for side in ('gold', 'gate'):
        folder = stage / 'sources' / side
        folder.mkdir(parents=True)
        names = source_names + (['tl_tx_packer_core.v'] if side == 'gate' else [])
        snapshots[side] = []
        for name in names:
            path = ROOT / 'rtl/tl' / name
            if side == 'gold':
                content = reference_sources[name]
            elif args.replace and args.replace.name == name:
                path = args.replace.resolve()
                content = path.read_bytes()
            else:
                content = path.read_bytes()
            (folder / name).write_bytes(content)
            snapshots[side].append(folder / name)
    result = dict(complete=False, reference_commit=reference_commit,
                  sources={str(p): sha(p) for paths in snapshots.values() for p in paths},
                  expected_different=args.expect_different, results=[], full_goal_complete=False)
    for top in args.tops:
        for width in args.widths:
            folder = stage / f'{top}_w{width}'
            folder.mkdir()
            layouts, ports, row = {}, {}, dict(top=top, width=width, reset=[], equivalent=False)
            result['results'].append(row)
            dump(stage / 'results.json', result)
            for side in ('gold', 'gate'):
                script = '\n'.join(f'read_verilog "{p}"' for p in snapshots[side]) + f'\nchparam -set WIDTH {width} {top}\nprep -top {top} -flatten\ntechmap\nopt -full\ndffunmap\nopt_clean\ncheck -assert\nwrite_json "{folder}/{side}_original.json"\n'
                (folder / f'{side}_prepare.ys').write_text(script)
                prepared = execute(['yosys', '-Q', '-T', '-s', str(folder / f'{side}_prepare.ys')], folder / f'{side}_prepare.log', 120)
                need(prepared['exit'] == 0, 'actual equivalence elaboration failed')
                graph = json.loads((folder / f'{side}_original.json').read_text())['modules'][top]
                qs = {b for c in graph['cells'].values() if c['type'] == '$_DFF_P_' for b in c['connections']['Q']}
                fields = sorted(n for n, wire in graph['netnames'].items() if not wire.get('hide_name')
                                and re.search(r'(?:^|\.)r_', n) and any(b in qs for b in wire['bits'])
                                and all(b in qs or b in ('0', '1') for b in wire['bits']))
                cut, layout = observe(graph, fields)
                need(audit_cut(graph, cut, layout) == (4 if top == 'tl_tx_packer' else 8), 'actual state inventory changed')
                layouts[side] = {n.removeprefix('Core_Inst.') if top == 'tl_tx_packer' else n: bits
                                 for n, bits in layout['aliases'].items()}
                ports[side] = {n: (p['direction'], len(p['bits'])) for n, p in cut['ports'].items()}
                cut['attributes'].pop('top', None)
                dump(folder / f'{side}_state.json', layout)
                dump(folder / f'{side}_cut.json', dict(modules={'step': cut}))
                pref = next(bits for name, bits in layout['aliases'].items() if name.endswith('r_prefer_fc'))
                need(len(pref) == 1, 'single actual preference FF required')
                expected = 1 << pref[0]
                output_proofs = ''.join(f' -prove {n} 0' for n, p in graph['ports'].items() if p['direction'] == 'output')
                script = f'read_json "{folder}/{side}_cut.json"\nhierarchy -check -top step\ncheck -assert\nwrite_blif "{folder}/{side}_raw.blif"\nsat -set i_rstn 0 -prove n_state {layout["state_bits"]}\'d{expected}{output_proofs} -verify -dump_json "{folder}/{side}_reset_witness.json"\n'
                (folder / f'{side}_reset.ys').write_text(script)
                reset = execute(['yosys', '-Q', '-T', '-s', str(folder / f'{side}_reset.ys')], folder / f'{side}_reset.log', 120)
                reset['passed'] = reset['exit'] == 0 and (folder / f'{side}_reset.log').read_text().count('SAT proof finished - no model found: SUCCESS!') == 1
                row['reset'].append(reset)
                need(reset['passed'], 'independent reset correspondence failed')
                live, audit = prune_dead_names((folder / f'{side}_raw.blif').read_text())
                (folder / f'{side}.blif').write_text(live)
                dump(folder / f'{side}_prune.json', audit)
            need(layouts['gold'] == layouts['gate'] and ports['gold'] == ports['gate'], 'state/port correspondence changed')
            command = f'cec -T 120 -v "{folder}/gold.blif" "{folder}/gate.blif"'
            (folder / 'command.txt').write_text(command + '\n')
            proof = execute(['stdbuf', '-oL', '-eL', 'yosys-abc', '-c', command], folder / 'cec.log', 150)
            status = outcome(proof, (folder / 'cec.log').read_text())
            row.update(proof=proof, status=status, equivalent=status == 'equivalent',
                       qualified=status == ('different' if args.expect_different else 'equivalent'))
            dump(stage / 'results.json', result)
            print(top, width, status, proof, flush=True)
    result['complete'] = len(result['results']) == len(args.tops) * len(args.widths) and all(r['qualified'] for r in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
