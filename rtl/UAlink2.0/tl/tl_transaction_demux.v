`timescale 1ns/1ps
`default_nettype none
// 明文TL内部事务分发器：kind 0/1/2/3分别表示Request/OrigData/ReadRsp/WriteRsp。
// 本模块只消费上游已接收的internal flit，不复制、归还或扣除credit；信用所有权仍在tl_port/tl_receive_credit。
module tl_transaction_demux(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire i_valid,
 input wire [511:0] i_data,input wire [127:0] i_meta,
 input wire [2:0] i_kind,input wire i_sop,input wire i_eop,output wire o_ready,
 output reg [3:0] o_kind_valid,input wire [3:0] i_kind_ready,
 output reg [2047:0] o_kind_data,output reg [511:0] o_kind_meta,
 output reg [11:0] o_kind,output reg [3:0] o_kind_sop,output reg [3:0] o_kind_eop,
 output wire o_owner_valid,output wire [2:0] o_owner_kind,
 output wire o_invalid_kind,output wire o_kind_change_error,output wire o_framing_error,
 output wire o_implemented,output wire o_error,
 // 原planned scaffold的聚合输出不是第二条事务通路，继续固定为失败关闭。
 output wire o_valid,output wire [511:0] o_data,output wire [127:0] o_meta
);
 reg hold_valid_q,hold_sop_q,hold_eop_q; // 单拍弹性槽保证目标输出stall时全部字段稳定。
 reg [511:0] hold_data_q;reg [127:0] hold_meta_q;reg [1:0] hold_kind_q; // 已接纳flit的完整明文字段与合法kind。
 reg owner_valid_q;reg [1:0] owner_kind_q; // SOP接纳后锁定packet输出直到EOP真实输出握手。
 reg invalid_kind_q,kind_change_q,framing_q; // 三类错误均sticky至reset或disable。
 wire active=i_rstn&&i_enable; // disable与reset都关闭全部事务可见性。
 wire output_take=active&&hold_valid_q&&i_kind_ready[hold_kind_q]; // 唯一真实下游消费事件。
 wire release_now=output_take&&hold_eop_q; // 只有EOP实际被目标接收才释放packet owner。
 wire effective_owner=owner_valid_q&&!release_now; // EOP消费同拍允许下一包SOP装入弹性槽。
 wire load_space=!hold_valid_q||output_take; // 空槽或本拍真实消费允许无气泡替换。
 wire input_kind_legal=(i_kind<3'd4); // 三位输入保留4..7作为可验证非法编码。
 wire input_phase_legal=!effective_owner?i_sop:((i_kind=={1'b0,owner_kind_q})&&!i_sop); // 新包必须SOP，包体必须保持kind且不得重发SOP。
 wire input_take=active&&i_valid&&input_kind_legal&&input_phase_legal&&load_space; // 所有输入状态只由真实ready-valid事件推进。
 assign o_ready=active&&input_kind_legal&&input_phase_legal&&load_space; // 坏kind/边界及满弹性槽均失败关闭。
 always @(*) begin // 仅当前owner kind对应的一个输出可以有效，禁止多路复制同一flit。
  o_kind_valid=4'd0;o_kind_data=2048'd0;o_kind_meta=512'd0;o_kind=12'd0;o_kind_sop=4'd0;o_kind_eop=4'd0; // 无效通道明确清零。
  if(active&&hold_valid_q) begin
   o_kind_valid[hold_kind_q]=1'b1; // 恰好一个合法目标获得valid。
   o_kind_data[hold_kind_q*512+:512]=hold_data_q;o_kind_meta[hold_kind_q*128+:128]=hold_meta_q; // payload与opaque metadata保持原值。
   o_kind[hold_kind_q*3+:3]={1'b0,hold_kind_q};o_kind_sop[hold_kind_q]=hold_sop_q;o_kind_eop[hold_kind_q]=hold_eop_q; // 输出kind和packet边界与槽内容一致。
  end
 end
 always @(posedge i_clk) begin // 弹性槽、packet owner与sticky诊断的唯一时序所有者。
  if(!i_rstn||!i_enable) begin
   hold_valid_q<=1'b0;hold_sop_q<=1'b0;hold_eop_q<=1'b0;hold_data_q<=512'd0;hold_meta_q<=128'd0;hold_kind_q<=2'd0; // reset取消尚未交付flit。
   owner_valid_q<=1'b0;owner_kind_q<=2'd0;invalid_kind_q<=1'b0;kind_change_q<=1'b0;framing_q<=1'b0; // reset取消packet tenure与旧错误。
  end else begin
   if(i_valid&&load_space&&!input_kind_legal)invalid_kind_q<=1'b1; // 仅当本拍可考察新头项时诊断非法kind；满槽后的下一头项尚不属于当前packet。
   if(i_valid&&load_space&&input_kind_legal&&!input_phase_legal) begin
    if(effective_owner&&(i_kind!={1'b0,owner_kind_q}))kind_change_q<=1'b1; // packet中途换kind单独诊断。
    else framing_q<=1'b1; // 缺SOP或owner期间重复SOP属于边界错误。
   end
   if(output_take) begin
    hold_valid_q<=1'b0; // 消费后缺省清空，若同拍有新输入则由后续赋值无气泡替换。
    if(hold_eop_q)owner_valid_q<=1'b0; // 只在真实EOP消费时结束旧packet。
   end
   if(input_take) begin
    hold_valid_q<=1'b1;hold_data_q<=i_data;hold_meta_q<=i_meta;hold_kind_q<=i_kind[1:0];hold_sop_q<=i_sop;hold_eop_q<=i_eop; // 原子保存全部可见字段。
    if(!effective_owner)begin owner_valid_q<=1'b1;owner_kind_q<=i_kind[1:0];end // 新SOP从接纳到EOP输出期间独占目标kind。
   end
  end
 end
 assign o_owner_valid=active&&owner_valid_q;assign o_owner_kind=o_owner_valid?{1'b0,owner_kind_q}:3'd0; // owner观察口不构成额外握手。
 assign o_invalid_kind=invalid_kind_q;assign o_kind_change_error=kind_change_q;assign o_framing_error=framing_q; // 导出sticky错误。
 assign o_error=invalid_kind_q||kind_change_q||framing_q;assign o_implemented=1'b1; // 仅声明本partial demux切片已实现。
 assign o_valid=1'b0;assign o_data=512'd0;assign o_meta=128'd0; // 旧聚合输出永不伪装成已完成事务。
endmodule
`default_nettype wire
