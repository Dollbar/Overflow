`timescale 1ns/1ps
`default_nettype none

// 普通明文事务的typed排序所有者边界。调用方提供已经恢复的源、目的、stream、VC、
// 256B region及端口亲和判决；本模块不从opaque metadata猜测这些协议字段。
// 每个排序domain最多一个未退休owner，不同domain保存在独立entry并由RR公平发出。
module endpoint_ordering_typed_owner #(
 parameter integer C_ENTRIES=8,
 parameter integer C_ENTRY_WIDTH=3,
 parameter integer C_TOKEN_WIDTH=16,
 parameter integer C_EPOCH_WIDTH=8
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire[C_EPOCH_WIDTH-1:0] i_epoch,
 input wire i_admit_valid,output wire o_admit_ready,input wire i_profile_valid,input wire i_affinity_valid,
 input wire[1:0] i_mode,input wire[1:0] i_stream,input wire[1:0] i_vc,input wire[9:0] i_src,input wire[9:0] i_dst,input wire[48:0] i_region,input wire[1:0] i_port,input wire[127:0] i_descriptor,
 output wire o_issue_valid,input wire i_issue_ready,output wire[C_EPOCH_WIDTH-1:0] o_issue_epoch,output wire[C_TOKEN_WIDTH-1:0] o_issue_token,
 output wire[1:0] o_issue_mode,output wire[1:0] o_issue_stream,output wire[1:0] o_issue_vc,output wire[9:0] o_issue_src,output wire[9:0] o_issue_dst,output wire[48:0] o_issue_region,output wire[1:0] o_issue_port,output wire[127:0] o_issue_descriptor,
 input wire i_retire_valid,output wire o_retire_ready,input wire[C_EPOCH_WIDTH-1:0] i_retire_epoch,input wire[C_TOKEN_WIDTH-1:0] i_retire_token,
 output wire o_busy,output wire o_quiescent,output wire[15:0] o_occupancy,
 output wire o_protocol_error,output wire o_token_error,output wire o_duplicate_error,output wire o_affinity_error,output wire o_epoch_error,output wire o_error
);
function can_encode;
 input integer count;input integer width;integer capacity;integer bit_index;
 begin
  capacity=1;
  for(bit_index=0;bit_index<width;bit_index=bit_index+1)if(capacity<count)capacity=capacity*2;
  can_encode=(count>=1)&&(width>=1)&&(width<=30)&&(capacity>=count);
end
endfunction
function integer entry_to_integer;
 input[C_ENTRY_WIDTH-1:0] value;integer value_bit;
 begin entry_to_integer=0;for(value_bit=0;value_bit<C_ENTRY_WIDTH;value_bit=value_bit+1)if(value[value_bit])entry_to_integer=entry_to_integer+(1<<value_bit);end
endfunction
function[C_ENTRY_WIDTH-1:0] integer_to_entry;
 input integer value;integer value_bit;
 begin for(value_bit=0;value_bit<C_ENTRY_WIDTH;value_bit=value_bit+1)integer_to_entry[value_bit]=((value&(1<<value_bit))!=0);end
endfunction
localparam CONFIG_LEGAL=can_encode(C_ENTRIES,C_ENTRY_WIDTH)&&(C_TOKEN_WIDTH>=2)&&(C_TOKEN_WIDTH<=30)&&(C_EPOCH_WIDTH>=1)&&(C_EPOCH_WIDTH<=30);
localparam[C_ENTRY_WIDTH-1:0] LAST_ENTRY=integer_to_entry(C_ENTRIES-1);
localparam[1:0] MODE_NONSO=2'd0,MODE_SOL=2'd1,MODE_SO=2'd2;
localparam[1:0] STREAM_REQ=2'd0,STREAM_READ_RSP=2'd1,STREAM_WRITE_RSP=2'd2;
reg[C_ENTRIES-1:0] valid_q,issued_q;
reg[1:0] mode_q[0:C_ENTRIES-1];reg[1:0] stream_q[0:C_ENTRIES-1];reg[1:0] vc_q[0:C_ENTRIES-1];reg[1:0] port_q[0:C_ENTRIES-1];
reg[9:0] src_q[0:C_ENTRIES-1];reg[9:0] dst_q[0:C_ENTRIES-1];reg[48:0] region_q[0:C_ENTRIES-1];reg[127:0] descriptor_q[0:C_ENTRIES-1];
reg[C_EPOCH_WIDTH-1:0] epoch_q[0:C_ENTRIES-1];reg[C_TOKEN_WIDTH-1:0] token_q[0:C_ENTRIES-1];
reg[C_TOKEN_WIDTH-1:0] next_token_q,last_retired_token_q;reg[C_EPOCH_WIDTH-1:0] active_epoch_q,last_retired_epoch_q;reg epoch_active_q,last_retired_valid_q,token_exhausted_q;
reg issue_hold_valid_q;reg[C_ENTRY_WIDTH-1:0] issue_hold_index_q,rr_q;
reg protocol_error_q,token_error_q,duplicate_error_q,affinity_error_q,epoch_error_q;
reg free_found,candidate_found,retire_found,domain_conflict,mode_conflict,affinity_conflict;
reg[C_ENTRY_WIDTH-1:0] free_index,candidate_index,retire_index;reg[15:0] occupancy;
integer scan_index,wrapped_index;
wire any_owner=|valid_q;
wire mode_legal=(i_mode==MODE_NONSO)||(i_mode==MODE_SOL)||(i_mode==MODE_SO);
wire stream_legal=(i_stream==STREAM_REQ)||(i_stream==STREAM_READ_RSP)||(i_stream==STREAM_WRITE_RSP);
wire base_admit_legal=CONFIG_LEGAL&&i_profile_valid&&mode_legal&&stream_legal&&((i_stream!=STREAM_REQ)||i_affinity_valid);
wire epoch_conflict=epoch_active_q&&(i_epoch!=active_epoch_q);
wire fatal_error=protocol_error_q||token_error_q||duplicate_error_q||affinity_error_q||epoch_error_q;
always @* begin
 occupancy=0;free_found=0;free_index=0;candidate_found=0;candidate_index=0;retire_found=0;retire_index=0;
 domain_conflict=0;mode_conflict=0;affinity_conflict=0;
 for(scan_index=0;scan_index<C_ENTRIES;scan_index=scan_index+1)begin
  if(valid_q[scan_index])begin
   occupancy=occupancy+1'b1;
   if((src_q[scan_index]==i_src)&&(dst_q[scan_index]==i_dst))begin
    if(mode_q[scan_index]!=i_mode)mode_conflict=1;
    if((stream_q[scan_index]==STREAM_REQ)&&(i_stream==STREAM_REQ)&&(region_q[scan_index]==i_region)&&(port_q[scan_index]!=i_port))affinity_conflict=1;
    if(stream_q[scan_index]==i_stream)begin
     case(i_mode)
      MODE_SO:domain_conflict=1;
      MODE_SOL:if(vc_q[scan_index]==i_vc)domain_conflict=1;
      MODE_NONSO:if((i_stream==STREAM_REQ)&&(vc_q[scan_index]==i_vc)&&(region_q[scan_index]==i_region))domain_conflict=1;
      default:begin end
     endcase
    end
   end
  end else if(!free_found)begin free_found=1;free_index=scan_index[C_ENTRY_WIDTH-1:0];end
  if(valid_q[scan_index]&&issued_q[scan_index]&&(epoch_q[scan_index]==i_retire_epoch)&&(token_q[scan_index]==i_retire_token))begin retire_found=1;retire_index=scan_index[C_ENTRY_WIDTH-1:0];end
  wrapped_index=entry_to_integer(rr_q)+scan_index;if(wrapped_index>=C_ENTRIES)wrapped_index=wrapped_index-C_ENTRIES;
  if(!candidate_found&&valid_q[wrapped_index]&&!issued_q[wrapped_index])begin candidate_found=1;candidate_index=wrapped_index[C_ENTRY_WIDTH-1:0];end
 end
end
assign o_occupancy=occupancy;
assign o_admit_ready=i_rstn&&i_enable&&!fatal_error&&!token_exhausted_q&&base_admit_legal&&!epoch_conflict&&!mode_conflict&&!affinity_conflict&&!domain_conflict&&free_found;
assign o_retire_ready=i_rstn&&!fatal_error&&retire_found;
assign o_issue_valid=i_rstn&&!fatal_error&&issue_hold_valid_q;
assign o_issue_epoch=o_issue_valid?epoch_q[issue_hold_index_q]:{C_EPOCH_WIDTH{1'b0}};
assign o_issue_token=o_issue_valid?token_q[issue_hold_index_q]:{C_TOKEN_WIDTH{1'b0}};
assign o_issue_mode=o_issue_valid?mode_q[issue_hold_index_q]:2'd0;assign o_issue_stream=o_issue_valid?stream_q[issue_hold_index_q]:2'd0;assign o_issue_vc=o_issue_valid?vc_q[issue_hold_index_q]:2'd0;
assign o_issue_src=o_issue_valid?src_q[issue_hold_index_q]:10'd0;assign o_issue_dst=o_issue_valid?dst_q[issue_hold_index_q]:10'd0;assign o_issue_region=o_issue_valid?region_q[issue_hold_index_q]:49'd0;assign o_issue_port=o_issue_valid?port_q[issue_hold_index_q]:2'd0;assign o_issue_descriptor=o_issue_valid?descriptor_q[issue_hold_index_q]:128'd0;
assign o_busy=i_rstn&&(any_owner||issue_hold_valid_q);assign o_quiescent=i_rstn&&CONFIG_LEGAL&&!fatal_error&&!any_owner&&!issue_hold_valid_q;
assign o_protocol_error=protocol_error_q;assign o_token_error=token_error_q;assign o_duplicate_error=duplicate_error_q;assign o_affinity_error=affinity_error_q;assign o_epoch_error=epoch_error_q;
assign o_error=i_rstn&&(!CONFIG_LEGAL||fatal_error);
integer reset_index;
always @(posedge i_clk)begin
 if(!i_rstn)begin
  valid_q<=0;issued_q<=0;next_token_q<={{(C_TOKEN_WIDTH-1){1'b0}},1'b1};active_epoch_q<=0;epoch_active_q<=0;last_retired_epoch_q<=0;last_retired_token_q<=0;last_retired_valid_q<=0;token_exhausted_q<=0;issue_hold_valid_q<=0;issue_hold_index_q<=0;rr_q<=0;
  protocol_error_q<=0;token_error_q<=0;duplicate_error_q<=0;affinity_error_q<=0;epoch_error_q<=0;
  for(reset_index=0;reset_index<C_ENTRIES;reset_index=reset_index+1)begin mode_q[reset_index]<=0;stream_q[reset_index]<=0;vc_q[reset_index]<=0;port_q[reset_index]<=0;src_q[reset_index]<=0;dst_q[reset_index]<=0;region_q[reset_index]<=0;descriptor_q[reset_index]<=0;epoch_q[reset_index]<=0;token_q[reset_index]<=0;end
 end else begin
  if(i_admit_valid&&(!base_admit_legal||mode_conflict))protocol_error_q<=1;
  if(i_admit_valid&&affinity_conflict)affinity_error_q<=1;
  if(i_admit_valid&&epoch_conflict)epoch_error_q<=1;
  if(i_retire_valid&&!retire_found)begin
   if(last_retired_valid_q&&(i_retire_epoch==last_retired_epoch_q)&&(i_retire_token==last_retired_token_q))duplicate_error_q<=1;else token_error_q<=1;
  end
  if(i_admit_valid&&o_admit_ready)begin
   valid_q[free_index]<=1;issued_q[free_index]<=0;mode_q[free_index]<=i_mode;stream_q[free_index]<=i_stream;vc_q[free_index]<=i_vc;src_q[free_index]<=i_src;dst_q[free_index]<=i_dst;region_q[free_index]<=i_region;port_q[free_index]<=i_port;descriptor_q[free_index]<=i_descriptor;epoch_q[free_index]<=i_epoch;token_q[free_index]<=next_token_q;
   active_epoch_q<=i_epoch;epoch_active_q<=1;
   if(next_token_q=={C_TOKEN_WIDTH{1'b1}})token_exhausted_q<=1;else next_token_q<=next_token_q+1'b1;
  end
  if(i_retire_valid&&o_retire_ready)begin valid_q[retire_index]<=0;issued_q[retire_index]<=0;last_retired_epoch_q<=i_retire_epoch;last_retired_token_q<=i_retire_token;last_retired_valid_q<=1;end
  if(issue_hold_valid_q&&i_issue_ready)begin issued_q[issue_hold_index_q]<=1;issue_hold_valid_q<=0;if(issue_hold_index_q==LAST_ENTRY)rr_q<=0;else rr_q<=issue_hold_index_q+1'b1;end
  else if(!issue_hold_valid_q&&candidate_found)begin issue_hold_valid_q<=1;issue_hold_index_q<=candidate_index;end
  if(!any_owner&&!issue_hold_valid_q&&!(i_admit_valid&&o_admit_ready))epoch_active_q<=0;
 end
end
endmodule
`default_nettype wire
