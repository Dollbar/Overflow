module dl_replay_header_tx #( // dl_replay_header_tx模块：LLR发送头调度与可选提前元数据保护
    parameter integer C_EARLY_TX_METADATA = 0 // 非零时采用由集成层明确证明的提前发送源元数据资格
) ( // dl_replay_header_tx模块：LLR发送头调度，单时钟沿前输出和沿上提交
    input wire i_clk, // 本地唯一时钟
    input wire i_rstn, // 低有效同步复位
    input wire i_link_reset, // 同步链路状态清除
    input wire i_flit_send, // 本沿实际提交所选Flit
    input wire i_payload, // 所选源含payload
    input wire i_replay, // 所选源来自重放队列，含最后一项
    input wire i_first_replay, // 所选源是本次首项重放
    input wire [8:0] i_tx_sequence, // 所选源完整非零序号
    input wire i_tx_metadata_ok, // 仅提前模式使用，默认模式仍执行完整原始元数据保护
    input wire [8:0] i_rx_sequence, // 含本拍接纳结果的接收非零序号
    input wire i_rx_request, // 本拍接收事件重装三个请求副本
    input wire i_new_group, // 本拍进入新的实际FEC组
    output wire [23:0] o_header, // 有效时输出完整头，保留位为零
    output wire o_header_valid, // 本拍生成并提交有效头
    output wire o_metadata_error, // send拍内部元数据不合法
    output wire [2:0] o_explicit_count, // 当前显式发送间隔状态
    output wire [1:0] o_request_count, // 当前剩余请求副本状态
    output wire [8:0] o_request_sequence, // 首份实际发送时捕获的目标
    output wire o_group_used // 当前组已实际发送过请求
); // 端口结束
reg [2:0] reg_explicit_count; // 显式间隔计数
reg [1:0] reg_request_count; // 请求副本计数
reg [8:0] reg_request_sequence; // 请求目标快照
reg reg_group_used; // 当前组请求占用
wire flag_active; // 复位和清除外的工作资格
wire flag_bad_metadata; // 内部元数据保护
wire flag_send; // 合法实际发送
wire flag_explicit; // 当前头使用完整序号
wire flag_request; // 当前头使用请求编码
wire [1:0] dec_pending; // 同拍接收事件之后的副本数
wire [8:0] dec_successor; // 有效接收序号的环后继
wire [8:0] dec_target; // 本拍请求目标
wire [23:0] dec_explicit_header; // 完整序号头
wire [23:0] dec_command_header; // 压缩序号与命令头
assign flag_active = i_rstn && !i_link_reset; // 同步复位期间沿前静默
assign flag_bad_metadata = (i_rx_sequence == 9'd0) || ((C_EARLY_TX_METADATA != 0) ? !i_tx_metadata_ok : ((i_tx_sequence == 9'd0) || (i_replay && !i_payload) || (i_first_replay && !i_replay))); // 非零序号及源类别一致性
assign flag_send = flag_active && i_flit_send && !flag_bad_metadata; // 只提交合法元数据
assign dec_pending = i_rx_request ? 2'd3 : reg_request_count; // 先处理同拍接收请求
assign flag_explicit = i_first_replay || (reg_explicit_count <= 3'd1); // 先减一后判零，首重放优先
assign flag_request = !flag_explicit && (dec_pending != 2'd0) && (!reg_group_used || i_new_group); // 同一实际组最多一份请求
assign dec_successor = (i_rx_sequence == 9'd511) ? 9'd1 : i_rx_sequence + 9'd1; // 合法序号环跳过零
assign dec_target = (dec_pending == 2'd3) ? dec_successor : reg_request_sequence; // 首次实际发送捕获，其余保持
assign dec_explicit_header = {2'b00, i_replay, i_payload, 3'b000, i_tx_sequence, 8'b00000000}; // op为Original或Replay
assign dec_command_header = {2'b01, flag_request, i_payload, (flag_request ? dec_target : i_rx_sequence), i_tx_sequence[2:0], 8'b00000000}; // Ack或Replay Request字段
assign o_header = flag_send ? (flag_explicit ? dec_explicit_header : dec_command_header) : 24'd0; // 非提交拍清零输出
assign o_header_valid = flag_send; // 有效即本拍提交
assign o_metadata_error = flag_active && i_flit_send && flag_bad_metadata; // 空闲元数据不触发诊断
assign o_explicit_count = reg_explicit_count; // 完整当前状态观察
assign o_request_count = reg_request_count; // 完整当前状态观察
assign o_request_sequence = reg_request_sequence; // 完整当前状态观察
assign o_group_used = reg_group_used; // 完整当前状态观察
always @(posedge i_clk) begin // 显式间隔只按合法实际发送推进
    if (!i_rstn) begin // 全局同步复位
        reg_explicit_count <= 3'd7; // 初始七个Flit间隔
    end else if (i_link_reset) begin // 链路重新初始化
        reg_explicit_count <= 3'd7; // 重装间隔
    end else if (flag_send) begin // 实际合法提交
        if (flag_explicit) begin // 显式发送重装
            reg_explicit_count <= 3'd7; // 保持七Flit间隔
        end else begin // 非显式发送推进
            reg_explicit_count <= reg_explicit_count - 3'd1; // 已排除零和一，不会下溢
        end // 结束显式分支
    end // 其他周期保持
end // 显式计数寄存器结束
always @(posedge i_clk) begin // 接收请求和本拍发送副本顺序处理
    if (!i_rstn) begin // 全局同步复位
        reg_request_count <= 2'd0; // 初始无请求
    end else if (i_link_reset) begin // 链路重新初始化
        reg_request_count <= 2'd0; // 清空请求
    end else if (flag_send && flag_request) begin // 本拍实际发出一份请求
        reg_request_count <= dec_pending - 2'd1; // 消耗接收重装之后的副本数
    end else if (i_rx_request) begin // 接收请求尚未实际发送
        reg_request_count <= 2'd3; // 指派三个副本而非累加
    end // 其他周期保持
end // 请求副本寄存器结束
always @(posedge i_clk) begin // 首份发送时冻结请求目标
    if (!i_rstn) begin // 全局同步复位
        reg_request_sequence <= 9'd0; // 没有已捕获请求
    end else if (i_link_reset) begin // 链路重新初始化
        reg_request_sequence <= 9'd0; // 清除旧目标
    end else if (flag_send && flag_request && (dec_pending == 2'd3)) begin // 首份实际发送
        reg_request_sequence <= dec_successor; // 捕获当拍有效接收序号后继
    end // 其他周期保持目标
end // 请求目标寄存器结束
always @(posedge i_clk) begin // 实际FEC组请求占用
    if (!i_rstn) begin // 全局同步复位
        reg_group_used <= 1'b0; // 初始组可发送请求
    end else if (i_link_reset) begin // 链路重新初始化
        reg_group_used <= 1'b0; // 清除组占用
    end else if (flag_send && flag_request) begin // 新组同拍发送也必须记占用
        reg_group_used <= 1'b1; // 本组已有实际请求
    end else if (i_new_group) begin // 无请求发送时进入新组
        reg_group_used <= 1'b0; // 即使空闲也释放旧组占用
    end // 其他周期保持
end // 组占用寄存器结束
endmodule // 结束dl_replay_header_tx模块
