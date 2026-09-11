"""Run: python3 verification/tl_control_partition/run_peers.py --kd28-root PATH
[--prepared | --integrated] [--label NAME] [--single] [--replace FILE] [--dependency-root DIR].
Outputs real dual class-source/port/SRAM/FC traces. Next independent check_evidence.py.
"""
from pathlib import Path
import argparse,hashlib,itertools,json,subprocess,sys
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'model/tl'))
from credit_context import decode_context
from control_partition import choose
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label');p.add_argument('--single',action='store_true');p.add_argument('--prepared',action='store_true',help='registered metadata source, with retirement-source ownership shim');p.add_argument('--integrated',action='store_true',help='production prepared/buffered wrapper and capture-driven source');p.add_argument('--replace',type=Path);p.add_argument('--dependency-root',type=Path);p.add_argument('--bank-depth',type=int,default=3);p.add_argument('--header-depth',type=int,default=2);a=p.parse_args();S=R/'build/verification/tl_control_partition'/(a.label or 'peers');S.mkdir(parents=True,exist_ok=False)
if a.prepared and a.integrated:p.error('--prepared and --integrated are mutually exclusive')
blocked=-1
def pack(v,b):return sum(int(x)<<(j*b) for j,x in enumerate(v))
def fixtures(auth,side,role):
    heads=[];tags=[];data=[]
    for group in range(12):
        kind=(1,3)[group%2] if role==0 else (2,4)[group%2];bits={1:128,3:64,2:64,4:32}[kind];n=256//bits;fields=[];auth_tags=[]
        for j in range(n):
            vc=(group+j)%4 if group%3==2 else group%4;pool=int(group%3==0);tag=(group*8+(j if group%3==2 else j//4))&2047;beat_offset=0 if group%3==2 else j%4;beat_last=True if group%3==2 else (j%4==3)
            if kind==1:word=(1<<124)|((0x23 if group%4 else 0x26)<<118)|(vc<<116)|(pool<<102)
            elif kind==3:word=(3<<60)|(3<<57)|(vc<<55)|(pool<<41)
            elif kind==2:word=(2<<60)|(vc<<58)|(tag<<47)|(pool<<46)|(beat_offset<<42)|(1<<37)|(int(beat_last)<<36)|((side+1)<<26)|((2-side)<<16)
            else:word=(4<<28)|(vc<<26)|(tag<<15)|(pool<<14)|((2-side)<<4)|(beat_offset<<2)|(int(beat_last)<<1)
            fields.append(word);auth_tags.append((side<<40)|(role<<32)|(group<<8)|(j+1));_,tokens,_=decode_context(word)
            for k,t in enumerate(tokens):data.append(sum(((side<<30)|(role<<29)|(group<<20)|(j<<12)|(k<<8)|b)<<(32*b) for b in range(8)))
        heads.append(pack(fields,bits));tags.append(pack(auth_tags,64))
    return heads,tags,data
src=sorted((R/'rtl/tl').glob('*.v'))+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v']
if a.dependency_root:src=[a.dependency_root/x.name if (a.dependency_root/x.name).is_file() else x for x in src]
if a.replace:src=[a.replace if x.name==a.replace.name else x for x in src]
external=[a.kd28_root/'Library/models/kd28/sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[a.kd28_root/'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v']
configs=list(itertools.product((8,16),(0,1),(0,1),(1,3)));configs=configs[:1] if a.single else configs;rows=[]
for width,auth,shared,delay in configs:
    B=S/f'w{width}_a{auth}_s{shared}_l{delay}';B.mkdir();streams=[[fixtures(auth,e,c) for c in (0,1)] for e in (0,1)];caps=[1]*20;depth=2*sum(caps);bits=20*(width+1);cw=depth.bit_length();hcw=a.header_depth.bit_length();dcw=a.bank_depth.bit_length()+1;decl=[];assigns=[];reads=[];data_cases=[];header_checks=[];limits=[];end_condition=[]
    for e in (0,1):
        for c in (0,1):
            source_heads,source_tags,d=streams[e][c];h=[];hts=[]
            for word,tags in zip(source_heads,source_tags):
                cursor=0
                while cursor<8:
                    part=choose(word,tags,([1]*15+[0]+[1]*4) if shared else caps,cursor=cursor,response=bool(c),auth=bool(auth),shared=bool(shared))
                    if not part['valid']:raise ValueError('fixture contains an individually oversized field')
                    h.append(part['word']);hts.append(part['tags']);cursor=part['end']
            nh=len(h);ns=len(source_heads);nd=len(d);suffix=f'{e}{c}'
            for name,values in [('headers',h),('data',d),('sources',source_heads),('source_tags',source_tags),('tags',hts)]: (B/f'{name}{suffix}.hex').write_text('\n'.join(f'{x:064x}' for x in values)+'\n')
            decl.append(f'reg [255:0] headers{suffix}[0:{nh-1}],data{suffix}[0:{nd-1}],sources{suffix}[0:{ns-1}],tags{suffix}[0:{nh-1}];reg [511:0] source_tags{suffix}[0:{ns-1}];')
            assigns.append(f'assign shd[{e}][{c*256}+:256]=wh[{e}][{c}]<{ns}?sources{suffix}[wh[{e}][{c}]]:0;assign shv[{e}][{c}]=done[{e}]&&peer_done[{e}]&&(wh[{e}][{c}]<{ns})&&(cycle>=next_h[{e}][{c}]);\nassign dv[{e}][{c*2}+:2]=(cycle<next_d[{e}][{c}])?2\'d0:((wd[{e}][{c}]+1<{nd})&&(wd[{e}][{c}]%7!=1))?2\'d2:(wd[{e}][{c}]<{nd})?2\'d1:2\'d0;\nassign d0[{e}][{c*256}+:256]=wd[{e}][{c}]<{nd}?data{suffix}[wd[{e}][{c}]]:0;assign d1[{e}][{c*256}+:256]=wd[{e}][{c}]+1<{nd}?data{suffix}[wd[{e}][{c}]+1]:0;')
            assigns.append(f'assign source_auth[{e}][{c*512}+:512]=wh[{e}][{c}]<{ns}?source_tags{suffix}[wh[{e}][{c}]]:0;assign tags_valid[{e}][{c}]=1\'b1;')
            if auth:header_checks.append(f'if(ht[{e}][{c}]&&tx[{e}][511:256]!==tags{suffix}[hi[{e}][{c}]])$fatal(1,"stored partition tags not paired with header");')
            for name in ('headers','data','sources','source_tags','tags'):reads.append(f'$readmemh("{B}/{name}{suffix}.hex",{name}{suffix});')
            data_cases.append(f'{e*2+c}:expected_data=data{suffix}[di[e][owner]+expected_count[owner]];')
            header_checks.append(f'if(ht[{e}][{c}]&&(hi[{e}][{c}]>={nh}||tx[{e}][255:0]!==headers{suffix}[hi[{e}][{c}]]))$fatal(1,"actual header order/class");')
            limits.append(f'if(hi[{e}][{c}]>{nh}||di[{e}][{c}]>{nd})$fatal(1,"class source over-consumed");')
            if c==blocked:end_condition.extend([f'hi[{e}][{c}]==0',f'di[{e}][{c}]==0',f'shortfall[{e}][{c}]'])
            else:end_condition.extend([f'hi[{e}][{c}]=={nh}',f'di[{e}][{c}]=={nd}',f'wh[{e}][{c}]=={ns}'])
    end_condition+=['count[0]==0','count[1]==0','pending[0]==0','pending[1]==0','publish_pending[0]==0','publish_pending[1]==0','!fv[0]','!fv[1]','available[0]==capacity[0]','available[1]==capacity[1]']
    tb=f'''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rstn=0,start=0;integer cycle=0,e,c,j,h,owner,stored=0,fc_total=0,cross_tail=0;integer expected_count[0:1];reg [255:0] expected_data;
{chr(10).join(decl)}
integer hi[0:1][0:1],di[0:1][0:1],eh[0:1][0:1],wh[0:1][0:1],wd[0:1][0:1],next_h[0:1][0:1],next_d[0:1][0:1];integer hwait=0,dwait=0;
wire [511:0] shd[0:1];wire [1023:0] source_auth[0:1];wire [1:0] shv[0:1],hs[0:1],ph[0:1],partition_error[0:1],partition_shortfall[0:1];wire [7:0] cursor[0:1],partition_end[0:1],partition_fields[0:1];wire [3:0] da[0:1];wire [1:0] hr[0:1],dr[0:1],input_error[0:1];wire [{2*hcw-1}:0] hcount[0:1];wire [{2*dcw-1}:0] dcount[0:1];
wire [511:0] tags_in[0:1];wire [1:0] tags_valid[0:1];wire [511:0] hd[0:1],d0[0:1],d1[0:1];wire [1:0] hv[0:1],ht[0:1],tt[0:1],shortfall[0:1],head_error[0:1];wire [3:0] dv[0:1],dt[0:1];
wire [511:0] tx[0:1],rx[0:1],fc[0:1],read_flit[0:1];wire [1:0] tm[0:1],rm[0:1],fm[0:1],read_msg[0:1];wire [5:0] txclasses[0:1];wire [437:0] metadata[0:1];wire [79:0] demands[0:1];
wire pv[0:1],taken[0:1],fct[0:1],fv[0:1],ft[0:1],done[0:1],peer_done[0:1],peer_shared[0:1],portfatal[0:1],fatal[0:1],rxv[0:1],rxt[0:1],prxt[0:1],ret[0:1],release_taken[0:1],read_valid[0:1],read_ready[0:1];
wire [6:0] pending[0:1];wire [{cw-1}:0] count[0:1];wire [89:0] txstate[0:1];wire [79:0] releases[0:1];wire [5:0] classes[0:1];wire [{bits-1}:0] available[0:1],capacity[0:1],publish_pending[0:1];
reg [511:0] link[0:1][0:{delay-1}];reg [1:0] message[0:1][0:{delay-1}];reg lv[0:1][0:{delay-1}];reg stalled[0:1];reg [511:0] held_flit[0:1];reg [1:0] held_msg[0:1];
{chr(10).join(assigns)}
genvar side,lane;generate for(side=0;side<2;side=side+1)begin:ends
 for(lane=0;lane<2;lane=lane+1)begin:partition
 tl_control_partition #(.WIDTH({width})) splitter(.i_clk(clk),.i_rstn(rstn),.i_source_valid(shv[side][lane]),.i_ready(hr[side][lane]),.i_done(peer_done[side]),.i_response(lane==1),.i_auth(1'b{auth}),.i_shared(peer_shared[side]),.i_source_control(shd[side][lane*256+:256]),.i_source_tags(source_auth[side][lane*512+:512]),.i_capacity(capacity[side]),.o_valid(hv[side][lane]),.o_taken(ph[side][lane]),.o_source_taken(hs[side][lane]),.o_error(partition_error[side][lane]),.o_shortfall(partition_shortfall[side][lane]),.o_control(hd[side][lane*256+:256]),.o_tags(tags_in[side][lane*256+:256]),.o_cursor(cursor[side][lane*4+:4]),.o_end(partition_end[side][lane*4+:4]),.o_fields(partition_fields[side][lane*4+:4]));
 end

 assign rx[side]=link[side][{delay-1}];assign rm[side]=message[side][{delay-1}];assign rxv[side]=lv[side][{delay-1}];assign read_ready[side]=cycle>100&&(cycle%5!=side+1);
 tl_tx_buffered #(.WIDTH({width}),.HEADER_DEPTH({a.header_depth}),.BANK_DEPTH({a.bank_depth})) scheduler(.i_clk(clk),.i_rstn(rstn),.i_taken(taken[side]),.i_pending(pending[side]),.i_auth(1'b{auth}),.i_done(peer_done[side]),.i_shared(peer_shared[side]),.i_available(available[side]),.i_capacity(capacity[side]),.i_request_budget(txstate[side][9:7]),.i_response_budget(txstate[side][6:3]),.i_header_valid(hv[side]),.i_headers(hd[side]),.i_tags_valid(tags_valid[side]),.i_tags(tags_in[side]),.i_data_valid(dv[side]),.i_data0(d0[side]),.i_data1(d1[side]),.i_fc_valid(fv[side]),.i_fc_flit(fc[side]),.i_fc_msg(fm[side]),.o_valid(pv[side]),.o_flit(tx[side]),.o_msg(tm[side]),.o_header_taken(ht[side]),.o_tags_taken(tt[side]),.o_data_taken(dt[side]),.o_fc_taken(fct[side]),.o_header_error(head_error[side]),.o_capacity_shortfall(shortfall[side]),.o_data_accepted(da[side]),.o_header_ready(hr[side]),.o_data_ready(dr[side]),.o_input_error(input_error[side]),.o_header_count(hcount[side]),.o_data_count(dcount[side]));
 tl_credit_admitted_port #(.WIDTH({width})) port(.i_clk(clk),.i_rstn(rstn),.i_receive(rxv[side]),.i_send(pv[side]&&(cycle%7!=side+1)),.i_auth(1'b{auth}),.i_rx_flit(rx[side]),.i_rx_msg(rm[side]),.i_tx_flit(tx[side]),.i_tx_msg(tm[side]),.o_rx_taken(prxt[side]),.o_tx_taken(taken[side]),.o_fatal(portfatal[side]),.o_done(peer_done[side]),.o_shared(peer_shared[side]),.o_capacity(capacity[side]),.o_available(available[side]),.o_tx_pending(pending[side]),.o_tx_validation_state(txstate[side]),.o_tx_lower(txclasses[side][2:0]),.o_tx_upper(txclasses[side][5:3]),.o_metadata(metadata[side]),.o_demands(demands[side]));
 tl_receive_credit #(.WIDTH({width}),.DEPTH({depth})) storage(.i_clk(clk),.i_rstn(rstn),.i_start(start),.i_shared(1'b{shared}),.i_auth(1'b{auth}),.i_capacities({20*width}'h{pack(caps,width):x}),.i_valid(rxv[side]),.i_flit(rx[side]),.i_msg(rm[side]),.o_taken(rxt[side]),.o_fatal(fatal[side]),.i_read_ready(read_ready[side]),.o_read_valid(read_valid[side]),.o_read_flit(read_flit[side]),.o_read_msg(read_msg[side]),.o_read_classes(classes[side]),.o_read_releases(releases[side]),.o_retired(ret[side]),.i_fc_send(fct[side]),.o_fc_valid(fv[side]),.o_fc_taken(ft[side]),.o_fc_flit(fc[side]),.o_fc_msg(fm[side]),.o_done(done[side]),.o_pending(publish_pending[side]),.o_count(count[side]),.o_release_taken(release_taken[side]));
end endgenerate
integer trace,qtrace,ptrace;initial begin ptrace=$fopen("{B}/partition_trace.txt","w"); trace=$fopen("{B}/trace.txt","w");qtrace=$fopen("{B}/queue_trace.txt","w");end
always @(posedge clk)begin
 if(!rstn)begin
 for(e=0;e<2;e=e+1)begin for(c=0;c<2;c=c+1)begin hi[e][c]=0;di[e][c]=0;wh[e][c]<=0;eh[e][c]<=0;wd[e][c]<=0;next_h[e][c]<=0;next_d[e][c]<=0;end stalled[e]=0;held_flit[e]=0;held_msg[e]=0;for(j=0;j<{delay};j=j+1)begin lv[e][j]<=0;link[e][j]<=0;message[e][j]<=0;end end
 end else begin
 {chr(10).join(header_checks)}
 for(e=0;e<2;e=e+1)begin
 $fdisplay(trace,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0h %0h %0h %0h %0h %0h",cycle,e,hi[e][0],hi[e][1],di[e][0],di[e][1],pending[e],pv[e],taken[e],ht[e],dt[e],tt[e],ft[e],rxv[e],rxt[e],ret[e],count[e],tm[e],rm[e],tx[e],rx[e],{{releases[e],classes[e],read_msg[e],read_flit[e]}},available[e],capacity[e],publish_pending[e]);
 for(c=0;c<2;c=c+1)begin
 $fdisplay(qtrace,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",cycle,e,c,eh[e][c],wd[e][c],hi[e][c],di[e][c],hv[e][c],hr[e][c],dv[e][c*2+:2],dr[e][c],ht[e][c],dt[e][c*2+:2],hcount[e][c*{hcw}+:{hcw}],dcount[e][c*{dcw}+:{dcw}],da[e][c*2+:2]);
 if(hcount[e][c*{hcw}+:{hcw}]!== (eh[e][c]-hi[e][c])||dcount[e][c*{dcw}+:{dcw}]!== (wd[e][c]-di[e][c]))$fatal(1,"actual Tx capacity conservation");
 if(ph[e][c])eh[e][c]<=eh[e][c]+1;
 if(hs[e][c])begin wh[e][c]<=wh[e][c]+1;next_h[e][c]<=cycle+(wh[e][c]%4);end
 if(dv[e][c*2+:2]&&dr[e][c])begin wd[e][c]<=wd[e][c]+da[e][c*2+:2];next_d[e][c]<=cycle+(wd[e][c]%5);end
 $fdisplay(ptrace,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0h %0h",cycle,e,c,wh[e][c],eh[e][c],cursor[e][c*4+:4],partition_end[e][c*4+:4],partition_fields[e][c*4+:4],shv[e][c],ph[e][c],hs[e][c],hd[e][c*256+:256],tags_in[e][c*256+:256]);
 if(partition_error[e][c]||partition_shortfall[e][c])$fatal(1,"legal source fields failed capacity partitioning");
 if(ph[e][c]!== (hv[e][c]&&hr[e][c])||hs[e][c]&&!ph[e][c])$fatal(1,"partition/source acknowledgement mismatch");
 if(hv[e][c]&&!hr[e][c])hwait=hwait+1;if(dv[e][c*2+:2]&&!dr[e][c])dwait=dwait+1;
 end
 if(input_error[e])$fatal(1,"buffered source quantity error");
 if(stalled[e]&&(!pv[e]||tx[e]!==held_flit[e]||tm[e]!==held_msg[e]))$fatal(1,"class choice changed stalled output");stalled[e]=pv[e]&&!taken[e];held_flit[e]=tx[e];held_msg[e]=tm[e];
 if(portfatal[e]||fatal[e]||head_error[e])$fatal(1,"actual port/storage/header fatal");
 if(rxv[e]&&(!rxt[e]||!prxt[e]))$fatal(1,"inflight wire rejected");
 if(ft[e]!==fct[e]||ret[e]!==release_taken[e]||ret[e]!== (read_valid[e]&&read_ready[e]))$fatal(1,"non-atomic source or retirement event");
 if((ht[e]||tt[e]||dt[e]||fct[e])&&!taken[e])$fatal(1,"source consumed before wire event");
 if(tt[e]!== (1'b{auth} ?ht[e]:2'd0))$fatal(1,"wrong tag source");
 expected_count[0]=0;expected_count[1]=0;
 if(taken[e])begin
 if(ht[e][0]!== (|demands[e][19:0])||ht[e][1]!== (|demands[e][39:20]))$fatal(1,"header acknowledgement class differs from actual CMD");
 for(h=0;h<2;h=h+1)begin
 if(txclasses[e][h*3+:3]==1||txclasses[e][h*3+:3]==2)begin
 owner=(pending[e]!=0)?(metadata[e][((h==1&&pending[e]>1)?6:0)+:5]>=15):(|demands[e][39:20]);
 case(2*e+owner)
 {chr(10).join(data_cases)}
 default:$fatal(1,"invalid source owner");endcase
 if(tx[e][h*256+:256]!==expected_data)$fatal(1,"actual Data/BE from wrong owner or index");expected_count[owner]=expected_count[owner]+1;
 end end
 if(pending[e]==1&&ht[e]&&((ht[e][1]?1:0)!=(metadata[e][4:0]>=15)))cross_tail=cross_tail+1;
 end
 if(dt[e][1:0]!==expected_count[0][1:0]||dt[e][3:2]!==expected_count[1][1:0])$fatal(1,"data acknowledgement class differs from actual tenure");
 if(ret[e])stored=stored+1;if(ft[e])fc_total=fc_total+1;
 for(c=0;c<2;c=c+1)begin hi[e][c]=hi[e][c]+ht[e][c];di[e][c]=di[e][c]+dt[e][c*2+:2];end
 lv[1-e][0]<=taken[e];link[1-e][0]<=tx[e];message[1-e][0]<=tm[e];
 for(j=1;j<{delay};j=j+1)begin lv[e][j]<=lv[e][j-1];link[e][j]<=link[e][j-1];message[e][j]<=message[e][j-1];end
 end
 {chr(10).join(limits)}
 end
end
initial begin
{chr(10).join(reads)}
repeat(3)@(negedge clk);rstn=1;start=1;@(negedge clk);start=0;
while(cycle<6000&&!({'&&'.join(end_condition)}))begin @(negedge clk);cycle=cycle+1;end
if(cycle>=6000)begin $display("STALLED Hreq=%0d/%0d Hrsp=%0d/%0d pending=%0d/%0d",hi[0][0],hi[1][0],hi[0][1],hi[1][1],pending[0],pending[1]);$fatal(1,"independent class progress timeout");end
if({int(blocked==-1 and not auth)}&&cross_tail==0)$fatal(1,"cross-class tail coverage missing");
$display("PASS actual channels width={width} auth={auth} shared={shared} delay={delay} blocked=none cycles=%0d stored=%0d fc=%0d cross_tail=%0d",cycle,stored,fc_total,cross_tail);
if(!hwait||!dwait)$fatal(1,"actual Tx backpressure coverage missing");$display("PASS Tx queues hwait=%0d dwait=%0d",hwait,dwait);$finish;
end
endmodule
'''
    if a.integrated:
        sys.path.insert(0,str(R/'verification/tl_tx_prepared'))
        from integrated_tb import integrate
        tb=integrate(tb,B,auth)
    if a.prepared:
        # Historical producer advances wh on final retirement. Claim each group once;
        # a true capture-based producer can replace without this adapter's bubble.
        tb=tb.replace('tl_control_partition #', 'tl_prepared_partition #')
        tb=tb.replace('.i_source_valid(shv[side][lane])', '.i_source_valid(shv[side][lane]&&!source_owned)')
        tb=tb.replace('.o_source_taken(hs[side][lane])', '.o_group_done(hs[side][lane]),.o_source_ready(source_ready),.o_captured(captured)')
        tb=tb.replace(' tl_prepared_partition #', " reg source_owned;wire source_ready,captured;\n always @(posedge clk)begin if(!rstn)source_owned<=0;else if(captured)source_owned<=1;else if(hs[side][lane])source_owned<=0;end\n tl_prepared_partition #")
    (B/'tb.sv').write_text(tb);c=subprocess.run(['iverilog','-g2012','-s','tb','-o',str(B/'sim.vvp'),*map(str,src+external),str(B/'tb.sv')],capture_output=True,text=True);(B/'compile.log').write_text(c.stdout+c.stderr);row=dict(width=width,auth=auth,shared=shared,delay=delay,blocked=blocked,bank_depth=a.bank_depth,header_depth=a.header_depth,tag_pattern=True,prepared=a.prepared,integrated=a.integrated,compile_exit=c.returncode,passed=False)
    if not c.returncode:
        c=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=120);(B/'run.log').write_text(c.stdout+c.stderr);row.update(run_exit=c.returncode,passed=c.returncode==0 and 'PASS actual channels' in c.stdout);print(c.stdout,flush=True)
    rows.append(row);(S/'results.json').write_text(json.dumps(dict(complete=len(rows)==len(configs) and all(x['passed'] for x in rows),results=rows,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in src+external}),indent=2)+'\n')
raise SystemExit(0 if all(x['passed'] for x in rows) else 1)
