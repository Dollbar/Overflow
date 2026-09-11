"""Run python3 verification/tl_receive/run_checks.py --kd28-root /path/to/authorized/repository.
Writes strict lint, real-blackbox synthesis, injected RTL tests and checks.json.
Next independent evidence audit; physical mapping and STA remain separate.
"""
from pathlib import Path
import argparse,json,subprocess,hashlib
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/tl_receive';S.mkdir(parents=True,exist_ok=True);p=argparse.ArgumentParser();p.add_argument('--kd28-root',required=True,type=Path);a=p.parse_args();sources=[p for p in sorted((R/'rtl/tl').glob('*.v')) if p.name!='tl_credit_publish.v']+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v'];ext=list(json.loads((S/'healthy.json').read_text())['external']);rows=[]
def run(cmd,log,timeout=180):
 try:x=subprocess.run(cmd,capture_output=True,text=True,timeout=timeout);status,output=x.returncode,x.stdout+x.stderr
 except subprocess.TimeoutExpired as e:status,output=124,(e.stdout or b'').decode()+(e.stderr or b'').decode()
 log.write_text(output);return status,output
for depth in (1,17):
 cmd=['verilator','--lint-only','-Wall','--timescale-override','1ps/1ps','--top-module','tl_receive_storage',f'-GDEPTH={depth}',str(R/'config/kd28_verilator.vlt'),*[str(p) for p in sources],*ext];status,log=run(cmd,S/f'final_lint_{depth}.log');rows.append(dict(kind='lint',depth=depth,command=cmd,exit_status=status,passed=status==0 and '%Warning' not in log and '%Error' not in log))
 black=a.kd28_root/'Library/models/kd28/sram/rtl/kd28_sram_blackboxes.v';mapper=a.kd28_root/'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v';ys=S/f'final_synth_{depth}.ys'
 ys.write_text(f'read_verilog -lib {black}\nread_verilog '+' '.join(str(p) for p in sources)+f' {mapper}\nchparam -set DEPTH {depth} tl_receive_storage\nsynth -top tl_receive_storage -flatten -noabc\ncheck -assert\nwrite_json {S}/final_synth_{depth}.json\nstat\n')
 status,log=run(['yosys','-Q','-T','-s',str(ys)],S/f'final_synth_{depth}.log');row=dict(kind='synth',depth=depth,exit_status=status,passed=status==0)
 if status==0:
  m=json.loads((S/f'final_synth_{depth}.json').read_text())['modules']['tl_receive_storage'];ff=[c for c in m['cells'].values() if 'DFF' in c['type'] or 'LATCH' in c['type']];macros=[c for c in m['cells'].values() if 'sram' in c['type'].lower()];row.update(cells=len(m['cells']),ff=sum(len(c['connections']['Q']) for c in ff),single_clock=all(c['connections'].get('C')==m['ports']['i_clk']['bits'] for c in ff),latches=any('LATCH' in c['type'] for c in ff),macros=len(macros));row['passed'] &= row['single_clock'] and not row['latches'] and len(macros)==19
 rows.append(row);print(row,flush=True)
changes={
 'early_cmd':('tl_receive_context.v',"if((w_counts[i*4+:4]==4'd0)&&!w_be[i])", "if(1'b1)"),
 'early_data':('tl_receive_context.v','if(n_metadata[6])o_releases','if(n_metadata[5])o_releases'),
 'premature_context':('tl_receive_storage.v','.i_commit(o_taken)','.i_commit(i_valid&&proposal)'),
 'stored_data_bit':('tl_receive_storage.v','.i_write_data(write_word)',".i_write_data(write_word ^ 600'd1)"),
 'block_free_control':('tl_receive_storage.v','assign space=!o_store||write_ready;','assign space=write_ready;')}
for name,(filename,before,after) in changes.items():
 original=(R/'rtl/tl'/filename).read_text();count=original.count(before)
 if count!=(2 if name=='early_data' else 1):raise RuntimeError('fault anchor')
 B=S/'final_faults'/name;B.mkdir(parents=True,exist_ok=False);fault=B/filename;fault.write_text(original.replace(before,after));cmd=['python3',str(R/'verification/tl_receive/run_rtl.py'),'--kd28-root',str(a.kd28_root),'--label','checked_'+name,'--replace',str(fault)];status,log=run(cmd,B/'runner.log',180);result=json.loads((S/('checked_'+name+'.json')).read_text());passed=status==1 and len(result['results'])==6 and all(x['compile_exit_status']==0 and x.get('run_exit_status')==1 for x in result['results']);rows.append(dict(kind='fault',name=name,filename=filename,before=before,after=after,occurrences=count,exit_status=status,passed=passed,sha256=hashlib.sha256(fault.read_bytes()).hexdigest()));print(name,passed,flush=True)
r=dict(complete=all(x['passed'] for x in rows),results=rows);(S/'final_checks.json').write_text(json.dumps(r,indent=2)+'\n');raise SystemExit(0 if r['complete'] else 1)
