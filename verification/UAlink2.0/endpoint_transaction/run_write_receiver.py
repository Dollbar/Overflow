#!/usr/bin/env python3
"""Check mixed Read/Write ownership directly at the real retired-TL receiver.
Run: python3 [-O] verification/endpoint_transaction/run_write_receiver.py --label NEW [--faults] [--baseline]
Outputs: build/verification/endpoint_transaction/NEW snapshots, vectors, logs and result.json.
Next: run actual Endpoint/Switch Write execution after this parser passes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())

def request(tag,address,length,full=False,read=False):
    size=4*(length+1);beats=((address%64)+size+63)//64
    return dict(tag=tag,address=address,length=length,full=full,read=read,beats=beats,
                attr=255 if read else 0x69,asi=0 if read else 2,meta=0 if read else 0xa7,src=513,dst=17)
def control(q):
    cmd=3 if q['read'] else 0x29 if q['full'] else 0x28
    return (1<<124)|(cmd<<118)|(q['asi']<<114)|(q['tag']<<103)|(q['attr']<<94)|(q['length']<<88)|(q['meta']<<80)|((q['address']>>2)<<25)|(q['src']<<15)|(q['dst']<<5)|(0 if q['read'] else q['beats']-1)
def response(tag,write=False):
    return (2<<60)|(tag<<47)|(0 if write else (1<<37)|(1<<36))|(513<<26)|(17<<16)
def pack(fields):
    value=0
    for v,w in fields:value=(value<<w)|v
    return value

def vectors():
    records=[];requests=[];responses=[]
    def record(low=0,high=0,lc=0,hc=3,msg=0):
        releases=((len(records)+1)*0x123456789abcdef)&((1<<80)-1)
        records.append((releases<<520)|(high<<256)|low|(msg<<512)|(lc<<514)|(hc<<517))
    def payload(q):
        data=sum(((q['tag']+j*29+byte*7)&255)<<(512*j+8*byte) for j in range(q['beats']) for byte in range(64))
        allowed=((1<<(4*(q['length']+1)))-1)<<(q['address']%256)
        be=allowed if q['full'] else allowed & int('55'*32,16)
        if q['tag']==1024:be=0
        return data,be
    def expected(q,data,be):
        requests.append(pack([(not q['read'],1),(q['full'],1),(q['tag'],11),(q['src'],10),(q['dst'],10),(q['address'],57),(q['length'],6),(q['attr'],8),(0,2),(0,1),(q['asi'],2),(q['meta'],8),(data,2048),(be,256)]))
    # A prior WriteFull final Data shares the record with the next Control.
    q=request(2047,128,15,full=True);d,b=payload(q);expected(q,d,b)
    record(control(q),d&((1<<256)-1),0,1)
    r=request(13,64,15,read=True);expected(r,0,0)
    record(control(r)|response(100,True)<<128,d>>256,0,1)
    responses.append(pack([(1,1),(0,2),(100,11),(17,10),(0,4),(0,2),(0,1),(0,2),(0,512),(0,1)]))
    # Read Response and Write share the same owner queue, despite separate output queues.
    q=request(1024,60,1);d,b=payload(q);expected(q,d,b)
    record(control(q)|response(101)<<128)
    halves=[(d>>(256*j))&((1<<256)-1) for j in range(2*q['beats'])]+[b,0xabcdef,0x987654]
    classes=[1]*(2*q['beats'])+[2,1,1]
    for j in range(0,len(halves),2):record(halves[j],halves[j+1] if j+1<len(halves) else 0,classes[j],classes[j+1] if j+1<len(halves) else 3)
    responses.append(pack([(0,1),(0,2),(101,11),(17,10),(0,4),(0,2),(1,1),(0,2),(0xabcdef|(0x987654<<256),512),(0,1)]))
    # A prior normal Write BE tail, new Control at sector4, and ordinary MSG delay.
    q=request(2001,192,0);d,b=payload(q);expected(q,d,b)
    record(control(q));record(0,1,4,4,3);record(d&((1<<256)-1),d>>256,1,1)
    r=request(2002,0,15,read=True);expected(r,0,0)
    record((control(r)|12)<<128,b,0,2) # inactive CWAY ignored
    # Both natural uncompressed Request positions, interleaved Data and BE owners.
    a=request(2003,4,0);z=request(2004,128,15,True)
    da,ba=payload(a);dz,bz=payload(z);expected(a,da,ba);expected(z,dz,bz)
    record(control(a)|(control(z)<<128));record(da&((1<<256)-1),da>>256,1,1)
    record(ba,dz&((1<<256)-1),2,1);record(0,dz>>256,0,1)
    # Fill/wrap the independent response FIFO; all statuses, unused OFFSET/LAST/SPARE.
    for group in range(6):
        word=0
        for position in range(4):
            tag=120+group*4+position;status=(0,2,3,6,8)[tag%5];off=tag%4;last=tag%2
            word|=(response(tag,True)|(status<<38)|(off<<42)|(last<<36)|0x3fff)<<(position*64)
            responses.append(pack([(1,1),(0,2),(tag,11),(17,10),(status,4),(off,2),(last,1),(0,2),(0,512),(0,1)]))
        record(word)
    # Every legal byte offset/length geometry, including all ten WriteFull cases.
    tag=20
    for full in (False,True):
        for offset in range(0,256,64 if full else 4):
            for length in (range(15,64,16) if full else range(64)):
                if offset+4*(length+1)>256:continue
                q=request(tag%2048,(1<<56)+offset,length,full=full);tag+=1
                d,b=payload(q);expected(q,d,b);record(control(q))
                hs=[(d>>(256*j))&((1<<256)-1) for j in range(2*q['beats'])]
                for j in range(0,len(hs),2):record(hs[j],hs[j+1],1,1)
                if not full:record(b,0,2,3)
    return records,requests,responses

TB=r'''`timescale 1ns/1ps
module tb;
parameter N=1,Q=1,S=1;
parameter EXPECT_ERROR=0,PORT_FLIP=0,LONG_STALL=0,CAUSAL_READY=0,RESET_AT=0;
reg clk=0;always #5 clk=~clk;reg rstn=0,iv=0;reg[599:0] record=0;wire ready,error,qv,sv;
wire[10:0]qt,st;wire[9:0]qs,qd,sd;wire[56:0]qa;wire[5:0]ql;wire[7:0]qat,qm;wire[1:0]qvc,qasi,sp,so,sn;wire qp,sl,se;wire[3:0]ss;wire[511:0]sdata;
wire qw,qf,sw;wire[2047:0]qdata;wire[255:0]qbe;
reg[599:0] inputs[0:N-1];reg[2420:0]reqs[0:Q-1];reg[545:0]rsps[0:S-1];
integer cycle=0,in_count=0,req_count=0,rsp_count=0,quiet=0;
reg[599:0]last_record=0;reg have_record=0;reg[1:0]port=0;integer error_cycles=0;
integer reset_cycles=0;reg reset_done=0;
reg qr=0,sr=0; // Ready在下降沿驱动，避免scoreboard与DUT采样竞态。
`ifdef LEGACY_BASELINE
endpoint_receive_transactions dut(
`else
endpoint_receive_transactions #(.WRITE_ENABLE(1)) dut(
.o_request_is_write(qw),.o_request_full(qf),.o_request_data(qdata),.o_request_be(qbe),.o_response_is_write(sw),
`endif
.i_clk(clk),.i_rstn(rstn),.i_port(port),.i_read_valid(iv),.o_read_ready(ready),.i_read_flit(record[511:0]),.i_read_msg(record[513:512]),.i_read_classes(record[519:514]),.i_read_releases(record[599:520]),
.o_request_valid(qv),.i_request_ready(qr),.o_request_tag(qt),.o_request_src(qs),.o_request_dst(qd),.o_request_address(qa),.o_request_length(ql),.o_request_attr(qat),.o_request_vc(qvc),.o_request_pool(qp),.o_request_asi(qasi),.o_request_metadata(qm),
.o_response_valid(sv),.i_response_ready(sr),.o_response_port(sp),.o_response_tag(st),.o_response_dst(sd),.o_response_status(ss),.o_response_offset(so),.o_response_last(sl),.o_response_num_beats(sn),.o_response_data(sdata),.o_response_data_error(se),.o_error(error));
initial begin $readmemh("records.mem",inputs);$readmemh("requests.mem",reqs);$readmemh("responses.mem",rsps);repeat(3)@(negedge clk);rstn=1;end
always@(negedge clk)begin
 if(have_record&&dut.r_record!==last_record)$fatal(1,"WRITE_RX_RECORD_NOT_ATOMIC");
 if(RESET_AT!=0&&!reset_done&&in_count==RESET_AT&&(reset_cycles!=0||ready))begin
  rstn=0;have_record=0;reset_cycles=reset_cycles+1;
  if(reset_cycles==3)begin reset_done=1;rstn=1;end
 end
 qr=(cycle%7!=1)&&(!LONG_STALL||cycle>300)&&(!CAUSAL_READY||rsp_count>0);sr=(cycle%11!=4)&&(!LONG_STALL||cycle>1500);
 port=(PORT_FLIP&&in_count>0)?2'd1:2'd0;
 iv=rstn&&(in_count<N)&&!(RESET_AT!=0&&!reset_done&&in_count==RESET_AT);if(in_count<N)record=inputs[in_count];
end
always@(posedge clk)begin
 cycle=cycle+1;
 if(rstn)begin
  if(error)begin
   if(!EXPECT_ERROR)$fatal(1,"WRITE_RX_ERROR input=%0d req=%0d rsp=%0d",in_count,req_count,rsp_count);
   if(ready||qv||sv)$fatal(1,"WRITE_RX_ERROR_NOT_FAILSTOP");
   error_cycles=error_cycles+1;
   if(error_cycles==8)begin $display("WRITE_RX_REJECT_PASS");$finish;end
  end
  if(EXPECT_ERROR&&(qv||sv))$fatal(1,"WRITE_RX_ILLEGAL_COMMITTED");
  if(iv&&ready)begin last_record=record;have_record=1;in_count=in_count+1;end
  if(qv)begin
   if(req_count>=Q||{qw,qf,qt,qs,qd,qa,ql,qat,qvc,qp,qasi,qm,qdata,qbe}!==reqs[req_count])begin
    $display("REQUEST_ACTUAL %h",{qw,qf,qt,qs,qd,qa,ql,qat,qvc,qp,qasi,qm,qdata,qbe});
    $display("REQUEST_EXPECT %h",reqs[req_count]);
    $display("REQUEST_FIELDS write=%b full=%b tag=%0d address=%h length=%0d BE=%h",qw,qf,qt,qa,ql,qbe);
    $fatal(1,"WRITE_RX_REQUEST index=%0d",req_count);
   end
   if(qr)req_count=req_count+1;
  end
  if(sv)begin
   if(rsp_count>=S||{sw,sp,st,sd,ss,so,sl,sn,sdata,se}!==rsps[rsp_count])begin
    $display("RESPONSE_ACTUAL %h",{sw,sp,st,sd,ss,so,sl,sn,sdata,se});$display("RESPONSE_EXPECT %h",rsps[rsp_count]);
    $fatal(1,"WRITE_RX_RESPONSE index=%0d",rsp_count);
   end
   if(sr)rsp_count=rsp_count+1;
  end
  if(in_count==N&&req_count==Q&&rsp_count==S)quiet=quiet+1;else quiet=0;
  if(quiet==20&&!EXPECT_ERROR)begin $display("WRITE_RX_PASS records=%0d requests=%0d responses=%0d cycles=%0d",N,Q,S,cycle);$finish;end
  if(EXPECT_ERROR&&cycle>500)$fatal(1,"WRITE_RX_MISSING_DIAGNOSTIC");
  if(cycle>200000)$fatal(1,"WRITE_RX_TIMEOUT");
 end
end
endmodule
'''

def negative_vectors():
    def rec(low=0,high=0,lc=0,hc=3,msg=0):return low|(high<<256)|(msg<<512)|(lc<<514)|(hc<<517)
    q=request(33,128,0);header=control(q)
    cases={
      'multicast_command':[rec((header&~(63<<118))|(0x26<<118))],
      'full_unaligned':[rec(control(request(33,4,15,True)))],
      'full_short_length':[rec(control(request(33,0,0,True)))],
      'cross_region':[rec(control(request(33,252,1)))],
      'numbeats_mismatch':[rec(header^1)],
      'request_pool':[rec(header|(1<<102))],
      'request_vc':[rec(header|(1<<116))],
      'cache_load':[rec(header|(1<<4))],
      'compressed_request':[rec(3<<60)],
      'response_reserved_status':[rec(response(33,True)|(1<<38))],
      'response_data_length':[rec(response(33,True)|(1<<44))],
      'response_multicast':[rec(response(33,True)|(2<<14))],
      'read_response_offset':[rec(response(33)|(1<<42))],
      'orphan_data':[rec(1,0,1,3)],
      'orphan_be':[rec(1,0,2,3)],
      'early_be':[rec(header),rec(1<<128,0,2,3)],
      'range_be':[rec(header),rec(0x11,0x22,1,1),rec(1,0,2,3)],
      'missing_be_replaced_data':[rec(header),rec(0x11,0x22,1,1),rec(0,0,1,3)],
      'poison':[rec(header),rec(32,0,5,3,1)],
      'auth':[rec(header,0,0,6)],
      'msg_class_mismatch':[rec(0,0,4,3)],
      'unknown_message':[rec(9,0,4,3,1)],
      'nonzero_nop':[rec(header,1,0,3)],
      'late_invalid_field':[rec(control(request(1,0,15,read=True))|(3<<188))],
      'port_mismatch':[rec(header),rec(0x11,0x22,1,1)]}
    return cases


def causal_vectors():
    # Eight queued Read requests cannot retire until the prior response arrives.
    # Its final upper Data shares a record with a ninth Request into the full FIFO.
    requests=[];records=[]
    for j in range(9):
        q=request(300+j,0,15,read=True)
        requests.append(pack([(0,1),(0,1),(q['tag'],11),(513,10),(17,10),(0,57),(15,6),(255,8),(0,2),(0,1),(0,2),(0,8),(0,2048),(0,256)]))
        if j<8:
            if j%2==0:records.append(control(q)|(3<<517))
            else:records[-1]|=control(q)<<128
    records.append(response(400)|(0x123<<256)|(1<<517))
    records.append(control(request(308,0,15,read=True))|(0x456<<256)|(1<<517))
    responses=[pack([(0,1),(0,2),(400,11),(17,10),(0,4),(0,2),(1,1),(0,2),(0x123|(0x456<<256),512),(0,1)])]
    return records,requests,responses


def reset_vectors():
    old=request(900,0,63,True);new=request(901,128,15,True);data=0x111|(0x222<<256);be=((1<<64)-1)<<128
    records=[control(old)|(0xdead<<256)|(1<<517),0xbeef|(0xface<<256)|(1<<514)|(1<<517),
             control(new)|(response(902,True)<<128)|(3<<517),data|(1<<514)|(1<<517)]
    requests=[pack([(1,1),(1,1),(901,11),(513,10),(17,10),(128,57),(15,6),(0x69,8),(0,2),(0,1),(2,2),(0xa7,8),(data,2048),(be,256)])]
    responses=[pack([(1,1),(0,2),(902,11),(17,10),(0,4),(0,2),(0,1),(0,2),(0,512),(0,1)])]
    return records,requests,responses


def run_case(stage,values,*,baseline=False,expect_error=False,port_flip=False,long_stall=False,causal_ready=False,reset_at=0,fault=None):
    stage.mkdir(parents=True,exist_ok=False)
    records,requests,responses=values
    for name,items in [('records',records),('requests',requests or [0]),('responses',responses or [0])]:
        (stage/(name+'.mem')).write_text(''.join(format(x,'x')+'\n' for x in items))
    (stage/'tb.sv').write_text(TB)
    (stage/'run_write_receiver.py').write_bytes(Path(__file__).read_bytes())
    paths=[ROOT/'rtl/endpoint/endpoint_receive_transactions.v',ROOT/'rtl/endpoint/endpoint_response_assembler.v',ROOT/'rtl/tl/tl_control_decode.v'];copies=[]
    for path in paths:
        dest=stage/path.name;source=path.read_text()
        if fault and path.name=='endpoint_receive_transactions.v':
            old,new=fault
            if source.count(old)!=1:raise RuntimeError('fault target missing or ambiguous')
            source=source.replace(old,new)
        dest.write_text(source);copies.append(dest)
    command=['iverilog','-g2012','-s','tb',f'-Ptb.N={len(records)}',f'-Ptb.Q={max(1,len(requests))}',f'-Ptb.S={max(1,len(responses))}',
             f'-Ptb.EXPECT_ERROR={int(expect_error)}',f'-Ptb.PORT_FLIP={int(port_flip)}',f'-Ptb.LONG_STALL={int(long_stall)}',f'-Ptb.CAUSAL_READY={int(causal_ready)}',f'-Ptb.RESET_AT={reset_at}']+(['-DLEGACY_BASELINE'] if baseline else [])+['-o',str(stage/'sim.vvp'),*map(str,copies),str(stage/'tb.sv')]
    source_paths={str(path.relative_to(ROOT)):path for path in paths}
    source_paths['verification/endpoint_transaction/run_write_receiver.py']=Path(__file__)
    result=dict(passed=False,baseline=baseline,sources={name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in source_paths.items()},records=len(records),requests=len(requests),responses=len(responses),fault=fault,expect_error=expect_error)
    for name,cmd in [('compile',command),('run',['vvp',str(stage/'sim.vvp')])]:
        with (stage/(name+'.log')).open('w') as log:code=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
        result[name+'_exit']=code;result[name+'_command']=cmd
        if name=='compile' and code:break
    log=(stage/'run.log').read_text() if (stage/'run.log').exists() else ''
    marker='WRITE_RX_REJECT_PASS' if expect_error else 'WRITE_RX_PASS'
    result['passed']=result.get('compile_exit')==0 and result.get('run_exit')==0 and marker in log
    result['expected_red']=(baseline or fault is not None) and result.get('compile_exit')==0 and result.get('run_exit')==1 and any(x in log for x in ('WRITE_RX_ERROR','WRITE_RX_REQUEST','WRITE_RX_RESPONSE','WRITE_RX_ILLEGAL_COMMITTED','WRITE_RX_MISSING_DIAGNOSTIC','WRITE_RX_TIMEOUT'))
    result['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


def static_checks(stage):
    stage.mkdir()
    paths=[ROOT/'rtl/endpoint/endpoint_receive_transactions.v',ROOT/'rtl/endpoint/endpoint_response_assembler.v',ROOT/'rtl/tl/tl_control_decode.v']
    sources=[]
    for path in paths:
        target=stage/path.name;shutil.copyfile(path,target);sources.append(target)
    results=[]
    for mode in (0,1):
        script='read_verilog '+ ' '.join('"'+str(p)+'"' for p in sources)+'\n'
        script+=f'chparam -set WRITE_ENABLE {mode} endpoint_receive_transactions\nhierarchy -check -top endpoint_receive_transactions\nproc\nopt\ncheck -assert\nstat\n'
        ys=stage/f'mode{mode}.ys';ys.write_text(script)
        commands=[('g2001',['iverilog','-g2001','-s','endpoint_receive_transactions',f'-Pendpoint_receive_transactions.WRITE_ENABLE={mode}','-o',str(stage/f'mode{mode}.vvp'),*map(str,sources)]),
                  ('lint',['verilator','--lint-only','--top-module','endpoint_receive_transactions',f'-GWRITE_ENABLE={mode}','-Wall',*map(str,sources)]),
                  ('yosys',['yosys','-Q','-s',str(ys)])]
        for name,cmd in commands:
            with (stage/f'{name}_mode{mode}.log').open('w') as log:
                result=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=180)
            results.append({'check':name,'mode':mode,'exit_code':result.returncode,'command':cmd})
    (stage/'result.json').write_text(json.dumps(results,indent=2)+'\n')
    return results


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--baseline',action='store_true');p.add_argument('--faults',action='store_true');a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('fresh safe label required')
    stage=ROOT/'build/verification/endpoint_transaction'/a.label
    stage.mkdir(parents=True,exist_ok=False)
    cases=[]
    values=vectors()
    for name,kwargs in [('ordered',{}),('long_backpressure',{'long_stall':True})]:
        if a.baseline and name!='ordered':continue
        result=run_case(stage/name,values,baseline=a.baseline,**kwargs)
        cases.append(dict(name=name,passed=result['expected_red'] if a.baseline else result['passed']))
    if not a.baseline:
        result=run_case(stage/'causal_old_tail',causal_vectors(),causal_ready=True)
        cases.append(dict(name='causal_old_tail',passed=result['passed']))
        result=run_case(stage/'reset_partial_write',reset_vectors(),reset_at=2)
        cases.append(dict(name='reset_partial_write',passed=result['passed']))
        for name,records in negative_vectors().items():
            result=run_case(stage/name,(records,[],[]),expect_error=True,port_flip=name=='port_mismatch')
            cases.append(dict(name=name,passed=result['passed']))
        if a.faults:
            faults={
              'half_bit':('request_data[data_slot][half_count*256+:256]<=payload;','request_data[data_slot][half_count*256+:256]<=payload^256\'d1;'),
              'be_zero':('if(expect_be)request_be[data_slot]<=payload;','if(expect_be)request_be[data_slot]<=256\'d0;'),
              'tag_bit':('requests[request_tail]<=f128;','requests[request_tail]<=f128^(128\'d1<<103);'),
              'old_tail_reassigned':('if(owner_count!=0&&(upper_class==1||upper_class==2))state<=EARLY;','if(1\'b0)state<=EARLY;')}
            for name,fault in faults.items():
                causal=name=='old_tail_reassigned'
                result=run_case(stage/('fault_'+name),causal_vectors() if causal else values,fault=fault,causal_ready=causal)
                cases.append(dict(name='fault_'+name,passed=result['expected_red']))
    checks=[] if a.baseline else static_checks(stage/'static')
    report={'passed':all(c['passed'] for c in cases) and all(c['exit_code']==0 for c in checks),'cases':cases,'requests':len(values[1]),'records':len(values[0]),'responses':len(values[2]),'optimized':not __debug__,'static_checks':checks}
    report['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ('artifacts_sha256','static_checks')},indent=2))
    return 0 if report['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
