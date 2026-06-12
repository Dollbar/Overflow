`timescale 1ns/1ps
`default_nettype none
// Release路径只读watchdog：观察真实valid/ready，不产生ready、release或credit状态更新。
module switch_release_path_watchdog #(
 parameter integer C_RELEASE_PORTS=1024,
 parameter integer C_RELEASE_INDEX_WIDTH=10,
 parameter integer C_TIMEOUT_CYCLES=1024,
 parameter integer C_TIMER_WIDTH=16
)(
 input wire i_clk,
 input wire i_rstn,
 input wire [C_RELEASE_PORTS-1:0] i_release_valid,
 input wire [C_RELEASE_PORTS-1:0] i_release_ready,
 input wire i_timeout_w1c,
 input wire i_counter_w1c,
 output wire o_stall_active,
 output reg o_timeout_sticky,
 output reg [31:0] o_stall_cycles,
 output reg [31:0] o_timeout_count,
 output reg [C_RELEASE_INDEX_WIDTH-1:0] o_first_stalled_port,
 output wire o_config_error
);
 localparam [C_TIMER_WIDTH-1:0] TIMEOUT_VALUE=C_TIMEOUT_CYCLES[C_TIMER_WIDTH-1:0];
 localparam CONFIG_LEGAL=(C_RELEASE_PORTS>=1)&&(C_RELEASE_PORTS<=(1<<C_RELEASE_INDEX_WIDTH))&&
  (C_TIMEOUT_CYCLES>=1)&&(C_TIMEOUT_CYCLES<=(1<<C_TIMER_WIDTH));
 wire [C_RELEASE_PORTS-1:0] stalled_ports=i_release_valid&~i_release_ready;
 wire stall_now=|stalled_ports;
 reg stall_active_q;
 reg timeout_reported_q;
 reg [C_TIMER_WIDTH-1:0] stall_timer_q;
 reg [C_RELEASE_INDEX_WIDTH-1:0] first_stalled_comb;
 reg first_found;
 integer scan_port;
 assign o_stall_active=stall_active_q;
 assign o_config_error=!CONFIG_LEGAL;

 always @(*) begin
  first_stalled_comb={C_RELEASE_INDEX_WIDTH{1'b0}};
  first_found=1'b0;
  for(scan_port=0;scan_port<C_RELEASE_PORTS;scan_port=scan_port+1)begin
   if(stalled_ports[scan_port]&&!first_found)begin
    first_stalled_comb=scan_port[C_RELEASE_INDEX_WIDTH-1:0];
    first_found=1'b1;
   end
  end
 end

 always @(posedge i_clk) begin
  if(!i_rstn)begin
   stall_active_q<=1'b0;
   timeout_reported_q<=1'b0;
   stall_timer_q<={C_TIMER_WIDTH{1'b0}};
   o_timeout_sticky<=1'b0;
   o_stall_cycles<=32'd0;
   o_timeout_count<=32'd0;
   o_first_stalled_port<={C_RELEASE_INDEX_WIDTH{1'b0}};
  end else if(!CONFIG_LEGAL)begin
   stall_active_q<=1'b0;
   timeout_reported_q<=1'b0;
   stall_timer_q<={C_TIMER_WIDTH{1'b0}};
   o_timeout_sticky<=1'b0;
   o_stall_cycles<=32'd0;
   o_timeout_count<=32'd0;
   o_first_stalled_port<={C_RELEASE_INDEX_WIDTH{1'b0}};
  end else begin
   stall_active_q<=stall_now;
   if(stall_now)begin
    if(!stall_active_q)o_first_stalled_port<=first_stalled_comb;
    if(o_stall_cycles!=32'hffffffff)o_stall_cycles<=o_stall_cycles+1'b1;
    if(stall_timer_q<(TIMEOUT_VALUE-1'b1))stall_timer_q<=stall_timer_q+1'b1;
    if(!timeout_reported_q&&(stall_timer_q==(TIMEOUT_VALUE-1'b1)))begin
     timeout_reported_q<=1'b1;
     o_timeout_sticky<=1'b1;
     if(o_timeout_count!=32'hffffffff)o_timeout_count<=o_timeout_count+1'b1;
    end
   end else begin
    stall_timer_q<={C_TIMER_WIDTH{1'b0}};
    timeout_reported_q<=1'b0;
    if(i_timeout_w1c)o_timeout_sticky<=1'b0;
    if(i_counter_w1c)begin
     o_stall_cycles<=32'd0;
     o_timeout_count<=32'd0;
     o_first_stalled_port<={C_RELEASE_INDEX_WIDTH{1'b0}};
    end
   end
  end
 end
endmodule
`default_nettype wire
