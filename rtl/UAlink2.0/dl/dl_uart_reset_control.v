// Stream0复位控制：实际维护提交、时钟推导的十毫秒等待和逐请求响应队列。
// 范围：内部同域控制模块；队列过载必须接上层恢复，完整收发仲裁集成另行验证。
`timescale 1ps/1ps // 以显式皮秒周期约束计时器的部署前提。
module dl_uart_reset_control #( // UART复位控制模块独立保存本地和远端所有权。
    parameter integer C_CLOCK_PERIOD_PS = 640, // 声明实际部署时钟周期以推导不提前的十毫秒等待。
    parameter integer C_RESPONSE_DEPTH = 4 // 保存每条已接收请求范围的有限队列容量。
) ( // 所有事件必须已位于同一个上升沿采样域。
    input wire i_clk, // 所有控制和队列寄存器使用的共同上升沿时钟。
    input wire i_rstn, // 同步低有效全局复位清除全部控制与故障。
    input wire i_local_request, // 固件请求在本地ready时被当前沿接受。
    input wire i_local_all, // 当前固件请求所选择的全部流范围。
    input wire i_rx_request, // 已完成framing和本流资格判断的远端请求事件。
    input wire i_rx_request_all, // 该远端请求的原始全部流范围。
    input wire i_rx_response, // 已确认适用于本流的边界复位响应事件。
    input wire [2:0] i_rx_response_status, // 原样解码的状态字段只有零表示成功。
    input wire i_tx_take, // 当前维护字在真实发送边界被接受的唯一提交事件。
    output wire o_local_ready, // 本地请求为空闲且未被全局或故障复位时可接纳。
    output wire o_stream_reset, // 禁用并清空本流数据和信用但不得清除接收framing。
    output wire o_block_messages, // 阻止普通DL消息而保留本轮强制维护路径。
    output wire o_tx_pending, // 当前存在可真正提交的维护字。
    output wire [31:0] o_tx_word, // 完整编码的当前维护字且保留位发零。
    output wire [1:0] o_tx_kind, // 零无效一NoOp二Request三SUCCESS响应。
    output wire o_waiting, // 当前本地请求正在等待适用SUCCESS。
    output wire [5:0] o_noops_left, // 本轮尚未实际发送的NoOp字数。
    output wire [4:0] o_response_count, // 包含当前队首的待回复远端请求条数。
    output wire o_local_start, // 当前沿真正接纳固件本地请求。
    output wire o_local_done, // 当前沿适用SUCCESS完成本地等待。
    output wire o_retry, // 当前沿超时进入新的完整排空序列。
    output wire o_reply_done, // 当前沿真正提交一个远端请求的响应。
    output wire o_fault, // 仅由全局复位清除的已锁存故障。
    output wire o_error // 本沿队列溢出或无pending却take的故障事件。
); // 结束UART复位控制接口。
    localparam [63:0] C_PERIOD = ((C_CLOCK_PERIOD_PS >= 1) && (C_CLOCK_PERIOD_PS <= 1000000000)) ? {32'd0, C_CLOCK_PERIOD_PS[31:0]} : 64'd1; // 非法周期使用安全常量避免除零并由下方守卫明确拒绝。
    localparam integer C_QUEUE_DEPTH = ((C_RESPONSE_DEPTH >= 1) && (C_RESPONSE_DEPTH <= 16)) ? C_RESPONSE_DEPTH : 1; // 非法深度只保证内部展开安全而不会绕过错误守卫。
    localparam [63:0] C_WAIT_CYCLES = (64'd10000000000+C_PERIOD-64'd1)/C_PERIOD; // 向上取整使等待绝不早于十毫秒。
    localparam integer C_TIMER_WIDTH = (C_WAIT_CYCLES <= 64'd2) ? 1 : // 覆盖最多二的1次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd4) ? 2 : // 覆盖最多二的2次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd8) ? 3 : // 覆盖最多二的3次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd16) ? 4 : // 覆盖最多二的4次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd32) ? 5 : // 覆盖最多二的5次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd64) ? 6 : // 覆盖最多二的6次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd128) ? 7 : // 覆盖最多二的7次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd256) ? 8 : // 覆盖最多二的8次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd512) ? 9 : // 覆盖最多二的9次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd1024) ? 10 : // 覆盖最多二的10次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd2048) ? 11 : // 覆盖最多二的11次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd4096) ? 12 : // 覆盖最多二的12次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd8192) ? 13 : // 覆盖最多二的13次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd16384) ? 14 : // 覆盖最多二的14次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd32768) ? 15 : // 覆盖最多二的15次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd65536) ? 16 : // 覆盖最多二的16次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd131072) ? 17 : // 覆盖最多二的17次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd262144) ? 18 : // 覆盖最多二的18次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd524288) ? 19 : // 覆盖最多二的19次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd1048576) ? 20 : // 覆盖最多二的20次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd2097152) ? 21 : // 覆盖最多二的21次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd4194304) ? 22 : // 覆盖最多二的22次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd8388608) ? 23 : // 覆盖最多二的23次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd16777216) ? 24 : // 覆盖最多二的24次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd33554432) ? 25 : // 覆盖最多二的25次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd67108864) ? 26 : // 覆盖最多二的26次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd134217728) ? 27 : // 覆盖最多二的27次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd268435456) ? 28 : // 覆盖最多二的28次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd536870912) ? 29 : // 覆盖最多二的29次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd1073741824) ? 30 : // 覆盖最多二的30次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd2147483648) ? 31 : // 覆盖最多二的31次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd4294967296) ? 32 : // 覆盖最多二的32次方个等待周期所需的位宽。
        (C_WAIT_CYCLES <= 64'd8589934592) ? 33 : // 覆盖最多二的33次方个等待周期所需的位宽。
        34; // 最小时钟周期一皮秒时等待周期仍小于二的三十四次方。
    localparam [C_TIMER_WIDTH-1:0] C_WAIT_LAST = C_WAIT_CYCLES[C_TIMER_WIDTH-1:0]-{{(C_TIMER_WIDTH-1){1'b0}}, 1'b1}; // 零基计数的最后等待周期。
    localparam [4:0] C_RESPONSE_LIMIT = C_RESPONSE_DEPTH[4:0]; // 固定五位观察能表示全部一至十六项配置。
    localparam [C_QUEUE_DEPTH-1:0] C_SCOPE_ONE = {{(C_QUEUE_DEPTH-1){1'b0}}, 1'b1}; // 队列写掩码的单个最低位。
    localparam [1:0] C_IDLE = 2'd0, C_NOOPS = 2'd1, C_REQUEST = 2'd2, C_WAIT = 2'd3; // 四种本地阶段全部具有明确有效含义。
    reg [1:0] sta_local; // 保存本地请求当前阶段而不占用远端响应所有权。
    reg [5:0] cnt_noops; // 只由真实NoOp提交递减的本轮排空余数。
    reg [C_TIMER_WIDTH-1:0] cnt_wait; // Request提交后从零开始的真实等待沿计数。
    reg reg_local_all; // 在固件接纳时冻结并在全部重试中保留请求范围。
    reg [4:0] cnt_response; // 记录尚未发出SUCCESS的远端请求条数。
    reg [C_QUEUE_DEPTH-1:0] reg_response_scope; // 最低位是队首且每条请求保存独立范围。
    reg reg_fault; // 过载或错误提交后保持禁用直到全局复位。
    wire flag_start, flag_success, flag_timeout; // 本地接纳成功或超时的原始同沿资格。
    wire flag_noop_take, flag_request_take, flag_reply_take; // 三类维护字在唯一提交边界的实际事件。
    wire flag_push, flag_overflow; // 远端请求入队与容量不足故障资格。
    wire [4:0] scope_index; // 考虑真实出队后新请求应占用的尾部位置。
    wire [C_QUEUE_DEPTH-1:0] scope_after_pop, scope_mask, scope_after_push; // 显式拆分队首移除和尾部范围写入。
    assign o_local_ready = i_rstn && !reg_fault && (sta_local == C_IDLE); // 远端队列不替代本地独立忙状态。
    assign flag_start = o_local_ready && i_local_request; // 固件只在真正ready时建立本轮所有权。
    assign flag_success = i_rstn && !reg_fault && (sta_local == C_WAIT) && i_rx_response && (i_rx_response_status == 3'd0); // 仅当前等待中的适用成功可完成本地请求。
    assign flag_timeout = i_rstn && !reg_fault && (sta_local == C_WAIT) && (cnt_wait == C_WAIT_LAST) && !flag_success; // 同沿SUCCESS优先于达到十毫秒终点。
    assign o_stream_reset = !i_rstn || reg_fault || flag_start || i_rx_request || (sta_local != C_IDLE) || (cnt_response != 5'd0); // 新请求即刻禁用且所有尚未完成的所有权共同保持复位。
    assign o_block_messages = !i_rstn || reg_fault || flag_start || flag_timeout || (sta_local == C_NOOPS) || (sta_local == C_REQUEST); // 仅全局故障和本地维护序列阻断普通消息。
    assign o_tx_pending = i_rstn && !reg_fault && !flag_start && !flag_timeout && ((sta_local == C_NOOPS) || (sta_local == C_REQUEST) || (cnt_response != 5'd0)); // 新本地请求和超时沿不能误提交旧响应。
    assign o_tx_kind = !o_tx_pending ? 2'd0 : (sta_local == C_NOOPS) ? 2'd1 : (sta_local == C_REQUEST) ? 2'd2 : 2'd3; // 对唯一发送边界明确当前维护消息来源。
    assign o_tx_word = !o_tx_pending ? 32'd0 : (sta_local == C_NOOPS) ? 32'd0 : (sta_local == C_REQUEST) ? {19'd0, reg_local_all, 12'h184} : {19'd0, reg_response_scope[0], 12'h1C4}; // 直接编码标准类型和范围且所有保留位清零。
    assign flag_noop_take = o_tx_pending && i_tx_take && (o_tx_kind == 2'd1); // 只有当前NoOp真正提交才减少排空余数。
    assign flag_request_take = o_tx_pending && i_tx_take && (o_tx_kind == 2'd2); // Request提交是十毫秒计时的唯一开始边界。
    assign flag_reply_take = o_tx_pending && i_tx_take && (o_tx_kind == 2'd3); // 真实响应提交恰好移除一个原队首请求。
    assign flag_overflow = i_rstn && !reg_fault && i_rx_request && (cnt_response == C_RESPONSE_LIMIT) && !flag_reply_take; // 满队列只允许借用本沿真实响应释放的槽位。
    assign o_error = i_rstn && !reg_fault && (flag_overflow || (i_tx_take && !o_tx_pending)); // 故障只作本地诊断而不制造保留Status响应。
    assign flag_push = i_rstn && !reg_fault && !o_error && i_rx_request; // 每个容量允许的远端请求均单独保留。
    assign scope_index = cnt_response-{4'd0, flag_reply_take}; // 新请求写入真实出队后的队尾索引。
    assign scope_after_pop = flag_reply_take ? (reg_response_scope >> 32'd1) : reg_response_scope; // 出队后原次项成为最低位队首。
    assign scope_mask = C_SCOPE_ONE << scope_index; // 使用固定宽度掩码只选择新请求的一个槽位。
    assign scope_after_push = (scope_after_pop & ~scope_mask) | ({C_QUEUE_DEPTH{i_rx_request_all}} & scope_mask); // 新请求不能覆盖其它仍有所有权的范围。
    assign o_waiting = i_rstn && !reg_fault && (sta_local == C_WAIT); // 暴露当前等待阶段而不提前宣称响应完成。
    assign o_noops_left = (i_rstn && !reg_fault && (sta_local == C_NOOPS)) ? cnt_noops : 6'd0; // 排空以外不暴露无效余数。
    assign o_response_count = (i_rstn && !reg_fault) ? cnt_response : 5'd0; // 故障或全局复位下屏蔽队列所有权观察。
    assign o_local_start = flag_start; // 精确反映固件valid和ready共同形成的接受事件。
    assign o_local_done = flag_success && !o_error; // 同沿故障不能被成功状态误标成正常完成。
    assign o_retry = flag_timeout && !o_error; // 故障优先于本地正常超时重试。
    assign o_reply_done = flag_reply_take; // 只把真实发送的队首响应报告为已完成。
    assign o_fault = i_rstn && reg_fault; // 已锁存故障在全局复位输入有效时立即屏蔽。
    generate // 非法配置必须在展开阶段明确失败。
        if ((C_CLOCK_PERIOD_PS < 1) || (C_CLOCK_PERIOD_PS > 1000000000) || (C_RESPONSE_DEPTH < 1) || (C_RESPONSE_DEPTH > 16)) begin : gen_invalid // 限制计时量化和有限响应存储的实现范围。
            dl_uart_reset_control_parameters_invalid Invalid_Inst (); // 未定义错误层次禁止非法参数被静默综合。
        end // 结束部署参数合法性条件。
    endgenerate // 结束复位控制参数校验。
    always @(posedge i_clk) begin // 同步保存本地阶段并明确全局故障最高优先级。
        if (!i_rstn || reg_fault || o_error) sta_local <= C_IDLE; // 故障后由独立故障位保持全部操作禁用。
        else if (flag_start || flag_timeout) sta_local <= C_NOOPS; // 新请求与重试均重新执行完整四十字序列。
        else if ((sta_local == C_NOOPS) && flag_noop_take && (cnt_noops == 6'd1)) sta_local <= C_REQUEST; // 第四十字完成后才允许Request成为队首。
        else if (flag_request_take) sta_local <= C_WAIT; // 真正发出Request之后才进入等待。
        else if (flag_success) sta_local <= C_IDLE; // 成功只释放本地阶段并保留远端队列。
    end // 结束本地四阶段寄存更新。
    always @(posedge i_clk) begin // 同步保存真实未发送的NoOp数量。
        if (!i_rstn || reg_fault || o_error) cnt_noops <= 6'd0; // 全局或故障清除旧排空计数。
        else if (flag_start || flag_timeout) cnt_noops <= 6'd40; // 每次尝试独立装入规范要求的四十字。
        else if (flag_noop_take) cnt_noops <= cnt_noops-6'd1; // 停顿和普通响应不减少NoOp数量。
    end // 结束NoOp计数寄存更新。
    always @(posedge i_clk) begin // 同步保存Request提交之后的真实周期数。
        if (!i_rstn || reg_fault || o_error || (sta_local != C_WAIT) || flag_success || flag_timeout) cnt_wait <= {C_TIMER_WIDTH{1'b0}}; // 只有完整等待阶段积累计时且终点不会回绕。
        else cnt_wait <= cnt_wait+{{(C_TIMER_WIDTH-1){1'b0}}, 1'b1}; // 每个真实时钟沿对应一个声明周期。
    end // 结束等待计时寄存更新。
    always @(posedge i_clk) begin // 独立保存本地固件请求的范围。
        if (!i_rstn || reg_fault || o_error) reg_local_all <= 1'b0; // 全局和故障取消本地旧范围。
        else if (flag_start) reg_local_all <= i_local_all; // 重试和远端请求均不覆盖该范围。
    end // 结束本地请求范围寄存更新。
    always @(posedge i_clk) begin // 同步保存每条待回复请求的有效数量。
        if (!i_rstn || reg_fault || o_error) cnt_response <= 5'd0; // 故障需要上层恢复而不继续发送部分旧响应。
        else cnt_response <= cnt_response+{4'd0, flag_push}-{4'd0, flag_reply_take}; // 同拍出入保持数量并保留新队尾。
    end // 结束远端请求计数寄存更新。
    always @(posedge i_clk) begin // 同步保存按到达顺序排列的全部响应范围。
        if (!i_rstn || reg_fault || o_error) reg_response_scope <= {C_QUEUE_DEPTH{1'b0}}; // 清除无效范围以方便故障后重新初始化。
        else if (flag_push) reg_response_scope <= scope_after_push; // 入队在真实出队后的尾部写入当前范围。
        else reg_response_scope <= scope_after_pop; // 只有真实响应提交才移动已有队列。
    end // 结束响应范围队列寄存更新。
    always @(posedge i_clk) begin // 粘滞故障具有唯一全局复位恢复条件。
        if (!i_rstn) reg_fault <= 1'b0; // 全局同步复位明确清除故障所有权。
        else if (o_error) reg_fault <= 1'b1; // 不允许SUCCESS或固件请求清除过载和错误提交。
    end // 结束粘滞故障寄存更新。
endmodule // 结束UART复位控制模块。
