`timescale 1ns/1ps
`default_nettype none
// Managed Endpoint的逐Station rate重配接线层。只门控“新事务准入”，不阻塞已在途
// completion/RX/replay drain；调用者必须把同一ready/valid对应的payload接到本模块。
// 原managed top ABI保持不变，本模块提供其下一次组合时所需的显式接点。
module endpoint_station_rate_managed_admission_gate #(
 parameter integer C_NUM_STATIONS=2,parameter integer C_FLAT_STATIONS=(C_NUM_STATIONS<1)?1:C_NUM_STATIONS,
 parameter integer C_RATE_WIDTH=16,parameter integer C_ADMISSION_PAYLOAD_WIDTH=128,
 parameter integer C_ACK_TIMEOUT_CYCLES=64
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire[C_FLAT_STATIONS-1:0] i_rate_request_valid,output wire[C_FLAT_STATIONS-1:0] o_rate_request_ready,
 input wire[C_FLAT_STATIONS*4-1:0] i_active_mask,input wire[C_FLAT_STATIONS*4*C_RATE_WIDTH-1:0] i_requested_rate_code,
 input wire[C_FLAT_STATIONS*4-1:0] i_requested_rate_legal,input wire[C_FLAT_STATIONS-1:0] i_station_quiescent,
 input wire[C_FLAT_STATIONS-1:0] i_station_busy,input wire[C_FLAT_STATIONS*4-1:0] i_port_link_reset,
 output wire[C_FLAT_STATIONS-1:0] o_rate_request_accept,output wire[C_FLAT_STATIONS-1:0] o_rate_request_reject,
 output wire[C_FLAT_STATIONS-1:0] o_rate_drain_request,output wire[C_FLAT_STATIONS-1:0] o_rate_admission_enable,
 output wire[C_FLAT_STATIONS*4-1:0] o_notify_valid,input wire[C_FLAT_STATIONS*4-1:0] i_notify_ready,
 output wire[C_FLAT_STATIONS*4*C_RATE_WIDTH-1:0] o_notify_rate_code,
 input wire[C_FLAT_STATIONS*4-1:0] i_notify_ack_valid,output wire[C_FLAT_STATIONS*4-1:0] o_notify_ack_ready,
 input wire[C_FLAT_STATIONS*4-1:0] i_notify_ack_success,input wire[C_FLAT_STATIONS*4*C_RATE_WIDTH-1:0] i_notify_ack_rate_code,
 output wire[C_FLAT_STATIONS*4-1:0] o_pacing_rate_valid,input wire[C_FLAT_STATIONS*4-1:0] i_pacing_rate_ready,
 output wire[C_FLAT_STATIONS*4*C_RATE_WIDTH-1:0] o_pacing_rate_code,
 input wire[C_FLAT_STATIONS*4-1:0] i_pacing_rate_accept,input wire[C_FLAT_STATIONS*4-1:0] i_pacing_rate_error,
 output wire[C_FLAT_STATIONS*4-1:0] o_rate_configured,output wire[C_FLAT_STATIONS*4*C_RATE_WIDTH-1:0] o_active_rate_code,
 input wire[C_FLAT_STATIONS-1:0] i_admission_valid,output wire[C_FLAT_STATIONS-1:0] o_admission_ready,
 input wire[C_FLAT_STATIONS*C_ADMISSION_PAYLOAD_WIDTH-1:0] i_admission_payload,
 output wire[C_FLAT_STATIONS-1:0] o_downstream_valid,input wire[C_FLAT_STATIONS-1:0] i_downstream_ready,
 output wire[C_FLAT_STATIONS*C_ADMISSION_PAYLOAD_WIDTH-1:0] o_downstream_payload,
 output wire[C_FLAT_STATIONS-1:0] o_mode_commit_busy,output wire[C_FLAT_STATIONS-1:0] o_owner_busy,
 output wire[C_FLAT_STATIONS-1:0] o_owner_quiescent,output wire[C_FLAT_STATIONS-1:0] o_timeout_error,
 output wire[C_FLAT_STATIONS-1:0] o_protocol_error,output wire[C_FLAT_STATIONS-1:0] o_config_error,
 output wire[C_FLAT_STATIONS-1:0] o_error
);
localparam C_CONFIG_LEGAL=(C_NUM_STATIONS>=1)&&(C_NUM_STATIONS<=256)&&(C_FLAT_STATIONS==C_NUM_STATIONS)&&
 (C_RATE_WIDTH>=1)&&(C_RATE_WIDTH<=64)&&(C_ADMISSION_PAYLOAD_WIDTH>=1)&&(C_ADMISSION_PAYLOAD_WIDTH<=4096);
wire[C_FLAT_STATIONS-1:0] owner_request_ready,owner_request_accept,owner_request_reject,owner_drain,owner_admission;
wire[C_FLAT_STATIONS-1:0] owner_config_error,owner_error,owner_busy,owner_quiescent,owner_timeout_error,owner_protocol_error;
wire[C_FLAT_STATIONS*4-1:0] owner_notify_valid,owner_notify_ack_ready,owner_apply_valid,owner_rate_configured;
wire[C_FLAT_STATIONS*4*C_RATE_WIDTH-1:0] owner_notify_rate_code,owner_apply_rate_code,owner_active_rate_code;
wire owner_global_busy,owner_global_quiescent,owner_global_error;
wire[C_FLAT_STATIONS-1:0] station_gate=owner_admission&~i_rate_request_valid;

endpoint_station_rate_reconfiguration_array #(.C_NUM_STATIONS(C_NUM_STATIONS),.C_FLAT_STATIONS(C_FLAT_STATIONS),
 .C_RATE_WIDTH(C_RATE_WIDTH),.C_ACK_TIMEOUT_CYCLES(C_ACK_TIMEOUT_CYCLES))u_rate_owner(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_request_valid(i_rate_request_valid),.o_request_ready(owner_request_ready),
 .i_active_mask(i_active_mask),.i_requested_rate_code(i_requested_rate_code),.i_requested_rate_legal(i_requested_rate_legal),
 .i_station_quiescent(i_station_quiescent),.i_port_link_reset(i_port_link_reset),.o_request_accept(owner_request_accept),
 .o_request_reject(owner_request_reject),.o_drain_request(owner_drain),.o_admission_enable(owner_admission),
 .o_notify_valid(owner_notify_valid),.i_notify_ready(i_notify_ready),.o_notify_rate_code(owner_notify_rate_code),
 .i_notify_ack_valid(i_notify_ack_valid),.o_notify_ack_ready(owner_notify_ack_ready),.i_notify_ack_success(i_notify_ack_success),
 .i_notify_ack_rate_code(i_notify_ack_rate_code),.o_apply_valid(owner_apply_valid),.i_apply_ready(i_pacing_rate_ready),
 .o_apply_rate_code(owner_apply_rate_code),.i_apply_accept(i_pacing_rate_accept),.i_apply_error(i_pacing_rate_error),
 .o_rate_configured(owner_rate_configured),.o_active_rate_code(owner_active_rate_code),.o_busy(owner_busy),.o_quiescent(owner_quiescent),
 .o_timeout_error(owner_timeout_error),.o_protocol_error(owner_protocol_error),.o_config_error(owner_config_error),.o_error(owner_error),
 .o_global_busy(owner_global_busy),.o_global_quiescent(owner_global_quiescent),.o_global_error(owner_global_error));

assign o_rate_request_ready=C_CONFIG_LEGAL?owner_request_ready:{C_FLAT_STATIONS{1'b0}};
assign o_rate_request_accept=C_CONFIG_LEGAL?owner_request_accept:{C_FLAT_STATIONS{1'b0}};
assign o_rate_request_reject=C_CONFIG_LEGAL?owner_request_reject:{C_FLAT_STATIONS{1'b0}};
assign o_rate_drain_request=C_CONFIG_LEGAL?owner_drain:{C_FLAT_STATIONS{1'b0}};
assign o_rate_admission_enable=C_CONFIG_LEGAL?owner_admission:{C_FLAT_STATIONS{1'b0}};
assign o_notify_valid=C_CONFIG_LEGAL?owner_notify_valid:{(C_FLAT_STATIONS*4){1'b0}};
assign o_notify_rate_code=C_CONFIG_LEGAL?owner_notify_rate_code:{(C_FLAT_STATIONS*4*C_RATE_WIDTH){1'b0}};
assign o_notify_ack_ready=C_CONFIG_LEGAL?owner_notify_ack_ready:{(C_FLAT_STATIONS*4){1'b0}};
assign o_pacing_rate_valid=C_CONFIG_LEGAL?owner_apply_valid:{(C_FLAT_STATIONS*4){1'b0}};
assign o_pacing_rate_code=C_CONFIG_LEGAL?owner_apply_rate_code:{(C_FLAT_STATIONS*4*C_RATE_WIDTH){1'b0}};
assign o_rate_configured=C_CONFIG_LEGAL?owner_rate_configured:{(C_FLAT_STATIONS*4){1'b0}};
assign o_active_rate_code=C_CONFIG_LEGAL?owner_active_rate_code:{(C_FLAT_STATIONS*4*C_RATE_WIDTH){1'b0}};
assign o_admission_ready=C_CONFIG_LEGAL?(i_downstream_ready&station_gate):{C_FLAT_STATIONS{1'b0}};
assign o_downstream_valid=C_CONFIG_LEGAL?(i_admission_valid&station_gate):{C_FLAT_STATIONS{1'b0}};
assign o_downstream_payload=C_CONFIG_LEGAL?i_admission_payload:{(C_FLAT_STATIONS*C_ADMISSION_PAYLOAD_WIDTH){1'b0}};
assign o_mode_commit_busy=C_CONFIG_LEGAL?(i_station_busy|owner_busy):{C_FLAT_STATIONS{1'b1}};
assign o_owner_busy=C_CONFIG_LEGAL?owner_busy:{C_FLAT_STATIONS{1'b0}};
assign o_owner_quiescent=C_CONFIG_LEGAL?owner_quiescent:{C_FLAT_STATIONS{1'b0}};
assign o_timeout_error=C_CONFIG_LEGAL?owner_timeout_error:{C_FLAT_STATIONS{1'b0}};
assign o_protocol_error=C_CONFIG_LEGAL?owner_protocol_error:{C_FLAT_STATIONS{1'b0}};
assign o_config_error=owner_config_error|{C_FLAT_STATIONS{!C_CONFIG_LEGAL}};
assign o_error=owner_error|{C_FLAT_STATIONS{!C_CONFIG_LEGAL}};
wire unused_global=owner_global_busy^owner_global_quiescent^owner_global_error;
endmodule
`default_nettype wire
