`timescale 1ns/1ps
`default_nettype none
// 多Station平坦阵列只复制事务owner；每Station状态、timeout、rate和link reset完全独立。
module endpoint_station_rate_reconfiguration_array #(
 parameter integer C_NUM_STATIONS=2,parameter integer C_FLAT_STATIONS=(C_NUM_STATIONS<1)?1:C_NUM_STATIONS,
 parameter integer C_RATE_WIDTH=16,parameter integer C_ACK_TIMEOUT_CYCLES=64
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire[C_FLAT_STATIONS-1:0] i_request_valid,output wire[C_FLAT_STATIONS-1:0] o_request_ready,
 input wire[C_FLAT_STATIONS*4-1:0] i_active_mask,input wire[C_FLAT_STATIONS*4*C_RATE_WIDTH-1:0] i_requested_rate_code,
 input wire[C_FLAT_STATIONS*4-1:0] i_requested_rate_legal,input wire[C_FLAT_STATIONS-1:0] i_station_quiescent,
 input wire[C_FLAT_STATIONS*4-1:0] i_port_link_reset,output wire[C_FLAT_STATIONS-1:0] o_request_accept,
 output wire[C_FLAT_STATIONS-1:0] o_request_reject,output wire[C_FLAT_STATIONS-1:0] o_drain_request,
 output wire[C_FLAT_STATIONS-1:0] o_admission_enable,output wire[C_FLAT_STATIONS*4-1:0] o_notify_valid,
 input wire[C_FLAT_STATIONS*4-1:0] i_notify_ready,output wire[C_FLAT_STATIONS*4*C_RATE_WIDTH-1:0] o_notify_rate_code,
 input wire[C_FLAT_STATIONS*4-1:0] i_notify_ack_valid,output wire[C_FLAT_STATIONS*4-1:0] o_notify_ack_ready,
 input wire[C_FLAT_STATIONS*4-1:0] i_notify_ack_success,input wire[C_FLAT_STATIONS*4*C_RATE_WIDTH-1:0] i_notify_ack_rate_code,
 output wire[C_FLAT_STATIONS*4-1:0] o_apply_valid,input wire[C_FLAT_STATIONS*4-1:0] i_apply_ready,
 output wire[C_FLAT_STATIONS*4*C_RATE_WIDTH-1:0] o_apply_rate_code,input wire[C_FLAT_STATIONS*4-1:0] i_apply_accept,
 input wire[C_FLAT_STATIONS*4-1:0] i_apply_error,output wire[C_FLAT_STATIONS*4-1:0] o_rate_configured,
 output wire[C_FLAT_STATIONS*4*C_RATE_WIDTH-1:0] o_active_rate_code,output wire[C_FLAT_STATIONS-1:0] o_busy,
 output wire[C_FLAT_STATIONS-1:0] o_quiescent,output wire[C_FLAT_STATIONS-1:0] o_timeout_error,
 output wire[C_FLAT_STATIONS-1:0] o_protocol_error,output wire[C_FLAT_STATIONS-1:0] o_config_error,
 output wire[C_FLAT_STATIONS-1:0] o_error,output wire o_global_busy,output wire o_global_quiescent,output wire o_global_error
);
localparam C_CONFIG_LEGAL=(C_NUM_STATIONS>=1)&&(C_NUM_STATIONS<=256)&&(C_FLAT_STATIONS==C_NUM_STATIONS);
genvar station;
generate if(C_CONFIG_LEGAL)begin:gen_legal
 for(station=0;station<C_FLAT_STATIONS;station=station+1)begin:gen_station
  endpoint_station_rate_reconfiguration_owner #(.C_RATE_WIDTH(C_RATE_WIDTH),.C_ACK_TIMEOUT_CYCLES(C_ACK_TIMEOUT_CYCLES))u_owner(
   .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_request_valid(i_request_valid[station]),.o_request_ready(o_request_ready[station]),
   .i_active_mask(i_active_mask[station*4+:4]),.i_requested_rate_code(i_requested_rate_code[station*4*C_RATE_WIDTH+:4*C_RATE_WIDTH]),
   .i_requested_rate_legal(i_requested_rate_legal[station*4+:4]),.i_station_quiescent(i_station_quiescent[station]),
   .i_port_link_reset(i_port_link_reset[station*4+:4]),.o_request_accept(o_request_accept[station]),.o_request_reject(o_request_reject[station]),
   .o_drain_request(o_drain_request[station]),.o_admission_enable(o_admission_enable[station]),
   .o_notify_valid(o_notify_valid[station*4+:4]),.i_notify_ready(i_notify_ready[station*4+:4]),
   .o_notify_rate_code(o_notify_rate_code[station*4*C_RATE_WIDTH+:4*C_RATE_WIDTH]),.i_notify_ack_valid(i_notify_ack_valid[station*4+:4]),
   .o_notify_ack_ready(o_notify_ack_ready[station*4+:4]),.i_notify_ack_success(i_notify_ack_success[station*4+:4]),
   .i_notify_ack_rate_code(i_notify_ack_rate_code[station*4*C_RATE_WIDTH+:4*C_RATE_WIDTH]),.o_apply_valid(o_apply_valid[station*4+:4]),
   .i_apply_ready(i_apply_ready[station*4+:4]),.o_apply_rate_code(o_apply_rate_code[station*4*C_RATE_WIDTH+:4*C_RATE_WIDTH]),
   .i_apply_accept(i_apply_accept[station*4+:4]),.i_apply_error(i_apply_error[station*4+:4]),
   .o_rate_configured(o_rate_configured[station*4+:4]),.o_active_rate_code(o_active_rate_code[station*4*C_RATE_WIDTH+:4*C_RATE_WIDTH]),
   .o_busy(o_busy[station]),.o_quiescent(o_quiescent[station]),.o_timeout_error(o_timeout_error[station]),
   .o_protocol_error(o_protocol_error[station]),.o_config_error(o_config_error[station]),.o_error(o_error[station]));
 end
 assign o_global_busy=|o_busy;assign o_global_quiescent=&o_quiescent;assign o_global_error=|o_error;
end else begin:gen_illegal
 assign o_request_ready={C_FLAT_STATIONS{1'b0}};assign o_request_accept={C_FLAT_STATIONS{1'b0}};assign o_request_reject={C_FLAT_STATIONS{1'b0}};
 assign o_drain_request={C_FLAT_STATIONS{1'b0}};assign o_admission_enable={C_FLAT_STATIONS{1'b0}};assign o_notify_valid={(C_FLAT_STATIONS*4){1'b0}};
 assign o_notify_rate_code={(C_FLAT_STATIONS*4*C_RATE_WIDTH){1'b0}};assign o_notify_ack_ready={(C_FLAT_STATIONS*4){1'b0}};
 assign o_apply_valid={(C_FLAT_STATIONS*4){1'b0}};assign o_apply_rate_code={(C_FLAT_STATIONS*4*C_RATE_WIDTH){1'b0}};
 assign o_rate_configured={(C_FLAT_STATIONS*4){1'b0}};assign o_active_rate_code={(C_FLAT_STATIONS*4*C_RATE_WIDTH){1'b0}};
 assign o_busy={C_FLAT_STATIONS{1'b0}};assign o_quiescent={C_FLAT_STATIONS{1'b0}};assign o_timeout_error={C_FLAT_STATIONS{1'b0}};
 assign o_protocol_error={C_FLAT_STATIONS{1'b0}};assign o_config_error={C_FLAT_STATIONS{1'b1}};assign o_error={C_FLAT_STATIONS{1'b1}};
 assign o_global_busy=1'b0;assign o_global_quiescent=1'b0;assign o_global_error=1'b1;
end endgenerate
endmodule
`default_nettype wire
