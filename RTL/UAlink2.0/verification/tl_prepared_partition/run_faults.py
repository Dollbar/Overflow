"""Run python3 verification/tl_prepared_partition/run_faults.py --unit-label unit
[--label faults] [--candidate FILE]. Compiles real mutated RTL against completed independent vectors.
Outputs compile/run logs, actual mismatches and candidate hashes. Compile failure
or timeout is not a detection. Next audit the positive and negative evidence.
"""
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'verification/tl_partition_mapping'))
from run_cec import dump, execute, need, sha

FAULTS = {
    'overwrite_owned': ('if(o_captured)begin', 'if(i_source_valid)begin'),
    'retire_early': ("selected_end==4'd8", "selected_end!=4'd0"),
    'ignore_ready': ('o_taken=o_valid&&i_ready', 'o_taken=o_valid'),
    'lose_replacement': ('if(o_source_ready)r_owned<=i_source_valid;', "if(o_group_done)r_owned<=1'b0;else if(o_source_ready)r_owned<=i_source_valid;"),
    'reset_cursor': ("r_owned<=1'b0;r_cursor<=4'd0", "r_owned<=1'b0;r_cursor<=r_cursor"),
    'live_done': ('o_valid=i_rstn&&r_owned', 'o_valid=i_rstn&&i_done&&r_owned'),
    'live_capacity': ('need<=r_capacity[', 'need<=i_capacity['),
    'missing_data_credit': ('r_counts<=source_counts', "r_counts<=32'd0"),
    'wrong_account': ('r_slots<=source_slots', "r_slots<=40'd0"),
    'wrong_tags': ('tags_offset_one=before_fields[0]', "tags_offset_one=(1'b0)"),
    'excess_auth_fields': ("(!r_auth||(prefix_fields[boundary]<=4'd4))", "1'b1"),
    'accept_bad_format': ('r_error<=format_error', "r_error<=1'b0"),
    'lose_shared_pool': ('r_shared<=i_shared', "r_shared<=1'b0"),
    'capture_invalid': ('o_captured=o_source_ready&&i_source_valid', 'o_captured=o_source_ready'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--unit-label', default='unit')
    parser.add_argument('--label', default='faults')
    parser.add_argument('--candidate',type=Path,default=ROOT/'rtl/tl/tl_prepared_partition.v')
    args = parser.parse_args()
    for name in (args.unit_label, args.label): need(name.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    base = ROOT / 'build/verification/tl_prepared_partition'
    unit = base / args.unit_label; healthy = json.loads((unit / 'results.json').read_text())
    need(healthy['complete'], 'healthy unit run required')
    for name, digest in healthy['sources'].items(): need(sha(Path(name)) == digest, 'healthy source identity')
    source_path = args.candidate.resolve(); source = source_path.read_text()
    stage = base / args.label; stage.mkdir(parents=True, exist_ok=False)
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    result = dict(complete=False, source_sha256=sha(source_path), healthy_sha256=sha(unit / 'results.json'), results=[])
    for name, (old, new) in FAULTS.items():
        need(source.count(old) == 1, f'fault anchor ambiguous: {name}')
        folder = stage / name; folder.mkdir()
        candidate = folder / source_path.name; candidate.write_text(source.replace(old, new))
        for width in (8, 16):
            need(any(r['width'] == width and r['passed'] for r in healthy['results']), 'missing healthy width')
            output = folder / f'w{width}'; output.mkdir()
            fixture = unit / f'w{width}'
            for file in ('vectors.hex', 'expected.hex'): (output / file).write_bytes((fixture / file).read_bytes())
            tb = output / 'tb.sv'; tb.write_text((fixture / 'tb.sv').read_text().replace(str(fixture), str(output)))
            sources = [candidate, unit / 'sources/tl_control_decode.v', unit / 'sources/tl_control_tenure.v']
            compile_result = execute(['iverilog', '-g2012', '-s', 'tb', '-o', str(output / 'sim.vvp'), *map(str, sources), str(tb)], output / 'compile.log', 90)
            row = dict(fault=name, width=width, candidate_sha256=sha(candidate), compile=compile_result, detected=False)
            if compile_result['exit'] == 0:
                run = execute(['vvp', str(output / 'sim.vvp')], output / 'run.log', 120)
                log = (output / 'run.log').read_text()
                row.update(run=run, detected=run['exit'] not in (0, 124) and 'FATAL:' in log and 'prepared vector ' in log)
            result['results'].append(row); dump(stage / 'results.json', result)
            print(name, width, row['detected'], flush=True)
    result['complete'] = len(result['results']) == 2*len(FAULTS) and all(r['detected'] for r in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
