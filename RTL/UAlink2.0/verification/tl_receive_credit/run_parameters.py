"""Run: python3 verification/tl_receive_credit/run_parameters.py --kd28-root PATH.
Writes actual supported/unsupported elaboration logs; next runtime capacity proofs.
"""
import argparse,json,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[2];p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);a=p.parse_args();S=R/'build/verification/tl_receive_credit/parameters';S.mkdir(exist_ok=False)
src=sorted((R/'rtl/tl').glob('*.v'))+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v'];root=a.kd28_root/'Library/models/kd28';ext=[root/'sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[root/'fifo/rtl/kd28_fifo_sdp_storage_map.v']
rows=[]
for w,d,c,valid in [(1,1,1,True),(8,100,7,True),(16,65535,16,True),(0,100,7,False),(17,100,7,False),(8,0,1,False),(8,65536,17,False),(8,3,1,False),(8,1,0,False)]:
    label=f'w{w}_d{d}_c{c}';cmd=['iverilog','-g2005','-s','tl_receive_credit','-o',str(S/(label+'.vvp')),f'-Ptl_receive_credit.WIDTH={w}',f'-Ptl_receive_credit.DEPTH={d}',f'-Ptl_receive_credit.COUNT_WIDTH={c}',*[str(x) for x in src+ext]]
    x=subprocess.run(cmd,capture_output=True,text=True,timeout=90);log=x.stdout+x.stderr;(S/(label+'.log')).write_text(log);row=dict(width=w,depth=d,count_width=c,valid=valid,exit_status=x.returncode,passed=(x.returncode==0 if valid else x.returncode!=0 and 'invalid' in log.lower()));rows.append(row);print(row,flush=True)
(S/'results.json').write_text(json.dumps(dict(complete=all(x['passed'] for x in rows),results=rows),indent=2)+'\n');raise SystemExit(0 if all(x['passed'] for x in rows) else 1)
