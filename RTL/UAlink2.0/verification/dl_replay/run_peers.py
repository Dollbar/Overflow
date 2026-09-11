"""Build and execute two actual data ports with real SRAM and ordered registered feedback.
Run: python3 verification/dl_replay/run_peers.py --depth 3 --width 32 --group-size 2 --delay 3 --count 1100 --seed 17 --inject --dependency-root PATH --record peer_3_32.json
Output: actual compiler/executable, full cycle/link traces, stats and record JSON.
Next: check_trace.py --record SAME_JSON, then complete all parameters and real fault challenges.
"""
from pathlib import Path
import argparse,json,tempfile,hashlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--depth',type=int,required=True);p.add_argument('--width',type=int,required=True);p.add_argument('--group-size',type=int,choices=(1,2,4),required=True);p.add_argument('--delay',type=int,required=True);p.add_argument('--count',type=int,required=True);p.add_argument('--seed',type=int,required=True);p.add_argument('--inject',action='store_true');p.add_argument('--dependency-root',type=Path,required=True);p.add_argument('--record',required=True);p.add_argument('--source',type=Path);a=p.parse_args();R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/dl_replay';S.mkdir(parents=True,exist_ok=True);(R/'build').mkdir(exist_ok=True)
if (S/a.record).exists():raise ValueError('refuse overwriting actual run evidence')
b=Path(tempfile.mkdtemp(prefix='actual_peers_',dir=D/'build'));src=a.source.resolve() if a.source else D/'rtl/dl/dl_replay_data_port.v';children=[D/'rtl/dl'/n for n in ('dl_replay_tx_control.v','dl_replay_tx_storage.v','dl_replay_event_port.v','dl_replay_receiver.v','dl_replay_header_tx.v')];root=a.dependency_root.resolve(strict=True)/'Library/models/kd28';external=[root/'sram/rtl/kd28_sram_sdp_model.v',root/'sram/rtl/kd28_sram_cells.v',root/'fifo/rtl/kd28_fifo_sdp_storage_map.v'];test=D/'verification/peer/peer_check.cpp';aw=max(1,(a.depth-1).bit_length())
cmd=['verilator','--cc','--exe','--build','-j','2','--top-module','dl_replay_data_port','--prefix','Vdl_replay_data_port','-Wno-DECLFILENAME','-Wno-TIMESCALEMOD','-Wno-WIDTH',f'-GC_DEPTH={a.depth}',f'-GC_DATA_WIDTH={a.width}',f'-GC_ADDR_WIDTH={aw}','-CFLAGS',f'-DPAYLOAD_WIDTH={a.width}','--Mdir',str(b/'obj'),str(src),*[str(x) for x in children+external],str(test)]
with (b/'compile.log').open('w') as f:rc=subprocess.run(cmd,cwd=D,stdout=f,stderr=subprocess.STDOUT,timeout=300).returncode
run=None;stats=None;run_cmd=[str(b/'obj/Vdl_replay_data_port'),str(a.group_size),str(a.delay),str(a.count),str(a.seed),str(int(a.inject)),str(b/'trace.txt'),str(b/'wire_trace.txt')]
if rc==0:
 with (b/'run.log').open('w') as f:
  try:run=subprocess.run(run_cmd,cwd=D,stdout=f,stderr=subprocess.STDOUT,timeout=180).returncode
  except subprocess.TimeoutExpired:run=124
 if run==0:stats=json.loads((b/'run.log').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();r=dict(depth=a.depth,width=a.width,group_size=a.group_size,delay=a.delay,count=a.count,seed=a.seed,inject=a.inject,directory=str(b.relative_to(R)),source=str(src.relative_to(R)),source_sha256=sha(src),children_sha256={str(p.relative_to(D)):sha(p) for p in children},test_sha256=sha(test),external_files={str(p):sha(p) for p in external},compile_command=cmd,run_command=run_cmd,compile_exit=rc,run_exit=run,stats=stats);(S/a.record).write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r),flush=True);raise SystemExit(rc or run)
