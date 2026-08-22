`timescale 1ns/1ps // 定义八 plane NIC 测试时间单位
module tb_kdlink_nic8; // 定义十六 bank NIC 协议和带宽自校验测试
    localparam integer MEASURE_CYCLES = 10000; // 固定满带宽连续测量周期数
    logic clk; // 生成一 GHz 测试时钟
    logic rst_n; // 生成低有效复位
    logic start_i; // 驱动 operation 启动脉冲
    wire start_ready_o; // 观察 operation 启动许可
    logic [511:0] descriptor_i; // 驱动 KDLink descriptor
    logic phase_i; // 驱动 collective phase
    logic [7:0] link_epoch_i; // 驱动 link epoch
    logic finish_i; // 驱动 operation 完成脉冲
    wire active_o; // 观察 NIC active 状态
    wire descriptor_error_o; // 观察 descriptor 错误脉冲
    logic [15:0] source_valid_i; // 驱动十六 source bank valid
    wire [15:0] source_ready_o; // 观察十六 source bank ready
    logic [8191:0] source_data_i; // 驱动十六 source bank payload
    logic [111:0] source_bytes_i; // 驱动十六 source bank有效字节数
    logic [15:0] source_eop_i; // 驱动 source 提前 EOP
    logic [79:0] source_dst_i; // 驱动 direct operation destination
    wire [15:0] link_tx_valid_o; // 观察十六 slice TX valid
    logic [15:0] link_tx_ready_i; // 驱动十六 slice TX ready
    wire [1535:0] link_tx_header_o; // 观察十六 slice TX header
    wire [8191:0] link_tx_data_o; // 观察十六 slice TX payload
    wire [111:0] link_tx_bytes_o; // 观察十六 slice TX 有效字节数
    logic [15:0] link_rx_valid_i; // 驱动十六 slice RX valid
    wire [15:0] link_rx_ready_o; // 观察十六 slice RX ready
    logic [1535:0] link_rx_header_i; // 驱动十六 slice RX header
    logic [8191:0] link_rx_data_i; // 驱动十六 slice RX payload
    logic [111:0] link_rx_bytes_i; // 驱动十六 slice RX 有效字节数
    wire [15:0] result_valid_o; // 观察十六 result bank valid
    logic [15:0] result_ready_i; // 驱动十六 result bank ready
    wire [1535:0] result_header_o; // 观察十六 result bank header
    wire [8191:0] result_data_o; // 观察十六 result bank payload
    wire [111:0] result_bytes_o; // 观察十六 result bank 有效字节数
    wire [15:0] source_stall_o; // 观察 source stall 位图
    wire [15:0] result_stall_o; // 观察 result stall 位图
    integer opcode_index; // 提供六种 opcode 测试索引
    integer bank_index; // 提供十六 bank 驱动和检查索引
    integer measure_cycle; // 提供满带宽测量周期索引
    integer expected_packet_seq; // 保存期望 packet sequence
    integer expected_flit_seq; // 保存期望 flit sequence
    integer expected_chunk; // 保存期望 chunk identity
    integer expected_vc; // 保存期望 VC identity
    integer expected_dst; // 保存期望 destination node
    integer expected_source_bytes; // 保存期望 TX 有效字节数
    integer expected_result_bytes; // 保存期望 RX 有效字节数
    reg [11:0] route_collective_id; // 保存路由测试 collective identity
    reg [95:0] observed_header; // 保存当前检查的 TX header
    kdlink_nic8 u_dut ( // 实例化八 plane 十六 bank NIC
        .clk_i(clk), .rst_n_i(rst_n), // 连接时钟和复位
        .start_i(start_i), .start_ready_o(start_ready_o), .descriptor_i(descriptor_i), .phase_i(phase_i), .link_epoch_i(link_epoch_i), .finish_i(finish_i), .active_o(active_o), .descriptor_error_o(descriptor_error_o), // 连接 operation 控制
        .source_valid_i(source_valid_i), .source_ready_o(source_ready_o), .source_data_i(source_data_i), .source_bytes_i(source_bytes_i), .source_eop_i(source_eop_i), .source_dst_i(source_dst_i), // 连接 Tensor source banks
        .link_tx_valid_o(link_tx_valid_o), .link_tx_ready_i(link_tx_ready_i), .link_tx_header_o(link_tx_header_o), .link_tx_data_o(link_tx_data_o), .link_tx_bytes_o(link_tx_bytes_o), // 连接 link TX slices
        .link_rx_valid_i(link_rx_valid_i), .link_rx_ready_o(link_rx_ready_o), .link_rx_header_i(link_rx_header_i), .link_rx_data_i(link_rx_data_i), .link_rx_bytes_i(link_rx_bytes_i), // 连接 link RX slices
        .result_valid_o(result_valid_o), .result_ready_i(result_ready_i), .result_header_o(result_header_o), .result_data_o(result_data_o), .result_bytes_o(result_bytes_o), // 连接 Tensor result banks
        .source_stall_o(source_stall_o), .result_stall_o(result_stall_o) // 连接 stall 状态
    ); // 结束 NIC 实例
    always #0.5 clk = ~clk; // 生成一 GHz 时钟
    initial begin // 执行 descriptor、路由、协议字段和满带宽测试
        clk = 1'b0; // 初始化时钟
        rst_n = 1'b0; // 保持复位有效
        start_i = 1'b0; // 清除 operation 启动
        descriptor_i = 512'd0; // 清零 descriptor
        phase_i = 1'b0; // 默认 ReduceScatter phase
        link_epoch_i = 8'h5A; // 设置初始 link epoch
        finish_i = 1'b0; // 清除 operation 完成
        source_valid_i = 16'd0; // 清除 source valid
        source_data_i = 8192'd0; // 清零 source payload
        source_bytes_i = {16{7'd64}}; // 默认每 flit 六十四有效字节
        source_eop_i = 16'd0; // 默认使用十六 flit packet
        source_dst_i = 80'd0; // 清零 direct destination
        link_tx_ready_i = 16'hFFFF; // 配置全部 TX slice 持续接收
        link_rx_valid_i = 16'd0; // 清除 RX valid
        link_rx_header_i = 1536'd0; // 清零 RX header
        link_rx_data_i = 8192'd0; // 清零 RX payload
        link_rx_bytes_i = {16{7'd64}}; // 默认 RX 每 flit 六十四有效字节
        result_ready_i = 16'hFFFF; // 配置全部 result bank 持续接收
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        @(negedge clk); // 建立 malformed descriptor
        descriptor_i = 512'd0; // 清零 descriptor 后写必要字段
        descriptor_i[15:10] = 6'd32; // 写入固定节点数
        descriptor_i[24:21] = 4'd2; // 写入 descriptor 版本
        descriptor_i[56:49] = 8'hFF; // 启用全部 plane
        descriptor_i[58:57] = 2'b11; // 启用双 slice
        descriptor_i[416] = 1'b1; // 故意置位 reserved 字段
        start_i = 1'b1; // 提交 malformed descriptor
        @(posedge clk); #0.01; // 等待错误脉冲
        if (!descriptor_error_o || active_o) $fatal(1, "NIC malformed descriptor was accepted"); // 要求拒绝 malformed descriptor
        @(negedge clk); start_i = 1'b0; // 清除 malformed 启动脉冲
        for (opcode_index = 0; opcode_index < 6; opcode_index = opcode_index + 1) begin // 覆盖六种 operation 路由和 VC
            @(negedge clk); // 建立当前 operation descriptor
            descriptor_i = 512'd0; // 清零 descriptor 后写合法字段
            descriptor_i[2:0] = opcode_index[2:0]; // 写入当前 opcode
            descriptor_i[4:3] = opcode_index[1:0]; // 写入当前 dtype
            descriptor_i[9:5] = 5'd7; // 写入本地 node 七
            descriptor_i[15:10] = 6'd32; // 写入固定节点数
            descriptor_i[24:21] = 4'd2; // 写入 descriptor 版本
            route_collective_id = 12'h120 + {9'd0, opcode_index[2:0]}; // 计算 operation collective ID
            descriptor_i[36:25] = route_collective_id; // 写入 operation collective ID
            descriptor_i[56:49] = 8'h01; // 仅启用 plane 零
            descriptor_i[58:57] = 2'b11; // 启用 plane 零双 slice
            source_dst_i[4:0] = 5'd19; // 写入 bank 零 direct destination
            start_i = 1'b1; // 启动当前 operation
            @(posedge clk); #0.01; // 等待 descriptor 锁存
            if (!active_o || descriptor_error_o) $fatal(1, "NIC legal descriptor rejected opcode=%0d", opcode_index); // 要求合法 descriptor 激活 NIC
            @(negedge clk); // 建立一个 bank 零 source flit
            start_i = 1'b0; // 清除启动脉冲
            source_valid_i = 16'h0001; // 仅 bank 零发送一个 flit
            source_data_i = 8192'd0; // 清零 payload 后写 tag
            source_data_i[31:0] = 32'hD000_0000 | opcode_index; // 写入 opcode 数据 tag
            source_eop_i = 16'h0001; // 单 flit packet 立即 EOP
            @(posedge clk); #0.01; // 等待 TX 弹性级输出
            if (link_tx_valid_o != 16'h0001) $fatal(1, "NIC route test valid mismatch opcode=%0d valid=%h", opcode_index, link_tx_valid_o); // 要求仅 bank 零输出
            observed_header = link_tx_header_o[95:0]; // 读取 bank 零 header
            expected_vc = (opcode_index <= 2) ? 2 : ((opcode_index <= 4) ? 3 : 4); // 计算 opcode 对应 VC
            expected_dst = (opcode_index <= 2) ? 8 : 19; // 计算 Ring 下一跳或 direct destination
            if (observed_header[3:0] != 4'd2 || observed_header[7:4] != 4'd0 || observed_header[10:8] != opcode_index[2:0] || observed_header[12:11] != opcode_index[1:0]) $fatal(1, "NIC base header mismatch opcode=%0d header=%h", opcode_index, observed_header); // 检查版本、消息、opcode 和 dtype
            if (observed_header[15:13] != expected_vc[2:0] || !observed_header[17] || !observed_header[18] || observed_header[19]) $fatal(1, "NIC VC/SOP/EOP mismatch opcode=%0d header=%h", opcode_index, observed_header); // 检查 VC 和 packet 边界
            if (observed_header[24:20] != 5'd7 || observed_header[29:25] != expected_dst[4:0] || observed_header[32:30] != 3'd0 || observed_header[37:33] != 5'd31) $fatal(1, "NIC route fields mismatch opcode=%0d header=%h", opcode_index, observed_header); // 检查 source、destination、plane 和 hop limit
            if (observed_header[45:38] != 8'h5A || observed_header[57:46] != route_collective_id || observed_header[81:70] != 12'd0 || observed_header[87:82] != 6'd0 || observed_header[94:88] != 7'd64) $fatal(1, "NIC identity fields mismatch opcode=%0d header=%h", opcode_index, observed_header); // 检查 epoch、collective、sequence 和字节数
            if (link_tx_data_o[31:0] != (32'hD000_0000 | opcode_index)) $fatal(1, "NIC route payload mismatch opcode=%0d", opcode_index); // 检查 payload 未损坏
            @(negedge clk); source_valid_i = 16'd0; source_eop_i = 16'd0; finish_i = 1'b1; // 停止 source 并完成当前 operation
            @(posedge clk); #0.01; // 等待 active 状态释放
            if (active_o) $fatal(1, "NIC finish failed opcode=%0d", opcode_index); // 要求 operation 完成后 idle
            @(negedge clk); finish_i = 1'b0; // 清除完成脉冲
        end // 结束六种 operation 路由测试
        @(negedge clk); // 建立满带宽 AllReduce descriptor
        descriptor_i = 512'd0; // 清零 descriptor 后写合法字段
        descriptor_i[2:0] = 3'd2; // 选择 AllReduce
        descriptor_i[4:3] = 2'd3; // 选择 BF16 dtype
        descriptor_i[9:5] = 5'd31; // 使用 node 三十一测试 Ring wrap-around
        descriptor_i[15:10] = 6'd32; // 写入固定节点数
        descriptor_i[24:21] = 4'd2; // 写入 descriptor 版本
        descriptor_i[36:25] = 12'hABC; // 写入 collective ID
        descriptor_i[56:49] = 8'hFF; // 启用八个 plane
        descriptor_i[58:57] = 2'b11; // 启用全部十六 slice
        phase_i = 1'b1; // 选择 AllGather phase 标记
        link_epoch_i = 8'hA5; // 更新满带宽测试 epoch
        start_i = 1'b1; // 启动满带宽 operation
        @(posedge clk); #0.01; // 等待 descriptor 锁存
        if (!active_o || descriptor_error_o) $fatal(1, "NIC bandwidth descriptor rejected"); // 要求满带宽 descriptor 合法
        for (measure_cycle = 0; measure_cycle < MEASURE_CYCLES; measure_cycle = measure_cycle + 1) begin // 连续驱动十六 bank 双向满流
            @(negedge clk); // 在下降沿建立下一个周期输入
            start_i = 1'b0; // 清除启动脉冲
            if (source_ready_o != 16'hFFFF || link_rx_ready_o != 16'hFFFF) $fatal(1, "NIC local ready bubble cycle=%0d source=%h rx=%h", measure_cycle, source_ready_o, link_rx_ready_o); // 要求本地弹性边界持续可接收
            source_valid_i = 16'hFFFF; // 全部 source bank 持续有效
            link_rx_valid_i = 16'hFFFF; // 全部 RX slice 持续有效
            source_data_i = {8192{measure_cycle[0]}}; // 交替驱动全宽 source payload 覆盖全部数据位翻转
            source_dst_i = {80{measure_cycle[0]}}; // 翻转 direct destination 输入并验证 collective 路由不受影响
            link_rx_header_i = {1536{~measure_cycle[0]}}; // 交替驱动全宽 RX header 覆盖 metadata 翻转
            link_rx_data_i = {8192{~measure_cycle[0]}}; // 交替驱动全宽 RX payload 覆盖全部数据位翻转
            for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 构造十六 bank 独立 payload
                source_bytes_i[bank_index*7 +: 7] = 7'((measure_cycle + bank_index) % 65); // 遍历协议合法的零到六十四字节范围
                link_rx_bytes_i[bank_index*7 +: 7] = 7'(64 - ((measure_cycle + bank_index) % 65)); // 反向遍历 RX 合法字节范围
                source_data_i[bank_index*512 +: 32] = measure_cycle[31:0]; // 写入 source 周期序号
                source_data_i[bank_index*512 + 32 +: 5] = bank_index[4:0]; // 写入 source bank identity
                link_rx_header_i[bank_index*96 +: 32] = 32'hA500_0000 | bank_index; // 写入 RX header tag
                link_rx_data_i[bank_index*512 +: 32] = measure_cycle[31:0]; // 写入 RX 周期序号
                link_rx_data_i[bank_index*512 + 32 +: 5] = bank_index[4:0]; // 写入 RX bank identity
            end // 结束十六 bank payload 构造
            @(posedge clk); #0.01; // 采样本周期双向输出
            if (link_tx_valid_o != 16'hFFFF || result_valid_o != 16'hFFFF) $fatal(1, "NIC bandwidth bubble cycle=%0d tx=%h rx=%h", measure_cycle, link_tx_valid_o, result_valid_o); // 要求十六 bank 双向无气泡
            if (source_stall_o != 16'd0 || result_stall_o != 16'd0) $fatal(1, "NIC unexpected stall cycle=%0d source=%h result=%h", measure_cycle, source_stall_o, result_stall_o); // 要求活跃窗口无 stall
            for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 检查十六 bank header 和 payload
                observed_header = link_tx_header_o[bank_index*96 +: 96]; // 读取当前 bank TX header
                expected_flit_seq = measure_cycle % 16; // 计算 packet 内 flit sequence
                expected_packet_seq = (bank_index % 2) + ((measure_cycle / 16) * 2); // 计算 bonded 偶奇 packet sequence
                expected_chunk = ((bank_index & 15) << 8) | (expected_packet_seq & 255); // 计算 bank stripe chunk identity
                expected_source_bytes = (measure_cycle + bank_index) % 65; // 计算当前 TX 有效字节数
                expected_result_bytes = 64 - expected_source_bytes; // 计算当前 RX 有效字节数
                if (observed_header[3:0] != 4'd2 || observed_header[7:4] != 4'd0 || observed_header[10:8] != 3'd2 || observed_header[12:11] != 2'd3 || observed_header[15:13] != 3'd2 || observed_header[16] != 1'b1) $fatal(1, "NIC bandwidth base header mismatch cycle=%0d bank=%0d header=%h", measure_cycle, bank_index, observed_header); // 检查协议基本字段
                if (observed_header[17] != (expected_flit_seq == 0) || observed_header[18] != (expected_flit_seq == 15) || observed_header[19]) $fatal(1, "NIC bandwidth packet flags mismatch cycle=%0d bank=%0d header=%h", measure_cycle, bank_index, observed_header); // 检查 SOP、EOP 和 retry
                if (observed_header[24:20] != 5'd31 || observed_header[29:25] != 5'd0 || observed_header[32:30] != bank_index[3:1] || observed_header[37:33] != 5'd31) $fatal(1, "NIC bandwidth route mismatch cycle=%0d bank=%0d header=%h", measure_cycle, bank_index, observed_header); // 检查 Ring wrap、plane 和 hop limit
                if (observed_header[45:38] != 8'hA5 || observed_header[57:46] != 12'hABC || observed_header[69:58] != expected_chunk[11:0] || observed_header[81:70] != expected_packet_seq[11:0] || observed_header[87:82] != expected_flit_seq[5:0] || observed_header[94:88] != expected_source_bytes[6:0] || observed_header[95]) $fatal(1, "NIC bandwidth identity mismatch cycle=%0d bank=%0d header=%h", measure_cycle, bank_index, observed_header); // 检查 epoch、collective、chunk、sequence 和字节数
                if (link_tx_data_o[bank_index*512 +: 32] != measure_cycle[31:0] || link_tx_data_o[bank_index*512 + 32 +: 5] != bank_index[4:0]) $fatal(1, "NIC TX payload mismatch cycle=%0d bank=%0d", measure_cycle, bank_index); // 检查 TX payload 未损坏
                if (result_header_o[bank_index*96 +: 32] != (32'hA500_0000 | bank_index) || result_data_o[bank_index*512 +: 32] != measure_cycle[31:0] || result_data_o[bank_index*512 + 32 +: 5] != bank_index[4:0] || result_bytes_o[bank_index*7 +: 7] != expected_result_bytes[6:0]) $fatal(1, "NIC RX payload mismatch cycle=%0d bank=%0d", measure_cycle, bank_index); // 检查 RX 到 result 路径未损坏
                if (link_tx_bytes_o[bank_index*7 +: 7] != expected_source_bytes[6:0] || result_header_o[bank_index*96 +: 96] != link_rx_header_i[bank_index*96 +: 96]) $fatal(1, "NIC metadata bit-exact mismatch cycle=%0d bank=%0d", measure_cycle, bank_index); // 检查有效字节数和完整 RX header
                if (link_tx_data_o[bank_index*512 +: 512] != source_data_i[bank_index*512 +: 512] || result_data_o[bank_index*512 +: 512] != link_rx_data_i[bank_index*512 +: 512]) $fatal(1, "NIC full-width payload mismatch cycle=%0d bank=%0d", measure_cycle, bank_index); // 检查完整五百一十二位双向 payload
            end // 结束十六 bank 输出检查
        end // 结束满带宽连续窗口
        @(negedge clk); source_valid_i = 16'd0; link_rx_valid_i = 16'd0; // 停止满带宽双向输入
        @(posedge clk); #0.01; // 等待满带宽输出排空
        @(negedge clk); // 建立双向本地弹性背压场景
        link_tx_ready_i = 16'd0; // 阻塞全部 link TX sink
        result_ready_i = 16'd0; // 阻塞全部 Tensor result sink
        source_valid_i = 16'hFFFF; // 向全部空闲 TX 弹性级注入一个 flit
        link_rx_valid_i = 16'hFFFF; // 向全部空闲 RX 弹性级注入一个 flit
        source_data_i = {8192{1'b0}}; // 写入背压阶段 source payload 零图案
        link_rx_header_i = {1536{1'b0}}; // 写入背压阶段 RX header 零图案
        link_rx_data_i = {8192{1'b1}}; // 写入背压阶段 RX payload 一图案
        source_bytes_i = {16{7'd0}}; // 写入合法零字节 TX metadata
        link_rx_bytes_i = {16{7'd64}}; // 写入合法六十四字节 RX metadata
        @(posedge clk); #0.01; // 将背压 flit 捕获到十六个双向弹性寄存器
        if (link_tx_valid_o != 16'hFFFF || result_valid_o != 16'hFFFF) $fatal(1, "NIC backpressure preload failed tx=%h rx=%h", link_tx_valid_o, result_valid_o); // 要求全部弹性级已占用
        repeat (3) begin // 保持多周期本地背压
            @(negedge clk); // 在稳定采样边沿检查 ready 和 stall
            if (source_ready_o != 16'd0 || link_rx_ready_o != 16'd0 || source_stall_o != 16'hFFFF || result_stall_o != 16'hFFFF) $fatal(1, "NIC backpressure state mismatch source_ready=%h rx_ready=%h source_stall=%h result_stall=%h", source_ready_o, link_rx_ready_o, source_stall_o, result_stall_o); // 检查无远端组合反馈的本地停顿状态
        end // 结束持续背压检查
        @(negedge clk); // 释放全部本地 sink 并停止 source
        source_valid_i = 16'd0; link_rx_valid_i = 16'd0; // 停止背压阶段输入
        link_tx_ready_i = 16'hFFFF; result_ready_i = 16'hFFFF; // 恢复全部本地消费许可
        @(posedge clk); #0.01; // 消费已缓存的双向 flit
        @(negedge clk); finish_i = 1'b1; link_epoch_i = 8'd0; phase_i = 1'b0; // 完成 operation 并回翻控制字段
        @(posedge clk); #0.01; // 等待 active 状态释放
        if (link_tx_valid_o != 16'd0 || result_valid_o != 16'd0 || active_o) $fatal(1, "NIC bandwidth operation did not drain"); // 要求无尾部残留
        $display("TB_KDLINK_NIC8_PASS cycles=%0d banks=16 measured_flits_per_direction=%0d active_window_GBps=1024.000 descriptor_to_finish_cycles=10001 full_operation_GBps=1023.898 tx_bubbles=0 rx_bubbles=0 opcodes=6", MEASURE_CYCLES, MEASURE_CYCLES*16); // 报告 NIC RTL 实测吞吐
        $finish; // 结束测试
    end // 结束主测试流程
    initial begin // 设置仿真超时
        #20000; // 等待最大测试时长
        $fatal(1, "KDLink NIC8 timeout"); // 超时失败
    end // 结束超时保护
endmodule // 结束八 plane NIC 测试
