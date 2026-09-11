"""Run python3 verification/tl_tx_buffered/run_fifo.py --kd28-root PATH [--label NAME]
[--replace FILE] [--depth N]. Real SRAM queue scoreboard; outputs logs/results.json.
Next run buffered dual peers and independent audits. No waveform is produced.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess
R=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='fifo_cover');p.add_argument('--replace',type=Path);p.add_argument('--depth',type=int);a=p.parse_args()
S=R/'build/verification/tl_tx_buffered'/a.label;S.mkdir(parents=True,exist_ok=False)
src=[a.replace or R/'rtl/tl/tl_tx_data_fifo.v',R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v']
external=[a.kd28_root/'Library/models/kd28/sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[a.kd28_root/'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v']
rows=[]
for depth in ([a.depth] if a.depth else [1,2,3,5,129,257]):
    B=S/f'd{depth}';B.mkdir();cw=depth.bit_length();tb=f'''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rstn=0,wv=0;reg [1:0] wc=0,take=0;reg [255:0] d0=0,d1=0;wire wr,err;wire [1:0] visible,wa;wire [255:0] q0,q1;wire [{cw}:0] count;
tl_tx_data_fifo #(.BANK_DEPTH({depth})) dut(.i_clk(clk),.i_rstn(rstn),.i_write_valid(wv),.i_write_count(wc),.i_data0(d0),.i_data1(d1),.o_write_ready(wr),.o_write_taken(wa),.i_take(take),.o_valid_count(visible),.o_data0(q0),.o_data1(q1),.o_count(count),.o_error(err));
reg [255:0] expected[0:99999];integer head=0,tail=0,serial=1,cycle=0,phase,k,n,accepted=0,consumed=0,twopop=0,onepop=0,fullstall=0,invalid=0,reset_nonempty=0,streak=0,maxstreak=0;
reg [31:0] rng=32'h294febcd;reg wantready;
always @(posedge clk)begin
 if(!rstn)begin if(tail>head)reset_nonempty=reset_nonempty+1;head=0;tail=0;end
 else begin
 if(count!==(tail-head))$fatal(1,"exact total includes SRAM cached and pending");
 if(visible>2||visible>count)$fatal(1,"invalid visible occupancy");
 if(visible>0&&q0!==expected[head])$fatal(1,"head order/data");
 if(visible>1&&q1!==expected[head+1])$fatal(1,"second half order/data");
 wantready=(wc==1||wc==2)&&((tail-head)<2*{depth});
 if(wa!==((wv&&wantready)?(((wc==2)&&((tail-head)+2<=2*{depth}))?2:1):0))$fatal(1,"actual partial admission count");
 if(wr!==wantready)$fatal(1,"atomic exact bank capacity ready");
 if(err!==((wv&&(wc==0||wc==3))||(take>visible)))$fatal(1,"invalid operation diagnostic");
 if(wv&&!wr)fullstall=fullstall+1;if(err)invalid=invalid+1;
 if(take<=visible)begin
 head=head+take;consumed=consumed+take;
 if(take==2)twopop=twopop+1;if(take==1)onepop=onepop+1;
 end
 if(take==2&&visible==2)streak=streak+1;else streak=0;if(streak>maxstreak)maxstreak=streak;
 if(wv&&wr)begin expected[tail]=d0;tail=tail+1;if(wa==2)begin expected[tail]=d1;tail=tail+1;end accepted=accepted+wa;end
 end
end
initial begin
 repeat(3)@(negedge clk);rstn=1;
 // Directed odd occupancy leaves exactly one free half for a proposed pair.
 wv=1;wc=1;take=0;
 for(k=0;k<2*{depth}-1;k=k+1)begin d0=serial;serial=serial+1;@(negedge clk);end
 wc=2;d0=serial;d1=serial+1;serial=serial+2;@(negedge clk);wv=0;wc=0;
 repeat(8)@(negedge clk);
 if(visible!=2)$fatal(1,"partial input did not complete visible pair");
 take=3;@(negedge clk);take=0;@(negedge clk);
 for(k=0;k<2*{depth}+30;k=k+1)begin take=visible;@(negedge clk);end
 take=0;
 if(count)$fatal(1,"directed invalid take corrupted queue");
 for(cycle=0;cycle<9000;cycle=cycle+1)begin
 rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
 rstn=(cycle!=1000&&cycle!=1001&&cycle!=4101);phase=cycle%2000;
 wv=phase<1200;wc=(phase<650)?2:((rng[2:1]==3)?1:rng[2:1]);
 take=(phase<600)?0:(phase<1200)?visible:(rng[6:5]==3)?3:((visible==2)?2:visible);
 if(phase>=1400)begin wv=0;take=visible;end
 d0={{8{{serial[31:0]}}}};d1={{8{{(serial+1)}}}};serial=serial+2;
 @(negedge clk);
 end
 wv=0;take=visible;
 for(k=0;k<2*{depth}+30;k=k+1)begin take=visible;@(negedge clk);end
 if(count||tail!=head)$fatal(1,"bounded drain failed");
 if(!onepop||!twopop||!fullstall||!invalid||!reset_nonempty)$fatal(1,"directed coverage missing");
 if({depth}>=5&&maxstreak<20)$fatal(1,"no sustained full Flit bandwidth");
 $display("PASS FIFO depth={depth} accepted=%0d consumed=%0d onepop=%0d twopop=%0d fullstall=%0d invalid=%0d reset_nonempty=%0d maxstreak=%0d",accepted,consumed,onepop,twopop,fullstall,invalid,reset_nonempty,maxstreak);$finish;
end
endmodule
'''
    # Use explicit 32-bit payload addition: unsized expressions in concatenation are illegal.
    tb=tb.replace('{8{(serial+1)}}',"{8{(serial+32'd1)}}")
    (B/'tb.sv').write_text(tb)
    c=subprocess.run(['iverilog','-g2012','-s','tb','-o',str(B/'sim.vvp'),*map(str,src+external),str(B/'tb.sv')],capture_output=True,text=True);(B/'compile.log').write_text(c.stdout+c.stderr);row=dict(depth=depth,compile_exit=c.returncode,passed=False)
    if c.returncode==0:
        c=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=120);(B/'run.log').write_text(c.stdout+c.stderr);row.update(run_exit=c.returncode,passed=c.returncode==0 and 'PASS FIFO' in c.stdout);print(c.stdout,flush=True)
    rows.append(row)
(S/'results.json').write_text(json.dumps(dict(complete=all(x['passed'] for x in rows),results=rows,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in src+external if f.exists()}),indent=2)+'\n')
raise SystemExit(0 if all(x['passed'] for x in rows) else 1)
