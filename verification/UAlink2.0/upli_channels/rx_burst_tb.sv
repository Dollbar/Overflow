`timescale 1ns/1ps
module rx_burst_tb;
parameter PORTS=1;
reg clk=0;always #5 clk=~clk;
reg rstn,known,rv,kc,hd,dv,last;
reg [1:0] slot,rp,rvc,num,dp,dvc,off;
wire [9:0] error,sticky;
wire [PORTS-1:0] busy;
upli_native_rx_burst_monitor #(.C_NUM_PORTS(PORTS)) dut(.i_clk(clk),.i_rstn(rstn),.i_tdm_known(known),.i_tdm_port(slot),.i_req_valid(rv),.i_req_port(rp),.i_req_class_known(kc),.i_req_has_data(hd),.i_req_vc(rvc),.i_req_num_beats(num),.i_data_valid(dv),.i_data_port(dp),.i_data_vc(dvc),.i_data_offset(off),.i_data_last(last),.o_error(error),.o_error_sticky(sticky),.o_active(busy));
integer fd,rows,n,rc;
reg [2047:0] file_name;
reg [9:0] ee,es;
reg [PORTS-1:0] eb;
initial begin
 if(!$value$plusargs("VECTORS=%s",file_name)||!$value$plusargs("ROWS=%d",rows))$fatal(1,"args");
 fd=$fopen(file_name,"r");if(!fd)$fatal(1,"vectors");
 // Establish the first synchronous reset before comparing registered observations.
 rstn=0;known=0;rv=0;kc=0;hd=0;dv=0;slot=0;rp=0;rvc=0;num=0;dp=0;dvc=0;off=0;last=0;
 @(posedge clk);#1;
 for(n=0;n<rows;n=n+1)begin
  @(negedge clk);
  rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",rstn,known,slot,rv,rp,kc,hd,rvc,num,dv,dp,dvc,off,last,ee,es,eb);
  if(rc!=17)$fatal(1,"parse");
  #1;if({error,sticky,busy}!=={ee,es,eb})$fatal(1,"RX_BURST_CHECK row=%0d error=%h/%h sticky=%h/%h active=%h/%h",n,error,ee,sticky,es,busy,eb);
  @(posedge clk);#1;
 end
 $display("RX_BURST_PASS ports=%0d rows=%0d",PORTS,rows);$finish;
end
endmodule
