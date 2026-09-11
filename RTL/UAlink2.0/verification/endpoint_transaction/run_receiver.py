#!/usr/bin/env python3
"""Check real receiver/assembler with independent tuples and ordered Data.

Run: python3 verification/endpoint_transaction/run_receiver.py --label fresh --faults
Outputs: build/verification/endpoint_transaction/LABEL/result.json and isolated
source/TB/compile/simulation evidence. Existing labels are never overwritten.
Next: connect actual TL receive storage and causal originator/completer engines.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FILES = ['rtl/endpoint/endpoint_receive_transactions.v',
         'rtl/endpoint/endpoint_response_assembler.v', 'rtl/tl/tl_control_decode.v']


def read(tag=0, src=1, dst=2, address=0, cway=0):
    # Independent Table 5-29 fixed field plus bit placements, no production encoder.
    return 0x10c0003fcf0000000000000000000000 | tag << 103 | src << 15 | dst << 5 | address << 23 | cway << 2


def response(tag=0, dst=1, status=0, src=2, spare=0):
    return 0x2000003000000000 | tag << 47 | src << 26 | dst << 16 | status << 38 | spare


def req_tuple(tag=0, src=1, dst=2, address=0):
    fields = [(tag,11),(src,10),(dst,10),(address,57),(15,6),(255,8),(0,2),(0,1),(0,2),(0,8)]
    value = 0
    for val, width in fields:
        value = (value << width) | val
    return value


def rsp_tuple(tag, data, port=2, dst=1, status=0):
    fields = [(port,2),(tag,11),(dst,10),(status,4),(0,2),(1,1),(0,2),(data,512),(0,1)]
    value = 0
    for val, width in fields:
        value = (value << width) | val
    return value


def half(seed):
    return int.from_bytes(bytes((seed + 7*i) & 255 for i in range(32)), 'little')


def rec(lower, upper=0, classes=(0,3), msg=0, port=2):
    return dict(flit=lower | upper << 256, classes=classes[0] | classes[1] << 3, msg=msg, port=port)


def vectors():
    cases = []
    records=[]; requests=[]; responses=[]
    # Both four-sector positions, full high address/tag/ID; CLOAD=0 CWAY ignored.
    records.append(rec(read(2047,1023,1022,(1<<57)-64,3) | read(1023,511,512,0x12340)<<128))
    requests += [req_tuple(2047,1023,1022,(1<<57)-64),req_tuple(1023,511,512,0x12340)]
    # Every legal uncompressed Response start, nonzero FC and SPARE.
    for sector in (0,2,4,6):
        tag=10+sector; a=half(tag); b=half(tag+81)
        control=response(tag, spare=0x3fff) << (32*sector)
        fcsector=2 if sector==0 else 0
        control |= 0x00000001 << (32*fcsector)
        records += [rec(control,a,(0,1)),rec(0,b,(0,1))]
        responses.append(rsp_tuple(tag,a|(b<<256)))
    # Old trailing half + two new Read fields, then old trailing half + four new headers.
    a=half(30);b=half(31)
    records += [rec(response(31),a,(0,1)),rec(read(7)|read(8,address=64)<<128,b,(0,1))]
    requests += [req_tuple(7),req_tuple(8,address=64)];responses.append(rsp_tuple(31,a|(b<<256)))
    a=half(40);b=half(41)
    records.append(rec(response(40),a,(0,1)))
    control=sum(response(100+i,status=3 if i==3 else 0)<<(64*i) for i in range(4))
    records.append(rec(control,b,(0,1)));responses.append(rsp_tuple(40,a|(b<<256)))
    for i in range(4):
        a=half(90+i);b=half(190+i)
        records.append(rec(a,b,(1,1)))
        responses.append(rsp_tuple(100+i,a|(b<<256),status=3 if i==3 else 0))
    # Message delays first Data and later final Data: msg0 and msg1 types 0/1.
    a=half(55);b=half(56)
    records += [rec(response(55),1,(0,4),2),rec(a,0,(1,4),2),rec(1,b,(4,1),1)]
    responses.append(rsp_tuple(55,a|(b<<256)))
    # Intermixed uncompressed Read and two Response fields in one real Control.
    a,b,c,d=(half(120+i) for i in range(4))
    records += [rec(read(99,address=1<<56) | response(201)<<128 | response(202)<<192,a,(0,1)),
                rec(b,c,(1,1)),rec(0,d,(0,1))]
    requests.append(req_tuple(99,address=1<<56))
    responses += [rsp_tuple(201,a|(b<<256)),rsp_tuple(202,c|(d<<256))]
    cases.append(dict(name='ordered',records=records,requests=requests,responses=responses,error=False))
    # Whole-word rejection must suppress a good early request if a later field is unsupported.
    bad_controls=[('compressed',read() | (3<<60)<<128),('write',read() ^ (0x20<<118)),
                  ('late_write',read() | (read() ^ (0x20<<118))<<128),
                  ('address',read() | 1<<25),('length',read() ^ 1<<88),('attr',read() ^ 1<<94),
                  ('vc',read() | 1<<116),('pool',read() | 1<<102),('asi',read() | 1<<114),
                  ('metadata',read() | 1<<80),('cache_load',read() | 1<<4),
                  ('read_numbeats',read() | 1),('rsp_type',response() | 1<<14),
                  ('rsp_vc',response() | 1<<58),('rsp_pool',response() | 1<<46),('rsp_status',response(status=1)),('rsp_last',response() ^ 1<<36),
                  ('rsp_offset',response() | 1<<42),('rsp_length',response() | 1<<44),
                  ('write_response',response() ^ 1<<37),('compressed_response',4<<28),('compressed_multi_response',5<<28),('bad_ftype',15<<28)]
    for name,control in bad_controls:
        cases.append(dict(name=name,records=[rec(control)],requests=[],responses=[],error=True))
    for name,record in [('auth',rec(read(),0,(0,6))),('poison_upper',rec(read(),0x20,(0,5),2)),
                        ('byte_enable',rec(0,0,(2,3))),('class7',rec(0,0,(7,3))),
                        ('upper_control',rec(read(),0,(0,0))),('nonzero_nop',rec(read(),1)),
                        ('class_msg',rec(read(),0,(0,3),1)),('bad_msg',rec(read(),7,(0,4),2)),
                        ('orphan_data',rec(half(3),half(4),(1,1)))]:
        cases.append(dict(name=name,records=[record],requests=[],responses=[],error=True))
    cases.append(dict(name='poison_pair',records=[rec(response(),half(1),(0,1)),rec(0,0x20,(0,5),2)],requests=[],responses=[],error=True))
    cases.append(dict(name='port_mismatch',records=[rec(response(),half(1),(0,1)),rec(0,half(2),(0,1),port=1)],requests=[],responses=[],error=True))
    cases.append(dict(name='reset_partial',records=[rec(response(8),half(8),(0,1))],requests=[],responses=[],error=False,reset_partial=True))
    return cases


PORTS = '''.i_clk(clk),.i_rstn(rstn),.i_port(port),.i_read_valid(iv),.o_read_ready(ir),
.i_read_flit(flit),.i_read_msg(msg),.i_read_classes(classes),.i_read_releases(releases),
.o_request_valid(qv),.i_request_ready(qr),.o_request_tag(qtag),.o_request_src(qsrc),.o_request_dst(qdst),
.o_request_address(qaddr),.o_request_length(qlen),.o_request_attr(qattr),.o_request_vc(qvc),
.o_request_pool(qpool),.o_request_asi(qasi),.o_request_metadata(qmeta),
.o_response_valid(sv),.i_response_ready(sr),.o_response_port(sport),.o_response_tag(stag),
.o_response_dst(sdst),.o_response_status(sstatus),.o_response_offset(soffset),.o_response_last(slast),
.o_response_num_beats(sbeats),.o_response_data(sdata),.o_response_data_error(sderr),.o_error(error)'''


def tb(case):
    records=case['records'];rq=case['requests'];rs=case['responses']
    text='''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rstn=0,iv=0; reg [1:0] port=2,msg=0;reg [511:0] flit=0;reg [5:0] classes=0;reg [79:0] releases=0;
wire ir,qv,sv,error;reg qr=0,sr=0;
wire [10:0] qtag,stag;wire [9:0] qsrc,qdst,sdst;wire [56:0] qaddr;wire [5:0] qlen;wire [7:0] qattr,qmeta;
wire [1:0] qvc,qasi,sport,soffset,sbeats;wire qpool,slast,sderr;wire [3:0] sstatus;wire [511:0] sdata;
wire [114:0] qt={qtag,qsrc,qdst,qaddr,qlen,qattr,qvc,qpool,qasi,qmeta};
wire [544:0] st={sport,stag,sdst,sstatus,soffset,slast,sbeats,sdata,sderr};
reg [114:0] expected_q[0:255];reg [544:0] expected_s[0:255];
integer qc=0,sc=0,cap=0,cycle=0,waited=0;reg old_qstall=0,old_sstall=0;
reg [114:0] old_q;reg [544:0] old_s;reg [599:0] accepted;
endpoint_receive_transactions dut(PORTLIST);
always @(negedge clk) begin
 qr=(cycle%7==6); sr=(cycle%11==10);
end
always @(posedge clk) begin
 cycle=cycle+1;
 if(cycle>12000)$fatal(1,"SCOREBOARD watchdog");
 if(rstn)begin
 if(old_qstall && (!qv || qt!==old_q))$fatal(1,"SCOREBOARD request unstable");
 if(old_sstall && (!sv || st!==old_s))$fatal(1,"SCOREBOARD response unstable");
 old_qstall=qv&&!qr;old_sstall=sv&&!sr;old_q=qt;old_s=st;
 if(qv&&qr)begin
 if(qc>=NREQ || qt!==expected_q[qc])$fatal(1,"SCOREBOARD req index=%0d actual=%h expected=%h",qc,qt,expected_q[qc]);qc=qc+1;
 end
 if(sv&&sr)begin
 if(sc>=NRSP || st!==expected_s[sc])$fatal(1,"SCOREBOARD rsp index=%0d actual=%h expected=%h",sc,st,expected_s[sc]);sc=sc+1;
 end
 if(iv&&ir)begin cap=cap+1;accepted={releases,classes,msg,flit};#1;
 if(dut.r_record!==accepted)$fatal(1,"SCOREBOARD incomplete record capture");end
 end else begin old_qstall=0;old_sstall=0;end
end
task send;input [511:0] d;input [5:0] c;input [1:0] m,p;input [79:0] rel;
begin
 @(negedge clk);iv=1;flit=d;classes=c;msg=m;port=p;releases=rel;waited=0;
 @(posedge clk);while(!ir)begin waited=waited+1;if(waited>2000)$fatal(1,"SCOREBOARD input blocked");@(posedge clk);end
 @(negedge clk);iv=0;flit=~d;classes=~c;msg=~m;releases=~rel;
end endtask
initial begin
'''.replace('PORTLIST',PORTS).replace('NREQ',str(len(rq))).replace('NRSP',str(len(rs)))
    for i,v in enumerate(rq):text+=f"expected_q[{i}]=115'h{v:x};\n"
    for i,v in enumerate(rs):text+=f"expected_s[{i}]=545'h{v:x};\n"
    text+='repeat(3)@(negedge clk);rstn=1;\n'
    for i,r in enumerate(records):
        text+=f"send(512'h{r['flit']:0128x},6'd{r['classes']},2'd{r['msg']},2'd{r['port']},80'h{(i+1)*0x123456789abcdef:020x});\n"
    if case.get('reset_partial'):
        text+='repeat(30)@(negedge clk);rstn=0;repeat(3)@(negedge clk);rstn=1;\n'
        # After reset an old continuation is an orphan; must not produce stale completion.
        r=rec(0,half(9),(0,1))
        text+=f"send(512'h{r['flit']:0128x},6'd8,2'd0,2'd2,80'd0);\n"
    expected_error=case['error'] or case.get('reset_partial',False)
    text+=f'''repeat(200)@(negedge clk);
if(error!==1'b{int(expected_error)} || qc!={len(rq)} || sc!={len(rs)} || cap!={len(records)+int(case.get('reset_partial',False))})
$fatal(1,"SCOREBOARD final error=%b req=%0d rsp=%0d capture=%0d",error,qc,sc,cap);
'''
    if expected_error:text+='if(ir||qv||sv)$fatal(1,"SCOREBOARD failstop outputs");\n'
    text+=f'$display("PASS receiver {case["name"]} records=%0d req=%0d rsp=%0d",cap,qc,sc);$finish;end\nendmodule\n'
    return text


def assembler_tb():
    code = r"""`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rstn=0,hv=0,dv=0;wire hr,dr,sv,error;reg sr=0;
reg [10:0] tag=0;reg [255:0] data=0;wire [1:0] port,off,beats;wire [10:0] otag;
wire [9:0] dst;wire [3:0] status;wire last,de;wire [511:0] outdata;
wire [544:0] actual={port,otag,dst,status,off,last,beats,outdata,de};
reg [544:0] expected[0:23];integer n=0,cycle=0,captured=0;reg stalled=0;reg [544:0] previous;
endpoint_response_assembler dut(.i_clk(clk),.i_rstn(rstn),.i_header_valid(hv),.o_header_ready(hr),
.i_header_port(2'd2),.i_header_tag(tag),.i_header_dst(10'd1),.i_header_status(4'd0),
.i_header_offset(2'd0),.i_header_last(1'b1),.i_header_num_beats(2'd0),
.i_data_valid(dv),.o_data_ready(dr),.i_data_port(2'd2),.i_data(data),
.o_response_valid(sv),.i_response_ready(sr),.o_response_port(port),.o_response_tag(otag),
.o_response_dst(dst),.o_response_status(status),.o_response_offset(off),.o_response_last(last),
.o_response_num_beats(beats),.o_response_data(outdata),.o_response_data_error(de),.o_error(error));
always @(negedge clk)sr=(cycle%13==12);
always @(posedge clk)begin
 cycle=cycle+1;if(cycle>10000)$fatal(1,"SCOREBOARD assembler watchdog");
 if(rstn)begin
 if(hv&&hr)captured=captured+1;
 if(stalled&&(!sv||actual!==previous))$fatal(1,"SCOREBOARD assembler unstable");
 stalled=sv&&!sr;previous=actual;
 if(sv&&sr)begin if(n>=24||actual!==expected[n])$fatal(1,"SCOREBOARD assembler order %0d",n);n=n+1;end
 end else stalled=0;
end
task header;input [10:0] t;begin @(negedge clk);tag=t;hv=1;@(posedge clk);while(!hr)@(posedge clk);@(negedge clk);hv=0;end endtask
task datum;input [255:0] d;begin @(negedge clk);data=d;dv=1;@(posedge clk);while(!dr)@(posedge clk);@(negedge clk);dv=0;end endtask
initial begin
"""
    for batch in range(3):
        for i in range(8):
            index=batch*8+i
            value=rsp_tuple(2000+index,half(index*2)|(half(index*2+1)<<256))
            code+=f"expected[{index}]=545'h{value:x};\n"
    code+='repeat(3)@(negedge clk);rstn=1;\n'
    for batch in range(3):
        for i in range(8):code+=f"header(11'd{2000+batch*8+i});\n"
        code+='@(negedge clk);hv=1;tag=2047;repeat(8)begin @(negedge clk);if(hr||error)$fatal(1,"SCOREBOARD assembler full is backpressure");end hv=0;\n'
        for i in range(16):code+=f"datum(256'h{half(batch*16+i):064x});\n"
    code+='repeat(200)@(negedge clk);if(n!=24||captured!=24||error)$fatal(1,"SCOREBOARD assembler counts");\n'
    code+='dv=1;data=0;repeat(3)@(negedge clk);dv=0;if(!error||dr||hr||sv)$fatal(1,"SCOREBOARD assembler orphan not blocked");\n'
    code+='$display("PASS receiver assembler_capacity results=%0d headers=%0d",n,captured);$finish;end endmodule\n'
    return code


def execute(command, cwd):
    result=subprocess.run(command,cwd=cwd,text=True,capture_output=True,timeout=60)
    return dict(command=command,returncode=result.returncode,output=result.stdout+result.stderr)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',required=True);parser.add_argument('--faults',action='store_true')
    parser.add_argument('--shell-baseline',action='store_true');args=parser.parse_args()
    if not args.label or Path(args.label).name!=args.label:parser.error('label must be one path component')
    stage=ROOT/'build/verification/endpoint_transaction'/args.label;stage.mkdir(parents=True,exist_ok=False)
    tools={x:shutil.which(x) for x in ('iverilog','vvp')}
    if not all(tools.values()):raise SystemExit('iverilog/vvp required')
    sources={Path(f).name:(ROOT/f).read_text() for f in FILES};allcases=[]
    suite=vectors();(stage/'vectors.json').write_text(json.dumps(suite,indent=2)+'\n')
    if args.shell_baseline:
        for module in ('endpoint_receive_transactions','endpoint_response_assembler'):
            folder=stage/module;folder.mkdir();(folder/(module+'.v')).write_text(sources[module+'.v'])
            bench=f'''module tb;wire ready,valid,error,implemented;wire[511:0]data;
{module} dut(.i_clk(1'b0),.i_rstn(1'b1),.i_enable(1'b1),.i_valid(1'b1),.i_data(512'd1),.i_meta(128'd0),.o_ready(ready),.o_valid(valid),.o_data(data),.o_implemented(implemented),.o_error(error));
initial begin #1;if(!ready||!implemented)$fatal(1,"SHELL_CAPABILITY missing receiver/assembler ready=%b implemented=%b",ready,implemented);$finish;end endmodule'''
            (folder/'tb.sv').write_text(bench)
            compile=execute([tools['iverilog'],'-g2012','-s','tb','-o','sim','tb.sv',module+'.v'],folder)
            sim=execute([tools['vvp'],'sim'],folder) if compile['returncode']==0 else dict(returncode=-1,output='not run')
            passed=compile['returncode']==0 and sim['returncode']!=0 and 'SHELL_CAPABILITY' in sim['output']
            allcases.append(dict(name=module,compile=compile,simulation=sim,passed=passed,expected_failure=True))
    else:
        jobs=[(case['name'],case,None) for case in suite]+[('assembler_capacity',None,None)]
        if args.faults:
            jobs += [(name,suite[0],mutation) for name,mutation in [
                ('fault_half_swap',('endpoint_response_assembler.v','{i_data, r_first}','{r_first, i_data}')),
                ('fault_tag_bit',('endpoint_receive_transactions.v','field128[113:103]','{1\'b0,field128[112:103]}')),
                ('fault_header_order',('endpoint_response_assembler.v','headers[r_head]',"headers[(r_count>4'd1)?(r_head+3'd1):r_head]")),
                ('fault_poison_skip',('endpoint_receive_transactions.v',"3'd2,3'd5,3'd6,3'd7: bad=1'b1;","3'd5:begin end 3'd2,3'd6,3'd7: bad=1'b1;"))]]
            jobs[-1]=('fault_poison_skip',next(c for c in suite if c['name']=='poison_pair'),jobs[-1][2])
        for name,case,mutation in jobs:
            folder=stage/name;folder.mkdir();copies=dict(sources)
            if mutation:
                fname,before,after=mutation
                if copies[fname].count(before)!=1:raise RuntimeError('mutation anchor must be unique '+name)
                copies[fname]=copies[fname].replace(before,after)
            for fname,content in copies.items():(folder/fname).write_text(content)
            (folder/'tb.sv').write_text(assembler_tb() if case is None else tb(case))
            compile=execute([tools['iverilog'],'-g2012','-Wall','-s','tb','-o','sim','tb.sv',*copies],folder)
            sim=execute([tools['vvp'],'sim'],folder) if compile['returncode']==0 else dict(returncode=-1,output='not run')
            failure_marker={'fault_half_swap':'SCOREBOARD rsp','fault_tag_bit':'SCOREBOARD req',
                            'fault_header_order':'SCOREBOARD rsp','fault_poison_skip':'SCOREBOARD final'}
            passed=compile['returncode']==0 and ((sim['returncode']!=0 and failure_marker[name] in sim['output']) if mutation else (sim['returncode']==0 and 'PASS receiver' in sim['output']))
            allcases.append(dict(name=name,compile=compile,simulation=sim,passed=passed,expected_failure=bool(mutation)))
    for c in allcases:
        (stage/c['name']/'result.json').write_text(json.dumps(c,indent=2)+'\n')
    report=dict(scope='receiver+ordered response assembler; no causal memory transaction claim',cases=allcases,passed=all(c['passed'] for c in allcases),
                source_sha256={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in FILES+['verification/endpoint_transaction/run_receiver.py']},
                tools={x:execute([path,'-V'],stage) for x,path in tools.items()})
    report['artifact_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(stage.rglob('*')) if f.is_file()}
    (stage/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(passed=report['passed'],cases=[(c['name'],c['passed']) for c in allcases],evidence=str(stage/'result.json')),indent=2))
    return 0 if report['passed'] else 1


if __name__=='__main__':raise SystemExit(main())
