`timescale 1ns/1ps
module bridge_tb;
parameter PORTS=1;
localparam CAP=4,SW=2,TW=10;
reg clk=0;always #5 clk=~clk;
reg rstn=0;reg [1:0] select_port=0,source_vc=0;reg source_pool=0;
reg req_valid=0,data_valid=0,data_space=1;reg [183:0] req_payload=0;reg [579:0] data_payload=0;reg data_pool=0;
wire req_ready,data_ready;wire [1:0] req_port,data_port;
wire request_valid,request_ready,request_pool;wire [1:0] request_port,request_vc;
wire [183:0] request_payload;wire [2047:0] request_data;wire [255:0] request_be;wire [3:0] request_poison,request_pools;
wire bridge_busy,bridge_error;
upli_endpoint_request_bridge #(.C_NUM_PORTS(PORTS)) bridge(
 .i_clk(clk),.i_rstn(rstn),.i_select_port(select_port),.o_req_consumer_port(req_port),
 .i_req_head_valid(req_valid),.i_req_consume_valid(req_valid),.i_req_payload(req_payload),.i_req_vc(source_vc),.i_req_pool(source_pool),.o_req_consumer_ready(req_ready),
 .o_data_consumer_port(data_port),.i_data_head_valid(data_valid),.i_data_consume_valid(data_valid&&data_space),.i_data_payload(data_payload),.i_data_vc(source_vc),.i_data_pool(data_pool),.o_data_consumer_ready(data_ready),
 .o_request_valid(request_valid),.i_request_ready(request_ready),.o_request_port(request_port),.o_request_vc(request_vc),.o_request_pool(request_pool),.o_request_payload(request_payload),.o_request_data(request_data),.o_request_be(request_be),.o_request_poison(request_poison),.o_request_data_pools(request_pools),.o_busy(bridge_busy),.o_error(bridge_error));
reg issue_ready=0,release_valid=0;reg [TW-1:0] release_token=0;
wire issue_valid,release_ready,error;wire [TW-1:0] allocation_token,issue_token;
wire [7:0] issue_station;wire [1:0] issue_port,issue_vc;wire issue_pool;
wire [183:0] issue_payload;wire [2047:0] issue_data;wire [255:0] issue_be;wire [3:0] issue_poison,issue_pools;wire [2:0] count;
upli_endpoint_request_context #(.CAPACITY(CAP),.C_NUM_PORTS(PORTS)) context_table(
 .i_clk(clk),.i_rstn(rstn),.i_request_valid(request_valid),.o_request_ready(request_ready),.o_request_token(allocation_token),
 .i_request_station(8'h91),.i_request_port(request_port),.i_request_vc(request_vc),.i_request_pool(request_pool),.i_request_payload(request_payload),.i_request_data(request_data),.i_request_be(request_be),.i_request_poison(request_poison),.i_request_data_pools(request_pools),
 .o_issue_valid(issue_valid),.i_issue_ready(issue_ready),.o_issue_token(issue_token),.o_issue_station(issue_station),.o_issue_port(issue_port),.o_issue_vc(issue_vc),.o_issue_pool(issue_pool),.o_issue_payload(issue_payload),.o_issue_data(issue_data),.o_issue_be(issue_be),.o_issue_poison(issue_poison),.o_issue_data_pools(issue_pools),
 .i_release_valid(release_valid),.i_release_token(release_token),.o_release_ready(release_ready),.o_error(error),.o_count(count));
reg [183:0] reqs[0:7];integer ns[0:7];reg [2047:0] datas[0:7];reg [255:0] bes[0:7];reg [3:0] poisons[0:7],pools[0:7];
integer sequence_ids[0:63],announced=0,allocated=0,issued=0,released=0;
reg [TW-1:0] tokens[0:63];reg released_ids[0:63];
integer req_heads=0,data_heads=0,checks=0,cycles=0,total_allocated=0,total_issued=0,total_released=0,stall_cycles=0;
integer idx,match_count,match_index;reg allow_error=0;
task ck(input bit good,input integer code);begin checks=checks+1;if(!good)$fatal(1,"CONTEXT_BRIDGE_MISMATCH id=%0d cycles=%0d portcount=%0d allocated=%0d issued=%0d",code,cycles,PORTS,allocated,issued);end endtask
always @(posedge clk)begin
 cycles<=cycles+1;
 if(!rstn)begin announced=0;allocated=0;issued=0;released=0;for(integer q=0;q<64;q=q+1)released_ids[q]=0;end
 else begin
  ck(!bridge_error,1);ck(!error||allow_error,2);ck(count==allocated-released,3);
  if(req_valid&&req_ready)req_heads<=req_heads+1;
  if(data_valid&&data_space&&data_ready)data_heads<=data_heads+1;
  if(request_valid&&request_ready)begin
   ck(allocated<announced,4);idx=sequence_ids[allocated];
   ck(request_payload===reqs[idx]&&request_data===datas[idx]&&request_be===bes[idx]&&request_poison===poisons[idx]&&request_pools===pools[idx],5);
   ck(request_port==idx%PORTS&&request_vc==idx%4&&request_pool==(idx/2)%2,6);
   tokens[allocated]=allocation_token;released_ids[allocated]=0;allocated=allocated+1;total_allocated=total_allocated+1;
  end
  if(issue_valid)begin
   ck(issued<allocated,7);idx=sequence_ids[issued];
   ck(issue_token===tokens[issued]&&issue_station==8'h91&&issue_port==idx%PORTS&&issue_vc==idx%4&&issue_pool==(idx/2)%2,8);
   ck(issue_payload===reqs[idx]&&issue_data===datas[idx]&&issue_be===bes[idx]&&issue_poison===poisons[idx]&&issue_pools===pools[idx],9);
   if(issue_ready)begin issued=issued+1;total_issued=total_issued+1;end else stall_cycles=stall_cycles+1;
  end
  if(release_valid&&release_ready)begin
   match_count=0;match_index=0;
   for(integer q=0;q<issued;q=q+1)if(!released_ids[q]&&tokens[q]==release_token)begin match_count=match_count+1;match_index=q;end
   ck(match_count==1,10);released_ids[match_index]=1;released=released+1;total_released=total_released+1;
  end
 end
 if(cycles>4000)$fatal(1,"CONTEXT_BRIDGE_MISMATCH timeout");
end
// Only the head BFM is synthetic. Both ownership modules above are actual RTL.
task send(input integer which);integer before_count;begin
 @(negedge clk);#1;sequence_ids[announced]=which;announced=announced+1;
 select_port=which%PORTS;source_vc=which%4;source_pool=(which/2)%2;req_payload=reqs[which];req_valid=1;before_count=req_heads;
 while(req_heads==before_count)begin @(posedge clk);#2;end
 @(negedge clk);#1;req_valid=0;
 for(integer b=0;b<ns[which];b=b+1)begin
  @(negedge clk);#1;data_payload={datas[which][b*512+:512],bes[which][b*64+:64],b[1:0],(b==ns[which]-1),poisons[which][b]};data_pool=pools[which][b];data_valid=1;before_count=data_heads;
  if(b==1)begin data_space=0;repeat(4)@(negedge clk);#1;data_space=1;end
  while(data_heads==before_count)begin @(posedge clk);#2;end
  @(negedge clk);#1;data_valid=0;
 end
end endtask
task issue_one;integer before_count;begin
 @(negedge clk);#1;before_count=issued;issue_ready=1;
 while(issued==before_count)begin @(posedge clk);#2;end
 @(negedge clk);#1;issue_ready=0;
end endtask
task retire(input integer ordinal);integer before_count;begin
 @(negedge clk);#1;release_token=tokens[ordinal];release_valid=1;before_count=released;
 while(released==before_count)begin @(posedge clk);#2;end
 @(negedge clk);#1;release_valid=0;
end endtask
task start_epoch;begin
 @(negedge clk);#1;rstn=0;req_valid=0;data_valid=0;issue_ready=0;release_valid=0;allow_error=0;
 repeat(3)@(negedge clk);#1;rstn=1;repeat(2)@(negedge clk);#1;ck(count==0&&!issue_valid&&!bridge_busy,20);
end endtask
integer fd,n;reg [4095:0] file_name;reg [TW-1:0] old_token;
initial begin
 if(!$value$plusargs("VECTORS=%s",file_name))$fatal(1,"CONTEXT_BRIDGE_MISMATCH missing fixtures");
 fd=$fopen(file_name,"r");if(!fd)$fatal(1,"CONTEXT_BRIDGE_MISMATCH open");
 for(integer q=0;q<8;q=q+1)begin n=$fscanf(fd,"%h %h %h %h %h %h\n",reqs[q],ns[q],datas[q],bes[q],poisons[q],pools[q]);ck(n==6,21);end
 start_epoch();
 for(integer q=0;q<4;q=q+1)send(q);
 wait(allocated==4);@(negedge clk);#1;
 fork send(4);join_none
 wait(request_valid&&!request_ready);repeat(17)@(negedge clk);#1;ck(count==4&&allocated==4&&bridge_busy,22);
 issue_one();repeat(5)@(negedge clk);#1;ck(count==4&&allocated==4&&issued==1,23);
 retire(0);wait(allocated==5);repeat(7)@(negedge clk);#1;ck(count==4&&bridge_busy==0,24);
 for(integer q=0;q<4;q=q+1)issue_one();
 retire(4);retire(2);retire(1);retire(3);repeat(3)@(negedge clk);#1;ck(count==0,25);
 old_token=tokens[0];send(0);wait(allocated==6);issue_one();
 @(negedge clk);#1;release_valid=1;release_token=old_token;allow_error=1;#1;ck(error&&!release_ready,26);
 @(negedge clk);#1;release_valid=0;allow_error=0;retire(5);
 send(2);send(3);wait(allocated==8);issue_one();repeat(7)@(negedge clk);#1;ck(count==2&&issued==7,27);
 start_epoch();send(0);wait(allocated==1);issue_one();retire(0);repeat(3)@(negedge clk);#1;ck(count==0,28);
 $display("CONTEXT_BRIDGE_PASS ports=%0d allocated=%0d issued=%0d released=%0d req_heads=%0d data_heads=%0d stalls=%0d checks=%0d cycles=%0d",PORTS,total_allocated,total_issued,total_released,req_heads,data_heads,stall_cycles,checks,cycles);$finish;
end
endmodule
