// Receive channel plus actual sender credit bank and external SRAM models.
// 日期 2026-09-08；独立输入日志检查真实 payload、原始 VC/Pool 和信用守恒。
`timescale 1ps/1ps // 同域皮秒精度覆盖常规与参考静态周期。
module upli_receive_channel_tb; // 单通道接收存储及完整信用交接的自检测试模块。
    parameter integer C_NUM_PORTS = 1; // 验证一、二或四端口实例。
    parameter integer C_PAYLOAD_WIDTH = 32; // 不透明输入数据位宽，存储 padding 由 DUT 负责。
    parameter integer C_CREDIT_WIDTH = 4; // 声明每账户容量及余额位宽。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = 20'h50132; // 低位依次为各端口 VC0..3 与共享池。
    parameter integer C_RETURN_DEPTH = 4; // 每端口退休元数据容量。
    parameter integer C_CHANNEL = 0; // 零一为请求和源数据，二三为读写响应。
    parameter integer C_HALF_PERIOD_PS = 320; // 一次仿真中固定时钟周期，不冒充动态切钟测试。
    localparam integer C_SLOTS = C_NUM_PORTS*5; // 独立账户及输入日志的数量。
    localparam integer C_BAL_WIDTH = C_SLOTS*C_CREDIT_WIDTH; // 全部账户扁平化观察宽度。
    localparam integer C_PENDING_WIDTH = (C_RETURN_DEPTH <= 1) ? 1 : (C_RETURN_DEPTH <= 3) ? 2 : (C_RETURN_DEPTH <= 7) ? 3 : (C_RETURN_DEPTH <= 15) ? 4 : 5; // 与返回队列实际计数域一致。
    localparam integer C_VIEW_WIDTH = 2*C_BAL_WIDTH+4*C_PENDING_WIDTH+C_PAYLOAD_WIDTH+42; // 包含真实银行与接收器全部契约输出。
    localparam integer C_SCORE_DEPTH = (1 << C_CREDIT_WIDTH); // 日志覆盖本次信用位宽的全部合法容量，独立于真实FIFO实现。
    reg clk; // 唯一验证时钟进程驱动。
    reg [C_PAYLOAD_WIDTH+17:0] stimulus; // 向量包含连接、独立非法注入及本地消费者选择。
    reg [C_VIEW_WIDTH-1:0] expected_before, expected_after; // 独立 Python 参考的沿前沿后快照。
    wire rstn, orig_req, comp_ack, comp_req, orig_ack, send_actual, receive_valid; // 明确区分合法发送银行事件与直接非法注入。
    wire [1:0] receive_port, receive_vc, consumer_port; // 原生两位端口与 VC 字段。
    wire receive_pool, consumer_ready; // 输入信用类型与本地消费者反压。
    wire [C_PAYLOAD_WIDTH-1:0] receive_payload; // 原始输入日志的数据来源。
    wire [2:0] consumer_account; // 零至三为 VC，四为共享池，其余选择无效。
    wire credit_connected, beats_connected; // 返回单方向与数据双方向资格独立。
    wire [3:0] credit_valid, credit_pool, credit_done, bank_done; // 原生四端口信用和银行确认。
    wire [7:0] credit_vc, credit_num; // 每端口原始 VC 与实际数量减一编码。
    wire [C_BAL_WIDTH-1:0] counts, balances; // 实际存储占用和真实发送端余额。
    wire [4*C_PENDING_WIDTH-1:0] pending; // 尚未调度到返回输出的元数据数量。
    wire [C_PAYLOAD_WIDTH-1:0] head_payload; // 真正 SRAM 路径读出的所选队首。
    wire [1:0] head_vc; // 保存的原始 VC，不能由当前消费者账户重构。
    wire head_pool, head_valid, consume_valid, accepted, bank_error; // 缓存可见与原子退休资格分别观察。
    wire [2:0] diagnostic; // 本地输入诊断而非线上 RAS 编码。
    wire [C_VIEW_WIDTH-1:0] observed; // 对完整可见输出进行全位比较。
    reg [C_PAYLOAD_WIDTH+2:0] saved [0:C_SLOTS*C_SCORE_DEPTH-1]; // 每账户独立保存实际输入字及原始元数据。
    reg [2:0] owed [0:127]; // 四端口各三十二项尚未被银行采样的退休元数据日志。
    integer write_index [0:C_SLOTS-1]; // 每个账户独立的输入日志写指针。
    integer read_index [0:C_SLOTS-1]; // 每个账户独立的输入日志读指针。
    integer score_count [0:C_SLOTS-1]; // 未退休真实 payload 数量。
    integer unreturned [0:C_SLOTS-1]; // 已退休但尚未到银行的信用所有权。
    integer owed_write [0:3]; // 各端口退休日志写指针。
    integer owed_read [0:3]; // 各端口退休日志读指针。
    integer owed_count [0:3]; // 各端口包含注册批次的待归还总记录数。
    integer fd, fields, rows, slot, port_index, amount, item_index, capacity, read_total, accepted_total; // 测试文件与独立记账临时变量。
    integer aborted_total, burst, max_burst, max_capacity, parallel_handoff; // 明确记录复位中止、连续退休和不同端口交接重叠覆盖。
    reg [4095:0] vector_path; // 外部指定向量路径，不绑定个人工作目录。
    assign {rstn, orig_req, comp_ack, comp_req, orig_ack, send_actual, receive_valid, receive_port, receive_vc, receive_pool, receive_payload, consumer_port, consumer_account, consumer_ready} = stimulus; // 固定拆解全部输入向量字段。
    assign credit_connected = (C_CHANNEL < 2) ? (comp_req && orig_ack) : (orig_req && comp_ack); // 核对四通道的反向信用连接。
    assign beats_connected = orig_req && comp_ack && comp_req && orig_ack; // 任何 beat 均须双方向建立。
    assign observed = {balances, bank_done, bank_error, counts, pending, credit_valid, credit_pool, credit_vc, credit_num, credit_done, head_payload, head_vc, head_pool, head_valid, consume_valid, accepted, diagnostic}; // 观察总线严格匹配模型打包顺序。
    upli_receive_channel #( // 真正接收 DUT 同时包括存储与两种信用发布器。
        .C_NUM_PORTS(C_NUM_PORTS), .C_PAYLOAD_WIDTH(C_PAYLOAD_WIDTH), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), // 端口数据和信用域共用验证配置。
        .C_CAPACITIES(C_CAPACITIES), .C_RETURN_DEPTH(C_RETURN_DEPTH) // 初始发布容量必须来自真实存储容量。
    ) Receiver_Inst ( // 使用显式获授权外部存储模型的接收器实例。
        .i_clk(clk), .i_rstn(rstn), .i_credit_connected(credit_connected), .i_beats_connected(beats_connected), // 单一时钟域的两种连接资格。
        .i_receive_valid(receive_valid), .i_receive_port(receive_port), .i_receive_vc(receive_vc), .i_receive_pool(receive_pool), .i_receive_payload(receive_payload), // 原生输入没有 ready。
        .i_consumer_port(consumer_port), .i_consumer_account(consumer_account), .i_consumer_ready(consumer_ready), // 本地按账户选择消费。
        .o_head_payload(head_payload), .o_head_vc(head_vc), .o_head_pool(head_pool), .o_head_valid(head_valid), .o_consume_valid(consume_valid), // 可见队首与可提交退休资格。
        .o_receive_accepted(accepted), .o_diagnostic(diagnostic), .o_counts(counts), .o_pending_count(pending), // 接收诊断和独立守恒观察。
        .o_credit_valid(credit_valid), .o_credit_pool(credit_pool), .o_credit_vc(credit_vc), .o_credit_num(credit_num), .o_credit_init_done(credit_done) // 实际注册信用总线连接银行。
    ); // 结束接收通道 DUT 实例。
    upli_credit_bank #( // 实际发送银行使用同一接收资源声明。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), .C_CAPACITIES(C_CAPACITIES) // 不伪造银行余额为常量。
    ) Sender_Inst ( // 真实信用银行过滤 done 并采样前周期的注册归还。
        .i_clk(clk), .i_rstn(rstn), .i_credit_connected(credit_connected), .i_beats_connected(beats_connected), // 与接收器共用真实连接电平。
        .i_credit_valid(credit_valid), .i_credit_pool(credit_pool), .i_credit_vc(credit_vc), .i_credit_num(credit_num), .i_credit_init_done(credit_done), // 没有模型代替真实信用连线。
        .i_send_valid(send_actual), .i_send_port(receive_port), .i_send_vc(receive_vc), .i_send_pool(receive_pool), // 直接非法注入不是合法发送事件。
        .o_balances(balances), .o_init_confirmed(bank_done), .o_error(bank_error) // 模型和独立容量公式双重检查。
    ); // 结束发送端信用银行实例。
    always #(C_HALF_PERIOD_PS) clk = ~clk; // 静态选择常规或参考时钟周期。
    initial begin // 读取向量并从真实输入输出维护独立所有权日志。
        clk = 1'b0; stimulus = {(C_PAYLOAD_WIDTH+18){1'b0}}; rows = 0; read_total = 0; accepted_total = 0; // 首沿之前全部驱动确定。
        aborted_total = 0; burst = 0; max_burst = 0; max_capacity = 0; parallel_handoff = 0; // 初始化独立性能与复位覆盖计数。
        for (slot = 0; slot < C_SLOTS; slot = slot+1) begin // 预检查日志容量与本次真实配置兼容。
            capacity = {{(32-C_CREDIT_WIDTH){1'b0}}, C_CAPACITIES[slot*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // 显式扩展配置值避免有符号比较歧义。
            if (capacity > max_capacity) max_capacity = capacity; // 最大真实容量用于本地连续消费的测试边界。
            if (capacity > C_SCORE_DEPTH) begin $display("FAIL scoreboard capacity"); $stop; end // 超出测试边界不能伪称覆盖。
        end // 结束测试日志容量前置检查。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin $display("FAIL missing vectors"); $stop; end // 禁止没有用例的空跑通过。
        fd = $fopen(vector_path, "r"); // 只读打开项目生成向量。
        if (fd == 0) begin $display("FAIL cannot open vectors"); $stop; end // 明确拒绝不可读文件。
        while (!$feof(fd)) begin // 顺序处理每个有效采样沿。
            @(negedge clk); // 在非采样边沿驱动输入。
            fields = $fscanf(fd, "%h %h %h\n", stimulus, expected_before, expected_after); // 要求输入及两个边界期望齐全。
            if (fields != 3) begin $display("FAIL malformed vector row=%0d", rows); $stop; end // 损坏向量不能跳过。
            #1; // 等待选择器与当前 head 组合稳定。
            if ((rows != 0) && (observed !== expected_before)) begin $display("FAIL channel before row=%0d actual=%h expected=%h", rows, observed, expected_before); $stop; end // 上电首次复位之前不假设状态。
            if (!rstn) begin // 同步复位取消所有旧信用与 payload 所有权。
                burst = 0; // 复位打断连续退休统计。
                for (slot = 0; slot < C_SLOTS; slot = slot+1) begin // 重置每账户独立队列，不清除物理 SRAM 内容。
                    if (rows != 0) aborted_total = aborted_total+score_count[slot]; // 首次上电不读未知日志，其后精确记录被复位中止的字。
                    write_index[slot] = 0; read_index[slot] = 0; score_count[slot] = 0; unreturned[slot] = 0; // 所有权计数清零。
                end // 结束账户复位记录。
                for (port_index = 0; port_index < 4; port_index = port_index+1) begin // 原生四端口退休日志全部复位。
                    owed_write[port_index] = 0; owed_read[port_index] = 0; owed_count[port_index] = 0; // 无旧注册信用可继续提交。
                end // 结束退休日志复位记录。
            end else begin // 在实际采样沿前核对已承诺的信用与当前退休。
                for (port_index = 0; port_index < C_NUM_PORTS; port_index = port_index+1) begin // 各端口信用可以同拍独立返回。
                    if (credit_valid[port_index] && bank_done[port_index]) begin // 初始化结束后的真实批次必须来自退休日志。
                        amount = 1+{30'd0, credit_num[port_index*2 +: 2]}; // 数量减一编码还原到一至四。
                        slot = port_index*5+(credit_pool[port_index] ? 4 : {30'd0, credit_vc[port_index*2 +: 2]}); // 按实际类型归入唯一共享池或 VC 账户。
                        for (item_index = 0; item_index < amount; item_index = item_index+1) begin // 逐个检查批次的原始元信息，不只比较数量。
                            if ((owed_count[port_index] == 0) || (owed[port_index*32+owed_read[port_index]] !== {credit_pool[port_index], credit_vc[port_index*2 +: 2]})) begin $display("FAIL original credit metadata row=%0d", rows); $stop; end // 错 VC、错 Pool、重复或伪归还立即失败。
                            owed_read[port_index] = (owed_read[port_index]+1)%32; owed_count[port_index] = owed_count[port_index]-1; unreturned[slot] = unreturned[slot]-1; // 已被真实银行采样的记录退出在途集合。
                        end // 结束批次逐项回放核对。
                    end // 结束有效正常信用批次处理。
                end // 结束各端口信用采样日志。
                if (consume_valid && consumer_ready) begin // 真正消费者和返回队列均可接纳才退休。
                    burst = burst+1; if (burst > max_burst) max_burst = burst; // 连续吞吐只按真实原子退休事件计数。
                    port_index = {30'd0, consumer_port}; slot = port_index*5+{29'd0, consumer_account}; // 当前选择对应独立 FIFO 账户。
                    if ((slot >= C_SLOTS) || (score_count[slot] == 0) || ({head_pool, head_vc, head_payload} !== saved[slot*C_SCORE_DEPTH+read_index[slot]])) begin $display("FAIL actual payload order row=%0d", rows); $stop; end // SRAM 输出必须匹配原始入站字及元数据。
                    read_index[slot] = (read_index[slot]+1)%C_SCORE_DEPTH; score_count[slot] = score_count[slot]-1; unreturned[slot] = unreturned[slot]+1; read_total = read_total+1; // 原子转移 payload 所有权到信用在途日志。
                    if (owed_count[port_index] >= 32) begin $display("FAIL return log overflow"); $stop; end // 显式保护独立日志而非依赖数组回绕。
                    owed[port_index*32+owed_write[port_index]] = {head_pool, head_vc}; // 元数据来源仅为已核对的真实读出头。
                    owed_write[port_index] = (owed_write[port_index]+1)%32; owed_count[port_index] = owed_count[port_index]+1; // 新退休条目加入旧批次之后。
                end else burst = 0; // 没有实际退休的周期打断连续吞吐。
            end // 结束同步复位及正常沿前记账。
            @(posedge clk); #1; // 等待 SRAM 和 DUT 非阻塞寄存更新完成。
            if (observed !== expected_after) begin $display("FAIL channel after row=%0d actual=%h expected=%h", rows, observed, expected_after); $stop; end // 全位检查模型预期与真实实现。
            if (accepted) begin // 记录接收器本沿真正接纳的原始输入字。
                slot = {30'd0, receive_port}*5+(receive_pool ? 4 : {30'd0, receive_vc}); // 池映射仅用于存放位置，不丢失原 VC。
                if (!rstn || !receive_valid || !send_actual || (slot >= C_SLOTS) || (score_count[slot] >= C_SCORE_DEPTH)) begin $display("FAIL illegal acceptance row=%0d", rows); $stop; end // 被拒绝直接注入不能偷偷进入存储。
                saved[slot*C_SCORE_DEPTH+write_index[slot]] = {receive_pool, receive_vc, receive_payload}; // 期望数据直接来自原始输入。
                write_index[slot] = (write_index[slot]+1)%C_SCORE_DEPTH; score_count[slot] = score_count[slot]+1; accepted_total = accepted_total+1; // 增加独立真实接纳数量。
            end // 结束实际入站日志更新。
            if (|(Receiver_Inst.initial_valid & Receiver_Inst.normal_valid)) begin $display("FAIL credit handoff overlap row=%0d", rows); $stop; end // 两个注册发布器不能预约同一端口周期。
            if ((|Receiver_Inst.initial_valid) && (|Receiver_Inst.normal_valid)) parallel_handoff = parallel_handoff+1; // 不同端口可以处于不同发布阶段并同时服务。
            for (slot = 0; slot < C_SLOTS; slot = slot+1) begin // 检查每个独立资源账户的完整容量守恒。
                capacity = {{(32-C_CREDIT_WIDTH){1'b0}}, C_CAPACITIES[slot*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // 实际容量不包括宏 padding 或读缓存额外空间。
                if (score_count[slot] != {{(32-C_CREDIT_WIDTH){1'b0}}, counts[slot*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}) begin $display("FAIL actual account count row=%0d slot=%0d", rows, slot); $stop; end // 独立数据日志校验实际占用。
                if (bank_done[slot/5] && ((score_count[slot]+unreturned[slot]+{{(32-C_CREDIT_WIDTH){1'b0}}, balances[slot*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}) != capacity)) begin $display("FAIL capacity conservation row=%0d slot=%0d", rows, slot); $stop; end // 银行、存储及所有在途记录总和必须等于容量。
            end // 结束全部账户守恒核对。
            for (port_index = 0; port_index < C_NUM_PORTS; port_index = port_index+1) begin // 核对队列与注册批次的完整返回管线占用。
                amount = (credit_valid[port_index] && bank_done[port_index]) ? (1+{30'd0, credit_num[port_index*2 +: 2]}) : 0; // 注册总线也是尚未回到银行的所有权。
                if (bank_done[port_index] && (owed_count[port_index] != (amount+{{(32-C_PENDING_WIDTH){1'b0}}, pending[port_index*C_PENDING_WIDTH +: C_PENDING_WIDTH]}))) begin $display("FAIL return pipeline conservation row=%0d", rows); $stop; end // 不遗漏已出队但仍在注册输出的批次。
            end // 结束返回管线逐端口核对。
            rows = rows+1; // 只记录完整通过的向量边沿。
        end // 结束所有向量的真实连线检查。
        $fclose(fd); // 关闭只读向量文件。
        if (rows < 3000) begin $display("FAIL incomplete channel vectors"); $stop; end // 防止截短为少量用例的空签核。
        if (accepted_total != read_total+aborted_total) begin $display("FAIL total payload ownership"); $stop; end // 区分真实退休与有意复位中止而非把丢失默认为合法。
        if ((max_capacity >= 16) && (C_RETURN_DEPTH >= 2) && (max_burst < 128)) begin $display("FAIL channel steady throughput burst=%0d", max_burst); $stop; end // 充足容量配置必须实测连续每拍一个字的消费能力。
        for (slot = 0; slot < C_SLOTS; slot = slot+1) begin // 最终复位再初始化后必须没有陈旧 payload 或信用。
            if ((score_count[slot] != 0) || (unreturned[slot] != 0)) begin $display("FAIL incomplete channel drain"); $stop; end // 未排空的所有权禁止通过。
        end // 结束最终账户排空检查。
        $display("PASS receive_channel rows=%0d ports=%0d width=%0d return_depth=%0d channel=%0d period_ps=%0d accepted=%0d retired=%0d aborted=%0d max_burst=%0d parallel_handoff=%0d", rows, C_NUM_PORTS, C_PAYLOAD_WIDTH, C_RETURN_DEPTH, C_CHANNEL, 2*C_HALF_PERIOD_PS, accepted_total, read_total, aborted_total, max_burst, parallel_handoff); // 报告真实配置、吞吐、复位及逐端口交接覆盖。
        $finish; // 仅所有模型及独立日志核对通过后退出。
    end // 结束接收通道自检流程。
    initial begin #10000000000; $display("FAIL receive channel watchdog"); $stop; end // 防止挂起被误认作完成。
endmodule // 结束 upli_receive_channel_tb 完整信用与 payload 检查模块。
