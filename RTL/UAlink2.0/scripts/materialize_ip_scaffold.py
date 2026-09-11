"""Create explicitly unimplemented RTL from config/ip_module_inventory.json.

Run python3 scripts/materialize_ip_scaffold.py [--check] [--root PATH].
Outputs planned RTL and the two role aggregators at inventory paths; --check
only reads and validates files. Never overwrites an existing differing file.
Next run python3 scripts/check_ip_structure.py --label NEW and review its
evidence before treating the structure as available, never as implemented.
"""
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


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
        if item['status'] not in ('planned', 'scaffold'):
            continue
        require(path.startswith('rtl/') and path.endswith('.v') and
                '..' not in Path(path).parts and not Path(path).is_absolute(), 'unsafe planned RTL path')
        require(name not in ('ualink_endpoint_scaffold', 'ualink_switch_scaffold'), 'aggregator cannot contain itself')
        require(item['roles'] and set(item['roles']) <= set(occupied), 'invalid planned roles')
        for role in item['roles']:
            slot = item['feature_slots'][role]
            require(type(slot) is int and 0 <= slot < 128 and slot not in occupied[role], 'invalid/duplicate feature slot')
            occupied[role].add(slot)
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


def materialize(root, check=False):
    modules = planned_modules(root)
    expected = {root / m['path']: shell(m['module']) for m in modules}
    for role in ('endpoint', 'switch'):
        expected[root / f'rtl/scaffold/{role}/ualink_{role}_scaffold.v'] = aggregate(role, modules)
    # Check every collision first, before creating any file.
    for path, code in expected.items():
        require(not path.is_symlink(), f'refusing symlink: {path}')
        if path.exists():
            require(path.read_text() == code, f'refusing to overwrite changed RTL: {path}')
        elif check:
            raise ValueError(f'missing generated RTL: {path}')
    if not check:
        for path, code in expected.items():
            if not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                with path.open('x') as stream:
                    stream.write(code)
    return dict(planned_modules=len(modules), generated_files=len(expected), readonly=check,
                implemented_features=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(materialize(args.root.resolve(), args.check), indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f'SCAFFOLD FAIL: {error}', file=sys.stderr)
        return 1
    print('SCAFFOLD CHECK PASS' if args.check else 'SCAFFOLD MATERIALIZED: no functional implementation claimed')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
