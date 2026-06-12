`timescale 1ns/1ps
`default_nettype none
// 最多256个互不共享状态的Station mode重配置所有者阵列。
module endpoint_station_mode_reconfiguration_array #(
 parameter integer C_NUM_STATIONS=2,parameter integer C_FLAT_STATIONS=(C_NUM_STATIONS<1)?1:C_NUM_STATIONS
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire[C_FLAT_STATIONS-1:0] i_request_valid,output wire[C_FLAT_STATIONS-1:0] o_request_ready,
 input wire[C_FLAT_STATIONS*2-1:0] i_requested_mode,input wire[C_FLAT_STATIONS-1:0] i_station_quiescent,
 input wire[C_FLAT_STATIONS*4-1:0] i_lane_up,input wire[C_FLAT_STATIONS-1:0] i_mode_commit_accept,
 input wire[C_FLAT_STATIONS*2-1:0] i_active_mode,input wire[C_FLAT_STATIONS*4-1:0] i_active_mask,
 input wire[C_FLAT_STATIONS*4-1:0] i_local_done,input wire[C_FLAT_STATIONS*4-1:0] i_peer_done,
 input wire[C_FLAT_STATIONS*4-1:0] i_external_link_reset,
 output wire[C_FLAT_STATIONS-1:0] o_request_accept,output wire[C_FLAT_STATIONS-1:0] o_request_reject,
 output wire[C_FLAT_STATIONS-1:0] o_admission_enable,output wire[C_FLAT_STATIONS*4-1:0] o_link_reset,
 output wire[C_FLAT_STATIONS-1:0] o_mode_commit,output wire[C_FLAT_STATIONS*4-1:0] o_reinit_start,
 output wire[C_FLAT_STATIONS-1:0] o_busy,output wire[C_FLAT_STATIONS-1:0] o_quiescent,
 output wire[C_FLAT_STATIONS-1:0] o_error
);
 localparam CONFIG_LEGAL=(C_NUM_STATIONS>=1)&&(C_NUM_STATIONS<=256)&&(C_FLAT_STATIONS==C_NUM_STATIONS);
 genvar s;generate if(CONFIG_LEGAL)begin:gen_legal
  for(s=0;s<C_NUM_STATIONS;s=s+1)begin:gen_station
   wire protocol_error,owner_error;
   endpoint_station_mode_reconfiguration_owner u_owner(
    .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_request_valid(i_request_valid[s]),
    .o_request_ready(o_request_ready[s]),.i_requested_mode(i_requested_mode[s*2+:2]),
    .i_station_quiescent(i_station_quiescent[s]),.i_lane_up(i_lane_up[s*4+:4]),
    .i_mode_commit_accept(i_mode_commit_accept[s]),.i_active_mode(i_active_mode[s*2+:2]),
    .i_active_mask(i_active_mask[s*4+:4]),.i_local_done(i_local_done[s*4+:4]),
    .i_peer_done(i_peer_done[s*4+:4]),.i_external_link_reset(i_external_link_reset[s*4+:4]),
    .o_request_accept(o_request_accept[s]),.o_request_reject(o_request_reject[s]),
    .o_admission_enable(o_admission_enable[s]),.o_link_reset(o_link_reset[s*4+:4]),
    .o_mode_commit(o_mode_commit[s]),.o_reinit_start(o_reinit_start[s*4+:4]),
    .o_busy(o_busy[s]),.o_quiescent(o_quiescent[s]),.o_protocol_error(protocol_error),.o_error(owner_error));
   assign o_error[s]=owner_error|protocol_error;
  end
 end else begin:gen_illegal
  assign o_request_ready={C_FLAT_STATIONS{1'b0}};assign o_request_accept={C_FLAT_STATIONS{1'b0}};
  assign o_request_reject={C_FLAT_STATIONS{1'b0}};assign o_admission_enable={C_FLAT_STATIONS{1'b0}};
  assign o_link_reset={(C_FLAT_STATIONS*4){1'b0}};assign o_mode_commit={C_FLAT_STATIONS{1'b0}};
  assign o_reinit_start={(C_FLAT_STATIONS*4){1'b0}};assign o_busy={C_FLAT_STATIONS{1'b0}};
  assign o_quiescent={C_FLAT_STATIONS{1'b0}};assign o_error={C_FLAT_STATIONS{1'b1}};
 end endgenerate
endmodule
`default_nettype wire
