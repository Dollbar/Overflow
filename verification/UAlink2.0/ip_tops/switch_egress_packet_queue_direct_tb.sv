`timescale 1ns/1ps
module direct_tb;
reg clk=0,rstn=0,rv=0,wv=0,last=0,ready=0;
reg [3:0] units=0;
reg [7:0] rt=0,wt=0,data=0;
wire ar,wr,ov,ol,rel,busy,err,sticky,allerr;
wire [7:0] od,ot;
wire [3:0] ru,reserved,stored,complete;
always #5 clk=~clk;
switch_egress_packet_queue #(.PORTS(1),.DATA_WIDTH(8),.CAPACITIES(4'd3)) dut(
.i_clk(clk),.i_rstn(rstn),.i_reserve_valid(rv),.i_reserve_units(units),.i_reserve_token(rt),.o_reserve_ready(ar),
.i_write_valid(wv),.i_write_data(data),.i_write_last(last),.i_write_token(wt),.o_write_ready(wr),
.i_ready(ready),.o_valid(ov),.o_data(od),.o_last(ol),.o_token(ot),.o_release_valid(rel),.o_release_units(ru),
.o_reserved(reserved),.o_stored(stored),.o_completed(complete),.o_busy(busy),.o_error_now(err),.o_error_sticky(sticky),.o_error(allerr));
task check(input bit ok,input string name);if(!ok)$fatal(1,"DIRECT_QUEUE_MISMATCH %s",name);endtask
task edge_step;begin @(posedge clk);#1;@(negedge clk);end endtask
task reset_state;begin rstn=0;rv=0;wv=0;ready=0;edge_step();rstn=1;#1;check(reserved==0&&stored==0&&complete==0&&!sticky&&ar,"reset empty");end endtask
integer n;
initial begin
@(negedge clk);reset_state();
rv=1;units=0;#1;check(err&&ar,"zero reserve rejected");edge_step();check(sticky&&reserved==0,"zero reserve no charge");reset_state();
rv=1;units=4;#1;check(err,"oversize reserve rejected");edge_step();check(sticky&&reserved==0,"oversize no charge");reset_state();
wv=1;wt=8'hac;data=8'hf3;last=1;#1;check(err&&!wr,"unowned write rejected");edge_step();check(sticky&&stored==0,"unowned no write");reset_state();
rv=1;units=2;rt=8'ha5;#1;check(ar&&!err,"whole reservation");edge_step();check(reserved==2&&busy&&!ar,"token acquired once");
units=1;rt=8'h17;#1;check(!ar&&!err,"second reserve backpressure");edge_step();check(reserved==2,"busy did not charge twice");rv=0;
wv=1;wt=8'ha5;data=8'h81;last=0;#1;check(wr,"first write");edge_step();wv=0;
for(n=0;n<7;n=n+1)begin #1;check(!ov&&stored==1&&complete==0&&reserved==2,"partial packet hidden");edge_step();end
wv=1;data=8'h7e;last=1;#1;check(wr&&!rel,"last enqueue does not release");edge_step();wv=0;
for(n=0;n<7&&!ov;n=n+1)edge_step();#1;check(ov&&od==8'h81&&ot==8'ha5&&!ol&&complete==1,"complete first word");
for(n=0;n<7;n=n+1)begin edge_step();check(ov&&od==8'h81&&ot==8'ha5&&!ol&&!rel,"head stable under stall");end
ready=1;#1;check(!rel&&ru==0,"intermediate dequeue no release");edge_step();ready=0;
for(n=0;n<7&&!ov;n=n+1)edge_step();#1;check(ov&&od==8'h7e&&ot==8'ha5&&ol&&reserved==2,"last word and original token retained");
ready=1;#1;check(rel&&ru==2,"one whole packet release");edge_step();ready=0;#1;check(reserved==0&&stored==0&&complete==0&&!ov&&!rel,"all ownership retired");
$display("DIRECT_QUEUE_PASS zero/oversize/unowned/busy/partial/full/retire/reset");$finish;
end
endmodule
