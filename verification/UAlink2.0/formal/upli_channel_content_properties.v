// Native receive-to-SRAM-to-retirement-to-credit metadata content properties.
// 日期2026-09-08；实际memory不抽象，期望字来自原生输入而非DUT写入/退休线。
`timescale 1ps/1ps // 一个形式步骤推进全部实际UPLI和SRAM共同上升沿。
module upli_channel_content_properties #( // 有限账户端到端完整字及正常归还内容关系检查模块。
    parameter integer C_NUM_PORTS = 1, // 本次真实station启用端口数。
    parameter integer C_PAYLOAD_WIDTH = 5, // 包含非字节payload以检查三位元数据的位置。
    parameter integer C_CREDIT_WIDTH = 4, // 真实容量向量每账户位宽。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = 20'h30000, // 默认仅pool三项，允许原VC在池中任意变化。
    parameter integer C_RETURN_DEPTH = 3, // 实际每port退休元数据队列长度。
    parameter integer C_OBSERVE_DEPTH = 3 // 仅形式观察填充长度，由脚本取全部真实容量最大值。
) ( // 唯一自由输入均是原接收通道原生端口。
    input wire i_clk, i_rstn, // 共同时钟和任意重复同步复位。
    input wire i_credit_connected, i_beats_connected, // 真实连接资格，不假设单调以掩盖数据错误。
    input wire i_receive_valid, // 原生beat输入没有ready。
    input wire [1:0] i_receive_port, i_receive_vc, // 包含未启用port和池内任意原VC。
    input wire i_receive_pool, // 原信用类型必须真实保存并回放。
    input wire [C_PAYLOAD_WIDTH-1:0] i_receive_payload, // 每次接受的任意不透明payload。
    input wire [1:0] i_consumer_port, // 独立本地消费端口选择。
    input wire [2:0] i_consumer_account, // 包含三种非法账户编码。
    input wire i_consumer_ready, // 任意本地背压。
    output wire o_violation // 全部实际内容关系的失败归约。
); // 结束原生符号接口。
    localparam [31:0] C_SLOTS = C_NUM_PORTS*5; // 每启用port四VC加一个pool。
    localparam integer C_WORD_WIDTH = ((C_PAYLOAD_WIDTH+10)/8)*8; // payload加三位原元数据再向上补齐字节。
    localparam integer C_SAVED_WIDTH = C_PAYLOAD_WIDTH+3; // 不含padding的实际有效字宽。
    localparam integer C_PENDING_WIDTH = (C_RETURN_DEPTH <= 1) ? 1 : (C_RETURN_DEPTH <= 3) ? 2 : (C_RETURN_DEPTH <= 7) ? 3 : (C_RETURN_DEPTH <= 15) ? 4 : 5; // 真实返回队列观察形状。
    localparam [5:0] C_RETURN_LIMIT = C_RETURN_DEPTH[5:0]; // 独立数量域避免小深度加减截断。
    localparam [31:0] C_RECORDS = C_RETURN_DEPTH; // 显式非负常量作为退休槽静态展开上界。
    wire [C_PAYLOAD_WIDTH-1:0] head_payload; // DUT实际消费payload。
    wire [1:0] head_vc; // DUT实际原VC输出。
    wire head_pool, head_valid, consume_valid, accepted; // 实际消费资格和注册接受观察。
    wire [2:0] diagnostic; // 本地拒绝编码不是协议线上RAS。
    wire [C_SLOTS*C_CREDIT_WIDTH-1:0] counts, unread, read_addr, write_addr; // 各账户真实数量/地址零扩展观察。
    wire [C_SLOTS-1:0] pending, account_bad, selected_valid, pushes; // 实际在途、性质与独立边界事件。
    wire [C_SLOTS*2-1:0] cached; // 各真实双缓存数量。
    wire [C_SLOTS*C_WORD_WIDTH-1:0] heads, tails, read_results, shadow_heads; // 真实数据流水和独立期望头。
    wire [C_SLOTS*C_OBSERVE_DEPTH*C_WORD_WIDTH-1:0] memories; // 实际SRAM逻辑行，仅形式观察空槽填零。
    wire [4*C_PENDING_WIDTH-1:0] returns; // 各port实际未发布退休数量。
    wire [C_NUM_PORTS*C_RETURN_DEPTH*3-1:0] saved_returns; // 原返回组件实际元数据寄存器观察。
    wire [3:0] valid, pool, done, initial_valid, normal_valid, normal_pool, port_bad; // 实际合并及正常/初始发布有效形状。
    wire [7:0] vcs, nums, normal_vc, normal_num; // 实际注册信用元信息。
    wire [C_NUM_PORTS*3-1:0] stages; // 真实初始发布状态，用于交接辅助不变量。
    wire [C_WORD_WIDTH-1:0] original_word; // 原生数据的独立正确封装。
    reg [C_WORD_WIDTH-1:0] expected_head; // 从独立shadow账户头选择，不重用DUT头数据。
    reg previous_accept; // 独立记录合格输入用于检查注册接收诊断。
    reg [3:0] previous_done; // 已发布初始化完成的粘滞历史。
    wire selected_space; // 独立从原返回数量检查原子消费空间。
    integer select_index; // 有界静态归约全部独立账户头。
    genvar gen_account, gen_port, gen_record; // 常量展开账户、port和退休元数据槽。
    upli_receive_channel Channel_Inst ( // 真实DUT由脚本预先参数化且保留全部原驱动。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_credit_connected(i_credit_connected), .i_beats_connected(i_beats_connected), // 原控制环境保持符号化。
        .i_receive_valid(i_receive_valid), .i_receive_port(i_receive_port), .i_receive_vc(i_receive_vc), .i_receive_pool(i_receive_pool), .i_receive_payload(i_receive_payload), // 实际原生入站数据。
        .i_consumer_port(i_consumer_port), .i_consumer_account(i_consumer_account), .i_consumer_ready(i_consumer_ready), // 独立消费选择和背压。
        .o_head_payload(head_payload), .o_head_vc(head_vc), .o_head_pool(head_pool), .o_head_valid(head_valid), .o_consume_valid(consume_valid), // 实际消费字和原子提交资格。
        .o_receive_accepted(accepted), .o_diagnostic(diagnostic), .o_counts(counts), .o_pending_count(returns), // 原事件诊断和真实所有权观察。
        .o_credit_valid(valid), .o_credit_pool(pool), .o_credit_vc(vcs), .o_credit_num(nums), .o_credit_init_done(done), // 原生合并信用输出。
        .o_formal_unread(unread), .o_formal_pending(pending), .o_formal_cached(cached), .o_formal_read_addr(read_addr), .o_formal_write_addr(write_addr), // 只读真实控制器原状态。
        .o_formal_head(heads), .o_formal_tail(tails), .o_formal_read_result(read_results), .o_formal_memory(memories), // 只读真实SRAM及流水内容。
        .o_formal_returns(saved_returns), .o_formal_stages(stages), // 只读真实返回存储与初始化状态。
        .o_formal_initial_valid(initial_valid), .o_formal_normal_valid(normal_valid), .o_formal_normal_pool(normal_pool), .o_formal_normal_vc(normal_vc), .o_formal_normal_num(normal_num) // 只读两类注册信用边界。
    ); // 结束唯一实际接收通道实例。
    assign original_word = {{(C_WORD_WIDTH-C_SAVED_WIDTH){1'b0}}, i_receive_pool, i_receive_vc, i_receive_payload}; // 独立定义正确payload/原元数据位置和零padding。
    assign selected_space = ({{(6-C_PENDING_WIDTH){1'b0}}, returns[i_consumer_port*C_PENDING_WIDTH +: C_PENDING_WIDTH]} < C_RETURN_LIMIT); // 固定四port总线不发生索引越界。
    always @(*) begin // 独立消费期望由边界账户选择和原接受顺序构造。
        expected_head = {C_WORD_WIDTH{1'b0}}; // 未启用或非法账户无有效字。
        for (select_index = 32'd0; select_index < C_SLOTS; select_index = select_index+32'd1) begin // 枚举全部实际账户。
            expected_head = expected_head | (shadow_heads[select_index*C_WORD_WIDTH +: C_WORD_WIDTH] & {C_WORD_WIDTH{selected_valid[select_index]}}); // 唯一合法选择贡献独立期望完整字。
        end // 结束全部账户的独立期望头归约。
    end // 结束完整赋值的选择逻辑。
    always @(posedge i_clk) begin // 保存独立原生接纳结果而非DUTflag_receive。
        if (!i_rstn) previous_accept <= 1'b0; // 复位优先取消原生输入。
        else previous_accept <= |pushes; // 合格输入应只属于一个账户。
    end // 结束独立接受历史。
    always @(posedge i_clk) begin // 已完成初始发布只允许复位撤销。
        if (!i_rstn) previous_done <= 4'd0; // 复位开启新的连接/信用epoch。
        else previous_done <= done; // 保存真实沿前完成资格。
    end // 结束初始完成历史。
    generate // 按账户保存原接受字并检查全部真实内容。
        for (gen_account = 32'd0; gen_account < C_SLOTS; gen_account = gen_account+32'd1) begin : gen_accounts // 一个实际账户对应一个独立顺序关系。
            localparam integer C_PORT_INDEX = gen_account/5, C_ACCOUNT_INDEX = gen_account%5; // 静态账户归属。
            localparam [1:0] C_PORT = C_PORT_INDEX[1:0]; // 原生port双位编码。
            localparam [2:0] C_ACCOUNT = C_ACCOUNT_INDEX[2:0]; // 四VC或pool选择编码。
            localparam integer C_DEPTH = {{(32-C_CREDIT_WIDTH){1'b0}}, C_CAPACITIES[gen_account*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // 真实账户容量无符号扩展。
            localparam [C_CREDIT_WIDTH-1:0] C_LIMIT = C_DEPTH[C_CREDIT_WIDTH-1:0]; // 与原观察数量等宽比较。
            wire receive_match, consumer_match, pop; // 独立原生选择与外部真实消费事件。
            assign receive_match = (i_receive_port == C_PORT) && (i_receive_pool ? (C_ACCOUNT == 3'd4) : (C_ACCOUNT == {1'b0, i_receive_vc})); // 池包含所有原VC但只有一个物理账户。
            assign consumer_match = (i_consumer_port == C_PORT) && (i_consumer_account == C_ACCOUNT); // 非法选择不会别名到任何账户。
            assign pushes[gen_account] = i_rstn && i_receive_valid && receive_match && i_credit_connected && i_beats_connected && done[C_PORT_INDEX] && (counts[gen_account*C_CREDIT_WIDTH +: C_CREDIT_WIDTH] < C_LIMIT); // 独立容量/初始化资格，不重用DUT写使能。
            assign pop = consume_valid && i_consumer_ready && consumer_match; // 唯一真实消费者握手定义本账户退休。
            assign selected_valid[gen_account] = consumer_match && (cached[gen_account*2 +: 2] != 2'd0); // 真实缓存数量定义可见头，随后比较独立完整字。
            if (C_DEPTH > 0) begin : gen_active // 只有实际容量才展开内容状态。
                upli_receive_word_invariant #( // 只读原存储，不实例化第二个DUT冒充oracle。
                    .C_DEPTH(C_DEPTH), .C_WORD_WIDTH(C_WORD_WIDTH), .C_COUNT_WIDTH(C_CREDIT_WIDTH) // 观察位宽允许原控制器零扩展。
                ) Word_Inst ( // 每账户独立原生接受队列。
                    .i_clk(i_clk), .i_rstn(i_rstn), .i_push(pushes[gen_account]), .i_pop(pop), .i_word(original_word), // 期望值完全来自正确边界数据。
                    .i_count(counts[gen_account*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]), .i_unread(unread[gen_account*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]), // 原总量和未读数量。
                    .i_read_addr(read_addr[gen_account*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]), .i_write_addr(write_addr[gen_account*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]), // 原循环地址。
                    .i_pending(pending[gen_account]), .i_cached(cached[gen_account*2 +: 2]), // 原在途与缓存资格。
                    .i_head(heads[gen_account*C_WORD_WIDTH +: C_WORD_WIDTH]), .i_tail(tails[gen_account*C_WORD_WIDTH +: C_WORD_WIDTH]), .i_read_result(read_results[gen_account*C_WORD_WIDTH +: C_WORD_WIDTH]), // 实际数据流水。
                    .i_memory(memories[gen_account*C_OBSERVE_DEPTH*C_WORD_WIDTH +: C_DEPTH*C_WORD_WIDTH]), // 仅实际存在的逻辑行，不把填充观察当容量。
                    .o_shadow_head(shadow_heads[gen_account*C_WORD_WIDTH +: C_WORD_WIDTH]), .o_violation(account_bad[gen_account]) // 所有关系是被证明输出而非assume。
                ); // 结束本账户独立内容关系。
            end else begin : gen_empty // 无存储账户不得形成接受或消费数据。
                assign shadow_heads[gen_account*C_WORD_WIDTH +: C_WORD_WIDTH] = {C_WORD_WIDTH{1'b0}}; // 无独立有效队列内容。
                assign account_bad[gen_account] = (|counts[gen_account*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]) || pending[gen_account] || (|cached[gen_account*2 +: 2]) || pop; // 零容量必须保持零所有权且不可退休。
            end // 结束实际与零容量分支。
        end // 结束全部原生账户内容证明。
        for (gen_port = 32'd0; gen_port < 32'd4; gen_port = gen_port+32'd1) begin : gen_ports // 固定原生四port返回形状。
            localparam [1:0] C_PORT = gen_port; // 本地退休端口匹配常量。
            if (gen_port < C_NUM_PORTS) begin : gen_active // 真实启用port具有独立退休队列。
                reg [5:0] shadow_count; // 独立期望未注册发布的退休记录数。
                wire [C_RETURN_DEPTH*3-1:0] shadow_words; // 按退休顺序排列的原VC/Pool。
                wire [C_RETURN_DEPTH-1:0] bad_words; // 每个真实有效保存记录的内容比较。
                reg [2:0] batch_count; // 仅从独立shadow前缀和顶层许可计算。
                wire retire, enabled; // 实际外部退休握手及旧逐port发布资格。
                wire [5:0] survivors, actual_count; // 本沿移出旧前缀后的独立数量和真实数量。
                reg expected_valid; // 下一真实注册周期应有的正常有效信号。
                reg [2:0] expected_metadata; // 下一真实注册周期应回放的原队首字段。
                reg [1:0] expected_num; // 独立生成标准Num+1批次编码。
                integer prefix_index; // 最多四项独立连续前缀扫描。
                assign actual_count = {{(6-C_PENDING_WIDTH){1'b0}}, returns[gen_port*C_PENDING_WIDTH +: C_PENDING_WIDTH]}; // 原返回队列占用观察。
                assign retire = consume_valid && i_consumer_ready && (i_consumer_port == C_PORT); // 原消费者事件不能被错误返回使能替代。
                assign enabled = i_rstn && i_credit_connected && done[gen_port]; // 使用沿前真实完成资格，不使用内部batch/enable。
                assign survivors = shadow_count-{3'd0, batch_count}; // 独立移出零至四项旧记录。
                always @(*) begin // 用有序前缀计数与原实现嵌套相等标志分离。
                    batch_count = 3'd0; // 空或未获许可不预约任何新批次。
                    for (prefix_index = 32'd0; prefix_index < 32'd4; prefix_index = prefix_index+32'd1) begin // 批次最多四信用。
                        if (enabled && (prefix_index < C_RETURN_DEPTH) && (batch_count == prefix_index[2:0]) && (shadow_count > {3'd0, prefix_index[2:0]}) && (shadow_words[prefix_index*3 +: 3] == shadow_words[2:0])) batch_count = batch_count+3'd1; // 任一不同VC/Pool立即终止连续前缀，不能跨过中间记录合批。
                    end // 结束独立同类最长前缀扫描。
                end // 结束正常发布独立期望计算。
                always @(posedge i_clk) begin // 独立统计真实退休与期望旧批次发布。
                    if (!i_rstn) shadow_count <= 6'd0; // 复位取消旧返回所有权。
                    else shadow_count <= survivors+{5'd0, retire}; // 本沿新退休不能借作同沿发布旧批次。
                end // 结束本port独立退休数量。
                always @(posedge i_clk) begin // 单独注册正常输出有效期望。
                    if (!i_rstn) expected_valid <= 1'b0; // 复位不能残留旧批次有效性。
                    else expected_valid <= batch_count != 3'd0; // 预约下一注册输出周期。
                end // 结束正常有效历史。
                always @(posedge i_clk) begin // 单独注册原VC/Pool的期望回放值。
                    if (!i_rstn) expected_metadata <= 3'd0; // 复位输出字段清零。
                    else expected_metadata <= (batch_count != 3'd0) ? shadow_words[2:0] : 3'd0; // 原队首而非当前输入决定输出字段。
                end // 结束正常元数据期望寄存器。
                always @(posedge i_clk) begin // 单独寄存Num+1的独立编码。
                    if (!i_rstn) expected_num <= 2'd0; // 无效复位字段归零。
                    else expected_num <= (batch_count != 3'd0) ? (batch_count[1:0]-2'd1) : 2'd0; // 四项编码三，零项禁止产生信用。
                end // 结束正常数量期望寄存器。
                for (gen_record = 32'd0; gen_record < C_RECORDS; gen_record = gen_record+32'd1) begin : gen_records // 实际每个退休槽都有独立期望。
                    localparam [5:0] C_INDEX = gen_record; // 固定期望队列位置。
                    reg [2:0] reg_word; // 当前退休顺序位置的原VC/Pool。
                    wire [5:0] successor_index; // 移出独立旧前缀后的来源位置。
                    wire [2:0] successor; // 不越界的动态顺序前移候选。
                    assign shadow_words[gen_record*3 +: 3] = reg_word; // 低槽是最旧未发布退休记录。
                    assign successor_index = C_INDEX+{3'd0, batch_count}; // 独立前缀长度决定原记录次序前移。
                    assign successor = (successor_index < C_RETURN_LIMIT) ? shadow_words[successor_index*3 +: 3] : 3'd0; // 队列外无效记录确定零值。
                    always @(posedge i_clk) begin // 一槽一时序寄存器，独立消费元数据来源。
                        if (!i_rstn) reg_word <= 3'd0; // 取消旧epoch退休字段。
                        else if (retire && (survivors == C_INDEX)) reg_word <= expected_head[C_PAYLOAD_WIDTH +: 3]; // 必须从原接受字的独立期望头记录，不从错误DUT退休元数据推断。
                        else if (batch_count != 3'd0) reg_word <= successor; // 只移出连续同类旧前缀。
                    end // 结束当前退休顺序记录更新。
                    assign bad_words[gen_record] = (shadow_count > C_INDEX) && (saved_returns[(gen_port*C_RETURN_DEPTH+gen_record)*3 +: 3] != reg_word); // 原返回组件的每个有效实际槽都必须保留正确原字段。
                end // 结束本port全部真实退休记录比较。
                assign port_bad[gen_port] = (actual_count != shadow_count) || (shadow_count > C_RETURN_LIMIT) || (|bad_words) || (normal_valid[gen_port] != expected_valid) || ({normal_pool[gen_port], normal_vc[gen_port*2 +: 2]} != expected_metadata) || (normal_num[gen_port*2 +: 2] != expected_num) || (initial_valid[gen_port] && normal_valid[gen_port]) || (initial_valid[gen_port] && done[gen_port]) || (previous_done[gen_port] && !done[gen_port]) || (stages[gen_port*3 +: 3] > 3'd5) || (done[gen_port] && (stages[gen_port*3 +: 3] != 3'd5)) || (valid[gen_port] != (initial_valid[gen_port] || normal_valid[gen_port])) || (normal_valid[gen_port] && (({pool[gen_port], vcs[gen_port*2 +: 2]} != expected_metadata) || (nums[gen_port*2 +: 2] != expected_num))) || (!valid[gen_port] && (pool[gen_port] || (vcs[gen_port*2 +: 2] != 2'd0) || (nums[gen_port*2 +: 2] != 2'd0))); // 数量、全部保存内容、注册输出和合并交接同时为被证明性质。
            end else begin : gen_unused // 未启用port不允许产生任何所有权或信用。
                assign port_bad[gen_port] = (|returns[gen_port*C_PENDING_WIDTH +: C_PENDING_WIDTH]) || valid[gen_port] || pool[gen_port] || done[gen_port] || initial_valid[gen_port] || normal_valid[gen_port] || normal_pool[gen_port] || (|vcs[gen_port*2 +: 2]) || (|nums[gen_port*2 +: 2]) || (|normal_vc[gen_port*2 +: 2]) || (|normal_num[gen_port*2 +: 2]); // 原生固定形状的未用部分确定零值。
            end // 结束真实port和未用port内容检查。
        end // 结束全部正常信用端口的独立顺序关系。
    endgenerate // 结束完整账户/正常归还内容证明结构。
    assign o_violation = (|account_bad) || (|port_bad) || (accepted != previous_accept) || (accepted && (diagnostic != 3'd0)) || (head_valid != (|selected_valid)) || ({head_pool, head_vc, head_payload} != expected_head[C_SAVED_WIDTH-1:0]) || (consume_valid != (i_rstn && head_valid && selected_space)); // 原生接受到实际消费和正常信用回放的任一内容/资格错误都失败。
endmodule // 结束upli_channel_content_properties实际通道内容关系。
