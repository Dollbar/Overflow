`timescale 1ns/1ps
`default_nettype none

// 已解码DL payload到现有tl_port.i_rx_*接口的最终提交屏障。
// i_candidate_flit/i_candidate_msg必须由未来dl_rx_deframer从已布局DL frame恢复，不能把
// dl_crc_512_commit_wrapper的原始10拍数据直接接到这里。四项资格必须在candidate有效前
// 已经成为该候选的最终结论：FEC完成、CRC frame已commit、sequence有效、replay接纳。
// 本模块不解析DL字段、不计算CRC、不复制sequence/replay状态，也不产生UPLI字段。
module endpoint_validated_tl_rx_stage (
 input  wire         i_clk,
 input  wire         i_rstn,
 input  wire         i_candidate_valid,
 output wire         o_candidate_ready,
 input  wire [511:0] i_candidate_flit,
 input  wire [1:0]   i_candidate_msg,
 input  wire         i_fec_complete,
 input  wire         i_crc_commit,
 input  wire         i_sequence_valid,
 input  wire         i_replay_accept,
 output wire         o_tl_valid,
 input  wire         i_tl_ready,
 output wire [511:0] o_tl_flit,
 output wire [1:0]   o_tl_msg,
 output wire         o_drop_event,
 output wire         o_validation_error,
 output wire [3:0]   o_reject_sticky, // [3:0]=FEC,CRC,sequence,replay未通过。
 output wire [15:0]  o_reject_count,
 output wire         o_busy,
 output wire         o_quiescent
);

reg valid_q;
reg [511:0] flit_q;
reg [1:0] msg_q;
reg [3:0] reject_sticky_q;
reg [15:0] reject_count_q;

wire [3:0] validation_vector;
wire validation_ok;
wire candidate_fire;
wire tl_fire;

assign validation_vector={i_fec_complete,i_crc_commit,i_sequence_valid,i_replay_accept};
assign validation_ok=&validation_vector;
// 本地一槽弹性ready；不依赖当前候选的验证值，避免valid/ready组合死锁。
assign o_candidate_ready=i_rstn&&(!valid_q||i_tl_ready);
assign candidate_fire=i_candidate_valid&&o_candidate_ready;
assign o_tl_valid=i_rstn&&valid_q;
assign tl_fire=o_tl_valid&&i_tl_ready;
assign o_tl_flit=o_tl_valid?flit_q:512'd0;
assign o_tl_msg=o_tl_valid?msg_q:2'd0;
assign o_drop_event=candidate_fire&&!validation_ok;
assign o_validation_error=|reject_sticky_q;
assign o_reject_sticky=reject_sticky_q;
assign o_reject_count=reject_count_q;
assign o_busy=i_rstn&&valid_q;
assign o_quiescent=i_rstn&&!valid_q;

always @(posedge i_clk)begin
 if(!i_rstn)begin
  valid_q<=1'b0;
  flit_q<=512'd0;
  msg_q<=2'd0;
  reject_sticky_q<=4'd0;
  reject_count_q<=16'd0;
 end else begin
  if(candidate_fire)begin
   if(validation_ok)begin
    valid_q<=1'b1;
    flit_q<=i_candidate_flit;
    msg_q<=i_candidate_msg;
   end else begin
    // 同拍弹出旧项时，失败的新项明确丢弃而不是继承旧valid。
    valid_q<=1'b0;
    flit_q<=512'd0;
    msg_q<=2'd0;
    reject_sticky_q<=reject_sticky_q|~validation_vector;
    if(reject_count_q!=16'hffff)reject_count_q<=reject_count_q+16'd1;
   end
  end else if(tl_fire)begin
   valid_q<=1'b0;
   flit_q<=512'd0;
   msg_q<=2'd0;
  end
 end
end

endmodule
`default_nettype wire
