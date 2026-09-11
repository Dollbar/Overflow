`timescale 1ns/1ps
module tb;
parameter integer PORTS=1,W=4;parameter [PORTS*W-1:0] CAPS=5;
reg clk=0,rstn=0;always #5 clk=~clk;
reg [PORTS-1:0] valid=0,admit=0,rv=0;reg [PORTS*PORTS-1:0] routes=0;
reg [PORTS*W-1:0] units=0,ru=0;
wire [PORTS-1:0] ready,ra,re,le;wire [PORTS*PORTS-1:0] grant;
wire [PORTS*W-1:0] gu,available,reserved;wire error;
switch_credit_reservation #(.PORTS(PORTS),.UNIT_WIDTH(W),.CAPACITIES(CAPS)) dut(.i_clk(clk),.i_rstn(rstn),.i_request_valid(valid),.i_route_match(routes),.i_request_units(units),.i_admit_ready(admit),.i_release_valid(rv),.i_release_units(ru),.o_request_ready(ready),.o_grant(grant),.o_grant_units(gu),.o_release_accepted(ra),.o_available(available),.o_reserved(reserved),.o_request_error(re),.o_release_error(le),.o_error(error));
reg [PORTS-1:0] er,era,ere,ele;reg [PORTS*PORTS-1:0] eg;reg [PORTS*W-1:0] egu,ea,ers;reg ee;
integer fd,n,cycle=0;
initial begin
@(posedge clk);#1;fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"NO_VECTORS");
while(!$feof(fd))begin @(negedge clk);#1;
n=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",valid,routes,units,admit,rv,ru,rstn,er,eg,egu,era,ea,ers,ere,ele,ee);
if(n!=16)$fatal(1,"BAD_VECTOR %0d",n);#1;cycle=cycle+1;
if({ready,grant,gu,ra,available,reserved,re,le,error}!=={er,eg,egu,era,ea,ers,ere,ele,ee})$fatal(1,"RESERVATION_MISMATCH cycle=%0d p=%0d ready=%h/%h grant=%h/%h free=%h/%h err=%h/%h",cycle,PORTS,ready,er,grant,eg,available,ea,{re,le,error},{ere,ele,ee});
end
$display("RESERVATION_PASS p=%0d cycles=%0d",PORTS,cycle);$finish;end
endmodule
