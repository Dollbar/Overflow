module rs_tx_calendar_frame #( // 模块 rs_tx_calendar_frame：连接真实日历和完整帧的同域包装器
    parameter integer C_SERIAL_GBPS = 200, // 参数指定每条串行通道速率类别
    parameter integer C_LANES = 1, // 参数指定当前物理链路通道数
    parameter integer C_BLOCKS = 2 // 参数指定每拍连续块数
) ( // 开始相位恢复、整帧预约和逐组输出接口
    input wire i_clk, // 输入唯一上升沿工作时钟
    input wire i_rstn, // 输入同步低有效复位并禁止当拍传输
    input wire i_phase_load, // 输入本地相位恢复，同时取消当前未完成帧
    input wire [13:0] i_phase, // 输入待恢复的共同码字相位
    input wire i_rapid, // 输入仅在相位恢复时捕获的持续RAM模式
    input wire i_resiliency, // 输入仅在相位恢复时捕获的链路弹性配置
    input wire i_pl_id, // 输入仅在相位恢复时捕获的物理层标识
    input wire i_flit_valid, // 输入上游可预约一条完整DL帧的资格
    input wire i_data_valid, // 输入已预约当前DL帧本组数据有效
    input wire [(64*C_BLOCKS)-1:0] i_data, // 输入当前连续数据块，首块在低位
    input wire i_block_ready, // 输入本地块组接收就绪，不代表PCS可暂停
    output wire [13:0] o_phase, // 输出真实调度器当前寄存相位
    output wire [13:0] o_next_phase, // 输出考虑当拍完整提交后的下一候选相位
    output wire [1:0] o_next_kind, // 输出DL、AM、RAM或速率Idle候选种类
    output wire o_next_valid, // 输出候选种类有效，复位及恢复期间无效
    output wire o_flit_ready, // 输出当前可预约DL帧的资格
    output wire o_flit_reserve, // 输出完整DL帧真实预约事件，不提前消费Data
    output wire o_cmd_ready, // 输出真实帧控制器命令槽就绪
    output wire o_cmd_accept, // 输出当前合法帧命令实际接纳
    output wire o_cmd_reject, // 输出真实帧控制器命令拒绝诊断
    output wire o_active, // 输出已有帧正在逐组发送
    output wire o_data_ready, // 输出当前DL数据组可被消费
    output wire o_data_take, // 输出当前DL数据组实际消费
    output wire o_block_valid, // 输出当前完整格式化块组有效
    output wire o_block_take, // 输出当前块组实际提交
    output wire o_block_last, // 输出当前有效组为整帧最后一组
    output wire o_frame_done, // 输出完整八十块实际发送完成
    output wire o_codeword_commit, // 输出真实日历调度器的码字提交事件
    output wire o_dl_done, // 输出当前DL帧完整提交，控制帧不得产生
    output wire o_starved, // 输出命令或当前被请求Data缺料诊断
    output wire [6:0] o_block_index, // 输出真实帧控制器当前组首索引
    output wire [(2*C_BLOCKS)-1:0] o_sync_headers, // 输出真实格式器逻辑同步头
    output wire [(64*C_BLOCKS)-1:0] o_payloads // 输出真实格式器完整块字段
); // 结束完整同域顶层端口
localparam [13:0] C_AM_MASK = (C_SERIAL_GBPS == 200 && C_LANES == 4) ? 14'd16383 : ((C_SERIAL_GBPS == 100 && C_LANES == 4) || (C_SERIAL_GBPS == 200 && C_LANES == 2)) ? 14'd8191 : 14'd4095; // 常量按规范表三之五确定普通AM相位掩码
localparam [13:0] C_RAM_MASK = (C_SERIAL_GBPS == 200 && C_LANES == 4) ? 14'd127 : ((C_SERIAL_GBPS == 100 && C_LANES == 4) || (C_SERIAL_GBPS == 200 && C_LANES == 2)) ? 14'd63 : 14'd31; // 常量按普通AM周期的一百二十八分之一确定RAM掩码
reg r_rapid; // 寄存器保存已经建立的持续RAM模式
reg r_resiliency; // 寄存器保存相位恢复时捕获的弹性配置
reg r_pl_id; // 寄存器保存相位恢复时捕获的物理层标识
wire flag_frame_rstn; // 信号在复位或本地恢复时同步取消当前帧并屏蔽传输
wire flag_am; // 信号预判当前寄存相位的普通AM位置
wire flag_ram; // 信号预判当前寄存相位的持续RAM位置
wire flag_idle; // 信号预判当前寄存相位的普通速率Idle位置
wire [13:0] wire_phase_after; // 信号保存与当拍完成无关的固定下一码字相位
wire flag_after_am; // 信号预判固定下一相位的普通AM位置
wire flag_after_ram; // 信号预判固定下一相位的持续RAM位置
wire flag_after_idle; // 信号预判固定下一相位的普通速率Idle位置
wire [1:0] wire_kind_current; // 信号保存当前相位已完成译码的事件
wire [1:0] wire_kind_after; // 信号保存固定下一相位已完成译码的事件
wire [1:0] wire_next_kind; // 信号由真实完整提交末级选择下一日历候选
wire flag_cmd_valid; // 信号表示下一候选具备控制内容或上游DL预约资格
wire [2:0] wire_cmd_kind; // 信号将日历事件转换为真实帧控制器的Data或Idle种类
wire [1:0] wire_cmd_marker; // 信号将日历事件转换为无标记或普通快速标记
wire [1:0] wire_rate_kind; // 信号接收真实调度器当前相位事件供本地结构审计
wire flag_rate_valid; // 信号接收真实调度器当前提交资格
wire flag_rate_dl_ready; // 信号接收真实调度器当前DL提交请求
wire flag_rate_dl_take; // 信号接收真实调度器当前DL提交事件
wire flag_rate_starved; // 信号接收真实调度器当前码字缺料诊断
assign flag_frame_rstn = i_rstn && !i_phase_load; // 本地恢复与复位同时禁止旧帧传输和新帧接纳
assign o_next_phase = o_phase + {{13{1'b0}},o_frame_done}; // 只对当拍真实完成码字进行下一命令相位预选
assign wire_phase_after = o_phase + 14'd1; // 固定下一相位提前计算，不串接真实完成信号
assign flag_am = ((o_phase & C_AM_MASK) == 14'd0); // 独立译码当前寄存相位的普通AM位置
assign flag_ram = ((o_phase & C_RAM_MASK) == 14'd0); // 独立译码当前寄存相位的持续RAM位置
assign flag_idle = (o_phase[9:0] == 10'd0); // 独立译码当前寄存相位的速率Idle位置
assign flag_after_am = ((wire_phase_after & C_AM_MASK) == 14'd0); // 独立译码固定下一相位的普通AM位置
assign flag_after_ram = ((wire_phase_after & C_RAM_MASK) == 14'd0); // 独立译码固定下一相位的持续RAM位置
assign flag_after_idle = (wire_phase_after[9:0] == 10'd0); // 独立译码固定下一相位的速率Idle位置
assign wire_kind_current = r_rapid ? (flag_ram ? 2'd2 : 2'd0) : (flag_am ? 2'd1 : (flag_idle ? 2'd3 : 2'd0)); // 当前相位普通AM优先，持续RAM不额外插Idle
assign wire_kind_after = r_rapid ? (flag_after_ram ? 2'd2 : 2'd0) : (flag_after_am ? 2'd1 : (flag_after_idle ? 2'd3 : 2'd0)); // 固定下一相位保持相同规范日历优先级
assign wire_next_kind = o_frame_done ? wire_kind_after : wire_kind_current; // 真实整帧完成仅做末级候选选择，不再进入相位译码链
assign o_next_valid = flag_frame_rstn; // 复位及恢复期间没有有效下一候选
assign o_next_kind = o_next_valid ? wire_next_kind : 2'd0; // 无效候选种类明确清零
assign wire_cmd_kind = (wire_next_kind == 2'd0) ? 3'd0 : 3'd1; // 数据槽发DL内容，其余日历槽发Idle控制序列
assign wire_cmd_marker = (wire_next_kind == 2'd1) ? 2'd1 : ((wire_next_kind == 2'd2) ? 2'd2 : 2'd0); // AM和RAM槽产生对应完整帧起始标记
assign flag_cmd_valid = flag_frame_rstn && ((wire_next_kind != 2'd0) || i_flit_valid); // 控制槽自足，数据槽必须先取得完整DL帧预约资格
assign o_flit_ready = o_cmd_ready && o_next_valid && (wire_next_kind == 2'd0); // 仅在真实命令槽可用的数据位置请求DL预约
assign o_flit_reserve = o_flit_ready && o_cmd_accept; // 只将真实DL命令接纳报告为完整帧预约
assign o_dl_done = o_frame_done && o_data_take; // 完整DL完成要求末组实际消费Data，控制完成不能代替
assign o_starved = (o_flit_ready && !i_flit_valid) || (o_data_ready && !i_data_valid); // 显式报告边界DL预约缺料或当前被请求数据缺料
always @(posedge i_clk) begin // 所有配置仅在同一真实工作时钟捕获
    if (!i_rstn) begin // 同步复位优先于本地相位恢复
        r_rapid <= 1'b0; // 复位恢复普通AM日历模式
        r_resiliency <= 1'b0; // 复位清除本地弹性配置
        r_pl_id <= 1'b0; // 复位清除本地物理层标识
    end else if (i_phase_load) begin // 仅在恢复相位的同沿采样新配置
        r_rapid <= i_rapid; // 捕获已由上层建立的持续RAM模式
        r_resiliency <= i_resiliency; // 捕获后续控制帧的弹性配置
        r_pl_id <= i_pl_id; // 捕获后续控制帧的物理层标识
    end // 无恢复时保持全部配置，输入扰动不得影响当前帧
end // 结束唯一配置时钟过程
rs_tx_rate_scheduler #(.C_SERIAL_GBPS(C_SERIAL_GBPS),.C_LANES(C_LANES)) u_rate ( // 连接已验证实际码字相位调度器
    .i_clk(i_clk), // 所有调度状态使用真实输入时钟
    .i_rstn(i_rstn), // 调度器保留同步复位最高优先级
    .i_phase_load(i_phase_load), // 恢复共同码字相位且取消当拍提交
    .i_phase(i_phase), // 传入完整十四位待恢复相位
    .i_rapid_alignment(r_rapid), // 只使用已经捕获的稳定模式
    .i_dl_valid(o_active), // 已接纳活跃帧提供当前完成所需资格，不使用未来DL预约
    .i_codeword_request(o_frame_done), // 只有完整八十块实际完成才请求推进日历
    .o_phase(o_phase), // 直接输出真实调度器寄存相位
    .o_slot_kind(wire_rate_kind), // 接收当前相位实际事件诊断
    .o_slot_valid(flag_rate_valid), // 接收当前码字提交资格诊断
    .o_codeword_commit(o_codeword_commit), // 直接输出真实码字提交事件供独立检查
    .o_dl_ready(flag_rate_dl_ready), // 接收调度器当前DL提交请求诊断
    .o_dl_take(flag_rate_dl_take), // 接收调度器当前DL提交事件诊断
    .o_starved(flag_rate_starved) // 接收调度器当前完整码字缺料诊断
); // 结束真实日历实例
rs_tx_frame_control #(.C_BLOCKS(C_BLOCKS)) u_frame ( // 连接已验证完整帧控制器及其真实格式器
    .i_clk(i_clk), // 帧状态使用与调度器相同的真实输入时钟
    .i_rstn(flag_frame_rstn), // 同步取消恢复或复位时的当前未完成帧
    .i_cmd_valid(flag_cmd_valid), // 接收当前具备内容的下一命令资格
    .i_cmd_kind(wire_cmd_kind), // 接收按未来相位预选的完整帧种类
    .i_cmd_marker(wire_cmd_marker), // 接收按未来相位预选的标记
    .i_cmd_count((wire_next_kind == 2'd2) ? 8'hff : 8'd0), // 持续RAM未安排AM，计数固定为规范要求的全一
    .i_cmd_resiliency((wire_next_kind == 2'd0) ? 1'b0 : r_resiliency), // 仅控制帧捕获稳定弹性配置，Data元数据清零
    .i_cmd_pl_id((wire_next_kind == 2'd0) ? 1'b0 : r_pl_id), // 仅控制帧捕获稳定物理层标识
    .i_data_valid(i_data_valid), // 当前已预约Data帧的逐组有效直接进入真实控制器
    .i_data(i_data), // 当前实际DL字节直接进入真实格式器
    .i_block_ready(i_block_ready), // 本地接收就绪只限定实际块组提交
    .o_cmd_ready(o_cmd_ready), // 直接输出真实空闲或末组命令槽
    .o_cmd_accept(o_cmd_accept), // 直接输出真实命令捕获事件
    .o_cmd_reject(o_cmd_reject), // 保留真实命令拒绝诊断
    .o_active(o_active), // 直接输出当前帧活跃状态
    .o_data_ready(o_data_ready), // 直接输出当前Data组请求
    .o_data_take(o_data_take), // 直接输出当前Data组实际消费
    .o_block_valid(o_block_valid), // 直接输出真实完整块有效
    .o_block_take(o_block_take), // 直接输出真实块组提交
    .o_block_last(o_block_last), // 直接输出有效末组标志
    .o_frame_done(o_frame_done), // 直接输出完整八十块实际提交
    .o_block_index(o_block_index), // 直接输出真实当前组首索引
    .o_sync_headers(o_sync_headers), // 直接输出真实格式器同步头
    .o_payloads(o_payloads) // 直接输出真实格式器完整字段
); // 结束真实帧控制与格式器实例
endmodule // 结束模块 rs_tx_calendar_frame
