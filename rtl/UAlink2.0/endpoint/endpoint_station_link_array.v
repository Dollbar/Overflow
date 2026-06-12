`timescale 1ns/1ps
`default_nettype none

// 固定四槽Station的独立hop-local DL上下文阵列。四个实例共享时钟和512-bit beat宽度，
// 但不共享RX sequence、TX replay window、ACK或Replay Request状态。
// x4/2x2/4x1沿用station_bifurcation的稳定槽0 / 0,2 / 0,1,2,3。
// 模式只在当前活动上下文全部quiescent时提交；提交后统一link-reset一拍。
// TX仍终止于CRC输入候选，A19 CRC octet映射和PCS/FEC未闭合，physical_valid保持全零。
module endpoint_station_link_array #(
 parameter integer C_REPLAY_DEPTH=4,
 parameter integer C_ADDR_WIDTH=(C_REPLAY_DEPTH<=2)?1:(C_REPLAY_DEPTH<=4)?2:(C_REPLAY_DEPTH<=8)?3:(C_REPLAY_DEPTH<=16)?4:(C_REPLAY_DEPTH<=32)?5:(C_REPLAY_DEPTH<=64)?6:(C_REPLAY_DEPTH<=128)?7:8
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire[3:0] i_ras_rx_cleanup,
 input wire[1:0] i_requested_mode,input wire i_mode_commit,input wire[3:0] i_lane_up,input wire[3:0] i_port_link_reset,
 output wire[1:0] o_active_mode,output wire[3:0] o_configured_mask,output wire[3:0] o_active_mask,
 output wire[15:0] o_lane_masks,output wire o_mode_commit_accept,output wire o_mode_error,
 input wire[3:0] i_rx_frame_valid,output wire[3:0] o_rx_frame_ready,input wire[2047:0] i_rx_frame_data,
 input wire[3:0] i_rx_frame_sop,input wire[3:0] i_rx_frame_eop,input wire[3:0] i_rx_fec_complete,input wire[3:0] i_rx_crc_ok,
 input wire[31:0] i_rx_replay_limit,output wire[3:0] o_tl_valid,input wire[3:0] i_tl_ready,
 output wire[2047:0] o_tl_flit,output wire[7:0] o_tl_msg,
 output wire[3:0] o_tx_control_valid,input wire[3:0] i_tx_control_ready,
 output wire[3:0] o_tx_control_replay_request,output wire[35:0] o_tx_control_target,
 output wire[35:0] o_rx_last_sequence,output wire[11:0] o_rx_bad_crc_count,output wire[31:0] o_rx_unexpected_count,output wire[3:0] o_rx_ambiguous,output wire[3:0] o_rx_in_replay,
 input wire[3:0] i_tx_frame_valid,output wire[3:0] o_tx_frame_ready,input wire[2047:0] i_tx_frame_data,
 input wire[3:0] i_tx_frame_sop,input wire[3:0] i_tx_frame_eop,
 output wire[3:0] o_crc_input_valid,input wire[3:0] i_crc_input_ready,output wire[2047:0] o_crc_input_data,
 output wire[3:0] o_crc_input_sop,output wire[3:0] o_crc_input_eop,output wire[35:0] o_crc_input_sequence,
 output wire[3:0] o_crc_input_replay,output wire[3:0] o_crc_required,output wire[3:0] o_physical_valid,
 output wire[31:0] o_tx_unacked_count,output wire[31:0] o_tx_resident_count,
 output wire[3:0] o_rx_port_quiescent,output wire[3:0] o_port_busy,output wire[3:0] o_port_quiescent,output wire o_busy,output wire o_quiescent,output wire o_error
);
reg[1:0] active_mode_q;reg mode_reset_q,mode_error_q;wire[3:0] configured_mask,active_mask;wire[15:0] lane_masks;wire[11:0] unused_service_units;
wire map_mode_error,map_duplicate;wire unused_map_ready,unused_map_valid,unused_map_implemented,unused_map_error;wire[511:0] unused_map_data;wire[127:0] unused_map_meta;
wire[3:0] context_reset,rx_busy,rx_quiet,tx_busy,tx_quiet,rx_error,tx_error,port_error;
wire[3:0] rx_received_command_valid,rx_received_command_request;wire[35:0] rx_received_command_target,rx_last_sequence;
wire[3:0] rx_replay_request;wire[3:0] unused_rx_frame_event,unused_rx_frame_accept,unused_rx_ambiguous,unused_rx_in_replay,unused_rx_crc_event,unused_rx_sequence_event,unused_rx_ras;
wire[11:0] unused_rx_bad_crc;wire[31:0] unused_rx_unexpected;wire[63:0] unused_rx_reject_count;
wire[3:0] tx_command_error,tx_metadata_error;wire[3:0] unused_tx_ack_accept,unused_tx_request_accept;
wire mode_request_valid,all_current_quiet;genvar p;
assign mode_request_valid=(i_requested_mode!=2'd3);
assign all_current_quiet=&((~active_mask)|(rx_quiet&tx_quiet));
assign o_mode_commit_accept=i_rstn&&i_enable&&i_mode_commit&&mode_request_valid&&all_current_quiet;
assign context_reset=i_port_link_reset|{4{mode_reset_q}}|~active_mask;
assign o_active_mode=active_mode_q;assign o_configured_mask=configured_mask;assign o_active_mask=active_mask;assign o_lane_masks=lane_masks;
assign o_mode_error=mode_error_q||map_mode_error||map_duplicate;
assign o_rx_port_quiescent=(~active_mask)|rx_quiet;assign o_port_busy=active_mask&(rx_busy|tx_busy);assign o_port_quiescent=(~active_mask)|(rx_quiet&tx_quiet);
assign o_busy=i_rstn&&(|o_port_busy);assign o_quiescent=i_rstn&&all_current_quiet&&!mode_reset_q;
assign o_error=o_mode_error||(|port_error);
assign o_rx_last_sequence=rx_last_sequence;assign o_rx_bad_crc_count=unused_rx_bad_crc;assign o_rx_unexpected_count=unused_rx_unexpected;assign o_rx_ambiguous=unused_rx_ambiguous;assign o_rx_in_replay=unused_rx_in_replay;
assign port_error=rx_error|tx_error|tx_command_error|tx_metadata_error;

station_bifurcation u_bifurcation(.i_mode(active_mode_q),.i_lane_up(i_lane_up),.o_port_configured(configured_mask),.o_port_active(active_mask),.o_lane_masks(lane_masks),.o_service_units(unused_service_units),.o_mode_error(map_mode_error),.o_duplicate_lane(map_duplicate),.i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_valid(1'b0),.i_data(512'd0),.i_meta(128'd0),.o_ready(unused_map_ready),.o_valid(unused_map_valid),.o_data(unused_map_data),.o_meta(unused_map_meta),.o_implemented(unused_map_implemented),.o_error(unused_map_error));

always @(posedge i_clk)begin
 if(!i_rstn)begin active_mode_q<=2'd0;mode_reset_q<=1'b0;mode_error_q<=1'b0;end
 else begin
  mode_reset_q<=1'b0;
  if(i_enable&&i_mode_commit)begin
   if(!mode_request_valid||!all_current_quiet)mode_error_q<=1'b1;
   else if(i_requested_mode!=active_mode_q)begin active_mode_q<=i_requested_mode;mode_reset_q<=1'b1;end
  end
 end
end

generate for(p=0;p<4;p=p+1)begin:gen_port
 endpoint_dl_rx_link_context u_rx(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_link_reset(context_reset[p]),.i_epoch_cleanup(i_ras_rx_cleanup[p]),.i_enable(i_enable&&active_mask[p]),
  .i_frame_valid(i_rx_frame_valid[p]),.o_frame_ready(o_rx_frame_ready[p]),.i_frame_data(i_rx_frame_data[p*512+:512]),.i_frame_sop(i_rx_frame_sop[p]),.i_frame_eop(i_rx_frame_eop[p]),.i_fec_complete(i_rx_fec_complete[p]),.i_crc_ok(i_rx_crc_ok[p]),.i_replay_limit(i_rx_replay_limit[p*8+:8]),
  .o_tl_valid(o_tl_valid[p]),.i_tl_ready(i_tl_ready[p]),.o_tl_flit(o_tl_flit[p*512+:512]),.o_tl_msg(o_tl_msg[p*2+:2]),
  .o_control_valid(o_tx_control_valid[p]),.i_control_ready(i_tx_control_ready[p]),.o_control_replay_request(o_tx_control_replay_request[p]),.o_control_target(o_tx_control_target[p*9+:9]),
  .o_received_command_valid(rx_received_command_valid[p]),.o_received_command_replay_request(rx_received_command_request[p]),.o_received_command_target(rx_received_command_target[p*9+:9]),
  .o_frame_event(unused_rx_frame_event[p]),.o_frame_accept_event(unused_rx_frame_accept[p]),.o_bad_crc_count(unused_rx_bad_crc[p*3+:3]),.o_unexpected_count(unused_rx_unexpected[p*8+:8]),.o_ambiguous(unused_rx_ambiguous[p]),.o_reject_frame_count(unused_rx_reject_count[p*16+:16]),.o_last_sequence(rx_last_sequence[p*9+:9]),.o_in_replay(unused_rx_in_replay[p]),.o_crc_error_event(unused_rx_crc_event[p]),.o_sequence_error_event(unused_rx_sequence_event[p]),.o_ras_event(unused_rx_ras[p]),.o_error(rx_error[p]),.o_busy(rx_busy[p]),.o_quiescent(rx_quiet[p]));
 endpoint_dl_tx_link_context #(.C_REPLAY_DEPTH(C_REPLAY_DEPTH),.C_ADDR_WIDTH(C_ADDR_WIDTH)) u_tx(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_link_reset(context_reset[p]),.i_enable(i_enable&&active_mask[p]),
  .i_framed_valid(i_tx_frame_valid[p]),.o_framed_ready(o_tx_frame_ready[p]),.i_framed_data(i_tx_frame_data[p*512+:512]),.i_framed_sop(i_tx_frame_sop[p]),.i_framed_eop(i_tx_frame_eop[p]),
  .i_rx_command_valid(rx_received_command_valid[p]),.i_rx_command_replay_request(rx_received_command_request[p]),.i_rx_command_target(rx_received_command_target[p*9+:9]),
  .i_rx_last_sequence(rx_last_sequence[p*9+:9]),.i_rx_replay_request(rx_replay_request[p]),.i_new_fec_group(1'b0),
  .o_crc_input_valid(o_crc_input_valid[p]),.i_crc_input_ready(i_crc_input_ready[p]),.o_crc_input_data(o_crc_input_data[p*512+:512]),.o_crc_input_sop(o_crc_input_sop[p]),.o_crc_input_eop(o_crc_input_eop[p]),.o_crc_input_sequence(o_crc_input_sequence[p*9+:9]),.o_crc_input_replay(o_crc_input_replay[p]),
  .o_crc_required(o_crc_required[p]),.o_physical_valid(o_physical_valid[p]),.o_unacked_count(o_tx_unacked_count[p*8+:8]),.o_resident_count(o_tx_resident_count[p*8+:8]),.o_ack_accept(unused_tx_ack_accept[p]),.o_replay_request_accept(unused_tx_request_accept[p]),.o_command_error(tx_command_error[p]),.o_metadata_error(tx_metadata_error[p]),.o_error(tx_error[p]),.o_busy(tx_busy[p]),.o_quiescent(tx_quiet[p]));
 // Replay Request只在控制候选被下一级真实接纳时装入TX FH副本状态，停顿不会重复装载。
 assign rx_replay_request[p]=o_tx_control_valid[p]&&i_tx_control_ready[p]&&o_tx_control_replay_request[p];
end endgenerate
endmodule
`default_nettype wire
