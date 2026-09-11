"""Check scaffold promotion protection using isolated temporary inventories/RTL.

Run: python3 verification/tools/test_ip_scaffold_lifecycle.py -v
     python3 -O verification/tools/test_ip_scaffold_lifecycle.py -v
Outputs: unittest results on stderr; temporary fixtures are deleted automatically.
Next: review typed-module promotion, explicitly refresh production aggregates,
then run scripts/check_ip_structure.py with a new evidence label.
"""
import importlib.util,json,os,shutil,subprocess,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def load(name,path):
 spec=importlib.util.spec_from_file_location(name,path);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
gen=load('generator',ROOT/'scripts/materialize_ip_scaffold.py');check=load('checker',ROOT/'scripts/check_ip_structure.py')
class Lifecycle(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
  inv=json.loads((ROOT/'config/ip_module_inventory.json').read_text())
  shared=next(m for m in inv['modules'] if m['status']=='planned' and set(m['roles'])=={'endpoint','switch'})
  local=next(m for m in inv['modules'] if m['status']=='planned' and m['roles']==['endpoint'])
  self.rows=json.loads(json.dumps([shared,local]));(self.root/'config').mkdir();self.save();gen.materialize(self.root)
 def save(self):
  (self.root/'config/ip_module_inventory.json').write_text(json.dumps({'modules':self.rows}))
 def promote(self):
  row=self.rows[0];row['status']='existing_partial';self.save();p=self.root/row['path']
  p.write_text('module '+row['module']+'(input wire [10:0] i_tag,output wire [10:0] o_tag);assign o_tag=i_tag;endmodule\n');return p
 def digests(self):
  return {str(p.relative_to(self.root)):p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
 def test_refuses_leaf_overwrite_even_with_refresh(self):
  p=self.root/self.rows[1]['path'];p.write_text(p.read_text()+'// deliberate leaf edit\n');self.promote();before=self.digests()
  with self.assertRaisesRegex(ValueError,'changed RTL'):gen.materialize(self.root,refresh_aggregates=True)
  self.assertEqual(before,self.digests())
 def test_requires_explicit_aggregate_refresh(self):
  self.promote();before=self.digests()
  with self.assertRaisesRegex(ValueError,'changed RTL'):gen.materialize(self.root)
  self.assertEqual(before,self.digests())
 def test_refresh_removes_promoted_instance_without_touching_leaf(self):
  leaf=self.promote();old=leaf.read_bytes();result=gen.materialize(self.root,refresh_aggregates=True)
  self.assertEqual(result['refreshed_aggregates'],2);self.assertEqual(old,leaf.read_bytes());gen.materialize(self.root,check=True)
  inv,roles=check.load_inventory(self.root)
  self.assertNotIn(self.rows[0]['feature_slots']['endpoint'],roles['endpoint']);self.assertFalse(roles['switch'])
  stage,report=check.audit(self.root,'promoted_structure');self.assertTrue(report['structure_passed']);self.assertEqual(report['materialized_shell_only'],1)
 def test_rejects_reuse_of_promoted_slot(self):
  self.promote();self.rows[1]['feature_slots']['endpoint']=self.rows[0]['feature_slots']['endpoint'];self.save()
  with self.assertRaisesRegex(ValueError,'slot'):gen.planned_modules(self.root)
  with self.assertRaisesRegex(ValueError,'slot'):check.load_inventory(self.root)
 def test_unmarked_aggregate_cannot_be_overwritten(self):
  self.promote();p=self.root/'rtl/scaffold/endpoint/ualink_endpoint_scaffold.v';p.write_text(p.read_text().replace('// Generated structural inventory:', '// Manually owned aggregation:',1));before=self.digests()
  with self.assertRaisesRegex(ValueError,'marker'):gen.materialize(self.root,refresh_aggregates=True)
  self.assertEqual(before,self.digests())
 def test_refresh_and_readonly_are_mutually_exclusive(self):
  before=self.digests()
  with self.assertRaisesRegex(ValueError,'exclusive'):gen.materialize(self.root,check=True,refresh_aggregates=True)
  self.assertEqual(before,self.digests())
 def test_cli_refresh_and_readonly(self):
  leaf=self.promote();previous=leaf.read_bytes();opts=['-O'] if sys.flags.optimize else []
  command=[sys.executable,*opts,str(ROOT/'scripts/materialize_ip_scaffold.py'),'--root',str(self.root)]
  refreshed=subprocess.run([*command,'--refresh-aggregates'],capture_output=True,text=True)
  self.assertEqual(refreshed.returncode,0,refreshed.stdout+refreshed.stderr);self.assertEqual(previous,leaf.read_bytes())
  before=self.digests();checked=subprocess.run([*command,'--check'],capture_output=True,text=True)
  self.assertEqual(checked.returncode,0,checked.stdout+checked.stderr);self.assertEqual(before,self.digests())
 def test_cli_incompatible_modes_do_not_write(self):
  before=self.digests();opts=['-O'] if sys.flags.optimize else []
  result=subprocess.run([sys.executable,*opts,str(ROOT/'scripts/materialize_ip_scaffold.py'),'--root',str(self.root),'--check','--refresh-aggregates'],capture_output=True,text=True)
  self.assertEqual(result.returncode,2);self.assertEqual(before,self.digests())
if __name__=='__main__':unittest.main()
