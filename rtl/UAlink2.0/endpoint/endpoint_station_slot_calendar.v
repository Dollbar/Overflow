`timescale 1ns/1ps
`default_nettype none

// 固定四个Logical Port的公共时钟槽日历。空槽照常消耗，禁止借用其它端口配额；
// 只有当前槽确有valid而对应下游未ready时冻结，直到真实握手后再推进。
module endpoint_station_slot_calendar(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire[1:0] i_mode,
 input wire[3:0] i_port_valid,input wire[3:0] i_port_ready,
 output reg[3:0] o_slot_enable,output reg[1:0] o_slot_port,output wire o_mode_error
);
reg[1:0] phase_q;reg[1:0] observed_mode_q;
wire mode_legal=(i_mode!=2'd3);
wire selected_valid=|(i_port_valid&o_slot_enable);
wire selected_ready=|(i_port_ready&o_slot_enable);
wire freeze_slot=i_rstn&&i_enable&&mode_legal&&selected_valid&&!selected_ready;
assign o_mode_error=i_rstn&&i_enable&&!mode_legal;
always @* begin
 o_slot_enable=4'b0000;o_slot_port=2'd0;
 if(i_rstn&&i_enable&&mode_legal)begin
  if(i_mode!=observed_mode_q)begin o_slot_enable=4'b0001;o_slot_port=2'd0;end
  else case(i_mode)
   2'd0:begin o_slot_enable=4'b0001;o_slot_port=2'd0;end
   2'd1:begin
    if(phase_q[0])begin o_slot_enable=4'b0100;o_slot_port=2'd2;end
    else begin o_slot_enable=4'b0001;o_slot_port=2'd0;end
   end
   default:begin o_slot_port=phase_q;o_slot_enable=(4'b0001<<phase_q);end
  endcase
 end
end
always @(posedge i_clk)begin
 if(!i_rstn)begin phase_q<=2'd0;observed_mode_q<=2'd0;end
 else if(!i_enable||!mode_legal)begin phase_q<=2'd0;observed_mode_q<=i_mode;end
 else if(i_mode!=observed_mode_q)begin phase_q<=2'd0;observed_mode_q<=i_mode;end
 else if(!freeze_slot)begin
  case(i_mode)
   2'd0:phase_q<=2'd0;
   2'd1:phase_q<=phase_q[0]?2'd0:2'd1;
   default:phase_q<=phase_q+2'd1;
  endcase
 end
end
endmodule
`default_nettype wire
