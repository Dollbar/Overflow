// UPLI per-channel ordered receive wrapper over the existing per-account SRAM and credit owner. // 保留每端口跨 VC/Pool 的实际接纳顺序而不重复实现信用。
// 日期 2026-09-11；Common 2.0 接收微架构辅助层，不解释 payload、Parity、Drop 或事务语义。 // 四种 Native channel 应分别实例化以避免跨通道队头阻塞。
`timescale 1ps/1ps // 本层与被包装的接收存储共享同一 UPLI 时钟域且不使用延时。
module upli_ordered_receive_channel #( // 消费者只选择物理端口，内部顺序队列选择该端口最早接纳的真实账户。
    parameter integer C_NUM_PORTS = 1, // 原生 station 配置允许一、二或四端口。
    parameter integer C_PAYLOAD_WIDTH = 32, // payload 由实际 receive_channel 原样保存。
    parameter integer C_CREDIT_WIDTH = 4, // 每账户逻辑容量计数为三至十六位。
    parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY = 3, // 未覆盖逐账户容量时使用统一默认值。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = {C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 每端口依次排列 VC0..3 和共享池容量。
    parameter integer C_RETURN_DEPTH = 4, // 正常信用元数据队列深度直接交给被包装组件。
    parameter integer C_PENDING_WIDTH = (C_RETURN_DEPTH <= 1) ? 1 : (C_RETURN_DEPTH <= 3) ? 2 : (C_RETURN_DEPTH <= 7) ? 3 : (C_RETURN_DEPTH <= 15) ? 4 : 5, // 返回观察宽度保持与 receive_channel 一致。
    parameter integer C_ORDER_COUNT_WIDTH = C_CREDIT_WIDTH+3 // 五账户容量之和最多需要账户宽度再加三位。
) ( // 原生接收接口与只按 port 选择的本地消费接口明确分离。
    input wire i_clk, // 顺序元数据、SRAM 和信用归还共用上升沿时钟。
    input wire i_rstn, // 同步低有效复位优先取消所有可见所有权。
    input wire i_credit_connected, // 对应通道信用返回方向已经建立。
    input wire i_beats_connected, // 双向连接均建立后才允许接纳 beat。
    input wire i_receive_valid, // 原生 UPLI 本沿有一个 beat且没有 ready 反压。
    input wire [1:0] i_receive_port, // 入站 beat 的物理 port。
    input wire [1:0] i_receive_vc, // 入站 beat 的原始 VC。
    input wire i_receive_pool, // 入站 beat 使用专用 VC 账户或共享池账户。
    input wire [C_PAYLOAD_WIDTH-1:0] i_receive_payload, // 不透明通道 payload。
    input wire [1:0] i_consumer_port, // 本地调度器只选择要消费的物理 port。
    input wire i_consumer_ready, // 本地消费者愿意原子接纳当前顺序头。
    output wire [C_PAYLOAD_WIDTH-1:0] o_head_payload, // 所选 port 最早实际接纳 beat 的缓存 payload。
    output wire [1:0] o_head_vc, // 与真实 payload 一同保存的原始 VC。
    output wire o_head_pool, // 与真实 payload 一同保存的原始 Pool 位。
    output wire [2:0] o_head_account, // 当前顺序头账户，零至三为 VC、四为共享池，无效时为零。
    output wire o_head_valid, // 顺序头对应的实际 SRAM 数据已经可见。
    output wire o_consume_valid, // 顺序头和信用返回空间同时可用，配合 ready 才退休。
    output wire o_receive_accepted, // 上一采样沿实际写入 SRAM 的诊断事件。
    output wire [2:0] o_diagnostic, // 被包装接收组件保存的上一沿输入诊断。
    output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_counts, // 每账户实际占用数直接来自唯一存储所有者。
    output wire [4*C_PENDING_WIDTH-1:0] o_pending_count, // 每端口待发布退休信用数直接来自唯一返回队列。
    output wire [C_NUM_PORTS*C_ORDER_COUNT_WIDTH-1:0] o_order_counts, // 每端口已经进入顺序 journal 的事件数，不含一个注册 accepted 在途事件。
    output wire [C_NUM_PORTS-1:0] o_order_error, // 当拍本地 journal 容量或保存账户一致性错误，不是协议 RAS 编码。
    output wire [C_NUM_PORTS-1:0] o_order_error_sticky, // 本地一致性错误保持至共同复位。
    output wire [3:0] o_credit_valid, // 初始或正常信用返回有效信号。
    output wire [3:0] o_credit_pool, // 当前信用返回的真实 Pool 位。
    output wire [7:0] o_credit_vc, // 当前信用返回的原始 VC。
    output wire [7:0] o_credit_num, // 当前批次信用数量减一编码。
    output wire [3:0] o_credit_init_done // 各 port 初始信用发布完成状态。
); // 结束有序接收封装的参数和端口声明。
    wire [C_PAYLOAD_WIDTH-1:0] child_head_payload; // 实际 SRAM 所选账户的 payload 头。
    wire [1:0] child_head_vc; // 实际 SRAM 字中保存的原始 VC。
    wire child_head_pool, child_head_valid, child_consume_valid; // 实际 SRAM 头状态和原子退休资格。
    wire child_receive_accepted; // receive_channel 注册的上一沿实际写入事件。
    wire [2:0] child_diagnostic; // receive_channel 注册的上一沿输入诊断。
    wire [C_NUM_PORTS*3-1:0] order_head_accounts; // 所有 port 当前 journal 头账户的扁平观察总线。
    wire [C_NUM_PORTS-1:0] order_head_valid; // 各 port 是否已有可消费的顺序事件。
    wire selected_head_consistent; // journal账户必须与实际SRAM保存的VC/Pool类别一致才允许公开或退休。
    reg [2:0] selected_account; // 当前 consumer port 对应的最早账户。
    reg selected_order_valid; // 当前 consumer port 是否命中一个真实 journal 头。
    reg [1:0] reg_receive_port; // 与下一周期 child_receive_accepted 对齐的接纳沿 port 快照。
    reg [2:0] reg_receive_account; // 与下一周期 child_receive_accepted 对齐的接纳沿账户快照。
    integer select_index; // 静态端口归约循环索引。
    genvar gen_port; // 为每个真实 port 建立容量精确的独立顺序 journal。
    assign o_head_payload = child_head_payload; // payload 始终来自既有真实 SRAM 数据路径。
    assign o_head_vc = child_head_vc; // VC 始终来自既有真实 SRAM 保存字。
    assign o_head_pool = child_head_pool; // Pool 始终来自既有真实 SRAM 保存字。
    assign o_head_account = selected_order_valid ? selected_account : 3'd0; // 无顺序头时调试账户输出确定为零。
    assign selected_head_consistent = !child_head_valid || ((selected_account == 3'd4) ? child_head_pool : ((selected_account < 3'd4) && !child_head_pool && (child_head_vc == selected_account[1:0]))); // Pool账户允许任意原VC，专用账户必须精确匹配VC。
    assign o_head_valid = child_head_valid && selected_order_valid && selected_head_consistent; // journal、真实SRAM头和保存类别必须同时一致才公开。
    assign o_consume_valid = child_consume_valid && selected_order_valid && selected_head_consistent; // 元数据异常不能表现为成功消费或触发底层退休。
    assign o_receive_accepted = child_receive_accepted; // 不改变既有注册接纳诊断的时序。
    assign o_diagnostic = child_diagnostic; // 不改变既有输入拒绝原因编码。
    always @(*) begin // 按 consumer port 选择一份独立 journal 头，不轮询 VC 或 Pool。
        selected_account = 3'd7; // 无效账户确保未命中时底层不会误选真实 FIFO。
        selected_order_valid = 1'b0; // 非法或空 port 默认没有可消费顺序头。
        for (select_index = 32'd0; select_index < C_NUM_PORTS; select_index = select_index+32'd1) begin // 配置端口数是常量且最多四个。
            if (i_consumer_port == select_index[1:0]) begin // 仅一个实际 port 可以命中。
                selected_account = order_head_accounts[select_index*3 +: 3]; // 账户来自该 port 最早实际接纳事件。
                selected_order_valid = order_head_valid[select_index]; // 空 journal 不向底层发出消费 ready。
            end // 结束当前 port 的唯一选择。
        end // 结束所有配置端口的组合选择。
    end // 结束 journal 头多路选择。
    always @(posedge i_clk) begin // 保存原生输入沿元信息以匹配 receive_channel 的注册 accepted 输出。
        if (!i_rstn) begin // 共同复位清除尚未形成有效 accepted 的元信息。
            reg_receive_port <= 2'd0; // 复位值不指代旧 port 所有权。
            reg_receive_account <= 3'd0; // 复位值不指代旧账户所有权。
        end else if (i_receive_valid) begin // 只有实际候选沿需要刷新对齐快照。
            reg_receive_port <= i_receive_port; // 下一沿 child accepted 使用本沿 port，而不是变化后的输入。
            reg_receive_account <= i_receive_pool ? 3'd4 : {1'b0, i_receive_vc}; // Pool 保存为账户四且不丢失真实 VC 数据字。
        end // 结束有效输入快照更新。
    end // 结束 accepted 元信息流水寄存。
    generate // 每个 port 的 journal 深度等于该 port 五个已发放账户容量总和。
        if ((C_NUM_PORTS != 1) && (C_NUM_PORTS != 2) && (C_NUM_PORTS != 4)) begin : gen_invalid_ports // 非法端口数不得被静默截断。
            upli_ordered_receive_channel_ports_invalid Invalid_Ports_Inst (); // 未定义层次使非法配置在 elaboration 明确失败。
        end // 结束端口参数保护。
        if (C_ORDER_COUNT_WIDTH != (C_CREDIT_WIDTH+3)) begin : gen_invalid_count_width // 派生观察宽度不可独立缩小或改变。
            upli_ordered_receive_channel_count_width_invalid Invalid_Count_Width_Inst (); // 未定义层次拒绝不一致接口宽度。
        end // 结束观察宽度参数保护。
        for (gen_port = 32'd0; gen_port < C_NUM_PORTS; gen_port = gen_port+32'd1) begin : gen_order_ports // 四通道实例内部每个 port 各自前进。
            localparam [1:0] C_PORT = gen_port[1:0]; // 端口常量显式收窄到原生两位字段。
            localparam [31:0] C_CAPACITY_0 = {{(32-C_CREDIT_WIDTH){1'b0}}, C_CAPACITIES[(gen_port*5+0)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // VC0容量先零扩展到整数加法宽度。
            localparam [31:0] C_CAPACITY_1 = {{(32-C_CREDIT_WIDTH){1'b0}}, C_CAPACITIES[(gen_port*5+1)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // VC1容量先零扩展到整数加法宽度。
            localparam [31:0] C_CAPACITY_2 = {{(32-C_CREDIT_WIDTH){1'b0}}, C_CAPACITIES[(gen_port*5+2)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // VC2容量先零扩展到整数加法宽度。
            localparam [31:0] C_CAPACITY_3 = {{(32-C_CREDIT_WIDTH){1'b0}}, C_CAPACITIES[(gen_port*5+3)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // VC3容量先零扩展到整数加法宽度。
            localparam [31:0] C_CAPACITY_4 = {{(32-C_CREDIT_WIDTH){1'b0}}, C_CAPACITIES[(gen_port*5+4)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // 共享池容量先零扩展到整数加法宽度。
            localparam integer C_DEPTH = C_CAPACITY_0+C_CAPACITY_1+C_CAPACITY_2+C_CAPACITY_3+C_CAPACITY_4; // journal 精确覆盖本 port 五账户可同时占用总量。
            wire flag_push_request; // 注册 accepted 指向本 port 时必须把保存账户写入 journal。
            wire flag_pop; // 真实底层退休与 journal 出队必须发生在同一沿。
            wire flag_metadata_error; // accepted 快照账户超出零至四说明内部时序或状态损坏。
            wire flag_head_error; // journal 账户必须与真实 SRAM 保存的 VC/Pool 类别一致。
            assign flag_push_request = child_receive_accepted && (reg_receive_port == C_PORT); // accepted 使用上一输入沿快照而非当前总线。
            assign flag_pop = child_consume_valid && selected_order_valid && selected_head_consistent && i_consumer_ready && (i_consumer_port == C_PORT); // 只在保存类别一致时与唯一真实 SRAM 退休事件完全相同。
            assign flag_metadata_error = flag_push_request && (reg_receive_account > 3'd4); // 正常 receive_channel 不可能接纳非法账户。
            assign flag_head_error = selected_order_valid && child_head_valid && !selected_head_consistent && (i_consumer_port == C_PORT); // 错配头保持原SRAM和journal所有权并请求外层处置。
            if (C_DEPTH > 0) begin : gen_order_storage // 非零总容量 port 获得与信用总量相同深度的顺序队列。
                localparam integer C_LOCAL_COUNT_WIDTH = (C_DEPTH < 2) ? 1 : (C_DEPTH < 4) ? 2 : (C_DEPTH < 8) ? 3 : (C_DEPTH < 16) ? 4 : (C_DEPTH < 32) ? 5 : (C_DEPTH < 64) ? 6 : (C_DEPTH < 128) ? 7 : (C_DEPTH < 256) ? 8 : (C_DEPTH < 512) ? 9 : (C_DEPTH < 1024) ? 10 : (C_DEPTH < 2048) ? 11 : (C_DEPTH < 4096) ? 12 : (C_DEPTH < 8192) ? 13 : (C_DEPTH < 16384) ? 14 : (C_DEPTH < 32768) ? 15 : (C_DEPTH < 65536) ? 16 : (C_DEPTH < 131072) ? 17 : (C_DEPTH < 262144) ? 18 : 19; // 计数和指针足以表示完整五账户总量。
                localparam [C_LOCAL_COUNT_WIDTH-1:0] C_DEPTH_VALUE = C_DEPTH[C_LOCAL_COUNT_WIDTH-1:0]; // 容量比较显式匹配本地计数宽度。
                reg [2:0] order_memory [0:C_DEPTH-1]; // 每项只保存底层账户选择，payload和原VC仍由实际SRAM保存。
                reg [C_LOCAL_COUNT_WIDTH-1:0] reg_write_pointer, reg_read_pointer; // 非二次幂深度使用显式末地址回绕。
                reg [C_LOCAL_COUNT_WIDTH-1:0] reg_count; // journal 中已经可选择的事件数。
                reg reg_error_sticky; // 本 port 容量或元数据一致性错误保持至复位。
                wire flag_full, flag_empty, flag_push, flag_capacity_error; // journal 沿前状态与合法更新事件。
                assign flag_full = (reg_count == C_DEPTH_VALUE); // 深度来自真实总信用，不允许隐藏额外占用。
                assign flag_empty = (reg_count == {C_LOCAL_COUNT_WIDTH{1'b0}}); // 空 journal 不向底层选择任何账户。
                assign flag_push = flag_push_request && !flag_metadata_error && !flag_full; // 异常满状态不覆写尚未退休的顺序项。
                assign flag_capacity_error = flag_push_request && flag_full; // 合法信用闭环中 count 加 accepted 在途不会超过深度。
                assign order_head_accounts[gen_port*3 +: 3] = flag_empty ? 3'd0 : order_memory[reg_read_pointer]; // 当前最早账户使用异步小型元数据读。
                assign order_head_valid[gen_port] = !flag_empty; // 仅真实已入 journal 的 accepted 可被消费。
                assign o_order_counts[gen_port*C_ORDER_COUNT_WIDTH +: C_ORDER_COUNT_WIDTH] = {{(C_ORDER_COUNT_WIDTH-C_LOCAL_COUNT_WIDTH){1'b0}}, reg_count}; // 观察总线只零扩展实际最小计数。
                assign o_order_error[gen_port] = flag_capacity_error || flag_metadata_error || flag_head_error; // 本地故障不自动改变协议隔离状态。
                assign o_order_error_sticky[gen_port] = reg_error_sticky; // 保持诊断由本 port 状态唯一驱动。
                always @(posedge i_clk) begin // journal 写入、退休和计数在同一实际时钟沿原子更新。
                    if (!i_rstn) begin // 同步复位取消所有旧 epoch 的顺序所有权。
                        reg_write_pointer <= {C_LOCAL_COUNT_WIDTH{1'b0}}; // 新 epoch 从首项写入。
                        reg_read_pointer <= {C_LOCAL_COUNT_WIDTH{1'b0}}; // 新 epoch 从首项读取。
                        reg_count <= {C_LOCAL_COUNT_WIDTH{1'b0}}; // 复位后没有已接纳顺序事件。
                        reg_error_sticky <= 1'b0; // 复位清除本地一致性历史。
                    end else begin // 正常沿按独立 push/pop 事件推进。
                        if (flag_push) begin // 只有真实 registered accepted 获得一个 journal 项。
                            order_memory[reg_write_pointer] <= reg_receive_account; // 保存接纳沿账户而非下一候选字段。
                            if (reg_write_pointer == (C_DEPTH_VALUE-1'b1)) reg_write_pointer <= {C_LOCAL_COUNT_WIDTH{1'b0}}; // 非二次幂末项精确回绕。
                            else reg_write_pointer <= reg_write_pointer+1'b1; // 其他写入推进到下一项。
                        end // 结束一次合法 journal 入队。
                        if (flag_pop) begin // 真实 SRAM 退休同步移除唯一对应顺序头。
                            if (reg_read_pointer == (C_DEPTH_VALUE-1'b1)) reg_read_pointer <= {C_LOCAL_COUNT_WIDTH{1'b0}}; // 非二次幂末项精确回绕。
                            else reg_read_pointer <= reg_read_pointer+1'b1; // 其他退休推进到下一项。
                        end // 结束一次合法 journal 出队。
                        case ({flag_push, flag_pop}) // 同拍入队和退休保持总数不变。
                            2'b10: reg_count <= reg_count+1'b1; // 只有接纳登记时增加一个可选择事件。
                            2'b01: reg_count <= reg_count-1'b1; // 只有真实退休时减少一个事件。
                            default: reg_count <= reg_count; // 同拍二者或均无事件时保持总数。
                        endcase // 结束 journal 数量更新。
                        if (flag_capacity_error || flag_metadata_error || flag_head_error) reg_error_sticky <= 1'b1; // 任一本地一致性错误保持到复位。
                    end // 结束正常沿状态更新。
                end // 结束本 port journal 时序状态。
            end else begin : gen_no_order_storage // 全零容量 port 不生成虚假 journal 或信用。
                reg reg_error_sticky; // 即使故障注入制造不可能的接纳，诊断仍保持到复位。
                assign order_head_accounts[gen_port*3 +: 3] = 3'd0; // 无资源 port 没有账户头。
                assign order_head_valid[gen_port] = 1'b0; // 无资源 port 永远不能消费。
                assign o_order_counts[gen_port*C_ORDER_COUNT_WIDTH +: C_ORDER_COUNT_WIDTH] = {C_ORDER_COUNT_WIDTH{1'b0}}; // 无资源 port 占用恒零。
                assign o_order_error[gen_port] = flag_push_request || flag_metadata_error || flag_head_error; // 若底层异常接纳零容量 port则立即报告。
                assign o_order_error_sticky[gen_port] = reg_error_sticky; // 异常事件保持语义与非零容量 port 一致。
                always @(posedge i_clk) begin // 零容量 port 只保存本地异常历史，不分配顺序数据存储。
                    if (!i_rstn) reg_error_sticky <= 1'b0; // 共同复位清除异常历史。
                    else if (flag_push_request || flag_metadata_error || flag_head_error) reg_error_sticky <= 1'b1; // 任一不可能事件保持到复位。
                end // 结束零容量 port 的异常历史寄存。
            end // 结束有无 journal 存储分支。
        end // 结束所有配置 port 的独立顺序状态。
    endgenerate // 结束容量派生 journal 结构。
    upli_receive_channel #( // 唯一存储、初始信用和正常信用归还仍由已验证组件拥有。
        .C_NUM_PORTS(C_NUM_PORTS), .C_PAYLOAD_WIDTH(C_PAYLOAD_WIDTH), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), .C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY), .C_CAPACITIES(C_CAPACITIES), .C_RETURN_DEPTH(C_RETURN_DEPTH), .C_PENDING_WIDTH(C_PENDING_WIDTH) // 全部容量和观察参数原样传递。
    ) Receive_Inst ( // journal 只提供实际最早账户选择而不复制任何 payload FIFO。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_credit_connected(i_credit_connected), .i_beats_connected(i_beats_connected), // 连接与复位语义不改变。
        .i_receive_valid(i_receive_valid), .i_receive_port(i_receive_port), .i_receive_vc(i_receive_vc), .i_receive_pool(i_receive_pool), .i_receive_payload(i_receive_payload), // 原生 beat 直接进入唯一实际 SRAM。
        .i_consumer_port(i_consumer_port), .i_consumer_account(selected_account), .i_consumer_ready(i_consumer_ready && selected_order_valid && selected_head_consistent), // 只在journal有头且保存类别一致时允许底层原子退休。
        .o_head_payload(child_head_payload), .o_head_vc(child_head_vc), .o_head_pool(child_head_pool), .o_head_valid(child_head_valid), .o_consume_valid(child_consume_valid), // 真实缓存头和退休资格返回本层。
        .o_receive_accepted(child_receive_accepted), .o_diagnostic(child_diagnostic), .o_counts(o_counts), .o_pending_count(o_pending_count), // 注册诊断及占用观察直接透传。
        .o_credit_valid(o_credit_valid), .o_credit_pool(o_credit_pool), .o_credit_vc(o_credit_vc), .o_credit_num(o_credit_num), .o_credit_init_done(o_credit_init_done) // 所有信用均由唯一底层组件产生。
    ); // 结束实际接收存储组件实例。
endmodule // 结束 UPLI 跨账户有序接收封装。
