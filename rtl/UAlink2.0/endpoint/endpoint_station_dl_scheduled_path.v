`timescale 1ns/1ps
`default_nettype none

// endpoint_station_dl_path的生产槽日历组合层。所有Port保持固定512-bit和同一时钟；
// 日历只分配服务拍，不改变链路context、信用或重放所有权。
module endpoint_station_dl_scheduled_path #(
 parameter integer C_REPLAY_DEPTH=4,
 parameter integer C_ADDR_WIDTH=(C_REPLAY_DEPTH<=2)?1:(C_REPLAY_DEPTH<=4)?2:(C_REPLAY_DEPTH<=8)?3:(C_REPLAY_DEPTH<=16)?4:(C_REPLAY_DEPTH<=32)?5:(C_REPLAY_DEPTH<=64)?6:(C_REPLAY_DEPTH<=128)?7:8
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire[3:0] i_ras_rx_cleanup,
 input wire[1:0] i_requested_mode,input wire i_mode_commit,input wire[3:0] i_lane_up,input wire[3:0] i_port_link_reset,
 output wire[3:0] o_port_slot_enable,output wire[1:0] o_slot_port,output wire o_slot_error,
 output wire[1:0] o_active_mode,output wire[3:0] o_active_mask,output wire o_mode_commit_accept,output wire o_mode_error,
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
wire[3:0] calendar_valid=i_tx_tl_valid&o_active_mask;
endpoint_station_slot_calendar u_calendar(.i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_mode(o_active_mode),
 .i_port_valid(calendar_valid),.i_port_ready(o_tx_tl_ready),.o_slot_enable(o_port_slot_enable),.o_slot_port(o_slot_port),.o_mode_error(o_slot_error));
endpoint_station_dl_path #(.C_REPLAY_DEPTH(C_REPLAY_DEPTH),.C_ADDR_WIDTH(C_ADDR_WIDTH)) u_path(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_ras_rx_cleanup(i_ras_rx_cleanup),.i_requested_mode(i_requested_mode),.i_mode_commit(i_mode_commit),.i_lane_up(i_lane_up),.i_port_link_reset(i_port_link_reset),.i_port_slot_enable(o_port_slot_enable),.o_active_mode(o_active_mode),.o_active_mask(o_active_mask),.o_mode_commit_accept(o_mode_commit_accept),.o_mode_error(o_mode_error),
 .i_tx_tl_valid(i_tx_tl_valid),.o_tx_tl_ready(o_tx_tl_ready),.i_tx_tl_data(i_tx_tl_data),.i_tx_tl_msg(i_tx_tl_msg),.i_tx_tl_sop(i_tx_tl_sop),.i_tx_tl_eop(i_tx_tl_eop),.i_tx_flush(i_tx_flush),
 .i_rx_frame_valid(i_rx_frame_valid),.o_rx_frame_ready(o_rx_frame_ready),.i_rx_frame_data(i_rx_frame_data),.i_rx_frame_sop(i_rx_frame_sop),.i_rx_frame_eop(i_rx_frame_eop),.i_rx_fec_complete(i_rx_fec_complete),.i_rx_crc_ok(i_rx_crc_ok),.o_rx_tl_valid(o_rx_tl_valid),.i_rx_tl_ready(i_rx_tl_ready),.o_rx_tl_data(o_rx_tl_data),.o_rx_tl_msg(o_rx_tl_msg),
 .o_tx_control_valid(o_tx_control_valid),.i_tx_control_ready(i_tx_control_ready),.o_tx_control_replay_request(o_tx_control_replay_request),.o_tx_control_target(o_tx_control_target),
 .o_crc_input_valid(o_crc_input_valid),.i_crc_input_ready(i_crc_input_ready),.o_crc_input_data(o_crc_input_data),.o_crc_input_sop(o_crc_input_sop),.o_crc_input_eop(o_crc_input_eop),.o_crc_input_sequence(o_crc_input_sequence),.o_crc_input_replay(o_crc_input_replay),.o_crc_required(o_crc_required),.o_physical_valid(o_physical_valid),.o_tx_resident_count(o_tx_resident_count),.o_tx_unacked_count(o_tx_unacked_count),.o_rx_last_sequence(o_rx_last_sequence),.o_rx_bad_crc_count(o_rx_bad_crc_count),.o_rx_unexpected_count(o_rx_unexpected_count),.o_rx_ambiguous(o_rx_ambiguous),.o_rx_in_replay(o_rx_in_replay),.o_rx_port_quiescent(o_rx_port_quiescent),.o_builder_busy(o_builder_busy),.o_builder_quiescent(o_builder_quiescent),.o_builder_protocol_error(o_builder_protocol_error),.o_busy(o_busy),.o_quiescent(o_quiescent),.o_error(o_error));
endmodule
`default_nettype wire
