"""Audit inventory source presence and explicitly unimplemented role scaffolds.

Run python3 scripts/check_ip_structure.py --label NEW [--root PATH]. Outputs
immutable build/verification/ip_structure/NEW/{evidence.json,*.ys,*.log,*.json}
from independent Yosys hierarchy/check and shell-contract SAT elaborations.
Next review materialized/shell_only status and implement each actual module;
a successful structure audit is never a protocol functionality claim.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PORTS = {'i_clk': ('input', 1), 'i_rstn': ('input', 1), 'i_enable': ('input', 1),
         'i_valid': ('input', 1), 'i_data': ('input', 512), 'i_meta': ('input', 128),
         'o_ready': ('output', 1), 'o_valid': ('output', 1), 'o_data': ('output', 512),
         'o_meta': ('output', 128), 'o_implemented': ('output', 1), 'o_error': ('output', 1)}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_inventory(root):
    path = root / 'config/ip_module_inventory.json'
    inventory = json.loads(path.read_text())
    rows = inventory['modules']
    require(isinstance(rows, list) and rows, 'missing inventory modules')
    names, paths = set(), set()
    roles = {'endpoint': {}, 'switch': {}}
    occupied = {'endpoint': set(), 'switch': set()}
    for row in rows:
        name, relative = row['module'], row['path']
        require(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_$]*', name) is not None and name not in names, 'invalid/duplicate module')
        require(relative not in paths and relative.startswith('rtl/') and relative.endswith('.v') and
                '..' not in Path(relative).parts, 'invalid/duplicate source path')
        names.add(name); paths.add(relative)
        source = root / relative
        require(source.is_file(), f'missing source: {relative}')
        text = re.sub(r'/\*.*?\*/|//[^\n]*', '', source.read_text(), flags=re.S)
        declarations = re.findall(r'\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)', text)
        require(declarations.count(name) == 1, f'module declaration missing/duplicated: {name}')
        if 'feature_slots' in row:
            require(isinstance(row['feature_slots'], dict) and row['roles'] and
                    set(row['roles']) <= set(occupied) and
                    set(row['feature_slots']) == set(row['roles']), 'invalid feature slot roles')
            for role, slot in row['feature_slots'].items():
                require(type(slot) is int and 0 <= slot < 128 and slot not in occupied[role], 'invalid/duplicate role slot')
                occupied[role].add(slot)
        if row['status'] in ('planned', 'scaffold'):
            require(set(row['roles']) <= set(roles) and row['roles'], 'invalid role list')
            for role in row['roles']:
                slot = row['feature_slots'][role]
                roles[role][slot] = row
    return inventory, roles


def yosys(stage, name, code):
    script = stage / f'{name}.ys'
    script.write_text(code)
    process = subprocess.run(['yosys', '-Q', '-T', '-s', str(script)], text=True,
                             capture_output=True, timeout=180)
    (stage / f'{name}.log').write_text(process.stdout + process.stderr)
    require(process.returncode == 0, f'Yosys {name} failed: {process.stderr[-1000:]}')
    return process.stdout + process.stderr


def check_role(stage, role, members, read_command):
    name = f'ualink_{role}_scaffold'
    original = stage / f'{role}_hierarchy.json'
    flattened = stage / f'{role}_flattened.json'
    yosys(stage, role, read_command + f'hierarchy -check -top {name}\ncheck -assert\n'
          f'write_json "{original}"\nflatten\nproc\nopt\ncheck -assert\nwrite_json "{flattened}"\n')
    graph = json.loads(original.read_text())['modules']
    top = graph[name]
    require(set(top['ports']) == {'i_clk', 'i_rstn', 'o_pending_features'}, 'role aggregator port mismatch')
    instances = {n: c for n, c in top['cells'].items() if c['type'] in graph}
    expected_instances = {'u_' + row['module']: row for row in members.values()}
    require(set(instances) == set(expected_instances), f'{role}: missing/extra planned instance')
    for instance, row in expected_instances.items():
        cell = instances[instance]
        require(cell['type'] == row['module'], 'role instance module mismatch')
        pins = cell['connections']
        require(pins['i_clk'] == top['ports']['i_clk']['bits'] and
                pins['i_rstn'] == top['ports']['i_rstn']['bits'], 'role clock/reset not direct')
        for pin, size in (('i_enable', 1), ('i_valid', 1), ('i_data', 512), ('i_meta', 128)):
            require(pins[pin] == ['0'] * size, 'scaffold traffic inputs are not disabled')
        slot = row['feature_slots'][role]
        bit = top['ports']['o_pending_features']['bits'][slot]
        inversions = [c for c in top['cells'].values() if c['type'] == '$logic_not' and
                      c['connections']['A'] == pins['o_implemented'] and c['connections']['Y'] == [bit]]
        require(len(inversions) == 1, 'pending bit not driven by its own implementation capability')
    flat = json.loads(flattened.read_text())['modules'][name]
    expected_bits = ['1' if bit in members else '0' for bit in range(128)]
    require(flat['ports']['o_pending_features']['bits'] == expected_bits, 'flattened role bitmap differs')
    require(not flat['cells'], 'unexpected active logic/state in disabled scaffold role')
    return dict(instances=len(instances), pending_bitmap_hex=f'{sum(1 << slot for slot in members):032x}',
                slots={str(slot): row['module'] for slot, row in sorted(members.items())})


def check_contract(stage, planned, read_command):
    code = 'module scaffold_contract(input wire i_clk,i_rstn,i_enable,i_valid,input wire [511:0] i_data,input wire [127:0] i_meta);\n'
    for index, row in enumerate(planned):
        code += f'wire ready{index},valid{index},implemented{index},error{index};wire [511:0] data{index};wire [127:0] meta{index};\n'
        code += f'{row["module"]} m{index}(.i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_valid(i_valid),.i_data(i_data),.i_meta(i_meta),'
        code += f'.o_ready(ready{index}),.o_valid(valid{index}),.o_implemented(implemented{index}),.o_error(error{index}),.o_data(data{index}),.o_meta(meta{index}));\n'
        code += f'always @* begin assert(!ready{index}&&!valid{index}&&!implemented{index});assert(data{index}==0&&meta{index}==0);assert(error{index}==(i_rstn&&i_enable&&i_valid));end\n'
    code += 'endmodule\n'
    harness = stage / 'scaffold_contract.sv'
    harness.write_text(code)
    log = yosys(stage, 'contract', read_command + f'read_verilog -formal -sv "{harness}"\n'
                'prep -top scaffold_contract -flatten\ncheck -assert\n'
                f'write_json "{stage}/contract.json"\nsat -prove-asserts -verify\n')
    graph = json.loads((stage / 'contract.json').read_text())['modules']['scaffold_contract']
    require(not any(c['type'] == '$assume' or 'dff' in c['type'].lower() or 'latch' in c['type'].lower()
                    for c in graph['cells'].values()), 'scaffold contract added assumptions or state')
    require('SAT proof finished - no model found: SUCCESS!' in log, 'shell contract was not proved')


def audit(root, label):
    require(re.fullmatch(r'[A-Za-z0-9_-]+', label) is not None, 'unsafe label')
    inventory, roles = load_inventory(root)
    planned = [r for r in inventory['modules'] if r['status'] in ('planned', 'scaffold')]
    stage = root / 'build/verification/ip_structure' / label
    stage.mkdir(parents=True, exist_ok=False)
    sources = [root / row['path'] for row in planned]
    sources += [root / f'rtl/scaffold/{role}/ualink_{role}_scaffold.v' for role in roles]
    read_command = 'read_verilog ' + ' '.join(f'"{p}"' for p in sources) + '\n'
    # Validate the actual child interface before any flattening can hide pins.
    yosys(stage, 'interfaces', read_command + f'write_json "{stage}/interfaces.json"\n')
    modules = json.loads((stage / 'interfaces.json').read_text())['modules']
    for row in planned:
        module = modules[row['module']]
        require(set(module['ports']) == set(PORTS), 'planned shell interface pin set differs')
        for name, (direction, width) in PORTS.items():
            require(module['ports'][name]['direction'] == direction and len(module['ports'][name]['bits']) == width,
                    'planned shell interface width/direction differs')
        require(not module.get('processes') and not module.get('memories'), 'unimplemented shell contains state')
    role_reports = {role: check_role(stage, role, members, read_command) for role, members in roles.items()}
    check_contract(stage, planned, read_command)
    report = dict(structure_passed=True, functional_completion=False, inventory_modules=len(inventory['modules']),
                  source_declarations_present=len(inventory['modules']), materialized_shell_only=len(planned),
                  existing_partial=len(inventory['modules'])-len(planned), role_scaffolds=role_reports,
                  shell_behavior_proved='no acceptance/output; error iff reset released and enabled valid input',
                  sources={str(p.relative_to(root)): sha(p) for p in
                           [root / row['path'] for row in inventory['modules']] + sources[-2:]},
                  inventory_sha256=sha(root / 'config/ip_module_inventory.json'),
                  checker_sha256=sha(Path(__file__)))
    (stage / 'evidence.json').write_text(json.dumps(report, indent=2) + '\n')
    return stage, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    try:
        stage, report = audit(args.root.resolve(), args.label)
    except (ValueError, OSError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(f'STRUCTURE FAIL: {error}', file=sys.stderr)
        return 1
    print(json.dumps(dict(evidence=str(stage / 'evidence.json'), inventory_modules=report['inventory_modules'],
                         materialized_shell_only=report['materialized_shell_only'], functional_completion=False)))
    print('STRUCTURE PASS: materialized shells are explicitly unimplemented')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
