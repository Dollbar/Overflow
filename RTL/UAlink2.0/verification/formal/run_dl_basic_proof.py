"""Prove Basic full actual state and public outputs against an independent reference.
Run: python3 verification/formal/run_dl_basic_proof.py --period-ps 640
Outputs: fresh build/dl_basic_proof_*/snapshot, exact graphs, query log and summary.json.
Next: require all declared profiles, real fault counterexamples and actual physical checks.
"""
import argparse,hashlib,json,os,re,shutil,subprocess,sys,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.check_dl_basic_observations import audit_graphs
NAMES=('rtl/dl/dl_basic_message_control.v','verification/formal/dl_basic_properties.v','scripts/prove_dl_basic_control.tcl','scripts/check_dl_basic_observations.py','verification/formal/run_dl_basic_proof.py','config/dl_basic_control_contract.json')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--period-ps',type=int,choices=(1,640,6400,1000000,1000001,1000000000),default=640);p.add_argument('--yosys',default='yosys');a=p.parse_args()
    hashes={n:sha(ROOT/n) for n in NAMES};run=Path(tempfile.mkdtemp(prefix='dl_basic_proof_',dir=ROOT/'build'));snap=run/'snapshot'
    for n in NAMES:
        (snap/n).parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/n,snap/n)
    started=time.monotonic();env=dict(os.environ,UALINK_PERIOD_PS=str(a.period_ps),UALINK_PROOF_DIR=str(run/'graph'));command=[a.yosys,'-Q','-T','-c','scripts/prove_dl_basic_control.tcl']
    with (run/'proof.log').open('w') as f:
        try:status=subprocess.run(command,cwd=snap,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=540).returncode
        except subprocess.TimeoutExpired:status=124
    content=(run/'proof.log').read_text();unchanged=all(sha(ROOT/n)==sha(snap/n)==h for n,h in hashes.items())
    audit={'passed':False}
    try:audit=audit_graphs(run/'graph/before.json',run/'graph/connected.json',snap/'config/dl_basic_control_contract.json',a.period_ps)
    except (AssertionError,OSError,KeyError,ValueError) as e:audit['failure']=type(e).__name__+': '+str(e)
    reset=content.count('DL_BASIC_RESET_BASE_PROVED\n')==1;step=content.count('DL_BASIC_FULL_INDUCTION_PROVED\n')==1;complete=content.count(f'DL_BASIC_FUNCTIONAL_PROVED period_ps={a.period_ps} state_bits=156 output_bits=194\n')==1
    diagnostics=bool(re.search(r'^\s*(?:Warning:|ERROR:)',content,re.M));success=content.count('SAT proof finished - no model found: SUCCESS!')
    passed=status==0 and unchanged and audit['passed'] and reset and step and complete and not diagnostics and success==2
    record=dict(directory=str(run.relative_to(ROOT)),period_ps=a.period_ps,source_sha256=hashes,source_unchanged=unchanged,tool=subprocess.check_output([a.yosys,'-V'],text=True).strip(),command=command,exit_status=status,graph_audit=audit,reset_base_passed=reset,full_induction_passed=step,solver_success_count=success,diagnostics=diagnostics,passed=passed,elapsed_seconds=time.monotonic()-started,artifact_sha256={str(f.relative_to(run)):sha(f) for f in run.rglob('*') if f.is_file()},scope='Binary synchronous full156bit declared state and194bit public outputs with all104 native input bits unconstrained except initial reset or previous full invariant; stable configured clock; no integration or liveness claim.')
    (run/'summary.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record),flush=True);return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
