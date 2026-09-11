"""Run: python3 verification/tl_tx_prepared/run_unit.py --kd28-root PATH [--label unit] [--widths 8 16] [--replace FILE].
Uses independent two-lane preparation models and bounded actual SRAM occupancy;
wire consumption is held off to exercise full queues, source/tag capture, input
noise, invalid groups, capacity shortfall and reset of owned/queued work. Outputs
vectors, expected/actual 1064-bit preparation observations and queue counts in
build/verification/tl_tx_prepared/LABEL. Next real consuming dual-peer checks.
"""
from pathlib import Path
import argparse,copy,hashlib,json,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'model/tl'))
from prepared_partition import PreparedPartitioner


def pack(items):
    value=0;shift=0
    for x,bits in items:value|=int(x)<<shift;shift+=bits
    return value


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='unit');p.add_argument('--widths',type=int,nargs='+',default=[8,16],choices=range(8,17));p.add_argument('--replace',type=Path);a=p.parse_args()
    if not a.label.replace('_','').replace('-','').isalnum() or len(a.widths)!=len(set(a.widths)):p.error('invalid matrix')
    stage=ROOT/'build/verification/tl_tx_prepared'/a.label;stage.mkdir(parents=True,exist_ok=False)
    src=sorted((ROOT/'rtl/tl').glob('*.v'))+[ROOT/'rtl/upli/upli_receive_fifo.v',ROOT/'rtl/upli/upli_receive_storage.v']
    if a.replace:src=[a.replace.resolve() if x.name==a.replace.name else x for x in src]
    external=[a.kd28_root/'Library/models/kd28/sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[a.kd28_root/'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v']
    report=dict(complete=False,sources={str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in src+external},results=[])
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    for width in a.widths:
      for auth in (0,1):
       for depth in (1,3):
        folder=stage/f'w{width}_a{auth}_d{depth}';folder.mkdir();models=[PreparedPartitioner(),PreparedPartitioner()];counts=[0,0];vectors=[];expected=[];queue_expected=[];coverage=dict(captured=0,missing_tags=0,error=0,shortfall=0,reset_owned=0,reset_queued=0,held_source_noise=0)
        for cycle in range(160):
            phase=cycle//40;rst=cycle%40>=2;done=cycle%40>=3;sv=3;tv=(0 if cycle%7<2 else 3);words=[];tags=[];caps=[0 if phase==2 else 1]*20
            for lane in (0,1):
                if phase==1:word=0
                elif lane==0:
                    field=(3<<60)|(3<<57)|(1<<41)|((cycle&15)<<8);word=sum(field<<(64*j) for j in range(4))
                else:
                    field=(4<<28)|(1<<14)|((cycle&7)<<15);word=sum(field<<(32*j) for j in range(8))
                words.append(word);tags.append(sum(((lane<<48)|(cycle<<16)|j)<<(64*j) for j in range(8)))
            queue_expected.append(pack([(counts[0],2),(counts[1],2)]))
            outs=[]
            for lane,model in enumerate(models):
                if not rst:coverage['reset_owned']+=int(model.owned is not None);coverage['reset_queued']+=int(counts[lane]>0)
                if model.owned is not None and model.owned[0]!=words[lane]:coverage['held_source_noise']+=1
                probe=copy.deepcopy(model).step(words[lane],tags[lane],caps,valid=False,ready=False,done=False,reset=not rst,response=bool(lane),auth=bool(auth))
                ready=bool(rst and counts[lane]<depth and (not auth or probe['valid']))
                valid_tags=not auth or bool(tv&(1<<lane))
                out=model.step(words[lane],tags[lane],caps,valid=bool(sv&(1<<lane)) and valid_tags,ready=ready,done=done,reset=not rst,response=bool(lane),auth=bool(auth));out['source_ready']&=valid_tags;out['tag_captured']=auth and out['captured'];outs.append(out)
                for key,flag in [('captured',out['captured']),('missing_tags',rst and auth and not valid_tags),('error',out['error']),('shortfall',out['shortfall'])]:coverage[key]+=int(flag)
                counts[lane]=0 if not rst else counts[lane]+int(out['taken'])
            keys=[('source_ready',1),('captured',1),('tag_captured',1),('group_done',1),('taken',1),('error',1),('shortfall',1),('valid',1),('fields',4),('end',4),('cursor',4),('word',256),('tags',256)]
            expected.append(pack([(pack([(out[k],bits) for out in outs]),2*bits) for k,bits in keys]))
            vectors.append(pack([(rst,1),(done,1),(sv,2),(tv,2),(pack([(x,256) for x in words]),512),(pack([(x,512) for x in tags]),1024),(pack([(x,width+1) for x in caps]),20*(width+1))]))
        for name,values in [('vectors',vectors),('expected',expected),('queue_expected',queue_expected)]: (folder/(name+'.hex')).write_text('\n'.join(f'{x:x}' for x in values)+'\n')
        bits=6+512+1024+20*(width+1);tb=f'''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg [{bits-1}:0] vector=0;wire rstn,done;wire [1:0] sv,tv;wire [511:0] control;wire [1023:0] tags;wire [{20*(width+1)-1}:0] capacity;
assign {{capacity,tags,control,tv,sv,done,rstn}}=vector;
wire [1:0] sr,sc,st,gd,pt,err,shortfall;wire [3:0] hc;wire valid;wire [511:0] flit;wire [1:0] msg;
tl_tx_prepared #(.WIDTH({width}),.HEADER_DEPTH({depth}),.HEADER_COUNT_WIDTH(2),.BANK_DEPTH(1)) dut(
.i_clk(clk),.i_rstn(rstn),.i_taken(1'b0),.i_pending(7'd0),.i_auth(1'b{auth}),.i_done(done),.i_shared(1'b0),.i_available(capacity),.i_capacity(capacity),.i_request_budget(3'd7),.i_response_budget(4'd15),
.i_source_valid(sv),.i_source_control(control),.i_source_tags_valid(tv),.i_source_tags(tags),.i_data_valid(4'd0),.i_data0(512'd0),.i_data1(512'd0),.i_fc_valid(1'b0),.i_fc_flit(512'd0),.i_fc_msg(2'd0),
.o_source_ready(sr),.o_source_captured(sc),.o_source_tags_taken(st),.o_group_queued(gd),.o_partition_taken(pt),.o_prepare_error(err),.o_prepare_shortfall(shortfall),.o_header_count(hc),.o_valid(valid),.o_flit(flit),.o_msg(msg));
wire [1063:0] actual={{dut.partition_tags,dut.partition_control,dut.partition_cursor,dut.partition_end,dut.partition_fields,dut.partition_valid,shortfall,err,pt,gd,st,sc,sr}};
reg [{bits-1}:0] vectors[0:159];reg [1063:0] answers[0:159];reg [3:0] count_answers[0:159];integer index,trace;
initial begin $readmemh("{folder}/vectors.hex",vectors);$readmemh("{folder}/expected.hex",answers);$readmemh("{folder}/queue_expected.hex",count_answers);trace=$fopen("{folder}/actual.hex","w");
for(index=0;index<160;index=index+1)begin @(negedge clk);vector=vectors[index];#1;$fdisplay(trace,"%h",actual);if(actual!==answers[index])$fatal(1,"prepared integration vector %0d",index);if(rstn&&hc!==count_answers[index])$fatal(1,"actual queued ownership %0d got=%h want=%h",index,hc,count_answers[index]);@(posedge clk);#1;end
$display("PASS prepared integration width={width} auth={auth} depth={depth} vectors=160");$finish;end
endmodule
'''
        # Depth one requires one actual count bit per lane; use the exact derived width.
        if depth==1:tb=tb.replace('.HEADER_COUNT_WIDTH(2)','.HEADER_COUNT_WIDTH(1)').replace('wire [3:0] hc','wire [1:0] hc').replace('hc!==count_answers[index]','hc!=={count_answers[index][2],count_answers[index][0]}')
        (folder/'tb.sv').write_text(tb);compile_run=subprocess.run(['iverilog','-g2012','-s','tb','-o',str(folder/'sim.vvp'),*map(str,src+external),str(folder/'tb.sv')],capture_output=True,text=True);(folder/'compile.log').write_text(compile_run.stdout+compile_run.stderr);row=dict(width=width,auth=auth,depth=depth,compile_exit=compile_run.returncode,passed=False,coverage=coverage,vectors=160)
        if compile_run.returncode==0:
            run=subprocess.run(['vvp',str(folder/'sim.vvp')],capture_output=True,text=True,timeout=90);(folder/'run.log').write_text(run.stdout+run.stderr);row.update(run_exit=run.returncode,passed=run.returncode==0 and 'PASS prepared integration' in run.stdout)
        report['results'].append(row);(stage/'results.json').write_text(json.dumps(report,indent=2)+'\n');print(width,auth,depth,row['passed'],flush=True)
    report['complete']=len(report['results'])==len(a.widths)*4 and all(r['passed'] for r in report['results']);(stage/'results.json').write_text(json.dumps(report,indent=2)+'\n');return 0 if report['complete'] else 1


if __name__=='__main__':raise SystemExit(main())
