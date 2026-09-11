"""Run python3 verification/tl_tx_prepared/run_capture_fault.py --label NEW_LABEL
[--pair mapped_pair] [--physical physical_baseline] [--widths 8 16]. Mutate one actual mapped preparation payload FF D pin to the
neighboring old payload Q. Prove the dormant/capture checker detects this real
failure with independent old payloads at an actual capture. Outputs complete
mapped mutation, D/Q inventories and SAT witnesses; next audit proof composition.
"""
from pathlib import Path
import argparse
import copy
import json

from run_dormant_state import ROOT, dormant_wrapper, dormant_inventory, audit_cut, dump, execute, need, sha
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
    (stage / 'dormant_runner.py').write_bytes(Path(__file__).with_name('run_dormant_state.py').read_bytes())
    result = dict(complete=False, scope='actual mapped payload-D fault qualification for dormant/capture proof',
                  pair=args.pair, physical=args.physical, library_sha256=sha(library), results=[], mapped_equivalence=False, full_goal_complete=False)
    field = 'gen_prepare[0].Prepare_Inst.r_control'
    for width in args.widths:
        folder = stage / f'w{width}'
        folder.mkdir()
        source = physical / f'w{width}/mapped.json'
        original = json.loads(source.read_text())['modules']['tl_tx_prepared']
        changed = copy.deepcopy(original)
        q = original['netnames'][field]['bits']
        targets = [n for n, c in original['cells'].items()
                   if c['type'] == 'DFQD2BWP40P140' and c['connections']['Q'] == [q[0]]]
        need(len(targets) == 1, 'one actual mapped payload FF required')
        target = targets[0]
        changed['cells'][target]['connections']['D'] = [q[1]]
        need(original['cells'][target]['connections']['D'] != [q[1]], 'fault must change actual D')
        restored = copy.deepcopy(changed)
        restored['cells'][target]['connections']['D'] = original['cells'][target]['connections']['D']
        need(restored == original, 'unintended mapped mutation')
        dump(folder / 'mutation.json', dict(source_sha256=sha(source), field=field, cell=target,
                                           before=original['cells'][target], after=changed['cells'][target]))
        dump(folder / 'mapped_fault.json', dict(modules={'tl_tx_prepared': changed}))
        script = f'read_verilog -lib "{blackbox}"\nread_liberty -ignore_miss_func "{library}"\nread_json "{folder}/mapped_fault.json"\nprep -top tl_tx_prepared -flatten\nselect -assert-count 64 tl_tx_prepared/t:KD28_SRAM_SDP_256X32\nexpose -evert tl_tx_prepared/t:KD28_SRAM_*\ntechmap\nopt -full\ndffunmap\nopt_clean\ncheck -assert\nwrite_json "{folder}/observed.json"\n'
        (folder / 'prepare.ys').write_text(script)
        prepare = execute(['yosys', '-Q', '-T', '-s', str(folder / 'prepare.ys')], folder / 'prepare.log', 180)
        row = dict(width=width, lane=0, prepare=prepare, detected=False)
        result['results'].append(row)
        dump(stage / 'results.json', result)
        need(prepare['exit'] == 0, 'actual payload mutant preparation failed')
        graph = json.loads((folder / 'observed.json').read_text())['modules']['tl_tx_prepared']
        healthy = json.loads((base / args.pair / f'w{width}/gate_state.json').read_text())
        cut, layout = observe(graph, list(healthy['aliases']))
        audit_cut(graph, cut, layout)
        need(layout['aliases'] == healthy['aliases'], 'fault changed actual state layout')
        cut['attributes'].pop('top', None)
        dump(folder / 'cut.json', dict(modules={'step_gate': cut}))
        dump(folder / 'state.json', layout)
        payload, fixed, observed = dormant_inventory(layout, 0)
        dump(folder / 'inventory.json', dict(independent_payload=payload, fixed_owner_cursor=fixed, observed_next_state=observed))
        (folder / 'dormant.v').write_text(dormant_wrapper(cut, layout, 0))
        script = f'read_json "{folder}/cut.json"\nread_verilog "{folder}/dormant.v"\nprep -top dormant_step -flatten\nopt -full\ncheck -assert\nwrite_json "{folder}/dormant.json"\nsat -prove o_bad 0 -verify -show i_rstn -show i_done -show i_source_valid -show independent_left -show independent_right -show next_left -show next_right -show o_bad -dump_json "{folder}/witness.json"\n'
        (folder / 'proof.ys').write_text(script)
        proof = execute(['yosys', '-Q', '-T', '-s', str(folder / 'proof.ys')], folder / 'proof.log', 180)
        log = (folder / 'proof.log').read_text()
        row.update(proof=proof, detected=proof['exit'] == 1 and 'SAT proof finished - model found: FAIL!' in log
                   and (folder / 'witness.json').is_file())
        dump(stage / 'results.json', result)
        print(width, row['detected'], proof, flush=True)
    result['complete'] = len(result['results']) == len(args.widths) and all(r['detected'] for r in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
