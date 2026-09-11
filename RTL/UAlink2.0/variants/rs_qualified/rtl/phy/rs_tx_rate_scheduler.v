module rs_tx_rate_scheduler #( // 模块 rs_tx_rate_scheduler：按实际码字提交推进共同相位的RS调度器
 parameter integer C_SERIAL_GBPS = 200, // 每条串行lane的标称速率类别
 parameter integer C_LANES = 1 // 当前物理链路lane数量
) ( // 本模块为同域请求提交接口，提交前允许组合候选变化
 input wire i_clk, // 唯一上升沿工作时钟
 input wire i_rstn, // 同步低有效复位并禁止复位期间提交
 input wire i_phase_load, // 同步恢复共同相位并取消当拍提交
 input wire [13:0] i_phase, // 待恢复的共同码字相位
 input wire i_rapid_alignment, // 上层已经建立的持续RAM模式
 input wire i_dl_valid, // DL源当前有完整且有效的flit
 input wire i_codeword_request, // 下游请求接纳当前组合码字槽
 output wire [13:0] o_phase, // 当前共同码字相位的完整观察
 output wire [1:0] o_slot_kind, // 零为DL，一为AM，二为RAM，三为速率匹配Idle
 output wire o_slot_valid, // 当前码字槽具备提交所需内容
 output wire o_codeword_commit, // 当拍真实码字提交事件
 output wire o_dl_ready, // 当前请求允许DL源交付完整flit
 output wire o_dl_take, // 当拍真实DL源接纳事件
 output wire o_starved // 当前数据槽请求因DL源缺料而未提交
); // 端口定义结束
localparam [13:0] C_AM_MASK = (C_SERIAL_GBPS == 200 && C_LANES == 4) ? 14'd16383 : ((C_SERIAL_GBPS == 100 && C_LANES == 4) || (C_SERIAL_GBPS == 200 && C_LANES == 2)) ? 14'd8191 : 14'd4095; // 表三之五的AM码字间隔掩码
localparam [13:0] C_RAM_MASK = (C_SERIAL_GBPS == 200 && C_LANES == 4) ? 14'd127 : ((C_SERIAL_GBPS == 100 && C_LANES == 4) || (C_SERIAL_GBPS == 200 && C_LANES == 2)) ? 14'd63 : 14'd31; // RAM间隔为对应AM间隔的一百二十八分之一
reg [13:0] reg_phase; // 唯一状态，全部合法profile共同周期为一万六千三百八十四码字
wire flag_active; // 复位及相位恢复之外允许候选和提交
wire flag_am_position; // 当前相位命中普通AM位置
wire flag_ram_position; // 当前相位命中持续RAM位置
wire flag_idle_position; // 当前相位命中普通速率匹配Idle位置
wire [1:0] wire_calendar_kind; // 不含本域复位资格的规范日历事件
generate // 编译展开时拒绝不支持的物理profile
 if (((C_SERIAL_GBPS != 100) && (C_SERIAL_GBPS != 200)) || ((C_LANES != 1) && (C_LANES != 2) && (C_LANES != 4))) begin : gen_invalid_profile // 只接受规范表中六组配置
  UALINK_RS_RATE_PROFILE_INVALID invalid_profile (); // 非法配置不能生成可用硬件
 end // 非法profile检查结束
endgenerate // 结束 generate 参数检查
assign flag_active = i_rstn && !i_phase_load; // 相位恢复与复位优先于当前槽请求
assign flag_am_position = ((reg_phase & C_AM_MASK) == 14'd0); // 按已提交码字相位判断AM
assign flag_ram_position = ((reg_phase & C_RAM_MASK) == 14'd0); // 按同一共同相位判断RAM
assign flag_idle_position = (reg_phase[9:0] == 10'd0); // 普通模式每一千零二十四码字提供Idle位置
assign wire_calendar_kind = i_rapid_alignment ? (flag_ram_position ? 2'd2 : 2'd0) : (flag_am_position ? 2'd1 : (flag_idle_position ? 2'd3 : 2'd0)); // AM替代Idle，持续RAM模式不额外插Idle
assign o_phase = reg_phase; // 完整暴露唯一状态供同域调度与验证使用
assign o_slot_kind = flag_active ? wire_calendar_kind : 2'd0; // 禁止提交期间输出无效的零种类
assign o_slot_valid = flag_active && ((wire_calendar_kind != 2'd0) || i_dl_valid); // 控制槽自足，数据槽必须具备真实DL内容
assign o_codeword_commit = o_slot_valid && i_codeword_request; // 只在真实请求与可用槽同时成立时提交
assign o_dl_ready = flag_active && (wire_calendar_kind == 2'd0) && i_codeword_request; // 控制槽绝不消耗DL源
assign o_dl_take = o_dl_ready && i_dl_valid; // 完整DL flit的真实接纳事件
assign o_starved = o_dl_ready && !i_dl_valid; // 数据缺料显式上报而不在RS伪造NOP
always @(posedge i_clk) begin // 唯一状态仅由真实工作时钟推进
 if (!i_rstn) begin // 同步复位具有最高优先级
  reg_phase <= 14'd0; // 初始化共同相位
 end else if (i_phase_load) begin // 相位恢复不同时消耗码字槽
  reg_phase <= i_phase; // 装载上层已经获得的共同相位
 end else if (o_codeword_commit) begin // 只有实际提交才推进日历
  reg_phase <= reg_phase + 14'd1; // 按全部profile的共同周期自然环回
 end // 无提交时保持共同相位
end // 唯一状态更新结束
endmodule // 结束模块 rs_tx_rate_scheduler
