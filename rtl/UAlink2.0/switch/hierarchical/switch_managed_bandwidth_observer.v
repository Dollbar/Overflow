`timescale 1ns/1ps
`default_nettype none
// 两个独立只读计量器；attempt由ready/valid tenure恢复，绝不反馈到数据通路。
module switch_managed_bandwidth_observer #(
 parameter integer C_PORTS=32,parameter integer C_COUNTER_WIDTH=64,
 parameter integer C_PAYLOAD_BYTES_WIDTH=7
)(
 input wire i_clk,input wire i_rstn,input wire i_window_start,input wire i_window_stop,
 input wire [C_PORTS-1:0] i_ingress_committed_valid,input wire [C_PORTS-1:0] i_ingress_committed_ready,
 input wire [C_PORTS-1:0] i_egress_retired_valid,input wire [C_PORTS-1:0] i_egress_retired_ready,
 output wire o_ingress_window_active,output wire o_ingress_window_done,
 output wire [C_COUNTER_WIDTH-1:0] o_ingress_measurement_cycles,
 output wire [C_PORTS*C_COUNTER_WIDTH-1:0] o_ingress_attempts,o_ingress_handshake_flits,
 output wire [C_PORTS*C_COUNTER_WIDTH-1:0] o_ingress_payload_bytes,o_ingress_payload_bits,o_ingress_stall_cycles,
 output wire [C_PORTS*5-1:0] o_ingress_overflow_sticky,output wire o_ingress_window_overflow_sticky,
 output wire o_egress_window_active,output wire o_egress_window_done,
 output wire [C_COUNTER_WIDTH-1:0] o_egress_measurement_cycles,
 output wire [C_PORTS*C_COUNTER_WIDTH-1:0] o_egress_attempts,o_egress_handshake_flits,
 output wire [C_PORTS*C_COUNTER_WIDTH-1:0] o_egress_payload_bytes,o_egress_payload_bits,o_egress_stall_cycles,
 output wire [C_PORTS*5-1:0] o_egress_overflow_sticky,output wire o_egress_window_overflow_sticky,
 output wire o_config_error,output wire o_error
);
 localparam CONFIG_LEGAL=(C_PORTS>=1)&&(C_PORTS<=32)&&(C_COUNTER_WIDTH>=8)&&
  (C_COUNTER_WIDTH<=64)&&(C_PAYLOAD_BYTES_WIDTH>=7)&&(C_PAYLOAD_BYTES_WIDTH<=16);
 localparam [C_PAYLOAD_BYTES_WIDTH-1:0] C_FULL_FABRIC_FLIT_BYTES=64;
 reg [C_PORTS-1:0] ingress_held_q,egress_held_q;
 wire [C_PORTS-1:0] ingress_attempt=i_ingress_committed_valid&~ingress_held_q;
 wire [C_PORTS-1:0] egress_attempt=i_egress_retired_valid&~egress_held_q;
 wire [C_PORTS*C_PAYLOAD_BYTES_WIDTH-1:0] payload_bytes;
 wire ingress_protocol_error,ingress_config_error,ingress_error;
 wire egress_protocol_error,egress_config_error,egress_error;
 genvar p;
 generate for(p=0;p<C_PORTS;p=p+1)begin:g_payload
  // 本观测边界的合同是每次握手携带完整有效的512-bit Fabric flit。
  assign payload_bytes[p*C_PAYLOAD_BYTES_WIDTH+:C_PAYLOAD_BYTES_WIDTH]=C_FULL_FABRIC_FLIT_BYTES;
 end endgenerate
 always @(posedge i_clk)begin
  if(!i_rstn)begin ingress_held_q<={C_PORTS{1'b0}};egress_held_q<={C_PORTS{1'b0}};end
  else begin
   ingress_held_q<=i_ingress_committed_valid&~i_ingress_committed_ready;
   egress_held_q<=i_egress_retired_valid&~i_egress_retired_ready;
  end
 end
 bandwidth_accounting #(.C_NUM_PORTS(C_PORTS),.C_COUNTER_WIDTH(C_COUNTER_WIDTH),
  .C_PAYLOAD_BYTES_WIDTH(C_PAYLOAD_BYTES_WIDTH),.C_MAX_PAYLOAD_BYTES(64))u_ingress(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_window_start(i_window_start),.i_window_stop(i_window_stop),
  .i_attempt(ingress_attempt),.i_valid(i_ingress_committed_valid),.i_ready(i_ingress_committed_ready),
  .i_payload_bytes(payload_bytes),.o_window_active(o_ingress_window_active),.o_window_done(o_ingress_window_done),
  .o_measurement_cycles(o_ingress_measurement_cycles),.o_valid_attempts(o_ingress_attempts),
  .o_handshake_flits(o_ingress_handshake_flits),.o_payload_bytes(o_ingress_payload_bytes),
  .o_payload_bits(o_ingress_payload_bits),.o_stall_cycles(o_ingress_stall_cycles),
  .o_counter_overflow_sticky(o_ingress_overflow_sticky),
  .o_window_overflow_sticky(o_ingress_window_overflow_sticky),.o_protocol_error(ingress_protocol_error),
  .o_config_error(ingress_config_error),.o_error(ingress_error));
 bandwidth_accounting #(.C_NUM_PORTS(C_PORTS),.C_COUNTER_WIDTH(C_COUNTER_WIDTH),
  .C_PAYLOAD_BYTES_WIDTH(C_PAYLOAD_BYTES_WIDTH),.C_MAX_PAYLOAD_BYTES(64))u_egress(
  .i_clk(i_clk),.i_rstn(i_rstn&&CONFIG_LEGAL),.i_window_start(i_window_start),.i_window_stop(i_window_stop),
  .i_attempt(egress_attempt),.i_valid(i_egress_retired_valid),.i_ready(i_egress_retired_ready),
  .i_payload_bytes(payload_bytes),.o_window_active(o_egress_window_active),.o_window_done(o_egress_window_done),
  .o_measurement_cycles(o_egress_measurement_cycles),.o_valid_attempts(o_egress_attempts),
  .o_handshake_flits(o_egress_handshake_flits),.o_payload_bytes(o_egress_payload_bytes),
  .o_payload_bits(o_egress_payload_bits),.o_stall_cycles(o_egress_stall_cycles),
  .o_counter_overflow_sticky(o_egress_overflow_sticky),
  .o_window_overflow_sticky(o_egress_window_overflow_sticky),.o_protocol_error(egress_protocol_error),
  .o_config_error(egress_config_error),.o_error(egress_error));
 assign o_config_error=!CONFIG_LEGAL||ingress_config_error||egress_config_error;
 assign o_error=o_config_error||ingress_error||egress_error||ingress_protocol_error||egress_protocol_error;
endmodule
`default_nettype wire
