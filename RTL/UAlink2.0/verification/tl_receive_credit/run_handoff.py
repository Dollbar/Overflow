"""Run: python3 verification/tl_receive_credit/run_handoff.py --kd28-root PATH.
Preload the local FIFO before publisher initialization to exercise real release
backpressure; this is a local interface test, not a legal wire-startup sequence.
Writes two healthy and four actual gate-bypass negatives. Next online proof.
"""
from pathlib import Path
import argparse,json,subprocess
R=Path(__file__).resolve().parents[2];p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);a=p.parse_args();S=R/'build/verification/tl_receive_credit/handoff';S.mkdir(exist_ok=False)
src=sorted((R/'rtl/tl').glob('*.v'))+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v'];root=a.kd28_root/'Library/models/kd28';ext=[root/'sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[root/'fifo/rtl/kd28_fifo_sdp_storage_map.v'];base=(R/'rtl/tl/tl_receive_credit.v').read_text();rows=[]
for width in (1,8):
    cap=sum(1<<(i*width) for i in (0,10,15));word=(1<<124)|(3<<118)|(1<<102)
    for fault in ('healthy','visible_before_credit_ready','pop_before_credit_ready'):
        B=S/f'w{width}_{fault}';B.mkdir();rtl=B/'tl_receive_credit.v';text=base
        if fault=='visible_before_credit_ready':text=text.replace('o_read_valid=storage_valid&&release_ready','o_read_valid=storage_valid')
        if fault=='pop_before_credit_ready':text=text.replace('.i_read_ready(i_read_ready&&release_ready)','.i_read_ready(i_read_ready)')
        rtl.write_text(text)
        tb=f'''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rstn=0,valid=0,start=0,send=0,ready=1;wire taken,rv,retired,release_taken,fv,done,active;wire [2:0] count;wire [{20*(width+1)-1}:0] pending;wire [511:0] data;wire [79:0] releases;integer retired_count=0,cycles=0;
tl_receive_credit #(.WIDTH({width}),.DEPTH(6)) dut(.i_clk(clk),.i_rstn(rstn),.i_start(start),.i_shared(1'b0),.i_auth(1'b0),.i_capacities({20*width}'h{cap:x}),.i_valid(valid),.i_flit(512'h{word:x}),.i_msg(2'd0),.o_taken(taken),.i_read_ready(ready),.o_read_valid(rv),.o_read_flit(data),.o_read_releases(releases),.o_retired(retired),.i_fc_send(send),.o_fc_valid(fv),.o_done(done),.o_active(active),.o_pending(pending),.o_count(count),.o_release_taken(release_taken));
always @(posedge clk)if(rstn)begin
 if(retired!==release_taken||retired!==(rv&&ready))$fatal(1,"actual handoff atomicity");
 if(!done&&(rv||retired||release_taken))$fatal(1,"consumer crossed publisher backpressure");
 if(retired)begin if(data!==512'h{word:x}||releases!==80'd1)$fatal(1,"wrong actual saved word/release");retired_count=retired_count+1;end
end
initial begin
 repeat(2)@(negedge clk);rstn=1;valid=1;#1;if(!taken)$fatal(1,"local preload was not accepted");
 @(negedge clk);valid=0;repeat(8)@(negedge clk);if(count!=1||rv||retired_count!=0)$fatal(1,"preloaded FIFO must hold for publisher");
 start=1;@(negedge clk);start=0;repeat(8)@(negedge clk);if(!fv||count!=1||rv)$fatal(1,"stalled initialization must hold consumer");
 send=1;while(retired_count==0&&cycles<100)begin @(negedge clk);cycles=cycles+1;end
 if(retired_count!=1||!done)$fatal(1,"initial completion must unlock exactly one consumption");
 ready=0;valid=1;@(negedge clk);valid=0;repeat(5)@(negedge clk);if(count!=1)$fatal(1,"second word preload for reset");
 rstn=0;@(negedge clk);rstn=1;#1;if(count!=0||active||done||fv||pending!=0||rv)$fatal(1,"reset left stored credit or data visible");
 $display("PASS actual handoff width={width} preinit_hold=16 retired=1 reset_discard=1");$finish;
end
endmodule
''';(B/'tb.v').write_text(tb);sources=[rtl if x.name==rtl.name else x for x in src];cmd=['iverilog','-g2012','-s','tb','-o',str(B/'sim.vvp'),*[str(x) for x in sources+ext],str(B/'tb.v')];c=subprocess.run(cmd,capture_output=True,text=True);(B/'compile.log').write_text(c.stdout+c.stderr);row=dict(width=width,fault=fault,compile_exit=c.returncode,passed=False)
        if c.returncode==0:
            x=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=30);log=x.stdout+x.stderr;(B/'run.log').write_text(log);row.update(run_exit=x.returncode,passed=(x.returncode==0 and 'PASS actual handoff' in log) if fault=='healthy' else (x.returncode==1 and 'FATAL:' in log and 'PASS actual handoff' not in log))
        rows.append(row);print(row,flush=True)
(S/'results.json').write_text(json.dumps(dict(complete=all(x['passed'] for x in rows),results=rows),indent=2)+'\n');raise SystemExit(0 if all(x['passed'] for x in rows) else 1)
