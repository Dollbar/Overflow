"""Create explicitly unimplemented RTL from config/ip_module_inventory.json.

Run python3 scripts/materialize_ip_scaffold.py [--check | --refresh-aggregates]
[--root PATH].
Outputs planned RTL and the two role aggregators at inventory paths; --check
only reads and validates files. Changed leaf RTL is never overwritten. Explicit
--refresh-aggregates permits replacing only the two marked generated role files.
Next run python3 scripts/check_ip_structure.py --label NEW and review its
evidence before treating the structure as available, never as implemented.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
AGGREGATE_MARKER = ('// Generated structural inventory: every asserted bit is unimplemented.\n'
                    '// Run python3 scripts/materialize_ip_scaffold.py --check; then check_ip_structure.py.\n')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def planned_modules(root):
    inventory = json.loads((root / 'config/ip_module_inventory.json').read_text())
    modules = inventory['modules']
    require(isinstance(modules, list), 'modules must be a list')
    planned = []
    names, paths = set(), set()
    occupied = {'endpoint': set(), 'switch': set()}
    for item in modules:
        name, path = item['module'], item['path']
        require(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_$]*', name) is not None, 'invalid module name')
        require(name not in names and path not in paths, 'duplicate inventory module/path')
        names.add(name); paths.add(path)
        # A promoted module keeps ownership of its stable role slots.
        if 'feature_slots' in item:
            require(isinstance(item['feature_slots'], dict) and item['roles'] and
                    set(item['roles']) <= set(occupied) and
                    set(item['feature_slots']) == set(item['roles']), 'invalid feature slot roles')
            for role, slot in item['feature_slots'].items():
                require(type(slot) is int and 0 <= slot < 128 and slot not in occupied[role], 'invalid/duplicate feature slot')
                occupied[role].add(slot)
        if item['status'] not in ('planned', 'scaffold'):
            continue
        require(path.startswith('rtl/') and path.endswith('.v') and
                '..' not in Path(path).parts and not Path(path).is_absolute(), 'unsafe planned RTL path')
        require(name not in ('ualink_endpoint_scaffold', 'ualink_switch_scaffold'), 'aggregator cannot contain itself')
        require(path not in ('rtl/scaffold/endpoint/ualink_endpoint_scaffold.v',
                             'rtl/scaffold/switch/ualink_switch_scaffold.v'), 'reserved aggregate path')
        require(item['roles'] and set(item['roles']) <= set(occupied), 'invalid planned roles')
        require('feature_slots' in item, 'missing planned feature slots')
        planned.append(item)
    return planned


def shell(name):
    return f'''// Generated unimplemented interface; inventory status remains planned.
// Regenerate/check: python3 scripts/materialize_ip_scaffold.py --check
// Next implement this module deliberately and update its reviewed inventory status.
`default_nettype none
module {name}(
 input wire i_clk,i_rstn,i_enable,i_valid,
 input wire [511:0] i_data,
 input wire [127:0] i_meta,
 output wire o_ready,o_valid,
 output wire [511:0] o_data,
 output wire [127:0] o_meta,
 output wire o_implemented,o_error
);
assign o_ready=1'b0;
assign o_valid=1'b0;
assign o_data=512'd0;
assign o_meta=128'd0;
assign o_implemented=1'b0;
assign o_error=i_rstn&&i_enable&&i_valid;
endmodule
`default_nettype wire
'''


def aggregate(role, modules):
    selected = sorted((m for m in modules if role in m['roles']), key=lambda m: m['feature_slots'][role])
    code = f'''// Generated structural inventory: every asserted bit is unimplemented.
// Run python3 scripts/materialize_ip_scaffold.py --check; then check_ip_structure.py.
`default_nettype none
module ualink_{role}_scaffold(
 input wire i_clk,i_rstn,
 output wire [127:0] o_pending_features
);
'''
    occupied = set()
    for item in selected:
        name = item['module']; slot = item['feature_slots'][role]; occupied.add(slot)
        code += f'''wire implemented_{slot};
{name} u_{name}(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_{slot}),.o_error());
assign o_pending_features[{slot}]=!implemented_{slot};
'''
    for slot in range(128):
        if slot not in occupied:
            code += f"assign o_pending_features[{slot}]=1'b0;\n"
    return code + 'endmodule\n`default_nettype wire\n'


def replace_aggregate(path, code, previous):
    require(path.read_text() == previous, f'aggregate changed during refresh: {path}')
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.' + path.name + '.', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(code)
        os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def materialize(root, check=False, refresh_aggregates=False):
    require(not (check and refresh_aggregates), 'check and refresh-aggregates are mutually exclusive')
    modules = planned_modules(root)
    expected = {root / m['path']: shell(m['module']) for m in modules}
    aggregate_paths = {}
    for role in ('endpoint', 'switch'):
        path = root / f'rtl/scaffold/{role}/ualink_{role}_scaffold.v'
        expected[path] = aggregate(role, modules)
        aggregate_paths[path] = f'ualink_{role}_scaffold'
    refresh = {}
    # Check every collision first, before creating any file.
    for path, code in expected.items():
        require(not path.is_symlink(), f'refusing symlink: {path}')
        if path.exists():
            previous = path.read_text()
            if previous != code:
                require(refresh_aggregates and path in aggregate_paths, f'refusing to overwrite changed RTL: {path}')
                require(previous.startswith(AGGREGATE_MARKER), f'missing generated aggregate marker: {path}')
                require(re.findall(r'^module\s+([A-Za-z_][A-Za-z0-9_$]*)', previous, re.M) ==
                        [aggregate_paths[path]], f'generated aggregate module identity mismatch: {path}')
                refresh[path] = previous
        elif check:
            raise ValueError(f'missing generated RTL: {path}')
    if not check:
        for path, code in expected.items():
            if not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                with path.open('x') as stream:
                    stream.write(code)
            elif path in refresh:
                replace_aggregate(path, code, refresh[path])
    return dict(planned_modules=len(modules), generated_files=len(expected), readonly=check,
                refreshed_aggregates=len(refresh),
                implemented_features=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--refresh-aggregates', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(materialize(args.root.resolve(), args.check, args.refresh_aggregates), indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f'SCAFFOLD FAIL: {error}', file=sys.stderr)
        return 1
    print('SCAFFOLD CHECK PASS' if args.check else 'SCAFFOLD MATERIALIZED: no functional implementation claimed')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
