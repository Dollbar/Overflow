`timescale 1ns/1ps
module tb;
parameter integer P=4,V=4,D=544,T=8,LIMIT=2;
localparam integer N=2*V*P;
reg clk=0;always #5 clk=~clk;
reg rstn=0;reg [N-1:0] valid=0,last=0;reg [N*D-1:0] data=0;reg [N*T-1:0] token=0;reg [P-1:0] ready=0;
wire [N-1:0] qready,selected;wire [P-1:0] ov,ol,resp,owned;wire [P*D-1:0] od;wire [P*T-1:0] ot;wire [P*2-1:0] vc;
reg [N-1:0] er,es;reg [P-1:0] ev,el,eresp,eo;reg [P*D-1:0] ed;reg [P*T-1:0] et;reg [P*2-1:0] ec;
switch_egress_scheduler #(.PORTS(P),.VCS(V),.DATA_WIDTH(D),.TOKEN_WIDTH(T),.RSP_BURST_MAX(LIMIT)) dut(
.i_clk(clk),.i_rstn(rstn),.i_valid(valid),.i_data(data),.i_last(last),.i_token(token),.i_ready(ready),
.o_ready(qready),.o_valid(ov),.o_data(od),.o_last(ol),.o_token(ot),.o_vc(vc),.o_response(resp),.o_selected(selected),.o_owned(owned));
integer fd,n,cycle=0;
initial begin
fd=$fopen("vectors.txt","r");
while(!$feof(fd))begin
 @(negedge clk);n=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",rstn,valid,data,last,token,ready,er,ev,ed,el,et,ec,eresp,es,eo);
 if(n==15)begin
  #1;if({qready,ov,od,ol,ot,vc,resp,selected,owned}!=={er,ev,ed,el,et,ec,eresp,es,eo})
   $fatal(1,"SCHEDULER_MISMATCH cycle=%0d ready=%h/%h selected=%h/%h owned=%h/%h valid=%h/%h last=%h/%h vc=%h/%h response=%h/%h data=%h/%h token=%h/%h",cycle,qready,er,selected,es,owned,eo,ov,ev,ol,el,vc,ec,resp,eresp,od,ed,ot,et);
  @(posedge clk);#1;cycle=cycle+1;
 end
end
$display("SCHEDULER_PASS cycles=%0d",cycle);$finish;
end
endmodule
