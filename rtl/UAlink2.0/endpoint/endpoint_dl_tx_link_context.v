`timescale 1ns/1ps
`default_nettype none

// 单Logical Port hop-local TX上下文。输入是未来标准dl_tx_framer产生的完整10x512 frame模板；
// 本模块分配sequence、保存完整640B模板、处理ACK/Replay Request并为每次发送重建FH。
// 输出仅是CRC计算级候选，不是PHY有效数据：CRC0..3生成及A19线上octet映射尚未闭合，
// 因而o_physical_valid固定为0，禁止绕过CRC/FEC边界。
module endpoint_dl_tx_link_context #(
 parameter integer C_REPLAY_DEPTH=4,
 parameter integer C_ADDR_WIDTH=(C_REPLAY_DEPTH<=2)?1:(C_REPLAY_DEPTH<=4)?2:(C_REPLAY_DEPTH<=8)?3:(C_REPLAY_DEPTH<=16)?4:(C_REPLAY_DEPTH<=32)?5:(C_REPLAY_DEPTH<=64)?6:(C_REPLAY_DEPTH<=128)?7:8
)(
 input wire i_clk,input wire i_rstn,input wire i_link_reset,input wire i_enable,
 input wire i_framed_valid,output wire o_framed_ready,input wire[511:0] i_framed_data,input wire i_framed_sop,input wire i_framed_eop,
 input wire i_rx_command_valid,input wire i_rx_command_replay_request,input wire[8:0] i_rx_command_target,
 input wire[8:0] i_rx_last_sequence,input wire i_rx_replay_request,input wire i_new_fec_group,
 output wire o_crc_input_valid,input wire i_crc_input_ready,output wire[511:0] o_crc_input_data,
 output wire o_crc_input_sop,output wire o_crc_input_eop,output wire[8:0] o_crc_input_sequence,output wire o_crc_input_replay,
 output wire o_crc_required,output wire o_physical_valid,
 output wire[7:0] o_unacked_count,output wire[7:0] o_resident_count,
 output wire o_ack_accept,output wire o_replay_request_accept,output wire o_command_error,output wire o_metadata_error,
 output wire o_error,output wire o_busy,output wire o_quiescent
);
reg[5119:0] input_frame_q,candidate_q;reg[3:0] input_count_q,output_count_q;reg input_pending_q,candidate_valid_q;
reg[8:0] candidate_sequence_q;reg candidate_replay_q;reg protocol_error_q;
wire storage_payload_accept;
wire storage_out_valid,storage_out_payload,storage_out_replay,storage_out_first;wire[8:0] storage_out_sequence;wire[5119:0] storage_out_data;wire storage_tag_error;wire[8:0] storage_stored_sequence;
wire storage_command_reject;
wire header_valid,header_metadata_error;wire[23:0] header;wire[2:0] unused_explicit_count;wire[1:0] unused_request_count;wire[8:0] unused_request_sequence;wire unused_group_used;
wire unused_storage_issue_ready,unused_storage_issue_accept,unused_storage_issue_payload,unused_storage_issue_replay,unused_storage_issue_first;
wire[8:0] unused_storage_issue_sequence;wire[7:0] unused_storage_ack_count;wire[8:0] unused_ctl_last_sequence,unused_ctl_last_ack,unused_ctl_scheduled_sequence;
wire[3:0] unused_ctl_ignore;wire[7:0] ctl_scheduled_count;wire[C_ADDR_WIDTH-1:0] unused_ctl_head,unused_ctl_write,unused_ctl_scheduled_pointer;wire unused_ctl_first_pending;
wire unused_snapshot_begin_ready,unused_snapshot_valid,unused_snapshot_last,unused_snapshot_active,unused_snapshot_done,unused_snapshot_error;
wire[5119:0] unused_snapshot_data;wire[8:0] unused_snapshot_sequence;wire[7:0] unused_snapshot_index,unused_snapshot_count,unused_snapshot_epoch,unused_snapshot_attempt;
wire storage_capture,storage_issue_request,frame_input_fire,frame_output_fire;wire link_active;
assign link_active=i_rstn&&!i_link_reset;
assign o_framed_ready=link_active&&i_enable&&!input_pending_q;
assign frame_input_fire=i_framed_valid&&o_framed_ready;
assign storage_issue_request=input_pending_q||(ctl_scheduled_count!=0);
assign storage_capture=storage_out_valid&&!candidate_valid_q&&header_valid;
assign o_crc_input_valid=link_active&&candidate_valid_q;
assign o_crc_input_data=o_crc_input_valid?candidate_q[output_count_q*512+:512]:512'd0;
assign o_crc_input_sop=o_crc_input_valid&&(output_count_q==0);assign o_crc_input_eop=o_crc_input_valid&&(output_count_q==9);
assign o_crc_input_sequence=candidate_sequence_q;assign o_crc_input_replay=candidate_replay_q;
assign frame_output_fire=o_crc_input_valid&&i_crc_input_ready;
assign o_crc_required=1'b1;assign o_physical_valid=1'b0;
assign o_command_error=storage_command_reject;assign o_metadata_error=header_metadata_error||storage_tag_error;
assign o_error=protocol_error_q||o_command_error||o_metadata_error;
assign o_busy=link_active&&(input_pending_q||(input_count_q!=0)||candidate_valid_q||storage_out_valid||(o_resident_count!=0));
assign o_quiescent=link_active&&!input_pending_q&&(input_count_q==0)&&!candidate_valid_q&&!storage_out_valid&&(o_resident_count==0);

dl_replay_tx_storage #(.C_DEPTH(C_REPLAY_DEPTH),.C_DATA_WIDTH(5120),.C_ADDR_WIDTH(C_ADDR_WIDTH)) u_storage(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_link_reset(i_link_reset),
 .i_ingress_event(i_rx_command_valid),.i_command_valid(i_rx_command_valid),.i_command_request(i_rx_command_replay_request),.i_command_target(i_rx_command_target),
 .i_issue(storage_issue_request),.i_payload(input_pending_q),.i_data(input_frame_q),.i_out_ready(storage_capture),
 .o_issue_ready(unused_storage_issue_ready),.o_issue_accept(unused_storage_issue_accept),.o_payload_accept(storage_payload_accept),
 .o_issue_payload(unused_storage_issue_payload),.o_issue_replay(unused_storage_issue_replay),.o_issue_first(unused_storage_issue_first),.o_issue_sequence(unused_storage_issue_sequence),
 .o_out_valid(storage_out_valid),.o_out_payload(storage_out_payload),.o_out_replay(storage_out_replay),.o_out_first(storage_out_first),.o_out_sequence(storage_out_sequence),.o_out_data(storage_out_data),
 .o_tag_error(storage_tag_error),.o_out_stored_sequence(storage_stored_sequence),.o_ack_accept(o_ack_accept),.o_ack_count(unused_storage_ack_count),
 .o_request_accept(o_replay_request_accept),.o_command_reject(storage_command_reject),.o_resident_count(o_resident_count),
 .o_ctl_last_sequence(unused_ctl_last_sequence),.o_ctl_last_ack(unused_ctl_last_ack),.o_ctl_ignore_count(unused_ctl_ignore),.o_ctl_unacked_count(o_unacked_count),
 .o_ctl_head_pointer(unused_ctl_head),.o_ctl_write_pointer(unused_ctl_write),.o_ctl_scheduled_sequence(unused_ctl_scheduled_sequence),.o_ctl_scheduled_count(ctl_scheduled_count),
 .o_ctl_scheduled_pointer(unused_ctl_scheduled_pointer),.o_ctl_first_pending(unused_ctl_first_pending),
 .i_snapshot_begin(1'b0),.o_snapshot_begin_ready(unused_snapshot_begin_ready),.i_snapshot_owner_error(1'b0),.i_snapshot_scope(1'b0),.i_snapshot_epoch(8'd0),.i_current_epoch(8'd0),.i_snapshot_attempt(8'd0),
 .i_snapshot_fenced(2'd0),.i_snapshot_fence_epoch(8'd0),.i_snapshot_fence_attempt(8'd0),.o_snapshot_valid(unused_snapshot_valid),.i_snapshot_ready(1'b0),.o_snapshot_data(unused_snapshot_data),.o_snapshot_sequence(unused_snapshot_sequence),
 .o_snapshot_index(unused_snapshot_index),.o_snapshot_count(unused_snapshot_count),.o_snapshot_last(unused_snapshot_last),.o_snapshot_epoch(unused_snapshot_epoch),.o_snapshot_attempt(unused_snapshot_attempt),.o_snapshot_active(unused_snapshot_active),.o_snapshot_done(unused_snapshot_done),.o_snapshot_error(unused_snapshot_error));

dl_replay_header_tx #(.C_EARLY_TX_METADATA(1)) u_header(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_link_reset(i_link_reset),.i_flit_send(storage_out_valid&&!candidate_valid_q),
 .i_payload(storage_out_payload),.i_replay(storage_out_replay),.i_first_replay(storage_out_first),.i_tx_sequence(storage_out_sequence),
 .i_tx_metadata_ok(storage_out_payload&&(storage_out_sequence!=0)&&(!storage_out_replay||(storage_stored_sequence==storage_out_sequence))),
 .i_rx_sequence(i_rx_last_sequence),.i_rx_request(i_rx_replay_request),.i_new_group(i_new_fec_group),
 .o_header(header),.o_header_valid(header_valid),.o_metadata_error(header_metadata_error),.o_explicit_count(unused_explicit_count),
 .o_request_count(unused_request_count),.o_request_sequence(unused_request_sequence),.o_group_used(unused_group_used));

always @(posedge i_clk)begin
 if(!i_rstn||i_link_reset)begin input_frame_q<=0;candidate_q<=0;input_count_q<=0;output_count_q<=0;input_pending_q<=0;candidate_valid_q<=0;candidate_sequence_q<=0;candidate_replay_q<=0;protocol_error_q<=0;end
 else begin
  if(frame_input_fire)begin
   if((input_count_q==0&&(!i_framed_sop||i_framed_eop))||(input_count_q!=0&&(i_framed_sop||((input_count_q==9)!=i_framed_eop))))begin input_count_q<=0;protocol_error_q<=1'b1;end
   else begin input_frame_q[input_count_q*512+:512]<=i_framed_data;if(input_count_q==9)begin input_count_q<=0;input_pending_q<=1'b1;end else input_count_q<=input_count_q+1'b1;end
  end
  if(storage_payload_accept)input_pending_q<=1'b0;
  if(storage_capture)begin
   candidate_q<=storage_out_data;candidate_q[632*8+:24]<=header;candidate_q[636*8+:32]<=32'd0;
   candidate_valid_q<=1'b1;candidate_sequence_q<=storage_out_sequence;candidate_replay_q<=storage_out_replay;output_count_q<=0;
  end
  if(frame_output_fire)begin if(output_count_q==9)begin output_count_q<=0;candidate_valid_q<=1'b0;end else output_count_q<=output_count_q+1'b1;end
 end
end

endmodule
`default_nettype wire
