`timescale 1ns/1ps // 定义三十二节点 fabric 测试时间单位
module tb_kdlink_v2_fabric32; // 定义八 plane 五百一十二 slice permutation 自校验测试
    localparam integer MEASURE_CYCLES = 1000; // 固定连续满注入测量周期数
    logic clk; // 生成一 GHz fabric 时钟
    logic rst_n; // 生成低有效复位
    logic [511:0] endpoint_tx_valid_i; // 驱动五百一十二 endpoint TX valid
    wire [511:0] endpoint_tx_ready_o; // 观察五百一十二 endpoint TX ready
    logic [327679:0] endpoint_tx_flit_i; // 驱动五百一十二 endpoint TX flit
    wire [511:0] endpoint_rx_valid_o; // 观察五百一十二 endpoint RX valid
    logic [511:0] endpoint_rx_ready_i; // 驱动五百一十二 endpoint RX ready
    wire [327679:0] endpoint_rx_flit_o; // 观察五百一十二 endpoint RX flit
    wire [15:0] protocol_error_o; // 观察八 plane 双 slice 协议错误
    integer drive_cycle; // 提供连续输入周期索引
    integer drive_endpoint; // 提供输入 endpoint bank 索引
    integer drive_node; // 保存输入 node identity
    integer drive_bank; // 保存输入 bank identity
    integer drive_plane; // 保存输入 plane identity
    integer drive_destination; // 保存 permutation destination
    integer check_endpoint; // 提供输出 endpoint bank 索引
    integer check_node; // 保存输出 node identity
    integer check_bank; // 保存输出 bank identity
    integer check_plane; // 保存输出 plane identity
    integer expected_source; // 保存 permutation 期望 source
    integer seen [0:511]; // 记录每 endpoint bank 已接收 flit 数
    integer bubbles; // 统计活跃窗口跨 lane 气泡
    integer source_stalls; // 统计任意 source backpressure 周期
    logic stream_started; // 标记五百一十二路输出已经启动
    kdlink_v2_fabric32 u_dut ( // 实例化三十二节点八 plane fabric
        .clk_i(clk), .rst_n_i(rst_n), // 连接时钟和复位
        .endpoint_tx_valid_i(endpoint_tx_valid_i), .endpoint_tx_ready_o(endpoint_tx_ready_o), .endpoint_tx_flit_i(endpoint_tx_flit_i), // 连接全部 endpoint TX
        .endpoint_rx_valid_o(endpoint_rx_valid_o), .endpoint_rx_ready_i(endpoint_rx_ready_i), .endpoint_rx_flit_o(endpoint_rx_flit_o), // 连接全部 endpoint RX
        .protocol_error_o(protocol_error_o) // 连接 fabric 协议状态
    ); // 结束 fabric 实例
    always #0.5 clk = ~clk; // 生成一 GHz 时钟
    always @(posedge clk or negedge rst_n) begin // 检查五百一十二路 permutation 输出
        if (!rst_n) begin // 检测复位有效
            bubbles = 0; // 清零气泡计数
            source_stalls = 0; // 清零 source stall 计数
            stream_started = 1'b0; // 清除输出启动标志
            for (check_endpoint = 0; check_endpoint < 512; check_endpoint = check_endpoint + 1) seen[check_endpoint] = 0; // 清零全部 endpoint 计数
        end else begin // 处理正常输出检查
            if (|endpoint_rx_valid_o) stream_started = 1'b1; // 捕获任一输出启动
            if (|(endpoint_tx_valid_i & ~endpoint_tx_ready_o)) source_stalls = source_stalls + 1; // 统计任意本地 ingress backpressure
            if (stream_started && (|endpoint_rx_valid_o) && !(&endpoint_rx_valid_o)) bubbles = bubbles + 1; // 统计跨 plane/slice 输出未对齐气泡
            for (check_endpoint = 0; check_endpoint < 512; check_endpoint = check_endpoint + 1) begin // 检查全部 endpoint bank 输出
                check_node = check_endpoint / 16; // 反解输出 node
                check_bank = check_endpoint & 15; // 反解输出 bank
                check_plane = check_bank >> 1; // 反解输出 plane
                expected_source = (check_node - check_plane - 1 + 32) & 31; // 反解固定 permutation source
                if (endpoint_rx_valid_o[check_endpoint]) begin // 检查当前 endpoint 输出有效
                    if (endpoint_rx_flit_o[check_endpoint*640 +: 16] != seen[check_endpoint][15:0]) $fatal(1, "fabric sequence mismatch endpoint=%0d seen=%0d got=%0d", check_endpoint, seen[check_endpoint], endpoint_rx_flit_o[check_endpoint*640 +: 16]); // 检查连续周期序号
                    if (endpoint_rx_flit_o[check_endpoint*640 + 16 +: 5] != expected_source[4:0] || endpoint_rx_flit_o[check_endpoint*640 + 21 +: 4] != check_bank[3:0]) $fatal(1, "fabric identity mismatch endpoint=%0d", check_endpoint); // 检查 source 和 bank identity
                    if (endpoint_rx_flit_o[check_endpoint*640 + 512 + 25 +: 5] != check_node[4:0] || endpoint_rx_flit_o[check_endpoint*640 + 512 + 30 +: 3] != check_plane[2:0]) $fatal(1, "fabric route mismatch endpoint=%0d", check_endpoint); // 检查 destination 和 plane header
                    seen[check_endpoint] = seen[check_endpoint] + 1; // 累加当前 endpoint 输出计数
                end // 结束当前 endpoint 有效输出检查
            end // 结束全部 endpoint 输出检查
        end // 结束正常输出检查
    end // 结束 permutation scoreboard
    initial begin // 执行八 plane 全 slice 连续 permutation
        clk = 1'b0; // 初始化时钟
        rst_n = 1'b0; // 初始保持复位
        endpoint_tx_valid_i = 512'd0; // 清除全部 TX valid
        for (drive_endpoint = 0; drive_endpoint < 512; drive_endpoint = drive_endpoint + 1) endpoint_tx_flit_i[drive_endpoint*640 +: 640] = 640'd0; // 清零全部 TX flit
        endpoint_rx_ready_i = {512{1'b1}}; // 配置全部 RX endpoint 持续接收
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        for (drive_cycle = 0; drive_cycle < MEASURE_CYCLES; drive_cycle = drive_cycle + 1) begin // 连续驱动固定测量窗口
            @(negedge clk); // 在下降沿更新全部输入
            endpoint_tx_valid_i = {512{1'b1}}; // 全部 endpoint bank 同拍有效
            for (drive_endpoint = 0; drive_endpoint < 512; drive_endpoint = drive_endpoint + 1) begin // 构造五百一十二路 permutation traffic
                drive_node = drive_endpoint / 16; // 反解输入 node
                drive_bank = drive_endpoint & 15; // 反解输入 bank
                drive_plane = drive_bank >> 1; // 反解输入 plane
                drive_destination = (drive_node + drive_plane + 1) & 31; // 为每 plane 构造独立一一 permutation
                endpoint_tx_flit_i[drive_endpoint*640 +: 640] = 640'd0; // 清零当前 flit 后重建字段
                endpoint_tx_flit_i[drive_endpoint*640 +: 16] = drive_cycle[15:0]; // 写入周期序号
                endpoint_tx_flit_i[drive_endpoint*640 + 16 +: 5] = drive_node[4:0]; // 写入 source identity
                endpoint_tx_flit_i[drive_endpoint*640 + 21 +: 4] = drive_bank[3:0]; // 写入 bank identity
                endpoint_tx_flit_i[drive_endpoint*640 + 512 + 13 +: 3] = drive_bank[2:0]; // 将 traffic 分布到八个 VC
                endpoint_tx_flit_i[drive_endpoint*640 + 512 + 25 +: 5] = drive_destination[4:0]; // 写入最终 destination
                endpoint_tx_flit_i[drive_endpoint*640 + 512 + 30 +: 3] = drive_plane[2:0]; // 写入 plane identity
            end // 结束五百一十二路输入构造
        end // 结束连续测量窗口
        @(negedge clk); endpoint_tx_valid_i = 512'd0; // 停止全部 ingress 输入
        wait (seen[0] == MEASURE_CYCLES); // 等待代表 endpoint 完成接收
        repeat (4) @(posedge clk); #0.01; // 等待全部 plane egress 排空
        for (check_endpoint = 0; check_endpoint < 512; check_endpoint = check_endpoint + 1) begin // 检查全部 endpoint 最终计数
            if (seen[check_endpoint] != MEASURE_CYCLES) $fatal(1, "fabric final count mismatch endpoint=%0d seen=%0d", check_endpoint, seen[check_endpoint]); // 要求每 endpoint 完整传输
        end // 结束最终计数检查
        if (bubbles != 0 || source_stalls != 0 || protocol_error_o != 16'd0) $fatal(1, "fabric performance failure bubbles=%0d stalls=%0d errors=%h", bubbles, source_stalls, protocol_error_o); // 要求无气泡无停顿无协议错误
        $display("TB_KDLINK_V2_FABRIC32_PASS cycles=%0d nodes=32 planes=8 slices_per_node=16 flits_per_cycle=512 per_npu_GBps=1024.000 system_GBps=32768.000 bubbles=0 source_stalls=0", MEASURE_CYCLES); // 报告全系统逻辑 payload 实测吞吐
        $finish; // 结束测试
    end // 结束主测试流程
    initial begin // 设置仿真超时
        #5000; // 等待最大测试时长
        $fatal(1, "KDLink-v2 fabric32 timeout"); // 超时失败
    end // 结束超时保护
endmodule // 结束三十二节点 fabric 测试
