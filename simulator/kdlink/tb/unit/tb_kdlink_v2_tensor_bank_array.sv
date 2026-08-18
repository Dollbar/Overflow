`timescale 1ns/1ps // 定义十六 bank 带宽测试时间单位
module tb_kdlink_v2_tensor_bank_array; // 定义十六 bank 全双工连续流自校验测试
    localparam integer MEASURE_CYCLES = 10000; // 固定连续流测量周期数
    logic clk; // 生成一 GHz 测试时钟
    logic rst_n; // 生成低有效复位
    logic [15:0] source_valid_i; // 驱动十六 bank source valid
    wire [15:0] source_ready_o; // 观察十六 bank source ready
    logic [1535:0] source_header_i; // 驱动十六 bank source header
    logic [8191:0] source_data_i; // 驱动十六 bank source payload
    logic [111:0] source_bytes_i; // 驱动十六 bank source bytes
    wire [15:0] link_tx_valid_o; // 观察十六 slice TX valid
    logic [15:0] link_tx_ready_i; // 驱动十六 slice TX ready
    wire [1535:0] link_tx_header_o; // 观察十六 slice TX header
    wire [8191:0] link_tx_data_o; // 观察十六 slice TX payload
    wire [111:0] link_tx_bytes_o; // 观察十六 slice TX bytes
    logic [15:0] link_rx_valid_i; // 驱动十六 slice RX valid
    wire [15:0] link_rx_ready_o; // 观察十六 slice RX ready
    logic [1535:0] link_rx_header_i; // 驱动十六 slice RX header
    logic [8191:0] link_rx_data_i; // 驱动十六 slice RX payload
    logic [111:0] link_rx_bytes_i; // 驱动十六 slice RX bytes
    wire [15:0] result_valid_o; // 观察十六 bank result valid
    logic [15:0] result_ready_i; // 驱动十六 bank result ready
    wire [1535:0] result_header_o; // 观察十六 bank result header
    wire [8191:0] result_data_o; // 观察十六 bank result payload
    wire [111:0] result_bytes_o; // 观察十六 bank result bytes
    wire [15:0] source_stall_o; // 观察 source stall
    wire [15:0] result_stall_o; // 观察 result stall
    integer source_cycle; // 记录 source 激励周期
    integer drive_bank; // 提供激励 bank 索引
    integer check_bank; // 提供检查 bank 索引
    integer tx_seen [0:15]; // 记录每 bank TX flit 数
    integer rx_seen [0:15]; // 记录每 bank result flit 数
    integer tx_bubbles; // 统计启动后 TX 气泡
    integer rx_bubbles; // 统计启动后 result 气泡
    kdlink_v2_tensor_bank_array u_dut ( // 实例化十六 bank 聚合边界
        .clk_i(clk), .rst_n_i(rst_n), // 连接时钟和复位
        .source_valid_i(source_valid_i), .source_ready_o(source_ready_o), .source_header_i(source_header_i), .source_data_i(source_data_i), .source_bytes_i(source_bytes_i), // 连接 source banks
        .link_tx_valid_o(link_tx_valid_o), .link_tx_ready_i(link_tx_ready_i), .link_tx_header_o(link_tx_header_o), .link_tx_data_o(link_tx_data_o), .link_tx_bytes_o(link_tx_bytes_o), // 连接 link TX slices
        .link_rx_valid_i(link_rx_valid_i), .link_rx_ready_o(link_rx_ready_o), .link_rx_header_i(link_rx_header_i), .link_rx_data_i(link_rx_data_i), .link_rx_bytes_i(link_rx_bytes_i), // 连接 link RX slices
        .result_valid_o(result_valid_o), .result_ready_i(result_ready_i), .result_header_o(result_header_o), .result_data_o(result_data_o), .result_bytes_o(result_bytes_o), // 连接 result banks
        .source_stall_o(source_stall_o), .result_stall_o(result_stall_o) // 连接停顿观察信号
    ); // 结束十六 bank 实例
    initial begin // 生成一 GHz 时钟
        clk = 1'b0; // 初始化时钟为低
        forever #0.5 clk = ~clk; // 生成一纳秒周期
    end // 结束时钟生成
    always @(posedge clk or negedge rst_n) begin // 检查每 bank 双向连续流
        if (!rst_n) begin // 检测复位有效
            tx_bubbles = 0; // 清零 TX 气泡计数
            rx_bubbles = 0; // 清零 RX 气泡计数
            for (check_bank = 0; check_bank < 16; check_bank = check_bank + 1) begin // 清零每 bank scoreboard
                tx_seen[check_bank] = 0; // 清零本 bank TX 计数
                rx_seen[check_bank] = 0; // 清零本 bank result 计数
            end // 结束 scoreboard 清零
        end else begin // 处理正常输出检查
            for (check_bank = 0; check_bank < 16; check_bank = check_bank + 1) begin // 检查全部 bank
                if (link_tx_valid_o[check_bank]) begin // 检查本 bank TX 输出
                    if (link_tx_data_o[check_bank*512 +: 32] != tx_seen[check_bank][31:0]) $fatal(1, "TX data mismatch bank=%0d seen=%0d data=%0d", check_bank, tx_seen[check_bank], link_tx_data_o[check_bank*512 +: 32]); // 检查 TX payload 顺序
                    if (link_tx_header_o[check_bank*96 +: 16] != check_bank[15:0] || link_tx_bytes_o[check_bank*7 +: 7] != 7'd64) $fatal(1, "TX metadata mismatch bank=%0d", check_bank); // 检查 TX metadata
                    tx_seen[check_bank] = tx_seen[check_bank] + 1; // 累计本 bank TX flit
                end else if (tx_seen[check_bank] > 0 && tx_seen[check_bank] < MEASURE_CYCLES) begin // 检查启动后的 TX 气泡
                    tx_bubbles = tx_bubbles + 1; // 累计 TX 气泡
                end // 结束 TX 检查
                if (result_valid_o[check_bank]) begin // 检查本 bank result 输出
                    if (result_data_o[check_bank*512 +: 32] != (32'h8000_0000 | rx_seen[check_bank][31:0])) $fatal(1, "RX data mismatch bank=%0d seen=%0d data=%h", check_bank, rx_seen[check_bank], result_data_o[check_bank*512 +: 32]); // 检查 result payload 顺序
                    if (result_header_o[check_bank*96 +: 16] != check_bank[15:0] || result_bytes_o[check_bank*7 +: 7] != 7'd64) $fatal(1, "RX metadata mismatch bank=%0d", check_bank); // 检查 result metadata
                    rx_seen[check_bank] = rx_seen[check_bank] + 1; // 累计本 bank result flit
                end else if (rx_seen[check_bank] > 0 && rx_seen[check_bank] < MEASURE_CYCLES) begin // 检查启动后的 result 气泡
                    rx_bubbles = rx_bubbles + 1; // 累计 result 气泡
                end // 结束 result 检查
            end // 结束全部 bank 检查
        end // 结束正常输出检查
    end // 结束双向 scoreboard
    initial begin // 执行十六 bank 全双工带宽测试
        rst_n = 1'b0; // 初始保持复位
        source_valid_i = 16'd0; // 初始清除 source valid
        source_header_i = 1536'd0; // 初始清零 source header
        source_data_i = 8192'd0; // 初始清零 source payload
        source_bytes_i = {16{7'd64}}; // 配置全部 source 为完整 payload
        link_tx_ready_i = 16'hFFFF; // 配置全部 TX 下游持续接收
        link_rx_valid_i = 16'd0; // 初始清除 RX valid
        link_rx_header_i = 1536'd0; // 初始清零 RX header
        link_rx_data_i = 8192'd0; // 初始清零 RX payload
        link_rx_bytes_i = {16{7'd64}}; // 配置全部 RX 为完整 payload
        result_ready_i = 16'hFFFF; // 配置全部 result 持续接收
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        for (source_cycle = 0; source_cycle < MEASURE_CYCLES; source_cycle = source_cycle + 1) begin // 连续驱动固定测量窗口
            @(negedge clk); // 在下降沿更新输入
            source_valid_i = 16'hFFFF; // 全部 source bank 同拍有效
            link_rx_valid_i = 16'hFFFF; // 全部 RX slice 同拍有效
            source_header_i = 1536'd0; // 清零 source header 后重建 tag
            source_data_i = 8192'd0; // 清零 source payload 后重建序号
            link_rx_header_i = 1536'd0; // 清零 RX header 后重建 tag
            link_rx_data_i = 8192'd0; // 清零 RX payload 后重建序号
            for (drive_bank = 0; drive_bank < 16; drive_bank = drive_bank + 1) begin // 为全部 bank 构造独立数据
                source_header_i[drive_bank*96 +: 16] = drive_bank[15:0]; // 写入 source bank identity
                source_data_i[drive_bank*512 +: 32] = source_cycle[31:0]; // 写入 source 周期序号
                link_rx_header_i[drive_bank*96 +: 16] = drive_bank[15:0]; // 写入 RX bank identity
                link_rx_data_i[drive_bank*512 +: 32] = 32'h8000_0000 | source_cycle[31:0]; // 写入 RX 周期序号
            end // 结束全部 bank 数据构造
        end // 结束连续测量窗口
        @(negedge clk); source_valid_i = 16'd0; link_rx_valid_i = 16'd0; // 停止双向输入
        wait (tx_seen[0] == MEASURE_CYCLES && rx_seen[0] == MEASURE_CYCLES); // 等待最后一级数据排空
        repeat (2) @(posedge clk); #0.01; // 等待所有 bank 状态稳定
        for (check_bank = 0; check_bank < 16; check_bank = check_bank + 1) begin // 检查每 bank 最终计数
            if (tx_seen[check_bank] != MEASURE_CYCLES || rx_seen[check_bank] != MEASURE_CYCLES) $fatal(1, "bank count mismatch bank=%0d tx=%0d rx=%0d", check_bank, tx_seen[check_bank], rx_seen[check_bank]); // 要求每 bank 完整传输
        end // 结束最终计数检查
        if (tx_bubbles != 0 || rx_bubbles != 0 || source_stall_o != 16'd0 || result_stall_o != 16'd0) $fatal(1, "unexpected bubbles or stalls tx=%0d rx=%0d source=%h result=%h", tx_bubbles, rx_bubbles, source_stall_o, result_stall_o); // 要求活跃窗口无气泡和停顿
        $display("TB_KDLINK_V2_TENSOR_BANK_ARRAY_PASS cycles=%0d banks=16 payload_bits_per_cycle=8192 tx_GBps=1024.000 rx_GBps=1024.000 full_duplex_GBps=2048.000 tx_bubbles=0 rx_bubbles=0", MEASURE_CYCLES); // 报告 K4 实测聚合吞吐
        $finish; // 结束测试
    end // 结束主测试流程
    initial begin // 设置仿真超时
        #20000; // 等待最大测试时长
        $fatal(1, "KDLink-v2 tensor bank array timeout"); // 超时失败
    end // 结束超时保护
endmodule // 结束十六 bank 带宽测试
