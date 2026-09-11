`timescale 1ns/1ps
module tb;
parameter PORTS=4,DATA_WIDTH=544;
reg rstn;reg [PORTS-1:0] valid,last,ready;
reg [PORTS*DATA_WIDTH-1:0] data;
reg [PORTS*PORTS-1:0] route,select;
wire [PORTS-1:0] ir,ov,ol;wire [PORTS*DATA_WIDTH-1:0] od;wire error;
reg [PORTS-1:0] er,ev,el;reg [PORTS*DATA_WIDTH-1:0] ed;reg ee;
integer fd,n,checks=0;
switch_fabric #(.PORTS(PORTS),.DATA_WIDTH(DATA_WIDTH)) dut(
 .i_rstn(rstn),.i_valid(valid),.i_data(data),.i_last(last),.i_route_match(route),.i_select(select),.i_ready(ready),
 .o_ready(ir),.o_valid(ov),.o_data(od),.o_last(ol),.o_error(error));
initial begin
 fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"FABRIC_FIXTURE");
 while(!$feof(fd))begin
  n=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h\n",rstn,valid,data,last,route,select,ready,er,ev,ed,el,ee);
  if(n!=12)$fatal(1,"FABRIC_PARSE n=%0d",n);
  #1;
  if({ir,ov,od,ol,error}!=={er,ev,ed,el,ee})$fatal(1,"FABRIC_MISMATCH ports=%0d width=%0d row=%0d select=%h route=%h got_ready=%h expected_ready=%h got_valid=%h expected_valid=%h got_error=%b expected_error=%b got_data=%h expected_data=%h",PORTS,DATA_WIDTH,checks,select,route,ir,er,ov,ev,error,ee,od,ed);
  checks=checks+1;
 end
 $display("FABRIC_PASS ports=%0d width=%0d checks=%0d",PORTS,DATA_WIDTH,checks);$finish;
end
endmodule
