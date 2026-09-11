`timescale 1ns/1ps
module tb;
 parameter PORTS=4,COUNT=1;
 reg clk=0;always #10 clk=~clk;
 reg rstn=0;reg [PORTS-1:0] valid=0,last=0,ready=0;
 reg [PORTS*PORTS-1:0] route=0;
 wire [PORTS*PORTS-1:0] selected;wire [PORTS-1:0] owned;reg [PORTS-1:0] expected_owned;
 reg [127:0] vectors[0:COUNT-1];reg [PORTS*PORTS-1:0] expected;
 integer index,e,s,ones;integer checked=0;
 switch_arbiter #(.PORTS(PORTS)) dut(.i_clk(clk),.i_rstn(rstn),.i_valid(valid),.i_route_match(route),.i_last(last),.i_ready(ready),.o_select(selected),.o_owned(owned));
 initial begin
  $readmemh("vectors.hex",vectors);
  for(index=0;index<COUNT;index=index+1)begin
   @(negedge clk);
   route=vectors[index][0+:PORTS*PORTS];valid=vectors[index][PORTS*PORTS+:PORTS];
   last=vectors[index][PORTS*PORTS+PORTS+:PORTS];ready=vectors[index][PORTS*PORTS+2*PORTS+:PORTS];
   rstn=vectors[index][PORTS*PORTS+3*PORTS];expected=vectors[index][PORTS*PORTS+3*PORTS+1+:PORTS*PORTS];
   expected_owned=vectors[index][2*PORTS*PORTS+3*PORTS+1+:PORTS];
   #1;
   if(selected!==expected)$fatal(1,"ARBITER_SELECTION row=%0d ports=%0d got=%h expected=%h",index,PORTS,selected,expected);
   if(owned!==expected_owned)$fatal(1,"ARBITER_OWNERSHIP row=%0d got=%h expected=%h",index,owned,expected_owned);
   for(e=0;e<PORTS;e=e+1)begin
    ones=0;for(s=0;s<PORTS;s=s+1)if(selected[e*PORTS+s])ones=ones+1;
    if(ones>1)$fatal(1,"ARBITER_ONEHOT row=%0d egress=%0d",index,e);
   end
   // Temporary ready inversion stays between edges: selection must be independent of downstream readiness.
   ready=~ready;#1;
   if(selected!==expected||owned!==expected_owned)$fatal(1,"ARBITER_READY_DEPENDENCE row=%0d ports=%0d",index,PORTS);
   ready=~ready;#1;
   if(selected!==expected)$fatal(1,"ARBITER_READY_RESTORE row=%0d",index);
   @(posedge clk);#1;checked=checked+1;
  end
  $display("ARBITER_PASS ports=%0d checked=%0d",PORTS,checked);$finish;
 end
 initial begin #1000000;$fatal(1,"ARBITER_TIMEOUT");end
endmodule
