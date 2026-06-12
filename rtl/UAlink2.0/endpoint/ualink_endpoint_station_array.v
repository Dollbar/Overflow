`timescale 1ns/1ps
`default_nettype none

// 参数化Endpoint Station阵列。每个Station完整拥有自己的四端口日历、DL RX sequence、
// TX replay与控制上下文；阵列只共享时钟和全局enable，不共享任何协议状态。
// C_FLAT_STATIONS仅用于让非法C_NUM_STATIONS=0仍有合法端口宽度，禁止独立覆盖。
module ualink_endpoint_station_array #(
 parameter integer C_NUM_STATIONS=2,
 parameter integer C_FLAT_STATIONS=(C_NUM_STATIONS<1)?1:C_NUM_STATIONS,
 parameter integer C_REPLAY_DEPTH=4,
 parameter integer C_ADDR_WIDTH=(C_REPLAY_DEPTH<=2)?1:(C_REPLAY_DEPTH<=4)?2:(C_REPLAY_DEPTH<=8)?3:(C_REPLAY_DEPTH<=16)?4:(C_REPLAY_DEPTH<=32)?5:(C_REPLAY_DEPTH<=64)?6:(C_REPLAY_DEPTH<=128)?7:8
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire[C_FLAT_STATIONS*2-1:0] i_requested_mode,input wire[C_FLAT_STATIONS-1:0] i_mode_commit,
 input wire[C_FLAT_STATIONS*4-1:0] i_lane_up,input wire[C_FLAT_STATIONS*4-1:0] i_port_link_reset,
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
 output wire[C_FLAT_STATIONS*4-1:0] o_tx_control_replay_request,output wire[C_FLAT_STATIONS*36-1:0] o_tx_control_target,
 output wire[C_FLAT_STATIONS*4-1:0] o_crc_input_valid,input wire[C_FLAT_STATIONS*4-1:0] i_crc_input_ready,
 output wire[C_FLAT_STATIONS*2048-1:0] o_crc_input_data,output wire[C_FLAT_STATIONS*4-1:0] o_crc_input_sop,
 output wire[C_FLAT_STATIONS*4-1:0] o_crc_input_eop,output wire[C_FLAT_STATIONS*36-1:0] o_crc_input_sequence,
 output wire[C_FLAT_STATIONS*4-1:0] o_crc_input_replay,output wire[C_FLAT_STATIONS*4-1:0] o_crc_required,
 output wire[C_FLAT_STATIONS*4-1:0] o_physical_valid,output wire[C_FLAT_STATIONS*32-1:0] o_tx_resident_count,
 output wire[C_FLAT_STATIONS*4-1:0] o_builder_busy,output wire[C_FLAT_STATIONS*4-1:0] o_builder_quiescent,
 output wire[C_FLAT_STATIONS*4-1:0] o_builder_protocol_error,output wire[C_FLAT_STATIONS-1:0] o_station_busy,
 output wire[C_FLAT_STATIONS-1:0] o_station_quiescent,output wire[C_FLAT_STATIONS-1:0] o_station_error,
 output wire o_busy,output wire o_quiescent,output wire o_config_error,output wire o_error,
 input wire i_query_valid,input wire[7:0] i_query_station,output reg[1:0] o_query_active_mode,
 output reg[3:0] o_query_active_mask,output reg o_query_busy,output reg o_query_quiescent,
 output reg o_query_error,output wire o_station_index_error
);
localparam CONFIG_LEGAL=(C_NUM_STATIONS>=1)&&(C_NUM_STATIONS<=256)&&(C_FLAT_STATIONS==C_NUM_STATIONS);
wire[31:0] query_index_32={24'd0,i_query_station};
wire query_legal=CONFIG_LEGAL&&((C_NUM_STATIONS==256)||(query_index_32<C_NUM_STATIONS));
assign o_config_error=!CONFIG_LEGAL;
assign o_station_index_error=i_rstn&&i_enable&&i_query_valid&&!query_legal;
assign o_busy=CONFIG_LEGAL&&i_rstn&&(|o_station_busy);
assign o_quiescent=CONFIG_LEGAL&&i_rstn&&(&o_station_quiescent);
assign o_error=o_config_error||o_station_index_error||(|o_station_error)||(|o_slot_error);
integer query_scan;
always @* begin
 o_query_active_mode=2'd0;o_query_active_mask=4'd0;o_query_busy=1'b0;o_query_quiescent=1'b0;o_query_error=1'b0;
 if(i_query_valid&&query_legal)begin
  for(query_scan=0;query_scan<C_NUM_STATIONS;query_scan=query_scan+1)begin
   if(i_query_station==query_scan[7:0])begin
    o_query_active_mode=o_active_mode[query_scan*2+:2];o_query_active_mask=o_active_mask[query_scan*4+:4];
    o_query_busy=o_station_busy[query_scan];o_query_quiescent=o_station_quiescent[query_scan];o_query_error=o_station_error[query_scan];
   end
  end
 end
end
genvar s;
generate if(CONFIG_LEGAL)begin:gen_legal
 wire[C_NUM_STATIONS*32-1:0] station_tx_unacked_count;
 wire[C_NUM_STATIONS*36-1:0] station_rx_last_sequence;
 wire[C_NUM_STATIONS*12-1:0] station_rx_bad_crc_count;
 wire[C_NUM_STATIONS*32-1:0] station_rx_unexpected_count;
 wire[C_NUM_STATIONS*4-1:0] station_rx_ambiguous;
 wire[C_NUM_STATIONS*4-1:0] station_rx_in_replay;
 wire[C_NUM_STATIONS*4-1:0] station_rx_port_quiescent;
 // 当前array ABI尚未向上暴露逐Port诊断；显式捕获，避免丢失子模块端口所有权。
 wire unused_station_diagnostics=^{station_tx_unacked_count,station_rx_last_sequence,
  station_rx_bad_crc_count,station_rx_unexpected_count,station_rx_ambiguous,
  station_rx_in_replay,station_rx_port_quiescent};
 for(s=0;s<C_NUM_STATIONS;s=s+1)begin:gen_station
  endpoint_station_dl_scheduled_path #(.C_REPLAY_DEPTH(C_REPLAY_DEPTH),.C_ADDR_WIDTH(C_ADDR_WIDTH)) u_station(
   .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_ras_rx_cleanup(4'b0000),.i_requested_mode(i_requested_mode[s*2+:2]),.i_mode_commit(i_mode_commit[s]),.i_lane_up(i_lane_up[s*4+:4]),.i_port_link_reset(i_port_link_reset[s*4+:4]),
   .o_port_slot_enable(o_port_slot_enable[s*4+:4]),.o_slot_port(o_slot_port[s*2+:2]),.o_slot_error(o_slot_error[s]),.o_active_mode(o_active_mode[s*2+:2]),.o_active_mask(o_active_mask[s*4+:4]),.o_mode_commit_accept(o_mode_commit_accept[s]),.o_mode_error(o_mode_error[s]),
   .i_tx_tl_valid(i_tx_tl_valid[s*4+:4]),.o_tx_tl_ready(o_tx_tl_ready[s*4+:4]),.i_tx_tl_data(i_tx_tl_data[s*2048+:2048]),.i_tx_tl_msg(i_tx_tl_msg[s*8+:8]),.i_tx_tl_sop(i_tx_tl_sop[s*4+:4]),.i_tx_tl_eop(i_tx_tl_eop[s*4+:4]),.i_tx_flush(i_tx_flush[s*4+:4]),
   .i_rx_frame_valid(i_rx_frame_valid[s*4+:4]),.o_rx_frame_ready(o_rx_frame_ready[s*4+:4]),.i_rx_frame_data(i_rx_frame_data[s*2048+:2048]),.i_rx_frame_sop(i_rx_frame_sop[s*4+:4]),.i_rx_frame_eop(i_rx_frame_eop[s*4+:4]),.i_rx_fec_complete(i_rx_fec_complete[s*4+:4]),.i_rx_crc_ok(i_rx_crc_ok[s*4+:4]),.o_rx_tl_valid(o_rx_tl_valid[s*4+:4]),.i_rx_tl_ready(i_rx_tl_ready[s*4+:4]),.o_rx_tl_data(o_rx_tl_data[s*2048+:2048]),.o_rx_tl_msg(o_rx_tl_msg[s*8+:8]),
   .o_tx_control_valid(o_tx_control_valid[s*4+:4]),.i_tx_control_ready(i_tx_control_ready[s*4+:4]),.o_tx_control_replay_request(o_tx_control_replay_request[s*4+:4]),.o_tx_control_target(o_tx_control_target[s*36+:36]),.o_crc_input_valid(o_crc_input_valid[s*4+:4]),.i_crc_input_ready(i_crc_input_ready[s*4+:4]),.o_crc_input_data(o_crc_input_data[s*2048+:2048]),.o_crc_input_sop(o_crc_input_sop[s*4+:4]),.o_crc_input_eop(o_crc_input_eop[s*4+:4]),.o_crc_input_sequence(o_crc_input_sequence[s*36+:36]),.o_crc_input_replay(o_crc_input_replay[s*4+:4]),.o_crc_required(o_crc_required[s*4+:4]),.o_physical_valid(o_physical_valid[s*4+:4]),.o_tx_resident_count(o_tx_resident_count[s*32+:32]),.o_tx_unacked_count(station_tx_unacked_count[s*32+:32]),.o_rx_last_sequence(station_rx_last_sequence[s*36+:36]),.o_rx_bad_crc_count(station_rx_bad_crc_count[s*12+:12]),.o_rx_unexpected_count(station_rx_unexpected_count[s*32+:32]),.o_rx_ambiguous(station_rx_ambiguous[s*4+:4]),.o_rx_in_replay(station_rx_in_replay[s*4+:4]),.o_rx_port_quiescent(station_rx_port_quiescent[s*4+:4]),.o_builder_busy(o_builder_busy[s*4+:4]),.o_builder_quiescent(o_builder_quiescent[s*4+:4]),.o_builder_protocol_error(o_builder_protocol_error[s*4+:4]),.o_busy(o_station_busy[s]),.o_quiescent(o_station_quiescent[s]),.o_error(o_station_error[s]));
 end
end else begin:gen_illegal
 assign o_port_slot_enable={C_FLAT_STATIONS*4{1'b0}};assign o_slot_port={C_FLAT_STATIONS*2{1'b0}};assign o_slot_error={C_FLAT_STATIONS{1'b0}};assign o_active_mode={C_FLAT_STATIONS*2{1'b0}};assign o_active_mask={C_FLAT_STATIONS*4{1'b0}};assign o_mode_commit_accept={C_FLAT_STATIONS{1'b0}};assign o_mode_error={C_FLAT_STATIONS{1'b0}};
 assign o_tx_tl_ready={C_FLAT_STATIONS*4{1'b0}};assign o_rx_frame_ready={C_FLAT_STATIONS*4{1'b0}};assign o_rx_tl_valid={C_FLAT_STATIONS*4{1'b0}};assign o_rx_tl_data={C_FLAT_STATIONS*2048{1'b0}};assign o_rx_tl_msg={C_FLAT_STATIONS*8{1'b0}};assign o_tx_control_valid={C_FLAT_STATIONS*4{1'b0}};assign o_tx_control_replay_request={C_FLAT_STATIONS*4{1'b0}};assign o_tx_control_target={C_FLAT_STATIONS*36{1'b0}};
 assign o_crc_input_valid={C_FLAT_STATIONS*4{1'b0}};assign o_crc_input_data={C_FLAT_STATIONS*2048{1'b0}};assign o_crc_input_sop={C_FLAT_STATIONS*4{1'b0}};assign o_crc_input_eop={C_FLAT_STATIONS*4{1'b0}};assign o_crc_input_sequence={C_FLAT_STATIONS*36{1'b0}};assign o_crc_input_replay={C_FLAT_STATIONS*4{1'b0}};assign o_crc_required={C_FLAT_STATIONS*4{1'b0}};assign o_physical_valid={C_FLAT_STATIONS*4{1'b0}};assign o_tx_resident_count={C_FLAT_STATIONS*32{1'b0}};
 assign o_builder_busy={C_FLAT_STATIONS*4{1'b0}};assign o_builder_quiescent={C_FLAT_STATIONS*4{1'b0}};assign o_builder_protocol_error={C_FLAT_STATIONS*4{1'b0}};assign o_station_busy={C_FLAT_STATIONS{1'b0}};assign o_station_quiescent={C_FLAT_STATIONS{1'b0}};assign o_station_error={C_FLAT_STATIONS{1'b0}};
end endgenerate
endmodule
`default_nettype wire
