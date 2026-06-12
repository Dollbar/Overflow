`timescale 1ns/1ps
`default_nettype none

// Standalone same-clock TL-to-DL admission pacer for the two frozen 512-bit
// normalized rate profiles.  The external FIFO remains the occupancy/budget owner;
// TL credits and Station port TDM are deliberately outside this block.
module tx_pacing #(
 parameter [15:0] C_FULL_RATE_CODE=16'd31250,
 parameter [15:0] C_REFERENCE_RATE_CODE=16'd3125
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire i_rate_valid,output wire o_rate_ready,input wire [15:0] i_rate_code,
 output reg o_rate_accept,output reg o_rate_error,
 output wire o_rate_configured,output wire [15:0] o_active_rate_code,
 input wire i_valid,output reg o_ready,input wire [511:0] i_data,input wire [127:0] i_meta,
 output reg o_valid,input wire i_output_ready,output reg [511:0] o_data,output reg [127:0] o_meta,
 input wire i_budget_available,output wire o_implemented
);
reg configured_q;
reg [15:0] active_rate_q;
reg [3:0] cooldown_q;
reg hold_valid_q;
reg [511:0] hold_data_q;
reg [127:0] hold_meta_q;
wire rate_supported;
wire full_rate;
wire pace_permit;
wire admission_eligible;
wire output_fire;
wire input_fire;
wire rate_fire;

assign rate_supported=(i_rate_code==C_FULL_RATE_CODE)||(i_rate_code==C_REFERENCE_RATE_CODE);
assign full_rate=(active_rate_q==C_FULL_RATE_CODE);
assign pace_permit=full_rate||(cooldown_q==4'd0);
assign admission_eligible=i_rstn&&i_enable&&configured_q&&pace_permit&&i_budget_available;
assign output_fire=o_valid&&i_output_ready;
assign input_fire=i_valid&&o_ready;
assign o_rate_ready=i_rstn&&i_enable&&!o_valid;
assign rate_fire=i_rate_valid&&o_rate_ready;
assign o_rate_configured=configured_q;
assign o_active_rate_code=active_rate_q;
assign o_implemented=1'b1;

always @* begin
 o_ready=1'b0;
 o_valid=1'b0;
 o_data=512'd0;
 o_meta=128'd0;
 if(i_rstn&&hold_valid_q)begin
  o_valid=1'b1;
  o_data=hold_data_q;
  o_meta=hold_meta_q;
  if(i_enable&&full_rate&&i_budget_available)o_ready=i_output_ready;
 end else if(admission_eligible)begin
  o_valid=i_valid;
  o_data=i_data;
  o_meta=i_meta;
  o_ready=1'b1;
 end
end

always @(posedge i_clk)begin
 if(!i_rstn)begin
  configured_q<=1'b0;
  active_rate_q<=16'd0;
  cooldown_q<=4'd0;
  hold_valid_q<=1'b0;
  hold_data_q<=512'd0;
  hold_meta_q<=128'd0;
  o_rate_accept<=1'b0;
  o_rate_error<=1'b0;
 end else begin
  o_rate_accept<=1'b0;
  if(rate_fire)begin
   if(rate_supported)begin
    configured_q<=1'b1;
    active_rate_q<=i_rate_code;
    cooldown_q<=4'd0;
    o_rate_accept<=1'b1;
   end else o_rate_error<=1'b1;
  end else if(output_fire)begin
   if(full_rate)cooldown_q<=4'd0;
   else cooldown_q<=4'd9;
  end else if(i_enable&&(cooldown_q!=4'd0))cooldown_q<=cooldown_q-1'b1;

  if(hold_valid_q)begin
   if(output_fire)begin
    if(input_fire)begin
     hold_valid_q<=1'b1;
     hold_data_q<=i_data;
     hold_meta_q<=i_meta;
    end else hold_valid_q<=1'b0;
   end
  end else if(input_fire&&!output_fire)begin
   hold_valid_q<=1'b1;
   hold_data_q<=i_data;
   hold_meta_q<=i_meta;
  end
 end
end
endmodule
`default_nettype wire
