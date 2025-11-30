`timescale 1ns/1ps // 定义异步 Tensor NIC 测试时间单位
module tb_kdlink_v2_nic8_cdc; // 定义十六 bank 双向 CDC exact-data 自校验测试
    localparam integer TEST_FLITS = 256; // 固定每 bank 跨域传输 flit 数
    logic tensor_clk; // 生成 Tensor 域异步时钟
    logic tensor_rst_n; // 生成 Tensor 域低有效复位
    logic slice_clk; // 生成 slice 域一 GHz 时钟
    logic slice_rst_n; // 生成 slice 域低有效复位
    logic start_i; // 驱动 slice 域 operation 启动
    wire start_ready_o; // 观察 slice 域启动许可
    logic [511:0] descriptor_i; // 驱动 slice 域 descriptor
    logic phase_i; // 驱动 slice 域 phase
    logic [7:0] link_epoch_i; // 驱动 slice 域 epoch
    logic finish_i; // 驱动 slice 域完成脉冲
    wire active_o; // 观察 NIC active 状态
    wire descriptor_error_o; // 观察 descriptor error
    logic [15:0] source_valid_i; // 驱动 Tensor 域 source valid
    wire [15:0] source_ready_o; // 观察 Tensor 域 source ready
    logic [8191:0] source_data_i; // 驱动 Tensor 域 source payload
    logic [111:0] source_bytes_i; // 驱动 Tensor 域 source 有效字节数
    logic [15:0] source_eop_i; // 驱动 Tensor 域 source EOP
    logic [79:0] source_dst_i; // 驱动 Tensor 域 source destination
    wire [15:0] link_tx_valid_o; // 观察 slice 域 link TX valid
    wire [15:0] link_tx_ready_i; // 保存 slice 域 link TX ready
    wire [1535:0] link_tx_header_o; // 观察 slice 域 link TX header
    wire [8191:0] link_tx_data_o; // 观察 slice 域 link TX payload
    wire [111:0] link_tx_bytes_o; // 观察 slice 域 link TX bytes
    wire [15:0] link_rx_valid_i; // 保存 slice 域 link RX valid
    wire [15:0] link_rx_ready_o; // 观察 slice 域 link RX ready
    wire [1535:0] link_rx_header_i; // 保存 slice 域 link RX header
    wire [8191:0] link_rx_data_i; // 保存 slice 域 link RX payload
    wire [111:0] link_rx_bytes_i; // 保存 slice 域 link RX bytes
    wire [15:0] result_valid_o; // 观察 Tensor 域 result valid
    logic [15:0] result_ready_i; // 驱动 Tensor 域 result ready
    wire [1535:0] result_header_o; // 观察 Tensor 域 result header
    wire [8191:0] result_data_o; // 观察 Tensor 域 result payload
    wire [111:0] result_bytes_o; // 观察 Tensor 域 result bytes
    wire [31:0] cdc_error_o; // 观察全部 async FIFO 错误状态
    integer drive_flit; // 提供 source flit 序号
    integer bank_index; // 提供十六 bank 驱动和检查索引
    integer result_seen; // 记录全部 bank 对齐 result 数
    integer expected_packet_seq; // 保存当前期望 packet sequence
    integer expected_flit_seq; // 保存当前期望 packet 内 flit sequence
    integer expected_bytes; // 保存当前期望有效字节数
    reg [511:0] expected_bank_data; // 保存当前 CDC 完整 payload 期望值
    reg [95:0] expected_bank_header; // 保存当前 CDC 完整 header 期望值
    assign link_rx_valid_i = link_tx_valid_o; // 将 slice TX valid 本地 loopback 到 RX
    assign link_tx_ready_i = link_rx_ready_o; // 使用 RX 本地 FIFO 许可驱动 TX ready
    assign link_rx_header_i = link_tx_header_o; // 将 slice TX header 本地 loopback 到 RX
    assign link_rx_data_i = link_tx_data_o; // 将 slice TX payload 本地 loopback 到 RX
    assign link_rx_bytes_i = link_tx_bytes_o; // 将 slice TX bytes 本地 loopback 到 RX
    kdlink_v2_nic8_cdc u_dut ( // 实例化异步 Tensor NIC wrapper
        .tensor_clk_i(tensor_clk), .tensor_rst_n_i(tensor_rst_n), .slice_clk_i(slice_clk), .slice_rst_n_i(slice_rst_n), // 连接两个异步时钟和复位域
        .start_i(start_i), .start_ready_o(start_ready_o), .descriptor_i(descriptor_i), .phase_i(phase_i), .link_epoch_i(link_epoch_i), .finish_i(finish_i), .active_o(active_o), .descriptor_error_o(descriptor_error_o), // 连接 slice 域 operation 控制
        .source_valid_i(source_valid_i), .source_ready_o(source_ready_o), .source_data_i(source_data_i), .source_bytes_i(source_bytes_i), .source_eop_i(source_eop_i), .source_dst_i(source_dst_i), // 连接 Tensor 域 source banks
        .link_tx_valid_o(link_tx_valid_o), .link_tx_ready_i(link_tx_ready_i), .link_tx_header_o(link_tx_header_o), .link_tx_data_o(link_tx_data_o), .link_tx_bytes_o(link_tx_bytes_o), // 连接 slice 域 link TX
        .link_rx_valid_i(link_rx_valid_i), .link_rx_ready_o(link_rx_ready_o), .link_rx_header_i(link_rx_header_i), .link_rx_data_i(link_rx_data_i), .link_rx_bytes_i(link_rx_bytes_i), // 连接 slice 域 link RX
        .result_valid_o(result_valid_o), .result_ready_i(result_ready_i), .result_header_o(result_header_o), .result_data_o(result_data_o), .result_bytes_o(result_bytes_o), .cdc_error_o(cdc_error_o) // 连接 Tensor 域 result 和 CDC 状态
    ); // 结束异步 NIC wrapper 实例
    always #0.4 tensor_clk = ~tensor_clk; // 生成一点二五 GHz Tensor 时钟以产生真实 FIFO backpressure
    always #0.5 slice_clk = ~slice_clk; // 生成一 GHz slice 时钟
    always @(posedge tensor_clk or negedge tensor_rst_n) begin // 检查 Tensor 域全部 result bank
        if (!tensor_rst_n) begin // 检测 Tensor 域复位有效
            result_seen = 0; // 清零 result 计数
        end else if (&result_valid_o) begin // 检查十六 bank result 同拍有效
            if (&result_ready_i) begin // 仅在真实 result 握手时推进 scoreboard
                for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 检查全部 bank crossing 数据
                    expected_bank_data = {512{result_seen[0]}}; // 重建交替全宽 crossing payload
                    expected_bank_data[31:0] = result_seen[31:0]; // 重建 source flit identity
                    expected_bank_data[35:32] = bank_index[3:0]; // 重建 bank identity
                    expected_packet_seq = bank_index[0] + ((result_seen / 16) * 2); // 重建 bonded 偶奇 packet sequence
                    expected_flit_seq = result_seen % 16; // 重建 packet 内 flit sequence
                    expected_bytes = (result_seen + bank_index) % 65; // 重建合法零到六十四字节 metadata
                    expected_bank_header = 96'd0; // 清零并重建完整协议 header
                    expected_bank_header[3:0] = 4'd2; // 重建协议版本
                    expected_bank_header[10:8] = 3'd5; // 重建 point-to-point opcode
                    expected_bank_header[15:13] = 3'd4; // 重建 point-to-point VC
                    expected_bank_header[17] = expected_flit_seq == 0; // 重建 SOP 标志
                    expected_bank_header[18] = expected_flit_seq == 15; // 重建 EOP 标志
                    expected_bank_header[24:20] = 5'd3; // 重建本地 source node
                    expected_bank_header[29:25] = 5'(result_seen + bank_index); // 重建 direct destination
                    expected_bank_header[32:30] = bank_index[3:1]; // 重建静态 plane identity
                    expected_bank_header[37:33] = 5'd31; // 重建 hop limit
                    expected_bank_header[45:38] = 8'hA6; // 重建 link epoch
                    expected_bank_header[57:46] = 12'h456; // 重建 collective identity
                    expected_bank_header[69:58] = {bank_index[3:0], expected_packet_seq[7:0]}; // 重建 chunk identity
                    expected_bank_header[81:70] = expected_packet_seq[11:0]; // 重建 packet sequence
                    expected_bank_header[87:82] = expected_flit_seq[5:0]; // 重建 flit sequence
                    expected_bank_header[94:88] = expected_bytes[6:0]; // 重建有效字节数
                    if (result_data_o[bank_index*512 +: 32] != result_seen[31:0] || result_data_o[bank_index*512 + 32 +: 4] != bank_index[3:0]) $fatal(1, "CDC payload mismatch seen=%0d bank=%0d", result_seen, bank_index); // 检查 payload 序号和 bank identity
                    if (result_data_o[bank_index*512 +: 512] != expected_bank_data) $fatal(1, "CDC full-width payload mismatch seen=%0d bank=%0d", result_seen, bank_index); // 检查完整五百一十二位 crossing 数据
                    if (result_bytes_o[bank_index*7 +: 7] != expected_bytes[6:0] || result_header_o[bank_index*96 +: 96] != expected_bank_header) $fatal(1, "CDC metadata mismatch seen=%0d bank=%0d", result_seen, bank_index); // 检查完整 header 和 bytes 原子对齐
                end // 结束全部 bank 数据检查
                result_seen = result_seen + 1; // 累加真实握手 result 数
            end // 结束 result ready 检查
        end else if (|result_valid_o) begin // 检查跨 bank valid 对齐
            $fatal(1, "CDC result banks lost alignment valid=%h", result_valid_o); // 禁止部分 bank 独立出现
        end // 结束 result valid 检查
    end // 结束 Tensor 域 result scoreboard
    initial begin // 执行十六 bank 双向异步 FIFO loopback
        tensor_clk = 1'b0; // 初始化 Tensor 时钟
        slice_clk = 1'b0; // 初始化 slice 时钟
        tensor_rst_n = 1'b0; // 保持 Tensor 域复位有效
        slice_rst_n = 1'b0; // 保持 slice 域复位有效
        start_i = 1'b0; // 清除 operation 启动
        descriptor_i = 512'd0; // 清零 descriptor 后写合法字段
        descriptor_i[2:0] = 3'd5; // 选择 point-to-point operation
        descriptor_i[4:3] = 2'd0; // 选择 INT32 dtype
        descriptor_i[9:5] = 5'd3; // 写入本地 node
        descriptor_i[15:10] = 6'd32; // 写入固定节点数
        descriptor_i[24:21] = 4'd2; // 写入 descriptor 版本
        descriptor_i[36:25] = 12'h456; // 写入 collective identity
        descriptor_i[56:49] = 8'hFF; // 启用全部 plane
        descriptor_i[58:57] = 2'b11; // 启用全部 slice
        phase_i = 1'b0; // 清零 phase
        link_epoch_i = 8'hA6; // 设置 link epoch
        finish_i = 1'b0; // 清除 operation 完成
        source_valid_i = 16'd0; // 清除 source valid
        source_data_i = 8192'd0; // 清零 source payload
        source_bytes_i = {16{7'd64}}; // 配置全部 bank 完整 payload
        source_eop_i = 16'd0; // 默认使用十六 flit packet
        source_dst_i = 80'd0; // 清零 direct destination
        result_ready_i = 16'hFFFF; // 配置全部 Tensor result 持续接收
        repeat (5) @(posedge tensor_clk); // 等待 Tensor 域复位稳定
        @(negedge tensor_clk); tensor_rst_n = 1'b1; // 在 Tensor 下降沿释放 Tensor 复位
        repeat (3) @(posedge slice_clk); // 等待 slice 域额外复位周期
        @(negedge slice_clk); slice_rst_n = 1'b1; start_i = 1'b1; // 释放 slice 复位并启动 operation
        @(negedge slice_clk); start_i = 1'b0; // 清除启动脉冲
        if (!active_o || descriptor_error_o) $fatal(1, "CDC NIC descriptor start failed"); // 要求合法 descriptor 激活 NIC
        for (drive_flit = 0; drive_flit < TEST_FLITS; drive_flit = drive_flit + 1) begin // 连续提交固定数量 Tensor flit
            @(negedge tensor_clk); // 在 Tensor 下降沿检查 FIFO 许可
            while (source_ready_o != 16'hFFFF) @(negedge tensor_clk); // 等待全部 source FIFO 同时可写
            source_valid_i = 16'hFFFF; // 全部 source bank 同拍有效
            source_eop_i = ((drive_flit & 15) == 15) ? 16'hFFFF : 16'd0; // 每十六 flit产生对齐 EOP
            result_ready_i = ((drive_flit & 31) == 16) ? 16'd0 : 16'hFFFF; // 周期性施加单周期 Tensor result 背压
            for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 构造全部 bank 独立 crossing 数据
                source_bytes_i[bank_index*7 +: 7] = 7'((drive_flit + bank_index) % 65); // 遍历全部合法 payload bytes 编码
                source_data_i[bank_index*512 +: 512] = {512{drive_flit[0]}}; // 交替驱动完整 payload 覆盖跨域数据位翻转
                source_data_i[bank_index*512 +: 32] = drive_flit[31:0]; // 写入 source flit 序号
                source_data_i[bank_index*512 + 32 +: 4] = bank_index[3:0]; // 写入 bank identity
                source_dst_i[bank_index*5 +: 5] = 5'((drive_flit + bank_index) & 31); // 显式截断并遍历全部 direct destination 编码
            end // 结束全部 bank 数据构造
        end // 结束全部 Tensor source 提交
        @(negedge tensor_clk); source_valid_i = 16'd0; source_eop_i = 16'd0; result_ready_i = 16'hFFFF; // 停止 Tensor source 并释放 result 背压
        wait (result_seen == TEST_FLITS); // 等待最后一个 result 穿越双向 CDC
        repeat (4) @(posedge tensor_clk); #0.01; // 等待全部 FIFO 状态稳定
        if (cdc_error_o != 32'd0) $fatal(1, "CDC FIFO error status=%h", cdc_error_o); // 要求无 overflow 或 underflow
        @(negedge slice_clk); finish_i = 1'b1; // 完成当前 NIC operation
        @(negedge slice_clk); finish_i = 1'b0; // 清除完成脉冲
        $display("TB_KDLINK_V2_NIC8_CDC_PASS banks=16 flits_per_bank=%0d tensor_clock_GHz=1.250 slice_clock_GHz=1.000 exact_data=PASS cdc_errors=0", TEST_FLITS); // 报告双向 CDC 测试通过
        $finish; // 结束测试
    end // 结束主测试流程
    initial begin // 设置仿真超时
        #5000; // 等待最大异步测试时长
        $fatal(1, "KDLink-v2 NIC8 CDC timeout"); // 超时失败
    end // 结束超时保护
endmodule // 结束异步 Tensor NIC 测试
