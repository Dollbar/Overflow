"""Run python3 verification/tl_prepared_partition/run_rtl.py [--label unit]
[--widths 8 16] [--replace FILE]. Outputs vectors, expected/actual edge traces,
source snapshots and logs under build/verification/tl_prepared_partition/LABEL.
Next: real faults, dual peers, structural checks and process timing.
"""
from pathlib import Path
import argparse
import hashlib
import itertools
import json
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'model/tl'))
from prepared_partition import PreparedPartitioner


def pack(values, width):
    return sum(int(v) << (i*width) for i, v in enumerate(values))


def fields(rng, response, case):
    """Construct independent naturally aligned fixtures, with arbitrary payload bits."""
    word = 0; sector = 0
    while sector < 8:
        kinds = [0, 4, 5] if response else [0]
        if sector % 2 == 0: kinds += [2] if response else [3]
        if not response and sector % 4 == 0: kinds += [1]
        kind = rng.choice(kinds); vc = rng.randrange(4); pool = rng.randrange(2)
        count = case % 4
        if kind == 1:
            size = 4; value = (rng.getrandbits(128) & ~((15 << 124) | (63 << 118) | (3 << 116) | (1 << 102) | 3)) | (1 << 124) | ((3, 35, 38, 39, 40, 41, 48)[case % 7] << 118) | (vc << 116) | (pool << 102) | (0 if case % 7 == 6 else count)
        elif kind == 2:
            size = 2; value = (2 << 60) | (vc << 58) | (pool << 46) | (count << 44) | ((case % 2) << 37) | (rng.getrandbits(8) << 47)
        elif kind == 3:
            size = 2; value = (3 << 60) | ((case % 8) << 57) | (vc << 55) | (pool << 41) | (count << 39) | rng.getrandbits(30)
        elif kind == 4:
            size = 1; value = (4 << 28) | (vc << 26) | (pool << 14) | (rng.getrandbits(8) << 15)
        elif kind == 5:
            size = 1; value = (5 << 28) | (vc << 26) | (pool << 14) | (rng.getrandbits(8) << 15) | (count << 2) | ((case % 2) << 1)
        else:
            size = 1; value = 0
        word |= value << (32*sector); sector += size
    return word


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', default='unit')
    parser.add_argument('--widths', type=int, nargs='+', choices=range(8, 17), default=[8, 16])
    parser.add_argument('--replace', type=Path)
    args = parser.parse_args()
    if not args.label.replace('_', '').replace('-', '').isalnum(): parser.error('invalid label')
    stage = ROOT / 'build/verification/tl_prepared_partition' / args.label
    stage.mkdir(parents=True, exist_ok=False)
    sources = [args.replace or ROOT / 'rtl/tl/tl_prepared_partition.v'] + [ROOT / 'rtl/tl' / n for n in ('tl_control_decode.v', 'tl_control_tenure.v')]
    snapshots = stage / 'sources'; snapshots.mkdir()
    for source in sources:
        if source.is_file(): (snapshots / source.name).write_bytes(source.read_bytes())
    identities = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources if p.exists()}
    compile_sources = [snapshots / p.name for p in sources]
    for source in [Path(__file__), ROOT / 'model/tl/prepared_partition.py', ROOT / 'model/tl/control_partition.py', ROOT / 'model/tl/credit_admission.py', ROOT / 'model/tl/credit_context.py', ROOT / 'model/tl/tl_tenure.py']:
        (snapshots / source.name).write_bytes(source.read_bytes())
    results = []
    for width in args.widths:
        folder = stage / f'w{width}'; folder.mkdir()
        model = PreparedPartitioner(); rng = random.Random(8531); vectors = []; answers = []
        inputs = [('rstn', 1), ('source_valid', 1), ('ready', 1), ('done', 1), ('response', 1), ('auth', 1), ('shared', 1), ('source_control', 256), ('source_tags', 512), ('capacity', 20*(width+1))]
        outputs = [('valid', 1), ('taken', 1), ('group_done', 1), ('error', 1), ('shortfall', 1), ('word', 256), ('tags', 256), ('fields', 4), ('end', 4), ('cursor', 4), ('source_ready', 1), ('captured', 1)]
        counts = dict(captured=0, group_done=0, taken=0, cancelled=0, error=0, shortfall=0, stalled=0, replaced=0, done_low_valid=0, partial_reset=0)
        def add(word=0, tags=0, caps=None, **kw):
            caps = caps if caps is not None else [0]*20
            reset = kw.get('reset', False); was_owned = model.owned is not None
            if reset and was_owned:
                counts['cancelled'] += 1
                counts['partial_reset'] += int(model.cursor != 0)
            out = model.step(word, tags, caps, **kw)
            data = dict(rstn=not reset, source_valid=kw.get('valid', True), ready=kw.get('ready', True), done=kw.get('done', True), response=kw.get('response', False), auth=kw.get('auth', False), shared=kw.get('shared', False), source_control=word, source_tags=tags, capacity=pack(caps, width+1))
            for k in ('captured', 'group_done', 'taken', 'error', 'shortfall'): counts[k] += int(out[k])
            counts['stalled'] += int(out['valid'] and not data['ready'])
            counts['replaced'] += int(out['captured'] and out['group_done'])
            counts['done_low_valid'] += int(out['valid'] and not data['done'])
            if counts['captured'] - counts['group_done'] - counts['cancelled'] != int(model.owned is not None): raise RuntimeError('ownership conservation violated')
            v = 0; shift = 0
            for k, b in inputs: v |= int(data[k]) << shift; shift += b
            vectors.append(v); v = 0; shift = 0
            for k, b in outputs: v |= int(out[k]) << shift; shift += b
            answers.append(v)
            return out
        single = (2 << 60) | (1 << 37)
        word = pack([single | (j << 47) for j in range(4)], 64)
        add(reset=True); add(word, pack(range(101, 109), 64), [1]*20, response=True, auth=True)
        add(valid=False); add(reset=True); add(valid=False)
        # Same-account capacity one forces all four odd/even tag offsets to appear.
        add(word, pack(range(101, 109), 64), [1]*20, response=True, auth=True)
        for index in range(4):
            held = add(rng.getrandbits(256), rng.getrandbits(512), [0]*20, ready=False, done=False)
            if (held['tags'], held['end']) != (101+index, 2*(index+1)): raise RuntimeError('literal serial tag offset fixture')
            add(valid=False, done=False)
        add(single, 201, [8]*20, response=True, auth=True)
        for tag in range(202, 302):
            out = add(single, tag, [8]*20, response=True, auth=True)
            if not (out['captured'] and out['group_done'] and out['tags'] == tag-1): raise RuntimeError('throughput fixture failed')
        add(valid=False)
        for response, auth, shared, cap in itertools.product((False, True), (False, True), (False, True), (0, 1, 2, 4, 8, 32)):
            for case in range(24):
                caps = [cap if case % 3 else rng.choice((0, 1, 2, 4, 8, 32)) for _ in range(20)]
                if shared: caps[15] = 0
                source = fields(rng, response, case)
                # Malformed and mixed-class groups must remain owned until reset.
                if case == 0: source = 0
                elif case == 1: source = 6 << 28
                elif case == 2: source = (single if not response else 3 << 60)
                elif case == 3: source = single | (1 << 64)
                add(reset=True)
                add(source, rng.getrandbits(512), caps, response=response, auth=auth, shared=shared, done=False)
                add(source, rng.getrandbits(512), caps, response=response, auth=auth, shared=shared, ready=False)
                for turn in range(20):
                    noise = dict(word=rng.getrandbits(256), tags=rng.getrandbits(512), caps=[rng.randrange(1 << (width+1)) for _ in range(20)], response=not response, auth=not auth, shared=not shared, valid=bool(turn % 2), done=False)
                    held = add(**noise, ready=False)
                    out = add(**noise, ready=True)
                    if out['group_done'] or out['error'] or out['shortfall']: break
                add(valid=False, done=False)
        add(reset=True); add(valid=False)
        if any(counts[k] == 0 for k in counts): raise RuntimeError(f'missing coverage {counts}')
        (folder / 'vectors.hex').write_text(''.join(f'{v:x}\n' for v in vectors))
        (folder / 'expected.hex').write_text(''.join(f'{v:x}\n' for v in answers))
        shift = 0; connections = []
        for k, b in inputs: connections.append(f'.i_{k}(v[{shift}+:{b}])'); shift += b
        input_bits = shift; shift = 0
        for k, b in outputs: connections.append(f'.o_{"control" if k == "word" else k}(actual[{shift}+:{b}])'); shift += b
        tb = f'''module tb;
reg clk=0;always #5 clk=~clk;reg [{input_bits-1}:0] v,vectors[0:{len(vectors)-1}];reg [{shift-1}:0] expected[0:{len(vectors)-1}];wire [{shift-1}:0] actual;integer j,fd;
tl_prepared_partition #(.WIDTH({width})) dut(.i_clk(clk),{','.join(connections)});
initial begin $readmemh("{folder}/vectors.hex",vectors);$readmemh("{folder}/expected.hex",expected);fd=$fopen("{folder}/actual.hex","w");for(j=0;j<{len(vectors)};j=j+1)begin @(negedge clk);v=vectors[j];#1;$fdisplay(fd,"%h",actual);if(actual!==expected[j])$fatal(1,"prepared vector %0d actual=%h expected=%h",j,actual,expected[j]);end @(negedge clk);$fclose(fd);$display("PASS prepared WIDTH={width} vectors={len(vectors)}");$finish;end
endmodule
'''
        (folder / 'tb.sv').write_text(tb)
        command = ['iverilog', '-g2012', '-s', 'tb', '-o', str(folder / 'sim.vvp'), *map(str, compile_sources), str(folder / 'tb.sv')]
        compile_result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        (folder / 'compile.log').write_text(compile_result.stdout + compile_result.stderr)
        row = dict(width=width, vectors=len(vectors), compile_exit=compile_result.returncode, passed=False, coverage=counts)
        if compile_result.returncode == 0:
            run = subprocess.run(['vvp', str(folder / 'sim.vvp')], capture_output=True, text=True, timeout=180)
            (folder / 'run.log').write_text(run.stdout + run.stderr)
            row.update(run_exit=run.returncode, passed=run.returncode == 0 and 'PASS prepared' in run.stdout)
            print(run.stdout, flush=True)
        results.append(row)
    unchanged = len(identities) == len(sources) and all(p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest() == identities.get(str(p)) for p in sources)
    report = dict(complete=unchanged and all(r['passed'] for r in results), sources_unchanged=unchanged, results=results, sources=identities)
    (stage / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
