`timescale 1ns/1ps // 定义仿真时间单位；该声明不参与综合数据通路。
`default_nettype none // 禁止隐式网络掩盖全Fabric排空状态的漏接。
// 全Fabric Route提交监督器：归约所有旧epoch owner、队列和credit slot，并复用唯一Route commit状态机。
module switch_fabric_quiesce_commit_supervisor #(
 parameter integer C_FRONTEND_COMPONENTS=2, // Frontend owner与已提交输出等busy位数量。
 parameter integer C_SOURCE_TILE_COMPONENTS=2, // Source Tile occupancy与packet owner等busy位数量。
 parameter integer C_GROUP_CORE_COMPONENTS=2, // Group/Core输入槽、输出槽与packet owner等busy位数量。
 parameter integer C_DESTINATION_COMPONENTS=2, // Destination Group stage与Egress nonempty等busy位数量。
 parameter integer C_CREDIT_COMPONENTS=1, // Destination credit ledger中issued或occupied归约位数量。
 parameter integer C_EPOCH_WIDTH=8, // Active Route epoch宽度。
 parameter integer C_TIMEOUT_CYCLES=1024, // pending连续非空超过该周期数后报告粘滞超时。
 parameter integer C_TIMEOUT_WIDTH=11 // 必须能编码0至C_TIMEOUT_CYCLES的饱和等待计数。
)(
 input wire i_clk, // 管理/提交时钟，上升沿更新pending、epoch和超时状态。
 input wire i_rstn, // 同步低有效复位，清除提交与诊断状态。
 input wire i_commit_request, // CSR单周期Route shadow提交请求。
 input wire i_shadow_illegal, // Shadow Route或Port identity image非法时禁止提交。
 input wire [C_FRONTEND_COMPONENTS-1:0] i_frontend_busy, // Frontend各owner/output仍引用旧epoch的位图。
 input wire [C_SOURCE_TILE_COMPONENTS-1:0] i_source_tile_busy, // Source Tile occupancy/owner非空位图。
 input wire [C_GROUP_CORE_COMPONENTS-1:0] i_group_core_busy, // Group/Core owner或弹性槽非空位图。
 input wire [C_DESTINATION_COMPONENTS-1:0] i_destination_busy, // Destination stage/Egress队列非空位图。
 input wire [C_CREDIT_COMPONENTS-1:0] i_credit_nonquiescent, // Credit ledger issued/occupied物理slot非零位图。
 output wire o_new_sop_admission, // 仅IDLE且本周期无新请求时允许接收新packet SOP。
 output wire o_body_drain_enable, // 合法配置下始终允许已拥有packet的body/EOP继续排空。
 output wire o_quiesce_request, // 请求到达同周期即置位，并保持到原子commit或非法取消。
 output wire o_commit_pulse, // 全Fabric真正排空后送给Route/identity双表的单周期切换脉冲。
 output wire o_pending, // CSR可读提交等待状态。
 output wire o_all_empty, // 所有被监督组件与credit ledger均静止的组合归约结果。
 output wire [C_EPOCH_WIDTH-1:0] o_epoch, // 每次成功commit后递增的active Route epoch。
 output reg [C_TIMEOUT_WIDTH-1:0] o_wait_cycles, // pending且非空期间的饱和等待周期计数。
 output reg o_timeout_error, // 等待超过参数门限后置位并保持到reset。
 output wire o_commit_error, // Route commit控制器报告的非法shadow粘滞错误。
 output wire o_config_error, // 参数不能编码组件数量或超时门限时fail-closed。
 output wire o_error // 汇总参数、非法提交和等待超时诊断。
);
 function width_encodes; // 静态检查计数宽度是否能编码指定非负最大值。
  input integer width_value; // 被检查的位宽。
  input integer maximum_value; // 需要表达的最大无符号值。
  integer capacity;integer bit_index;
  begin
   capacity=1;
   for(bit_index=0;bit_index<width_value;bit_index=bit_index+1)capacity=capacity*2;
   width_encodes=(width_value>=1)&&(width_value<=30)&&(maximum_value>=0)&&(capacity>maximum_value);
  end
 endfunction
 localparam CONFIG_LEGAL=(C_FRONTEND_COMPONENTS>=1)&&(C_SOURCE_TILE_COMPONENTS>=1)&&
  (C_GROUP_CORE_COMPONENTS>=1)&&(C_DESTINATION_COMPONENTS>=1)&&(C_CREDIT_COMPONENTS>=1)&&
  (C_EPOCH_WIDTH>=1)&&(C_EPOCH_WIDTH<=30)&&(C_TIMEOUT_CYCLES>=1)&&
  width_encodes(C_TIMEOUT_WIDTH,C_TIMEOUT_CYCLES); // 非法参数禁止准入和commit。
 wire pending_q; // 唯一Route commit叶模块持有的pending状态。
 wire leaf_admission_unused; // 叶模块admission在请求同周期尚未拉低，本层采用更严格组合门控。
 wire leaf_quiesce_unused; // 本层加入请求同周期门控，因此不直接导出叶模块延迟一沿的quiesce。
 wire any_busy; // 所有旧epoch占用状态的统一归约。
 wire commit_shadow_illegal; // 参数非法与shadow非法共同阻止active image切换。
 wire [31:0] wait_cycles_extended; // 扩展计数后再与32位integer参数比较，避免有符号或截断歧义。
 assign any_busy=(|i_frontend_busy)||(|i_source_tile_busy)||(|i_group_core_busy)||
  (|i_destination_busy)||(|i_credit_nonquiescent); // 任一真实owner/slot存在都必须继续排空。
 assign o_all_empty=!any_busy; // 只有每一级均清零才满足全Fabric quiescent。
 assign o_config_error=!CONFIG_LEGAL; // 参数错误是静态fail-closed条件。
 assign commit_shadow_illegal=i_shadow_illegal||o_config_error; // 非法配置不得生成commit pulse。
 assign o_new_sop_admission=i_rstn&&CONFIG_LEGAL&&!(pending_q || i_commit_request); // 请求同周期即阻止新SOP。
 assign o_body_drain_enable=i_rstn&&CONFIG_LEGAL; // pending不阻止已有owner继续消费body/EOP。
 assign o_quiesce_request=i_rstn&&(pending_q||i_commit_request); // 给各级调度器持续提供排空模式。
 assign o_pending=pending_q; // 导出CSR pending，不创建第二份提交状态。
 assign o_error=o_config_error||o_commit_error||o_timeout_error; // 汇总严重管理/排空错误。
 assign wait_cycles_extended={{(32-C_TIMEOUT_WIDTH){1'b0}},o_wait_cycles}; // CONFIG_LEGAL保证复制次数非负。
 switch_route_commit #(.EPOCH_WIDTH(C_EPOCH_WIDTH)) u_route_commit( // 复用既有原子提交与epoch唯一owner。
  .i_clk(i_clk),.i_rstn(i_rstn),.i_commit_request(i_commit_request),.i_inflight_empty(o_all_empty),
  .i_shadow_illegal(commit_shadow_illegal),.o_admission_enable(leaf_admission_unused),
  .o_quiesce_request(leaf_quiesce_unused),.o_commit_pulse(o_commit_pulse),.o_pending(pending_q),
  .o_epoch(o_epoch),.o_commit_error(o_commit_error));
 always @(posedge i_clk) begin // 只监控等待时长；超时不取消pending，避免旧epoch数据被新表解释。
  if(!i_rstn) begin
   o_wait_cycles<={C_TIMEOUT_WIDTH{1'b0}}; // reset清除旧等待计数。
   o_timeout_error<=1'b0; // reset是清除超时粘滞位的唯一方式。
  end else if(!pending_q||o_all_empty) begin
   o_wait_cycles<={C_TIMEOUT_WIDTH{1'b0}}; // IDLE或已排空时重新开始下一次计时。
   o_timeout_error<=o_timeout_error; // 成功commit不隐式清除历史RAS证据。
  end else if(wait_cycles_extended<C_TIMEOUT_CYCLES) begin
   o_wait_cycles<=o_wait_cycles+{{(C_TIMEOUT_WIDTH-1){1'b0}},1'b1}; // 未达门限时逐周期累加。
   o_timeout_error<=o_timeout_error; // 等待恰好门限周期仍允许正常完成。
  end else begin
   o_wait_cycles<=o_wait_cycles; // 达门限后饱和，禁止无符号回绕掩盖stuck状态。
   o_timeout_error<=1'b1; // 超过门限后置位，pending继续fail-closed等待真实排空。
  end
 end
endmodule
`default_nettype wire // 恢复后续编译单元的默认网络行为。
