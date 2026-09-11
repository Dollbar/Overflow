`timescale 1ns/1ps
module response_collector_tb;
parameter PORTS=1;
reg clk=0;always #5 clk=~clk;
reg rstn,stop;
reg [1:0] select_valid,head_valid,consume_valid,pool,ready;
reg [3:0] select_port,vc;
reg [5:0] account;
reg [618:0] rd;
reg [100:0] wr;
wire [3:0] consumer_port,response_port,response_vc;
wire [1:0] response_valid,consumer_ready,response_pool,retired,errors;
wire [5:0] response_account;
wire [618:0] response_rd;
wire [100:0] response_wr;
wire fault;
upli_endpoint_response_collector #(.C_NUM_PORTS(PORTS)) dut(
.i_clk(clk),.i_rstn(rstn),.i_stop(stop),.i_select_valid(select_valid),.i_select_port(select_port),
.i_head_valid(head_valid),.i_consume_valid(consume_valid),.i_head_vc(vc),.i_head_pool(pool),.i_head_account(account),
.i_read_payload(rd),.i_write_payload(wr),.i_retire_ready(ready),
.o_consumer_port(consumer_port),.o_consumer_ready(consumer_ready),.o_response_valid(response_valid),.o_response_port(response_port),
.o_response_vc(response_vc),.o_response_pool(response_pool),.o_response_account(response_account),.o_read_payload(response_rd),.o_write_payload(response_wr),
.o_retired(retired),.o_metadata_error(errors),.o_fault_stop_request(fault));
integer fd,rc,rows,n;
reg [2047:0] file_name;
reg [3:0] ep,evc;
reg [1:0] evalid,etake,epool,eerr;
reg [5:0] eaccount;
reg efault;
reg [618:0] erd;
reg [100:0] ewr;
initial begin
 if(!$value$plusargs("VECTORS=%s",file_name)||!$value$plusargs("ROWS=%d",rows))$fatal(1,"args");
 fd=$fopen(file_name,"r");if(!fd)$fatal(1,"file");
 for(n=0;n<rows;n=n+1)begin
  @(negedge clk);
  rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",rstn,stop,select_valid,select_port,head_valid,consume_valid,vc,pool,account,ready,rd,wr,ep,evalid,etake,erd,ewr,evc,epool,eaccount,eerr,efault);
  if(rc!=22)$fatal(1,"parse");
  #1;
  if({consumer_port,response_port,response_valid,consumer_ready,retired,response_rd,response_wr,response_vc,response_pool,response_account,errors,fault}!=={ep,ep,evalid,etake,etake,erd,ewr,evc,epool,eaccount,eerr,efault})$fatal(1,"COLLECTOR_CHECK row=%0d ports=%0d valid=%h/%h port=%h/%h err=%h/%h",n,PORTS,response_valid,evalid,consumer_port,ep,errors,eerr);
  @(posedge clk);#1;
 end
 $display("COLLECTOR_PASS ports=%0d rows=%0d",PORTS,rows);$finish;
end
endmodule
