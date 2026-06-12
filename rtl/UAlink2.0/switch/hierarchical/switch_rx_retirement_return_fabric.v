`timescale 1ns/1ps
`default_nettype none
// Egress安全EOP到source RX信用所有者的banked返回网络。descriptor完全opaque，不解释协议或token。
module switch_rx_retirement_return_fabric #(
 parameter integer C_INPUTS=8,parameter integer C_NUM_SOURCES=8,parameter integer C_NUM_BANKS=2,parameter integer C_FIFO_DEPTH=4,
 parameter integer C_SOURCE_WIDTH=10,parameter integer C_MASK_WIDTH=17,parameter integer C_TOKEN_WIDTH=18,
 parameter integer C_SOURCE_INDEX_WIDTH=(C_NUM_SOURCES<=2)?1:(C_NUM_SOURCES<=4)?2:(C_NUM_SOURCES<=8)?3:(C_NUM_SOURCES<=16)?4:(C_NUM_SOURCES<=32)?5:(C_NUM_SOURCES<=64)?6:(C_NUM_SOURCES<=128)?7:(C_NUM_SOURCES<=256)?8:(C_NUM_SOURCES<=512)?9:10,
 parameter integer C_INPUT_WIDTH=(C_INPUTS<=2)?1:(C_INPUTS<=4)?2:(C_INPUTS<=8)?3:(C_INPUTS<=16)?4:(C_INPUTS<=32)?5:(C_INPUTS<=64)?6:(C_INPUTS<=128)?7:(C_INPUTS<=256)?8:(C_INPUTS<=512)?9:10,
 parameter integer C_BANK_WIDTH=(C_NUM_BANKS<=2)?1:(C_NUM_BANKS<=4)?2:(C_NUM_BANKS<=8)?3:(C_NUM_BANKS<=16)?4:5,
 parameter integer C_PTR_WIDTH=(C_FIFO_DEPTH<=2)?1:(C_FIFO_DEPTH<=4)?2:(C_FIFO_DEPTH<=8)?3:4
)(
 input wire i_clk,input wire i_rstn,input wire[C_INPUTS-1:0]i_valid,output wire[C_INPUTS-1:0]o_ready,input wire[C_INPUTS-1:0]i_eop,
 input wire[C_INPUTS*C_SOURCE_WIDTH-1:0]i_source_port,input wire[C_INPUTS*C_MASK_WIDTH-1:0]i_owner_valid,
 input wire[C_INPUTS*C_MASK_WIDTH*C_TOKEN_WIDTH-1:0]i_owner_tokens,
 output wire[C_NUM_SOURCES-1:0]o_source_valid,input wire[C_NUM_SOURCES-1:0]i_source_ready,
 output wire[C_NUM_SOURCES*C_MASK_WIDTH-1:0]o_source_owner_valid,
 output wire[C_NUM_SOURCES*C_MASK_WIDTH*C_TOKEN_WIDTH-1:0]o_source_owner_tokens,
 output wire o_quiescent,output wire o_error,output wire o_config_error
);
 localparam CONFIG_LEGAL=(C_INPUTS>=1)&&(C_INPUTS<=1024)&&(C_NUM_SOURCES>=1)&&(C_NUM_SOURCES<=1024)&&
  (C_SOURCE_WIDTH>=C_SOURCE_INDEX_WIDTH)&&(C_SOURCE_WIDTH<=10)&&((1<<C_SOURCE_INDEX_WIDTH)>=C_NUM_SOURCES)&&
  (C_NUM_BANKS>=1)&&(C_NUM_BANKS<=32)&&((1<<C_BANK_WIDTH)==C_NUM_BANKS)&&(C_NUM_BANKS<=C_NUM_SOURCES)&&
  (C_FIFO_DEPTH>=2)&&(C_FIFO_DEPTH<=16)&&((1<<C_PTR_WIDTH)==C_FIFO_DEPTH)&&
  ((1<<C_INPUT_WIDTH)>=C_INPUTS)&&(C_MASK_WIDTH>=1)&&(C_MASK_WIDTH<=32)&&(C_TOKEN_WIDTH>=1)&&(C_TOKEN_WIDTH<=64);
 reg[C_NUM_SOURCES-1:0]source_outstanding_q,last_valid_q;reg[C_NUM_SOURCES*C_MASK_WIDTH-1:0]last_mask_q;
 reg[C_NUM_SOURCES*C_MASK_WIDTH*C_TOKEN_WIDTH-1:0]last_tokens_q;reg error_q;integer error_scan,source_update,bank_update;
 wire[C_NUM_BANKS*C_INPUTS-1:0]bank_grant;wire[C_NUM_BANKS-1:0]bank_enqueue,bank_dequeue,bank_head_valid;
 wire[C_NUM_BANKS*C_SOURCE_WIDTH-1:0]bank_enqueue_source,bank_head_source;
 wire[C_NUM_BANKS*C_MASK_WIDTH-1:0]bank_enqueue_mask,bank_head_mask;
 wire[C_NUM_BANKS*C_MASK_WIDTH*C_TOKEN_WIDTH-1:0]bank_enqueue_tokens,bank_head_tokens;
 reg malformed_event;integer checked_source;
 always @*begin
  malformed_event=1'b0;checked_source=0;
  for(error_scan=0;error_scan<C_INPUTS;error_scan=error_scan+1)if(i_valid[error_scan])begin
   checked_source=0;checked_source[C_SOURCE_WIDTH-1:0]=i_source_port[error_scan*C_SOURCE_WIDTH+:C_SOURCE_WIDTH];
   if((checked_source>=C_NUM_SOURCES)||!i_eop[error_scan]||!(|i_owner_valid[error_scan*C_MASK_WIDTH+:C_MASK_WIDTH]))malformed_event=1'b1;
   else if(source_outstanding_q[checked_source]||(last_valid_q[checked_source]&&
    (last_mask_q[checked_source*C_MASK_WIDTH+:C_MASK_WIDTH]==i_owner_valid[error_scan*C_MASK_WIDTH+:C_MASK_WIDTH])&&
    (last_tokens_q[checked_source*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH]==i_owner_tokens[error_scan*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH])))malformed_event=1'b1;
  end
 end
 genvar input_index,bank_index,source_index;
 generate for(input_index=0;input_index<C_INPUTS;input_index=input_index+1)begin:g_input_ready
  wire[C_NUM_BANKS-1:0]input_bank_grants;
  for(bank_index=0;bank_index<C_NUM_BANKS;bank_index=bank_index+1)assign input_bank_grants[bank_index]=bank_grant[bank_index*C_INPUTS+input_index];
  assign o_ready[input_index]=CONFIG_LEGAL&&!error_q&&(|input_bank_grants);
 end endgenerate
 generate for(bank_index=0;bank_index<C_NUM_BANKS;bank_index=bank_index+1)begin:g_bank
  localparam [C_BANK_WIDTH-1:0] BANK_ID=bank_index;
  reg[C_INPUT_WIDTH-1:0]rr_q,winner_q;reg winner_valid;integer scan_offset,candidate_value,source_value;
  reg[C_PTR_WIDTH-1:0]head_q,tail_q;reg[C_PTR_WIDTH:0]count_q;
  reg[C_SOURCE_WIDTH-1:0]source_mem[0:C_FIFO_DEPTH-1];reg[C_MASK_WIDTH-1:0]mask_mem[0:C_FIFO_DEPTH-1];
  reg[C_MASK_WIDTH*C_TOKEN_WIDTH-1:0]token_mem[0:C_FIFO_DEPTH-1];integer memory_reset;
  wire fifo_empty=!(|count_q);wire fifo_full=count_q[C_PTR_WIDTH];
  always @*begin
   winner_valid=1'b0;winner_q={C_INPUT_WIDTH{1'b0}};candidate_value=0;source_value=0;
   for(scan_offset=0;scan_offset<C_INPUTS;scan_offset=scan_offset+1)begin
    candidate_value=0;candidate_value[C_INPUT_WIDTH-1:0]=rr_q;candidate_value=candidate_value+scan_offset;if(candidate_value>=C_INPUTS)candidate_value=candidate_value-C_INPUTS;
    if(!winner_valid&&i_valid[candidate_value])begin
     source_value=0;source_value[C_SOURCE_WIDTH-1:0]=i_source_port[candidate_value*C_SOURCE_WIDTH+:C_SOURCE_WIDTH];
     if((source_value<C_NUM_SOURCES)&&i_eop[candidate_value]&&(|i_owner_valid[candidate_value*C_MASK_WIDTH+:C_MASK_WIDTH])&&
      !source_outstanding_q[source_value]&&!(last_valid_q[source_value]&&
       (last_mask_q[source_value*C_MASK_WIDTH+:C_MASK_WIDTH]==i_owner_valid[candidate_value*C_MASK_WIDTH+:C_MASK_WIDTH])&&
       (last_tokens_q[source_value*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH]==i_owner_tokens[candidate_value*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH]))&&
      (i_source_port[candidate_value*C_SOURCE_WIDTH+:C_BANK_WIDTH]==BANK_ID))begin winner_valid=1'b1;winner_q=candidate_value[C_INPUT_WIDTH-1:0];end
    end
   end
  end
  for(input_index=0;input_index<C_INPUTS;input_index=input_index+1)assign bank_grant[bank_index*C_INPUTS+input_index]=winner_valid&&!fifo_full&&!error_q&&(winner_q==input_index);
  assign bank_enqueue[bank_index]=winner_valid&&!fifo_full&&!error_q;
  assign bank_enqueue_source[bank_index*C_SOURCE_WIDTH+:C_SOURCE_WIDTH]=i_source_port[winner_q*C_SOURCE_WIDTH+:C_SOURCE_WIDTH];
  assign bank_enqueue_mask[bank_index*C_MASK_WIDTH+:C_MASK_WIDTH]=i_owner_valid[winner_q*C_MASK_WIDTH+:C_MASK_WIDTH];
  assign bank_enqueue_tokens[bank_index*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH]=i_owner_tokens[winner_q*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH];
  assign bank_head_valid[bank_index]=!fifo_empty;assign bank_head_source[bank_index*C_SOURCE_WIDTH+:C_SOURCE_WIDTH]=fifo_empty?{C_SOURCE_WIDTH{1'b0}}:source_mem[head_q];
  assign bank_head_mask[bank_index*C_MASK_WIDTH+:C_MASK_WIDTH]=fifo_empty?{C_MASK_WIDTH{1'b0}}:mask_mem[head_q];
  assign bank_head_tokens[bank_index*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH]=fifo_empty?{(C_MASK_WIDTH*C_TOKEN_WIDTH){1'b0}}:token_mem[head_q];
  assign bank_dequeue[bank_index]=!fifo_empty&&i_source_ready[source_mem[head_q][C_SOURCE_INDEX_WIDTH-1:0]];
  always @(posedge i_clk)begin
   if(!i_rstn)begin rr_q<=0;head_q<=0;tail_q<=0;count_q<=0;for(memory_reset=0;memory_reset<C_FIFO_DEPTH;memory_reset=memory_reset+1)begin source_mem[memory_reset]<=0;mask_mem[memory_reset]<=0;token_mem[memory_reset]<=0;end end
   else if(CONFIG_LEGAL)begin
    case({bank_enqueue[bank_index],bank_dequeue[bank_index]})2'b10:count_q<=count_q+1'b1;2'b01:count_q<=count_q-1'b1;default:count_q<=count_q;endcase
    if(bank_enqueue[bank_index])begin source_mem[tail_q]<=bank_enqueue_source[bank_index*C_SOURCE_WIDTH+:C_SOURCE_WIDTH];mask_mem[tail_q]<=bank_enqueue_mask[bank_index*C_MASK_WIDTH+:C_MASK_WIDTH];token_mem[tail_q]<=bank_enqueue_tokens[bank_index*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH];tail_q<=tail_q+1'b1;rr_q<=winner_q+1'b1;end
    if(bank_dequeue[bank_index])head_q<=head_q+1'b1;
   end
  end
 end endgenerate
 generate for(source_index=0;source_index<C_NUM_SOURCES;source_index=source_index+1)begin:g_source
  localparam integer SOURCE_BANK=source_index%C_NUM_BANKS;localparam [C_SOURCE_WIDTH-1:0] SOURCE_ID=source_index;
  assign o_source_valid[source_index]=CONFIG_LEGAL&&bank_head_valid[SOURCE_BANK]&&(bank_head_source[SOURCE_BANK*C_SOURCE_WIDTH+:C_SOURCE_WIDTH]==SOURCE_ID);
  assign o_source_owner_valid[source_index*C_MASK_WIDTH+:C_MASK_WIDTH]=o_source_valid[source_index]?bank_head_mask[SOURCE_BANK*C_MASK_WIDTH+:C_MASK_WIDTH]:{C_MASK_WIDTH{1'b0}};
  assign o_source_owner_tokens[source_index*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH]=o_source_valid[source_index]?bank_head_tokens[SOURCE_BANK*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH]:{(C_MASK_WIDTH*C_TOKEN_WIDTH){1'b0}};
 end endgenerate
 wire[C_NUM_SOURCES-1:0]source_fire=o_source_valid&i_source_ready;
 always @(posedge i_clk)begin
  if(!i_rstn)begin source_outstanding_q<=0;last_valid_q<=0;last_mask_q<=0;last_tokens_q<=0;error_q<=0;end
  else if(CONFIG_LEGAL)begin
   if(malformed_event)error_q<=1'b1;
   for(source_update=0;source_update<C_NUM_SOURCES;source_update=source_update+1)if(source_fire[source_update])begin source_outstanding_q[source_update]<=1'b0;last_valid_q[source_update]<=1'b1;last_mask_q[source_update*C_MASK_WIDTH+:C_MASK_WIDTH]<=o_source_owner_valid[source_update*C_MASK_WIDTH+:C_MASK_WIDTH];last_tokens_q[source_update*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH]<=o_source_owner_tokens[source_update*C_MASK_WIDTH*C_TOKEN_WIDTH+:C_MASK_WIDTH*C_TOKEN_WIDTH];end
   for(bank_update=0;bank_update<C_NUM_BANKS;bank_update=bank_update+1)if(bank_enqueue[bank_update])source_outstanding_q[bank_enqueue_source[bank_update*C_SOURCE_WIDTH+:C_SOURCE_INDEX_WIDTH]]<=1'b1;
  end
 end
 assign o_quiescent=i_rstn&&CONFIG_LEGAL&&!(|source_outstanding_q)&&!(|bank_head_valid);assign o_error=i_rstn&&(!CONFIG_LEGAL||error_q);assign o_config_error=!CONFIG_LEGAL;
endmodule
`default_nettype wire
