`timescale 1ns/1ps
`default_nettype none
// Managed transaction top的唯一commit准入门；不拥有mode，只在整个Station静止时
// 把CSR单拍命令交给既有scheduler mode owner。拒绝状态由下一次成功准入原子清除。
module endpoint_station_mode_commit_admission #(parameter integer C_STATIONS=2)(
 input wire i_clk,input wire i_rstn,input wire[C_STATIONS-1:0] i_commit,input wire[C_STATIONS-1:0] i_station_busy,
 output wire[C_STATIONS-1:0] o_admitted_commit,output wire[C_STATIONS-1:0] o_reject_pulse,output reg[C_STATIONS-1:0] o_reject_sticky);
 assign o_admitted_commit=i_commit&~i_station_busy;
 assign o_reject_pulse=i_commit&i_station_busy;
 always @(posedge i_clk)begin
  if(!i_rstn)o_reject_sticky<={C_STATIONS{1'b0}};
  else o_reject_sticky<=(o_reject_sticky|o_reject_pulse)&~o_admitted_commit;
 end
endmodule
// 单Station managed epoch时序owner。数据路径cleanup是显式事件，绝不借用reset清账。
module endpoint_station_managed_epoch_owner #(
 parameter integer EPOCH_WIDTH=8
)(
 input wire i_clk,
 input wire i_rstn,input wire i_enable,
 input wire i_close_valid,output wire o_close_ready,input wire[EPOCH_WIDTH-1:0] i_close_epoch,
 input wire i_cleanup_valid,output wire o_cleanup_ready,output wire o_rx_cleanup_pulse,
 input wire i_recover_valid,input wire[EPOCH_WIDTH-1:0] i_recover_epoch,output wire o_recover_ready,output wire o_recovered,
 input wire i_station_quiescent,input wire i_station_error,input wire[2:0] i_owner_ready,
 output wire o_admission_enable,output wire o_isolated,output wire[EPOCH_WIDTH-1:0] o_epoch,
 output wire o_certificate,output wire[EPOCH_WIDTH-1:0] o_certificate_epoch,output wire o_error
);
 localparam[2:0] ST_IDLE=3'd0,ST_DRAIN=3'd1,ST_VERIFY=3'd2,ST_CERTIFIED=3'd3,ST_FAULT=3'd4;
 reg[2:0] state_q;reg[EPOCH_WIDTH-1:0] epoch_q,certificate_epoch_q;reg protocol_error_q;
 wire close_epoch_match,recover_epoch_match,precleanup_ready,certificate_live,recover_fire;
 assign close_epoch_match=(i_close_epoch===epoch_q);
 assign recover_epoch_match=(i_recover_epoch===(epoch_q+1'b1));
 assign precleanup_ready=(i_station_quiescent===1'b1)&&(i_owner_ready[2:1]===2'b11)&&(i_station_error===1'b0);
 assign certificate_live=(state_q==ST_CERTIFIED)&&(certificate_epoch_q==epoch_q)&&(i_owner_ready===3'b111)&&(i_station_error===1'b0);
 assign recover_fire=i_recover_valid&&o_recover_ready;
 assign o_close_ready=i_rstn&&i_enable&&(state_q==ST_IDLE);
 assign o_cleanup_ready=i_rstn&&i_enable&&(state_q==ST_DRAIN)&&precleanup_ready;
 assign o_rx_cleanup_pulse=i_cleanup_valid&&o_cleanup_ready;
 assign o_recover_ready=i_rstn&&i_enable&&certificate_live&&recover_epoch_match;
 assign o_recovered=recover_fire;assign o_admission_enable=i_rstn&&i_enable&&(state_q==ST_IDLE);
 assign o_isolated=i_rstn&&(state_q!=ST_IDLE);assign o_epoch=epoch_q;
 assign o_certificate=certificate_live;assign o_certificate_epoch=certificate_epoch_q;
 assign o_error=protocol_error_q||(state_q==ST_FAULT);
 always @(posedge i_clk)begin
  if(!i_rstn)begin state_q<=ST_IDLE;epoch_q<={EPOCH_WIDTH{1'b0}};certificate_epoch_q<={EPOCH_WIDTH{1'b0}};protocol_error_q<=1'b0;end
  else if(!i_enable)state_q<=ST_IDLE;
  else case(state_q)
   ST_IDLE:if(i_close_valid&&o_close_ready)begin
    if(close_epoch_match)state_q<=ST_DRAIN;else protocol_error_q<=1'b1;
   end
   ST_DRAIN:begin
    if(i_station_error)state_q<=ST_FAULT;
    else if(o_rx_cleanup_pulse)begin certificate_epoch_q<=epoch_q;state_q<=ST_VERIFY;end
   end
   ST_VERIFY:begin
    if(i_station_error)state_q<=ST_FAULT;
    else if(i_owner_ready==3'b111)state_q<=ST_CERTIFIED;
    else state_q<=ST_DRAIN;
   end
   ST_CERTIFIED:begin
    if(i_station_error)state_q<=ST_FAULT;
    else if(!certificate_live)state_q<=ST_DRAIN;
    else if(recover_fire)begin epoch_q<=i_recover_epoch;certificate_epoch_q<=i_recover_epoch;state_q<=ST_IDLE;end
   end
   default:state_q<=ST_FAULT;
  endcase
 end
endmodule
`default_nettype wire
