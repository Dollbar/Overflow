`timescale 1ns/1ps
module tb;
import ualink_test_pkg::*;
parameter INJECT=0, BANK_DEPTH=3;
reg clk=0; always #5 clk=~clk;
reg rstn=0,start=0; integer cycle=0,quiet=0,e,j,k,index_value;
integer requested[0:1],completed[0:1],sent[0:1][0:7],reads[0:1][0:7],returns[0:1][0:7],seen[0:1][0:7];
integer result_at[0:1][0:7];reg [511:0] expected_memory[0:1][0:7];
integer originals[0:1],replays[0:1],max_count[0:1];reg dropped[0:1],corrupted[0:1];
wire done[0:1],peer_done[0:1],error[0:1],te[0:1],request_valid[0:1],request_ready[0:1];
wire [10:0] request_tag[0:1];wire [56:0] request_address[0:1];
wire complete_valid[0:1],complete_ready[0:1],complete_data_valid[0:1];
wire [1:0] complete_port[0:1];wire [10:0] complete_tag[0:1];wire [3:0] complete_status[0:1];wire [511:0] complete_data[0:1];
wire [7:0] origin_count[0:1],completer_count[0:1],unacked[0:1],scheduled[0:1];
wire mem_valid[0:1],mem_ready[0:1],result_ready[0:1];wire [1:0] mem_slot[0:1];wire [56:0] mem_address[0:1];
wire [5:0] mem_length[0:1];wire [7:0] mem_attr[0:1],mem_metadata[0:1];wire [1:0] mem_asi[0:1];
// Independent observer state is updated only by public memory handshakes.
reg score_mem_active[0:1][0:3];reg [56:0] score_mem_address[0:1][0:3];integer score_mem_at[0:1][0:3];
wire result_valid[0:1];wire [1:0] result_slot[0:1];wire [3:0] result_status[0:1];wire [511:0] result_data[0:1];
wire link_valid[0:1],link_ready[0:1],link_payload[0:1],link_replay[0:1];wire [543:0] link_data[0:1];
wire [1:0] sv,sr,ov,orr,sl,se;wire [1089:0] sd,od;wire drop_now[0:1],bad_now[0:1];
reg rv[0:1],rc[0:1];reg [543:0] rd[0:1];
wire [511:0] observed_tx[0:1];wire [1:0] observed_ht[0:1];wire [7:0] request_starts[0:1];
ualink_switch_top #(.PORTS(2),.DATA_WIDTH(545)) sw(.clk(clk),.rstn(rstn),.i_route_ids({10'd513,10'd17}),.i_port_enable(2'b11),
.i_valid(sv),.o_ready(sr),.i_data(sd),.i_dst({10'd17,10'd513}),.i_last(2'b11),.o_valid(ov),.i_ready(orr),.o_data(od),.o_last(sl),.o_route_error(se));
genvar s;generate for(s=0;s<2;s=s+1)begin:ends
 assign request_valid[s]=rstn&&done[s]&&peer_done[s]&&requested[s]<8;
 assign request_tag[s]=tag_at(requested[s]);assign request_address[s]=address_at(requested[s]);
 assign complete_ready[s]=cycle>350&&(cycle%7!=s+1);
 ualink_memory_vip #(.SIDE(s)) memory_vip(
 .i_clk(clk),.i_rstn(rstn),.i_read_valid(mem_valid[s]),.o_read_ready(mem_ready[s]),
 .i_read_slot(mem_slot[s]),.i_read_address(mem_address[s]),.i_read_length(mem_length[s]),
 .i_read_attr(mem_attr[s]),.i_read_asi(mem_asi[s]),.i_read_metadata(mem_metadata[s]),
 .o_result_valid(result_valid[s]),.i_result_ready(result_ready[s]),.o_result_slot(result_slot[s]),
 .o_result_data(result_data[s]),.o_result_status(result_status[s]));
 assign drop_now[s]=INJECT&&link_payload[s]&&!link_replay[s]&&originals[s]==5&&!dropped[s];
 assign bad_now[s]=INJECT&&link_payload[s]&&!link_replay[s]&&originals[s]==2&&!corrupted[s];
 assign sv[s]=link_valid[s]&&!drop_now[s];assign sd[s*545+:545]={!bad_now[s],link_data[s]};
 assign link_ready[s]=drop_now[s]||sr[s];assign orr[s]=rstn&&(cycle%7!=s+1)&&!(cycle>=90&&cycle<110);
 ualink_endpoint_top #(.TRANSACTION_MODE(1),.WIDTH(8),.HEADER_DEPTH(2),.BANK_DEPTH(BANK_DEPTH),.RX_DEPTH(40),.DL_DEPTH(3)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_link_reset(1'b0),.i_start(start),.i_auth(1'b0),.i_shared(1'b0),.i_capacities({20{8'd1}}),
 .i_source_valid(2'd0),.i_source_control(512'd0),.i_source_tags_valid(2'd0),.i_source_tags(1024'd0),.i_data_valid(4'd0),.i_data0(512'd0),.i_data1(512'd0),.i_read_ready(1'b0),
 .i_port(2'd0),.i_local_id(s==0?10'd17:10'd513),.i_request_valid(request_valid[s]),.o_request_ready(request_ready[s]),.i_request_port(2'd0),
 .i_request_tag(request_tag[s]),.i_request_address(request_address[s]),.i_request_dst(s==0?10'd513:10'd17),.i_request_length(6'd15),.i_request_attr(8'hff),
 .o_complete_valid(complete_valid[s]),.i_complete_ready(complete_ready[s]),.o_complete_port(complete_port[s]),.o_complete_tag(complete_tag[s]),
 .o_complete_status(complete_status[s]),.o_complete_data(complete_data[s]),.o_complete_data_valid(complete_data_valid[s]),
 .o_mem_valid(mem_valid[s]),.i_mem_ready(mem_ready[s]),.o_mem_slot(mem_slot[s]),.o_mem_address(mem_address[s]),.o_mem_length(mem_length[s]),.o_mem_attr(mem_attr[s]),.o_mem_asi(mem_asi[s]),.o_mem_metadata(mem_metadata[s]),
 .i_mem_result_valid(result_valid[s]),.o_mem_result_ready(result_ready[s]),.i_mem_result_slot(result_slot[s]),.i_mem_result_data(result_data[s]),.i_mem_result_status(result_status[s]),
 .o_outstanding_count(origin_count[s]),.o_completer_count(completer_count[s]),.o_transaction_error(te[s]),
 .o_link_valid(link_valid[s]),.o_link_data(link_data[s]),.i_link_ready(link_ready[s]),.o_link_payload(link_payload[s]),.o_link_replay(link_replay[s]),
 .i_link_valid(rv[s]),.i_link_data(rd[s]),.i_link_crc_ok(rc[s]),.i_rx_replay_limit(8'd50),
 .o_done(done[s]),.o_peer_done(peer_done[s]),.o_error(error[s]),.o_unacked_count(unacked[s]),.o_scheduled_count(scheduled[s]));
 assign observed_tx[s]=dut.u_tx.o_flit;assign observed_ht[s]=dut.u_tx.o_header_taken;
 tl_control_decode observe(.i_half(observed_tx[s][255:0]),.o_request_starts(request_starts[s]));
end endgenerate
// Frozen local-memory byte fixtures; completion oracle never calls the BFM data function.
initial begin
 expected_memory[0][0]=512'h6e5c4a38261402f0deccbaa8968472604e3c2a1806f4e2d0beac9a88766452402e1c0af8e6d4c2b09e8c7a68564432200efcead8c6b4a2907e6c5a4836241200;
 expected_memory[0][1]=512'h8a7a665642321e0efaead6c6b2a28e7e6a5a46362212feeedacab6a692826e5e4a3a261602f2decebaaa968672624e3e2a1a06f6e2d2beae9a8a766652422e1e;
 expected_memory[0][2]=512'ha69486745e4c3e2c1604f6e4cebcae9c867466543e2c1e0cf6e4d6c4ae9c8e7c665446341e0cfeecd6c4b6a48e7c6e5c46342614feecdeccb6a496846e5c4e3c;
 expected_memory[0][3]=512'hc2b2a2927a6a5a4a32221202eadacabaa29282725a4a3a2a1202f2e2cabaaa9a827262523a2a1a0af2e2d2c2aa9a8a7a625242321a0afaead2c2b2a28a7a6a5a;
 expected_memory[0][4]=512'hdeccbaa89e8c7a684e3c2a180efcead8beac9a887e6c5a482e1c0af8eedccab89e8c7a685e4c3a280efcead8cebcaa987e6c5a483e2c1a08eedccab8ae9c8a78;
 expected_memory[0][5]=512'hfaead6c6baaa96866a5a46362a1a06f6dacab6a69a8a76664a3a26160afae6d6baaa96867a6a56462a1a06f6eadac6b69a8a76665a4a36260afae6d6cabaa696;
 expected_memory[0][6]=512'h1604f6e4d6c4b6a48674665446342614f6e4d6c4b6a4968466544634261406f4d6c4b6a4968476644634261406f4e6d4b6a4968476645644261406f4e6d4c6b4;
 expected_memory[0][7]=512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
 expected_memory[1][0]=512'hab99877563513f2d1b09f7e5d3c1af9d8b79675543311f0dfbe9d7c5b3a18f7d6b5947352311ffeddbc9b7a593816f5d4b39271503f1dfcdbba9978573614f3d;
 expected_memory[1][1]=512'hc7b7a3937f6f5b4b37271303efdfcbbba79783735f4f3b2b1707f3e3cfbfab9b877763533f2f1b0bf7e7d3c3af9f8b7b675743331f0ffbebd7c7b3a38f7f6b5b;
 expected_memory[1][2]=512'he3d1c3b19b897b69534133210bf9ebd9c3b1a3917b695b4933211301ebd9cbb9a39183715b493b291301f3e1cbb9ab99837163513b291b09f3e1d3c1ab998b79;
 expected_memory[1][3]=512'hffefdfcfb7a797876f5f4f3f271707f7dfcfbfaf978777674f3f2f1f07f7e7d7bfaf9f8f776757472f1f0fffe7d7c7b79f8f7f6f574737270fffefdfc7b7a797;
 expected_memory[1][4]=512'h1b09f7e5dbc9b7a58b7967554b392715fbe9d7c5bba997856b5947352b1907f5dbc9b7a59b8977654b3927150bf9e7d5bba997857b6957452b1907f5ebd9c7b5;
 expected_memory[1][5]=512'h37271303f7e7d3c3a7978373675743331707f3e3d7c7b3a38777635347372313f7e7d3c3b7a7938367574333271703f3d7c7b3a3978773634737231307f7e3d3;
 expected_memory[1][6]=512'h534133211301f3e1c3b1a3918371635133211301f3e1d3c1a3918371635143311301f3e1d3c1b3a18371635143312311f3e1d3c1b3a1938163514331231103f1;
 expected_memory[1][7]=512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
 for(e=0;e<2;e=e+1)begin
  requested[e]=0;completed[e]=0;originals[e]=0;replays[e]=0;dropped[e]=0;corrupted[e]=0;max_count[e]=0;rv[e]=0;rc[e]=1;rd[e]=0;
  for(j=0;j<8;j=j+1)begin sent[e][j]=0;reads[e][j]=0;returns[e][j]=0;seen[e][j]=0;result_at[e][j]=-1;end
  for(j=0;j<4;j=j+1)begin score_mem_active[e][j]=0;score_mem_address[e][j]=0;score_mem_at[e][j]=-1;end
 end
 repeat(3)@(negedge clk);rstn=1;start=1;@(negedge clk);start=0;
end
always @(posedge clk)begin
 cycle<=cycle+1;
 if(rstn)begin
  if(|se)$fatal(1,"CAUSAL_ROUTE_ERROR");
  for(e=0;e<2;e=e+1)begin
   if(error[e]||te[e])$fatal(1,"CAUSAL_DUT_ERROR side=%0d cycle=%0d transaction=%b",e,cycle,te[e]);
   rv[e]<=ov[e]&&orr[e];if(ov[e]&&orr[e])begin rd[e]<=od[e*545+:544];rc[e]<=od[e*545+544];end
   if(request_valid[e]&&request_ready[e])begin $display("APP %0d %0d %0d",cycle,e,request_tag[e]);requested[e]=requested[e]+1;end
   if(origin_count[e]>max_count[e])max_count[e]=origin_count[e];
   if(observed_ht[e][0])for(k=0;k<8;k=k+1)if(request_starts[e][k])begin
    index_value=tag_index(observed_tx[e][k*32+103+:11]);
    if(index_value<0||sent[e][index_value]!=0||index_value>=requested[e])$fatal(1,"CAUSAL_SEND_IDENTITY");
    if({observed_tx[e][k*32+25+:55],2'b00}!==address_at(index_value))$fatal(1,"CAUSAL_SEND_ADDRESS");
    sent[e][index_value]=1;$display("SENT %0d %0d %0d",cycle,e,index_value);
   end
   if(mem_valid[e]&&mem_ready[e])begin
    index_value=address_index(mem_address[e]);
    if(index_value<0||score_mem_active[e][mem_slot[e]]||sent[1-e][index_value]!=1||reads[e][index_value]!=0)$fatal(1,"CAUSAL_MEMORY_REQUEST side=%0d address=%h",e,mem_address[e]);
    if(mem_length[e]!==15||mem_attr[e]!==8'hff||mem_asi[e]!==0||mem_metadata[e]!==0)$fatal(1,"CAUSAL_MEMORY_FIELDS");
    reads[e][index_value]=1;score_mem_active[e][mem_slot[e]]=1;score_mem_address[e][mem_slot[e]]=mem_address[e];score_mem_at[e][mem_slot[e]]=cycle;
    $display("MEM_READ %0d %0d %0d %0d",cycle,e,index_value,mem_slot[e]);
   end
   if(result_valid[e]&&result_ready[e])begin
    index_value=address_index(score_mem_address[e][result_slot[e]]);
    if(index_value<0||!score_mem_active[e][result_slot[e]]||returns[e][index_value]!=0||score_mem_at[e][result_slot[e]]>=cycle)$fatal(1,"CAUSAL_MEMORY_RESULT");
    if(result_status[e]!==((index_value==7)?4'd3:4'd0)||result_data[e]!==expected_memory[e][index_value])$fatal(1,"CAUSAL_MEMORY_RESULT_DATA");
    returns[e][index_value]=1;result_at[e][index_value]=cycle;score_mem_active[e][result_slot[e]]=0;$display("MEM_RESULT %0d %0d %0d",cycle,e,index_value);
   end
   if(complete_valid[e])begin
    index_value=tag_index(complete_tag[e]);
    if(index_value<0||seen[e][index_value]!=0||sent[e][index_value]!=1||returns[1-e][index_value]!=1||result_at[1-e][index_value]>=cycle)$fatal(1,"CAUSAL_EARLY_COMPLETE_VALID");
    if(complete_data[e]!==expected_memory[e==0?1:0][index_value])$fatal(1,"CAUSAL_COMPLETION_DATA side=%0d index=%0d",e,index_value);
   end
   if(complete_valid[e]&&complete_ready[e])begin
    index_value=tag_index(complete_tag[e]);
    if(index_value<0||seen[e][index_value]!=0||sent[e][index_value]!=1||returns[1-e][index_value]!=1)$fatal(1,"CAUSAL_COMPLETION_IDENTITY");
    if(complete_port[e]!==0||complete_status[e]!==((index_value==7)?4'd3:4'd0)||complete_data_valid[e]!== (index_value!=7))$fatal(1,"CAUSAL_COMPLETION_STATUS");
    if(complete_data[e]!==expected_memory[1-e][index_value])$fatal(1,"CAUSAL_COMPLETION_DATA side=%0d index=%0d",e,index_value);
    seen[e][index_value]=1;completed[e]=completed[e]+1;$display("COMPLETE %0d %0d %0d",cycle,e,index_value);
   end
   if(link_valid[e]&&link_ready[e]&&link_payload[e])begin
    if(link_replay[e])replays[e]=replays[e]+1;else originals[e]=originals[e]+1;
    if(drop_now[e])dropped[e]=1;if(bad_now[e])corrupted[e]=1;
   end
  end
  if(completed[0]==8&&completed[1]==8&&origin_count[0]==0&&origin_count[1]==0&&completer_count[0]==0&&completer_count[1]==0&&unacked[0]==0&&unacked[1]==0&&scheduled[0]==0&&scheduled[1]==0)quiet=quiet+1;else quiet=0;
  if(quiet==30)begin
   if(max_count[0]!=4||max_count[1]!=4)$fatal(1,"CAUSAL_OUTSTANDING_COVERAGE");
   if(INJECT&&(!dropped[0]||!dropped[1]||!corrupted[0]||!corrupted[1]||replays[0]==0||replays[1]==0))$fatal(1,"CAUSAL_RECOVERY_COVERAGE");
   $display("CAUSAL_READ_PASS requests=16 completions=16 max_outstanding=4,4 replays=%0d,%0d cycles=%0d",replays[0],replays[1],cycle);$finish;
  end
  if(cycle>6000)$fatal(1,"CAUSAL_TIMEOUT requests=%0d,%0d complete=%0d,%0d count=%0d,%0d",requested[0],requested[1],completed[0],completed[1],origin_count[0],origin_count[1]);
 end
end
endmodule
