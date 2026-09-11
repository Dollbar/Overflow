`timescale 1ns/1ps
module tb;
parameter RESET_STAGE=1,BANK_DEPTH=3,FAULT=0,PARTIAL_BEATS=1;localparam COUNT=4;
reg clk=0;always #5 clk=~clk;reg rstn=0,power_rstn=0,start=0,allow_requests=0,inflight_reset=0;integer epoch=0;
integer all_requested=0,all_completed=0,all_read_results=0,all_write_results=0,reset_edges=0,held_cycles=0,old_beats0=0,old_beats1=0;
integer cycle=0,quiet=0,e,j,k,idx,expected_index,nbytes;
integer requested[0:1],completed[0:1],cursor[0:1],max_count[0:1];
integer memory_issue[0:1];
integer response_beats[0:1][0:COUNT-1],last_response_at[0:1][0:COUNT-1];
reg [95:0] descriptors[0:4*COUNT-1];reg [2047:0] payloads[0:4*COUNT-1];
reg [255:0] byte_enables[0:4*COUNT-1],expected_masks[0:4*COUNT-1];reg [2047:0] expected_data[0:4*COUNT-1],expected_raw[0:4*COUNT-1];
reg [255:0] memory_masks[0:4*COUNT-1];reg [3:0] statuses[0:4*COUNT-1],num_beats[0:4*COUNT-1];
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
wire [2047:0] memory_snapshot[0:1];reg [2047:0] retained_memory[0:1];
wire fabric_error;wire [1:0] sv,sr,ov,orr,sl,se;wire [1089:0] sd,od;
reg rv[0:1],rc[0:1];reg [543:0] rd[0:1];
wire [511:0] observed_tx[0:1];wire [1:0] observed_ht[0:1];wire [7:0] request_starts[0:1];
ualink_switch_top #(.PORTS(2),.DATA_WIDTH(545)) sw(.clk(clk),.rstn(rstn),.i_route_ids({10'd513,10'd17}),.i_port_enable(2'b11),
.i_valid(sv),.o_ready(sr),.i_data(sd),.i_dst({10'd17,10'd513}),.i_last(2'b11),.o_valid(ov),.i_ready(orr),.o_data(od),.o_last(sl),.o_route_error(se),.o_fabric_error(fabric_error));
genvar s;generate for(s=0;s<2;s=s+1)begin:ends
 wire [95:0] candidate=descriptors[epoch*2*COUNT+s*COUNT+((requested[s]<COUNT)?requested[s]:0)];
 assign request_valid[s]=rstn&&allow_requests&&done[s]&&peer_done[s]&&requested[s]<(epoch?COUNT:2);
 assign request_tag[s]=candidate[91:81];assign request_address[s]=candidate[80:24];
 assign complete_ready[s]=allow_requests&&(epoch==1||complete_write[s])&&(cycle%7!=s+1);
 read_reset_memory memory_bfm(
 .clk(clk),.rstn((FAULT==2&&s==0)?power_rstn:rstn),.read_valid(mem_valid[s]),.read_ready(mem_ready[s]),.read_slot(mem_slot[s]),.read_address(mem_address[s]),.read_length(mem_length[s]),
 .read_status(statuses[epoch*2*COUNT+(1-s)*COUNT+((memory_issue[s]<COUNT)?memory_issue[s]:0)]),
 .read_result_valid(result_valid[s]),.read_result_ready(result_ready[s]),.read_result_slot(result_slot[s]),.read_result_data(result_full[s]),.read_result_status(result_status[s]),
 .write_valid(write_valid[s]),.write_ready(write_ready[s]),.write_slot(write_slot[s]),.write_address(write_address[s]),
 .write_data(write_data[s]),.write_be(write_be[s]),
 .write_result_valid(write_result_valid[s]),.write_result_ready(write_result_ready[s]),.write_result_slot(write_result_slot[s]),
 .write_executed(write_executed[s]),.write_execute_slot(write_execute_slot[s]),.execution_count(execution_count[s]),.snapshot(memory_snapshot[s]));
 assign result_data[s]=result_full[s][511:0];
 assign sv[s]=link_valid[s];assign sd[s*545+:545]={1'b1,link_data[s]};
 assign link_ready[s]=sr[s];assign orr[s]=rstn&&(cycle%7!=s+1);
 ualink_endpoint_top #(.TRANSACTION_MODE(1),.WRITE_ENABLE(1),.FULL_READ_ENABLE(1),.WIDTH(8),.HEADER_DEPTH(2),.BANK_DEPTH(BANK_DEPTH),.RX_DEPTH(160),.DL_DEPTH(3)) dut(
 .i_clk(clk),.i_rstn((FAULT==1&&s==0)?power_rstn:rstn),.i_link_reset(1'b0),.i_start(start),.i_auth(1'b0),.i_shared(1'b0),.i_capacities({20{8'd4}}),
 .i_source_valid(2'd0),.i_source_control(512'd0),.i_source_tags_valid(2'd0),.i_source_tags(1024'd0),.i_data_valid(4'd0),.i_data0(512'd0),.i_data1(512'd0),.i_read_ready(1'b0),
 .i_port(2'd0),.i_local_id(s==0?10'd17:10'd513),.i_request_valid(request_valid[s]),.o_request_ready(request_ready[s]),.i_request_port(2'd0),
 .i_request_tag(request_tag[s]),.i_request_address(request_address[s]),.i_request_dst(s==0?10'd513:10'd17),.i_request_length(candidate[23:18]),.i_request_attr(candidate[17:10]),
 .o_complete_valid(complete_valid[s]),.i_complete_ready(complete_ready[s]),.o_complete_port(complete_port[s]),.o_complete_tag(complete_tag[s]),
 .o_complete_status(complete_status[s]),.o_complete_data(complete_data[s]),.o_complete_data_valid(complete_data_valid[s]),.o_complete_data_full(complete_full[s]),.o_complete_mask(complete_mask[s]),
 .o_mem_valid(mem_valid[s]),.i_mem_ready(mem_ready[s]),.o_mem_slot(mem_slot[s]),.o_mem_address(mem_address[s]),.o_mem_length(mem_length[s]),.o_mem_attr(mem_attr[s]),.o_mem_asi(mem_asi[s]),.o_mem_metadata(mem_metadata[s]),.o_mem_be(mem_be[s]),
 .i_mem_result_valid(result_valid[s]),.o_mem_result_ready(result_ready[s]),.i_mem_result_slot(result_slot[s]),.i_mem_result_data(result_data[s]),.i_mem_result_data_full(result_full[s]),.i_mem_result_status(result_status[s]),
 .i_request_is_write(candidate[93]),.i_request_full(candidate[92]),.i_request_asi(candidate[9:8]),.i_request_metadata(candidate[7:0]),
 .i_request_data(payloads[epoch*2*COUNT+s*COUNT+((requested[s]<COUNT)?requested[s]:0)]),.i_request_be(byte_enables[epoch*2*COUNT+s*COUNT+((requested[s]<COUNT)?requested[s]:0)]),
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
function integer tag_index;
 input integer side;input [10:0] tag;integer scan;
 begin
  tag_index=-1;
  for(scan=0;scan<(epoch?COUNT:2);scan=scan+1)
   if(descriptors[epoch*2*COUNT+side*COUNT+scan][91:81]==tag)tag_index=scan;
 end
endfunction
initial begin
 $readmemh("descriptors.hex",descriptors);$readmemh("payloads.hex",payloads);$readmemh("byte_enables.hex",byte_enables);
 $readmemh("expected_masks.hex",expected_masks);$readmemh("expected_data.hex",expected_data);$readmemh("expected_raw.hex",expected_raw);
 $readmemh("memory_masks.hex",memory_masks);$readmemh("statuses.hex",statuses);$readmemh("num_beats.hex",num_beats);$readmemh("retained_memory.hex",retained_memory);
 repeat(3)@(negedge clk);power_rstn=1;rstn=1;start=1;allow_requests=1;@(negedge clk);start=0;
 if(RESET_STAGE==1)wait(cursor[0]==2&&cursor[1]==2&&returns[0][1]==0&&returns[1][1]==0&&seen[0][0]&&seen[1][0]);
 if(RESET_STAGE==2)wait(response_beats[0][1]==PARTIAL_BEATS&&response_beats[1][1]==PARTIAL_BEATS);
 if(RESET_STAGE==3)wait(held_cycles>=8);
 @(negedge clk);
 if(all_completed!=2||!seen[0][0]||!seen[1][0]||execution_count[0]!=1||execution_count[1]!=1)$fatal(1,"READ_RESET_TARGET_SEED_WRITE");
 if(RESET_STAGE==1&&(cursor[0]!=2||cursor[1]!=2||returns[0][1]!=0||returns[1][1]!=0||response_beats[0][1]!=0||response_beats[1][1]!=0))$fatal(1,"READ_RESET_TARGET_BACKEND_PENDING");
 if(RESET_STAGE==2&&(PARTIAL_BEATS<1||PARTIAL_BEATS>3||response_beats[0][1]!=PARTIAL_BEATS||response_beats[1][1]!=PARTIAL_BEATS||complete_valid[0]||complete_valid[1]))$fatal(1,"READ_RESET_TARGET_PARTIAL");
 if(RESET_STAGE==3&&(!complete_valid[0]||!complete_valid[1]||complete_write[0]||complete_write[1]||response_beats[0][1]!=4||response_beats[1][1]!=4))$fatal(1,"READ_RESET_TARGET_COMPLETE");
 old_beats0=response_beats[0][1];old_beats1=response_beats[1][1];
 $display("READ_RESET_TARGET stage=%0d cycle=%0d backend=%0d,%0d read_results=%0d,%0d response_beats=%0d,%0d held=%0d",RESET_STAGE,cycle,cursor[0],cursor[1],returns[0][1],returns[1][1],old_beats0,old_beats1,held_cycles);
 inflight_reset=1;allow_requests=0;rstn=0;repeat(3)@(negedge clk);epoch=1;rstn=1;
 // Longer than the actual saved Read's 70-cycle latency; stale backend results cannot hide until tag reuse.
 repeat(120)@(negedge clk);
 $display("READ_RESET_QUIET_PASS stage=%0d cycle=%0d",RESET_STAGE,cycle);
 start=1;allow_requests=1;@(negedge clk);start=0;
end
always @(posedge clk)begin
 cycle<=cycle+1; // NBA keeps ready/backpressure inputs stable through the sampling edge.
 if(cycle>5000)$fatal(1,"READ_RESET_TIMEOUT app=%d,%d cursor=%d,%d complete=%d,%d",requested[0],requested[1],cursor[0],cursor[1],completed[0],completed[1]);
 if(!rstn)begin
  reset_edges=reset_edges+1;quiet=0;held_cycles=0;
  for(e=0;e<2;e=e+1)begin
   requested[e]<=0;memory_issue[e]<=0;completed[e]=0;cursor[e]=0;max_count[e]=0;
   rv[e]<=0;rd[e]<=0;rc[e]<=1;complete_held[e]=0;
   for(j=0;j<COUNT;j=j+1)begin sent[e][j]=0;returns[e][j]=0;result_at[e][j]=-1;seen[e][j]=0;executions[e][j]=0;response_beats[e][j]=0;last_response_at[e][j]=-1;end
   for(j=0;j<4;j=j+1)begin read_active[e][j]=0;write_active[e][j]=0;read_owner[e][j]=-1;write_owner[e][j]=-1;memory_at[e][j]=-1;end
  end
  #1;
  for(e=0;e<2;e=e+1)begin
   if(origin_count[e]!==0||completer_count[e]!==0||write_count[e]!==0||complete_valid[e]!==0||mem_valid[e]!==0||write_valid[e]!==0||result_valid[e]!==0||write_result_valid[e]!==0||unacked[e]!==0||scheduled[e]!==0||link_valid[e]!==0)$fatal(1,"READ_RESET_STATE side=%0d",e);
   if(memory_snapshot[e]!==(inflight_reset?retained_memory[e]:2048'd0))$fatal(1,"READ_RESET_MEMORY_ROLLBACK");
  end
  if(ov!==0)$fatal(1,"READ_RESET_SWITCH_STATE");
 end else begin
  if((|se)||fabric_error)$fatal(1,"READ_RESET_ROUTE_ERROR");
  for(e=0;e<2;e=e+1)begin
   if((result_valid[e]&&!read_active[e][result_slot[e]])||(write_result_valid[e]&&!write_active[e][write_result_slot[e]])||(write_executed[e]&&!write_active[e][write_execute_slot[e]]))$fatal(1,"READ_RESET_OLD_BACKEND side=%0d",e);
   if(epoch==0&&execution_count[e]==0&&memory_snapshot[e]!==2048'd0)$fatal(1,"READ_RESET_PREMATURE_WRITE");
   if(epoch==1&&!allow_requests&&(complete_valid[e]||mem_valid[e]||write_valid[e]||origin_count[e]||completer_count[e]||write_count[e]||response_fire[e]||memory_snapshot[e]!==retained_memory[e]))$fatal(1,"READ_RESET_QUIET_LEAK");
   if(error[e]||te[e])$fatal(1,"READ_RESET_DUT_ERROR cycle=%0d side=%0d transaction=%b",cycle,e,te[e]);
   rv[e]<=ov[e]&&orr[e];if(ov[e]&&orr[e])begin rd[e]<=od[e*545+:544];rc[e]<=od[e*545+544];end
   if((write_valid[e]&&write_ready[e])||(mem_valid[e]&&mem_ready[e]))memory_issue[e]<=memory_issue[e]+1;
   if(origin_count[e]>4||write_count[e]>4||completer_count[e]>4)$fatal(1,"READ_RESET_CAPACITY");
   if(origin_count[e]>max_count[e])max_count[e]=origin_count[e];
   if(request_valid[e]&&request_ready[e])begin all_requested=all_requested+1;$display("READ_RESET_APP epoch=%0d cycle=%0d side=%0d index=%0d write=%0d",epoch,cycle,e,requested[e],descriptors[epoch*2*COUNT+e*COUNT+requested[e]][93]);requested[e]<=requested[e]+1;end
   if(observed_ht[e][0])for(k=0;k<8;k=k+1)if(request_starts[e][k])begin
    idx=tag_index(e,observed_tx[e][k*32+103+:11]);
    if(idx<0||idx>=(epoch?COUNT:2)||sent[e][idx]!=0||idx>=requested[e])$fatal(1,"READ_RESET_SEND_IDENTITY");
    if({observed_tx[e][k*32+25+:55],2'b00}!==descriptors[epoch*2*COUNT+e*COUNT+idx][80:24])$fatal(1,"READ_RESET_SEND_ADDRESS");
    sent[e][idx]=1;
   end
   if(write_valid[e]&&write_ready[e])begin
    idx=cursor[e];expected_index=epoch*2*COUNT+(1-e)*COUNT+idx;
    if(idx>=(epoch?COUNT:2)||!descriptors[expected_index][93]||sent[1-e][idx]!=1||write_active[e][write_slot[e]])$fatal(1,"READ_RESET_WRITE_ORDER");
    if(write_address[e]!==descriptors[expected_index][80:24]||write_length[e]!==descriptors[expected_index][23:18]||write_attr[e]!==descriptors[expected_index][17:10]||write_asi[e]!==descriptors[expected_index][9:8]||write_metadata[e]!==descriptors[expected_index][7:0]||write_be[e]!==memory_masks[expected_index])$fatal(1,"READ_RESET_WRITE_FIELDS side=%0d index=%0d address=%h len=%d be=%h expected=%h",e,idx,write_address[e],write_length[e],write_be[e],memory_masks[expected_index]);
    nbytes=64*((write_address[e]%64+4*(write_length[e]+1)+63)/64);
    for(j=0;j<nbytes;j=j+1)if(write_data[e][j*8+:8]!==payloads[expected_index][j*8+:8])$fatal(1,"READ_RESET_WRITE_DATA side=%0d index=%0d byte=%0d",e,idx,j);
    write_active[e][write_slot[e]]=1;write_owner[e][write_slot[e]]=idx;memory_at[e][write_slot[e]]=cycle;cursor[e]=cursor[e]+1;
    $display("READ_RESET_MEMORY_WRITE epoch=%0d cycle=%0d side=%0d index=%0d slot=%0d",epoch,cycle,e,idx,write_slot[e]);
   end
   if(mem_valid[e]&&mem_ready[e])begin
    idx=cursor[e];expected_index=epoch*2*COUNT+(1-e)*COUNT+idx;
    if(idx>=(epoch?COUNT:2)||descriptors[expected_index][93]||sent[1-e][idx]!=1||read_active[e][mem_slot[e]])$fatal(1,"READ_RESET_READ_ORDER");
    if(mem_address[e]!==descriptors[expected_index][80:24]||mem_length[e]!==descriptors[expected_index][23:18]||mem_attr[e]!==descriptors[expected_index][17:10]||mem_asi[e]!==descriptors[expected_index][9:8]||mem_metadata[e]!==descriptors[expected_index][7:0]||mem_be[e]!==memory_masks[expected_index])$fatal(1,"READ_RESET_READ_FIELDS");
    $display("READ_RESET_MEMORY_READ epoch=%0d cycle=%0d side=%0d index=%0d slot=%0d",epoch,cycle,e,idx,mem_slot[e]);
    read_active[e][mem_slot[e]]=1;read_owner[e][mem_slot[e]]=idx;memory_at[e][mem_slot[e]]=cycle;cursor[e]=cursor[e]+1;
   end
   if(write_executed[e])begin
    idx=write_owner[e][write_execute_slot[e]];
    if(!write_active[e][write_execute_slot[e]]||idx<0||executions[e][idx]!=0||memory_at[e][write_execute_slot[e]]>=cycle)$fatal(1,"READ_RESET_DUPLICATE_EXECUTION");
    executions[e][idx]=1;$display("READ_RESET_EXECUTE epoch=%0d cycle=%0d side=%0d index=%0d",epoch,cycle,e,idx);
   end
   if(write_result_valid[e]&&write_result_ready[e])begin
    all_write_results=all_write_results+1;
    idx=write_owner[e][write_result_slot[e]];
    if(idx<0||!write_active[e][write_result_slot[e]]||executions[e][idx]!=1||returns[e][idx]!=0)$fatal(1,"READ_RESET_EXECUTION_CAUSALITY side=%0d",e);
    returns[e][idx]=1;result_at[e][idx]=cycle;write_active[e][write_result_slot[e]]=0;
   end
   if(result_valid[e]&&result_ready[e])begin
    all_read_results=all_read_results+1;
    $display("READ_RESET_RESULT epoch=%0d cycle=%0d side=%0d slot=%0d",epoch,cycle,e,result_slot[e]);
    idx=read_owner[e][result_slot[e]];
    if(idx<0||!read_active[e][result_slot[e]]||returns[e][idx]!=0||memory_at[e][result_slot[e]]>=cycle)$fatal(1,"READ_RESET_READ_RESULT_CAUSALITY");
    if(result_full[e]!==expected_raw[epoch*2*COUNT+(1-e)*COUNT+idx]||result_status[e]!==statuses[epoch*2*COUNT+(1-e)*COUNT+idx])$fatal(1,"READ_RESET_READ_DATA side=%0d index=%0d",e,idx);
    returns[e][idx]=1;result_at[e][idx]=cycle;read_active[e][result_slot[e]]=0;
   end
   if(response_fire[e])begin
    idx=tag_index(e,response_tag[e]);expected_index=epoch*2*COUNT+e*COUNT+idx;
    if(idx<0||idx>=(epoch?COUNT:2)||sent[e][idx]!=1||returns[1-e][idx]!=1||result_at[1-e][idx]>=cycle||seen[e][idx]!=0)$fatal(1,"READ_RESET_RESPONSE_CAUSALITY side=%0d index=%0d",e,idx);
    if(response_write[e]!==descriptors[expected_index][93]||response_dst[e]!==(e==0?10'd17:10'd513)||response_status[e]!==statuses[expected_index]||response_port[e]!==0||response_error[e]||response_length[e]!==0)$fatal(1,"READ_RESET_RESPONSE_IDENTITY");
    if(response_write[e])begin
     if(response_beats[e][idx]!=0)$fatal(1,"READ_RESET_DUPLICATE_WRITE_RESPONSE");
    end else begin
     if(response_beats[e][idx]>=num_beats[expected_index]||response_offset[e]!==response_beats[e][idx][1:0]||response_last[e]!==((response_beats[e][idx]+1)==num_beats[expected_index]))$fatal(1,"READ_RESET_RESPONSE_BEAT side=%0d index=%0d offset=%0d seen=%0d last=%b",e,idx,response_offset[e],response_beats[e][idx],response_last[e]);
     // Compare selected bytes only here; the application full result must also clear every unused byte.
     for(j=0;j<64;j=j+1)if(statuses[expected_index]==0&&expected_masks[expected_index][response_offset[e]*64+j])
      if(response_data[e][j*8+:8]!==expected_data[expected_index][(response_offset[e]*64+j)*8+:8])$fatal(1,"READ_RESET_COMPLETE_DATA response side=%0d index=%0d",e,idx);
    end
    $display("READ_RESET_RESPONSE epoch=%0d cycle=%0d side=%0d tag=%0d write=%b offset=%0d last=%b",epoch,cycle,e,response_tag[e],response_write[e],response_offset[e],response_last[e]);
    response_beats[e][idx]=response_beats[e][idx]+1;last_response_at[e][idx]=cycle;
   end
   if(complete_held[e]&&held_value[e]!=={complete_valid[e],complete_write[e],complete_port[e],complete_tag[e],complete_status[e],complete_data_valid[e],complete_data[e],complete_full[e],complete_mask[e]})$fatal(1,"READ_RESET_COMPLETE_STABILITY");
   complete_held[e]=complete_valid[e]&&!complete_ready[e];held_value[e]={complete_valid[e],complete_write[e],complete_port[e],complete_tag[e],complete_status[e],complete_data_valid[e],complete_data[e],complete_full[e],complete_mask[e]};
   if(complete_valid[e])begin
    idx=tag_index(e,complete_tag[e]);expected_index=epoch*2*COUNT+e*COUNT+idx;
    if(idx<0||idx>=(epoch?COUNT:2)||seen[e][idx]!=0||sent[e][idx]!=1||returns[1-e][idx]!=1||result_at[1-e][idx]>=cycle||last_response_at[e][idx]>=cycle||response_beats[e][idx]!=(descriptors[expected_index][93]?1:num_beats[expected_index]))$fatal(1,"READ_RESET_EARLY_COMPLETE");
    if(complete_write[e]!==descriptors[expected_index][93]||complete_port[e]!==0||complete_status[e]!==statuses[expected_index]||complete_data_valid[e]!==(!descriptors[expected_index][93]&&statuses[expected_index]==0)||complete_data[e]!==expected_data[expected_index][511:0]||complete_full[e]!==expected_data[expected_index]||complete_mask[e]!==expected_masks[expected_index])$fatal(1,"READ_RESET_COMPLETE_DATA side=%0d index=%0d",e,idx);
    if(complete_ready[e])begin if(epoch==0&&!complete_write[e])$fatal(1,"READ_RESET_OLD_EPOCH_RETIRED");all_completed=all_completed+1;seen[e][idx]=1;completed[e]=completed[e]+1;$display("READ_RESET_COMPLETE epoch=%0d cycle=%0d side=%0d index=%0d",epoch,cycle,e,idx);end
   end
  end
  if(complete_valid[0]&&complete_valid[1]&&!complete_write[0]&&!complete_write[1]&&!complete_ready[0]&&!complete_ready[1])held_cycles=held_cycles+1;else held_cycles=0;
  if(epoch==1&&completed[0]==COUNT&&completed[1]==COUNT&&origin_count[0]==0&&origin_count[1]==0&&completer_count[0]==0&&completer_count[1]==0&&write_count[0]==0&&write_count[1]==0&&unacked[0]==0&&unacked[1]==0&&scheduled[0]==0&&scheduled[1]==0)quiet=quiet+1;else quiet=0;
  if(quiet==80)begin
   if(all_requested!=12||all_completed!=10||reset_edges!=6||all_write_results!=2||all_read_results!=(8+2*(RESET_STAGE!=1))||execution_count[0]!=1||execution_count[1]!=1||cursor[0]!=COUNT||cursor[1]!=COUNT||max_count[0]!=4||max_count[1]!=4)$fatal(1,"READ_RESET_COVERAGE");
   for(e=0;e<2;e=e+1)begin
    if(memory_snapshot[e]!==retained_memory[e])$fatal(1,"READ_RESET_FINAL_MEMORY");
    for(j=0;j<COUNT;j=j+1)if(returns[e][j]!=1||sent[e][j]!=1||seen[e][j]!=1||response_beats[e][j]!=num_beats[2*COUNT+e*COUNT+j])$fatal(1,"READ_RESET_FINAL_OWNERSHIP");
   end
   $display("READ_RESET_PASS stage=%0d old_write_completed=2 old_read_cancelled=2 new_read_completed=8 old_beats=%0d,%0d new_read_beats=22 backend_read_results=%0d cycles=%0d",RESET_STAGE,old_beats0,old_beats1,all_read_results,cycle);$finish;
  end
 end
end
endmodule

// Simulation-only byte memory. It consumes actual commands/data/BE, holds delayed results,
// and never reads expected-data fixtures. Unused return lanes are deliberately nonzero.
module read_reset_memory(
 input wire clk,rstn,
 input wire read_valid,output wire read_ready,input wire [1:0] read_slot,input wire [56:0] read_address,
 input wire [5:0] read_length,input wire [3:0] read_status,
 output reg read_result_valid,input wire read_result_ready,output reg [1:0] read_result_slot,
 output reg [2047:0] read_result_data,output reg [3:0] read_result_status,
 input wire write_valid,output wire write_ready,input wire [1:0] write_slot,input wire [56:0] write_address,
 input wire [2047:0] write_data,input wire [255:0] write_be,
 output reg write_result_valid,input wire write_result_ready,output reg [1:0] write_result_slot,
 output reg write_executed,output reg [1:0] write_execute_slot,output reg [31:0] execution_count,output wire [2047:0] snapshot
);
 reg [7:0] memory[0:255];reg read_pending,write_pending,write_applied;
 reg [1:0] saved_read_slot,saved_write_slot;reg [56:0] saved_read_address,saved_write_address;
 reg [2047:0] saved_data;reg [255:0] saved_be;reg [5:0] saved_read_length;reg [3:0] saved_read_status;
 integer cycles,read_due,write_due,b,init_byte;
 // Actual byte memory survives uniform network reset; only pending ownership/results are cancelled.
 initial begin execution_count=0;for(init_byte=0;init_byte<256;init_byte=init_byte+1)memory[init_byte]=0;end
 genvar byte_lane;generate for(byte_lane=0;byte_lane<256;byte_lane=byte_lane+1)begin:observe_memory
  assign snapshot[byte_lane*8+:8]=memory[byte_lane];
 end endgenerate
 assign read_ready=rstn&&!read_pending&&(cycles%5!=1);
 assign write_ready=rstn&&!write_pending&&(cycles%7!=2);
 always @(posedge clk)begin
  if(!rstn)begin
   cycles<=0;read_pending<=0;write_pending<=0;write_applied<=0;read_result_valid<=0;write_result_valid<=0;write_executed<=0;
   read_result_slot<=0;read_result_data<=0;read_result_status<=0;write_result_slot<=0;write_execute_slot<=0;
   saved_read_slot<=0;saved_write_slot<=0;saved_read_address<=0;saved_write_address<=0;saved_data<=0;saved_be<=0;read_due<=0;write_due<=0;saved_read_length<=0;saved_read_status<=0;
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
   if(read_valid&&read_ready)begin read_pending<=1;saved_read_slot<=read_slot;saved_read_address<=read_address;saved_read_length<=read_length;saved_read_status<=read_status;read_due<=cycles+70;end
   if(write_valid&&write_ready)begin
    write_pending<=1;write_applied<=0;saved_write_slot<=write_slot;saved_write_address<=write_address;saved_data<=write_data;saved_be<=write_be;write_due<=cycles+17;
   end
  end
 end
endmodule
