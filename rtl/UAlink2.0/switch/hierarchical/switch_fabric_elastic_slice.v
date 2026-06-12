`timescale 1ns/1ps
`default_nettype none
// 单级registered elastic slice；调用者把data与全部sideband打包为一个payload。
module switch_fabric_elastic_slice #(
 parameter integer C_PAYLOAD_WIDTH=512
)(
 input wire i_clk,input wire i_rstn,
 input wire i_valid,output wire o_ready,input wire [C_PAYLOAD_WIDTH-1:0] i_payload,
 output wire o_valid,input wire i_ready,output wire [C_PAYLOAD_WIDTH-1:0] o_payload,
 output wire o_quiescent,output wire o_config_error,output wire o_error
);
 localparam CONFIG_LEGAL=(C_PAYLOAD_WIDTH>=1)&&(C_PAYLOAD_WIDTH<=65536);
 reg valid_q;reg [C_PAYLOAD_WIDTH-1:0] payload_q;
 // ready仅依赖本地占用与相邻下游ready，不穿越其它fabric层级。
 assign o_ready=i_rstn&&CONFIG_LEGAL&&(!valid_q||i_ready);
 assign o_valid=i_rstn&&CONFIG_LEGAL&&valid_q;
 assign o_payload=payload_q;
 assign o_config_error=!CONFIG_LEGAL;
 assign o_error=o_config_error;
 assign o_quiescent=CONFIG_LEGAL&&!valid_q;
 always @(posedge i_clk)begin
  if(!i_rstn)begin valid_q<=1'b0;payload_q<=0;end
  else if(CONFIG_LEGAL&&o_ready)begin
   valid_q<=i_valid;
   if(i_valid)payload_q<=i_payload;
  end
  else if(!CONFIG_LEGAL)begin valid_q<=1'b0;payload_q<=0;end
 end
endmodule
`default_nettype wire
