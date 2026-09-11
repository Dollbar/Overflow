// 默认配置完整归纳：独立上计数字数、剩余时间和环形范围队列对应全部真实寄存器。
`timescale 1ps/1ps // 形式步使用共同采样沿，物理十毫秒周期由独立常量固定。
module uart_reset_properties ( // 全状态与全输出复位归纳模块。
    input wire i_clk, // 实际控制器与独立参考状态使用同一采样时钟。
    input wire i_rstn, // 复位在每一步均自由变化，不假设只有启动时使用。
    input wire i_local_request, // 包含忙期间和错误同时提交的任意固件请求。
    input wire i_local_all, // 全部本地请求范围自由变化。
    input wire i_rx_request, // 任意远端请求，包括队列满时过载。
    input wire i_rx_request_all, // 每条远端请求范围独立自由。
    input wire i_rx_response, // 任意提前或等待中的响应事件。
    input wire [2:0] i_rx_response_status, // 全部三位状态均为自由输入。
    input wire i_tx_take, // 任意真实提交输入，包含无pending的故障情况。
    output wire [2:0] o_groups, // 状态界全部寄存器关系和全部公开输出三组性质。
    output wire o_violation // 完整合取失败位用于实际复位基例和一步归纳。
); // 结束默认控制器完整归纳接口。
    localparam [24:0] C_WAIT_EDGES = 25'd15625000; // 独立字面十毫秒除以默认六百四十皮秒周期。
    reg ref_running, ref_wait, ref_fault, ref_all; // 用独立运行和等待位保存本地所有权而不复用DUT状态编码。
    reg [5:0] ref_sent; // 本轮累计真实发送NoOp数，与DUT剩余数方向相反。
    reg [24:0] ref_time_left; // 以剩余真实周期递减，与DUT等待沿计数方向相反。
    reg [2:0] ref_count; // 仅三位保存参考队列长度，不能依赖DUT五位计数。
    reg [1:0] ref_head; // 四项独立环形参考队列的读指针。
    wire [3:0] ref_scopes, ordered_scopes; // 原始环形存储和按当前队首旋转后的全部真实范围关系。
    wire [1:0] ref_tail; // 从环形头和长度推导新请求写入槽位。
    wire [42:0] observed_state; // 脚本精确连接实际四十三位全部寄存器，不能成为自由输入。
    wire [55:0] observed, expected; // 实际全部公开输出与独立参考的完整拼接。
    wire actual_ready, actual_stream, actual_block, actual_pending, actual_wait; // 真实资格和状态输出。
    wire [31:0] actual_word; // 真实全部维护字数据位。
    wire [1:0] actual_kind; // 真实当前维护类型。
    wire [5:0] actual_left; // 真实当前尚未提交的NoOp数量。
    wire [4:0] actual_count; // 真实响应队列全部五位观察。
    wire actual_start, actual_done, actual_retry, actual_reply, actual_fault, actual_error; // 真实全部同沿控制与诊断事件。
    wire ref_ready, ref_start, ref_success, ref_retry, ref_pending, ref_error, ref_push; // 所有参考资格只从独立状态和自由输入生成。
    wire ref_noop_take, ref_request_take, ref_reply_take, ref_stream, ref_block; // 独立实际提交和两类禁止状态。
    wire [1:0] ref_kind, ref_phase; // 当前维护类型和仅用于关系比较的预期DUT阶段。
    wire [31:0] ref_word; // 使用独立字面线编码和环形队首构造完整发送字。
    wire [5:0] ref_left; // 四十减真实累计发送数得到独立余数。
    wire [24:0] ref_elapsed; // 由完整剩余周期得到应有的实际等待计数。
    wire bounds_ok, state_ok; // 完整参考状态界和所有实际寄存器对应关系。
    genvar gen_slot; // 四个独立参考环形范围寄存器。
    dl_uart_reset_control Reset_Inst ( // 证明实际默认产品模块，不替换内部状态或发送资格。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_local_request(i_local_request), .i_local_all(i_local_all), // 全部本地事件保持符号自由。
        .i_rx_request(i_rx_request), .i_rx_request_all(i_rx_request_all), .i_rx_response(i_rx_response), // 全部远端事件保持符号自由。
        .i_rx_response_status(i_rx_response_status), .i_tx_take(i_tx_take), // 无状态资格和合法提交的外加假设。
        .o_local_ready(actual_ready), .o_stream_reset(actual_stream), .o_block_messages(actual_block), // 全部资格和禁止状态参与证明。
        .o_tx_pending(actual_pending), .o_tx_word(actual_word), .o_tx_kind(actual_kind), .o_waiting(actual_wait), // 全部发送数据与等待状态参与证明。
        .o_noops_left(actual_left), .o_response_count(actual_count), .o_local_start(actual_start), // 完整计数和本地接纳事件参与证明。
        .o_local_done(actual_done), .o_retry(actual_retry), .o_reply_done(actual_reply), .o_fault(actual_fault), .o_error(actual_error) // 全部成功重试和故障事件参与证明。
    ); // 结束实际默认产品接口连接。
    assign observed = {actual_ready, actual_stream, actual_block, actual_pending, actual_word, actual_kind, actual_wait, actual_left, actual_count, actual_start, actual_done, actual_retry, actual_reply, actual_fault, actual_error}; // 无输出位被排除或替换为常量。
    assign ref_ready = i_rstn && !ref_fault && !ref_running && !ref_wait; // 独立本地所有权空闲时才可接受固件请求。
    assign ref_start = ref_ready && i_local_request; // 同沿新请求必须具备真正参考接纳资格。
    assign ref_success = i_rstn && !ref_fault && ref_wait && i_rx_response && (i_rx_response_status == 3'd0); // 只有等待阶段的适用零状态才能成功。
    assign ref_retry = i_rstn && !ref_fault && ref_wait && (ref_time_left == 25'd1) && !ref_success; // 剩余最后一个真实周期且没有成功才重试。
    assign ref_pending = i_rstn && !ref_fault && !ref_start && !ref_retry && (ref_running || (ref_count != 3'd0)); // 新开始和超时当沿抑制旧维护offer。
    assign ref_kind = !ref_pending ? 2'd0 : ref_running ? ((ref_sent < 6'd40) ? 2'd1 : 2'd2) : 2'd3; // 只有实际累计发满四十字才允许Request。
    assign ref_word = (ref_kind == 2'd2) ? (ref_all ? 32'h00001184 : 32'h00000184) : (ref_kind == 2'd3) ? (ref_scopes[ref_head] ? 32'h000011C4 : 32'h000001C4) : 32'd0; // 全部保留位由独立字面编码确定为零。
    assign ref_noop_take = (ref_kind == 2'd1) && i_tx_take; // 不把停顿或无效提交计入实际NoOp字数。
    assign ref_request_take = (ref_kind == 2'd2) && i_tx_take; // 真正提交Request是剩余时间装载的唯一来源。
    assign ref_reply_take = (ref_kind == 2'd3) && i_tx_take; // 每次真实SUCCESS提交恰好移除原队首。
    assign ref_error = i_rstn && !ref_fault && ((i_tx_take && !ref_pending) || (i_rx_request && (ref_count == 3'd4) && !ref_reply_take)); // 任意非法take和无法借出队槽位的过载都明确进入故障。
    assign ref_push = i_rstn && !ref_fault && !ref_error && i_rx_request; // 参考有限队列逐条接收所有容量允许的请求。
    assign ref_stream = !i_rstn || ref_fault || ref_running || ref_wait || (ref_count != 3'd0) || ref_start || i_rx_request; // 任一本地或远端所有权都会保持数据流复位。
    assign ref_block = !i_rstn || ref_fault || ref_running || ref_start || ref_retry; // 普通消息仅在全局故障及本地维护序列中被阻断。
    assign ref_left = ref_running ? 6'd40-ref_sent : 6'd0; // 不活动时实际剩余计数应为零。
    assign ref_elapsed = ref_wait ? C_WAIT_EDGES-ref_time_left : 25'd0; // 独立剩余时间变换只用于核对实际上计数状态。
    assign ref_phase = ref_running ? ((ref_sent < 6'd40) ? 2'd1 : 2'd2) : ref_wait ? 2'd3 : 2'd0; // 参考没有依赖该编码来推进任何自身寄存器。
    assign ref_tail = ref_head+ref_count[1:0]; // 四项环形索引按自然模四运算定位当前队尾。
    generate // 所有四项参考内容和真实存储位关系参与同一个归纳。
        for (gen_slot = 32'd0; gen_slot < 32'd4; gen_slot = gen_slot+32'd1) begin : gen_scope // 逐槽保存参考范围而不跟随DUT整体移位。
            localparam [1:0] C_SLOT = gen_slot[1:0]; // 显式两位常量限定环形地址宽度。
            reg ref_bit; // 每个槽位使用独立参考寄存器。
            wire [1:0] read_index; // 从参考头部旋转得到实际固定槽应对应的位置。
            assign ref_scopes[gen_slot] = ref_bit; // 组合汇集全部参考真实范围。
            assign read_index = ref_head+C_SLOT; // 对应固定位置使用自然模四地址。
            assign ordered_scopes[gen_slot] = ref_scopes[read_index]; // 空闲槽也保持零并参与全部位比较。
            always @(posedge i_clk) begin // 独立环形槽只随参考提交和请求事件更新。
                if (!i_rstn || ref_fault || ref_error) ref_bit <= 1'b0; // 全局或故障取消全部旧范围所有权。
                else if (ref_push && (ref_tail == C_SLOT)) ref_bit <= i_rx_request_all; // 满队列同拍替换优先把新范围写入旧队首槽。
                else if (ref_reply_take && (ref_head == C_SLOT)) ref_bit <= 1'b0; // 真正出队后清除旧槽以维持空闲位关系。
            end // 结束单个环形参考范围寄存器。
        end // 结束全部四项范围寄存器和关系展开。
    endgenerate // 结束完整环形队列参考。
    assign bounds_ok = !ref_elapsed[24] && !(ref_running && ref_wait) && (ref_sent <= 6'd40) && (ref_count <= 3'd4) && (ref_wait ? ((ref_time_left >= 25'd1) && (ref_time_left <= C_WAIT_EDGES) && (ref_sent == 6'd40)) : (ref_time_left == 25'd0)) && (!ref_fault || (!ref_running && !ref_wait && !ref_all && (ref_sent == 6'd0) && (ref_count == 3'd0) && (ref_head == 2'd0) && (ref_scopes == 4'd0))) && ((ordered_scopes >> ref_count) == 4'd0); // 参考边界互斥故障清空和全部空闲范围为零本身都是待证结论。
    assign state_ok = observed_state == {ref_fault, ordered_scopes, 2'd0, ref_count, ref_all, ref_elapsed[23:0], ref_left, ref_phase}; // 全部四十三个真实寄存位均对应独立参考，没有自由状态切口。
    assign expected = {ref_ready, ref_stream, ref_block, ref_pending, ref_word, ref_kind, (i_rstn && !ref_fault && ref_wait), ((i_rstn && !ref_fault) ? ref_left : 6'd0), ((i_rstn && !ref_fault) ? {2'd0, ref_count} : 5'd0), ref_start, (ref_success && !ref_error), (ref_retry && !ref_error), ref_reply_take, (i_rstn && ref_fault), ref_error}; // 完整构造全部五十六位公开输出，包括复位屏蔽和同沿故障。
    assign o_groups[0] = !bounds_ok; // 参考自身状态界必须保持而不能外加假设。
    assign o_groups[1] = !state_ok; // 全部真实寄存器及每个队列内容位必须保持关系。
    assign o_groups[2] = observed != expected; // 任一公开输出位不等都构成实际反例。
    assign o_violation = |o_groups; // 三组完整性质共同成为归纳前提与下一步结论。
    always @(posedge i_clk) begin // 独立维护本地排空与Request发送期间的所有权。
        if (!i_rstn || ref_fault || ref_error) ref_running <= 1'b0; // 全局或错误取消旧本地运行。
        else if (ref_start || ref_retry) ref_running <= 1'b1; // 每次新尝试建立完整运行所有权。
        else if (ref_request_take) ref_running <= 1'b0; // Request真实发送后转交独立等待所有权。
    end // 结束参考本地运行寄存器。
    always @(posedge i_clk) begin // 等待所有权独立于远端请求和响应队列。
        if (!i_rstn || ref_fault || ref_error || ref_success || ref_retry) ref_wait <= 1'b0; // 成功和重试仅释放本地等待。
        else if (ref_request_take) ref_wait <= 1'b1; // 提前SUCCESS不能替代Request真实提交后的等待。
    end // 结束参考本地等待寄存器。
    always @(posedge i_clk) begin // 独立向上累计本轮已经真正发送的NoOp数。
        if (!i_rstn || ref_fault || ref_error || ref_start || ref_retry) ref_sent <= 6'd0; // 全新尝试不能继承上轮已经发送的字数。
        else if (ref_noop_take) ref_sent <= ref_sent+6'd1; // 只有真实NoOp消费增加计数。
    end // 结束参考实际发送字数寄存器。
    always @(posedge i_clk) begin // 独立剩余时间由真实Request提交装载且每沿递减。
        if (!i_rstn || ref_fault || ref_error || ref_success || ref_retry) ref_time_left <= 25'd0; // 所有离开等待的事件清除旧截止时间。
        else if (ref_request_take) ref_time_left <= C_WAIT_EDGES; // 默认十毫秒等待从实际发送Request的当前沿开始。
        else if (ref_wait) ref_time_left <= ref_time_left-25'd1; // 只有真正等待的下一个时钟沿减少剩余周期。
    end // 结束参考剩余等待时间寄存器。
    always @(posedge i_clk) begin // 独立冻结本地请求范围。
        if (!i_rstn || ref_fault || ref_error) ref_all <= 1'b0; // 全局和故障清除旧本地范围。
        else if (ref_start) ref_all <= i_local_all; // 重试和远端请求不能覆盖本轮范围。
    end // 结束参考本地范围寄存器。
    always @(posedge i_clk) begin // 队列长度由独立入队和实际响应出队更新。
        if (!i_rstn || ref_fault || ref_error) ref_count <= 3'd0; // 清空故障中的全部旧待回复义务。
        else if (ref_push && !ref_reply_take) ref_count <= ref_count+3'd1; // 仅入队增加真实待回复条数。
        else if (ref_reply_take && !ref_push) ref_count <= ref_count-3'd1; // 仅实际响应减少待回复条数。
    end // 结束独立参考队列长度寄存器。
    always @(posedge i_clk) begin // 环形头部只在真实响应出队时移动。
        if (!i_rstn || ref_fault || ref_error) ref_head <= 2'd0; // 全局或故障统一重新建立环形队列起点。
        else if (ref_reply_take) ref_head <= ref_head+2'd1; // 四项参考队列自然模四环回。
    end // 结束独立参考环形头寄存器。
    always @(posedge i_clk) begin // 粘滞故障具有唯一同步全局复位恢复条件。
        if (!i_rstn) ref_fault <= 1'b0; // 全局复位清除参考故障。
        else if (ref_error) ref_fault <= 1'b1; // 成功或后续固件请求不能清除过载诊断。
    end // 结束独立参考故障寄存器。
endmodule // 结束默认UART复位控制全部真实状态和输出归纳模块。
