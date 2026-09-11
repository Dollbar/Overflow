"""Independently audit actual SRAM mapper formal evidence.

Run python3 verification/sram_storage_map/check_formal.py --stage PATH
--widths 40 512 --depths 3 2049 [--fault data|mask|bank]. Prints deterministic
JSON audit coverage and AUDIT PASS; elapsed time goes separately to stderr.
For the bank-captured reference use --reference-profile captured_bank.
Incomplete stages require --allow-incomplete-stage plus --exclude-config W:D
for every actual timeout; excluded configurations are explicitly unproven.
Writes no evidence files.
Temporary Yosys elaborations bind sources to graphs, without repeating SAT.
Next compose this boundary theorem with SRAM behavior and FIFO invariants.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
# Reviewed dependency identities, independent of a candidate run's manifest.
# Updating these requires a new source review, not accepting self-declared hashes.
REVIEWED_SOURCE_SHA256 = {
    'kd28_fifo_sdp_storage_map.v': '821c2b14cfdd3f029cb47d7e005c960bca10b18e4e9e3414cc06595cbfe89f1c',
    'kd28_sram_blackboxes.v': 'cd48ea4bb1cdd7c185fb1f0ab0a3a4922338af260cd66b60e728c32ce97281a6',
}
REVIEWED_RUNNER_SHA256 = {
    'captured_address': {'6fd7e0a8566bcccc9a60919a1d18840091e5eceb42769558d741368c93008fc7',
                         '659c2dee2fb9c1756ef146ccf12e8626f8c9475075de7e18f4f1c0eab2fd8596',
                         'f9eae66d6596a6bb0b85149b5b25c11eb2773b75bbb6769c7574494dffb9ae99'},
    'captured_bank': {'659c2dee2fb9c1756ef146ccf12e8626f8c9475075de7e18f4f1c0eab2fd8596',
                      'f9eae66d6596a6bb0b85149b5b25c11eb2773b75bbb6769c7574494dffb9ae99'},
}


class AuditError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise AuditError(message)


def read_json(path):
    return json.loads(path.read_text())


def compact(text):
    # Only whitespace is insignificant. Comments/directives and extra statements
    # are deliberately not discarded: this is a closed reviewed proof language.
    return re.sub(r'\s+', '', text)


def dimensions(width, depth):
    require(type(width) is int and width >= 8 and width % 8 == 0, 'invalid width')
    require(type(depth) is int and 1 <= depth <= 65535, 'invalid depth')
    if depth <= 256:
        rows, bits, row_bits = 256, 32, 8
    elif depth <= 512:
        rows, bits, row_bits = 512, 64, 9
    elif depth <= 1024:
        rows, bits, row_bits = 1024, 128, 10
    else:
        rows, bits, row_bits = 2048, 256, 11
    banks = (depth + rows - 1) // rows
    lanes = (width + bits - 1) // bits
    aw = 1
    while 2 ** aw <= depth:
        aw += 1
    return rows, bits, row_bits, banks, lanes, aw


def expected_wrapper(width, depth, aw):
    return f'''module mapped_storage(
input wire i_clk,i_write_cs,i_read_cs,
input wire [{aw-1}:0] i_write_addr,i_read_addr,
input wire [{width-1}:0] i_write_data,
output wire [{width-1}:0] o_read_data);
kd28_fifo_sdp_storage_map #(.DATA_WIDTH({width}),.DEPTH({max(2,depth)}),.ADDR_WIDTH({aw})) actual(
.write_clk_i(i_clk),.write_cs_i(i_write_cs),.write_addr_i(i_write_addr),.write_data_i(i_write_data),
.read_clk_i(i_clk),.read_cs_i(i_read_cs),.read_addr_i(i_read_addr),.read_data_o(o_read_data));
endmodule'''


def check_graphs(original, cut, inventory, width, depth):
    rows, bits, rab, banks, lanes, aw = dimensions(width, depth)
    top = original['modules']['mapped_storage']
    ports = top['ports']
    sizes = {'i_clk': 1, 'i_write_cs': 1, 'i_read_cs': 1,
             'i_write_addr': aw, 'i_read_addr': aw, 'i_write_data': width, 'o_read_data': width}
    require(set(ports) == set(sizes), 'original top port set differs')
    primary_bits = set()
    for name, size in sizes.items():
        port = ports[name]
        require(len(port['bits']) == size and port['direction'] ==
                ('output' if name == 'o_read_data' else 'input'), 'original port width/direction differs')
        if port['direction'] == 'input':
            require(all(type(b) is int and b not in primary_bits for b in port['bits']), 'aliased primary input')
            primary_bits.update(port['bits'])
    pins = {'WCLK': 1, 'WCS': 1, 'WA': rab, 'D': bits, 'WM': bits // 8,
            'RCLK': 1, 'RCS': 1, 'RA': rab, 'Q': bits}
    expected_inventory = []
    expected_cut = copy.deepcopy(original)
    cut_top = expected_cut['modules']['mapped_storage']
    positions = set()
    qbits = set()
    for name, cell in top['cells'].items():
        kind = cell['type']
        require(kind not in ('$assume', '$assert', '$anyseq', '$anyconst') and
                'latch' not in kind.lower(), 'unexpected formal cell/latch in mapper')
        if not kind.startswith('KD28_SRAM_'):
            if 'ff' in kind.lower():
                require(kind == '$dff', 'unexpected state cell class')
                require(cell['connections']['CLK'] == ports['i_clk']['bits'] and
                        int(cell['parameters']['CLK_POLARITY'], 2) == 1, 'state clock changed')
            continue
        match = re.fullmatch(r'actual\.gen_depth_bank\[(\d+)\]\.gen_width_lane\[(\d+)\]\.(?:genblk1\.)*gen_sdp_\d+x\d+\.u_sram', name)
        require(match is not None, 'unrecognized macro instance')
        bank, lane = map(int, match.groups())
        require((bank, lane) not in positions, 'duplicate macro position')
        positions.add((bank, lane))
        require(kind == f'KD28_SRAM_SDP_{rows}X{bits}', 'wrong macro geometry')
        require(set(cell['connections']) == set(pins), 'macro pin omitted/added')
        prefix = f'm{bank}_{lane}_'
        for pin, size in pins.items():
            wires = cell['connections'][pin]
            require(len(wires) == size, 'macro pin width differs')
            require(cell['port_directions'][pin] == ('output' if pin == 'Q' else 'input'), 'macro pin direction differs')
            if pin == 'Q':
                require(len(set(wires)) == len(wires) and all(type(b) is int and b not in qbits and
                        b not in primary_bits for b in wires), 'aliased/non-symbolic macro Q')
                qbits.update(wires)
            if pin in ('WCLK', 'RCLK'):
                require(wires == ports['i_clk']['bits'], 'macro clock differs')
            cut_top['ports'][prefix + pin] = {'direction': 'input' if pin == 'Q' else 'output', 'bits': wires}
        del cut_top['cells'][name]
        expected_inventory.append(dict(name=name, bank=bank, tile=lane, type=kind, prefix=prefix, pins=pins))
    require(positions == {(b, l) for b in range(banks) for l in range(lanes)}, 'missing/extra macro')
    expected_inventory.sort(key=lambda row: (row['bank'], row['tile']))
    require(inventory == expected_inventory, 'inventory differs from independent complete geometry')
    require(cut == expected_cut, 'cut modified nonmacro graph/state/ports or macro observation')
    return cut_top['ports'], banks * lanes


def check_properties(text, ports, width, depth, reference_profile='captured_address'):
    rows, bits, _, banks, lanes, aw = dimensions(width, depth)
    # This closed template is authored here from the reviewed pin and temporal
    # contract; no runner import, template call, or runner geometry is trusted.
    inputs = [f'input wire [{len(p["bits"])-1}:0] {n}' for n, p in ports.items() if p['direction'] == 'input']
    expected = 'module properties(' + ','.join(inputs) + ');'
    expected += ''.join(f'wire [{len(p["bits"])-1}:0] {n};' for n, p in ports.items() if p['direction'] == 'output')
    expected += 'mapped_storage dut(' + ','.join(f'.{n}({n})' for n in ports) + ');'
    physical = lanes * bits
    pad = physical - width
    value = f"{{{pad}'d0,i_write_data}}" if pad else 'i_write_data'
    expected += f'wire [{physical-1}:0] padded={value};'
    require(reference_profile in REVIEWED_RUNNER_SHA256, 'unreviewed reference profile')
    if reference_profile == 'captured_bank':
        bank_bits = 1
        while 2 ** bank_bits < banks:
            bank_bits += 1
        expected += f'reg seen=0;reg [{bank_bits-1}:0] last_bank;'
        expected += f"always @(posedge i_clk)if(i_read_cs)begin seen<=i_read_addr<{depth};last_bank<=i_read_addr/32'd{rows};end"
    else:
        expected += f'reg seen=0;reg [{aw-1}:0] last_read;'
        expected += f'always @(posedge i_clk)if(i_read_cs)begin seen<=i_read_addr<{depth};last_read<=i_read_addr;end'
    expected += f'wire [{banks*width-1}:0] logical_bank_data;'
    for bank in range(banks):
        word = ','.join(f'm{bank}_{lane}_Q' for lane in range(lanes-1, -1, -1))
        expected += f'wire [{physical-1}:0] bank{bank}={{{word}}};'
        expected += f'assign logical_bank_data[{bank*width} +: {width}]=bank{bank}[{width-1}:0];'
    expected += 'always @* begin'
    for bank in range(banks):
        for lane in range(lanes):
            pin = f'm{bank}_{lane}_'
            obligations = [f'{pin}WCLK==i_clk&&{pin}RCLK==i_clk',
                f"{pin}WCS==(i_write_cs&&((i_write_addr/32'd{rows})=={bank}))",
                f"{pin}RCS==(i_read_cs&&((i_read_addr/32'd{rows})=={bank}))",
                f"{pin}WA==(i_write_addr%32'd{rows})", f"{pin}RA==(i_read_addr%32'd{rows})",
                f'{pin}D==padded[{lane*bits} +: {bits}]', f"{pin}WM=={bits//8}'h{'f'*(bits//32)}"]
            expected += ''.join(f'assert({clause});' for clause in obligations)
    if reference_profile == 'captured_bank':
        for bank in range(banks):
            expected += f'if(seen&&last_bank=={bank})assert(o_read_data==bank{bank}[{width-1}:0]);'
    else:
        expected += f"if(seen)assert(o_read_data==logical_bank_data[(last_read/32'd{rows})*{width} +: {width}]);"
    expected += 'end endmodule'
    require(compact(text) == compact(expected), 'property contract differs: assumptions, pin/word coverage, or bank/seen semantics')


def replay(script, expected, folder, label):
    with tempfile.TemporaryDirectory(prefix='sram-graph-audit-') as tmp:
        output = Path(tmp) / 'graph.json'
        script_path = Path(tmp) / 'replay.ys'
        script_path.write_text(script + f'write_json "{output}"\n')
        process = subprocess.run(['yosys', '-Q', '-T', '-s', str(script_path)],
                                 text=True, capture_output=True, timeout=120, cwd=ROOT)
        require(process.returncode == 0, f'{folder.name}: {label} replay failed: {process.stdout[-1000:]} {process.stderr[-1000:]}')
        require(read_json(output) == expected, f'{folder.name}: {label} graph not derived from recorded sources')


def audit_sources(stage, result, fault):
    require(result['fault'] == fault, 'fault mode differs from requested audit')
    sources = result['sources']
    require(len(sources) == 2 and {Path(p).name for p in sources} ==
            {'kd28_fifo_sdp_storage_map.v', 'kd28_sram_blackboxes.v'}, 'wrong source manifest')
    changes = {
        'data': ('.D(write_data_padded[lane_index*MACRO_WIDTH +: MACRO_WIDTH])', '.D(~write_data_padded[lane_index*MACRO_WIDTH +: MACRO_WIDTH])', 4),
        'mask': (".WM({MACRO_MASK_WIDTH{1'b1}})", ".WM({MACRO_MASK_WIDTH{1'b0}})", 4),
        'bank': ('bank_read_data[(read_bank_q*PHYSICAL_WIDTH)', 'bank_read_data[(read_bank_select*PHYSICAL_WIDTH)', 1)}
    for name, digest in sources.items():
        path = Path(name)
        require(digest == REVIEWED_SOURCE_SHA256[path.name], 'dependency is outside the independently reviewed source identity')
        data = path.read_bytes()
        require(hashlib.sha256(data).hexdigest() == digest, 'current dependency source hash differs')
        if path.name == 'kd28_fifo_sdp_storage_map.v' and fault:
            old, new, count = changes[fault]
            require(result['mutation'] == {'old': old, 'new': new} and data.count(old.encode()) == count, 'fault source patch differs')
            data = data.replace(old.encode(), new.encode())
        require((stage / path.name).read_bytes() == data, 'source snapshot differs from authorized source/fault')
    require(fault or result['mutation'] is None, 'unexpected mutation')
    profile = result.get('reference_profile', 'captured_address')
    require(profile in REVIEWED_RUNNER_SHA256 and hashlib.sha256((stage / 'runner.py').read_bytes()).hexdigest()
            in REVIEWED_RUNNER_SHA256[profile], 'runner snapshot differs from independently reviewed entry')


def audit_stage(stage, widths, depths, fault=None, reference_profile='captured_address',
                allow_incomplete_stage=False, excluded=None, bit_lower=False):
    stage = stage.resolve()
    result = read_json(stage / 'results.json')
    require(widths and depths and len(set(widths)) == len(widths) and len(set(depths)) == len(depths), 'empty/duplicate requested matrix')
    expected_pairs = {(w, d) for w in widths for d in depths}
    rows = result['results']
    require(len(rows) == len(expected_pairs) and {(r['width'], r['depth']) for r in rows} == expected_pairs, 'missing/extra/duplicate parameter configuration')
    excluded = set() if excluded is None else set(excluded)
    require(excluded <= expected_pairs and (not excluded or allow_incomplete_stage), 'excluded configurations need explicit incomplete-stage audit')
    require(reference_profile == result.get('reference_profile', 'captured_address'), 'reference profile differs from requested audit')
    require(result.get('bit_lower', False) is bit_lower, 'bit-lowering profile differs from requested audit')
    failed = {(r['width'], r['depth']) for r in rows if r['passed'] is not True}
    require((allow_incomplete_stage and excluded == failed and excluded and result['complete'] is False)
            or (not allow_incomplete_stage and not excluded and not failed and result['complete'] is True),
            'incomplete stage or exclusions do not exactly identify failed configurations')
    require(result['assumptions'] == [] and
            result['physical_signoff'] is False and result['full_goal_complete'] is False, 'invalid completion/scope claims')
    audit_sources(stage, result, fault)
    require({p.name for p in stage.iterdir() if p.is_dir() and re.fullmatch(r'w\d+_d\d+', p.name)} ==
            {f'w{w}_d{d}' for w, d in expected_pairs}, 'configuration directories differ')
    total_macros = 0
    total_words = 0
    omitted = []
    for row in rows:
        width, depth = row['width'], row['depth']
        if (width, depth) in excluded:
            require(row['proof']['exit'] == 124 and row['induction_proven'] is False and row['counterexample'] is False,
                    'excluded configuration is not the declared unproven timeout')
            omitted.append(dict(width=width, depth=depth, status='timeout_unproven', proof_exit=124))
            continue
        _, _, _, banks, _, aw = dimensions(width, depth)
        words = banks if reference_profile == 'captured_bank' else 1
        folder = stage / f'w{width}_d{depth}'
        require(compact((folder / 'wrapper.v').read_text()) == compact(expected_wrapper(width, depth, aw)), 'wrapper configuration/clock contract differs')
        original = read_json(folder / 'original.json')
        cut = read_json(folder / 'cut.json')
        ports, macros = check_graphs(original, cut, read_json(folder / 'inventory.json'), width, depth)
        check_properties((folder / 'properties.sv').read_text(), ports, width, depth, reference_profile)
        prepare = f'read_verilog "{stage}/kd28_fifo_sdp_storage_map.v" "{stage}/kd28_sram_blackboxes.v" "{folder}/wrapper.v"\nprep -top mapped_storage -flatten\ncheck -assert\n'
        optimization = 'wreduce\nopt -full -keepdc' if reference_profile == 'captured_bank' else 'opt -keepdc'
        if bit_lower:
            optimization += '\ntechmap\nopt -full -keepdc'
        prefix = f'read_json "{folder}/cut.json"\nread_verilog -formal -sv "{folder}/properties.sv"\nprep -top properties -flatten\n{optimization}\ncheck -assert\n'
        query = '-seq 4' if fault else '-seq 2 -tempinduct -maxsteps 8'
        proof = prefix + f'write_json "{folder}/proof.json"\nsat {query} -prove-asserts -verify -show-inputs -dump_json "{folder}/witness.json"\n'
        require((folder / 'prepare.ys').read_text() == prepare + f'write_json "{folder}/original.json"\n', 'prepare command differs')
        require((folder / 'proof.ys').read_text() == proof, 'SAT command differs or adds constraints')
        proof_graph = read_json(folder / 'proof.json')
        top = proof_graph['modules']['properties']
        require(all(c['type'] != '$assume' for m in proof_graph['modules'].values() for c in m.get('cells', {}).values()), 'hidden graph assumption')
        init = [(name, net['attributes']['init']) for name, net in top['netnames'].items() if 'init' in net.get('attributes', {})]
        require(init == [('seen', '0')], 'unexpected state initialization/vacuity')
        require(sum(c['type'] == '$assert' for c in top['cells'].values()) >= 1, 'no proof obligations')
        require(row['prepare']['exit'] == 0 and 'ERROR:' not in (folder / 'prepare.log').read_text(), 'elaboration evidence failed')
        log = (folder / 'proof.log').read_text()
        require('Final init constraint equation: \\seen = 1\'0' in log, 'initial seen evidence missing')
        require('Final constraint equation: { } = { }' in log, 'unconstrained input evidence missing')
        require('Import proof for assert:' in log, 'SAT has no imported assertions')
        if fault:
            require(row['proof']['exit'] == 1 and 'SAT proof finished - model found: FAIL!' in log and
                    'ERROR: Called with -verify and proof did fail!' in log and (folder / 'witness.json').is_file(), 'missing reachable negative-control counterexample')
            witness = read_json(folder / 'witness.json')
            require(isinstance(witness.get('signal'), list) and witness['signal'], 'empty counterexample witness')
        else:
            require(row['proof']['exit'] == 0 and 'ERROR:' not in log and
                    re.search(r'^Base case for induction length \d+ proven\.$', log, re.M) and
                    'Induction step proven: SUCCESS!' in log, 'missing base/induction proof evidence')
        require(row['passed'] is True and row['induction_proven'] is (fault is None) and
                row['counterexample'] is (fault is not None) and row['macros'] == macros and
                row['properties'] == 7 * macros + words, 'result summary disagrees with evidence')
        replay(prepare, original, folder, 'original')
        replay(prefix, proof_graph, folder, 'proof')
        total_macros += macros
        total_words += words
    passed_count = len(rows) - len(omitted)
    return dict(configurations=passed_count, macro_instances=total_macros,
                input_pin_obligations=total_macros*8, full_word_obligations=total_words,
                source_assert_statements=total_macros*7+total_words, input_assumptions=0,
                elaboration_graph_replays=passed_count*2, sat_replayed=False,
                fault=fault, reference_profile=reference_profile, bit_lower=bit_lower, excluded=omitted,
                read_scope='full word if most recent issued read is legal; arbitrary independent macro Q',
                widths=widths, depths=depths)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--widths', type=int, nargs='+', required=True)
    parser.add_argument('--depths', type=int, nargs='+', required=True)
    parser.add_argument('--fault', choices=('data', 'mask', 'bank'))
    parser.add_argument('--reference-profile', choices=('captured_address', 'captured_bank'), default='captured_address')
    parser.add_argument('--allow-incomplete-stage', action='store_true')
    parser.add_argument('--bit-lower', action='store_true')
    parser.add_argument('--exclude-config', nargs='+', default=[], metavar='WIDTH:DEPTH')
    args = parser.parse_args()
    started = time.monotonic()
    try:
        excluded = [tuple(map(int, pair.split(':'))) for pair in args.exclude_config]
        require(all(len(pair) == 2 for pair in excluded) and len(set(excluded)) == len(excluded), 'invalid/duplicate exclusion')
        report = audit_stage(args.stage, args.widths, args.depths, args.fault, args.reference_profile,
                             args.allow_incomplete_stage, excluded, args.bit_lower)
    except (AuditError, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(f'AUDIT FAIL: {error}', file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2))
    print('AUDIT PASS: source, geometry, boundary, properties, graph replay and SAT evidence')
    print(f'AUDIT TIMING: {time.monotonic()-started:.3f} seconds', file=sys.stderr)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
