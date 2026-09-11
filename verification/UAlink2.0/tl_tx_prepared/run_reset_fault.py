"""Run python3 verification/tl_tx_prepared/run_reset_fault.py --label NEW_LABEL
[--pair mapped_pair] [--physical physical_baseline] [--widths 8 16]. Changes one actual mapped DFQD D pin to i_done, preserving its
Q/clock and every other mapped cell. Outputs exact mutation, normalized actual
D/Q inventory and reset SAT witnesses. Next qualify output/capture faults and
complete mapped sequential correspondence; this negative alone is not a proof.
"""
from pathlib import Path
import argparse
import copy
import json

from run_reset_state import ROOT, reset_inventory, reset_wrapper, audit_cut, dump, execute, need, sha
from mapped_state import observe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--pair', default='mapped_pair')
    parser.add_argument('--physical', default='physical_baseline')
    parser.add_argument('--widths', type=int, nargs='+', choices=(8, 16), default=[8, 16])
    args = parser.parse_args()
    for label in (args.label, args.pair, args.physical):
        need(label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    need(len(args.widths) == len(set(args.widths)), 'duplicate widths')
    base = ROOT / 'build/verification/tl_tx_prepared'
    physical = base / args.physical
    baseline = json.loads((physical / 'results.json').read_text())
    library = Path(baseline['libraries']['ssg0p81v125c']['path'])
    need(sha(library) == baseline['libraries']['ssg0p81v125c']['sha256'], 'library changed')
    blackbox = next(Path(p) for p in baseline['sources'] if p.endswith('kd28_sram_blackboxes.v'))
    need(sha(blackbox) == baseline['sources'][str(blackbox)], 'SRAM interface changed')
    stage = base / args.label
    stage.mkdir(exist_ok=False)
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    (stage / 'reset_runner.py').write_bytes(Path(__file__).with_name('run_reset_state.py').read_bytes())
    result = dict(complete=False, scope='actual mapped reset-D fault qualification',
                  pair=args.pair, physical=args.physical, library_sha256=sha(library), results=[], mapped_equivalence=False, full_goal_complete=False)
    field = 'Buffered_Inst.Channels_Inst.Packer_Inst.r_prefer_fc'
    for width in args.widths:
        folder = stage / f'w{width}'
        folder.mkdir()
        source = physical / f'w{width}/mapped.json'
        original = json.loads(source.read_text())['modules']['tl_tx_prepared']
        changed = copy.deepcopy(original)
        q = original['netnames'][field]['bits']
        targets = [n for n, c in original['cells'].items()
                   if c['type'] == 'DFQD2BWP40P140' and c['connections']['Q'] == q]
        need(len(targets) == 1, 'one actual mapped FF required')
        target = targets[0]
        changed['cells'][target]['connections']['D'] = original['ports']['i_done']['bits']
        need(original['cells'][target]['connections']['D'] != changed['cells'][target]['connections']['D'],
             'fault must change the real D pin')
        restored = copy.deepcopy(changed)
        restored['cells'][target]['connections']['D'] = original['cells'][target]['connections']['D']
        need(restored == original, 'unintended mapped mutation')
        dump(folder / 'mutation.json', dict(source_sha256=sha(source), field=field, cell=target,
                                           before=original['cells'][target], after=changed['cells'][target]))
        dump(folder / 'mapped_fault.json', dict(modules={'tl_tx_prepared': changed}))
        script = f'read_verilog -lib "{blackbox}"\nread_liberty -ignore_miss_func "{library}"\nread_json "{folder}/mapped_fault.json"\nprep -top tl_tx_prepared -flatten\nselect -assert-count 64 tl_tx_prepared/t:KD28_SRAM_SDP_256X32\nexpose -evert tl_tx_prepared/t:KD28_SRAM_*\ntechmap\nopt -full\ndffunmap\nopt_clean\ncheck -assert\nwrite_json "{folder}/observed.json"\n'
        (folder / 'prepare.ys').write_text(script)
        prepared = execute(['yosys', '-Q', '-T', '-s', str(folder / 'prepare.ys')], folder / 'prepare.log', 180)
        row = dict(width=width, prepare=prepared, detected=False)
        result['results'].append(row)
        dump(stage / 'results.json', result)
        need(prepared['exit'] == 0, 'actual mutant preparation failed')
        graph = json.loads((folder / 'observed.json').read_text())['modules']['tl_tx_prepared']
        healthy_layout = json.loads((base / args.pair / f'w{width}/gate_state.json').read_text())
        cut, layout = observe(graph, list(healthy_layout['aliases']))
        audit_cut(graph, cut, layout)
        need(layout['aliases'] == healthy_layout['aliases'], 'fault changed actual state layout')
        cut['attributes'].pop('top', None)
        dump(folder / 'cut.json', dict(modules={'step_gate': cut}))
        dump(folder / 'state.json', layout)
        observed, dormant = reset_inventory(layout, 'gate')
        dump(folder / 'reset_inventory.json', dict(observed=observed, dormant=dormant))
        (folder / 'reset.v').write_text(reset_wrapper('gate', cut, layout, observed))
        script = f'read_json "{folder}/cut.json"\nread_verilog "{folder}/reset.v"\nprep -top reset_step -flatten\nopt -full\ncheck -assert\nwrite_json "{folder}/reset.json"\nsat -prove o_bad 0 -verify -show-inputs -show o_bad -dump_json "{folder}/witness.json"\n'
        (folder / 'proof.ys').write_text(script)
        proof = execute(['yosys', '-Q', '-T', '-s', str(folder / 'proof.ys')], folder / 'proof.log', 120)
        log = (folder / 'proof.log').read_text()
        row.update(proof=proof, detected=proof['exit'] == 1 and
                   'SAT proof finished - model found: FAIL!' in log and (folder / 'witness.json').is_file())
        dump(stage / 'results.json', result)
        print(width, row['detected'], proof, flush=True)
    result['complete'] = len(result['results']) == len(args.widths) and all(r['detected'] for r in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
