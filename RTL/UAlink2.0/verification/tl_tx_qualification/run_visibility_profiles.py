"""Run python3 verification/tl_tx_qualification/run_visibility_profiles.py
--kd28-root PATH --label NEW. Check explicit 0/1 and rejected -1/2 visibility
parameters on FIFO, storage and channel RTL, plus strict lint for both valid
FIFO/channel profiles. Outputs scripts, source hashes and logs under
build/verification/tl_tx_qualification/NEW. Next complete-state composition,
production regression and physical audits; elaboration alone is not proof.
"""
from pathlib import Path
import argparse
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'verification/tl_partition_mapping'))
from run_cec import dump, execute, need, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--kd28-root', required=True, type=Path)
    parser.add_argument('--rtl-root', type=Path, default=ROOT / 'rtl', help='optional isolated candidate RTL tree')
    args = parser.parse_args()
    need(args.label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    stage = ROOT / 'build/verification/tl_tx_qualification' / args.label
    stage.mkdir(parents=True, exist_ok=False)
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    fifo = args.rtl_root.resolve() / 'upli/upli_receive_fifo.v'
    storage = args.rtl_root.resolve() / 'upli/upli_receive_storage.v'
    channel = [args.rtl_root.resolve() / 'tl' / (n + '.v') for n in ('tl_tx_channels', 'tl_tx_packer_core',
               'tl_credit_admission', 'tl_control_decode', 'tl_control_tenure')]
    deps = [args.kd28_root / 'Library/models/kd28/sram/rtl/kd28_sram_blackboxes.v',
            args.kd28_root / 'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v']
    report = dict(complete=False, sources={str(p): sha(p) for p in [fifo, storage] + channel + deps}, results=[])
    for top, parameter, sources in [('upli_receive_fifo', 'C_ZERO_INVALID', [fifo]),
                                    ('upli_receive_storage', 'C_ZERO_INVALID', [fifo, storage]),
                                    ('tl_tx_channels', 'RAW_HEADERS', channel)]:
        for value in (-1, 0, 1, 2):
            name = f'{top}_{value}'
            script = ''
            if top == 'upli_receive_storage':
                script += f'read_verilog -lib "{deps[0]}"\nread_verilog "{deps[1]}"\n'
            script += '\n'.join(f'read_verilog "{p}"' for p in sources)
            # Yosys chparam does not parse a bare negative decimal; use the
            # exact two's-complement value of the signed integer parameter.
            literal = "32'hffffffff" if value == -1 else str(value)
            script += f'\nchparam -set {parameter} {literal} {top}\nhierarchy -check -top {top}\n'
            (stage / (name + '.ys')).write_text(script)
            run = execute(['yosys', '-Q', '-T', '-s', str(stage / (name + '.ys'))], stage / (name + '.log'), 60)
            log = (stage / (name + '.log')).read_text()
            valid = value in (0, 1)
            marker = 'tl_tx_channels_parameters_invalid' if top == 'tl_tx_channels' else 'upli_receive_parameters_invalid'
            passed = run['exit'] == 0 if valid else (run['exit'] != 0 and marker in log and 'is not part of the design' in log)
            report['results'].append(dict(kind='elaboration', top=top, value=value, valid=valid, run=run, passed=passed))
            if valid and top != 'upli_receive_storage':
                run = execute(['verilator', '--lint-only', '--top-module', top, '-Wall',
                               f'-G{parameter}={value}', *map(str, sources)], stage / (name + '_lint.log'), 60)
                report['results'].append(dict(kind='lint', top=top, value=value, run=run, passed=run['exit'] == 0))
            dump(stage / 'results.json', report)
    report['complete'] = len(report['results']) == 16 and all(r['passed'] for r in report['results'])
    dump(stage / 'results.json', report)
    print(report['complete'], [(r['kind'], r['top'], r['value']) for r in report['results'] if not r['passed']])
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
