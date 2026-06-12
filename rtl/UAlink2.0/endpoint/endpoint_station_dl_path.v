`timescale 1ns/1ps
`default_nettype none

// 四Logical Port Station的TL->DL模板->hop-local link组合层。
// i_port_slot_enable是外部common-clock TDM调度器给出的逐槽服务许可；本模块不声称它生成
// x4/2x2/4x1比例，只保证inactive或无slot的端口绝不接纳，数据宽度和时钟始终固定。
// 模式提交同时等待四个builder和当前活动link context排空，避免遗漏尚未成帧的TL所有权。
module endpoint_station_dl_path #(
 parameter integer C_REPLAY_DEPTH=4,
 parameter integer C_ADDR_WIDTH=(C_REPLAY_DEPTH<=2)?1:(C_REPLAY_DEPTH<=4)?2:(C_REPLAY_DEPTH<=8)?3:(C_REPLAY_DEPTH<=16)?4:(C_REPLAY_DEPTH<=32)?5:(C_REPLAY_DEPTH<=64)?6:(C_REPLAY_DEPTH<=128)?7:8
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire[3:0] i_ras_rx_cleanup,
 input wire[1:0] i_requested_mode,input wire i_mode_commit,input wire[3:0] i_lane_up,input wire[3:0] i_port_link_reset,
 input wire[3:0] i_port_slot_enable,output wire[1:0] o_active_mode,output wire[3:0] o_active_mask,
 output wire o_mode_commit_accept,output wire o_mode_error,
 input wire[3:0] i_tx_tl_valid,output wire[3:0] o_tx_tl_ready,input wire[2047:0] i_tx_tl_data,input wire[7:0] i_tx_tl_msg,
 input wire[3:0] i_tx_tl_sop,input wire[3:0] i_tx_tl_eop,input wire[3:0] i_tx_flush,
 input wire[3:0] i_rx_frame_valid,output wire[3:0] o_rx_frame_ready,input wire[2047:0] i_rx_frame_data,
 input wire[3:0] i_rx_frame_sop,input wire[3:0] i_rx_frame_eop,input wire[3:0] i_rx_fec_complete,input wire[3:0] i_rx_crc_ok,
 output wire[3:0] o_rx_tl_valid,input wire[3:0] i_rx_tl_ready,output wire[2047:0] o_rx_tl_data,output wire[7:0] o_rx_tl_msg,
 output wire[3:0] o_tx_control_valid,input wire[3:0] i_tx_control_ready,output wire[3:0] o_tx_control_replay_request,output wire[35:0] o_tx_control_target,
 output wire[3:0] o_crc_input_valid,input wire[3:0] i_crc_input_ready,output wire[2047:0] o_crc_input_data,
 output wire[3:0] o_crc_input_sop,output wire[3:0] o_crc_input_eop,output wire[35:0] o_crc_input_sequence,output wire[3:0] o_crc_input_replay,
 output wire[3:0] o_crc_required,output wire[3:0] o_physical_valid,output wire[31:0] o_tx_resident_count,output wire[31:0] o_tx_unacked_count,
 output wire[35:0] o_rx_last_sequence,output wire[11:0] o_rx_bad_crc_count,output wire[31:0] o_rx_unexpected_count,output wire[3:0] o_rx_ambiguous,output wire[3:0] o_rx_in_replay,output wire[3:0] o_rx_port_quiescent,
 output wire[3:0] o_builder_busy,output wire[3:0] o_builder_quiescent,output wire[3:0] o_builder_protocol_error,
 output wire o_busy,output wire o_quiescent,output wire o_error
);
wire[3:0] builder_ready,builder_frame_valid,builder_frame_ready,builder_frame_sop,builder_frame_eop,builder_carry;
wire[2047:0] builder_frame_data;wire[63:0] builder_protocol_count;wire[3:0] builder_quiet_raw;
wire[3:0] active_mask,configured_mask;wire[15:0] unused_lane_masks;wire base_mode_accept,base_mode_error,base_busy,base_quiet,base_error;
wire[3:0] unused_port_busy,unused_port_quiet;
wire all_builder_quiet,safe_mode_commit;reg mode_block_error_q,builder_mode_reset_q;genvar p;
assign o_active_mask=active_mask;assign all_builder_quiet=&((~active_mask)|builder_quiet_raw);
assign safe_mode_commit=i_mode_commit&&all_builder_quiet;assign o_mode_commit_accept=base_mode_accept;
assign o_mode_error=base_mode_error||mode_block_error_q;
assign o_builder_quiescent=(~active_mask)|builder_quiet_raw;
assign o_busy=i_rstn&&((|o_builder_busy)||base_busy);assign o_quiescent=i_rstn&&all_builder_quiet&&base_quiet;
assign o_error=o_mode_error||base_error||(|o_builder_protocol_error);
always @(posedge i_clk)begin
 if(!i_rstn)begin mode_block_error_q<=1'b0;builder_mode_reset_q<=1'b0;end
 else begin builder_mode_reset_q<=base_mode_accept;if(i_enable&&i_mode_commit&&!all_builder_quiet)mode_block_error_q<=1'b1;end
end

generate for(p=0;p<4;p=p+1)begin:gen_builder
 assign o_tx_tl_ready[p]=active_mask[p]&&i_port_slot_enable[p]&&builder_ready[p];
 dl_tx_frame_template_builder u_builder(
  .i_clk(i_clk),.i_rstn(i_rstn&&!i_port_link_reset[p]&&!builder_mode_reset_q&&active_mask[p]),.i_enable(i_enable&&active_mask[p]),
  .i_tl_valid(i_tx_tl_valid[p]&&active_mask[p]&&i_port_slot_enable[p]),.o_tl_ready(builder_ready[p]),.i_tl_data(i_tx_tl_data[p*512+:512]),.i_tl_msg(i_tx_tl_msg[p*2+:2]),.i_tl_sop(i_tx_tl_sop[p]),.i_tl_eop(i_tx_tl_eop[p]),.i_flush(i_tx_flush[p]&&active_mask[p]&&i_port_slot_enable[p]),
  .o_frame_valid(builder_frame_valid[p]),.i_frame_ready(builder_frame_ready[p]),.o_frame_data(builder_frame_data[p*512+:512]),.o_frame_sop(builder_frame_sop[p]),.o_frame_eop(builder_frame_eop[p]),.o_carry_active(builder_carry[p]),
  .o_protocol_error(o_builder_protocol_error[p]),.o_protocol_error_count(builder_protocol_count[p*16+:16]),.o_busy(o_builder_busy[p]),.o_quiescent(builder_quiet_raw[p]));
end endgenerate

endpoint_station_link_array #(.C_REPLAY_DEPTH(C_REPLAY_DEPTH),.C_ADDR_WIDTH(C_ADDR_WIDTH)) u_links(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_ras_rx_cleanup(i_ras_rx_cleanup),.i_requested_mode(i_requested_mode),.i_mode_commit(safe_mode_commit),.i_lane_up(i_lane_up),.i_port_link_reset(i_port_link_reset),.o_active_mode(o_active_mode),.o_configured_mask(configured_mask),.o_active_mask(active_mask),.o_lane_masks(unused_lane_masks),.o_mode_commit_accept(base_mode_accept),.o_mode_error(base_mode_error),
 .i_rx_frame_valid(i_rx_frame_valid),.o_rx_frame_ready(o_rx_frame_ready),.i_rx_frame_data(i_rx_frame_data),.i_rx_frame_sop(i_rx_frame_sop),.i_rx_frame_eop(i_rx_frame_eop),.i_rx_fec_complete(i_rx_fec_complete),.i_rx_crc_ok(i_rx_crc_ok),.i_rx_replay_limit({4{8'd3}}),.o_tl_valid(o_rx_tl_valid),.i_tl_ready(i_rx_tl_ready),.o_tl_flit(o_rx_tl_data),.o_tl_msg(o_rx_tl_msg),
 .o_tx_control_valid(o_tx_control_valid),.i_tx_control_ready(i_tx_control_ready),.o_tx_control_replay_request(o_tx_control_replay_request),.o_tx_control_target(o_tx_control_target),.o_rx_last_sequence(o_rx_last_sequence),.o_rx_bad_crc_count(o_rx_bad_crc_count),.o_rx_unexpected_count(o_rx_unexpected_count),.o_rx_ambiguous(o_rx_ambiguous),.o_rx_in_replay(o_rx_in_replay),
 .i_tx_frame_valid(builder_frame_valid),.o_tx_frame_ready(builder_frame_ready),.i_tx_frame_data(builder_frame_data),.i_tx_frame_sop(builder_frame_sop),.i_tx_frame_eop(builder_frame_eop),
 .o_crc_input_valid(o_crc_input_valid),.i_crc_input_ready(i_crc_input_ready),.o_crc_input_data(o_crc_input_data),.o_crc_input_sop(o_crc_input_sop),.o_crc_input_eop(o_crc_input_eop),.o_crc_input_sequence(o_crc_input_sequence),.o_crc_input_replay(o_crc_input_replay),.o_crc_required(o_crc_required),.o_physical_valid(o_physical_valid),.o_tx_unacked_count(o_tx_unacked_count),.o_tx_resident_count(o_tx_resident_count),.o_rx_port_quiescent(o_rx_port_quiescent),.o_port_busy(unused_port_busy),.o_port_quiescent(unused_port_quiet),.o_busy(base_busy),.o_quiescent(base_quiet),.o_error(base_error));
wire unused_observation=(|configured_mask)||(|unused_lane_masks)||(|unused_port_busy)||(|unused_port_quiet)||(|builder_carry)||(|builder_protocol_count);
endmodule
`default_nettype wire
