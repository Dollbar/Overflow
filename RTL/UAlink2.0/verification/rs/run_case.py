"""Execute actual calendar/rate/frame/formatter RTL against frozen cycle vectors.
Run: python3 verification/rs/run_case.py --serial 200 --lanes 1 --blocks 8 --label final [--full-calendar] [--source FILE]
Output: case_LABEL_SERIAL_LANES_BLOCKS.json, actual native trace and build inputs.
Next: all24 profiles, fault detection, independent proof and actual top-level STA.
"""
from pathlib import Path
import argparse,hashlib,importlib,importlib.util,json,random,shutil,subprocess,sys,tempfile
R=Path(__file__).resolve().parents[2];S=R/'build/verification/rs';S.mkdir(parents=True,exist_ok=True)
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
FLAGS=('command_ready','command_accepted','command_rejected','active','data_ready','data_consumed','output_valid','output_taken','last','frame_completed')
PORTS=('o_cmd_ready','o_cmd_accept','o_cmd_reject','o_active','o_data_ready','o_data_take','o_block_valid','o_block_take','o_block_last','o_frame_done','o_next_valid','o_flit_ready','o_flit_reserve','o_codeword_commit','o_dl_done','o_starved')
KINDS={None:0,'dl_flit':0,'alignment_marker':1,'rapid_alignment_marker':2,'rate_idle':3}
def reference(d):
    name='calendar_frame_reference'
    for key in tuple(sys.modules):
        if key==name or key.startswith(name+'.'):sys.modules.pop(key)
    spec=importlib.util.spec_from_file_location(name,d/'model/__init__.py',submodule_search_locations=[str(d/'model')]);p=importlib.util.module_from_spec(spec);sys.modules[name]=p;spec.loader.exec_module(p)
    return importlib.import_module(name+'.rs_calendar_frame')
def vectors(d,serial,lanes,n,full=False):
    m=reference(d);e=m.CalendarFrame(serial,lanes,n);rng=random.Random(serial*100+lanes*10+n);rows=[];sections={};frames=reserved=accepted=data_bytes=0
    period=16384 if serial==200 and lanes==4 else 8192 if lanes==4 or (serial==200 and lanes==2) else 4096
    def emit(fv=False,data=None,ready=True,reset=False,load=None,section='directed'):
        nonlocal frames,reserved,accepted,data_bytes
        raw=load or m.CalendarConfig(rng.randrange(16384),bool(rng.randrange(2)),bool(rng.randrange(2)),rng.randrange(2))
        payload=data if data is not None else rng.randbytes(8*n)
        o=e.tick(flit_valid=fv,data=data,ready=ready,reset=reset,phase_load=load);bits=[getattr(o.frame,x) for x in FLAGS]+[o.next_kind is not None,o.flit_ready,o.flit_reserved,o.codeword_completed,o.dl_completed,o.starved]
        flags=sum(int(v)<<i for i,v in enumerate(bits));headers=sum(b.sync_header<<(2*i) for i,b in enumerate(o.frame.blocks));words=[b.payload for b in o.frame.blocks] if o.frame.output_valid else [0]*n
        rows.append([int(not reset),int(load is not None),raw.phase,int(raw.rapid),int(raw.resiliency),raw.pl_id,int(fv),int(data is not None),int(ready),*[int.from_bytes(payload[i:i+8],'little') for i in range(0,8*n,8)],flags,o.frame.index,headers,o.phase,o.next_phase,KINDS[o.next_kind],*words])
        sections[section]=sections.get(section,0)+1;frames+=o.codeword_completed;reserved+=o.flit_reserved;accepted+=o.frame.command_accepted;data_bytes+=8*n*o.frame.data_consumed
        return o
    for _ in range(4):emit(reset=True,fv=True,data=bytes(8*n),section='reset')
    emit(section='startup')
    for _ in range(80//n):emit(fv=True,data=bytes(8*n),section='startup')
    # Literal boundary transactions, with source/control bus noise between loads.
    for rapid in (False,True):
        for start in (0,1,31,63,127,1023,period//128-1,period-1,16383):
            for lr,pl in ((False,0),(True,1)):
                emit(load=m.CalendarConfig(start,rapid,lr,pl),section='boundaries');emit(fv=True,section='boundaries')
                for frame_no in range(3):
                    for index in range(0,80,n):
                        data=bytes((frame_no*83+index*8+j)%256 for j in range(8*n))
                        emit(fv=True,data=data,section='boundaries')
    # Missing descriptor, reserved-frame data starvation, and last-group backpressure.
    for start in (1,1023,period-1,16383):
        emit(load=m.CalendarConfig(start),section='stalls')
        for _ in range(4):emit(data=bytes(8*n),section='stalls')
        emit(fv=True,data=bytes(8*n),section='stalls')
        for index in range(0,80,n):
            data=rng.randbytes(8*n)
            if index in (0,80-n):
                for _ in range(3):emit(fv=True,section='stalls')
                for _ in range(3):emit(fv=True,data=data,ready=False,section='stalls')
            emit(fv=True,data=data,section='stalls')
    # Reset/load abort before first group, after one, and at final transfer boundary.
    for rapid in (False,True):
        for prefix in (0,1,80//n-1):
            for reset in (False,True):
                emit(load=m.CalendarConfig(1,rapid,True,1),section='abort');emit(fv=True,section='abort')
                for _ in range(prefix):emit(data=bytes(8*n),section='abort')
                emit(fv=True,data=bytes(8*n),reset=reset,load=m.CalendarConfig(1024,not rapid),section='abort')
                emit(fv=True,section='abort')
                for _ in range(80//n):emit(fv=True,data=bytes(8*n),section='abort')
    # A long deterministic mixed stream obeys hold-until-consumed for payload.
    emit(load=m.CalendarConfig(1019,True,True,1),section='mixed');held=None
    for cycle in range(1000):
        if held is None and cycle%7:held=rng.randbytes(8*n)
        o=emit(fv=cycle%11!=0,data=held,ready=cycle%5!=0,section='mixed')
        if o.frame.data_consumed:held=None
    directed_rows=len(rows)
    if full:
        for rapid in (False,True):
            emit(load=m.CalendarConfig(0,rapid,True,1),section='complete_calendar');emit(fv=True,section='complete_calendar')
            for ordinal in range(period):
                for index in range(0,80,n):
                    o=emit(fv=True,data=bytes((ordinal+index+j)%256 for j in range(8*n)),section='complete_calendar')
                    if not o.frame.output_taken or o.phase!=ordinal or o.frame.index!=index:raise ValueError('independent complete-period scenario has a bubble or wrong phase')
    return rows,dict(rows=len(rows),clock_edges=len(rows),directed_rows=directed_rows,sections=sections,completed_frames=frames,reserved_flits=reserved,accepted_commands=accepted,consumed_data_bytes=data_bytes,full_calendar=full)
def driver(n):
    put='dut.i_data=data[0];' if n==1 else 'for(unsigned k=0;k<N;k++){dut.i_data[2*k]=uint32_t(data[k]);dut.i_data[2*k+1]=uint32_t(data[k]>>32);}'
    get='got[k]=dut.o_payloads;' if n==1 else 'got[k]=uint64_t(dut.o_payloads[2*k])|(uint64_t(dut.o_payloads[2*k+1])<<32);'
    flags='|'.join(f'(unsigned(dut.{name})<<{i})' for i,name in enumerate(PORTS))
    return f'''#include "Vrs_tx_calendar_frame.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
int main(int argc,char**argv){{
 constexpr unsigned N={n};if(argc!=3)return 2;std::ifstream input(argv[1]);std::ofstream trace(argv[2]);if(!input||!trace)return 2;
 Vrs_tx_calendar_frame dut;dut.i_clk=0;dut.eval();unsigned rstn,load,phase,rapid,lr,pl,fv,dv,ready,eflags,index,headers,op,np,nk;uint64_t row=0;std::array<uint64_t,N>data,expected,got;
 while(input>>rstn>>load>>phase>>rapid>>lr>>pl>>fv>>dv>>ready){{
  for(auto &x:data)input>>x;input>>eflags>>index>>headers>>op>>np>>nk;for(auto &x:expected)input>>x;if(!input)return 2;
  dut.i_rstn=rstn;dut.i_phase_load=load;dut.i_phase=phase;dut.i_rapid=rapid;dut.i_resiliency=lr;dut.i_pl_id=pl;dut.i_flit_valid=fv;dut.i_data_valid=dv;dut.i_block_ready=ready;{put}dut.eval();
  unsigned actual_flags={flags};for(unsigned k=0;k<N;k++){{{get}}}
  trace<<rstn<<' '<<load<<' '<<phase<<' '<<rapid<<' '<<lr<<' '<<pl<<' '<<fv<<' '<<dv<<' '<<ready;for(auto x:data)trace<<' '<<x;trace<<' '<<actual_flags<<' '<<unsigned(dut.o_block_index)<<' '<<unsigned(dut.o_sync_headers)<<' '<<unsigned(dut.o_phase)<<' '<<unsigned(dut.o_next_phase)<<' '<<unsigned(dut.o_next_kind);for(auto x:got)trace<<' '<<x;trace<<'\\n';
  if(actual_flags!=eflags||dut.o_block_index!=index||dut.o_sync_headers!=headers||dut.o_phase!=op||dut.o_next_phase!=np||dut.o_next_kind!=nk||got!=expected){{std::cerr<<"MISMATCH row "<<row<<" actual calendar/frame outputs; clock_edges "<<row<<"\\n";return 1;}}
  dut.i_clk=1;dut.eval();dut.i_clk=0;dut.eval();++row;
 }}
 std::cout<<"PASS rows "<<row<<" clock_edges "<<row<<"\\n";return 0;
}}
'''
def main():
    p=argparse.ArgumentParser();p.add_argument('--serial',type=int,choices=(100,200),required=True);p.add_argument('--lanes',type=int,choices=(1,2,4),required=True);p.add_argument('--blocks',type=int,choices=(1,2,4,8),required=True);p.add_argument('--label',required=True);p.add_argument('--full-calendar',action='store_true');p.add_argument('--source',type=Path);a=p.parse_args()
    record=S/f'case_{a.label}_{a.serial}_{a.lanes}_{a.blocks}.json'
    if record.exists():raise ValueError('refuse actual case overwrite')
    d=R;b=Path(tempfile.mkdtemp(prefix=f'{a.label}_{a.serial}_{a.lanes}_{a.blocks}_',dir=d/'build'));source=a.source.resolve() if a.source else d/'rtl/phy/rs_tx_calendar_frame.v'
    shutil.copy2(source,b/'rs_tx_calendar_frame.v')
    for name in ('rs_tx_block_formatter.v','rs_tx_rate_scheduler.v','rs_tx_frame_control.v'):shutil.copy2(d/'rtl/phy'/name,b/name)
    shutil.copytree(d/'model/phy',b/'model',ignore=shutil.ignore_patterns('__pycache__'));(b/'driver.cpp').write_text(driver(a.blocks));rows,stats=vectors(b,a.serial,a.lanes,a.blocks,a.full_calendar)
    with (b/'vectors.txt').open('w') as f:
        for row in rows:f.write(' '.join(map(str,row))+'\n')
    del rows
    cmd=['verilator','--cc','--exe','--build','-j','2','--Mdir',str(b/'obj'),'--top-module','rs_tx_calendar_frame','--prefix','Vrs_tx_calendar_frame',f'-GC_SERIAL_GBPS={a.serial}',f'-GC_LANES={a.lanes}',f'-GC_BLOCKS={a.blocks}',*[str(b/name) for name in ('rs_tx_calendar_frame.v','rs_tx_rate_scheduler.v','rs_tx_frame_control.v','rs_tx_block_formatter.v')],str(b/'driver.cpp')]
    with (b/'compile.log').open('w') as f:rc=subprocess.run(cmd,cwd=b,stdout=f,stderr=subprocess.STDOUT,timeout=180).returncode
    run_cmd=[str(b/'obj/Vrs_tx_calendar_frame'),str(b/'vectors.txt'),str(b/'trace.txt')];run_rc=None
    if rc==0:
        with (b/'run.log').open('w') as f:run_rc=subprocess.run(run_cmd,cwd=b,stdout=f,stderr=subprocess.STDOUT,timeout=120).returncode
    passed=rc==0 and run_rc==0 and (b/'run.log').read_text().strip()==f"PASS rows {stats['rows']} clock_edges {stats['rows']}"
    r=dict(serial=a.serial,lanes=a.lanes,blocks=a.blocks,label=a.label,directory=str(b.relative_to(R)),source_sha256=sha(b/'rs_tx_calendar_frame.v'),compile_command=cmd,compile_exit=rc,run_command=run_cmd,run_exit=run_rc,passed=passed,stats=stats,files={str(p.relative_to(b)):sha(p) for p in b.rglob('*') if p.is_file() and not {'obj','__pycache__'}.intersection(p.relative_to(b).parts)})
    record.write_text(json.dumps(r,indent=2)+'\n');print(a.label,a.serial,a.lanes,a.blocks,'PASS' if passed else 'FAIL',stats,flush=True);return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
