`timescale 1ns/1ps
`default_nettype none
// 整数带宽计量叶；不参与业务ready/valid，只观察调用者给出的真实事件。
module bandwidth_accounting #(
 parameter integer C_NUM_PORTS=32,
 parameter integer C_COUNTER_WIDTH=64,
 parameter integer C_PAYLOAD_BYTES_WIDTH=7,
 parameter integer C_MAX_PAYLOAD_BYTES=64
)(
 input wire i_clk,input wire i_rstn,
 input wire i_window_start,input wire i_window_stop,
 // attempt必须仅在新flit首次提交给接口时脉冲；valid可在stall期间持续。
 input wire [C_NUM_PORTS-1:0] i_attempt,
 input wire [C_NUM_PORTS-1:0] i_valid,input wire [C_NUM_PORTS-1:0] i_ready,
 // 每个valid flit的协议payload byte数；只有真实handshake时进入payload分子。
 input wire [C_NUM_PORTS*C_PAYLOAD_BYTES_WIDTH-1:0] i_payload_bytes,
 output wire o_window_active,output reg o_window_done,
 output reg [C_COUNTER_WIDTH-1:0] o_measurement_cycles,
 output reg [C_NUM_PORTS*C_COUNTER_WIDTH-1:0] o_valid_attempts,
 output reg [C_NUM_PORTS*C_COUNTER_WIDTH-1:0] o_handshake_flits,
 output reg [C_NUM_PORTS*C_COUNTER_WIDTH-1:0] o_payload_bytes,
 output reg [C_NUM_PORTS*C_COUNTER_WIDTH-1:0] o_payload_bits,
 output reg [C_NUM_PORTS*C_COUNTER_WIDTH-1:0] o_stall_cycles,
 // 每Port五位依次为attempt/handshake/bytes/bits/stall饱和事件。
 output reg [C_NUM_PORTS*5-1:0] o_counter_overflow_sticky,
 output reg o_window_overflow_sticky,
 output reg o_protocol_error,output wire o_config_error,output wire o_error
);
 localparam CONFIG_LEGAL=(C_NUM_PORTS>=1)&&(C_NUM_PORTS<=32)&&
  (C_COUNTER_WIDTH>=8)&&(C_COUNTER_WIDTH<=64)&&
  (C_PAYLOAD_BYTES_WIDTH>=1)&&(C_PAYLOAD_BYTES_WIDTH<=16)&&
  (C_COUNTER_WIDTH>=C_PAYLOAD_BYTES_WIDTH+3)&&
  (C_MAX_PAYLOAD_BYTES>=0)&&(C_MAX_PAYLOAD_BYTES<(32'd1<<C_PAYLOAD_BYTES_WIDTH));
 reg window_active_q;
 wire start_accepted=CONFIG_LEGAL&&i_window_start&&!i_window_stop&&!window_active_q;
 wire stop_accepted=CONFIG_LEGAL&&i_window_stop&&!i_window_start&&window_active_q;
 wire window_command_error=(i_window_start&&i_window_stop)||(i_window_start&&window_active_q)||
  (i_window_stop&&!window_active_q);
 assign o_window_active=CONFIG_LEGAL&&window_active_q;
 assign o_config_error=!CONFIG_LEGAL;
 assign o_error=o_config_error||o_protocol_error;

 always @(posedge i_clk)begin
  if(!i_rstn)begin window_active_q<=1'b0;o_window_done<=1'b0;end
  else begin
   o_window_done<=1'b0;
   if(start_accepted)window_active_q<=1'b1;
   else if(stop_accepted)begin window_active_q<=1'b0;o_window_done<=1'b1;end
  end
 end

 always @(posedge i_clk)begin
  if(!i_rstn)begin o_measurement_cycles<={C_COUNTER_WIDTH{1'b0}};o_window_overflow_sticky<=1'b0;end
  else if(start_accepted)begin o_measurement_cycles<={C_COUNTER_WIDTH{1'b0}};o_window_overflow_sticky<=1'b0;end
  else if(window_active_q)begin
   if(&o_measurement_cycles)o_window_overflow_sticky<=1'b1;
   else o_measurement_cycles<=o_measurement_cycles+1'b1;
  end
 end

 integer error_port;
 reg event_protocol_error;
 always @(*)begin
  event_protocol_error=window_command_error;
  for(error_port=0;error_port<C_NUM_PORTS;error_port=error_port+1)begin
   if(i_attempt[error_port]&&!i_valid[error_port])event_protocol_error=1'b1;
   if(window_active_q&&i_valid[error_port]&&i_ready[error_port]&&
      ({{(32-C_PAYLOAD_BYTES_WIDTH){1'b0}},i_payload_bytes[error_port*C_PAYLOAD_BYTES_WIDTH+:C_PAYLOAD_BYTES_WIDTH]}>C_MAX_PAYLOAD_BYTES))
    event_protocol_error=1'b1;
  end
 end
 always @(posedge i_clk)begin
  if(!i_rstn)o_protocol_error<=1'b0;
  else if(CONFIG_LEGAL)o_protocol_error<=o_protocol_error||event_protocol_error;
 end

 genvar port_index;
 generate for(port_index=0;port_index<C_NUM_PORTS;port_index=port_index+1)begin:g_port
  wire [C_PAYLOAD_BYTES_WIDTH-1:0] payload_value=
   i_payload_bytes[port_index*C_PAYLOAD_BYTES_WIDTH+:C_PAYLOAD_BYTES_WIDTH];
  wire payload_legal={{(32-C_PAYLOAD_BYTES_WIDTH){1'b0}},payload_value}<=C_MAX_PAYLOAD_BYTES;
  wire [C_COUNTER_WIDTH:0] byte_add={{(C_COUNTER_WIDTH+1-C_PAYLOAD_BYTES_WIDTH){1'b0}},payload_value};
  wire [C_COUNTER_WIDTH:0] bit_add=
   {{(C_COUNTER_WIDTH+1-C_PAYLOAD_BYTES_WIDTH-3){1'b0}},payload_value,3'b000};
  wire [C_COUNTER_WIDTH:0] byte_sum={1'b0,o_payload_bytes[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]}+byte_add;
  wire [C_COUNTER_WIDTH:0] bit_sum={1'b0,o_payload_bits[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]}+bit_add;
  always @(posedge i_clk)begin
   if(!i_rstn||start_accepted)begin
    o_valid_attempts[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<={C_COUNTER_WIDTH{1'b0}};
    o_handshake_flits[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<={C_COUNTER_WIDTH{1'b0}};
    o_payload_bytes[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<={C_COUNTER_WIDTH{1'b0}};
    o_payload_bits[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<={C_COUNTER_WIDTH{1'b0}};
    o_stall_cycles[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<={C_COUNTER_WIDTH{1'b0}};
    o_counter_overflow_sticky[port_index*5+:5]<=5'd0;
   end else if(window_active_q)begin
    if(i_attempt[port_index]&&i_valid[port_index])begin
     if(&o_valid_attempts[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH])o_counter_overflow_sticky[port_index*5]<=1'b1;
     else o_valid_attempts[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<=
      o_valid_attempts[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]+1'b1;
    end
    if(i_valid[port_index]&&i_ready[port_index])begin
     if(&o_handshake_flits[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH])o_counter_overflow_sticky[port_index*5+1]<=1'b1;
     else o_handshake_flits[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<=
      o_handshake_flits[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]+1'b1;
     if(payload_legal)begin
      if(byte_sum[C_COUNTER_WIDTH])begin
       o_payload_bytes[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<={C_COUNTER_WIDTH{1'b1}};
       o_counter_overflow_sticky[port_index*5+2]<=1'b1;
      end else o_payload_bytes[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<=byte_sum[C_COUNTER_WIDTH-1:0];
      if(bit_sum[C_COUNTER_WIDTH])begin
       o_payload_bits[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<={C_COUNTER_WIDTH{1'b1}};
       o_counter_overflow_sticky[port_index*5+3]<=1'b1;
      end else o_payload_bits[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<=bit_sum[C_COUNTER_WIDTH-1:0];
     end
    end
    if(i_valid[port_index]&&!i_ready[port_index])begin
     if(&o_stall_cycles[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH])o_counter_overflow_sticky[port_index*5+4]<=1'b1;
     else o_stall_cycles[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]<=
      o_stall_cycles[port_index*C_COUNTER_WIDTH+:C_COUNTER_WIDTH]+1'b1;
    end
   end
  end
 end endgenerate
endmodule
`default_nettype wire
