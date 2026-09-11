"""Run: python3 verification/tl_tx_packer/run_peers.py --kd28-root PATH [--label NAME].
Actual packer + admitted port + receive SRAM + FC publisher on both endpoints.
Outputs raw source/clock traces; next run check_evidence.py for independent auditing.
"""
from pathlib import Path
import argparse,hashlib,itertools,json,subprocess,sys
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'model/tl'))
from credit_context import decode_context
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='peers');p.add_argument('--single',action='store_true');p.add_argument('--replace',type=Path);p.add_argument('--data-credits',type=int,choices=(1,4),default=4);a=p.parse_args();S=R/'build/verification/tl_tx_packer'/a.label;S.mkdir(parents=True,exist_ok=False)
def pack(v,b):return sum(x<<(j*b) for j,x in enumerate(v))
def fixtures(auth,side):
    heads=[];data=[]
    for j in range(48):
        kind=1 if j<12 else (j+side)%5+1;lane=1 if j<12 else (j//5)%5;vc=max(0,lane-1);pool=int(lane==0);n=2 if j<12 else j%4
        if kind==1:word=(1<<124)|((0x23 if j%2 else 0x26)<<118)|(vc<<116)|(pool<<102)|n
        elif kind==2:word=(2<<60)|(vc<<58)|(pool<<46)|(n<<44)|(1<<37)
        elif kind==3:word=(3<<60)|(3<<57)|(vc<<55)|(pool<<41)|(n<<39)
        elif kind==4:word=(4<<28)|(vc<<26)|(pool<<14)
        else:word=(5<<28)|(vc<<26)|(pool<<14)|(n<<2)|2
        heads.append(word)
        _,tokens,_=decode_context(word)
        for k,t in enumerate(tokens):data.append(sum(((side<<31)|(j<<16)|(k<<8)|b)<<(32*b) for b in range(8)))
    for batch in range(8):
        word=0
        for k in range(4 if auth else 8):
            lane=k%5;word|=((5<<28)|(max(0,lane-1)<<26)|(int(lane==0)<<14))<<(32*k)
        heads.append(word)
    return heads,data
src=sorted((R/'rtl/tl').glob('*.v'))+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v']
if a.replace:src=[a.replace if q.name==a.replace.name else q for q in src]
external=[a.kd28_root/'Library/models/kd28/sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[a.kd28_root/'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v']
configs=list(itertools.product((8,16),(0,1),(0,1),(1,3)));configs=configs[:1] if a.single else configs;rows=[]
for width,auth,shared,delay in configs:
    B=S/f'w{width}_a{auth}_s{shared}_l{delay}';B.mkdir();streams=[fixtures(auth,e) for e in (0,1)];nh=[len(x[0]) for x in streams];nd=[len(x[1]) for x in streams];caps=[2]*10+[a.data_credits]*10;depth=2*sum(caps);bits=20*(width+1)
    for e,(h,d) in enumerate(streams):
        for name,values in [('headers',h),('data',d)]: (B/f'{name}{e}.hex').write_text('\n'.join(f'{x:064x}' for x in values)+'\n')
    tb=f'''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rstn=0,start=0;integer cycle=0,e,j,coalesced=0,fc_tail=0,tail_only=0,stored=0,fc_total=0;
reg [255:0] headers0[0:{nh[0]-1}],headers1[0:{nh[1]-1}],data0[0:{nd[0]-1}],data1[0:{nd[1]-1}];
integer hi[0:1],di[0:1];reg [255:0] head[0:1],d0[0:1],d1[0:1];wire [1:0] dv[0:1];
wire [511:0] tx[0:1],rx[0:1],fc[0:1],read_flit[0:1];wire [1:0] tm[0:1],rm[0:1],fm[0:1],read_msg[0:1],dt[0:1];
wire peer_shared[0:1],shortfall[0:1];reg stalled[0:1];reg [511:0] held_flit[0:1];reg [1:0] held_msg[0:1];
wire pv[0:1],taken[0:1],hv[0:1],ht[0:1],tt[0:1],fct[0:1],fv[0:1],ft[0:1],done[0:1],peer_done[0:1],portfatal[0:1],fatal[0:1],rxv[0:1],rxt[0:1],prxt[0:1],ret[0:1],release_taken[0:1],read_valid[0:1],read_ready[0:1];
wire [6:0] pending[0:1],count[0:1];wire [89:0] txstate[0:1];wire [79:0] releases[0:1];wire [5:0] classes[0:1];wire [{bits-1}:0] available[0:1],capacity[0:1],publish_pending[0:1];
reg [511:0] link[0:1][0:{delay-1}];reg [1:0] message[0:1][0:{delay-1}];reg lv[0:1][0:{delay-1}];
always @* begin
head[0]=hi[0]<{nh[0]}?headers0[hi[0]]:0;head[1]=hi[1]<{nh[1]}?headers1[hi[1]]:0;
d0[0]=di[0]<{nd[0]}?data0[di[0]]:0;d1[0]=di[0]+1<{nd[0]}?data0[di[0]+1]:0;
d0[1]=di[1]<{nd[1]}?data1[di[1]]:0;d1[1]=di[1]+1<{nd[1]}?data1[di[1]+1]:0;
end
genvar side;generate for(side=0;side<2;side=side+1)begin:ends
 assign hv[side]=done[side]&&peer_done[side]&&(side==0?hi[0]<{nh[0]}:hi[1]<{nh[1]});
 assign dv[side]=(side==0?di[0]+1<{nd[0]}:di[1]+1<{nd[1]})?2'd2:(side==0?di[0]<{nd[0]}:di[1]<{nd[1]})?2'd1:2'd0;
 assign rx[side]=link[side][{delay-1}];assign rm[side]=message[side][{delay-1}];assign rxv[side]=lv[side][{delay-1}];
 assign read_ready[side]=cycle>100&&(cycle%5!=side+1);
 tl_tx_packer #(.WIDTH({width})) packer(.i_clk(clk),.i_rstn(rstn),.i_taken(taken[side]),.i_pending(pending[side]),.i_auth(1'b{auth}),.i_done(peer_done[side]),.i_shared(peer_shared[side]),.i_available(available[side]),.i_capacity(capacity[side]),.i_request_budget(txstate[side][9:7]),.i_response_budget(txstate[side][6:3]),.i_header_valid(hv[side]),.i_header(head[side]),.i_tags_valid(1'b1),.i_tags(256'd0),.i_data_valid(dv[side]),.i_data0(d0[side]),.i_data1(d1[side]),.i_fc_valid(fv[side]),.i_fc_flit(fc[side]),.i_fc_msg(fm[side]),.o_valid(pv[side]),.o_flit(tx[side]),.o_msg(tm[side]),.o_header_taken(ht[side]),.o_tags_taken(tt[side]),.o_data_taken(dt[side]),.o_fc_taken(fct[side]),.o_header_wait(),.o_capacity_shortfall(shortfall[side]));
 tl_credit_admitted_port #(.WIDTH({width})) port(.i_clk(clk),.i_rstn(rstn),.i_receive(rxv[side]),.i_send(pv[side]&&(cycle%7!=side+1)),.i_auth(1'b{auth}),.i_rx_flit(rx[side]),.i_rx_msg(rm[side]),.i_tx_flit(tx[side]),.i_tx_msg(tm[side]),.o_rx_taken(prxt[side]),.o_tx_taken(taken[side]),.o_fatal(portfatal[side]),.o_done(peer_done[side]),.o_shared(peer_shared[side]),.o_capacity(capacity[side]),.o_available(available[side]),.o_tx_pending(pending[side]),.o_tx_validation_state(txstate[side]));
 tl_receive_credit #(.WIDTH({width}),.DEPTH({depth})) storage(.i_clk(clk),.i_rstn(rstn),.i_start(start),.i_shared(1'b{shared}),.i_auth(1'b{auth}),.i_capacities({20*width}'h{pack(caps,width):x}),.i_valid(rxv[side]),.i_flit(rx[side]),.i_msg(rm[side]),.o_taken(rxt[side]),.o_fatal(fatal[side]),.i_read_ready(read_ready[side]),.o_read_valid(read_valid[side]),.o_read_flit(read_flit[side]),.o_read_msg(read_msg[side]),.o_read_classes(classes[side]),.o_read_releases(releases[side]),.o_retired(ret[side]),.i_fc_send(fct[side]),.o_fc_valid(fv[side]),.o_fc_taken(ft[side]),.o_fc_flit(fc[side]),.o_fc_msg(fm[side]),.o_done(done[side]),.o_pending(publish_pending[side]),.o_count(count[side]),.o_release_taken(release_taken[side]));
end endgenerate
integer trace;initial trace=$fopen("{B}/trace.txt","w");
always @(posedge clk)begin
 if(!rstn)begin
 for(e=0;e<2;e=e+1)begin hi[e]=0;di[e]=0;stalled[e]=0;held_flit[e]=0;held_msg[e]=0;for(j=0;j<{delay};j=j+1)begin lv[e][j]<=0;link[e][j]<=0;message[e][j]<=0;end end
 end else begin
 for(e=0;e<2;e=e+1)begin
 $fdisplay(trace,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0h %0h %0h %0h %0h %0h",cycle,e,hi[e],di[e],pending[e],pv[e],taken[e],ht[e],dt[e],tt[e],ft[e],rxv[e],rxt[e],ret[e],count[e],tm[e],rm[e],tx[e],rx[e],{{releases[e],classes[e],read_msg[e],read_flit[e]}},available[e],capacity[e],publish_pending[e]);
 if(stalled[e]&&(!pv[e]||tx[e]!==held_flit[e]||tm[e]!==held_msg[e]))$fatal(1,"candidate changed while stalled");
 stalled[e]=pv[e]&&!taken[e];held_flit[e]=tx[e];held_msg[e]=tm[e];
 if(portfatal[e]||fatal[e])$fatal(1,"actual port/storage fatal");
 if(rxv[e]&&(!rxt[e]||!prxt[e]))$fatal(1,"inflight wire flit rejected");
 if(ft[e]!==fct[e]||ret[e]!==release_taken[e]||ret[e]!== (read_valid[e]&&read_ready[e]))$fatal(1,"non-atomic source or retirement acknowledgement");
 if((ht[e]||tt[e]||dt[e]!=0||fct[e])&&!taken[e])$fatal(1,"source consumed without wire transfer");
 if(tt[e]!== (ht[e]&&1'b{auth}))$fatal(1,"AuthTags source consumption");
 if(taken[e]&&pending[e]==1)begin if(ht[e])coalesced=coalesced+1;else if(fct[e])fc_tail=fc_tail+1;else tail_only=tail_only+1;end
 if(ret[e])stored=stored+1;if(ft[e])fc_total=fc_total+1;
 hi[e]=hi[e]+ht[e];di[e]=di[e]+dt[e];
 if(hi[e]>(e==0?{nh[0]}:{nh[1]})||di[e]>(e==0?{nd[0]}:{nd[1]}))$fatal(1,"input source over-consumed");
 lv[1-e][0]<=taken[e];link[1-e][0]<=tx[e];message[1-e][0]<=tm[e];
 for(j=1;j<{delay};j=j+1)begin lv[e][j]<=lv[e][j-1];link[e][j]<=link[e][j-1];message[e][j]<=message[e][j-1];end
 end end
end
initial begin
$readmemh("{B}/headers0.hex",headers0);$readmemh("{B}/headers1.hex",headers1);$readmemh("{B}/data0.hex",data0);$readmemh("{B}/data1.hex",data1);
repeat(3)@(negedge clk);rstn=1;start=1;@(negedge clk);start=0;
while(cycle<6000&&!(hi[0]=={nh[0]}&&hi[1]=={nh[1]}&&di[0]=={nd[0]}&&di[1]=={nd[1]}&&count[0]==0&&count[1]==0&&pending[0]==0&&pending[1]==0&&publish_pending[0]==0&&publish_pending[1]==0&&!fv[0]&&!fv[1]&&available[0]==capacity[0]&&available[1]==capacity[1]))begin @(negedge clk);cycle=cycle+1;end
if(cycle>=6000)begin $display("STALLED h=%0d/%0d d=%0d/%0d tenure=%0d/%0d fifo=%0d/%0d shortfall=%0d/%0d",hi[0],hi[1],di[0],di[1],pending[0],pending[1],count[0],count[1],shortfall[0],shortfall[1]);$fatal(1,"packer actual dual liveness timeout");end
$display("PASS actual packer width={width} auth={auth} shared={shared} delay={delay} cycles=%0d stored=%0d fc=%0d coalesced=%0d fc_tail=%0d tail_only=%0d",cycle,stored,fc_total,coalesced,fc_tail,tail_only);$finish;
end
endmodule
'''
    (B/'tb.sv').write_text(tb);c=subprocess.run(['iverilog','-g2012','-s','tb','-o',str(B/'sim.vvp'),*map(str,src+external),str(B/'tb.sv')],capture_output=True,text=True);(B/'compile.log').write_text(c.stdout+c.stderr);row=dict(width=width,auth=auth,shared=shared,delay=delay,data_credits=a.data_credits,compile_exit=c.returncode,passed=False)
    if not c.returncode:
        c=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=120);(B/'run.log').write_text(c.stdout+c.stderr);row.update(run_exit=c.returncode,passed=c.returncode==0 and 'PASS actual packer' in c.stdout);print(c.stdout,flush=True)
    rows.append(row);(S/'results.json').write_text(json.dumps(dict(complete=len(rows)==len(configs) and all(r['passed'] for r in rows),results=rows,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in src+external}),indent=2)+'\n')
raise SystemExit(0 if all(r['passed'] for r in rows) else 1)
