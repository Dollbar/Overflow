// Receive-channel ownership properties over actual storage and return controllers.
// 日期 2026-09-08；宏 Q 任意化仅证明数量与交接，不证明 SRAM 内容或元数据顺序。
`timescale 1ps/1ps // 一个形式步骤表示共同 UPLI 时钟的一次采样。
module upli_receive_channel_properties #( // 顶层接收、逐账户退休及正常归还守恒检查模块。
    parameter integer C_NUM_PORTS = 1, // 本次实际展开的有效端口数量。
    parameter integer C_PAYLOAD_WIDTH = 8, // 数据保持实际宽度，性质不假定 payload 的值。
    parameter integer C_CREDIT_WIDTH = 4, // 静态容量及输出计数的统一位宽。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = 20'h50132, // 低位起逐端口四 VC 与共享池的精确容量。
    parameter integer C_RETURN_DEPTH = 4 // 正常退休队列的实际深度。
) ( // 环境不假设内部状态合法，也不屏蔽非法入站或消费者选择。
    input wire i_clk, // 全部 DUT 与历史寄存器使用共同上升沿。
    input wire i_rstn, // 任意同步复位可取消旧所有权。
    input wire i_credit_connected, // 返回方向资格允许任意变化，数量性质不依赖单调假设。
    input wire i_beats_connected, // 入站双向连接资格保持独立符号输入。
    input wire i_receive_valid, // 原生输入没有 ready，允许无容量的错误交易。
    input wire [1:0] i_receive_port, // 包含未启用端口的完整物理字段。
    input wire [1:0] i_receive_vc, // 原始虚拟通道字段。
    input wire i_receive_pool, // 区分专用 VC 与跨 VC 共享池账户。
    input wire [C_PAYLOAD_WIDTH-1:0] i_receive_payload, // 任意被写入 SRAM 的实际数据。
    input wire [1:0] i_consumer_port, // 本地消费端口可包含未启用编码。
    input wire [2:0] i_consumer_account, // 本地五个合法账户及三个非法编码。
    input wire i_consumer_ready, // 任意下游背压，不预设持续消费。
    output wire o_violation // 任一边界或所有权关系被破坏时置位。
); // 结束接收通道形式接口。
    localparam integer C_PENDING_WIDTH = (C_RETURN_DEPTH <= 1) ? 1 : (C_RETURN_DEPTH <= 3) ? 2 : (C_RETURN_DEPTH <= 7) ? 3 : (C_RETURN_DEPTH <= 15) ? 4 : 5; // 与实际返回队列计数形状一致。
    localparam [5:0] C_RETURN_LIMIT = C_RETURN_DEPTH[5:0]; // 独立检查算术可表示十六项队列及额外事件。
    localparam [31:0] C_SLOT_LIMIT = C_NUM_PORTS*5; // 明确有界的非负账户展开数量。
    wire [C_PAYLOAD_WIDTH-1:0] head_payload; // 真实被选择头的有效数据位。
    wire [1:0] head_vc; // 真实缓存头原 VC 字段，仅检查无效时清零。
    wire head_pool, head_valid, consume_valid, accepted; // 实际消费资格和注册接纳事件。
    wire [2:0] diagnostic; // 实际注册本地输入拒绝编码。
    wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] counts, unread, read_addr; // 真实总占用、后端未读数量及循环读地址。
    wire [C_NUM_PORTS*25-1:0] read_bank; // 各外部映射真实保存的读 bank，零扩展为五位。
    wire [C_NUM_PORTS*5-1:0] pending, account_bad, selected_valid; // 真实在途读与逐账户性质归约。
    wire [C_NUM_PORTS*10-1:0] cached; // 每账户两个输出缓存的真实有效数量。
    wire [4*C_PENDING_WIDTH-1:0] returns; // 真实尚未注册发布的退休记录数。
    wire [3:0] valid, pool, done, initial_valid, normal_valid, port_bad; // 实际原生输出与两个注册发布源的观察。
    wire [7:0] vcs, nums, normal_num; // 真实合并输出和正常批次数量编码。
    wire [C_NUM_PORTS*3-1:0] stages; // 真实初始发布阶段，完成状态关系也作为被证明性质。
    reg [C_NUM_PORTS*5-1:0] previous_writes; // 独立按沿前容量与输入资格记录合法写入。
    reg [3:0] previous_done; // 用于证明初始完成只能被复位撤销。
    reg previous_credit, previous_reset; // 前一沿返回预约及同步复位的独立历史。
    wire selected_space; // 从实际逐端口队列数量独立检查消费空间。
    genvar gen_slot, gen_port; // 常量展开全部账户及四个原生端口。
    upli_receive_channel Channel_Inst ( // 使用脚本已参数化并仅增加观察端口的真实 DUT。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_credit_connected(i_credit_connected), .i_beats_connected(i_beats_connected), // 原始连接与复位控制不作替换。
        .i_receive_valid(i_receive_valid), .i_receive_port(i_receive_port), .i_receive_vc(i_receive_vc), .i_receive_pool(i_receive_pool), .i_receive_payload(i_receive_payload), // 完整原生输入保持符号化。
        .i_consumer_port(i_consumer_port), .i_consumer_account(i_consumer_account), .i_consumer_ready(i_consumer_ready), // 本地调度不被预设为合法选择。
        .o_head_payload(head_payload), .o_head_vc(head_vc), .o_head_pool(head_pool), .o_head_valid(head_valid), .o_consume_valid(consume_valid), // 直接观察真实消费接口。
        .o_receive_accepted(accepted), .o_diagnostic(diagnostic), .o_counts(counts), .o_pending_count(returns), // 真实所有权数量而非模型替身。
        .o_credit_valid(valid), .o_credit_pool(pool), .o_credit_vc(vcs), .o_credit_num(nums), .o_credit_init_done(done), // 注册返回总线及完成状态。
        .o_formal_unread(unread), .o_formal_pending(pending), .o_formal_cached(cached), // 控制器真实寄存器保持原驱动，只增加可见性。
        .o_formal_read_addr(read_addr), .o_formal_bank(read_bank), // 保留真实未复位 bank，只有在途读时证明其范围。
        .o_formal_stages(stages), // 不假设完成时阶段合法，而是观察实际寄存器证明。
        .o_formal_initial_valid(initial_valid), .o_formal_normal_valid(normal_valid), .o_formal_normal_num(normal_num) // 观察两源发布资格以验证合并边界。
    ); // 结束接收通道原始状态实例。
    assign selected_space = ({{(6-C_PENDING_WIDTH){1'b0}}, returns[i_consumer_port*C_PENDING_WIDTH +: C_PENDING_WIDTH]} < C_RETURN_LIMIT); // 动态索引始终落在固定四端口总线上，检查域显式零扩展。
    always @(posedge i_clk) begin // 保存真实完成状态以证明粘滞性与旧初始化资格。
        if (!i_rstn) previous_done <= 4'd0; // 同步复位取消前一沿的完成承诺。
        else previous_done <= done; // 不依据当前连接组合预测完成。
    end // 结束完成状态历史寄存器。
    always @(posedge i_clk) begin // 记录生成当前注册信用所用的返回连接资格。
        if (!i_rstn) previous_credit <= 1'b0; // 复位沿不预约新的信用发布。
        else previous_credit <= i_credit_connected; // 后续输入撤销不取消已注册输出。
    end // 结束返回方向资格历史寄存器。
    always @(posedge i_clk) begin // 标记紧接同步复位的状态，覆盖运行中重新复位。
        previous_reset <= !i_rstn; // 任意复位沿后检查所有可见有效性已清零。
    end // 结束独立同步复位历史寄存器。
    generate // 每个真实账户分别检查，不允许不同账户的正负误差抵消。
        for (gen_slot = 32'd0; gen_slot < C_SLOT_LIMIT; gen_slot = gen_slot+32'd1) begin : gen_accounts // 包含零容量账户而非仅存在的宏。
            localparam integer C_PORT_INDEX = gen_slot/5, C_ACCOUNT_INDEX = gen_slot%5; // 静态提取账户所属端口和类型。
            localparam [1:0] C_PORT = C_PORT_INDEX[1:0]; // 入站与消费者端口比较的双位常量。
            localparam [2:0] C_ACCOUNT = C_ACCOUNT_INDEX[2:0]; // 四个专用 VC 或共享池的三位编码。
            localparam [17:0] C_LIMIT = {{(18-C_CREDIT_WIDTH){1'b0}}, C_CAPACITIES[gen_slot*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // 扩展静态容量避免检查加法溢出。
            localparam [17:0] C_BANK_LIMIT = (C_LIMIT <= 18'd2048) ? 18'd1 : ((C_LIMIT+18'd2047)/18'd2048); // 固定宏映射深度超过二千零四十八才增加 bank。
            wire [17:0] count_wide, unread_wide, cached_wide, address_wide; // 独立十八位检查域覆盖最大容量。
            wire receive_match, consume_match; // 从外部字段独立译码此账户。
            wire bad_capacity, bad_reservation, bad_transfer, bad_address; // 分组所有权性质便于审查和反例定位。
            reg [17:0] previous_count; // 仅记录前一沿的实际总占用。
            reg previous_retire; // 仅记录实际消费者握手，不观察内部释放信号。
            assign count_wide = {{(18-C_CREDIT_WIDTH){1'b0}}, counts[gen_slot*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // 对实际输出数量零扩展。
            assign unread_wide = {{(18-C_CREDIT_WIDTH){1'b0}}, unread[gen_slot*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // 对实际未读数量零扩展。
            assign cached_wide = {16'd0, cached[gen_slot*2 +: 2]}; // 双输出缓存有效数量独立扩展。
            assign address_wide = {{(18-C_CREDIT_WIDTH){1'b0}}, read_addr[gen_slot*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // 真实循环读指针用于证明发出的地址不会越界。
            assign receive_match = (i_receive_port == C_PORT) && (i_receive_pool ? (C_ACCOUNT == 3'd4) : (C_ACCOUNT == {1'b0, i_receive_vc})); // 原 VC 和池选择不通过 DUT 译码线重用。
            assign consume_match = (i_consumer_port == C_PORT) && (i_consumer_account == C_ACCOUNT); // 非法字段没有任何账户命中。
            assign selected_valid[gen_slot] = consume_match && (cached_wide != 18'd0); // 从真实缓存有效状态独立重建可见性。
            always @(posedge i_clk) begin // 保存旧占用以检查下一沿加减事件。
                if (!i_rstn) previous_count <= 18'd0; // 复位后旧所有权不参与正常守恒。
                else previous_count <= count_wide; // 保持观察而不是复制 DUT 的计数更新实现。
            end // 结束本账户数量历史寄存器。
            always @(posedge i_clk) begin // 独立预测原生输入是否应被此账户接受。
                if (!i_rstn) previous_writes[gen_slot] <= 1'b0; // 复位优先，不允许输入产生新所有权。
                else previous_writes[gen_slot] <= i_receive_valid && receive_match && i_credit_connected && i_beats_connected && done[C_PORT_INDEX] && (count_wide < C_LIMIT); // 使用沿前容量，满状态不能借用同拍消费。
            end // 结束本账户合法接收事件寄存器。
            always @(posedge i_clk) begin // 外部真实消费握手必须对应恰好一个账户的释放。
                if (!i_rstn) previous_retire <= 1'b0; // 复位沿终止而非正常退休旧 payload。
                else previous_retire <= consume_valid && i_consumer_ready && consume_match; // 不重用内部 FIFO 读使能构造期望。
            end // 结束本账户消费事件历史寄存器。
            assign bad_capacity = (count_wide > C_LIMIT) || (unread_wide > C_LIMIT); // 总容量与后端容量都不能超出静态资源。
            assign bad_reservation = (count_wide != unread_wide+cached_wide+{17'd0, pending[gen_slot]}) || (cached_wide+{17'd0, pending[gen_slot]} > 18'd2); // 在途和缓存均属于总所有权并共享两个输出预约。
            assign bad_transfer = (previous_count+{17'd0, previous_writes[gen_slot]}) != (count_wide+{17'd0, previous_retire}); // 账户变化必须精确等于独立输入判断减真实消费事件。
            assign bad_address = ((C_LIMIT != 18'd0) && (address_wide >= C_LIMIT)) || (pending[gen_slot] && ({13'd0, read_bank[gen_slot*5 +: 5]} >= C_BANK_LIMIT)); // 证明读指针及在途 bank 合法，不假设未复位空闲 bank 的值。
            assign account_bad[gen_slot] = bad_capacity || bad_reservation || bad_transfer || bad_address; // 四组关系全部参与归纳而非变成环境假设。
        end // 结束全部账户的独立资源证明。
        for (gen_port = 32'd0; gen_port < 32'd4; gen_port = gen_port+32'd1) begin : gen_ports // 未启用端口也须证明完全无输出。
            localparam [1:0] C_PORT = gen_port; // 当前正常退休归属端口的固定编码。
            wire [5:0] return_count, returned; // 六位检查域避免队列边界回绕。
            reg [5:0] previous_returns; // 前一沿真实尚未发布的退休记录数。
            reg previous_retire; // 前一沿向本端口承诺的真实消费者事件。
            assign return_count = {{(6-C_PENDING_WIDTH){1'b0}}, returns[gen_port*C_PENDING_WIDTH +: C_PENDING_WIDTH]}; // 当前真实正常队列数量。
            assign returned = normal_valid[gen_port] ? ({4'd0, normal_num[gen_port*2 +: 2]}+6'd1) : 6'd0; // 从真实注册返回独立解码一至四项。
            always @(posedge i_clk) begin // 保留正常归还前的真实所有权数量。
                if (!i_rstn) previous_returns <= 6'd0; // 复位不把取消的记录伪装成归还信用。
                else previous_returns <= return_count; // 当前发布批次在下一状态比较中计入消耗。
            end // 结束返回队列数量历史寄存器。
            always @(posedge i_clk) begin // 只用实际消费端的握手记账。
                if (!i_rstn) previous_retire <= 1'b0; // 复位期间不存在合法退休事件。
                else previous_retire <= consume_valid && i_consumer_ready && (i_consumer_port == C_PORT); // 元数据入队若遗漏会违反下一沿守恒。
            end // 结束返回所有权来源历史寄存器。
            if (gen_port < C_NUM_PORTS) begin : gen_active // 检查有效端口正常队列和注册交接。
                wire bad_capacity, bad_transfer, bad_handoff, bad_output, bad_stage; // 按资源、交接、输出和状态分组反例。
                assign bad_capacity = (return_count > C_RETURN_LIMIT) || (returned > previous_returns); // 不允许溢出队列或借本沿新记录发布信用。
                assign bad_transfer = (previous_returns+{5'd0, previous_retire}) != (return_count+returned); // 每个真实消费都必须成为记录或已注册的正常信用。
                assign bad_handoff = (normal_valid[gen_port] && (!previous_done[gen_port] || !previous_credit)) || (initial_valid[gen_port] && done[gen_port]) || (previous_done[gen_port] && !done[gen_port]) || (initial_valid[gen_port] && normal_valid[gen_port]); // 使用旧逐端口资格且初始与正常发布绝不重叠。
                assign bad_output = (valid[gen_port] != (initial_valid[gen_port] || normal_valid[gen_port])) || (normal_valid[gen_port] && (nums[gen_port*2 +: 2] != normal_num[gen_port*2 +: 2])) || (!valid[gen_port] && (pool[gen_port] || (vcs[gen_port*2 +: 2] != 2'd0) || (nums[gen_port*2 +: 2] != 2'd0))); // 输出合并不能丢有效或数量，无效周期元数据清零。
                assign bad_stage = (stages[gen_port*3 +: 3] > 3'd5) || (done[gen_port] && (stages[gen_port*3 +: 3] != 3'd5)); // 完成只属于最终阶段，此关系本身必须被证明。
                assign port_bad[gen_port] = bad_capacity || bad_transfer || bad_handoff || bad_output || bad_stage; // 全部端口性质共同参与证明。
            end else begin : gen_unused // 未使用端口不能产生信用或别名所有权。
                assign port_bad[gen_port] = (return_count != 6'd0) || valid[gen_port] || pool[gen_port] || done[gen_port] || initial_valid[gen_port] || normal_valid[gen_port] || (vcs[gen_port*2 +: 2] != 2'd0) || (nums[gen_port*2 +: 2] != 2'd0); // 固定四端口形状的未启用部分必须保持零。
            end // 结束有效和未用端口的性质选择。
        end // 结束四端口正常归还所有权检查。
    endgenerate // 结束逐账户及逐端口的独立检查结构。
    assign o_violation = (|account_bad) || (|port_bad) || (accepted != (|previous_writes)) || (accepted && (diagnostic != 3'd0)) || (head_valid != (|selected_valid)) || (consume_valid != (i_rstn && head_valid && selected_space)) || (!head_valid && ((head_payload != {C_PAYLOAD_WIDTH{1'b0}}) || (head_vc != 2'd0) || head_pool)) || (previous_reset && ((|counts) || (|returns) || (|valid) || (|done) || head_valid || accepted || (diagnostic != 3'd0))); // 任一真实接口与数量不一致即失败，复位之后旧缓存无可见资格。
endmodule // 结束 upli_receive_channel_properties 顶层资源所有权模块。
