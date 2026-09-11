"""Run the actual UART receive SRAM/FIFO path with retained evidence.

Run: python3 verification/rtl/run_uart_rx_path.py --kd28-root /authorized/root
     --depth 128 --seed 17 --cycles 20000 --half-period-ps 320
Outputs: build/uart_rx_path_*/snapshot, independent vectors, logs, summary.json.
Next: inspect wire-payload scoreboard evidence; physical SRAM timing is separate.
The external model files are read in place, hashed before/after each stage, not copied.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


DEPENDENCIES = ('Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v',
                'Library/models/kd28/sram/rtl/kd28_sram_sp_model.v',
                'Library/models/kd28/sram/rtl/kd28_sram_sdp_model.v',
                'Library/models/kd28/sram/rtl/kd28_sram_tdp_model.v',
                'Library/models/kd28/sram/rtl/kd28_sram_cells.v')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--kd28-root', type=Path, required=True)
    p.add_argument('--depth', type=int, default=128)
    p.add_argument('--seed', type=int, default=17)
    p.add_argument('--cycles', type=int, default=20000)
    p.add_argument('--half-period-ps', type=int, choices=(320, 3200), default=320)
    p.add_argument('--verilator', default='verilator')
    args = p.parse_args()
    if not 1 <= args.depth <= 4095 or args.cycles < 0:
        p.error('depth must be1..4095 and cycles nonnegative')
    root = Path(__file__).resolve().parents[2]
    external = args.kd28_root.resolve(strict=True)
    rtl = ('rtl/upli/upli_receive_fifo.v', 'rtl/upli/upli_receive_storage.v',
           'rtl/dl/dl_uart_rx_path.v')
    names = rtl+('verification/rtl/uart_rx_path_tb.v', 'verification/rtl/uart_rx_path_vectors.py',
                 'verification/rtl/run_uart_rx_path.py', 'model/ualink/receive_fifo.py',
                 'model/ualink/uart_rx_path.py',
                 'model/__init__.py', 'model/ualink/__init__.py', 'config/kd28_verilator.vlt',
                 'config/uart_rx_path_contract.json')
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    hashes = {name: sha(root/name) for name in names}
    dependency_hashes = {name: sha(external/name) for name in DEPENDENCIES}
    (root/'build').mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='uart_rx_path_', dir=root/'build'))
    snapshot = run/'snapshot'
    for name in names:
        target = snapshot/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root/name, target)
    record = dict(directory=str(run.relative_to(root)), source_sha256=hashes,
                  dependency_root=str(external), dependency_sha256=dependency_hashes,
                  seed=args.seed, depth=args.depth, random_cycles=args.cycles,
                  period_ps=args.half_period_ps*2, stages=[], passed=False,
                  verilator=subprocess.check_output([args.verilator, '--version'], text=True, timeout=20).strip())
    start = time.monotonic()
    def check_inputs():
        assert all(sha(root/name) == sha(snapshot/name) == value for name, value in hashes.items()), 'source changed'
        assert all(sha(external/name) == value for name, value in dependency_hashes.items()), 'external model changed'
    def invoke(command, log_name, timeout):
        check_inputs()
        with (run/log_name).open('w') as log:
            try:
                status = subprocess.run(command, cwd=snapshot, stdout=log, stderr=subprocess.STDOUT,
                                        timeout=timeout).returncode
            except subprocess.TimeoutExpired:
                status = 124
        record['stages'].append(dict(command=list(map(str, command)), log=log_name,
                                     exit_status=status, sha256=sha(run/log_name)))
        check_inputs()
        if status:
            raise RuntimeError(f'{log_name} failed with exit {status}')
    try:
        invoke([sys.executable, 'verification/rtl/uart_rx_path_vectors.py', '--depth', str(args.depth),
                '--seed', str(args.seed), '--cycles', str(args.cycles), '--output', str(run/'vectors.mem'),
                '--summary', str(run/'vectors.json')], 'vectors.log', 60)
        expected = json.loads((run/'vectors.json').read_text())
        record.update(expected=expected, vectors_sha256=sha(run/'vectors.mem'))
        invoke([args.verilator, '--binary', '--timing', '--language', '1364-2001', '-Wall',
                '--top-module', 'uart_rx_path_tb', '--Mdir', str(run/'obj'),
                f'-GC_HALF_PERIOD_PS={args.half_period_ps}', f'-GC_RX_DEPTH={args.depth}',
                'config/kd28_verilator.vlt', *rtl, 'verification/rtl/uart_rx_path_tb.v',
                *(str(external/name) for name in DEPENDENCIES)], 'compile.log', 180)
        invoke([str(run/'obj/Vuart_rx_path_tb'), f'+VECTORS={run}/vectors.mem'], 'sim.log', 60)
        matches = re.findall(r'^PASS uart_rx_path rows=(\d+) payload_writes=(\d+) reads=(\d+) messages=(\d+) headers=(\d+) discards=(\d+) errors=(\d+) credits=(\d+) requests=(\d+) responses=(\d+) others=(\d+) resets=(\d+) stream_resets=(\d+)$', (run/'sim.log').read_text(), re.M)
        assert len(matches) == 1, 'missing or duplicate PASS marker'
        assert not re.search(r'^FAIL ', (run/'sim.log').read_text(), re.M), 'simulation diagnostic'
        observed = dict(zip(('rows', 'payload_writes', 'reads', 'messages', 'headers', 'discards', 'errors', 'credits', 'requests', 'responses', 'others', 'resets', 'stream_resets'), map(int, matches[0])))
        assert all(observed[key] == expected[key] for key in observed), (observed, expected)
        assert expected['max_rx_fill'] == args.depth
        assert expected['read_counter_wraps'] >= 2 and expected['discards'] > 0 and expected['errors'] > 0
        assert expected['rows'] >= args.cycles and expected['reads'] >= 8256
        record.update(observed=observed, source_unchanged=True, dependencies_unchanged=True, passed=True)
    except (RuntimeError, AssertionError, OSError) as error:
        record['failure'] = str(error)
    record['elapsed_seconds'] = time.monotonic()-start
    (run/'summary.json').write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
