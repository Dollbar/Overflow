`timescale 1ns/1ps
module tb;
parameter PORTS=4;
parameter CONFIG=1;
localparam W=37;
localparam IW=(PORTS<=2)?1:$clog2(PORTS);
reg clk=0;always #5 clk=~clk;
reg rstn=0;
reg [PORTS*10-1:0] ids=0,dst=0;
reg [PORTS-1:0] enable=0,valid=0,last=0,ready=0;
reg [PORTS*W-1:0] data=0;
wire [PORTS-1:0] source_ready,out_valid,out_last,route_error;
wire [PORTS*W-1:0] out_data;
reg wr=0,wen=0,commit=0;
reg [IW-1:0] index=0;
reg [9:0] id=0;
wire wa,ca,pending,error,quiet,fe;
integer checks=0,j,k;
ualink_switch_top #(.PORTS(PORTS),.DATA_WIDTH(W),.ROUTE_CONFIG_ENABLE(CONFIG)) dut(
.clk(clk),.rstn(rstn),.i_route_ids(ids),.i_port_enable(enable),.i_valid(valid),.o_ready(source_ready),.i_data(data),.i_dst(dst),.i_last(last),.o_valid(out_valid),.i_ready(ready),.o_data(out_data),.o_last(out_last),.o_route_error(route_error),.o_pending_features(),
.i_route_write_valid(wr),.i_route_write_index(index),.i_route_write_id(id),.i_route_write_enable(wen),.i_route_commit(commit),.o_route_write_accepted(wa),.o_route_commit_accepted(ca),.o_route_config_pending(pending),.o_route_config_error(error),.o_route_quiescent(quiet),.o_fabric_error(fe));
task ck;input condition;input integer number;begin checks=checks+1;if(condition!==1'b1)$fatal(1,"CONFIG_MISMATCH case=%0d PORTS=%0d mode=%0d valid=%h ready=%h out=%h quiet=%b ca=%b err=%b",number,PORTS,CONFIG,valid,source_ready,out_valid,quiet,ca,error);end endtask
// All drives occur after a falling edge. Checks observe settled combinational signals;
// the rising edge samples unchanged inputs, then tick returns after the next falling edge.
task tick;begin @(posedge clk);#1;@(negedge clk);#1;end endtask
task write_entry;input integer n;input [9:0] value;input en;begin index=n;id=value;wen=en;wr=1;#1;ck(wa&&!ca&&!error,100+n);tick;wr=0;#1;end endtask
task idle_commit;begin commit=1;#1;ck(quiet&&ca&&!error,200);tick;commit=0;#1;ck(!pending,201);end endtask
task packet;input integer source;input integer egress;input [9:0] target;input [W-1:0] word;begin
valid=0;last=0;ready={PORTS{1'b1}};valid[source]=1;last[source]=1;dst[source*10+:10]=target;data[source*W+:W]=word;#1;
ck(out_valid==(1<<egress)&&source_ready==(1<<source)&&out_last==(1<<egress)&&out_data[egress*W+:W]===word&&!route_error&&!fe,300+source*PORTS+egress);
tick;valid=0;last=0;#1;end endtask
// Observe every output in the first combinational interval after commit, before
// another rising edge can hide a partial multi-cycle publication.
task parallel_routes;input swapped;integer s,e;reg [PORTS*W-1:0] expected_words;begin
valid={PORTS{1'b1}};last={PORTS{1'b1}};ready={PORTS{1'b1}};expected_words=0;
for(s=0;s<PORTS;s=s+1)begin
 dst[s*10+:10]=(swapped&&PORTS==1)?10'h381:10'h280+s;
 data[s*W+:W]=37'h1a13579bd+s;
 e=swapped?((s+PORTS-1)%PORTS):s;
 expected_words[e*W+:W]=37'h1a13579bd+s;
end
#1;ck(out_valid==={PORTS{1'b1}}&&source_ready==={PORTS{1'b1}}&&out_last==={PORTS{1'b1}}&&out_data===expected_words&&!route_error&&!fe,350+swapped);
tick;valid=0;last=0;#1;
end endtask
initial begin
@(negedge clk);#1;for(j=0;j<PORTS;j=j+1)ids[j*10+:10]=10'h080+j;enable={PORTS{1'b1}};tick;rstn=1;#1;
if(!CONFIG)begin
wr=1;commit=1;wen=1;id=10'h3ff;#1;ck({wa,ca,pending,error,quiet}===5'b0,1);
for(j=0;j<PORTS;j=j+1)packet(j,(j+1)%PORTS,10'h080+(j+1)%PORTS,37'h123456789+j);
ck({wa,ca,pending,error,quiet}===5'b0,2);
end else begin
ck(quiet&&!pending&&!error,10);
// Static inputs are enabled, but configured active table starts disabled.
valid[0]=1;last[0]=1;ready={PORTS{1'b1}};dst[9:0]=10'h080;#1;ck(!out_valid&&!source_ready&&route_error[0]&&!quiet,11);tick;valid=0;
for(j=0;j<PORTS;j=j+1)write_entry(j,10'h280+j,1);
ck(pending,12);
valid[0]=1;dst[9:0]=10'h280;#1;ck(!out_valid&&!source_ready&&route_error[0],13);tick;valid=0;idle_commit;parallel_routes(0);
for(j=0;j<PORTS;j=j+1)packet(j,j,10'h280+j,37'h1fedcba98+j);
// Stage an atomic permutation; old active routes must continue forwarding.
for(j=0;j<PORTS;j=j+1)write_entry(j,PORTS==1?10'h381:10'h280+(j+1)%PORTS,1);
ck(pending,14);parallel_routes(0);
packet(0,0,10'h280,37'h100000123);
// First selected beat stalls: commit must be rejected before owner registers.
valid=1;last=0;ready=0;dst[9:0]=10'h280;data[W-1:0]=37'h1abcdef01;commit=1;#1;
ck(!quiet&&!ca&&error&&out_valid==1&&!source_ready,20);tick;
ck(!quiet&&!ca&&error,21);
// Accepted non-last retains the owner and rejects commit.
ready=1;#1;ck(!quiet&&!ca&&error&&source_ready==1,22);tick;
// An invalid bubble retains data/last/ready and never becomes quiescent.
valid=0;last=1;#1;ck(!quiet&&!ca&&error&&!out_valid&&source_ready==1&&out_last==1&&out_data[W-1:0]===37'h1abcdef01,23);tick;
ck(!quiet&&!ca&&error,24);
// Actual last handshake does not permit a simultaneous commit.
valid=1;#1;ck(!quiet&&!ca&&error&&out_valid==1&&source_ready==1,25);tick;
commit=0;valid=0;last=0;#1;ck(quiet&&pending,26);idle_commit;parallel_routes(1);
for(j=0;j<PORTS;j=j+1)packet(j,PORTS==1?0:(j+PORTS-1)%PORTS,PORTS==1?10'h381:10'h280+j,37'h1f0000000+j);
if(PORTS>1)begin
write_entry(0,10'h280+(2%PORTS),1);commit=1;#1;ck(quiet&&!ca&&error&&pending,30);tick;commit=0;
packet(0,PORTS-1,10'h280,37'h122223333);
write_entry(0,10'h281,1);idle_commit;
end
// Concurrent write+commit never changes either table.
wr=1;commit=1;index=0;id=10'h123;wen=0;#1;ck(!wa&&!ca&&error,31);tick;wr=0;commit=0;#1;ck(!pending,32);
// Reset cancels both shadow data and active routes, plus a stalled owner.
write_entry(0,10'h155,1);valid=1;last=0;ready=0;dst[9:0]=PORTS==1?10'h381:10'h281;tick;
rstn=0;#1;ck(!out_valid&&!source_ready&&!quiet&&!fe,40);tick;valid=0;rstn=1;#1;ck(quiet&&!pending,41);
valid=1;last=1;ready={PORTS{1'b1}};#1;ck(!out_valid&&!source_ready&&route_error[0],42);tick;valid=0;
end
$display("CONFIG_PASS ports=%0d mode=%0d checks=%0d",PORTS,CONFIG,checks);$finish;
end
initial begin #100000;$fatal(1,"CONFIG_TIMEOUT");end
endmodule
