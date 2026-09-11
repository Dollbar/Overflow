`timescale 1ns/1ps
module tb;
parameter P=1,V=1,T=8;
reg clk=0;always #5 clk=~clk;
reg rstn=0;reg [P-1:0] auth=0,valid=0,response=0,last=0,ready=0;
reg [P*544-1:0] record=0;reg [P*T-1:0] token=0;reg [P*2-1:0] vc=0;
wire [P*1-1:0] ready_out;
wire [P*1-1:0] valid_out;
wire [P*544-1:0] record_out;
wire [P*T-1:0] token_out;
wire [P*2-1:0] vc_out;
wire [P*1-1:0] response_out;
wire [P*1-1:0] last_out;
wire [P*6-1:0] classes_out;
wire [P*7-1:0] pending_before_out;
wire [P*73-1:0] be_before_out;
wire [P*584-1:0] metadata_before_out;
wire [P*80-1:0] demands_out;
wire [P*80-1:0] releases_out;
wire [P*1-1:0] store_out;
wire [P*1-1:0] error_out;
wire [P*1-1:0] error_sticky_out;
wire [P*1-1:0] captured_out;
wire [P*1-1:0] retired_out;
localparam E=P*(1+1+544+T+2+1+1+6+7+73+584+80+80+1+1+1+1+1);
reg [E-1:0] expected;
wire [E-1:0] actual={retired_out,captured_out,error_sticky_out,error_out,store_out,releases_out,demands_out,metadata_before_out,be_before_out,pending_before_out,classes_out,last_out,response_out,vc_out,token_out,record_out,valid_out,ready_out};
switch_egress_tl_context #(.PORTS(P),.VCS(V),.TOKEN_WIDTH(T)) dut(.i_clk(clk),.i_rstn(rstn),.i_auth(auth),.i_valid(valid),.i_record(record),.i_token(token),.i_vc(vc),.i_response(response),.i_last(last),.i_ready(ready),.o_ready(ready_out),.o_valid(valid_out),.o_record(record_out),.o_token(token_out),.o_vc(vc_out),.o_response(response_out),.o_last(last_out),.o_classes(classes_out),.o_pending_before(pending_before_out),.o_be_before(be_before_out),.o_metadata_before(metadata_before_out),.o_demands(demands_out),.o_releases(releases_out),.o_store(store_out),.o_error(error_out),.o_error_sticky(error_sticky_out),.o_captured(captured_out),.o_retired(retired_out));
integer fd,n,cycle=0;
initial begin
 fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"NO_VECTORS");
 while(!$feof(fd))begin
  @(negedge clk);n=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h\n",rstn,auth,valid,record,token,vc,response,last,ready,expected);
  if(n==10)begin #2;if(actual!==expected)$fatal(1,"CONTEXT_MISMATCH cycle=%0d actual=%h expected=%h",cycle,actual,expected);@(posedge clk);#1;cycle=cycle+1;end
 end
 $display("CONTEXT_PASS cycles=%0d",cycle);$finish;
end
endmodule
