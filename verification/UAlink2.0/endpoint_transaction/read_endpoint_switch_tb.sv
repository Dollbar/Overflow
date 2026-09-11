`timescale 1ns/1ps
module tb;
parameter COUNT=10,INJECT=0,BANK_DEPTH=3,FAULT=0;
reg clk=0;always #5 clk=~clk;reg rstn=0,start=0;
integer cycle=0,quiet=0,e,j,k,idx,expected_index,nbytes,base,write_total=0;
integer requested[0:1],completed[0:1],cursor[0:1],max_count[0:1];
integer originals[0:1],replays[0:1],memory_issue[0:1],beat_total=0;
integer response_beats[0:1][0:COUNT-1],last_response_at[0:1][0:COUNT-1];reg dropped[0:1],corrupted[0:1];
reg [95:0] descriptors[0:2*COUNT-1];reg [2047:0] payloads[0:2*COUNT-1];
reg [255:0] byte_enables[0:2*COUNT-1],expected_masks[0:2*COUNT-1];reg [2047:0] expected_data[0:2*COUNT-1],expected_raw[0:2*COUNT-1];
reg [255:0] memory_masks[0:2*COUNT-1];reg [3:0] statuses[0:2*COUNT-1],num_beats[0:2*COUNT-1];
integer sent[0:1][0:COUNT-1],returns[0:1][0:COUNT-1],result_at[0:1][0:COUNT-1],seen[0:1][0:COUNT-1],executions[0:1][0:COUNT-1];
integer read_owner[0:1][0:3],write_owner[0:1][0:3],memory_at[0:1][0:3];
reg read_active[0:1][0:3],write_active[0:1][0:3],complete_held[0:1];reg [2835:0] held_value[0:1];
wire done[0:1],peer_done[0:1],error[0:1],te[0:1],request_valid[0:1],request_ready[0:1];
wire [10:0] request_tag[0:1];wire [56:0] request_address[0:1];
wire complete_valid[0:1],complete_ready[0:1],complete_data_valid[0:1],complete_write[0:1];
wire [1:0] complete_port[0:1];wire [10:0] complete_tag[0:1];wire [3:0] complete_status[0:1];wire [511:0] complete_data[0:1];
wire [2047:0] complete_full[0:1],result_full[0:1];wire [255:0] complete_mask[0:1],mem_be[0:1];
wire response_fire[0:1],response_write[0:1],response_last[0:1],response_error[0:1];
wire [10:0] response_tag[0:1];wire [9:0] response_dst[0:1];wire [1:0] response_offset[0:1],response_length[0:1],response_port[0:1];
wire [3:0] response_status[0:1];wire [511:0] response_data[0:1];
wire [7:0] origin_count[0:1],completer_count[0:1],write_count[0:1],unacked[0:1],scheduled[0:1];
wire mem_valid[0:1],mem_ready[0:1],result_ready[0:1];wire [1:0] mem_slot[0:1];wire [56:0] mem_address[0:1];
wire [5:0] mem_length[0:1];wire [7:0] mem_attr[0:1],mem_metadata[0:1];wire [1:0] mem_asi[0:1];
wire result_valid[0:1];wire [1:0] result_slot[0:1];wire [3:0] result_status[0:1];wire [511:0] result_data[0:1];
wire write_valid[0:1],write_ready[0:1],write_result_valid[0:1],write_result_ready[0:1],write_executed[0:1];
wire [1:0] write_slot[0:1],write_result_slot[0:1],write_execute_slot[0:1];wire [56:0] write_address[0:1];
wire [5:0] write_length[0:1];wire [7:0] write_attr[0:1],write_metadata[0:1];wire [1:0] write_asi[0:1];
wire [2047:0] write_data[0:1];wire [255:0] write_be[0:1];wire [31:0] execution_count[0:1];
wire link_valid[0:1],link_ready[0:1],link_payload[0:1],link_replay[0:1];wire [543:0] link_data[0:1];
wire [1:0] sv,sr,ov,orr,sl,se;wire [1089:0] sd,od;wire drop_now[0:1],bad_now[0:1];
reg rv[0:1],rc[0:1];reg [543:0] rd[0:1];
wire [511:0] observed_tx[0:1];wire [1:0] observed_ht[0:1];wire [7:0] request_starts[0:1];
ualink_switch_top #(.PORTS(2),.DATA_WIDTH(545)) sw(.clk(clk),.rstn(rstn),.i_route_ids({10'd513,10'd17}),.i_port_enable(2'b11),
.i_valid(sv),.o_ready(sr),.i_data(sd),.i_dst({10'd17,10'd513}),.i_last(2'b11),.o_valid(ov),.i_ready(orr),.o_data(od),.o_last(sl),.o_route_error(se));
genvar s;generate for(s=0;s<2;s=s+1)begin:ends
 wire [95:0] candidate=descriptors[s*COUNT+((requested[s]<COUNT)?requested[s]:0)];
 assign request_valid[s]=rstn&&done[s]&&peer_done[s]&&requested[s]<COUNT;
 assign request_tag[s]=candidate[91:81];assign request_address[s]=candidate[80:24];
 assign complete_ready[s]=cycle>500&&(cycle%7!=s+1);
 full_read_test_memory memory_bfm(
 .clk(clk),.rstn(rstn),.read_valid(mem_valid[s]),.read_ready(mem_ready[s]),.read_slot(mem_slot[s]),.read_address(mem_address[s]),.read_length(mem_length[s]),
 .read_status(statuses[(1-s)*COUNT+((memory_issue[s]<COUNT)?memory_issue[s]:0)]),
 .read_result_valid(result_valid[s]),.read_result_ready(result_ready[s]),.read_result_slot(result_slot[s]),.read_result_data(result_full[s]),.read_result_status(result_status[s]),
 .write_valid(write_valid[s]),.write_ready(write_ready[s]),.write_slot(write_slot[s]),.write_address(write_address[s]),
 .write_data(write_data[s]),.write_be(write_be[s]),
 .write_result_valid(write_result_valid[s]),.write_result_ready(write_result_ready[s]),.write_result_slot(write_result_slot[s]),
 .write_executed(write_executed[s]),.write_execute_slot(write_execute_slot[s]),.execution_count(execution_count[s]));
 assign result_data[s]=result_full[s][511:0];
 assign drop_now[s]=INJECT&&link_payload[s]&&!link_replay[s]&&originals[s]==5&&!dropped[s];
 assign bad_now[s]=INJECT&&link_payload[s]&&!link_replay[s]&&originals[s]==2&&!corrupted[s];
 assign sv[s]=link_valid[s]&&!drop_now[s];assign sd[s*545+:545]={!bad_now[s],link_data[s]};
 assign link_ready[s]=drop_now[s]||sr[s];assign orr[s]=rstn&&(cycle%7!=s+1)&&!(cycle>=90&&cycle<110);
 ualink_endpoint_top #(.TRANSACTION_MODE(1),.WRITE_ENABLE(1),.FULL_READ_ENABLE(1),.WIDTH(8),.HEADER_DEPTH(2),.BANK_DEPTH(BANK_DEPTH),.RX_DEPTH(160),.DL_DEPTH(3)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_link_reset(1'b0),.i_start(start),.i_auth(1'b0),.i_shared(1'b0),.i_capacities({20{8'd4}}),
 .i_source_valid(2'd0),.i_source_control(512'd0),.i_source_tags_valid(2'd0),.i_source_tags(1024'd0),.i_data_valid(4'd0),.i_data0(512'd0),.i_data1(512'd0),.i_read_ready(1'b0),
 .i_port(2'd0),.i_local_id(s==0?10'd17:10'd513),.i_request_valid(request_valid[s]),.o_request_ready(request_ready[s]),.i_request_port(2'd0),
 .i_request_tag(request_tag[s]),.i_request_address(request_address[s]),.i_request_dst(s==0?10'd513:10'd17),.i_request_length(candidate[23:18]),.i_request_attr(candidate[17:10]),
 .o_complete_valid(complete_valid[s]),.i_complete_ready(complete_ready[s]),.o_complete_port(complete_port[s]),.o_complete_tag(complete_tag[s]),
 .o_complete_status(complete_status[s]),.o_complete_data(complete_data[s]),.o_complete_data_valid(complete_data_valid[s]),.o_complete_data_full(complete_full[s]),.o_complete_mask(complete_mask[s]),
 .o_mem_valid(mem_valid[s]),.i_mem_ready(mem_ready[s]),.o_mem_slot(mem_slot[s]),.o_mem_address(mem_address[s]),.o_mem_length(mem_length[s]),.o_mem_attr(mem_attr[s]),.o_mem_asi(mem_asi[s]),.o_mem_metadata(mem_metadata[s]),.o_mem_be(mem_be[s]),
 .i_mem_result_valid(result_valid[s]),.o_mem_result_ready(result_ready[s]),.i_mem_result_slot(result_slot[s]),.i_mem_result_data(result_data[s]),.i_mem_result_data_full(FAULT==2?{1536'd0,result_full[s][511:0]}:result_full[s]),.i_mem_result_status(result_status[s]),
 .i_request_is_write(candidate[93]),.i_request_full(candidate[92]),.i_request_asi(candidate[9:8]),.i_request_metadata(candidate[7:0]),
 .i_request_data(payloads[s*COUNT+((requested[s]<COUNT)?requested[s]:0)]),.i_request_be(byte_enables[s*COUNT+((requested[s]<COUNT)?requested[s]:0)]),
 .o_complete_is_write(complete_write[s]),
 .o_write_mem_valid(write_valid[s]),.i_write_mem_ready(write_ready[s]),.o_write_mem_slot(write_slot[s]),.o_write_mem_address(write_address[s]),
 .o_write_mem_length(write_length[s]),.o_write_mem_attr(write_attr[s]),.o_write_mem_asi(write_asi[s]),.o_write_mem_metadata(write_metadata[s]),
 .o_write_mem_data(write_data[s]),.o_write_mem_be(write_be[s]),.i_write_mem_result_valid(write_result_valid[s]),.o_write_mem_result_ready(write_result_ready[s]),
 .i_write_mem_result_slot(write_result_slot[s]),.i_write_mem_result_status(4'd0),.o_write_completer_count(write_count[s]),
 .o_outstanding_count(origin_count[s]),.o_completer_count(completer_count[s]),.o_transaction_error(te[s]),
 .o_link_valid(link_valid[s]),.o_link_data(link_data[s]),.i_link_ready(link_ready[s]),.o_link_payload(link_payload[s]),.o_link_replay(link_replay[s]),
 .i_link_valid(rv[s]),.i_link_data(rd[s]),.i_link_crc_ok(rc[s]),.i_rx_replay_limit(8'd50),
 .o_done(done[s]),.o_peer_done(peer_done[s]),.o_error(error[s]),.o_unacked_count(unacked[s]),.o_scheduled_count(scheduled[s]));
 // Observe only actual receiver-to-Tag handshakes, independent of backend due/pending state.
 assign response_fire[s]=dut.transactions.u_core.u_receiver.o_response_valid&&dut.transactions.u_core.u_receiver.i_response_ready;
 assign response_tag[s]=dut.transactions.u_core.u_receiver.o_response_tag;
 assign response_write[s]=dut.transactions.u_core.u_receiver.o_response_is_write;
 assign response_dst[s]=dut.transactions.u_core.u_receiver.o_response_dst;
 assign response_offset[s]=dut.transactions.u_core.u_receiver.o_response_offset;
 assign response_length[s]=dut.transactions.u_core.u_receiver.o_response_num_beats;
 assign response_last[s]=dut.transactions.u_core.u_receiver.o_response_last;
 assign response_status[s]=dut.transactions.u_core.u_receiver.o_response_status;
 assign response_port[s]=dut.transactions.u_core.u_receiver.o_response_port;
 assign response_error[s]=dut.transactions.u_core.u_receiver.o_response_data_error;
 assign response_data[s]=dut.transactions.u_core.u_receiver.o_response_data;
 assign observed_tx[s]=dut.u_tx.o_flit;assign observed_ht[s]=dut.u_tx.o_header_taken;
 tl_control_decode observe(.i_half(observed_tx[s][255:0]),.o_request_starts(request_starts[s]));
end endgenerate
initial begin
 $readmemh("descriptors.hex",descriptors);$readmemh("payloads.hex",payloads);$readmemh("byte_enables.hex",byte_enables);
 $readmemh("expected_masks.hex",expected_masks);$readmemh("expected_data.hex",expected_data);$readmemh("expected_raw.hex",expected_raw);
 $readmemh("memory_masks.hex",memory_masks);$readmemh("statuses.hex",statuses);$readmemh("num_beats.hex",num_beats);
 for(j=0;j<COUNT;j=j+1)if(descriptors[j][93])write_total=write_total+1;else beat_total=beat_total+num_beats[j];
 for(e=0;e<2;e=e+1)begin
  requested[e]=0;completed[e]=0;memory_issue[e]=0;cursor[e]=0;max_count[e]=0;originals[e]=0;replays[e]=0;dropped[e]=0;corrupted[e]=0;
  rv[e]=0;rd[e]=0;rc[e]=1;complete_held[e]=0;
  for(j=0;j<COUNT;j=j+1)begin sent[e][j]=0;returns[e][j]=0;result_at[e][j]=-1;seen[e][j]=0;executions[e][j]=0;response_beats[e][j]=0;last_response_at[e][j]=-1;end
  for(j=0;j<4;j=j+1)begin read_active[e][j]=0;write_active[e][j]=0;read_owner[e][j]=-1;write_owner[e][j]=-1;memory_at[e][j]=-1;end
 end
 repeat(3)@(negedge clk);rstn=1;start=1;@(negedge clk);start=0;
end
always @(posedge clk)begin
 cycle<=cycle+1; // NBA keeps ready/backpressure inputs stable through the sampling edge.
 if(cycle>COUNT*350+3000)$fatal(1,"READ_ESE_TIMEOUT app=%d,%d cursor=%d,%d complete=%d,%d",requested[0],requested[1],cursor[0],cursor[1],completed[0],completed[1]);
 if(rstn)begin
  if(|se)$fatal(1,"READ_ESE_ROUTE_ERROR");
  for(e=0;e<2;e=e+1)begin
   if(error[e]||te[e])$fatal(1,"READ_ESE_DUT_ERROR cycle=%0d side=%0d transaction=%b",cycle,e,te[e]);
   rv[e]<=ov[e]&&orr[e];if(ov[e]&&orr[e])begin rd[e]<=od[e*545+:544];rc[e]<=od[e*545+544];end
   if((write_valid[e]&&write_ready[e])||(mem_valid[e]&&mem_ready[e]))memory_issue[e]<=memory_issue[e]+1;
   if(origin_count[e]>4||write_count[e]>4||completer_count[e]>4)$fatal(1,"READ_ESE_CAPACITY");
   if(origin_count[e]>max_count[e])max_count[e]=origin_count[e];
   if(request_valid[e]&&request_ready[e])begin $display("READ_ESE_APP cycle=%0d side=%0d index=%0d write=%0d",cycle,e,requested[e],descriptors[e*COUNT+requested[e]][93]);requested[e]<=requested[e]+1;end
   if(observed_ht[e][0])for(k=0;k<8;k=k+1)if(request_starts[e][k])begin
    idx=observed_tx[e][k*32+103+:11]-1024;
    if(idx<0||idx>=COUNT||sent[e][idx]!=0||idx>=requested[e])$fatal(1,"READ_ESE_SEND_IDENTITY");
    if({observed_tx[e][k*32+25+:55],2'b00}!==descriptors[e*COUNT+idx][80:24])$fatal(1,"READ_ESE_SEND_ADDRESS");
    sent[e][idx]=1;
   end
   if(write_valid[e]&&write_ready[e])begin
    idx=cursor[e];expected_index=(1-e)*COUNT+idx;
    if(idx>=COUNT||!descriptors[expected_index][93]||sent[1-e][idx]!=1||write_active[e][write_slot[e]])$fatal(1,"READ_ESE_WRITE_ORDER");
    if(write_address[e]!==descriptors[expected_index][80:24]||write_length[e]!==descriptors[expected_index][23:18]||write_attr[e]!==descriptors[expected_index][17:10]||write_asi[e]!==descriptors[expected_index][9:8]||write_metadata[e]!==descriptors[expected_index][7:0]||write_be[e]!==memory_masks[expected_index])$fatal(1,"READ_ESE_WRITE_FIELDS side=%0d index=%0d address=%h len=%d be=%h expected=%h",e,idx,write_address[e],write_length[e],write_be[e],memory_masks[expected_index]);
    nbytes=64*((write_address[e]%64+4*(write_length[e]+1)+63)/64);
    for(j=0;j<nbytes;j=j+1)if(write_data[e][j*8+:8]!==payloads[expected_index][j*8+:8])$fatal(1,"READ_ESE_WRITE_DATA side=%0d index=%0d byte=%0d",e,idx,j);
    write_active[e][write_slot[e]]=1;write_owner[e][write_slot[e]]=idx;memory_at[e][write_slot[e]]=cycle;cursor[e]=cursor[e]+1;
    $display("READ_ESE_MEMORY_WRITE cycle=%0d side=%0d index=%0d slot=%0d",cycle,e,idx,write_slot[e]);
   end
   if(mem_valid[e]&&mem_ready[e])begin
    idx=cursor[e];expected_index=(1-e)*COUNT+idx;
    if(idx>=COUNT||descriptors[expected_index][93]||sent[1-e][idx]!=1||read_active[e][mem_slot[e]])$fatal(1,"READ_ESE_READ_ORDER");
    if(mem_address[e]!==descriptors[expected_index][80:24]||mem_length[e]!==descriptors[expected_index][23:18]||mem_attr[e]!==descriptors[expected_index][17:10]||mem_asi[e]!==descriptors[expected_index][9:8]||mem_metadata[e]!==descriptors[expected_index][7:0]||mem_be[e]!==memory_masks[expected_index])$fatal(1,"READ_ESE_READ_FIELDS");
    read_active[e][mem_slot[e]]=1;read_owner[e][mem_slot[e]]=idx;memory_at[e][mem_slot[e]]=cycle;cursor[e]=cursor[e]+1;
   end
   if(write_executed[e])begin
    idx=write_owner[e][write_execute_slot[e]];
    if(!write_active[e][write_execute_slot[e]]||idx<0||executions[e][idx]!=0||memory_at[e][write_execute_slot[e]]>=cycle)$fatal(1,"READ_ESE_DUPLICATE_EXECUTION");
    executions[e][idx]=1;$display("READ_ESE_EXECUTE cycle=%0d side=%0d index=%0d",cycle,e,idx);
   end
   if(write_result_valid[e]&&write_result_ready[e])begin
    idx=write_owner[e][write_result_slot[e]];
    if(idx<0||!write_active[e][write_result_slot[e]]||executions[e][idx]!=1||returns[e][idx]!=0)$fatal(1,"READ_ESE_EXECUTION_CAUSALITY side=%0d",e);
    returns[e][idx]=1;result_at[e][idx]=cycle;write_active[e][write_result_slot[e]]=0;
   end
   if(result_valid[e]&&result_ready[e])begin
    idx=read_owner[e][result_slot[e]];
    if(idx<0||!read_active[e][result_slot[e]]||returns[e][idx]!=0||memory_at[e][result_slot[e]]>=cycle)$fatal(1,"READ_ESE_READ_RESULT_CAUSALITY");
    if(result_full[e]!==expected_raw[(1-e)*COUNT+idx]||result_status[e]!==statuses[(1-e)*COUNT+idx])$fatal(1,"READ_ESE_READ_DATA side=%0d index=%0d",e,idx);
    returns[e][idx]=1;result_at[e][idx]=cycle;read_active[e][result_slot[e]]=0;
   end
   if(response_fire[e])begin
    idx=response_tag[e]-1024;expected_index=e*COUNT+idx;
    if(idx<0||idx>=COUNT||sent[e][idx]!=1||returns[1-e][idx]!=1||result_at[1-e][idx]>=cycle||seen[e][idx]!=0)$fatal(1,"READ_ESE_RESPONSE_CAUSALITY side=%0d index=%0d",e,idx);
    if(response_write[e]!==descriptors[expected_index][93]||response_dst[e]!==(e==0?10'd17:10'd513)||response_status[e]!==statuses[expected_index]||response_port[e]!==0||response_error[e]||response_length[e]!==0)$fatal(1,"READ_ESE_RESPONSE_IDENTITY");
    if(response_write[e])begin
     if(response_beats[e][idx]!=0)$fatal(1,"READ_ESE_DUPLICATE_WRITE_RESPONSE");
    end else begin
     if(response_beats[e][idx]>=num_beats[expected_index]||response_offset[e]!==response_beats[e][idx][1:0]||response_last[e]!==((response_beats[e][idx]+1)==num_beats[expected_index]))$fatal(1,"READ_ESE_RESPONSE_BEAT side=%0d index=%0d offset=%0d seen=%0d last=%b",e,idx,response_offset[e],response_beats[e][idx],response_last[e]);
     // Compare selected bytes only here; the application full result must also clear every unused byte.
     for(j=0;j<64;j=j+1)if(statuses[expected_index]==0&&expected_masks[expected_index][response_offset[e]*64+j])
      if(response_data[e][j*8+:8]!==expected_data[expected_index][(response_offset[e]*64+j)*8+:8])$fatal(1,"READ_ESE_COMPLETE_DATA response side=%0d index=%0d",e,idx);
    end
    response_beats[e][idx]=response_beats[e][idx]+1;last_response_at[e][idx]=cycle;
   end
   if(complete_held[e]&&held_value[e]!=={complete_valid[e],complete_write[e],complete_port[e],complete_tag[e],complete_status[e],complete_data_valid[e],complete_data[e],complete_full[e],complete_mask[e]})$fatal(1,"READ_ESE_COMPLETE_STABILITY");
   complete_held[e]=complete_valid[e]&&!complete_ready[e];held_value[e]={complete_valid[e],complete_write[e],complete_port[e],complete_tag[e],complete_status[e],complete_data_valid[e],complete_data[e],complete_full[e],complete_mask[e]};
   if(complete_valid[e])begin
    idx=complete_tag[e]-1024;expected_index=e*COUNT+idx;
    if(idx<0||idx>=COUNT||seen[e][idx]!=0||sent[e][idx]!=1||returns[1-e][idx]!=1||result_at[1-e][idx]>=cycle||last_response_at[e][idx]>=cycle||response_beats[e][idx]!=(descriptors[expected_index][93]?1:num_beats[expected_index]))$fatal(1,"READ_ESE_EARLY_COMPLETE");
    if(complete_write[e]!==descriptors[expected_index][93]||complete_port[e]!==0||complete_status[e]!==statuses[expected_index]||complete_data_valid[e]!==(!descriptors[expected_index][93]&&statuses[expected_index]==0)||complete_data[e]!==expected_data[expected_index][511:0]||complete_full[e]!==expected_data[expected_index]||complete_mask[e]!==expected_masks[expected_index])$fatal(1,"READ_ESE_COMPLETE_DATA side=%0d index=%0d",e,idx);
    if(complete_ready[e])begin seen[e][idx]=1;completed[e]=completed[e]+1;$display("READ_ESE_COMPLETE cycle=%0d side=%0d index=%0d",cycle,e,idx);end
   end
   if(link_valid[e]&&link_ready[e]&&link_payload[e])begin
    if(link_replay[e])replays[e]=replays[e]+1;else originals[e]<=originals[e]+1;
    if(drop_now[e])dropped[e]<=1;if(bad_now[e])corrupted[e]<=1;
   end
  end
  if(completed[0]==COUNT&&completed[1]==COUNT&&origin_count[0]==0&&origin_count[1]==0&&completer_count[0]==0&&completer_count[1]==0&&write_count[0]==0&&write_count[1]==0&&unacked[0]==0&&unacked[1]==0&&scheduled[0]==0&&scheduled[1]==0)quiet=quiet+1;else quiet=0;
  if(quiet==50)begin
   if(execution_count[0]!=write_total||execution_count[1]!=write_total||cursor[0]!=COUNT||cursor[1]!=COUNT||max_count[0]!=4||max_count[1]!=4)$fatal(1,"READ_ESE_EXECUTION_COVERAGE");
   if(INJECT&&(!dropped[0]||!dropped[1]||!corrupted[0]||!corrupted[1]||replays[0]==0||replays[1]==0))$fatal(1,"READ_ESE_RECOVERY_COVERAGE");
   for(e=0;e<2;e=e+1)for(j=0;j<COUNT;j=j+1)if(returns[e][j]!=1||sent[e][j]!=1||seen[e][j]!=1||response_beats[e][j]!=(descriptors[e*COUNT+j][93]?1:num_beats[e*COUNT+j]))$fatal(1,"READ_ESE_FINAL_OWNERSHIP");
   $display("READ_ESE_BEATS read_per_side=%0d",beat_total);
   $display("READ_ESE_PASS requests=%0d completions=%0d writes=%0d,%0d replays=%0d,%0d cycles=%0d",COUNT*2,completed[0]+completed[1],execution_count[0],execution_count[1],replays[0],replays[1],cycle);$finish;
  end
 end
end
endmodule

// Simulation-only byte memory. It consumes actual commands/data/BE, holds delayed results,
// and never reads expected-data fixtures. Unused return lanes are deliberately nonzero.
module full_read_test_memory(
 input wire clk,rstn,
 input wire read_valid,output wire read_ready,input wire [1:0] read_slot,input wire [56:0] read_address,
 input wire [5:0] read_length,input wire [3:0] read_status,
 output reg read_result_valid,input wire read_result_ready,output reg [1:0] read_result_slot,
 output reg [2047:0] read_result_data,output reg [3:0] read_result_status,
 input wire write_valid,output wire write_ready,input wire [1:0] write_slot,input wire [56:0] write_address,
 input wire [2047:0] write_data,input wire [255:0] write_be,
 output reg write_result_valid,input wire write_result_ready,output reg [1:0] write_result_slot,
 output reg write_executed,output reg [1:0] write_execute_slot,output reg [31:0] execution_count
);
 reg [7:0] memory[0:255];reg read_pending,write_pending,write_applied;
 reg [1:0] saved_read_slot,saved_write_slot;reg [56:0] saved_read_address,saved_write_address;
 reg [2047:0] saved_data;reg [255:0] saved_be;reg [5:0] saved_read_length;reg [3:0] saved_read_status;
 integer cycles,read_due,write_due,b;
 assign read_ready=rstn&&!read_pending&&(cycles%5!=1);
 assign write_ready=rstn&&!write_pending&&(cycles%7!=2);
 always @(posedge clk)begin
  if(!rstn)begin
   cycles<=0;read_pending<=0;write_pending<=0;write_applied<=0;read_result_valid<=0;write_result_valid<=0;write_executed<=0;execution_count<=0;
   read_result_slot<=0;read_result_data<=0;read_result_status<=0;write_result_slot<=0;write_execute_slot<=0;
   saved_read_slot<=0;saved_write_slot<=0;saved_read_address<=0;saved_write_address<=0;saved_data<=0;saved_be<=0;read_due<=0;write_due<=0;saved_read_length<=0;saved_read_status<=0;
   for(b=0;b<256;b=b+1)memory[b]<=0;
  end else begin
   cycles<=cycles+1;write_executed<=0;
   if(read_result_valid&&read_result_ready)begin read_result_valid<=0;read_pending<=0;end
   if(write_result_valid&&write_result_ready)begin write_result_valid<=0;write_pending<=0;end
   if(read_pending&&!read_result_valid&&cycles>=read_due)begin
    read_result_valid<=1;read_result_slot<=saved_read_slot;read_result_status<=saved_read_status;
    for(b=0;b<256;b=b+1)begin
     if(b<64*((saved_read_address%64+4*(saved_read_length+1)+63)/64))read_result_data[b*8+:8]<=memory[(saved_read_address/64)*64+b];
     else read_result_data[b*8+:8]<=8'hd7;
    end
   end
   if(write_pending&&!write_applied&&cycles>=write_due)begin
    for(b=0;b<256;b=b+1)if(saved_be[b])memory[b]<=saved_data[(b-(saved_write_address/64)*64)*8+:8];
    write_applied<=1;write_executed<=1;write_execute_slot<=saved_write_slot;execution_count<=execution_count+1;
    write_result_valid<=1;write_result_slot<=saved_write_slot;
   end
   if(read_valid&&read_ready)begin read_pending<=1;saved_read_slot<=read_slot;saved_read_address<=read_address;saved_read_length<=read_length;saved_read_status<=read_status;read_due<=cycles+9;end
   if(write_valid&&write_ready)begin
    write_pending<=1;write_applied<=0;saved_write_slot<=write_slot;saved_write_address<=write_address;saved_data<=write_data;saved_be<=write_be;write_due<=cycles+17;
   end
  end
 end
endmodule
