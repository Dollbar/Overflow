`timescale 1ns/1ps
`default_nettype none

// CRC wrapper之后到tl_port.i_rx_*的生产接收路径。
// 四项frame最终判决只在SOP握手时采样；失败frame在解帧前整帧丢弃，防止其payload
// 污染跨frame TL carry。通过准入的TL flit仍逐项经过validated stage。
module endpoint_dl_to_tl_rx_path(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire i_frame_valid,output wire o_frame_ready,input wire [511:0] i_frame_data,
 input wire i_frame_sop,input wire i_frame_eop,
 input wire i_fec_complete,input wire i_crc_commit,input wire i_sequence_valid,input wire i_replay_accept,
 output wire o_tl_valid,input wire i_tl_ready,output wire [511:0] o_tl_flit,output wire [1:0] o_tl_msg,
 output wire o_ras_event,output wire o_validation_error,output wire o_protocol_error,
 output wire [3:0] o_reject_sticky,output wire [15:0] o_reject_frame_count,
 output wire o_busy,output wire o_quiescent
);
reg frame_active_q,drop_frame_q;
reg [3:0] beat_count_q;
reg [3:0] verdict_q;
reg [3:0] reject_sticky_q;
reg [15:0] reject_count_q;
reg protocol_error_q,ras_event_q;
wire [3:0] incoming_verdict;
wire incoming_ok,first_beat,route_to_deframer;
wire def_ready,def_valid,def_error,def_error_event,def_busy,def_quiescent,def_carry,def_implemented;
wire [511:0] def_data;wire[127:0] def_meta;
wire candidate_ready,stage_drop,stage_error,stage_busy,stage_quiescent;
wire [3:0] stage_reject;wire[15:0] stage_reject_count;
wire input_fire;
wire [16:0] reject_count_sum;
wire def_meta_reserved;

assign incoming_verdict={i_fec_complete,i_crc_commit,i_sequence_valid,i_replay_accept};
assign incoming_ok=&incoming_verdict;
assign first_beat=!frame_active_q;
// 新frame必须等deframer空闲，避免覆盖仍服务上一frame输出的冻结判决。
assign o_frame_ready=i_rstn&&i_enable&&(first_beat?def_ready:(drop_frame_q?1'b1:def_ready));
assign input_fire=i_frame_valid&&o_frame_ready;
assign route_to_deframer=frame_active_q?!drop_frame_q:incoming_ok;
assign o_ras_event=ras_event_q||def_error_event||stage_drop;
assign o_validation_error=|reject_sticky_q||stage_error;
assign def_meta_reserved=def_valid&&(|def_meta[127:2]);
assign o_protocol_error=protocol_error_q||def_error||def_meta_reserved||(i_rstn&&!def_implemented);
assign o_reject_sticky=reject_sticky_q|stage_reject;
assign reject_count_sum={1'b0,reject_count_q}+{1'b0,stage_reject_count};
assign o_reject_frame_count=reject_count_sum[16]?16'hffff:reject_count_sum[15:0];
assign o_busy=i_rstn&&(frame_active_q||def_busy||stage_busy||def_carry);
assign o_quiescent=i_rstn&&def_implemented&&!frame_active_q&&!def_carry&&def_quiescent&&stage_quiescent;

dl_rx_deframer u_deframer(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),
 .i_valid(i_frame_valid&&o_frame_ready&&route_to_deframer),.i_data(i_frame_data),.i_meta(128'd0),
 .i_sop(i_frame_sop),.i_eop(i_frame_eop),.i_ready(candidate_ready),
 .o_ready(def_ready),.o_valid(def_valid),.o_data(def_data),.o_meta(def_meta),
 .o_implemented(def_implemented),.o_error(def_error),.o_error_event(def_error_event),.o_busy(def_busy),
 .o_quiescent(def_quiescent),.o_carry_active(def_carry));

endpoint_validated_tl_rx_stage u_validated_stage(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_candidate_valid(def_valid),.o_candidate_ready(candidate_ready),
 .i_candidate_flit(def_data),.i_candidate_msg(def_meta[1:0]),
 .i_fec_complete(verdict_q[3]),.i_crc_commit(verdict_q[2]),
 .i_sequence_valid(verdict_q[1]),.i_replay_accept(verdict_q[0]),
 .o_tl_valid(o_tl_valid),.i_tl_ready(i_tl_ready),.o_tl_flit(o_tl_flit),.o_tl_msg(o_tl_msg),
 .o_drop_event(stage_drop),.o_validation_error(stage_error),.o_reject_sticky(stage_reject),
 .o_reject_count(stage_reject_count),.o_busy(stage_busy),.o_quiescent(stage_quiescent));

always @(posedge i_clk)begin
 if(!i_rstn)begin
  frame_active_q<=1'b0;drop_frame_q<=1'b0;beat_count_q<=4'd0;verdict_q<=4'd0;
  reject_sticky_q<=4'd0;reject_count_q<=16'd0;protocol_error_q<=1'b0;ras_event_q<=1'b0;
 end else begin
  ras_event_q<=1'b0;
  if(input_fire)begin
   if(first_beat)begin
    if(!i_frame_sop||i_frame_eop)begin
     protocol_error_q<=1'b1;ras_event_q<=1'b1;frame_active_q<=1'b0;beat_count_q<=4'd0;
    end else begin
     frame_active_q<=1'b1;drop_frame_q<=!incoming_ok;beat_count_q<=4'd1;verdict_q<=incoming_verdict;
     if(!incoming_ok)begin
      reject_sticky_q<=reject_sticky_q|~incoming_verdict;ras_event_q<=1'b1;
      if(reject_count_q!=16'hffff)reject_count_q<=reject_count_q+1'b1;
     end
    end
   end else if(i_frame_sop||((beat_count_q==4'd9)!=i_frame_eop))begin
    protocol_error_q<=1'b1;ras_event_q<=1'b1;frame_active_q<=1'b0;drop_frame_q<=1'b0;beat_count_q<=4'd0;
   end else if(i_frame_eop)begin
    frame_active_q<=1'b0;drop_frame_q<=1'b0;beat_count_q<=4'd0;
   end else beat_count_q<=beat_count_q+1'b1;
  end
 end
end

endmodule
`default_nettype wire
