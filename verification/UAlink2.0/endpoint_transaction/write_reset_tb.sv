`timescale 1ns/1ps
module tb;
parameter RESET_STAGE=1,BANK_DEPTH=3,FAULT=0;localparam COUNT=9;
reg clk=0;always #5 clk=~clk;reg rstn=0,power_rstn=0,start=0,allow_requests=0,inflight_reset=0;integer epoch=0;
integer cycle=0,quiet=0,e,j,k,idx,expected_index,nbytes;integer all_requested=0,all_completed=0,reset_edges=0,held_cycles=0;
integer requested[0:1],completed[0:1],cursor[0:1],max_count[0:1];
integer rx_data_halves[0:1],rx_be_halves[0:1];
reg [95:0] descriptors[0:4*COUNT-1];reg [2047:0] payloads[0:4*COUNT-1];
reg [255:0] byte_enables[0:4*COUNT-1],expected_masks[0:4*COUNT-1];reg [511:0] expected_reads[0:4*COUNT-1];
integer sent[0:1][0:COUNT-1],returns[0:1][0:COUNT-1],result_at[0:1][0:COUNT-1],seen[0:1][0:COUNT-1],executions[0:1][0:COUNT-1];
integer read_owner[0:1][0:3],write_owner[0:1][0:3],memory_at[0:1][0:3];
reg read_active[0:1][0:3],write_active[0:1][0:3],complete_held[0:1];reg [531:0] held_value[0:1];
wire done[0:1],peer_done[0:1],error[0:1],te[0:1],request_valid[0:1],request_ready[0:1];
wire [10:0] request_tag[0:1];wire [56:0] request_address[0:1];
wire complete_valid[0:1],complete_ready[0:1],complete_data_valid[0:1],complete_write[0:1];
wire [1:0] complete_port[0:1];wire [10:0] complete_tag[0:1];wire [3:0] complete_status[0:1];wire [511:0] complete_data[0:1];
wire [7:0] origin_count[0:1],completer_count[0:1],write_count[0:1],unacked[0:1],scheduled[0:1];
wire mem_valid[0:1],mem_ready[0:1],result_ready[0:1];wire [1:0] mem_slot[0:1];wire [56:0] mem_address[0:1];
wire [5:0] mem_length[0:1];wire [7:0] mem_attr[0:1],mem_metadata[0:1];wire [1:0] mem_asi[0:1];
wire result_valid[0:1];wire [1:0] result_slot[0:1];wire [3:0] result_status[0:1];wire [511:0] result_data[0:1];
wire write_valid[0:1],write_ready[0:1],write_result_valid[0:1],write_result_ready[0:1],write_executed[0:1];
wire [1:0] write_slot[0:1],write_result_slot[0:1],write_execute_slot[0:1];wire [56:0] write_address[0:1];
wire [5:0] write_length[0:1];wire [7:0] write_attr[0:1],write_metadata[0:1];wire [1:0] write_asi[0:1];
wire [2047:0] write_data[0:1];wire [255:0] write_be[0:1];wire [31:0] execution_count[0:1];
wire link_valid[0:1],link_ready[0:1],link_payload[0:1],link_replay[0:1];wire [543:0] link_data[0:1];
wire [1:0] sv,sr,ov,orr,sl,se;wire [1089:0] sd,od;
reg rv[0:1],rc[0:1];reg [543:0] rd[0:1];
wire [511:0] observed_tx[0:1];wire [1:0] observed_ht[0:1];wire [7:0] request_starts[0:1];
wire observed_rx_valid[0:1],observed_rx_ready[0:1];wire [5:0] observed_rx_classes[0:1];
wire [2047:0] memory_snapshot[0:1];reg [2047:0] retained_memory[0:1];
ualink_switch_top #(.PORTS(2),.DATA_WIDTH(545)) sw(.clk(clk),.rstn(rstn),.i_route_ids({10'd513,10'd17}),.i_port_enable(2'b11),
.i_valid(sv),.o_ready(sr),.i_data(sd),.i_dst({10'd17,10'd513}),.i_last(2'b11),.o_valid(ov),.i_ready(orr),.o_data(od),.o_last(sl),.o_route_error(se));
genvar s;generate for(s=0;s<2;s=s+1)begin:ends
 wire [95:0] candidate=descriptors[epoch*2*COUNT+s*COUNT+((requested[s]<COUNT)?requested[s]:0)];
 assign request_valid[s]=rstn&&allow_requests&&done[s]&&peer_done[s]&&requested[s]<(epoch?COUNT:1);
 assign request_tag[s]=candidate[91:81];assign request_address[s]=candidate[80:24];
 assign complete_ready[s]=epoch==1&&allow_requests&&(cycle%7!=s+1);
 write_reset_memory memory_bfm(
 .clk(clk),.rstn((FAULT==2&&s==0)?power_rstn:rstn),.read_valid(mem_valid[s]),.read_ready(mem_ready[s]),.read_slot(mem_slot[s]),.read_address(mem_address[s]),
 .read_result_valid(result_valid[s]),.read_result_ready(result_ready[s]),.read_result_slot(result_slot[s]),.read_result_data(result_data[s]),
 .write_valid(write_valid[s]),.write_ready(write_ready[s]),.write_slot(write_slot[s]),.write_address(write_address[s]),
 .write_data(write_data[s]),.write_be(write_be[s]),
 .write_result_valid(write_result_valid[s]),.write_result_ready(write_result_ready[s]),.write_result_slot(write_result_slot[s]),
 .write_executed(write_executed[s]),.write_execute_slot(write_execute_slot[s]),.execution_count(execution_count[s]),.snapshot(memory_snapshot[s]));
 assign result_status[s]=4'd0;
 assign sv[s]=link_valid[s];assign sd[s*545+:545]={1'b1,link_data[s]};
 assign link_ready[s]=sr[s];assign orr[s]=rstn&&(cycle%7!=s+1);
 ualink_endpoint_top #(.TRANSACTION_MODE(1),.WRITE_ENABLE(1),.WIDTH(8),.HEADER_DEPTH(2),.BANK_DEPTH(BANK_DEPTH),.RX_DEPTH(160),.DL_DEPTH(3)) dut(
 .i_clk(clk),.i_rstn((FAULT==1&&s==0)?power_rstn:rstn),.i_link_reset(1'b0),.i_start(start),.i_auth(1'b0),.i_shared(1'b0),.i_capacities({20{8'd4}}),
 .i_source_valid(2'd0),.i_source_control(512'd0),.i_source_tags_valid(2'd0),.i_source_tags(1024'd0),.i_data_valid(4'd0),.i_data0(512'd0),.i_data1(512'd0),.i_read_ready(1'b0),
 .i_port(2'd0),.i_local_id(s==0?10'd17:10'd513),.i_request_valid(request_valid[s]),.o_request_ready(request_ready[s]),.i_request_port(2'd0),
 .i_request_tag(request_tag[s]),.i_request_address(request_address[s]),.i_request_dst(s==0?10'd513:10'd17),.i_request_length(candidate[23:18]),.i_request_attr(candidate[17:10]),
 .o_complete_valid(complete_valid[s]),.i_complete_ready(complete_ready[s]),.o_complete_port(complete_port[s]),.o_complete_tag(complete_tag[s]),
 .o_complete_status(complete_status[s]),.o_complete_data(complete_data[s]),.o_complete_data_valid(complete_data_valid[s]),
 .o_mem_valid(mem_valid[s]),.i_mem_ready(mem_ready[s]),.o_mem_slot(mem_slot[s]),.o_mem_address(mem_address[s]),.o_mem_length(mem_length[s]),.o_mem_attr(mem_attr[s]),.o_mem_asi(mem_asi[s]),.o_mem_metadata(mem_metadata[s]),
 .i_mem_result_valid(result_valid[s]),.o_mem_result_ready(result_ready[s]),.i_mem_result_slot(result_slot[s]),.i_mem_result_data(result_data[s]),.i_mem_result_status(result_status[s]),
 .i_request_is_write(candidate[93]),.i_request_full(candidate[92]),.i_request_asi(candidate[9:8]),.i_request_metadata(candidate[7:0]),
 .i_request_data(payloads[epoch*2*COUNT+s*COUNT+((requested[s]<COUNT)?requested[s]:0)]),.i_request_be(byte_enables[epoch*2*COUNT+s*COUNT+((requested[s]<COUNT)?requested[s]:0)]),
 .o_complete_is_write(complete_write[s]),
 .o_write_mem_valid(write_valid[s]),.i_write_mem_ready(write_ready[s]),.o_write_mem_slot(write_slot[s]),.o_write_mem_address(write_address[s]),
 .o_write_mem_length(write_length[s]),.o_write_mem_attr(write_attr[s]),.o_write_mem_asi(write_asi[s]),.o_write_mem_metadata(write_metadata[s]),
 .o_write_mem_data(write_data[s]),.o_write_mem_be(write_be[s]),.i_write_mem_result_valid(write_result_valid[s]),.o_write_mem_result_ready(write_result_ready[s]),
 .i_write_mem_result_slot(write_result_slot[s]),.i_write_mem_result_status(4'd0),.o_write_completer_count(write_count[s]),
 .o_read_valid(observed_rx_valid[s]),.o_read_classes(observed_rx_classes[s]),.o_outstanding_count(origin_count[s]),.o_completer_count(completer_count[s]),.o_transaction_error(te[s]),
 .o_link_valid(link_valid[s]),.o_link_data(link_data[s]),.i_link_ready(link_ready[s]),.o_link_payload(link_payload[s]),.o_link_replay(link_replay[s]),
 .i_link_valid(rv[s]),.i_link_data(rd[s]),.i_link_crc_ok(rc[s]),.i_rx_replay_limit(8'd50),
 .o_done(done[s]),.o_peer_done(peer_done[s]),.o_error(error[s]),.o_unacked_count(unacked[s]),.o_scheduled_count(scheduled[s]));
 assign observed_rx_ready[s]=dut.transactions.u_core.o_read_ready;
 assign observed_tx[s]=dut.u_tx.o_flit;assign observed_ht[s]=dut.u_tx.o_header_taken;
 tl_control_decode observe(.i_half(observed_tx[s][255:0]),.o_request_starts(request_starts[s]));
end endgenerate
function integer tag_index;
 input integer side;input [10:0] value;integer scan;
 begin
  tag_index=-1;
  for(scan=0;scan<(epoch?COUNT:1);scan=scan+1)
   if(descriptors[epoch*2*COUNT+side*COUNT+scan][91:81]==value)tag_index=scan;
 end
endfunction
initial begin
 $readmemh("descriptors.hex",descriptors);$readmemh("payloads.hex",payloads);$readmemh("byte_enables.hex",byte_enables);
 $readmemh("expected_masks.hex",expected_masks);$readmemh("expected_reads.hex",expected_reads);$readmemh("retained_memory.hex",retained_memory);
 repeat(3)@(negedge clk);power_rstn=1;rstn=1;start=1;allow_requests=1;@(negedge clk);start=0;
 if(RESET_STAGE==1)wait(rx_data_halves[0]>=2&&rx_data_halves[1]>=2&&rx_be_halves[0]==0&&rx_be_halves[1]==0);
 if(RESET_STAGE==2)wait(cursor[0]==1&&cursor[1]==1&&execution_count[0]==0&&execution_count[1]==0);
 if(RESET_STAGE==3)wait(held_cycles>=8);
 @(negedge clk);
 if(RESET_STAGE==1&&(rx_be_halves[0]!=0||rx_be_halves[1]!=0||rx_data_halves[0]>=8||rx_data_halves[1]>=8||cursor[0]!=0||cursor[1]!=0))$fatal(1,"WRITE_RESET_TARGET_PARTIAL");
 if(RESET_STAGE==2&&(execution_count[0]!=0||execution_count[1]!=0||cursor[0]!=1||cursor[1]!=1))$fatal(1,"WRITE_RESET_TARGET_PRE_EXECUTE");
 if(RESET_STAGE==3&&(!complete_valid[0]||!complete_valid[1]||execution_count[0]!=1||execution_count[1]!=1))$fatal(1,"WRITE_RESET_TARGET_EXECUTED");
 $display("WRITE_RESET_TARGET stage=%0d cycle=%0d data=%0d,%0d be=%0d,%0d backend=%0d,%0d executed=%0d,%0d held=%0d",RESET_STAGE,cycle,rx_data_halves[0],rx_data_halves[1],rx_be_halves[0],rx_be_halves[1],cursor[0],cursor[1],execution_count[0],execution_count[1],held_cycles);
 inflight_reset=1;allow_requests=0;rstn=0;repeat(3)@(negedge clk);epoch=1;rstn=1;
 // Longer than backend execution latency: stale pending work cannot hide behind new requests.
 repeat(120)@(negedge clk);
 $display("WRITE_RESET_QUIET_PASS stage=%0d cycle=%0d",RESET_STAGE,cycle);
 start=1;allow_requests=1;@(negedge clk);start=0;
end
always @(posedge clk)begin
 cycle<=cycle+1;
 if(cycle>4000)$fatal(1,"WRITE_RESET_TIMEOUT stage=%0d epoch=%0d app=%d,%d cursor=%d,%d complete=%d,%d",RESET_STAGE,epoch,requested[0],requested[1],cursor[0],cursor[1],completed[0],completed[1]);
 if(!rstn)begin
  reset_edges=reset_edges+1;quiet=0;held_cycles=0;
  for(e=0;e<2;e=e+1)begin
   requested[e]<=0;completed[e]=0;cursor[e]=0;max_count[e]=0;rx_data_halves[e]<=0;rx_be_halves[e]<=0;
   rv[e]<=0;rd[e]<=0;rc[e]<=1;complete_held[e]=0;
   for(j=0;j<COUNT;j=j+1)begin sent[e][j]=0;returns[e][j]=0;result_at[e][j]=-1;seen[e][j]=0;executions[e][j]=0;end
   for(j=0;j<4;j=j+1)begin read_active[e][j]=0;write_active[e][j]=0;read_owner[e][j]=-1;write_owner[e][j]=-1;memory_at[e][j]=-1;end
  end
  #1;
  for(e=0;e<2;e=e+1)begin
   if(origin_count[e]!==0||completer_count[e]!==0||write_count[e]!==0||complete_valid[e]!==0||mem_valid[e]!==0||write_valid[e]!==0||result_valid[e]!==0||write_result_valid[e]!==0||unacked[e]!==0||scheduled[e]!==0||link_valid[e]!==0)$fatal(1,"WRITE_RESET_STATE side=%0d",e);
   if(memory_snapshot[e]!==(inflight_reset?retained_memory[e]:2048'd0))$fatal(1,"WRITE_RESET_MEMORY_ROLLBACK");
  end
  if(ov!==0)$fatal(1,"WRITE_RESET_SWITCH_STATE");
 end else begin
  if(|se)$fatal(1,"WRITE_RESET_ROUTE_ERROR");
  for(e=0;e<2;e=e+1)begin
   if((write_executed[e]&&!write_active[e][write_execute_slot[e]])||(write_result_valid[e]&&!write_active[e][write_result_slot[e]]))$fatal(1,"WRITE_RESET_OLD_BACKEND side=%0d",e);
   if(error[e]||te[e])$fatal(1,"WRITE_RESET_DUT_ERROR cycle=%0d side=%0d",cycle,e);
   if(epoch==0&&execution_count[e]==0&&memory_snapshot[e]!==2048'd0)$fatal(1,"WRITE_RESET_PREMATURE_SIDE_EFFECT");
   if(epoch==1&&!allow_requests&&(complete_valid[e]||mem_valid[e]||write_valid[e]||origin_count[e]||completer_count[e]||write_count[e]||memory_snapshot[e]!==retained_memory[e]))$fatal(1,"WRITE_RESET_QUIET_LEAK");
   rv[e]<=ov[e]&&orr[e];if(ov[e]&&orr[e])begin rd[e]<=od[e*545+:544];rc[e]<=od[e*545+544];end
   if(observed_rx_valid[e]&&observed_rx_ready[e])begin
    rx_data_halves[e]<=rx_data_halves[e]+(observed_rx_classes[e][2:0]==1)+(observed_rx_classes[e][5:3]==1);
    rx_be_halves[e]<=rx_be_halves[e]+(observed_rx_classes[e][2:0]==2)+(observed_rx_classes[e][5:3]==2);
   end
   if(request_valid[e]&&request_ready[e])begin all_requested=all_requested+1;$display("WRITE_RESET_APP epoch=%0d cycle=%0d side=%0d index=%0d tag=%0d",epoch,cycle,e,requested[e],request_tag[e]);requested[e]<=requested[e]+1;end
   if(observed_ht[e][0])for(k=0;k<8;k=k+1)if(request_starts[e][k])begin
    idx=tag_index(e,observed_tx[e][k*32+103+:11]);
    if(idx<0||sent[e][idx]!=0||idx>=requested[e])$fatal(1,"WRITE_RESET_SEND_IDENTITY");
    if({observed_tx[e][k*32+25+:55],2'b00}!==descriptors[epoch*2*COUNT+e*COUNT+idx][80:24])$fatal(1,"WRITE_RESET_SEND_ADDRESS");
    sent[e][idx]=1;
   end
   if(write_valid[e]&&write_ready[e])begin
    idx=cursor[e];expected_index=epoch*2*COUNT+(1-e)*COUNT+idx;
    if(idx>=(epoch?COUNT:1)||!descriptors[expected_index][93]||sent[1-e][idx]!=1||write_active[e][write_slot[e]])$fatal(1,"WRITE_RESET_WRITE_ORDER");
    if(write_address[e]!==descriptors[expected_index][80:24]||write_length[e]!==63||write_attr[e]!==8'h81||write_asi[e]!==2||write_metadata[e]!==8'h5a||write_be[e]!==expected_masks[expected_index]||write_data[e]!==payloads[expected_index])$fatal(1,"WRITE_RESET_WRITE_FIELDS");
    write_active[e][write_slot[e]]=1;write_owner[e][write_slot[e]]=idx;memory_at[e][write_slot[e]]=cycle;cursor[e]=cursor[e]+1;
    $display("WRITE_RESET_COMMAND epoch=%0d cycle=%0d side=%0d slot=%0d",epoch,cycle,e,write_slot[e]);
   end
   if(mem_valid[e]&&mem_ready[e])begin
    idx=cursor[e];expected_index=epoch*2*COUNT+(1-e)*COUNT+idx;
    if(epoch==0||idx>=COUNT||descriptors[expected_index][93]||sent[1-e][idx]!=1||read_active[e][mem_slot[e]])$fatal(1,"WRITE_RESET_READ_ORDER");
    if(mem_address[e]!==descriptors[expected_index][80:24]||mem_length[e]!==15||mem_attr[e]!==255||mem_asi[e]!==0||mem_metadata[e]!==0)$fatal(1,"WRITE_RESET_READ_FIELDS");
    read_active[e][mem_slot[e]]=1;read_owner[e][mem_slot[e]]=idx;memory_at[e][mem_slot[e]]=cycle;cursor[e]=cursor[e]+1;
   end
   if(write_executed[e])begin
    idx=write_owner[e][write_execute_slot[e]];
    if(idx<0||executions[e][idx]!=0||memory_at[e][write_execute_slot[e]]>=cycle)$fatal(1,"WRITE_RESET_EXECUTION_CAUSALITY");
    executions[e][idx]=1;$display("WRITE_RESET_EXECUTE epoch=%0d cycle=%0d side=%0d index=%0d",epoch,cycle,e,idx);
   end
   if(write_result_valid[e]&&write_result_ready[e])begin
    idx=write_owner[e][write_result_slot[e]];
    if(idx<0||executions[e][idx]!=1||returns[e][idx]!=0)$fatal(1,"WRITE_RESET_RESULT_CAUSALITY");
    returns[e][idx]=1;result_at[e][idx]=cycle;write_active[e][write_result_slot[e]]=0;
   end
   if(result_valid[e]&&result_ready[e])begin
    idx=read_owner[e][result_slot[e]];
    if(idx<0||!read_active[e][result_slot[e]]||returns[e][idx]!=0||memory_at[e][result_slot[e]]>=cycle)$fatal(1,"WRITE_RESET_READ_CAUSALITY");
    if(result_data[e]!==expected_reads[epoch*2*COUNT+(1-e)*COUNT+idx])$fatal(1,"WRITE_RESET_RETAINED_READ_DATA side=%0d index=%0d",e,idx);
    returns[e][idx]=1;result_at[e][idx]=cycle;read_active[e][result_slot[e]]=0;
   end
   if(complete_held[e]&&held_value[e]!=={complete_valid[e],complete_write[e],complete_port[e],complete_tag[e],complete_status[e],complete_data_valid[e],complete_data[e]})$fatal(1,"WRITE_RESET_COMPLETE_STABILITY");
   complete_held[e]=complete_valid[e]&&!complete_ready[e];held_value[e]={complete_valid[e],complete_write[e],complete_port[e],complete_tag[e],complete_status[e],complete_data_valid[e],complete_data[e]};
   if(complete_valid[e])begin
    idx=tag_index(e,complete_tag[e]);expected_index=epoch*2*COUNT+e*COUNT+idx;
    if(idx<0||seen[e][idx]!=0||sent[e][idx]!=1||returns[1-e][idx]!=1||result_at[1-e][idx]>=cycle)$fatal(1,"WRITE_RESET_OLD_COMPLETE");
    if(complete_write[e]!==descriptors[expected_index][93]||complete_port[e]!==0||complete_status[e]!==0||complete_data_valid[e]!==!descriptors[expected_index][93]||complete_data[e]!==expected_reads[expected_index])$fatal(1,"WRITE_RESET_COMPLETE_DATA");
    if(complete_ready[e])begin
     if(epoch==0)$fatal(1,"WRITE_RESET_OLD_EPOCH_RETIRED");
     seen[e][idx]=1;completed[e]=completed[e]+1;all_completed=all_completed+1;$display("WRITE_RESET_COMPLETE epoch=%0d cycle=%0d side=%0d index=%0d",epoch,cycle,e,idx);
    end
   end
  end
  if(complete_valid[0]&&complete_valid[1]&&!complete_ready[0]&&!complete_ready[1])held_cycles=held_cycles+1;else held_cycles=0;
  if(epoch==1&&completed[0]==COUNT&&completed[1]==COUNT&&origin_count[0]==0&&origin_count[1]==0&&completer_count[0]==0&&completer_count[1]==0&&write_count[0]==0&&write_count[1]==0&&unacked[0]==0&&unacked[1]==0&&scheduled[0]==0&&scheduled[1]==0)quiet=quiet+1;else quiet=0;
  if(quiet==80)begin
   if(all_requested!=20||all_completed!=18||reset_edges!=6||execution_count[0]!=(1+(RESET_STAGE==3))||execution_count[1]!=(1+(RESET_STAGE==3))||executions[0][4]!=1||executions[1][4]!=1)$fatal(1,"WRITE_RESET_COVERAGE");
   $display("WRITE_RESET_PASS stage=%0d requests_old=2 requests_new=18 completed_old=0 completed_new=18 writes_old=%0d writes_new=2 cancelled_results=2 cycles=%0d",RESET_STAGE,(RESET_STAGE==3)?2:0,cycle);$finish;
  end
 end
end
endmodule
module write_reset_memory(
 input wire clk,rstn,
 input wire read_valid,output wire read_ready,input wire [1:0] read_slot,input wire [56:0] read_address,
 output reg read_result_valid,input wire read_result_ready,output reg [1:0] read_result_slot,output reg [511:0] read_result_data,
 input wire write_valid,output wire write_ready,input wire [1:0] write_slot,input wire [56:0] write_address,
 input wire [2047:0] write_data,input wire [255:0] write_be,
 output reg write_result_valid,input wire write_result_ready,output reg [1:0] write_result_slot,
 output reg write_executed,output reg [1:0] write_execute_slot,output reg [31:0] execution_count,output wire [2047:0] snapshot
);
 reg [7:0] memory[0:255];reg read_pending,write_pending,write_applied;
 reg [1:0] saved_read_slot,saved_write_slot;reg [56:0] saved_read_address,saved_write_address;
 reg [2047:0] saved_data;reg [255:0] saved_be;
 integer cycles,read_due,write_due,b,init_byte;
 // Memory and its cumulative execution count belong to the backend, not the cancelled link epoch.
 initial begin execution_count=0;for(init_byte=0;init_byte<256;init_byte=init_byte+1)memory[init_byte]=0;end
 genvar byte_lane;generate for(byte_lane=0;byte_lane<256;byte_lane=byte_lane+1)begin:observe_memory
  assign snapshot[byte_lane*8+:8]=memory[byte_lane];
 end endgenerate
 assign read_ready=rstn&&!read_pending&&(cycles%5!=1);
 assign write_ready=rstn&&!write_pending&&(cycles%7!=2);
 always @(posedge clk)begin
  if(!rstn)begin
   cycles<=0;read_pending<=0;write_pending<=0;write_applied<=0;read_result_valid<=0;write_result_valid<=0;write_executed<=0;
   read_result_slot<=0;read_result_data<=0;write_result_slot<=0;write_execute_slot<=0;
   saved_read_slot<=0;saved_write_slot<=0;saved_read_address<=0;saved_write_address<=0;saved_data<=0;saved_be<=0;read_due<=0;write_due<=0;
  end else begin
   cycles<=cycles+1;write_executed<=0;
   if(read_result_valid&&read_result_ready)begin read_result_valid<=0;read_pending<=0;end
   if(write_result_valid&&write_result_ready)begin write_result_valid<=0;write_pending<=0;end
   if(read_pending&&!read_result_valid&&cycles>=read_due)begin
    read_result_valid<=1;read_result_slot<=saved_read_slot;
    for(b=0;b<64;b=b+1)read_result_data[b*8+:8]<=memory[saved_read_address+b];
   end
   if(write_pending&&!write_applied&&cycles>=write_due)begin
    for(b=0;b<256;b=b+1)if(saved_be[b])memory[b]<=saved_data[(b-(saved_write_address/64)*64)*8+:8];
    write_applied<=1;write_executed<=1;write_execute_slot<=saved_write_slot;execution_count<=execution_count+1;
    write_result_valid<=1;write_result_slot<=saved_write_slot;
   end
   if(read_valid&&read_ready)begin read_pending<=1;saved_read_slot<=read_slot;saved_read_address<=read_address;read_due<=cycles+9;end
   if(write_valid&&write_ready)begin
    write_pending<=1;write_applied<=0;saved_write_slot<=write_slot;saved_write_address<=write_address;saved_data<=write_data;saved_be<=write_be;write_due<=cycles+70;
   end
  end
 end
endmodule
