`timescale 1ns/1ps
module tb;
parameter RESET_STAGE=1, MUTANT=0, BANK_DEPTH=3;
reg clk=0;always #5 clk=~clk;
reg network_rstn=0,power_rstn=0,start=0,allow_requests=0;
integer epoch=0,cycle=0,quiet=0,held_cycles=0,e,j;
integer requested[0:1],completed[0:1],sent[0:1],captures[0:1],reads[0:1],returns[0:1],result_at[0:1];
integer all_requested=0,all_completed=0,reset_edges=0;
reg [511:0] expected_memory[0:1];
reg active[0:1][0:3];integer read_at[0:1][0:3];
reg held[0:1];reg [530:0] held_value[0:1];
wire done[0:1],peer_done[0:1],error[0:1],te[0:1],request_valid[0:1],request_ready[0:1];
wire [10:0] request_tag[0:1];wire [56:0] request_address[0:1];
wire complete_valid[0:1],complete_ready[0:1],complete_data_valid[0:1];
wire [1:0] complete_port[0:1];wire [10:0] complete_tag[0:1];wire [3:0] complete_status[0:1];wire [511:0] complete_data[0:1];
wire [7:0] origin_count[0:1],completer_count[0:1],unacked[0:1],scheduled[0:1];
wire mem_valid[0:1],mem_ready[0:1],result_ready[0:1];wire [1:0] mem_slot[0:1];wire [56:0] mem_address[0:1];
wire [5:0] mem_length[0:1];wire [7:0] mem_attr[0:1],mem_metadata[0:1];wire [1:0] mem_asi[0:1];
wire result_valid[0:1];wire [1:0] result_slot[0:1];wire [3:0] result_status[0:1];wire [511:0] result_data[0:1];
wire link_valid[0:1],link_ready[0:1],link_payload[0:1],link_replay[0:1];wire [543:0] link_data[0:1];
wire [1:0] sv,sr,ov,orr,sl,se;wire [1089:0] sd,od;
reg rv[0:1],rc[0:1];reg [543:0] rd[0:1];
wire [511:0] observed_tx[0:1];wire [1:0] observed_ht[0:1],captured[0:1];wire [7:0] request_starts[0:1];
ualink_switch_top #(.PORTS(2),.DATA_WIDTH(545)) sw(.clk(clk),.rstn(network_rstn),.i_route_ids({10'd513,10'd17}),.i_port_enable(2'b11),
.i_valid(sv),.o_ready(sr),.i_data(sd),.i_dst({10'd17,10'd513}),.i_last(2'b11),.o_valid(ov),.i_ready(orr),.o_data(od),.o_last(sl),.o_route_error(se));
genvar s;generate for(s=0;s<2;s=s+1)begin:ends
 assign request_valid[s]=network_rstn&&done[s]&&peer_done[s]&&allow_requests&&done[1-s]&&peer_done[1-s]&&requested[s]<1;
 assign request_tag[s]=11'd1024;assign request_address[s]=57'd0;
 assign complete_ready[s]=epoch==1&&allow_requests&&(cycle%7!=s+1);
 ualink_memory_vip #(.SIDE(s),.MIN_LATENCY(40)) memory_vip(
 .i_clk(clk),.i_rstn((MUTANT==1&&s==0)?power_rstn:network_rstn),.i_read_valid(mem_valid[s]),.o_read_ready(mem_ready[s]),
 .i_read_slot(mem_slot[s]),.i_read_address(mem_address[s]),.i_read_length(mem_length[s]),
 .i_read_attr(mem_attr[s]),.i_read_asi(mem_asi[s]),.i_read_metadata(mem_metadata[s]),
 .o_result_valid(result_valid[s]),.i_result_ready(result_ready[s]),.o_result_slot(result_slot[s]),
 .o_result_data(result_data[s]),.o_result_status(result_status[s]));
 // 545-bit local transport record: explicit CRC status followed by DL digital record.
 assign sv[s]=link_valid[s];assign sd[s*545+:545]={1'b1,link_data[s]};
 assign link_ready[s]=sr[s];assign orr[s]=network_rstn&&(cycle%7!=s+1);
 ualink_endpoint_top #(.TRANSACTION_MODE(1),.WIDTH(8),.HEADER_DEPTH(2),.BANK_DEPTH(BANK_DEPTH),.RX_DEPTH(40),.DL_DEPTH(3)) dut(
 .i_clk(clk),.i_rstn((MUTANT==2&&s==0)?power_rstn:network_rstn),.i_link_reset(1'b0),.i_start(start),.i_auth(1'b0),.i_shared(1'b0),.i_capacities({20{8'd1}}),
 .i_source_valid(2'd0),.i_source_control(512'd0),.i_source_tags_valid(2'd0),.i_source_tags(1024'd0),.i_data_valid(4'd0),.i_data0(512'd0),.i_data1(512'd0),.i_read_ready(1'b0),
 .i_port(2'd0),.i_local_id(s==0?10'd17:10'd513),.i_request_valid(request_valid[s]),.o_request_ready(request_ready[s]),.i_request_port(2'd0),
 .i_request_tag(request_tag[s]),.i_request_address(request_address[s]),.i_request_dst(s==0?10'd513:10'd17),.i_request_length(6'd15),.i_request_attr(8'hff),
 .o_complete_valid(complete_valid[s]),.i_complete_ready(complete_ready[s]),.o_complete_port(complete_port[s]),.o_complete_tag(complete_tag[s]),
 .o_complete_status(complete_status[s]),.o_complete_data(complete_data[s]),.o_complete_data_valid(complete_data_valid[s]),
 .o_mem_valid(mem_valid[s]),.i_mem_ready(mem_ready[s]),.o_mem_slot(mem_slot[s]),.o_mem_address(mem_address[s]),.o_mem_length(mem_length[s]),.o_mem_attr(mem_attr[s]),.o_mem_asi(mem_asi[s]),.o_mem_metadata(mem_metadata[s]),
 .i_mem_result_valid(result_valid[s]),.o_mem_result_ready(result_ready[s]),.i_mem_result_slot(result_slot[s]),.i_mem_result_data(result_data[s]),.i_mem_result_status(result_status[s]),
 .o_source_captured(captured[s]),.o_outstanding_count(origin_count[s]),.o_completer_count(completer_count[s]),.o_transaction_error(te[s]),
 .o_link_valid(link_valid[s]),.o_link_data(link_data[s]),.i_link_ready(link_ready[s]),.o_link_payload(link_payload[s]),.o_link_replay(link_replay[s]),
 .i_link_valid(rv[s]),.i_link_data(rd[s]),.i_link_crc_ok(rc[s]),.i_rx_replay_limit(8'd50),
 .o_done(done[s]),.o_peer_done(peer_done[s]),.o_error(error[s]),.o_unacked_count(unacked[s]),.o_scheduled_count(scheduled[s]));
 assign observed_tx[s]=dut.u_tx.o_flit;assign observed_ht[s]=dut.u_tx.o_header_taken;
 tl_control_decode observe(.i_half(observed_tx[s][255:0]),.o_request_starts(request_starts[s]));
end endgenerate
// Independent frozen full-width fixtures for address zero, unchanged across reset epochs.
// Neither completion nor memory-result checking calls the VIP's data generator.
initial begin
 expected_memory[0]=512'h6e5c4a38261402f0deccbaa8968472604e3c2a1806f4e2d0beac9a88766452402e1c0af8e6d4c2b09e8c7a68564432200efcead8c6b4a2907e6c5a4836241200;
 expected_memory[1]=512'hab99877563513f2d1b09f7e5d3c1af9d8b79675543311f0dfbe9d7c5b3a18f7d6b5947352311ffeddbc9b7a593816f5d4b39271503f1dfcdbba9978573614f3d;
 if(RESET_STAGE<1||RESET_STAGE>3||MUTANT<0||MUTANT>2)$fatal(1,"RESET_CONFIGURATION");
 repeat(3)@(negedge clk);
 power_rstn=1;network_rstn=1;start=1;allow_requests=1;
 @(negedge clk);start=0;
 // Capture is preparation, not transmission: reset with both descriptors captured but no header retirement.
 if(RESET_STAGE==1)wait(requested[0]==1&&requested[1]==1&&captures[0]==1&&captures[1]==1&&sent[0]==0&&sent[1]==0);
 if(RESET_STAGE==2)wait(reads[0]==1&&reads[1]==1&&returns[0]==0&&returns[1]==0);
 if(RESET_STAGE==3)wait(held_cycles>=8);
 @(negedge clk);
 if(RESET_STAGE==1&&(captures[0]!=1||captures[1]!=1||sent[0]!=0||sent[1]!=0||origin_count[0]!=1||origin_count[1]!=1))$fatal(1,"RESET_TARGET_RESERVED");
 if(RESET_STAGE==2&&(returns[0]!=0||returns[1]!=0||completer_count[0]!=1||completer_count[1]!=1))$fatal(1,"RESET_TARGET_MEMORY");
 if(RESET_STAGE==3&&(!complete_valid[0]||!complete_valid[1]||complete_ready[0]||complete_ready[1]))$fatal(1,"RESET_TARGET_COMPLETE");
 $display("RESET_TARGET stage=%0d cycle=%0d reserved=%0d,%0d captures=%0d,%0d sent=%0d,%0d reads=%0d,%0d returns=%0d,%0d held=%0d",RESET_STAGE,cycle,requested[0],requested[1],captures[0],captures[1],sent[0],sent[1],reads[0],reads[1],returns[0],returns[1],held_cycles);
 // All network participants and the one-cycle transport register cancel the same local epoch.
 network_rstn=0;allow_requests=0;
 repeat(3)@(negedge clk);
 epoch=1;network_rstn=1;
 // No new service request can hide a stale result during this longer-than-VIP-latency window.
 repeat(100)@(negedge clk);
 $display("RESET_QUIET_PASS stage=%0d cycle=%0d",RESET_STAGE,cycle);
 start=1;allow_requests=1;@(negedge clk);start=0;
end
always @(posedge clk)begin
 cycle=cycle+1;
 if(cycle>2500)$fatal(1,"RESET_TIMEOUT stage=%0d epoch=%0d",RESET_STAGE,epoch);
 if(!network_rstn)begin
  reset_edges=reset_edges+1;quiet=0;held_cycles=0;
  for(e=0;e<2;e=e+1)begin
   requested[e]=0;completed[e]=0;sent[e]=0;captures[e]=0;reads[e]=0;returns[e]=0;result_at[e]=-1;held[e]=0;
   rv[e]<=0;rd[e]<=0;rc[e]<=1;
   for(j=0;j<4;j=j+1)begin active[e][j]=0;read_at[e][j]=-1;end
  end
  // Check registered reset effects after the actual synchronous edge, including both ledgers.
  #1;
  for(e=0;e<2;e=e+1)
   if(origin_count[e]!==0||completer_count[e]!==0||unacked[e]!==0||scheduled[e]!==0||complete_valid[e]!==0||mem_valid[e]!==0||result_valid[e]!==0||link_valid[e]!==0)
    $fatal(1,"RESET_STATE_NOT_CLEARED side=%0d stage=%0d",e,RESET_STAGE);
  if(ov!==0)$fatal(1,"RESET_SWITCH_OUTPUT");
 end else begin
  if(|se)$fatal(1,"RESET_ROUTE_ERROR");
  // Examine offered memory results before a DUT diagnostic can obscure their stale ownership.
  for(e=0;e<2;e=e+1)if(result_valid[e]&&!active[e][result_slot[e]])$fatal(1,"RESET_OLD_MEMORY_RESULT side=%0d epoch=%0d",e,epoch);
  for(e=0;e<2;e=e+1)begin
   if(error[e]||te[e])$fatal(1,"RESET_DUT_ERROR side=%0d cycle=%0d",e,cycle);
   rv[e]<=ov[e]&&orr[e];if(ov[e]&&orr[e])begin rd[e]<=od[e*545+:544];rc[e]<=od[e*545+544];end
   if(origin_count[e]>1||completer_count[e]>1)$fatal(1,"RESET_CAPACITY");
   if(epoch==1&&!allow_requests&&(origin_count[e]!==0||completer_count[e]!==0||complete_valid[e]!==0||mem_valid[e]!==0))$fatal(1,"RESET_QUIET_LEAK");
   if(request_valid[e]&&request_ready[e])begin
    if(requested[e]!=0)$fatal(1,"RESET_DUPLICATE_APP");
    requested[e]=1;all_requested=all_requested+1;$display("RESET_APP epoch=%0d cycle=%0d side=%0d tag=1024 address=0",epoch,cycle,e);
   end
   if(captured[e][0])begin
    if(requested[e]!=1||captures[e]!=0)$fatal(1,"RESET_CAPTURE_OWNERSHIP");
    captures[e]=1;
   end
   if(observed_ht[e][0])begin
    if(captures[e]!=1||sent[e]!=0||request_starts[e]!==8'b1)$fatal(1,"RESET_SEND_OWNERSHIP");
    if(observed_tx[e][113:103]!==11'd1024||{observed_tx[e][79:25],2'b00}!==57'd0)$fatal(1,"RESET_SEND_FIELDS");
    sent[e]=1;$display("RESET_SENT epoch=%0d cycle=%0d side=%0d",epoch,cycle,e);
   end
   if(mem_valid[e]&&mem_ready[e])begin
    if(sent[1-e]!=1||reads[e]!=0||active[e][mem_slot[e]]||mem_slot[e]>=4)$fatal(1,"RESET_MEMORY_REQUEST");
    if(mem_address[e]!==0||mem_length[e]!==15||mem_attr[e]!==8'hff||mem_asi[e]!==0||mem_metadata[e]!==0)$fatal(1,"RESET_MEMORY_FIELDS");
    reads[e]=1;active[e][mem_slot[e]]=1;read_at[e][mem_slot[e]]=cycle;
    $display("RESET_MEM_READ epoch=%0d cycle=%0d side=%0d slot=%0d",epoch,cycle,e,mem_slot[e]);
   end
   if(result_valid[e])begin
    if(returns[e]!=0||read_at[e][result_slot[e]]>=cycle||result_status[e]!==0||result_data[e]!==expected_memory[e])$fatal(1,"RESET_MEMORY_RESULT_DATA");
    if(result_ready[e])begin
     returns[e]=1;result_at[e]=cycle;active[e][result_slot[e]]=0;
     $display("RESET_MEM_RESULT epoch=%0d cycle=%0d side=%0d",epoch,cycle,e);
    end
   end
   if(held[e]&&held_value[e]!=={complete_valid[e],complete_port[e],complete_tag[e],complete_status[e],complete_data_valid[e],complete_data[e]})$fatal(1,"RESET_HELD_COMPLETION_CHANGED");
   held[e]=complete_valid[e]&&!complete_ready[e];held_value[e]={complete_valid[e],complete_port[e],complete_tag[e],complete_status[e],complete_data_valid[e],complete_data[e]};
   // First valid is checked even when the application is applying backpressure.
   if(complete_valid[e])begin
    if(requested[e]!=1||sent[e]!=1||returns[1-e]!=1||result_at[1-e]>=cycle||completed[e]!=0)$fatal(1,"RESET_OLD_OR_EARLY_COMPLETE");
    if(complete_tag[e]!==11'd1024||complete_port[e]!==0||complete_status[e]!==0||complete_data_valid[e]!==1||complete_data[e]!==expected_memory[1-e])$fatal(1,"RESET_COMPLETE_DATA");
    if(complete_ready[e])begin
     if(epoch!=1)$fatal(1,"RESET_OLD_EPOCH_RETIRED");
     completed[e]=1;all_completed=all_completed+1;$display("RESET_COMPLETE epoch=%0d cycle=%0d side=%0d",epoch,cycle,e);
    end
   end
  end
  if(complete_valid[0]&&complete_valid[1]&&!complete_ready[0]&&!complete_ready[1])held_cycles=held_cycles+1;else held_cycles=0;
  if(epoch==1&&completed[0]==1&&completed[1]==1&&origin_count[0]==0&&origin_count[1]==0&&completer_count[0]==0&&completer_count[1]==0&&unacked[0]==0&&unacked[1]==0&&scheduled[0]==0&&scheduled[1]==0)quiet=quiet+1;else quiet=0;
  if(quiet==80)begin
   if(all_requested!=4||all_completed!=2||reset_edges!=6)$fatal(1,"RESET_COVERAGE");
   $display("NETWORK_RESET_PASS stage=%0d requests=4 new_epoch_completions=2 cancelled=2 quiet_before=100 quiet_after=80 cycles=%0d",RESET_STAGE,cycle);$finish;
  end
 end
end
endmodule
