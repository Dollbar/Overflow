`timescale 1ns/1ps
`default_nettype none
// 单Station mode重配置所有者。它只解释冻结的x4/2x2/4x1 mode编码，PHY retrain
// 完成由lane_up显式提供；TL credit完成使用真实local_done/peer_done，不伪造物理训练。
module endpoint_station_mode_reconfiguration_owner(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire i_request_valid,output wire o_request_ready,input wire[1:0] i_requested_mode,
 input wire i_station_quiescent,input wire[3:0] i_lane_up,input wire i_mode_commit_accept,
 input wire[1:0] i_active_mode,input wire[3:0] i_active_mask,
 input wire[3:0] i_local_done,input wire[3:0] i_peer_done,input wire[3:0] i_external_link_reset,
 output wire o_request_accept,output wire o_request_reject,output wire o_admission_enable,
 output wire[3:0] o_link_reset,output wire o_mode_commit,output wire[3:0] o_reinit_start,
 output wire o_busy,output wire o_quiescent,output reg o_protocol_error,output wire o_error
);
 localparam[2:0] ST_IDLE=3'd0,ST_DRAIN=3'd1,ST_RESET=3'd2,ST_RETRAIN=3'd3,
  ST_COMMIT=3'd4,ST_INIT=3'd5,ST_FAULT=3'd6;
 reg[2:0] state_q;reg[1:0] target_mode_q;reg[3:0] target_mask_q;
 wire request_legal=(i_requested_mode!=2'b11);
 wire request_fire=i_request_valid&&o_request_ready;
 wire target_lanes_up=&i_lane_up;
 wire init_complete=((i_local_done&i_peer_done&target_mask_q)==target_mask_q);
 wire target_map_visible=(i_active_mode==target_mode_q)&&(i_active_mask==target_mask_q);
 assign o_request_ready=i_rstn&&i_enable&&(state_q==ST_IDLE);
 assign o_request_accept=request_fire&&request_legal;
 assign o_request_reject=i_rstn&&i_enable&&i_request_valid&&((state_q!=ST_IDLE)||(request_fire&&!request_legal));
 assign o_admission_enable=i_rstn&&i_enable&&(state_q==ST_IDLE);
 assign o_link_reset=(state_q==ST_RESET)?4'b1111:4'b0000;
 assign o_mode_commit=i_rstn&&i_enable&&(state_q==ST_COMMIT);
 assign o_reinit_start=(i_rstn&&i_enable&&(state_q==ST_INIT))?
  (target_mask_q&~(i_local_done&i_peer_done)):4'b0000;
 assign o_busy=i_rstn&&(state_q!=ST_IDLE);
 assign o_quiescent=i_rstn&&(state_q==ST_IDLE);
 assign o_error=o_protocol_error||(state_q==ST_FAULT);
 always @(posedge i_clk)begin
  if(!i_rstn)begin state_q<=ST_IDLE;target_mode_q<=2'd0;target_mask_q<=4'b0001;o_protocol_error<=1'b0;end
  else begin
   if(o_request_reject)o_protocol_error<=1'b1;
   if((state_q!=ST_IDLE)&&(|i_external_link_reset))begin state_q<=ST_FAULT;o_protocol_error<=1'b1;end
   else case(state_q)
    ST_IDLE:if(request_fire)begin
     if(request_legal)begin
      target_mode_q<=i_requested_mode;
      target_mask_q<=(i_requested_mode==2'd0)?4'b0001:(i_requested_mode==2'd1)?4'b0101:4'b1111;
      state_q<=ST_DRAIN;
     end else o_protocol_error<=1'b1;
    end
    ST_DRAIN:if(i_station_quiescent)state_q<=ST_RESET;
    ST_RESET:state_q<=ST_RETRAIN;
    ST_RETRAIN:if(target_lanes_up)state_q<=ST_COMMIT;
    ST_COMMIT:if(i_mode_commit_accept)state_q<=ST_INIT;
    ST_INIT:begin
     if(!target_map_visible)begin state_q<=ST_FAULT;o_protocol_error<=1'b1;end
     else if(init_complete)state_q<=ST_IDLE;
    end
    default:state_q<=ST_FAULT;
   endcase
  end
 end
endmodule
`default_nettype wire
