`timescale 1ns/1ps // 定义 KDSwitch congestion 测试时间单位
module tb_kdlink_switch32_congestion; // 定义单 slice 全端口拥塞与背压测试
    localparam integer FAIR_FLITS_PER_SOURCE = 4; // 固定公平性阶段每 source flit 数
    localparam integer DIRECTED_ROUNDS = 40; // 固定全 egress VC0 加全 VC 遍历轮数
    logic clk; // 生成一 GHz switch 时钟
    logic rst_n; // 生成低有效复位
    logic [31:0] ingress_valid_i; // 驱动三十二 ingress valid
    wire [31:0] ingress_ready_o; // 观察三十二 ingress ready
    logic [20479:0] ingress_flit_i; // 驱动三十二 ingress flit
    wire [31:0] egress_valid_o; // 观察三十二 egress valid
    logic [31:0] egress_ready_i; // 驱动三十二 egress ready
    wire [20479:0] egress_flit_o; // 观察三十二 egress flit
    wire [31:0] escape_pending_o; // 观察 escape pending
    wire protocol_error_o; // 观察 switch 错误
    integer test_phase; // 选择公平性、定向或空闲阶段
    integer directed_round; // 保存当前定向轮次和 destination
    integer directed_destination; // 保存当前定向 destination
    integer directed_vc; // 保存当前定向 VC
    integer drive_input; // 提供 ingress 索引
    integer check_output; // 提供 egress 索引
    integer accepted [0:31]; // 记录公平性阶段每 ingress 已接受数
    integer received [0:31]; // 记录公平性阶段每 ingress 已服务数
    logic [31:0] directed_accepted; // 记录当前轮已接受的 source
    logic [31:0] directed_seen; // 记录当前轮已输出的 source
    integer total_received; // 记录公平性阶段 egress 总服务数
    integer directed_received; // 记录定向阶段总服务数
    integer observed_source; // 保存输出 flit source
    integer expected_source; // 保存 round-robin 预期 source
    logic [639:0] expected_flit; // 保存 bit-exact 预期 flit
    logic [639:0] stalled_flit; // 保存背压期间稳定 flit
    logic stalled_flit_valid; // 标记已捕获背压队首
    kdlink_switch_slice32 u_dut ( // 实例化单 slice switch 数据面
        .clk_i(clk), .rst_n_i(rst_n), .ingress_valid_i(ingress_valid_i), .ingress_ready_o(ingress_ready_o), .ingress_flit_i(ingress_flit_i), // 连接 ingress
        .egress_valid_o(egress_valid_o), .egress_ready_i(egress_ready_i), .egress_flit_o(egress_flit_o), .escape_pending_o(escape_pending_o), .protocol_error_o(protocol_error_o) // 连接 egress 和状态
    ); // 结束单 slice switch 实例
    initial begin // 生成一 GHz 时钟
        clk = 1'b0; // 初始化时钟为低
        forever #0.5 clk = ~clk; // 生成一纳秒周期
    end // 结束时钟生成
    always @(*) begin // 按当前阶段构造三十二 ingress traffic
        ingress_valid_i = 32'd0; // 默认全部 ingress 无效
        ingress_flit_i = 20480'd0; // 默认全部 ingress flit 为零
        for (drive_input = 0; drive_input < 32; drive_input = drive_input + 1) begin // 构造每个 ingress flit
            if (test_phase == 0) begin // 处理全部 source 到 egress 零的公平性阶段
                if (accepted[drive_input] < FAIR_FLITS_PER_SOURCE) ingress_valid_i[drive_input] = 1'b1; // 未接受完整 burst 时持续声明有效
                ingress_flit_i[drive_input*640 +: 640] = {640{accepted[drive_input][0] ^ drive_input[0]}}; // 交替翻转完整 flit 数据
                ingress_flit_i[drive_input*640 +: 2] = accepted[drive_input][1:0]; // 写入每 source 局部序号
                ingress_flit_i[drive_input*640 + 16 +: 5] = drive_input[4:0]; // 写入 source identity
                ingress_flit_i[drive_input*640 + 525 +: 3] = drive_input[2:0]; // 将 traffic 分布到八 VC
                ingress_flit_i[drive_input*640 + 537 +: 5] = 5'd0; // 全部 traffic 路由到 egress 零
            end else if (test_phase == 1) begin // 处理全 egress 和全 VC 定向阶段
                ingress_valid_i[drive_input] = !directed_accepted[drive_input]; // 每 source 每轮仅接受一个 flit
                ingress_flit_i[drive_input*640 +: 640] = {640{directed_round[0] ^ drive_input[0]}}; // 对全宽 flit 产生双向翻转
                ingress_flit_i[drive_input*640 +: 16] = directed_round[15:0]; // 写入轮次 identity
                ingress_flit_i[drive_input*640 + 16 +: 5] = drive_input[4:0]; // 写入 source identity
                ingress_flit_i[drive_input*640 + 525 +: 3] = directed_vc[2:0]; // 选择 escape VC0 或全 VC 遍历值
                ingress_flit_i[drive_input*640 + 537 +: 5] = directed_destination[4:0]; // 每轮选择当前目标 egress
            end // 结束阶段化 traffic 构造
        end // 结束 ingress traffic 构造
    end // 结束 ingress traffic 组合驱动
    always @(posedge clk or negedge rst_n) begin // 更新公平性和 bit-exact scoreboard
        if (!rst_n) begin // 检测复位有效
            total_received = 0; // 清零公平性总接收数
            directed_received = 0; // 清零定向总接收数
            expected_source = 0; // round-robin 从 ingress 零开始
            directed_accepted = 32'd0; // 清零定向接受位图
            directed_seen = 32'd0; // 清零定向输出位图
            stalled_flit = 640'd0; // 清零背压参考 flit
            stalled_flit_valid = 1'b0; // 清除背压参考有效位
            for (drive_input = 0; drive_input < 32; drive_input = drive_input + 1) begin // 清零每 ingress 状态
                accepted[drive_input] = 0; // 清零本 ingress 接受数
                received[drive_input] = 0; // 清零本 ingress 服务数
            end // 结束 ingress 状态清零
        end else begin // 处理正常 traffic
            if (test_phase == 0) begin // 累计公平性阶段事件
                for (drive_input = 0; drive_input < 32; drive_input = drive_input + 1) begin // 累计各 ingress 接受事件
                    if (ingress_valid_i[drive_input] && ingress_ready_o[drive_input]) accepted[drive_input] = accepted[drive_input] + 1; // 推进本 ingress burst
                end // 结束 ingress 接受累计
                if (egress_valid_o[0] && egress_ready_i[0]) begin // 检查拥塞 egress 服务事件
                    observed_source = {27'd0, egress_flit_o[16 +: 5]}; // 提取服务 source identity
                    if (observed_source != expected_source) $fatal(1, "congestion fairness order mismatch expected=%0d observed=%0d total=%0d", expected_source, observed_source, total_received); // 要求严格 round-robin 服务
                    if (egress_flit_o[1:0] != received[observed_source][1:0]) $fatal(1, "congestion per-source order mismatch source=%0d", observed_source); // 检查每 source 局部顺序
                    if (egress_flit_o[525 +: 3] != observed_source[2:0]) $fatal(1, "congestion VC isolation mismatch source=%0d", observed_source); // 检查八 VC 字段保持
                    received[observed_source] = received[observed_source] + 1; // 累计本 source 服务数
                    total_received = total_received + 1; // 累计总服务数
                    expected_source = (expected_source + 1) & 31; // 推进严格 round-robin 预期 source
                end // 结束 egress 服务检查
            end else if (test_phase == 1) begin // 累计定向全端口事件
                for (drive_input = 0; drive_input < 32; drive_input = drive_input + 1) begin // 捕获本轮 ingress 接受事件
                    if (ingress_valid_i[drive_input] && ingress_ready_o[drive_input]) directed_accepted[drive_input] = 1'b1; // 标记本 source 已被接受
                end // 结束本轮接受捕获
                if (egress_valid_o[directed_destination] && !egress_ready_i[directed_destination]) begin // 检查背压期间队首保持稳定
                    if (!stalled_flit_valid) begin // 捕获首个阻塞队首
                        stalled_flit = egress_flit_o[directed_destination*640 +: 640]; // 保存阻塞队首 flit
                        stalled_flit_valid = 1'b1; // 标记参考 flit 有效
                    end else if (egress_flit_o[directed_destination*640 +: 640] !== stalled_flit) begin // 比较持续阻塞的数据稳定性
                        $fatal(1, "egress data changed under backpressure round=%0d", directed_round); // 报告 ready 低时数据变化
                    end // 结束背压稳定性检查
                end else if (egress_ready_i[directed_destination]) begin // ready 恢复后允许下轮重新捕获
                    stalled_flit_valid = 1'b0; // 清除背压参考有效位
                end // 结束背压状态维护
                for (check_output = 0; check_output < 32; check_output = check_output + 1) begin // 检查全部 egress 输出
                    if (egress_valid_o[check_output] && egress_ready_i[check_output]) begin // 捕获有效 output fire
                        if (check_output != directed_destination) $fatal(1, "unexpected egress output=%0d round=%0d", check_output, directed_round); // 要求 packet 只到指定 egress
                        observed_source = {27'd0, egress_flit_o[check_output*640 + 16 +: 5]}; // 提取 source identity
                        if (directed_seen[observed_source]) $fatal(1, "duplicate directed source=%0d round=%0d", observed_source, directed_round); // 禁止同轮重复输出
                        expected_flit = {640{directed_round[0] ^ observed_source[0]}}; // 重建全宽预期 flit
                        expected_flit[15:0] = directed_round[15:0]; // 重建轮次 identity
                        expected_flit[20:16] = observed_source[4:0]; // 重建 source identity
                        expected_flit[527:525] = directed_vc[2:0]; // 重建 VC identity
                        expected_flit[541:537] = directed_destination[4:0]; // 重建 destination identity
                        if (egress_flit_o[check_output*640 +: 640] !== expected_flit) $fatal(1, "directed bit-exact mismatch round=%0d source=%0d", directed_round, observed_source); // 检查完整六百四十位数据
                        directed_seen[observed_source] = 1'b1; // 标记本 source 已输出
                        directed_received = directed_received + 1; // 累计定向总服务数
                    end // 结束 output fire 检查
                end // 结束全部 egress 检查
            end // 结束阶段 scoreboard
        end // 结束正常 traffic
    end // 结束 scoreboard
    initial begin // 执行公平性、全 egress、全 VC 和背压测试
        rst_n = 1'b0; // 初始保持复位
        test_phase = 2; // 复位期间保持输入空闲
        directed_round = 0; // 初始化定向轮次
        directed_destination = 0; // 初始化定向 destination
        directed_vc = 0; // 初始化定向 VC
        egress_ready_i = 32'hFFFF_FFFF; // 配置全部 egress 持续接收
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; test_phase = 0; // 在下降沿释放复位并启动公平性流量
        wait (total_received == 32*FAIR_FLITS_PER_SOURCE); // 等待三十二 source 完成公平性流量
        @(negedge clk); test_phase = 2; // 停止公平性输入
        repeat (4) @(posedge clk); // 等待公平性流水排空
        for (drive_input = 0; drive_input < 32; drive_input = drive_input + 1) begin // 检查全部 source 最终服务数
            if (accepted[drive_input] != FAIR_FLITS_PER_SOURCE || received[drive_input] != FAIR_FLITS_PER_SOURCE) $fatal(1, "congestion count mismatch input=%0d accepted=%0d received=%0d", drive_input, accepted[drive_input], received[drive_input]); // 要求无丢包且有界公平
        end // 结束 source 计数检查
        for (directed_round = 0; directed_round < DIRECTED_ROUNDS; directed_round = directed_round + 1) begin // 遍历全部 VC0 destination 并补齐八 VC
            @(negedge clk); // 在安全边沿配置新一轮 traffic
            directed_destination = directed_round < 32 ? directed_round : directed_round - 32; // 前三十二轮遍历全部 egress，后八轮使用 egress 零到七
            directed_vc = directed_round < 32 ? 0 : directed_round - 32; // 前三十二轮固定 escape VC0，后八轮遍历全部 VC
            directed_accepted = 32'd0; // 清除本轮 source 接受位图
            directed_seen = 32'd0; // 清除本轮 source 输出位图
            stalled_flit_valid = 1'b0; // 清除背压队首参考
            egress_ready_i = 32'hFFFF_FFFF; // 默认全部 egress 可接收
            egress_ready_i[directed_destination] = 1'b0; // 阻塞当前目标以填充 egress FIFO
            test_phase = 1; // 启动当前轮三十二 source 拥塞流量
            wait (directed_accepted == 32'hFFFF_FFFF); // 等待全部 source 被 VOQ 接受
            wait (egress_valid_o[directed_destination]); // 等待目标 egress 出现有效队首
            repeat (8) @(posedge clk); // 保持背压使 FIFO 达到 near-full/full 并阻塞 matching
            @(negedge clk); egress_ready_i[directed_destination] = 1'b1; // 释放目标 egress 并排空全部 VOQ
            wait (directed_received == (directed_round + 1)*32); // 等待本轮三十二 flit 全部输出
            @(negedge clk); test_phase = 2; // 轮间停止新输入
            repeat (3) @(posedge clk); // 等待在途 crossbar 和 egress 状态清空
            if (directed_seen != 32'hFFFF_FFFF) $fatal(1, "directed source coverage incomplete round=%0d seen=%h", directed_round, directed_seen); // 检查本轮无丢包
        end // 结束全 destination 遍历
        if (protocol_error_o) $fatal(1, "congestion protocol error"); // 要求内部不变量无错误
        $display("TB_KDLINK_SWITCH32_CONGESTION_PASS sources=32 fairness_flits=%0d directed_flits=%0d egresses=32 escape_pairs=1024 vcs=8 backpressure=1 bit_exact=640 loss=0", 32*FAIR_FLITS_PER_SOURCE, directed_received); // 报告全端口测试结果
        $finish; // 结束测试
    end // 结束主测试流程
    initial begin // 设置仿真超时
        #20000; // 等待最大测试时长
        $fatal(1, "KDLink switch32 congestion timeout"); // 超时失败
    end // 结束超时保护
endmodule // 结束 congestion 测试
