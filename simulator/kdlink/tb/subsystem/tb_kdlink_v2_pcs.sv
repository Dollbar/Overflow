`timescale 1ns/1ps // 定义数字 PCS 端到端测试时间单位
module tb_kdlink_v2_pcs; // 定义训练、marker、扰码和失锁自校验测试
    localparam integer DATA_FLITS = 1000; // 固定连续 data flit 测量数量
    logic clk; // 生成一 GHz PCS 时钟
    logic rst_n; // 生成低有效复位
    logic tx_flit_valid_i; // 驱动 TX logical flit valid
    logic [639:0] tx_flit_i; // 驱动 TX logical flit
    logic tx_training_i; // 驱动 training control
    logic tx_alignment_marker_i; // 驱动 alignment marker
    logic [15:0] tx_marker_sequence_i; // 驱动 marker sequence
    wire tx_blocks_valid_o; // 观察 TX block group valid
    wire [659:0] tx_blocks_o; // 观察 TX block group
    logic fault_inject; // 控制单 lane sync header fault
    wire [9:0] rx_lane_valid_i; // 连接 RX lane valid
    wire [659:0] rx_lane_blocks_i; // 连接可能故障的 RX lane blocks
    wire rx_flit_valid_o; // 观察恢复 flit valid
    wire [639:0] rx_flit_o; // 观察恢复 logical flit
    wire rx_block_lock_o; // 观察 block lock
    wire rx_deskew_locked_o; // 观察 deskew lock
    wire rx_block_error_o; // 观察 block error
    wire rx_deskew_overflow_o; // 观察 deskew overflow
    integer send_flit; // 提供 data flit 序号
    integer received_flits; // 统计恢复 data flit
    integer bubbles; // 统计恢复流启动后的气泡
    logic data_stream_started; // 标记恢复 data 流已经启动
    logic block_error_seen; // 记录 fault 是否触发 block error
    assign rx_lane_valid_i = {10{tx_blocks_valid_o}}; // 无偏斜 loopback 时十 lane 同拍有效
    assign rx_lane_blocks_i = fault_inject ? (tx_blocks_o ^ (660'd3 << (3*66))) : tx_blocks_o; // 在 lane 三 sync header 注入两 bit fault
    kdlink_v2_pcs u_dut ( // 实例化全双工数字 PCS
        .clk_i(clk), .rst_n_i(rst_n), .tx_flit_valid_i(tx_flit_valid_i), .tx_flit_i(tx_flit_i), .tx_training_i(tx_training_i), .tx_alignment_marker_i(tx_alignment_marker_i), .tx_marker_sequence_i(tx_marker_sequence_i), // 连接 TX logical 和 control
        .tx_blocks_valid_o(tx_blocks_valid_o), .tx_blocks_o(tx_blocks_o), .rx_lane_valid_i(rx_lane_valid_i), .rx_lane_blocks_i(rx_lane_blocks_i), // loopback TX blocks 到 RX lanes
        .rx_flit_valid_o(rx_flit_valid_o), .rx_flit_o(rx_flit_o), .rx_block_lock_o(rx_block_lock_o), .rx_deskew_locked_o(rx_deskew_locked_o), .rx_block_error_o(rx_block_error_o), .rx_deskew_overflow_o(rx_deskew_overflow_o) // 连接恢复数据和 PCS 状态
    ); // 结束 PCS 实例
    initial begin // 生成一 GHz PCS 时钟
        clk = 1'b0; // 初始化时钟为低
        forever #0.5 clk = ~clk; // 生成一纳秒周期
    end // 结束时钟生成
    always @(posedge clk or negedge rst_n) begin // 检查恢复 flit 和 fault 状态
        if (!rst_n) begin // 检测复位有效
            received_flits = 0; // 清零恢复 flit 计数
            bubbles = 0; // 清零气泡计数
            data_stream_started = 1'b0; // 清除 data 流启动标志
            block_error_seen = 1'b0; // 清除 block error 记录
        end else begin // 处理正常 PCS 输出检查
            if (rx_block_error_o) block_error_seen = 1'b1; // 记录 block error 脉冲
            if (rx_flit_valid_o && (received_flits < DATA_FLITS)) begin // 检查测量窗口内恢复 data flit
                data_stream_started = 1'b1; // 标记恢复 data 流启动
                if (rx_flit_o[31:0] != received_flits[31:0]) $fatal(1, "PCS data sequence mismatch expected=%0d observed=%0d", received_flits, rx_flit_o[31:0]); // 检查扰码往返 bit-exact
                if (rx_flit_o[639:608] != (32'hA500_0000 | received_flits[31:0])) $fatal(1, "PCS upper data mismatch flit=%0d", received_flits); // 检查最高 lane bit ordering
                received_flits = received_flits + 1; // 累计恢复 flit
            end else if (data_stream_started && received_flits < DATA_FLITS) begin // 检查启动后的 data 气泡
                bubbles = bubbles + 1; // 累计 data 气泡
            end // 结束 data flit 检查
        end // 结束正常 PCS 输出检查
    end // 结束 PCS scoreboard
    initial begin // 执行 training、alignment、data 和 fault 流程
        rst_n = 1'b0; // 初始保持复位
        tx_flit_valid_i = 1'b0; // 初始清除 TX flit valid
        tx_flit_i = 640'd0; // 初始清零 TX flit
        tx_training_i = 1'b0; // 初始关闭 training
        tx_alignment_marker_i = 1'b0; // 初始关闭 marker
        tx_marker_sequence_i = 16'h1234; // 配置固定 marker sequence
        fault_inject = 1'b0; // 初始关闭 fault injection
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        repeat (16) begin // 发送十六组训练 control block
            @(negedge clk); tx_training_i = 1'b1; tx_alignment_marker_i = 1'b0; tx_flit_valid_i = 1'b0; // 驱动一组训练 block
        end // 结束训练序列
        @(negedge clk); tx_training_i = 1'b0; tx_alignment_marker_i = 1'b1; // 发送 alignment marker
        for (send_flit = 0; send_flit < DATA_FLITS; send_flit = send_flit + 1) begin // 连续发送 logical data flit
            @(negedge clk); // 在下降沿更新 logical flit
            tx_alignment_marker_i = 1'b0; // 结束 marker control
            tx_flit_valid_i = 1'b1; // 持续声明 logical flit 有效
            tx_flit_i = {640{send_flit[0]}}; // 交替驱动完整 logical flit 覆盖全部 PCS 数据位
            tx_flit_i[31:0] = send_flit[31:0]; // 写入低 lane sequence
            tx_flit_i[639:608] = 32'hA500_0000 | send_flit[31:0]; // 写入最高 lane sequence
        end // 结束连续 data 流
        @(negedge clk); tx_flit_valid_i = 1'b0; // 停止正常 data 流
        wait (received_flits == DATA_FLITS); // 等待全部正常 data 恢复
        if (!rx_block_lock_o || !rx_deskew_locked_o || rx_deskew_overflow_o || bubbles != 0) $fatal(1, "PCS lock/performance failure block=%b deskew=%b overflow=%b bubbles=%0d", rx_block_lock_o, rx_deskew_locked_o, rx_deskew_overflow_o, bubbles); // 检查训练、deskew 和 II 一
        @(negedge clk); tx_flit_valid_i = 1'b1; tx_flit_i[31:0] = DATA_FLITS; tx_flit_i[639:608] = 32'hA500_0000 | DATA_FLITS; fault_inject = 1'b1; // 发送一个 sync header 故障 data group
        @(negedge clk); tx_flit_valid_i = 1'b0; fault_inject = 1'b1; // 保持 fault 覆盖 TX 注册输出周期
        @(negedge clk); fault_inject = 1'b0; // 结束 fault injection
        repeat (6) @(posedge clk); #0.01; // 等待 RX fault 状态传播
        if (!block_error_seen || rx_block_lock_o || rx_deskew_locked_o) $fatal(1, "PCS fault did not force loss of lock error=%b block=%b deskew=%b", block_error_seen, rx_block_lock_o, rx_deskew_locked_o); // 要求故障触发失锁
        $display("TB_KDLINK_V2_PCS_PASS training_groups=16 marker=1 data_flits=%0d blocks_per_flit=10 encoded_bits_per_cycle=660 bubbles=0 scramble_roundtrip=1 fault_loss_of_lock=1", DATA_FLITS); // 报告 K6 PCS 验收结果
        $finish; // 结束测试
    end // 结束主测试流程
    initial begin // 设置仿真超时
        #3000; // 等待最大测试时长
        $fatal(1, "KDLink-v2 PCS timeout"); // 超时失败
    end // 结束超时保护
endmodule // 结束 PCS 端到端测试
