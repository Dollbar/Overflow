`timescale 1ns/1ps // 定义扩展事务与完成历史自检时间单位
`include "kdlink_defs.vh" // 引入全局提交状态编码
module tb_kdlink_scale_transaction; // 定义超过十六槽碰撞和 exact-once 联合自检
    logic clk; // 产生事务控制时钟
    logic rst_n; // 驱动低有效硬复位
    logic issue_valid; // 驱动新事务请求
    wire issue_ready; // 观察新事务许可
    logic [63:0] issue_id; // 驱动新事务标识
    logic [15:0] issue_epoch; // 驱动新事务拓扑代次
    logic [15:0] issue_timeout; // 驱动新事务超时门限
    wire send_valid; // 观察发送命令有效位
    logic send_ready; // 驱动发送命令许可
    wire [63:0] send_id; // 观察发送事务标识
    wire [15:0] send_epoch; // 观察发送拓扑代次
    wire [3:0] send_retry; // 观察发送重试次数
    logic source_commit_valid; // 驱动源端收到的提交确认
    logic [63:0] source_commit_id; // 驱动确认事务标识
    logic [15:0] source_commit_epoch; // 驱动确认拓扑代次
    logic [1:0] source_commit_status; // 驱动确认状态
    logic route_reset; // 驱动路由软复位
    logic [15:0] route_epoch; // 驱动换路后的新拓扑代次
    wire completion_valid; // 观察源端完成脉冲
    wire [63:0] completion_id; // 观察完成事务标识
    wire source_protocol_error; // 观察源端协议错误
    wire retry_exhausted; // 观察源端重试耗尽
    wire source_overflow; // 观察源端窗口溢出
    wire [8:0] outstanding_count; // 观察源端保留事务数量
    logic history_commit_valid; // 驱动目的端本地提交事件
    wire history_commit_ready; // 观察目的端历史许可
    logic [14:0] history_source_domain; // 驱动十五位原事务源域
    logic [14:0] history_destination_domain; // 驱动十五位原事务目的域
    logic [4:0] history_source_node; // 驱动原事务源节点
    logic [4:0] history_destination_node; // 驱动原事务目的节点
    logic [15:0] history_epoch; // 驱动到达拓扑代次
    logic [63:0] history_id; // 驱动目的端事务标识
    wire deliver_valid; // 观察首次交付脉冲
    wire [63:0] deliver_id; // 观察首次交付事务标识
    wire ack_valid; // 观察首次或重复确认脉冲
    wire [15:0] ack_epoch; // 观察确认沿用的到达代次
    wire [63:0] ack_id; // 观察确认事务标识
    wire duplicate_seen; // 观察重复事务 sticky 状态
    wire history_overflow; // 观察历史窗口溢出状态
    wire [8:0] history_count; // 观察已占用历史数量
    logic [14:0] codec_source_domain; // 驱动提交 codec 源域
    logic [14:0] codec_destination_domain; // 驱动提交 codec 目的域
    logic [4:0] codec_source_node; // 驱动提交 codec 源节点
    logic [4:0] codec_destination_node; // 驱动提交 codec 目的节点
    logic [15:0] codec_epoch; // 驱动提交 codec 拓扑代次
    logic [63:0] codec_id; // 驱动提交 codec 事务标识
    logic [1:0] codec_status; // 驱动提交 codec 状态
    wire [511:0] codec_payload; // 观察编码提交 payload
    logic [511:0] decoder_payload; // 驱动独立提交解码器
    wire [14:0] decoded_source_domain; // 观察解码源域
    wire [14:0] decoded_destination_domain; // 观察解码目的域
    wire [4:0] decoded_source_node; // 观察解码源节点
    wire [4:0] decoded_destination_node; // 观察解码目的节点
    wire [15:0] decoded_epoch; // 观察解码拓扑代次
    wire [63:0] decoded_id; // 观察解码事务标识
    wire [1:0] decoded_status; // 观察解码提交状态
    wire decoder_valid; // 观察提交 payload 合法性
    integer send_count; // 统计发送命令握手次数
    integer completion_count; // 统计源端完成脉冲数
    integer delivery_count; // 统计目的端首次交付数
    integer ack_count; // 统计目的端确认数
    integer index; // 遍历超过十六条事务
    integer watchdog; // 限制等待循环周期
    kdlink_transaction_window #(.ENTRY_COUNT(20), .REPLAY_GRACE_CYCLES(16'd8)) u_source ( // 实例化二十槽关联源事务窗口
        .clk_i(clk), .rst_n_i(rst_n), // 连接时钟和硬复位
        .issue_valid_i(issue_valid), .issue_ready_o(issue_ready), .issue_transaction_id_i(issue_id), // 连接新事务握手和标识
        .issue_topology_epoch_i(issue_epoch), .issue_timeout_quanta_i(issue_timeout), // 连接新事务代次和超时
        .send_valid_o(send_valid), .send_ready_i(send_ready), .send_transaction_id_o(send_id), // 连接发送命令握手和标识
        .send_topology_epoch_o(send_epoch), .send_retry_count_o(send_retry), // 观察发送代次和重试次数
        .commit_valid_i(source_commit_valid), .commit_transaction_id_i(source_commit_id), // 连接源端确认有效位和标识
        .commit_topology_epoch_i(source_commit_epoch), .commit_status_i(source_commit_status), // 连接确认代次和状态
        .route_reset_i(route_reset), .route_topology_epoch_i(route_epoch), // 连接换路事件和新代次
        .completion_valid_o(completion_valid), .completion_transaction_id_o(completion_id), // 观察完成脉冲和标识
        .protocol_error_o(source_protocol_error), .retry_exhausted_o(retry_exhausted), // 观察协议和预算错误
        .window_overflow_o(source_overflow), .outstanding_count_o(outstanding_count) // 观察容量状态
    ); // 结束源事务窗口实例
    kdlink_commit_window #(.ENTRY_COUNT(20), .REPLAY_GRACE_CYCLES(16'd100)) u_history ( // 实例化二十槽关联目的完成历史
        .clk_i(clk), .rst_n_i(rst_n), .route_reset_i(route_reset), // 连接时钟、硬复位和不清历史的软复位
        .commit_valid_i(history_commit_valid), .commit_ready_o(history_commit_ready), // 连接本地提交握手
        .source_domain_i(history_source_domain), .destination_domain_i(history_destination_domain), // 连接十五位域身份
        .source_node_i(history_source_node), .destination_node_i(history_destination_node), // 连接 leaf 内节点身份
        .topology_epoch_i(history_epoch), .global_transaction_id_i(history_id), // 连接到达代次和事务标识
        .deliver_valid_o(deliver_valid), .deliver_transaction_id_o(deliver_id), // 观察一次性交付
        .global_ack_valid_o(ack_valid), .global_ack_source_domain_o(), .global_ack_destination_domain_o(), // 观察确认有效位并忽略已单独验证的域回环
        .global_ack_source_node_o(), .global_ack_destination_node_o(), .global_ack_topology_epoch_o(ack_epoch), // 观察确认代次
        .global_ack_transaction_id_o(ack_id), .global_ack_status_o(), // 观察确认事务标识
        .duplicate_seen_o(duplicate_seen), .window_overflow_o(history_overflow), .history_count_o(history_count) // 观察历史状态
    ); // 结束目的端完成历史实例
    kdlink_scale_global_commit_encoder u_commit_encoder ( // 实例化 schema-4 提交编码器
        .source_domain_i(codec_source_domain), .destination_domain_i(codec_destination_domain), // 连接十五位域字段
        .source_node_i(codec_source_node), .destination_node_i(codec_destination_node), // 连接节点字段
        .topology_epoch_i(codec_epoch), .global_transaction_id_i(codec_id), .status_i(codec_status), // 连接代次、事务和状态
        .payload_o(codec_payload) // 观察编码 payload
    ); // 结束提交编码器实例
    kdlink_scale_global_commit_decoder u_commit_decoder ( // 实例化独立 schema-4 提交解码器
        .payload_i(decoder_payload), .source_domain_o(decoded_source_domain), .destination_domain_o(decoded_destination_domain), // 连接 payload 并观察域字段
        .source_node_o(decoded_source_node), .destination_node_o(decoded_destination_node), // 观察节点字段
        .topology_epoch_o(decoded_epoch), .global_transaction_id_o(decoded_id), .status_o(decoded_status), // 观察代次、事务和状态
        .payload_valid_o(decoder_valid) // 观察保留位和状态合法性
    ); // 结束提交解码器实例
    always #0.5 clk = ~clk; // 产生一纳秒时钟周期
    always @(posedge clk) begin // 统计所有关键事务事件
        if (send_valid && send_ready) send_count <= send_count + 1; // 统计源端发送命令
        if (completion_valid) completion_count <= completion_count + 1; // 统计源端完成脉冲
        if (deliver_valid) delivery_count <= delivery_count + 1; // 统计目的端首次交付
        if (ack_valid) ack_count <= ack_count + 1; // 统计目的端确认脉冲
    end // 结束事件计数
    task automatic issue_one(input [63:0] transaction_id, input [15:0] epoch_value); // 签发一条预期接受的源事务
        integer issue_wait; // 限制流水准入许可等待周期
        begin // 开始新事务握手
            @(negedge clk); issue_id = transaction_id; issue_epoch = epoch_value; issue_valid = 1'b1; #0.1; // 驱动新事务并等待许可
            issue_wait = 0; // 清零准入许可等待计数
            while (!issue_ready && (issue_wait < 8)) begin @(negedge clk); issue_wait = issue_wait + 1; end // 保持请求稳定直到准入流水返回 ready
            if (!issue_ready) $fatal(1, "associative source transaction was not accepted"); // 要求存在容量时在有界周期内接受事务
            @(negedge clk); issue_valid = 1'b0; // 完成单周期事务请求
            @(negedge clk); // 等待一级源事务分配流水占用目标保留槽
        end // 结束新事务握手
    endtask // 结束 issue_one
    task automatic source_commit_one(input [63:0] transaction_id, input [15:0] epoch_value); // 返回一条源端提交确认
        begin // 开始确认脉冲
            @(negedge clk); source_commit_id = transaction_id; source_commit_epoch = epoch_value; source_commit_valid = 1'b1; // 驱动确认身份
            @(negedge clk); source_commit_valid = 1'b0; // 结束确认脉冲
        end // 结束确认发送
    endtask // 结束 source_commit_one
    task automatic history_commit_one(input [63:0] transaction_id, input [14:0] source_domain_value, input [15:0] epoch_value); // 提交一条预期接受的目的端身份
        begin // 开始目的端提交握手
            @(negedge clk); history_id = transaction_id; history_source_domain = source_domain_value; history_epoch = epoch_value; history_commit_valid = 1'b1; #0.1; // 驱动完整提交身份
            if (!history_commit_ready) $fatal(1, "associative destination history unexpectedly backpressured"); // 要求存在容量或重复匹配时接受
            @(negedge clk); history_commit_valid = 1'b0; // 完成单周期提交事件
        end // 结束目的端提交握手
    endtask // 结束 history_commit_one
    initial begin // 执行编解码、碰撞、换路和 exact-once 测试
        clk = 1'b0; rst_n = 1'b0; issue_valid = 1'b0; issue_id = 64'd0; issue_epoch = 16'd0; issue_timeout = 16'd200; // 初始化源事务输入
        send_ready = 1'b1; source_commit_valid = 1'b0; source_commit_id = 64'd0; source_commit_epoch = 16'd0; source_commit_status = `KDL_GLOBAL_STATUS_COMMITTED; // 初始化发送和确认接口
        route_reset = 1'b0; route_epoch = 16'h0201; // 初始化路由软复位接口
        history_commit_valid = 1'b0; history_source_domain = 15'd0; history_destination_domain = 15'h1234; // 初始化目的端域身份
        history_source_node = 5'd2; history_destination_node = 5'd29; history_epoch = 16'h0200; history_id = 64'd0; // 初始化目的端节点和事务身份
        codec_source_domain = 15'h5555; codec_destination_domain = 15'h2aaa; codec_source_node = 5'h15; codec_destination_node = 5'h0a; // 初始化提交 codec 互补地址
        codec_epoch = 16'ha55a; codec_id = 64'h0123_4567_89ab_cdef; codec_status = `KDL_GLOBAL_STATUS_COMMITTED; decoder_payload = 512'd0; // 初始化提交 codec 事务字段
        send_count = 0; completion_count = 0; delivery_count = 0; ack_count = 0; // 清零事件计数
        repeat (3) @(negedge clk); rst_n = 1'b1; #0.1; // 释放硬复位
        decoder_payload = codec_payload; #0.1; // 将编码 payload 送入独立解码器
        if (!decoder_valid || {decoded_status, decoded_id, decoded_epoch, decoded_destination_node, decoded_source_node, decoded_destination_domain, decoded_source_domain} != codec_payload[121:0] || codec_payload[511:122] != 390'd0) $fatal(1, "schema-4 global commit codec mismatch"); // 要求提交字段位级往返且保留位恒零
        codec_source_domain = 15'h7fff; codec_destination_domain = 15'h7fff; codec_source_node = 5'h1f; codec_destination_node = 5'h1f; codec_epoch = 16'hffff; codec_id = 64'hffff_ffff_ffff_ffff; codec_status = 2'b10; #0.1; // 驱动提交 codec 全字段高电平和合法状态二
        decoder_payload = codec_payload; #0.1; // 将全位 payload 送入解码器形成上升翻转
        if (!decoder_valid || decoded_id != 64'hffff_ffff_ffff_ffff || decoded_status != 2'b10) $fatal(1, "schema-4 global commit all-one vector mismatch"); // 要求全宽字段无截断
        codec_status = 2'b01; #0.1; decoder_payload = codec_payload; #0.1; // 独立翻转状态低位并保持合法编码
        if (!decoder_valid || decoded_status != 2'b01) $fatal(1, "schema-4 global commit alternate status mismatch"); // 要求两个合法非提交状态均可编解码
        codec_source_domain = 15'd0; codec_destination_domain = 15'd0; codec_source_node = 5'd0; codec_destination_node = 5'd0; codec_epoch = 16'd0; codec_id = 64'd0; codec_status = 2'b00; #0.1; // 将全部提交字段回落为零
        decoder_payload = codec_payload; #0.1; // 将全零 payload 送入解码器形成下降翻转
        if (!decoder_valid || codec_payload[121:0] != 122'd0) $fatal(1, "schema-4 global commit zero vector mismatch"); // 要求全零合法向量完整往返
        decoder_payload[511] = 1'b1; #0.1; // 注入非零保留位
        if (decoder_valid) $fatal(1, "schema-4 global commit reserved bit was accepted"); // 要求拒绝非零保留位
        for (index = 0; index < 20; index = index + 1) issue_one(64'h1000_0000_0000_0000 | ({56'd0, index[7:0]} << 4), 16'h0200); // 签发二十条低四位完全相同的并发事务
        if (outstanding_count != 9'd20 || source_overflow) $fatal(1, "source transaction window did not exceed legacy sixteen-slot limit"); // 要求二十条事务全部保留
        watchdog = 0; while ((send_count < 20) && (watchdog < 80)) begin @(negedge clk); watchdog = watchdog + 1; end // 等待全部首次发送命令
        if (send_count != 20) $fatal(1, "not all associative source transactions were sent"); // 要求无低位碰撞丢失
        for (index = 19; index >= 0; index = index - 1) source_commit_one(64'h1000_0000_0000_0000 | ({56'd0, index[7:0]} << 4), 16'h0200); // 逆序完成全部并发事务
        repeat (2) @(negedge clk); // 等待最后完成计数传播
        if (outstanding_count != 9'd0 || completion_count != 20 || source_protocol_error) $fatal(1, "out-of-order associative source completion failed"); // 要求二十条精确完成
        issue_id = 64'h1000_0000_0000_0000; issue_epoch = 16'h0200; issue_valid = 1'b1; repeat (3) @(negedge clk); #0.1; // 保持请求覆盖准入流水并尝试立即复用刚完成事务标识
        if (issue_ready) $fatal(1, "completed source transaction identity bypassed replay grace"); // 要求相同标识受保护
        issue_valid = 1'b0; repeat (10) @(negedge clk); // 等待源端复用保护期结束
        issue_one(64'h2000_0000_0000_0000, 16'h0200); // 签发换路测试事务
        watchdog = 0; while ((!send_valid || (send_id != 64'h2000_0000_0000_0000)) && (watchdog < 40)) begin @(negedge clk); watchdog = watchdog + 1; end // 等待换路测试首次发送
        @(negedge clk); route_reset = 1'b1; @(negedge clk); route_reset = 1'b0; // 触发不得丢事务的路由软复位
        watchdog = 0; while ((!send_valid || (send_id != 64'h2000_0000_0000_0000) || (send_epoch != 16'h0201) || (send_retry != 4'd1)) && (watchdog < 40)) begin @(negedge clk); watchdog = watchdog + 1; end // 等待新代次重发
        if (watchdog >= 40) $fatal(1, "route reset did not reissue transaction in new epoch"); // 要求换代重发成功
        source_commit_one(64'h2000_0000_0000_0000, 16'h0200); repeat (2) @(negedge clk); // 注入旧代次确认
        if (!source_protocol_error || outstanding_count != 9'd1) $fatal(1, "stale source commit completed rerouted transaction"); // 要求拒绝旧代次确认
        source_commit_one(64'h2000_0000_0000_0000, 16'h0201); repeat (2) @(negedge clk); // 返回新代次合法确认
        if (outstanding_count != 9'd0 || completion_id != 64'h2000_0000_0000_0000) $fatal(1, "rerouted source transaction did not complete"); // 要求新代次确认完成事务
        for (index = 0; index < 20; index = index + 1) begin // 使用逐位变化端点身份填满全部完成历史槽
            history_destination_domain = 15'h2aaa ^ index[14:0]; history_source_node = index[4:0]; history_destination_node = ~index[4:0]; // 翻转每条历史的源目的端点字段
            history_commit_one(64'haaaa_aaaa_aaaa_aaa0 ^ ({56'd0, index[7:0]} << 4), 15'h5555 ^ index[14:0], 16'ha55a); // 写入第一组高翻转事务身份
        end // 结束第一轮完成历史填充
        repeat (2) @(negedge clk); // 等待最后确认和交付计数
        if (delivery_count != 20 || ack_count != 20 || history_count != 9'd20) $fatal(1, "destination history did not exceed legacy sixteen-slot limit"); // 要求二十条均首次交付
        route_reset = 1'b1; @(negedge clk); route_reset = 1'b0; // 证明软复位不清除完成历史
        history_destination_domain = 15'h2aaa; history_source_node = 5'd0; history_destination_node = 5'h1f; // 恢复第一条完成历史的精确端点身份
        history_commit_one(64'haaaa_aaaa_aaaa_aaa0, 15'h5555, 16'h5aa5); repeat (2) @(negedge clk); // 以新代次重放第一条完成身份
        if (delivery_count != 20 || ack_count != 21 || !duplicate_seen || ack_epoch != 16'h5aa5 || ack_id != 64'haaaa_aaaa_aaaa_aaa0) $fatal(1, "cross-epoch destination duplicate suppression failed"); // 要求不重复交付但沿到达代次确认
        history_id = 64'h4000_0000_0000_0000; history_source_domain = 15'h4000; history_epoch = 16'h0301; history_commit_valid = 1'b1; #0.1; // 在保护期内尝试第二十一条身份
        if (history_commit_ready) $fatal(1, "full protected destination history accepted replacement"); // 要求满窗口反压新身份
        @(negedge clk); history_commit_valid = 1'b0; #0.1; // 完成溢出观测
        if (!history_overflow || deliver_id == 64'h4000_0000_0000_0000) $fatal(1, "destination history overflow was not isolated"); // 要求 sticky 报告且不交付
        repeat (105) @(negedge clk); // 等待全部完成历史达到可替换保护年龄
        for (index = 0; index < 20; index = index + 1) begin // 用互补身份覆盖全部历史槽以验证过期替换
            history_destination_domain = 15'h5555 ^ index[14:0]; history_source_node = ~index[4:0]; history_destination_node = index[4:0]; // 驱动与首轮互补的端点位图
            history_commit_one(64'h5555_5555_5555_5550 ^ ({56'd0, index[7:0]} << 4), 15'h2aaa ^ index[14:0], 16'h5aa5); // 写入第二组高翻转事务身份
        end // 结束全部过期历史替换
        repeat (2) @(negedge clk); // 等待最后一次交付与确认计数传播
        if (delivery_count != 40 || ack_count != 41 || deliver_id != (64'h5555_5555_5555_5550 ^ (64'd19 << 4))) $fatal(1, "expired destination history replacement failed"); // 要求全部保护期后槽恢复吞吐
        issue_timeout = 16'hffff; // 为第二轮源事务写入全位翻转超时门限
        for (index = 0; index < 20; index = index + 1) issue_one(64'hffff_ffff_ffff_fff0 ^ ({56'd0, index[7:0]} << 4), 16'hffff); // 用近全一身份再次覆盖全部源事务槽
        issue_id = 64'hffff_ffff_ffff_ffff; issue_epoch = 16'hffff; issue_valid = 1'b1; repeat (3) @(negedge clk); #0.1; // 保持请求覆盖准入流水并请求第二十一条非重复事务
        if (issue_ready) $fatal(1, "full source transaction window accepted a twenty-first transaction"); // 要求容量溢出时产生反压
        @(negedge clk); issue_valid = 1'b0; #0.1; // 提交一次满窗口溢出观测
        if (!source_overflow) $fatal(1, "source transaction overflow was not reported"); // 要求源窗口 sticky 报告容量不足
        repeat (300) @(negedge clk); // 令全部已发送事务的年龄低九位完成双向翻转
        send_ready = 1'b0; // 保留全部事务以统一推进重试计数
        for (index = 0; index < 16; index = index + 1) begin // 穷举四位重试计数并触发预算耗尽
            @(negedge clk); route_epoch = index[0] ? 16'ha55a : 16'h5aa5; route_reset = 1'b1; // 在互补代次间换路并递增全部活动槽重试数
            @(negedge clk); route_reset = 1'b0; // 结束当前单周期换路脉冲
        end // 结束重试计数覆盖序列
        repeat (2) @(negedge clk); #0.1; // 等待耗尽事件传播到 sticky 状态
        if (!retry_exhausted || outstanding_count != 9'd20) $fatal(1, "source retry exhaustion coverage sequence failed"); // 要求耗尽只报告错误而不静默释放事务
        source_commit_status = 2'b11; source_commit_one(64'hffff_ffff_ffff_fff0, 16'ha55a); // 注入身份匹配但状态未提交的非法确认
        source_commit_status = `KDL_GLOBAL_STATUS_COMMITTED; // 恢复合法全局提交状态
        for (index = 19; index >= 0; index = index - 1) source_commit_one(64'hffff_ffff_ffff_fff0 ^ ({56'd0, index[7:0]} << 4), 16'ha55a); // 完成全部已耗尽但仍保留的事务
        repeat (2) @(negedge clk); #0.1; // 等待最后完成与计数传播
        if (outstanding_count != 9'd0) $fatal(1, "exhausted source transactions were not explicitly completed"); // 要求只有合法提交才能释放保留项
        issue_id = 64'd0; issue_epoch = 16'd0; issue_timeout = 16'd0; issue_valid = 1'b1; source_commit_id = 64'd0; source_commit_epoch = 16'd0; route_epoch = 16'd0; repeat (3) @(negedge clk); #0.1; // 将全部宽输入回落并保持请求覆盖准入流水以检查零超时合同
        if (issue_ready) $fatal(1, "zero-timeout source transaction was accepted"); // 要求零超时请求永远不进入事务窗口
        @(negedge clk); issue_valid = 1'b0; source_commit_valid = 1'b0; // 结束最终输入边界刺激
        rst_n = 1'b0; repeat (2) @(negedge clk); // 最终硬复位验证全部易失槽回到安全零状态
        $display("TB_KDLINK_SCALE_TRANSACTION_PASS"); // 输出 manifest 约定的通过签名
        $finish; // 结束自校验仿真
    end // 结束主测试序列
endmodule // 结束 tb_kdlink_scale_transaction
