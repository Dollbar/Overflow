#!/usr/bin/env python3
"""Exercise immutable exports in temporary Git repositories, without Overflow access.

Run: python3 verification/tools/test_overflow_export.py -v
     python3 -O verification/tools/test_overflow_export.py -v
Outputs: unittest results; all temporary repositories are removed automatically.
Next: export an explicitly reviewed source commit with scripts/export_overflow.py.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = (lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
EXPORTER = ROOT/'scripts/export_overflow.py'


class OverflowExport(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.base=Path(self.tmp.name);self.source=self.base/'source';self.dest=self.base/'dest'
        self.source.mkdir();self.dest.mkdir();(self.dest/'other_project.txt').write_text('keep me\n')
        self.git('init','-q');self.git('config','user.name','Fixture');self.git('config','user.email','fixture@example.invalid')
        self.write('rtl/endpoint/block.v','module block; endmodule\n')
        self.write('rtl/README.md','design explanation [status](../docs/status.md)\n')
        self.write('verification/README.md','verify [status](../docs/status.md)\n')
        self.write('docs/status.md','fixture status\n')
        self.write('README.md','root explanation\n')
        self.write('scripts/helper.py','from pathlib import Path\nROOT=Path(__file__).resolve().parents[1]\n')
        self.write('model/pkg/__init__.py','from pathlib import Path\nROOT=Path(__file__).resolve().parents[2]\nHERE=Path(__file__).resolve().parent\nVALUE=17\n')
        self.write('simulator/driver.py','from pathlib import Path as P\nROOT=P(__file__).resolve().parent.parent\n')
        self.write('verification/unit/probe.py', '''from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
ALSO=Path(__file__).resolve().parent.parent.parent
HERE=Path(__file__).resolve().parent
LITERAL="Path(__file__).resolve().parents[2]"
sys.path.insert(0,str(ROOT/'model'))
import pkg
assert pkg.VALUE==17
assert (ROOT/'rtl/endpoint/block.v').is_file()
assert ROOT==ALSO==pkg.ROOT
print(ROOT)
''')
        self.write('verification/unit/identity.py', 'from pathlib import Path\nROOT=Path(__file__).resolve().parents[2]\nIDENTITY=Path(__file__).resolve().relative_to(ROOT)\nprint(IDENTITY)\n')
        self.write('specs/private/secret.txt','must not export\n')
        self.write('third_party/private/cells.v','restricted\n')
        self.write('third_party/cells.lib','licensed cells\n')
        self.write('third_party/README.md','external input instructions\n')
        self.write('build/tracked_generated.txt','must not export\n')
        self.commit=self.commit_source()

    def git(self,*args):
        return subprocess.run(['git','-C',str(self.source),*args],check=True,capture_output=True,text=True).stdout.strip()

    def write(self,name,text):
        p=self.source/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)

    def commit_source(self):
        self.git('add','-A');self.git('commit','-qm','fixture update');return self.git('rev-parse','HEAD')

    def run_export(self,*args,commit=None):
        self.assertTrue(EXPORTER.is_file(),'export entry point does not exist yet')
        opts=['-O'] if sys.flags.optimize else []
        return subprocess.run([sys.executable,*opts,str(EXPORTER),'--source',str(self.source),
                               '--commit',commit or self.commit,'--dest',str(self.dest),*args],capture_output=True,text=True)

    def snapshot(self):
        return {str(p.relative_to(self.dest)):('link',p.readlink().as_posix()) if p.is_symlink()
                else ('file',p.read_bytes(),p.stat().st_mode&0o777)
                for p in self.dest.rglob('*') if p.is_symlink() or p.is_file()}

    def assert_pass(self,r):
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)

    def test_mapping_immutable_inputs_manifest_and_boundaries(self):
        self.write('rtl/endpoint/block.v','uncommitted replacement\n')
        self.write('verification/untracked.py','do not copy\n')
        self.assert_pass(self.run_export())
        self.assertEqual((self.dest/'rtl/UAlink2.0/endpoint/block.v').read_text(),'module block; endmodule\n')
        self.assertIn('(../../verification/UAlink2.0/project/docs/status.md)',(self.dest/'rtl/UAlink2.0/README.md').read_text())
        self.assertFalse((self.dest/'verification/UAlink2.0/untracked.py').exists())
        manifest=json.loads((self.dest/'verification/UAlink2.0/.ualink-export.json').read_text())
        self.assertEqual(manifest['source_commit'],self.commit)
        self.assertEqual(len(manifest['excluded']),4)
        for name,item in manifest['files'].items():
            p=self.dest/name
            if item['kind']=='file':self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),item['sha256'])
            else:self.assertEqual(p.readlink().as_posix(),item['target'])
        self.assertEqual((self.dest/'other_project.txt').read_text(),'keep me\n')

    def test_original_and_exported_python_roots_and_identity(self):
        r=subprocess.run([sys.executable,str(self.source/'verification/unit/probe.py')],capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr)
        self.assert_pass(self.run_export())
        project=self.dest/'verification/UAlink2.0/project'
        for link,target in [('rtl','../../../rtl/UAlink2.0'),('verification','..'),
                            ('model','../../../simulator/UAlink2.0/model'),('simulator','../../../simulator/UAlink2.0')]:
            self.assertEqual((project/link).readlink().as_posix(),target)
        r=subprocess.run([sys.executable,str(self.dest/'verification/UAlink2.0/unit/probe.py')],cwd='/tmp',capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(Path(r.stdout.strip()),project)
        identity=subprocess.run([sys.executable,str(self.dest/'verification/UAlink2.0/unit/identity.py')],capture_output=True,text=True)
        self.assertEqual(identity.returncode,0,identity.stderr);self.assertEqual(identity.stdout.strip(),'verification/unit/identity.py')
        source=(self.dest/'verification/UAlink2.0/unit/probe.py').read_text()
        self.assertIn('HERE=Path(__file__).resolve().parent',source)
        self.assertIn('LITERAL="Path(__file__).resolve().parents[2]"',source)
        # The transformed expression also retains the original layout fallback.
        (self.source/'verification/unit/probe.py').write_text(source)
        original=subprocess.run([sys.executable,str(self.source/'verification/unit/probe.py')],capture_output=True,text=True)
        self.assertEqual(original.returncode,0,original.stderr)

    def test_readonly_plan_does_not_write(self):
        before=self.snapshot();self.assert_pass(self.run_export('--check'));self.assertEqual(before,self.snapshot())
        self.assert_pass(self.run_export());before=self.snapshot();self.assert_pass(self.run_export('--check'));self.assertEqual(before,self.snapshot())
        self.assert_pass(self.run_export());self.assertEqual(before,self.snapshot())

    def test_unowned_subtree_is_rejected_before_any_write(self):
        p=self.dest/'rtl/UAlink2.0/owner.v';p.parent.mkdir(parents=True);p.write_text('someone else\n')
        before=self.snapshot();self.assertNotEqual(self.run_export().returncode,0);self.assertEqual(before,self.snapshot())

    def test_modified_owned_file_is_protected(self):
        self.assert_pass(self.run_export());p=self.dest/'rtl/UAlink2.0/endpoint/block.v';p.write_text('local edit\n')
        before=self.snapshot();self.assertNotEqual(self.run_export().returncode,0);self.assertEqual(before,self.snapshot())

    def test_increment_removes_only_old_owned_files(self):
        self.assert_pass(self.run_export());(self.dest/'verification/UAlink2.0/local_notes.txt').write_text('unowned\n')
        (self.source/'rtl/endpoint/block.v').unlink();self.write('rtl/endpoint/new.v','module new_block;endmodule\n')
        newer=self.commit_source();self.assert_pass(self.run_export(commit=newer))
        self.assertFalse((self.dest/'rtl/UAlink2.0/endpoint/block.v').exists())
        self.assertTrue((self.dest/'rtl/UAlink2.0/endpoint/new.v').exists())
        self.assertEqual((self.dest/'verification/UAlink2.0/local_notes.txt').read_text(),'unowned\n')

    def test_unowned_new_target_is_not_adopted_even_if_equal(self):
        self.assert_pass(self.run_export());self.write('rtl/endpoint/new.v','new\n');newer=self.commit_source()
        (self.dest/'rtl/UAlink2.0/endpoint/new.v').write_text('new\n');before=self.snapshot()
        self.assertNotEqual(self.run_export(commit=newer).returncode,0);self.assertEqual(before,self.snapshot())

    def test_destination_symlink_escape_is_rejected(self):
        outside=self.base/'outside';outside.mkdir();(self.dest/'rtl').symlink_to(outside,target_is_directory=True)
        before=self.snapshot();self.assertNotEqual(self.run_export().returncode,0);self.assertEqual(before,self.snapshot());self.assertEqual(list(outside.iterdir()),[])

    def test_changed_owned_symlink_is_rejected(self):
        self.assert_pass(self.run_export());link=self.dest/'verification/UAlink2.0/project/rtl';link.unlink();link.symlink_to('/tmp')
        before=self.snapshot();self.assertNotEqual(self.run_export().returncode,0);self.assertEqual(before,self.snapshot())

    def test_source_symlink_is_rejected(self):
        (self.source/'verification/escape').symlink_to('/etc/passwd');newer=self.commit_source();before=self.snapshot()
        self.assertNotEqual(self.run_export(commit=newer).returncode,0);self.assertEqual(before,self.snapshot())

    def test_manifest_escape_is_rejected(self):
        self.assert_pass(self.run_export());p=self.dest/'verification/UAlink2.0/.ualink-export.json';r=json.loads(p.read_text())
        r['files']['../escape']={'kind':'file','sha256':'0'*64,'mode':420};p.write_text(json.dumps(r));before=self.snapshot()
        self.assertNotEqual(self.run_export().returncode,0);self.assertEqual(before,self.snapshot())

    def test_mapping_collision_is_rejected(self):
        self.write('simulator/model/pkg/__init__.py','collision\n');newer=self.commit_source();before=self.snapshot()
        self.assertNotEqual(self.run_export(commit=newer).returncode,0);self.assertEqual(before,self.snapshot())

    def test_namespace_ignores_and_readme_entry(self):
        self.assert_pass(self.run_export())
        for namespace in ('rtl','verification','simulator'):
            self.assertIn('__pycache__/',(self.dest/namespace/'UAlink2.0/.gitignore').read_text())
        readme=(self.dest/'verification/UAlink2.0/README.md').read_text()
        self.assertIn('(project/docs/status.md)',readme)
        self.assertIn('cd verification/UAlink2.0/project',readme)
        self.assertIn('make test',readme)

    def test_source_namespace_ignore_collision_is_explicit(self):
        self.write('verification/.gitignore','local rules\n');newer=self.commit_source();before=self.snapshot()
        result=self.run_export(commit=newer)
        self.assertNotEqual(result.returncode,0);self.assertIn('mapping collision',result.stderr)
        self.assertEqual(before,self.snapshot())

    def test_branch_name_is_not_an_immutable_commit(self):
        before=self.snapshot();self.assertNotEqual(self.run_export(commit='HEAD').returncode,0);self.assertEqual(before,self.snapshot())


if __name__=='__main__':unittest.main()
