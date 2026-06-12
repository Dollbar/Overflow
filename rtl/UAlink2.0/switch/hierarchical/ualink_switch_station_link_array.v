`timescale 1ns/1ps
`default_nettype none
// Switch侧逐Logical Port链路终止阵列。TX输入必须已经由egress repack形成native TL；
// RX输出只来自CRC/sequence/replay commit barrier。每Station/Port复用独立已验证link context。
// 本层不解释internal class，也不实现未确定的A19 CRC octet映射，physical TX保持失败关闭。
module ualink_switch_station_link_array #(
 parameter integer C_NUM_STATIONS=2,parameter integer C_FLAT_STATIONS=(C_NUM_STATIONS<1)?1:C_NUM_STATIONS,
 parameter integer C_REPLAY_DEPTH=4,parameter integer C_ADDR_WIDTH=(C_REPLAY_DEPTH<=2)?1:(C_REPLAY_DEPTH<=4)?2:(C_REPLAY_DEPTH<=8)?3:(C_REPLAY_DEPTH<=16)?4:(C_REPLAY_DEPTH<=32)?5:(C_REPLAY_DEPTH<=64)?6:(C_REPLAY_DEPTH<=128)?7:8
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire[C_FLAT_STATIONS*2-1:0] i_station_requested_mode,input wire[C_FLAT_STATIONS-1:0] i_station_mode_commit,
 input wire[C_FLAT_STATIONS*4-1:0] i_lane_up,input wire[C_FLAT_STATIONS*4-1:0] i_port_link_reset,
 output wire[C_FLAT_STATIONS*2-1:0] o_active_mode,output wire[C_FLAT_STATIONS*4-1:0] o_active_mask,
 output wire[C_FLAT_STATIONS-1:0] o_mode_commit_accept,output wire[C_FLAT_STATIONS-1:0] o_mode_error,
 output wire[C_FLAT_STATIONS*4-1:0] o_port_slot_enable,output wire[C_FLAT_STATIONS*2-1:0] o_slot_port,
 input wire[C_FLAT_STATIONS*4-1:0] i_egress_tl_valid,output wire[C_FLAT_STATIONS*4-1:0] o_egress_tl_ready,
 input wire[C_FLAT_STATIONS*2048-1:0] i_egress_tl_data,input wire[C_FLAT_STATIONS*8-1:0] i_egress_tl_msg,
 input wire[C_FLAT_STATIONS*4-1:0] i_egress_tl_sop,input wire[C_FLAT_STATIONS*4-1:0] i_egress_tl_eop,input wire[C_FLAT_STATIONS*4-1:0] i_egress_flush,
 input wire[C_FLAT_STATIONS*4-1:0] i_link_rx_frame_valid,output wire[C_FLAT_STATIONS*4-1:0] o_link_rx_frame_ready,
 input wire[C_FLAT_STATIONS*2048-1:0] i_link_rx_frame_data,input wire[C_FLAT_STATIONS*4-1:0] i_link_rx_frame_sop,
 input wire[C_FLAT_STATIONS*4-1:0] i_link_rx_frame_eop,input wire[C_FLAT_STATIONS*4-1:0] i_link_rx_fec_complete,input wire[C_FLAT_STATIONS*4-1:0] i_link_rx_crc_ok,
 output wire[C_FLAT_STATIONS*4-1:0] o_ingress_tl_valid,input wire[C_FLAT_STATIONS*4-1:0] i_ingress_tl_ready,
 output wire[C_FLAT_STATIONS*2048-1:0] o_ingress_tl_data,output wire[C_FLAT_STATIONS*8-1:0] o_ingress_tl_msg,
 output wire[C_FLAT_STATIONS*4-1:0] o_link_control_valid,input wire[C_FLAT_STATIONS*4-1:0] i_link_control_ready,
 output wire[C_FLAT_STATIONS*4-1:0] o_link_control_replay_request,output wire[C_FLAT_STATIONS*36-1:0] o_link_control_target,
 output wire[C_FLAT_STATIONS*4-1:0] o_crc_frame_valid,input wire[C_FLAT_STATIONS*4-1:0] i_crc_frame_ready,
 output wire[C_FLAT_STATIONS*2048-1:0] o_crc_frame_data,output wire[C_FLAT_STATIONS*4-1:0] o_crc_frame_sop,
 output wire[C_FLAT_STATIONS*4-1:0] o_crc_frame_eop,output wire[C_FLAT_STATIONS*36-1:0] o_crc_frame_sequence,
 output wire[C_FLAT_STATIONS*4-1:0] o_crc_frame_replay,output wire[C_FLAT_STATIONS*4-1:0] o_crc_required,
 output wire[C_FLAT_STATIONS*4-1:0] o_physical_valid,output wire[C_FLAT_STATIONS*32-1:0] o_tx_resident_count,
 output wire[C_FLAT_STATIONS-1:0] o_station_busy,output wire[C_FLAT_STATIONS-1:0] o_station_quiescent,
 output wire[C_FLAT_STATIONS-1:0] o_station_error,output wire o_busy,output wire o_quiescent,output wire o_config_error,output wire o_error
);
 wire[C_FLAT_STATIONS-1:0] slot_error;wire[C_FLAT_STATIONS*4-1:0] builder_busy,builder_quiet,builder_error;
 wire[1:0] query_mode;wire[3:0] query_mask;wire query_busy,query_quiet,query_error,index_error;
 ualink_endpoint_station_array #(.C_NUM_STATIONS(C_NUM_STATIONS),.C_FLAT_STATIONS(C_FLAT_STATIONS),.C_REPLAY_DEPTH(C_REPLAY_DEPTH),.C_ADDR_WIDTH(C_ADDR_WIDTH))u_array(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_requested_mode(i_station_requested_mode),.i_mode_commit(i_station_mode_commit),.i_lane_up(i_lane_up),.i_port_link_reset(i_port_link_reset),
  .o_port_slot_enable(o_port_slot_enable),.o_slot_port(o_slot_port),.o_slot_error(slot_error),.o_active_mode(o_active_mode),.o_active_mask(o_active_mask),.o_mode_commit_accept(o_mode_commit_accept),.o_mode_error(o_mode_error),
  .i_tx_tl_valid(i_egress_tl_valid),.o_tx_tl_ready(o_egress_tl_ready),.i_tx_tl_data(i_egress_tl_data),.i_tx_tl_msg(i_egress_tl_msg),.i_tx_tl_sop(i_egress_tl_sop),.i_tx_tl_eop(i_egress_tl_eop),.i_tx_flush(i_egress_flush),
  .i_rx_frame_valid(i_link_rx_frame_valid),.o_rx_frame_ready(o_link_rx_frame_ready),.i_rx_frame_data(i_link_rx_frame_data),.i_rx_frame_sop(i_link_rx_frame_sop),.i_rx_frame_eop(i_link_rx_frame_eop),.i_rx_fec_complete(i_link_rx_fec_complete),.i_rx_crc_ok(i_link_rx_crc_ok),
  .o_rx_tl_valid(o_ingress_tl_valid),.i_rx_tl_ready(i_ingress_tl_ready),.o_rx_tl_data(o_ingress_tl_data),.o_rx_tl_msg(o_ingress_tl_msg),
  .o_tx_control_valid(o_link_control_valid),.i_tx_control_ready(i_link_control_ready),.o_tx_control_replay_request(o_link_control_replay_request),.o_tx_control_target(o_link_control_target),
  .o_crc_input_valid(o_crc_frame_valid),.i_crc_input_ready(i_crc_frame_ready),.o_crc_input_data(o_crc_frame_data),.o_crc_input_sop(o_crc_frame_sop),.o_crc_input_eop(o_crc_frame_eop),.o_crc_input_sequence(o_crc_frame_sequence),.o_crc_input_replay(o_crc_frame_replay),.o_crc_required(o_crc_required),.o_physical_valid(o_physical_valid),.o_tx_resident_count(o_tx_resident_count),
  .o_builder_busy(builder_busy),.o_builder_quiescent(builder_quiet),.o_builder_protocol_error(builder_error),.o_station_busy(o_station_busy),.o_station_quiescent(o_station_quiescent),.o_station_error(o_station_error),.o_busy(o_busy),.o_quiescent(o_quiescent),.o_config_error(o_config_error),.o_error(o_error),
  .i_query_valid(1'b0),.i_query_station(8'd0),.o_query_active_mode(query_mode),.o_query_active_mask(query_mask),.o_query_busy(query_busy),.o_query_quiescent(query_quiet),.o_query_error(query_error),.o_station_index_error(index_error));
 wire unused=^{slot_error,builder_busy,builder_quiet,builder_error,query_mode,query_mask,query_busy,query_quiet,query_error,index_error};
endmodule
`default_nettype wire
