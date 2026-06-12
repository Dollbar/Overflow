`timescale 1ns/1ps
`default_nettype none
// 将一个完整512-bit native TL Flit适配为builder输入；不推断多Flit包长或复制任何credit/replay owner。
module endpoint_tl_word_packet_boundary_adapter #( // 显式模式锁存native SOP/EOP；默认兼容每word独立成帧。
 parameter [15:0] FULL_RATE_CODE=16'd31250, // 无cooldown的已冻结全速率代码。
 parameter [15:0] REFERENCE_RATE_CODE=16'd3125, // 每十拍一个机会的已冻结参考速率代码。
 parameter integer EXPLICIT_PACKET_BOUNDARY_ENABLE=0,parameter integer INTERNAL_PACKET_BOUNDARY_ENABLE=0
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire i_active, // 单时钟、复位、Station使能和稳定端口资格。
 input wire i_rate_valid,output wire o_rate_ready,input wire [15:0] i_rate_code, // 该端口独立pacing配置。
 output wire o_rate_accept,output wire o_rate_error,output wire o_rate_configured,output wire [15:0] o_active_rate_code, // pacing状态。
 input wire i_budget_available, // 外部DL resident预算资格，不创建第二预算owner。
 input wire i_native_valid,output wire o_native_ready,input wire [511:0] i_native_flit,input wire [1:0] i_native_msg,input wire i_native_sop,input wire i_native_eop,input wire i_internal_sop,input wire i_internal_eop, // 显式或内部owner边界须与native word一起保持到该握手。
 output wire o_builder_valid,input wire i_builder_ready,output wire [511:0] o_builder_flit,output wire [1:0] o_builder_msg, // scheduled builder握手。
 output wire o_builder_sop,output wire o_builder_eop,output wire o_builder_flush,output wire o_error // 完整word边界、立即flush和失败关闭诊断。
);
 wire paced_ready,paced_valid,paced_rate_ready; // tx_pacing两侧真实握手。
 wire [511:0] paced_data; // 停顿时由pacer保持的完整TL Flit。
 wire [127:0] paced_meta; // `{保留,M,SOP,EOP}`随Flit一起锁定。
 wire unused_implemented; // 现有tx_pacing实现存在证书。
 wire inactive_input_error; // inactive端口不得接纳TL或速率配置。
 wire effective_native_sop,effective_native_eop,mode_conflict,effective_active;
 assign mode_conflict=(EXPLICIT_PACKET_BOUNDARY_ENABLE!=0)&&(INTERNAL_PACKET_BOUNDARY_ENABLE!=0);
 assign effective_active=i_active&&!mode_conflict; // 非法双owner配置禁止任何数据或配置握手。
 assign effective_native_sop=(EXPLICIT_PACKET_BOUNDARY_ENABLE!=0)?i_native_sop:((INTERNAL_PACKET_BOUNDARY_ENABLE!=0)?i_internal_sop:1'b1);
 assign effective_native_eop=(EXPLICIT_PACKET_BOUNDARY_ENABLE!=0)?i_native_eop:((INTERNAL_PACKET_BOUNDARY_ENABLE!=0)?i_internal_eop:1'b1);
 assign inactive_input_error=i_rstn&&i_enable&&!i_active&&(i_native_valid||i_rate_valid); // 静态inactive输入失败关闭。
 assign o_rate_ready=effective_active&&paced_rate_ready;
 assign o_native_ready=effective_active&&paced_ready; // 只有单一合法owner且pacer真实接纳时返回ready。
 assign o_builder_valid=effective_active&&paced_valid; // 非法双owner配置不产生builder候选。
 assign o_builder_flit=o_builder_valid?paced_data:512'd0; // 无有效候选时清零payload。
 assign o_builder_msg=o_builder_valid?paced_meta[3:2]:2'd0; // 二位M字段原样随完整word输出。
 assign o_builder_sop=o_builder_valid&&paced_meta[1]; // 显式SOP与对应word经过同一pacing寄存器。
 assign o_builder_eop=o_builder_valid&&paced_meta[0]; // 显式EOP与对应word经过同一pacing寄存器。
 assign o_builder_flush=o_builder_valid&&paced_meta[0]; // 只有显式EOP word请求builder形成DL frame。
 assign o_error=inactive_input_error||o_rate_error||!unused_implemented||mode_conflict; // 两个owner不可同时生效。
 tx_pacing #(.C_FULL_RATE_CODE(FULL_RATE_CODE),.C_REFERENCE_RATE_CODE(REFERENCE_RATE_CODE)) u_pacing( // 复用现有逐端口速率节拍和单word stall寄存器。
  .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable&&effective_active),.i_rate_valid(i_rate_valid&&effective_active),.o_rate_ready(paced_rate_ready),.i_rate_code(i_rate_code), // inactive或双owner配置永不接纳。
  .o_rate_accept(o_rate_accept),.o_rate_error(o_rate_error),.o_rate_configured(o_rate_configured),.o_active_rate_code(o_active_rate_code), // 公开实际配置结果。
  .i_valid(i_native_valid&&effective_active),.o_ready(paced_ready),.i_data(i_native_flit),.i_meta({124'd0,i_native_msg,effective_native_sop,effective_native_eop}), // Flit、M和边界同拍锁存。
  .o_valid(paced_valid),.i_output_ready(i_builder_ready&&effective_active),.o_data(paced_data),.o_meta(paced_meta), // 下游停顿时Flit、M和边界一起保持。
  .i_budget_available(i_budget_available&&effective_active),.o_implemented(unused_implemented)); // resident预算只作为资格输入。
endmodule // 结束完整native TL word packet-boundary适配器。
`default_nettype wire
