"""Run python3 verification/sram_storage_map/test_formal_audit.py.

Uses the actual first_healthy/w40_d2049 artifacts (override SRAM_AUDIT_FIXTURE).
Copies evidence into temporary directories and verifies accepted evidence plus
rejection of concrete weakened artifacts. Produces unittest results; next run
check_formal.py across the complete requested width/depth matrix.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import importlib.util

ROOT = Path(__file__).resolve().parents[2]
CHECK = Path(__file__).with_name('check_formal.py')


def load_checker():
    spec = importlib.util.spec_from_file_location('mapping_checker', CHECK)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FormalAuditMutationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sram-audit-test-')
        self.addCleanup(self.temp.cleanup)
        self.stage = Path(self.temp.name) / 'evidence'
        source = Path(os.environ.get('SRAM_AUDIT_FIXTURE',
            str(ROOT / 'build/verification/sram_storage_map/first_healthy'))).resolve()
        self.stage.mkdir()
        for path in source.iterdir():
            if path.is_file():
                shutil.copy2(path, self.stage / path.name)
        shutil.copytree(source / 'w40_d2049', self.stage / 'w40_d2049')
        for path in self.stage.rglob('*'):
            if path.is_file():
                path.write_text(path.read_text().replace(str(source), str(self.stage)))
        result = json.loads((self.stage / 'results.json').read_text())
        result['results'] = [r for r in result['results'] if (r['width'], r['depth']) == (40, 2049)]
        (self.stage / 'results.json').write_text(json.dumps(result))
        self.folder = self.stage / 'w40_d2049'

    def edit_json(self, name, edit):
        path = self.folder / name
        value = json.loads(path.read_text())
        edit(value)
        path.write_text(json.dumps(value))

    def edit_text(self, name, old, new):
        path = self.folder / name
        value = path.read_text()
        self.assertIn(old, value)
        path.write_text(value.replace(old, new))

    def run_audit(self, accepted=False, depths=('2049',)):
        optimize = ['-' + 'O' * sys.flags.optimize] if sys.flags.optimize else []
        proc = subprocess.run([sys.executable, *optimize, str(CHECK), '--stage', str(self.stage),
            '--widths', '40', '--depths', *depths], text=True, capture_output=True)
        if accepted:
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn('AUDIT PASS:', proc.stdout)
        else:
            self.assertNotEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn('AUDIT FAIL:', proc.stderr)

    def test_accepts_actual_healthy_proof(self):
        self.run_audit(accepted=True)

    def test_rejects_missing_macro(self):
        def edit(graph):
            cells = graph['modules']['mapped_storage']['cells']
            cells.pop(next(n for n, c in cells.items() if c['type'].startswith('KD28_SRAM_')))
        self.edit_json('original.json', edit)
        self.run_audit()

    def test_rejects_aliased_macro_q(self):
        def edit(graph):
            cells = [c for c in graph['modules']['mapped_storage']['cells'].values()
                     if c['type'].startswith('KD28_SRAM_')]
            cells[1]['connections']['Q'][0] = cells[0]['connections']['Q'][0]
        self.edit_json('original.json', edit)
        self.run_audit()

    def test_rejects_internal_state_cut(self):
        def edit(graph):
            top = graph['modules']['mapped_storage']
            name = next(n for n, c in top['cells'].items() if c['type'].startswith('$dff'))
            cell = top['cells'].pop(name)
            top['ports']['hidden_bank_cut'] = {'direction': 'input', 'bits': cell['connections']['Q']}
        self.edit_json('cut.json', edit)
        self.run_audit()

    def test_rejects_added_assumption(self):
        self.edit_text('properties.sv', 'always @* begin', 'always @* begin\n assume(i_read_cs);')
        self.run_audit()

    def test_rejects_missing_full_word_obligation(self):
        self.edit_text('properties.sv', 'if(seen)assert(o_read_data==', 'if(1\'b0)assert(o_read_data==')
        self.run_audit()

    def test_rejects_current_bank_instead_of_held_bank(self):
        self.edit_text('properties.sv', '(last_read/32\'d2048)', '(i_read_addr/32\'d2048)')
        self.run_audit()

    def test_rejects_seen_forever_zero(self):
        self.edit_text('properties.sv', 'seen<=i_read_addr<2049', 'seen<=0')
        self.run_audit()

    def test_rejects_incomplete_parameter_matrix(self):
        self.run_audit(depths=('3', '2049'))

    def test_rejects_hidden_sat_constraint(self):
        self.edit_text('proof.ys', 'sat -seq', 'sat -set i_read_cs 0 -seq')
        self.run_audit()

    def test_rejects_missing_base_case_log(self):
        self.edit_text('proof.log', 'Base case for induction length', 'Removed base case for induction length')
        self.run_audit()

    def test_rejects_missing_output_bit(self):
        self.edit_text('properties.sv', 'o_read_data==logical_bank_data', 'o_read_data[38:0]==logical_bank_data')
        self.run_audit()

    def test_rejects_missing_mask_pin_obligation(self):
        text = (self.folder / 'properties.sv').read_text()
        (self.folder / 'properties.sv').write_text('\n'.join(l for l in text.splitlines() if 'assert(m1_0_WM' not in l))
        self.run_audit()

    def test_rejects_forged_original_and_cut_graph_pair(self):
        for name in ('original.json', 'cut.json'):
            def edit(graph):
                cells = graph['modules']['mapped_storage']['cells']
                cell = next(c for c in cells.values() if c['type'].startswith('$dff'))
                cell['connections']['D'][0] = '0'
            self.edit_json(name, edit)
        self.run_audit()

    def test_rejects_missing_wrapper_parameter(self):
        self.edit_text('wrapper.v', '.DATA_WIDTH(40),', '')
        self.run_audit()

    def test_rejects_modified_snapshot(self):
        path = self.stage / 'kd28_fifo_sdp_storage_map.v'
        path.write_text(path.read_text().replace('read_bank_q <= read_bank_select;', 'read_bank_q <= 0;'))
        self.run_audit()

    def test_rejects_self_declared_replacement_dependency(self):
        import hashlib
        result_path = self.stage / 'results.json'
        result = json.loads(result_path.read_text())
        old = next(p for p in result['sources'] if p.endswith('kd28_fifo_sdp_storage_map.v'))
        replacement = self.stage.parent / 'kd28_fifo_sdp_storage_map.v'
        replacement.write_text((self.stage / replacement.name).read_text() + '\n// Unreviewed replacement\n')
        result['sources'].pop(old)
        result['sources'][str(replacement)] = hashlib.sha256(replacement.read_bytes()).hexdigest()
        result_path.write_text(json.dumps(result))
        (self.stage / replacement.name).write_bytes(replacement.read_bytes())
        # Keep the serialized graph in sync with this harmless source extension;
        # the defect is accepting a self-declared dependency outside the review.
        self.run_audit()

    def test_rejects_hidden_proof_graph_assumption(self):
        def edit(graph):
            cells = graph['modules']['properties']['cells']
            cell = next(c for c in cells.values() if c['type'] == '$assert')
            cell['type'] = '$assume'
        self.edit_json('proof.json', edit)
        self.run_audit()

    def test_rejects_extra_initial_state_constraint(self):
        def edit(graph):
            graph['modules']['properties']['netnames']['last_read']['attributes']['init'] = '0' * 12
        self.edit_json('proof.json', edit)
        self.run_audit()

    def test_captured_bank_reference_is_accepted_without_weakening_hold(self):
        checker = load_checker()
        ports = json.loads((self.folder / 'cut.json').read_text())['modules']['mapped_storage']['ports']
        code = (self.folder / 'properties.sv').read_text()
        code = code.replace('reg [11:0] last_read;', 'reg [0:0] last_bank;')
        code = code.replace('last_read<=i_read_addr;', "last_bank<=i_read_addr/32'd2048;")
        code = code.replace("if(seen)assert(o_read_data==logical_bank_data[(last_read/32'd2048)*40 +: 40]);",
                            'if(seen&&last_bank==0)assert(o_read_data==bank0[39:0]);\n'
                            'if(seen&&last_bank==1)assert(o_read_data==bank1[39:0]);')
        checker.check_properties(code, ports, 40, 2049, reference_profile='captured_bank')
        with self.assertRaises(checker.AuditError):
            checker.check_properties(code.replace('seen&&last_bank==1', "seen&&(i_read_addr/32'd2048)==1"),
                                     ports, 40, 2049, reference_profile='captured_bank')
        with self.assertRaises(checker.AuditError):
            checker.check_properties(code.replace('if(seen&&last_bank==1)assert(o_read_data==bank1[39:0]);', ''),
                                     ports, 40, 2049, reference_profile='captured_bank')

    def test_rejects_exclusion_of_successful_configuration(self):
        checker = load_checker()
        with self.assertRaises(checker.AuditError):
            checker.audit_stage(self.stage, [40], [2049], allow_incomplete_stage=True,
                                excluded={(40, 2049)})

    def test_rejects_undeclared_bit_lowering(self):
        checker = load_checker()
        with self.assertRaises(checker.AuditError):
            checker.audit_stage(self.stage, [40], [2049], bit_lower=True)

    def test_rejects_forged_proof_graph(self):
        def edit(graph):
            cells = graph['modules']['properties']['cells']
            name = next(n for n, c in cells.items() if c['type'] == '$assert')
            cells.pop(name)
        self.edit_json('proof.json', edit)
        self.run_audit()


if __name__ == '__main__':
    unittest.main()
