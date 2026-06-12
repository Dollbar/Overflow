`timescale 1ns/1ps
`default_nettype none

// 多Station Endpoint交付组合层：CSR窗口唯一驱动Station mode/link-reset控制，
// 真实Station array状态直接回读。TL、已提交DL frame、CRC模板及hop控制边界保持外露。
// A19 CRC octet映射尚未闭合，因此下层Station array继续令physical valid失败关闭。
module ualink_endpoint_station_managed_top #(
 parameter integer C_NUM_STATIONS=2,
 parameter integer C_FLAT_STATIONS=(C_NUM_STATIONS<1)?1:C_NUM_STATIONS,
 parameter integer C_REPLAY_DEPTH=4,
 parameter integer C_ADDR_WIDTH=(C_REPLAY_DEPTH<=2)?1:(C_REPLAY_DEPTH<=4)?2:(C_REPLAY_DEPTH<=8)?3:(C_REPLAY_DEPTH<=16)?4:(C_REPLAY_DEPTH<=32)?5:(C_REPLAY_DEPTH<=64)?6:(C_REPLAY_DEPTH<=128)?7:8
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire i_csr_req_valid,output wire o_csr_req_ready,input wire i_csr_req_write,
 input wire[15:0] i_csr_req_addr,input wire[31:0] i_csr_req_wdata,
 output wire o_csr_rsp_valid,input wire i_csr_rsp_ready,output wire[31:0] o_csr_rsp_rdata,
 output wire o_csr_rsp_error,output wire o_csr_rsp_unsupported,
 input wire[C_FLAT_STATIONS*4-1:0] i_lane_up,
 output wire[C_FLAT_STATIONS*2-1:0] o_requested_mode,output wire[C_FLAT_STATIONS-1:0] o_mode_commit,
 output wire[C_FLAT_STATIONS*4-1:0] o_port_link_reset,
 output wire[C_FLAT_STATIONS*4-1:0] o_port_slot_enable,output wire[C_FLAT_STATIONS*2-1:0] o_slot_port,
 output wire[C_FLAT_STATIONS-1:0] o_slot_error,output wire[C_FLAT_STATIONS*2-1:0] o_active_mode,
 output wire[C_FLAT_STATIONS*4-1:0] o_active_mask,output wire[C_FLAT_STATIONS-1:0] o_mode_commit_accept,
 output wire[C_FLAT_STATIONS-1:0] o_mode_error,
 input wire[C_FLAT_STATIONS*4-1:0] i_tx_tl_valid,output wire[C_FLAT_STATIONS*4-1:0] o_tx_tl_ready,
 input wire[C_FLAT_STATIONS*2048-1:0] i_tx_tl_data,input wire[C_FLAT_STATIONS*8-1:0] i_tx_tl_msg,
 input wire[C_FLAT_STATIONS*4-1:0] i_tx_tl_sop,input wire[C_FLAT_STATIONS*4-1:0] i_tx_tl_eop,
 input wire[C_FLAT_STATIONS*4-1:0] i_tx_flush,
 input wire[C_FLAT_STATIONS*4-1:0] i_rx_frame_valid,output wire[C_FLAT_STATIONS*4-1:0] o_rx_frame_ready,
 input wire[C_FLAT_STATIONS*2048-1:0] i_rx_frame_data,input wire[C_FLAT_STATIONS*4-1:0] i_rx_frame_sop,
 input wire[C_FLAT_STATIONS*4-1:0] i_rx_frame_eop,input wire[C_FLAT_STATIONS*4-1:0] i_rx_fec_complete,
 input wire[C_FLAT_STATIONS*4-1:0] i_rx_crc_ok,output wire[C_FLAT_STATIONS*4-1:0] o_rx_tl_valid,
 input wire[C_FLAT_STATIONS*4-1:0] i_rx_tl_ready,output wire[C_FLAT_STATIONS*2048-1:0] o_rx_tl_data,
 output wire[C_FLAT_STATIONS*8-1:0] o_rx_tl_msg,
 output wire[C_FLAT_STATIONS*4-1:0] o_tx_control_valid,input wire[C_FLAT_STATIONS*4-1:0] i_tx_control_ready,
 output wire[C_FLAT_STATIONS*4-1:0] o_tx_control_replay_request,
 output wire[C_FLAT_STATIONS*36-1:0] o_tx_control_target,
 output wire[C_FLAT_STATIONS*4-1:0] o_crc_input_valid,input wire[C_FLAT_STATIONS*4-1:0] i_crc_input_ready,
 output wire[C_FLAT_STATIONS*2048-1:0] o_crc_input_data,output wire[C_FLAT_STATIONS*4-1:0] o_crc_input_sop,
 output wire[C_FLAT_STATIONS*4-1:0] o_crc_input_eop,output wire[C_FLAT_STATIONS*36-1:0] o_crc_input_sequence,
 output wire[C_FLAT_STATIONS*4-1:0] o_crc_input_replay,output wire[C_FLAT_STATIONS*4-1:0] o_crc_required,
 output wire[C_FLAT_STATIONS*4-1:0] o_physical_valid,output wire[C_FLAT_STATIONS*32-1:0] o_tx_resident_count,
 output wire[C_FLAT_STATIONS*4-1:0] o_builder_busy,output wire[C_FLAT_STATIONS*4-1:0] o_builder_quiescent,
 output wire[C_FLAT_STATIONS*4-1:0] o_builder_protocol_error,
 output wire[C_FLAT_STATIONS-1:0] o_station_busy,output wire[C_FLAT_STATIONS-1:0] o_station_quiescent,
 output wire[C_FLAT_STATIONS-1:0] o_station_error,output wire o_busy,output wire o_quiescent,
 output wire o_csr_error_sticky,output wire o_security_unsupported,output wire o_config_error,output wire o_error
);
 wire array_config_error,array_error,csr_config_error,csr_error,managed_error;
 wire[1:0] unused_query_mode;wire[3:0] unused_query_mask;
 wire unused_query_busy,unused_query_quiescent,unused_query_error,unused_index_error;
 wire[C_FLAT_STATIONS*4-1:0] unused_request_reject_sticky;

 endpoint_station_csr_window #(.C_NUM_STATIONS(C_NUM_STATIONS),.C_FLAT_STATIONS(C_FLAT_STATIONS))u_csr(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_req_valid(i_csr_req_valid),.o_req_ready(o_csr_req_ready),
  .i_req_write(i_csr_req_write),.i_req_addr(i_csr_req_addr),.i_req_wdata(i_csr_req_wdata),
  .o_rsp_valid(o_csr_rsp_valid),.i_rsp_ready(i_csr_rsp_ready),.o_rsp_rdata(o_csr_rsp_rdata),
  .o_rsp_error(o_csr_rsp_error),.o_rsp_unsupported(o_csr_rsp_unsupported),
  .o_requested_mode(o_requested_mode),.o_mode_commit(o_mode_commit),.o_port_link_reset(o_port_link_reset),
  .i_active_mode(o_active_mode),.i_active_mask(o_active_mask),.i_station_busy(o_station_busy),
  .i_station_quiescent(o_station_quiescent),.i_station_error(o_station_error),
  .i_global_busy(o_busy),.i_global_quiescent(o_quiescent),.i_global_error(managed_error),
  .i_request_reject_pulse({C_FLAT_STATIONS*4{1'b0}}),.o_request_reject_sticky(unused_request_reject_sticky),
  .o_error_sticky(o_csr_error_sticky),.o_unsupported_security(o_security_unsupported),
  .o_config_error(csr_config_error),.o_error(csr_error));

 ualink_endpoint_station_array #(.C_NUM_STATIONS(C_NUM_STATIONS),.C_FLAT_STATIONS(C_FLAT_STATIONS),
  .C_REPLAY_DEPTH(C_REPLAY_DEPTH),.C_ADDR_WIDTH(C_ADDR_WIDTH))u_array(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_requested_mode(o_requested_mode),.i_mode_commit(o_mode_commit),
  .i_lane_up(i_lane_up),.i_port_link_reset(o_port_link_reset),.o_port_slot_enable(o_port_slot_enable),
  .o_slot_port(o_slot_port),.o_slot_error(o_slot_error),.o_active_mode(o_active_mode),.o_active_mask(o_active_mask),
  .o_mode_commit_accept(o_mode_commit_accept),.o_mode_error(o_mode_error),
  .i_tx_tl_valid(i_tx_tl_valid),.o_tx_tl_ready(o_tx_tl_ready),.i_tx_tl_data(i_tx_tl_data),.i_tx_tl_msg(i_tx_tl_msg),
  .i_tx_tl_sop(i_tx_tl_sop),.i_tx_tl_eop(i_tx_tl_eop),.i_tx_flush(i_tx_flush),
  .i_rx_frame_valid(i_rx_frame_valid),.o_rx_frame_ready(o_rx_frame_ready),.i_rx_frame_data(i_rx_frame_data),
  .i_rx_frame_sop(i_rx_frame_sop),.i_rx_frame_eop(i_rx_frame_eop),.i_rx_fec_complete(i_rx_fec_complete),
  .i_rx_crc_ok(i_rx_crc_ok),.o_rx_tl_valid(o_rx_tl_valid),.i_rx_tl_ready(i_rx_tl_ready),
  .o_rx_tl_data(o_rx_tl_data),.o_rx_tl_msg(o_rx_tl_msg),.o_tx_control_valid(o_tx_control_valid),
  .i_tx_control_ready(i_tx_control_ready),.o_tx_control_replay_request(o_tx_control_replay_request),
  .o_tx_control_target(o_tx_control_target),.o_crc_input_valid(o_crc_input_valid),.i_crc_input_ready(i_crc_input_ready),
  .o_crc_input_data(o_crc_input_data),.o_crc_input_sop(o_crc_input_sop),.o_crc_input_eop(o_crc_input_eop),
  .o_crc_input_sequence(o_crc_input_sequence),.o_crc_input_replay(o_crc_input_replay),.o_crc_required(o_crc_required),
  .o_physical_valid(o_physical_valid),.o_tx_resident_count(o_tx_resident_count),.o_builder_busy(o_builder_busy),
  .o_builder_quiescent(o_builder_quiescent),.o_builder_protocol_error(o_builder_protocol_error),
  .o_station_busy(o_station_busy),.o_station_quiescent(o_station_quiescent),.o_station_error(o_station_error),
  .o_busy(o_busy),.o_quiescent(o_quiescent),.o_config_error(array_config_error),.o_error(array_error),
  .i_query_valid(1'b0),.i_query_station(8'd0),.o_query_active_mode(unused_query_mode),
  .o_query_active_mask(unused_query_mask),.o_query_busy(unused_query_busy),.o_query_quiescent(unused_query_quiescent),
  .o_query_error(unused_query_error),.o_station_index_error(unused_index_error));

 assign o_config_error=array_config_error||csr_config_error;
 assign managed_error=array_error||csr_error||o_config_error;
 assign o_error=managed_error;
 wire unused_status=^{unused_query_mode,unused_query_mask,unused_query_busy,unused_query_quiescent,
  unused_request_reject_sticky,
  unused_query_error,unused_index_error};
endmodule
`default_nettype wire
