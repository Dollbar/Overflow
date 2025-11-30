`timescale 1ns/1ps // 定义 replay buffer 测试时间单位
module tb_kdlink_v2_replay_buffer; // 定义多 flit、背压和 retry 边界测试
    logic clk; // 生成一 GHz replay 时钟
    logic rst_n; // 生成低有效复位
    logic store_start_i; // 驱动新 packet 开始
    logic store_valid_i; // 驱动 packet body 有效
    logic [607:0] store_body_i; // 驱动六百零八位 packet body
    logic store_last_i; // 驱动 packet 尾部
    wire store_ready_o; // 观察 replay 窗口接收能力
    logic ack_valid_i; // 驱动精确 ACK
    logic [11:0] ack_collective_id_i; // 驱动 ACK collective identity
    logic ack_phase_i; // 驱动 ACK phase identity
    logic [11:0] ack_packet_seq_i; // 驱动 ACK packet sequence
    logic nack_valid_i; // 驱动精确 NACK
    logic [11:0] nack_collective_id_i; // 驱动 NACK collective identity
    logic nack_phase_i; // 驱动 NACK phase identity
    logic [11:0] nack_packet_seq_i; // 驱动 NACK packet sequence
    wire replay_valid_o; // 观察 replay flit 有效
    logic replay_ready_i; // 驱动 replay sink 接收能力
    wire [607:0] replay_body_o; // 观察修改协议字段后的 replay body
    wire replay_last_o; // 观察 replay packet 尾部
    wire retry_exhausted_o; // 观察 retry 上限脉冲
    wire [3:0] occupancy_o; // 观察 replay entry occupancy
    integer flit_index; // 提供十六 flit packet 索引
    integer retry_index; // 提供 retry 次数索引
    integer entry_index; // 提供 replay entry 索引
    integer reuse_pass; // 提供 replay entry 复用轮次
    integer reuse_flits; // 保存当前复用 packet flit 数
    integer replay_checked; // 统计已 bit-exact 检查的 replay flit
    integer expected_index; // 保存当前预期 replay flit 索引
    integer exhausted_seen; // 统计 retry exhausted 脉冲
    logic [607:0] expected_replay; // 保存当前 bit-exact 预期 replay body
    logic [607:0] held_replay; // 保存背压期间 replay body
    logic held_replay_valid; // 标记已捕获背压参考 body
    kdlink_v2_replay_buffer u_dut ( // 实例化单 slice replay buffer
        .clk_i(clk), .rst_n_i(rst_n), .store_start_i(store_start_i), .store_valid_i(store_valid_i), .store_body_i(store_body_i), .store_last_i(store_last_i), .store_ready_o(store_ready_o), // 连接 store 通路
        .ack_valid_i(ack_valid_i), .ack_collective_id_i(ack_collective_id_i), .ack_phase_i(ack_phase_i), .ack_packet_seq_i(ack_packet_seq_i), // 连接 ACK 通路
        .nack_valid_i(nack_valid_i), .nack_collective_id_i(nack_collective_id_i), .nack_phase_i(nack_phase_i), .nack_packet_seq_i(nack_packet_seq_i), // 连接 NACK 通路
        .replay_valid_o(replay_valid_o), .replay_ready_i(replay_ready_i), .replay_body_o(replay_body_o), .replay_last_o(replay_last_o), .retry_exhausted_o(retry_exhausted_o), .occupancy_o(occupancy_o) // 连接 replay 输出和状态
    ); // 结束 replay buffer 实例
    initial begin // 生成一 GHz 时钟
        clk = 1'b0; // 初始化时钟为低
        forever #0.5 clk = ~clk; // 生成一纳秒周期
    end // 结束时钟生成
    always @(negedge clk or negedge rst_n) begin // 检查 replay bit-exact 数据与背压稳定性
        if (!rst_n) begin // 检测复位有效
            replay_checked = 0; // 清零 replay flit 计数
            exhausted_seen = 0; // 清零 exhausted 脉冲计数
            held_replay = 608'd0; // 清零背压参考 body
            held_replay_valid = 1'b0; // 清除背压参考有效位
        end else begin // 处理正常 replay 输出检查
            if (retry_exhausted_o) exhausted_seen = exhausted_seen + 1; // 累计 retry 上限脉冲
            if (replay_valid_o && !replay_ready_i) begin // 检查 replay sink 背压状态
                if (!held_replay_valid) begin // 捕获首个阻塞 body
                    held_replay = replay_body_o; // 保存阻塞期间参考 body
                    held_replay_valid = 1'b1; // 标记背压参考有效
                end else if (replay_body_o !== held_replay) begin // 检查持续阻塞的数据稳定性
                    $fatal(1, "replay body changed under backpressure"); // 报告 replay ready 低时数据变化
                end // 结束背压稳定性捕获
            end // 结束背压状态检查
            if (replay_valid_o && replay_ready_i) begin // 检查 replay output fire
                expected_index = replay_checked & 15; // 计算当前十六 flit packet 内索引
                expected_replay = {608{expected_index[0]}}; // 重建原始全宽交替 body
                expected_replay[569:558] = 12'hA5A; // 重建 collective identity
                expected_replay[528] = 1'b1; // 重建 phase identity
                expected_replay[593:582] = 12'h5A5; // 重建 packet sequence
                expected_replay[527:525] = 3'd6; // 应用 replay VC 修改
                expected_replay[531] = 1'b1; // 应用 retry 标志修改
                if (replay_body_o !== expected_replay) $fatal(1, "replay bit-exact mismatch retry_flit=%0d", replay_checked); // 检查完整六百零八位 replay body
                if (replay_last_o != (expected_index == 15)) $fatal(1, "replay last mismatch index=%0d last=%b", expected_index, replay_last_o); // 检查 packet 尾部位置
                replay_checked = replay_checked + 1; // 推进 replay flit 计数
                held_replay_valid = 1'b0; // 消费后清除背压参考状态
            end // 结束 replay output fire 检查
        end // 结束正常 replay 输出检查
    end // 结束 replay scoreboard
    initial begin // 执行完整 replay 操作矩阵
        rst_n = 1'b0; // 初始保持复位有效
        store_start_i = 1'b0; // 初始清除 store start
        store_valid_i = 1'b0; // 初始清除 store valid
        store_body_i = 608'd0; // 初始清零 store body
        store_last_i = 1'b0; // 初始清除 store last
        ack_valid_i = 1'b0; // 初始清除 ACK valid
        ack_collective_id_i = 12'd0; // 初始清零 ACK collective identity
        ack_phase_i = 1'b0; // 初始清零 ACK phase
        ack_packet_seq_i = 12'd0; // 初始清零 ACK sequence
        nack_valid_i = 1'b0; // 初始清除 NACK valid
        nack_collective_id_i = 12'd0; // 初始清零 NACK collective identity
        nack_phase_i = 1'b0; // 初始清零 NACK phase
        nack_packet_seq_i = 12'd0; // 初始清零 NACK sequence
        replay_ready_i = 1'b1; // 初始允许 replay 输出
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        for (flit_index = 0; flit_index < 16; flit_index = flit_index + 1) begin // 连续存储十六 flit packet
            @(negedge clk); // 在下降沿更新 store body
            if (!store_ready_o) $fatal(1, "replay store unexpectedly blocked flit=%0d", flit_index); // 要求新 packet 可连续写入
            store_start_i = flit_index == 0; // 仅首 flit 声明 packet start
            store_valid_i = 1'b1; // 保持十六 flit 连续有效
            store_body_i = {608{flit_index[0]}}; // 产生全宽双向翻转 body
            store_body_i[569:558] = 12'hA5A; // 写入 collective identity
            store_body_i[528] = 1'b1; // 写入 phase identity
            store_body_i[593:582] = 12'h5A5; // 写入 packet sequence
            store_last_i = flit_index == 15; // 仅第十六 flit声明 packet last
        end // 结束十六 flit packet store
        @(negedge clk); store_start_i = 1'b0; store_valid_i = 1'b0; store_last_i = 1'b0; // 结束 packet store
        #0.01; if (occupancy_o != 4'd1) $fatal(1, "replay occupancy after store=%0d", occupancy_o); // 检查 packet entry 已占用
        ack_valid_i = 1'b1; ack_collective_id_i = 12'h5A5; ack_phase_i = 1'b0; ack_packet_seq_i = 12'hA5A; // 发送不匹配 ACK identity
        @(negedge clk); ack_valid_i = 1'b0; // 结束 ACK miss 脉冲
        #0.01; if (occupancy_o != 4'd1) $fatal(1, "ACK miss released replay entry"); // 要求 ACK miss 不释放 entry
        nack_valid_i = 1'b1; nack_collective_id_i = 12'hFFF; nack_phase_i = 1'b0; nack_packet_seq_i = 12'h000; // 发送不匹配 NACK identity
        @(negedge clk); nack_valid_i = 1'b0; // 结束 NACK miss 脉冲
        repeat (3) @(negedge clk); // 等待可能的错误 replay 输出
        if (replay_valid_o) $fatal(1, "NACK miss started replay"); // 要求 NACK miss 不启动 replay
        nack_collective_id_i = 12'hA5A; nack_phase_i = 1'b1; nack_packet_seq_i = 12'h5A5; // 配置匹配 NACK identity
        for (retry_index = 0; retry_index < 7; retry_index = retry_index + 1) begin // 执行七次允许的 packet replay
            replay_ready_i = retry_index != 0; // 第一次 replay 先施加输出背压
            @(negedge clk); nack_valid_i = 1'b1; // 发出单周期精确 NACK
            @(negedge clk); nack_valid_i = 1'b0; // 结束精确 NACK 脉冲
            if (retry_index == 0) begin // 对第一次 replay 检查输出保持
                wait (replay_valid_o); // 等待首 replay flit 到达输出寄存器
                repeat (4) @(negedge clk); // 保持四周期 replay backpressure
                replay_ready_i = 1'b1; // 释放 replay sink
            end // 结束第一次 replay 背压处理
            wait (replay_checked == (retry_index + 1)*16); // 等待当前十六 flit 全部 bit-exact 提交
            wait (!replay_valid_o); // 等待 replay 输出寄存器回到空闲
        end // 结束七次允许的 replay
        @(negedge clk); nack_valid_i = 1'b1; // 第八次发送匹配 NACK
        @(negedge clk); nack_valid_i = 1'b0; // 结束第八次 NACK 脉冲
        #0.01; if (!retry_exhausted_o || replay_valid_o) $fatal(1, "eighth NACK did not exhaust retry limit"); // 要求上限脉冲且禁止第八次 replay
        @(negedge clk); // 等待 exhausted 脉冲结束
        if (retry_exhausted_o || exhausted_seen != 1) $fatal(1, "retry exhausted pulse width/count mismatch count=%0d", exhausted_seen); // 检查单周期 exhausted 语义
        ack_valid_i = 1'b1; ack_collective_id_i = 12'hA5A; ack_phase_i = 1'b1; ack_packet_seq_i = 12'h5A5; // 发送匹配 ACK 释放多 flit entry
        @(negedge clk); ack_valid_i = 1'b0; // 结束匹配 ACK 脉冲
        #0.01; if (occupancy_o != 4'd0) $fatal(1, "matching ACK did not release replay entry"); // 检查 entry 已释放
        for (entry_index = 0; entry_index < 8; entry_index = entry_index + 1) begin // 填满全部八个 replay entries
            @(negedge clk); // 在下降沿配置单 flit packet
            if (!store_ready_o) $fatal(1, "replay window filled early entry=%0d", entry_index); // 要求八个 entry 均可分配
            store_start_i = 1'b1; store_valid_i = 1'b1; store_last_i = 1'b1; // 构造单 flit 完整 packet
            store_body_i = {608{entry_index[0]}}; // 对全部 body 位产生双向翻转
            store_body_i[569:558] = entry_index[0] ? 12'hFFF : 12'h000; // 交替翻转 collective identity 全部位
            store_body_i[528] = entry_index[0]; // 交替翻转 phase identity
            store_body_i[593:582] = entry_index[11:0]; // 写入唯一 packet sequence
        end // 结束 replay 窗口填充
        @(negedge clk); store_start_i = 1'b0; store_valid_i = 1'b0; store_last_i = 1'b0; // 结束窗口填充流量
        #0.01; if (occupancy_o != 4'd8 || store_ready_o) $fatal(1, "replay window full mismatch occupancy=%0d ready=%b", occupancy_o, store_ready_o); // 检查 full 和 backpressure
        for (entry_index = 0; entry_index < 8; entry_index = entry_index + 1) begin // 逐项 ACK 释放完整窗口
            @(negedge clk); // 在下降沿配置精确 ACK
            ack_valid_i = 1'b1; // 声明 ACK valid
            ack_collective_id_i = entry_index[0] ? 12'hFFF : 12'h000; // 匹配交替 collective identity
            ack_phase_i = entry_index[0]; // 匹配交替 phase identity
            ack_packet_seq_i = entry_index[11:0]; // 匹配唯一 packet sequence
            @(negedge clk); ack_valid_i = 1'b0; // 结束当前 ACK 脉冲
        end // 结束完整窗口释放
        #0.01; if (occupancy_o != 4'd0 || !store_ready_o) $fatal(1, "replay window did not drain occupancy=%0d ready=%b", occupancy_o, store_ready_o); // 检查窗口完全释放
        for (reuse_pass = 0; reuse_pass < 5; reuse_pass = reuse_pass + 1) begin // 以多种 packet 长度复用全部八个 entry
            case (reuse_pass) // 选择覆盖 flit_count 每一位的 packet 长度
                0: reuse_flits = 2; // 首轮写入二 flit packet
                1: reuse_flits = 4; // 第二轮写入四 flit packet
                2: reuse_flits = 8; // 第三轮写入八 flit packet
                3: reuse_flits = 16; // 第四轮写入十六 flit packet
                default: reuse_flits = 1; // 最后一轮回到单 flit packet形成反向翻转
            endcase // 结束复用 packet 长度选择
            for (entry_index = 0; entry_index < 8; entry_index = entry_index + 1) begin // 填充当前复用轮全部 entries
                for (flit_index = 0; flit_index < reuse_flits; flit_index = flit_index + 1) begin // 连续写入当前 packet
                    @(negedge clk); // 在下降沿配置复用 store body
                    if (!store_ready_o) $fatal(1, "replay reuse blocked pass=%0d entry=%0d flit=%0d", reuse_pass, entry_index, flit_index); // 要求 packet 内和窗口内持续可写
                    store_start_i = flit_index == 0; // 仅首 flit 声明新 packet
                    store_valid_i = 1'b1; // 声明当前复用 body 有效
                    store_last_i = flit_index == reuse_flits-1; // 在当前长度尾部结束 packet
                    store_body_i = {608{reuse_pass[0] ^ entry_index[0] ^ flit_index[0]}}; // 产生 entry 复用全宽翻转
                    store_body_i[569:558] = (reuse_pass[0] ^ entry_index[0]) ? 12'hFFF : 12'h000; // 双向翻转 collective identity
                    store_body_i[528] = reuse_pass[0] ^ entry_index[0]; // 双向翻转 phase identity
                    store_body_i[593:582] = reuse_pass[0] ? ~entry_index[11:0] : entry_index[11:0]; // 双向翻转并保持 packet identity 唯一
                end // 结束当前复用 packet store
            end // 结束当前复用窗口填充
            @(negedge clk); store_start_i = 1'b0; store_valid_i = 1'b0; store_last_i = 1'b0; // 结束当前复用窗口 store
            #0.01; if (occupancy_o != 4'd8 || store_ready_o) $fatal(1, "replay reuse window not full pass=%0d occupancy=%0d", reuse_pass, occupancy_o); // 检查全部 entry 已重新占用
            for (entry_index = 0; entry_index < 8; entry_index = entry_index + 1) begin // 精确 ACK 释放当前复用窗口
                @(negedge clk); // 在下降沿配置当前复用 ACK
                ack_valid_i = 1'b1; // 声明 ACK valid
                ack_collective_id_i = (reuse_pass[0] ^ entry_index[0]) ? 12'hFFF : 12'h000; // 匹配当前 collective identity
                ack_phase_i = reuse_pass[0] ^ entry_index[0]; // 匹配当前 phase identity
                ack_packet_seq_i = reuse_pass[0] ? ~entry_index[11:0] : entry_index[11:0]; // 匹配当前 packet identity
                @(negedge clk); ack_valid_i = 1'b0; // 结束当前复用 ACK
            end // 结束当前复用窗口释放
            #0.01; if (occupancy_o != 4'd0 || !store_ready_o) $fatal(1, "replay reuse window did not drain pass=%0d occupancy=%0d", reuse_pass, occupancy_o); // 检查当前复用窗口已排空
        end // 结束全部 entry 复用轮次
        for (entry_index = 0; entry_index < 3; entry_index = entry_index + 1) begin // 在空窗口翻转完整 NACK identity 并验证 miss
            @(negedge clk); // 在下降沿配置 NACK miss
            nack_valid_i = 1'b1; // 声明 NACK valid
            nack_collective_id_i = entry_index[0] ? 12'hFFF : 12'h000; // 双向翻转 NACK collective identity
            nack_phase_i = entry_index[0]; // 双向翻转 NACK phase identity
            nack_packet_seq_i = entry_index[0] ? 12'hFFF : 12'h000; // 双向翻转 NACK packet identity
            @(negedge clk); nack_valid_i = 1'b0; // 结束当前 NACK miss
            if (replay_valid_o || retry_exhausted_o) $fatal(1, "empty-window NACK miss changed replay state"); // 要求空窗口 NACK 无副作用
        end // 结束 NACK identity 翻转
        if (replay_checked != 7*16 || exhausted_seen != 1) $fatal(1, "replay final count mismatch flits=%0d exhausted=%0d", replay_checked, exhausted_seen); // 检查最终 replay 操作数量
        $display("TB_KDLINK_V2_REPLAY_BUFFER_PASS packet_flits=16 legal_retries=7 replay_flits=%0d backpressure=1 ack_miss=1 nack_miss=1 retry_exhausted=1 window_entries=8 reuse_lengths=2,4,8,16,1 bit_exact=608", replay_checked); // 报告 replay 测试结果
        $finish; // 结束测试
    end // 结束主 stimulus
    initial begin // 设置 replay 测试超时
        #5000; // 等待最大允许仿真时间
        $fatal(1, "KDLink-v2 replay buffer timeout"); // 超时报错避免仿真挂起
    end // 结束超时保护
endmodule // 结束 replay buffer 测试平台
