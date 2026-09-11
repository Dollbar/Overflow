"""Run python3 verification/tl_control_partition/run_checks.py --kd28-root PATH.
Optional --dependency-root DIR selects private candidates. Requires healthy peers; records real lint/synthesis and same-fixture RTL mutants.
Next independently audit evidence and perform clean-export compatibility.
"""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys
R=Path(__file__).resolve().parents[2];p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='checks');p.add_argument('--peers-label',default='peers_semantics');p.add_argument('--replace',type=Path);p.add_argument('--dependency-root',type=Path);p.add_argument('--boundary-fault',choices=('missing_guard','truncated_header'),default='missing_guard');a=p.parse_args();S=R/'build/verification/tl_control_partition'
if not all(re.fullmatch(r'[a-zA-Z0-9_-]+',v) for v in (a.label,a.peers_label)):p.error('invalid label')
peer_tbs=sorted((S/a.peers_label).glob('*/tb.sv'))
if len(peer_tbs)!=16:raise ValueError('requires exactly 16 healthy actual peer fixtures before EDA')
healthy=json.loads((S/a.peers_label/'results.json').read_text())
if not healthy['complete'] or len(healthy['results'])!=16:raise ValueError('healthy peer matrix is incomplete')
B=S/a.label;B.mkdir(exist_ok=False)
src=[R/'rtl/tl'/n for n in ('tl_control_partition.v','tl_credit_admission.v','tl_control_decode.v','tl_control_tenure.v')];rows=[]
if a.dependency_root:src=[a.dependency_root/x.name if (a.dependency_root/x.name).is_file() else x for x in src]
if a.replace:src=[a.replace.resolve() if x.name==a.replace.name else x for x in src]
def run(name,cmd):
    c=subprocess.run(cmd,capture_output=True,text=True,timeout=300);(B/(name+'.log')).write_text(c.stdout+c.stderr);return c
for w in (8,16):
    c=run(f'lint_{w}',['verilator','--lint-only','-Wall','--top-module','tl_control_partition',f'-GWIDTH={w}',*map(str,src)]);rows.append(dict(kind='lint',width=w,passed=c.returncode==0));print(rows[-1],flush=True)
    script='read_verilog '+' '.join(map(str,src))+f'\nchparam -set WIDTH {w} tl_control_partition\nsynth -flatten -noabc -top tl_control_partition\ncheck -assert\nwrite_json {B}/synth_{w}.json\n';(B/f'synth_{w}.ys').write_text(script);c=run(f'synth_{w}',['yosys','-Q','-T','-s',str(B/f'synth_{w}.ys')]);rows.append(dict(kind='synthesis',width=w,passed=c.returncode==0));print(rows[-1],flush=True)
source=src[0].read_text();mutations={
 'lost_cursor':("r_cursor<=o_source_taken?4'd0:selected_end", "r_cursor<=4'd0"),
 'early_source_release':("o_source_taken=o_taken&&(selected_end==4'd8)",'o_source_taken=o_taken'),
 'lost_tag_offset':(('tags_shifted=before_fields[3]?256\'d0:(before_fields[2]?tags_offset_two[511:256]:tags_offset_two[255:0]);','tags_shifted=i_source_tags[255:0];') if 'assign tags_shifted=' in source else ('source_tag=before_fields+TAG_POSITION','source_tag=TAG_POSITION')),
 'corrupt_field':('selected_control=prefix[pick];',"selected_control=prefix[pick]^256'd1;"),
 'mid_field_cut':(('&&complete_boundary&&',"&&1'b1&&") if a.boundary_fault=='missing_guard' else ('selected_control=prefix[pick];',"selected_control=prefix[pick];if(!starts[pick])selected_control[pick*32+:32]=32'd0;")),
 'auth_overfill':("&&(!i_auth||(prefix_fields[boundary]<=4'd4))",''),
 'ignore_capacity':('&&allowed;',';'),
 'allow_fc':('||(|bad_fc)',''),
}
for name,(old,new) in mutations.items():
    if source.count(old)!=1:raise ValueError('mutation anchor '+name)
    d=B/name;d.mkdir();f=d/'tl_control_partition.v';f.write_text(source.replace(old,new));unit_label=('fault_' if a.label=='checks' else a.label+'_fault_')+name;c=run(name,[sys.executable,str(R/'verification/tl_control_partition/run_rtl.py'),'--label',unit_label,'--replace',str(f)]+(['--dependency-root',str(a.dependency_root)] if a.dependency_root else []));result=json.loads((S/unit_label/'results.json').read_text());rows.append(dict(kind='unit_fault',name=name,passed=c.returncode==1 and len(result['results'])==2 and all(x['compile_exit']==0 and x.get('run_exit')==1 for x in result['results'])));print(rows[-1],flush=True)
root=a.kd28_root/'Library/models/kd28';ext=[root/'sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[root/'fifo/rtl/kd28_fifo_sdp_storage_map.v']
for name in ('lost_cursor','early_source_release','lost_tag_offset','ignore_capacity'):
    f=B/name/'tl_control_partition.v';sources=[f if x.name==f.name else a.dependency_root/x.name if a.dependency_root and (a.dependency_root/x.name).is_file() else x for x in sorted((R/'rtl/tl').glob('*.v'))]+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v']+ext
    for source_tb in peer_tbs:
        if name=='lost_tag_offset' and '_a0_' in source_tb.parent.name:continue
        d=B/(name+'_'+source_tb.parent.name);d.mkdir();tb=d/'tb.sv';v=source_tb.read_text()
        for log in ('trace.txt','queue_trace.txt','partition_trace.txt'):v=v.replace(str(source_tb.parent/log),str(d/log))
        tb.write_text(v);c=run(d.name+'_compile',['iverilog','-g2012','-s','tb','-o',str(d/'sim.vvp'),*map(str,sources),str(tb)])
        if c.returncode:raise ValueError('peer fault compile failed')
        c=run(d.name,['vvp',str(d/'sim.vvp')]);rows.append(dict(kind='peer_fault',name=name,config=source_tb.parent.name,passed=c.returncode==1 and 'FATAL:' in c.stdout and 'PASS actual channels' not in c.stdout))
result=dict(complete=all(x['passed'] for x in rows),results=rows,boundary_fault=a.boundary_fault,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in src});(B/'results.json').write_text(json.dumps(result,indent=2)+'\n');print('checks complete',result['complete']);raise SystemExit(0 if result['complete'] else 1)
