`timescale 1ns/1ps // 定义一 GHz bonded port 仿真时间单位
module tb_kdlink_v2_bonded_port; // 定义双 slice 满带宽、重排和 fault replay 自校验测试
    localparam integer NORMAL_FLITS = 20000; // 定义双 slice 连续满带宽 flit 数量
    localparam integer DEGRADED_FLITS = 2000; // 定义单 slice 降级连续 flit 数量
    localparam integer FAULT_BASE = NORMAL_FLITS; // 定义 fault recovery packet 起始索引
    logic clk; // 生成 bonded port 时钟
    logic rst_n; // 生成低有效复位
    logic [1:0] configured_slice_mask_i; // 配置两个 slice 可用
    logic [1:0] slice_fault_i; // 注入独立 slice fault
    logic [1:0] tx_valid_i; // 驱动两个逻辑 packet lane
    wire [1:0] tx_ready_o; // 观察两个逻辑 lane ready
    logic [191:0] tx_header_i; // 驱动两个逻辑 header
    logic [1023:0] tx_payload_i; // 驱动两个逻辑 payload
    logic [13:0] tx_payload_bytes_i; // 驱动两个逻辑字节数
    logic [1:0] ack_valid_i; // 驱动两个 origin slice ACK
    logic [23:0] ack_collective_id_i; // 驱动两个 ACK collective identity
    logic [1:0] ack_phase_i; // 驱动两个 ACK phase
    logic [23:0] ack_packet_seq_i; // 驱动两个 ACK packet sequence
    logic [1:0] nack_valid_i; // 驱动两个 origin slice NACK
    logic [23:0] nack_collective_id_i; // 驱动两个 NACK collective identity
    logic [1:0] nack_phase_i; // 驱动两个 NACK phase
    logic [23:0] nack_packet_seq_i; // 驱动两个 NACK packet sequence
    wire [1:0] slice_tx_valid_o; // 观察两个 physical TX valid
    wire [1279:0] slice_tx_flit_o; // 观察两个 physical TX flit
    wire [1:0] slice_rx_valid_i; // 形成 fault-aware physical loopback valid
    wire [1279:0] slice_rx_flit_i; // 形成 physical loopback flit
    wire [1:0] rx_valid_o; // 观察两个全局有序 RX valid
    wire [191:0] rx_header_o; // 观察两个全局有序 RX header
    wire [1023:0] rx_payload_o; // 观察两个全局有序 RX payload
    wire [13:0] rx_payload_bytes_o; // 观察两个全局有序 RX 字节数
    wire [1:0] active_slice_mask_o; // 观察 active slice mask
    wire degraded_o; // 观察 bonded port 降级状态
    wire link_down_o; // 观察 bonded port link down 状态
    wire [8:0] reorder_occupancy_o; // 观察 reorder occupancy
    wire [7:0] replay_occupancy_o; // 观察 replay occupancy
    wire [63:0] stripe_packet_count_o; // 观察每 slice packet 计数
    wire [1:0] crc_error_o; // 观察每 slice CRC error
    wire duplicate_drop_o; // 观察 duplicate drop
    wire reorder_error_o; // 观察 reorder error
    wire [1:0] retry_exhausted_o; // 观察 retry exhausted
    logic suppress_slice1_ack; // 控制 fault packet 保留在 replay buffer
    logic normal_tx_monitor; // 标记双 slice TX 满带宽监测窗口
    logic normal_rx_monitor; // 标记双 slice RX 满带宽监测窗口
    logic degraded_tx_monitor; // 标记单 slice TX 满带宽监测窗口
    logic degraded_rx_monitor; // 标记单 slice RX 满带宽监测窗口
    integer send_cycle; // 提供连续 normal stimulus 索引
    integer degraded_index; // 提供连续 degraded stimulus 索引
    integer normal_tx_flits; // 统计 normal physical TX flit
    integer normal_rx_flits; // 统计 normal logical RX flit
    integer degraded_tx_flits; // 统计 degraded physical TX flit
    integer degraded_rx_flits; // 统计 degraded logical RX flit
    integer total_rx_flits; // 统计全测试有序 RX flit
    logic retry_seen; // 标记 fault packet 以 retry identity 提交
    assign slice_rx_valid_i = slice_tx_valid_o & ~slice_fault_i; // fault slice 丢弃在途 flit
    assign slice_rx_flit_i = slice_tx_flit_o; // 连接无损 healthy slice loopback 数据
    kdlink_v2_bonded_port u_dut ( // 实例化双 slice bonded port
        .clk_i(clk), .rst_n_i(rst_n), .configured_slice_mask_i(configured_slice_mask_i), .slice_fault_i(slice_fault_i), // 连接时钟复位与健康状态
        .tx_valid_i(tx_valid_i), .tx_ready_o(tx_ready_o), .tx_header_i(tx_header_i), .tx_payload_i(tx_payload_i), .tx_payload_bytes_i(tx_payload_bytes_i), // 连接双 lane TX source
        .ack_valid_i(ack_valid_i), .ack_collective_id_i(ack_collective_id_i), .ack_phase_i(ack_phase_i), .ack_packet_seq_i(ack_packet_seq_i), // 连接双 slice ACK
        .nack_valid_i(nack_valid_i), .nack_collective_id_i(nack_collective_id_i), .nack_phase_i(nack_phase_i), .nack_packet_seq_i(nack_packet_seq_i), // 连接双 slice NACK
        .slice_tx_valid_o(slice_tx_valid_o), .slice_tx_flit_o(slice_tx_flit_o), .slice_rx_valid_i(slice_rx_valid_i), .slice_rx_flit_i(slice_rx_flit_i), // 连接两个 physical slice loopback
        .rx_valid_o(rx_valid_o), .rx_header_o(rx_header_o), .rx_payload_o(rx_payload_o), .rx_payload_bytes_o(rx_payload_bytes_o), // 连接全局有序 RX sink
        .active_slice_mask_o(active_slice_mask_o), .degraded_o(degraded_o), .link_down_o(link_down_o), .reorder_occupancy_o(reorder_occupancy_o), .replay_occupancy_o(replay_occupancy_o), // 连接 bonded port 状态
        .stripe_packet_count_o(stripe_packet_count_o), .crc_error_o(crc_error_o), .duplicate_drop_o(duplicate_drop_o), .reorder_error_o(reorder_error_o), .retry_exhausted_o(retry_exhausted_o) // 连接计数和错误状态
    ); // 结束 bonded port 实例
    initial begin // 生成一 GHz bonded port 时钟
        clk = 1'b0; // 初始化时钟为低
        forever #0.5 clk = ~clk; // 生成一纳秒周期时钟
    end // 结束时钟生成
    always @(posedge clk or negedge rst_n) begin // 生成比 store 晚一周期的精确 ACK
        if (!rst_n) begin // 检测复位有效
            ack_valid_i <= 2'b00; // 清除 ACK valid
            ack_collective_id_i <= 24'd0; // 清零 ACK collective identity
            ack_phase_i <= 2'b00; // 清零 ACK phase
            ack_packet_seq_i <= 24'd0; // 清零 ACK packet sequence
        end else begin // 处理正常 ACK 生成
            ack_valid_i <= 2'b00; // 默认当前周期不发 ACK
            if (tx_valid_i[0] && tx_ready_o[0]) begin // 检查 lane 零 input fire
                if ((active_slice_mask_o == 2'b10) || ((active_slice_mask_o == 2'b11) && tx_header_i[70])) begin // 检查 lane 零分配到 origin 一
                    if (!suppress_slice1_ack) ack_valid_i[1] <= 1'b1; // 正常 packet 生成 origin 一 ACK
                    ack_collective_id_i[23:12] <= tx_header_i[57:46]; // 保存 origin 一 collective identity
                    ack_phase_i[1] <= tx_header_i[16]; // 保存 origin 一 phase
                    ack_packet_seq_i[23:12] <= tx_header_i[81:70]; // 保存 origin 一 packet sequence
                end else begin // 处理 lane 零分配到 origin 零
                    ack_valid_i[0] <= 1'b1; // 生成 origin 零 ACK
                    ack_collective_id_i[11:0] <= tx_header_i[57:46]; // 保存 origin 零 collective identity
                    ack_phase_i[0] <= tx_header_i[16]; // 保存 origin 零 phase
                    ack_packet_seq_i[11:0] <= tx_header_i[81:70]; // 保存 origin 零 packet sequence
                end // 结束 lane 零 origin 选择
            end // 结束 lane 零 ACK 生成
            if (tx_valid_i[1] && tx_ready_o[1]) begin // 检查 lane 一 input fire
                if ((active_slice_mask_o == 2'b10) || ((active_slice_mask_o == 2'b11) && tx_header_i[166])) begin // 检查 lane 一分配到 origin 一
                    if (!suppress_slice1_ack) ack_valid_i[1] <= 1'b1; // 正常 packet 生成 origin 一 ACK
                    ack_collective_id_i[23:12] <= tx_header_i[153:142]; // 保存 origin 一 collective identity
                    ack_phase_i[1] <= tx_header_i[112]; // 保存 origin 一 phase
                    ack_packet_seq_i[23:12] <= tx_header_i[177:166]; // 保存 origin 一 packet sequence
                end else begin // 处理 lane 一分配到 origin 零
                    ack_valid_i[0] <= 1'b1; // 生成 origin 零 ACK
                    ack_collective_id_i[11:0] <= tx_header_i[153:142]; // 保存 origin 零 collective identity
                    ack_phase_i[0] <= tx_header_i[112]; // 保存 origin 零 phase
                    ack_packet_seq_i[11:0] <= tx_header_i[177:166]; // 保存 origin 零 packet sequence
                end // 结束 lane 一 origin 选择
            end // 结束 lane 一 ACK 生成
        end // 结束正常 ACK 生成
    end // 结束精确 ACK 时序逻辑
    always @(negedge clk or negedge rst_n) begin // 监测 physical TX steady-state 带宽
        if (!rst_n) begin // 检测复位有效
            normal_tx_flits = 0; // 清零 normal TX flit 统计
            degraded_tx_flits = 0; // 清零 degraded TX flit 统计
        end else begin // 处理正常 TX 监测
            if (normal_tx_monitor && (|slice_tx_valid_o)) begin // 检测 normal TX 输出窗口
                if (slice_tx_valid_o != 2'b11) $fatal(1, "bonded normal TX bubble valid=%b count=%0d", slice_tx_valid_o, normal_tx_flits); // 要求两个 slice 每周期各一 flit
                normal_tx_flits = normal_tx_flits + 2; // 累计双 slice TX flit
            end else if (normal_tx_monitor && (normal_tx_flits > 0) && (normal_tx_flits < NORMAL_FLITS)) begin // 检测 normal TX 中间气泡
                $fatal(1, "bonded normal TX stream stopped count=%0d", normal_tx_flits); // 报告双 slice TX 气泡
            end // 结束 normal TX 监测
            if (degraded_tx_monitor && (|slice_tx_valid_o)) begin // 检测 degraded TX 输出窗口
                if (slice_tx_valid_o != 2'b01) $fatal(1, "bonded degraded TX invalid=%b count=%0d", slice_tx_valid_o, degraded_tx_flits); // 要求只有 healthy slice 零持续输出
                degraded_tx_flits = degraded_tx_flits + 1; // 累计单 slice TX flit
            end else if (degraded_tx_monitor && (degraded_tx_flits > 0) && (degraded_tx_flits < DEGRADED_FLITS)) begin // 检测 degraded TX 中间气泡
                $fatal(1, "bonded degraded TX stream stopped count=%0d", degraded_tx_flits); // 报告单 slice TX 气泡
            end // 结束 degraded TX 监测
        end // 结束正常 TX 监测
    end // 结束 physical TX 带宽监测
    always @(negedge clk or negedge rst_n) begin // 检查有序 RX payload 和 steady-state 带宽
        if (!rst_n) begin // 检测复位有效
            normal_rx_flits = 0; // 清零 normal RX flit 统计
            degraded_rx_flits = 0; // 清零 degraded RX flit 统计
            total_rx_flits = 0; // 清零总 RX flit 统计
            retry_seen = 1'b0; // 清除 retry 提交标志
        end else begin // 处理正常 RX 检查
            if (rx_valid_o[0]) begin // 检查第一有序 output lane
                if (rx_payload_o[31:0] != total_rx_flits[31:0]) $fatal(1, "bonded RX lane0 payload mismatch got=%0d exp=%0d", rx_payload_o[31:0], total_rx_flits); // 检查全局 payload 顺序
                if (rx_header_o[81:70] != total_rx_flits[11:0]) $fatal(1, "bonded RX lane0 sequence mismatch got=%0d exp=%0d", rx_header_o[81:70], total_rx_flits[11:0]); // 检查 modulo packet sequence
                if ((total_rx_flits < NORMAL_FLITS) && (rx_payload_bytes_o[6:0] != 7'(total_rx_flits % 65))) $fatal(1, "bonded RX lane0 byte count mismatch got=%0d exp=%0d", rx_payload_bytes_o[6:0], total_rx_flits % 65); // 检查 normal 流零到六十四字节 metadata
                if (total_rx_flits == FAULT_BASE + 1) begin // 检查 fault packet replay identity
                    if (!rx_header_o[19] || (rx_header_o[15:13] != 3'd6)) $fatal(1, "fault packet did not commit as replay"); // 要求 retry 标志和 replay VC
                    retry_seen = 1'b1; // 标记 replay packet 已提交
                end // 结束 replay identity 检查
                total_rx_flits = total_rx_flits + 1; // 推进全局 RX 计数
                if (normal_rx_monitor) normal_rx_flits = normal_rx_flits + 1; // 累计 normal RX flit
                if (degraded_rx_monitor) degraded_rx_flits = degraded_rx_flits + 1; // 累计 degraded RX flit
            end // 结束第一 output lane 检查
            if (rx_valid_o[1]) begin // 检查第二有序 output lane
                if (rx_payload_o[543:512] != total_rx_flits[31:0]) $fatal(1, "bonded RX lane1 payload mismatch got=%0d exp=%0d", rx_payload_o[543:512], total_rx_flits); // 检查全局 payload 顺序
                if (rx_header_o[177:166] != total_rx_flits[11:0]) $fatal(1, "bonded RX lane1 sequence mismatch got=%0d exp=%0d", rx_header_o[177:166], total_rx_flits[11:0]); // 检查 modulo packet sequence
                if ((total_rx_flits < NORMAL_FLITS) && (rx_payload_bytes_o[13:7] != 7'(total_rx_flits % 65))) $fatal(1, "bonded RX lane1 byte count mismatch got=%0d exp=%0d", rx_payload_bytes_o[13:7], total_rx_flits % 65); // 检查 normal 流零到六十四字节 metadata
                if (total_rx_flits == FAULT_BASE + 1) begin // 检查 fault packet replay identity
                    if (!rx_header_o[115] || (rx_header_o[111:109] != 3'd6)) $fatal(1, "fault packet lane1 did not commit as replay"); // 要求 retry 标志和 replay VC
                    retry_seen = 1'b1; // 标记 replay packet 已提交
                end // 结束 replay identity 检查
                total_rx_flits = total_rx_flits + 1; // 推进全局 RX 计数
                if (normal_rx_monitor) normal_rx_flits = normal_rx_flits + 1; // 累计 normal RX flit
                if (degraded_rx_monitor) degraded_rx_flits = degraded_rx_flits + 1; // 累计 degraded RX flit
            end // 结束第二 output lane 检查
            if (normal_rx_monitor && (normal_rx_flits > 0) && (normal_rx_flits < NORMAL_FLITS) && (rx_valid_o != 2'b11)) $fatal(1, "bonded normal RX bubble valid=%b count=%0d", rx_valid_o, normal_rx_flits); // 要求 normal RX 每周期两个 flit
            if (degraded_rx_monitor && (degraded_rx_flits > 0) && (degraded_rx_flits < DEGRADED_FLITS) && (rx_valid_o != 2'b01) && (rx_valid_o != 2'b10)) $fatal(1, "bonded degraded RX bubble valid=%b count=%0d", rx_valid_o, degraded_rx_flits); // 要求 degraded RX 每周期一个 context flit
            if (crc_error_o != 2'b00 || reorder_error_o || retry_exhausted_o != 2'b00) begin // 捕获未计划协议错误的现场状态
                $display("BONDED_ERROR time=%0t total_rx=%0d occupancy=%0d rx_valid=%b rx_seq0=%0d rx_seq1=%0d retry=%b crc=%b reorder=%b", $time, total_rx_flits, reorder_occupancy_o, rx_valid_o, rx_header_o[81:70], rx_header_o[177:166], retry_exhausted_o, crc_error_o, reorder_error_o); // 输出重排触发现场
                $fatal(1, "unexpected bonded port error crc=%b reorder=%b retry=%b", crc_error_o, reorder_error_o, retry_exhausted_o); // 禁止未计划的协议错误
            end // 结束未计划协议错误检查
        end // 结束正常 RX 检查
    end // 结束有序 RX scoreboard
    initial begin // 执行双 slice、fault replay 和降级模式 stimulus
        rst_n = 1'b0; // 初始保持复位有效
        configured_slice_mask_i = 2'b11; // 配置两个 slice 可用
        slice_fault_i = 2'b00; // 初始没有 slice fault
        tx_valid_i = 2'b00; // 初始清除 TX valid
        tx_header_i = 192'd0; // 初始清零 TX header
        tx_payload_i = 1024'd0; // 初始清零 TX payload
        tx_payload_bytes_i = {7'd64, 7'd64}; // 配置两个完整 payload
        nack_valid_i = 2'b00; // 初始清除 NACK valid
        nack_collective_id_i = 24'd0; // 初始清零 NACK collective identity
        nack_phase_i = 2'b00; // 初始清零 NACK phase
        nack_packet_seq_i = 24'd0; // 初始清零 NACK packet sequence
        suppress_slice1_ack = 1'b0; // 初始允许两个 slice ACK
        normal_tx_monitor = 1'b1; // 启用 normal TX 带宽监测
        normal_rx_monitor = 1'b1; // 启用 normal RX 带宽监测
        degraded_tx_monitor = 1'b0; // 初始关闭 degraded TX 监测
        degraded_rx_monitor = 1'b0; // 初始关闭 degraded RX 监测
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        for (send_cycle = 0; send_cycle < NORMAL_FLITS/2; send_cycle = send_cycle + 1) begin // 连续驱动每周期两个单 flit packet
            @(negedge clk); // 在下降沿更新双 lane stimulus
            tx_valid_i = 2'b11; // 保持两个逻辑 lane 连续有效
            tx_header_i = {192{send_cycle[0]}}; // 翻转双 lane 调用方 header 全宽并重建合法字段
            tx_header_i[7:4] = 4'd0; tx_header_i[103:100] = 4'd0; // 写入两个 DATA message type
            tx_header_i[10:8] = 3'd2; tx_header_i[106:104] = 3'd2; // 写入两个 AllReduce opcode
            tx_header_i[12:11] = send_cycle[1:0]; tx_header_i[108:107] = ~send_cycle[1:0]; // 遍历两个 lane dtype
            tx_header_i[15:13] = 3'd2; tx_header_i[111:109] = 3'd2; // 写入两个 collective VC
            tx_header_i[16] = send_cycle[0]; tx_header_i[112] = ~send_cycle[0]; // 交替驱动两个 phase identity
            tx_header_i[17] = 1'b1; tx_header_i[113] = 1'b1; // 写入两个 SOP 标志
            tx_header_i[18] = 1'b1; tx_header_i[114] = 1'b1; // 写入两个 EOP 标志
            tx_header_i[19] = 1'b0; tx_header_i[115] = 1'b0; // 清除两个正常 traffic retry 标志
            tx_header_i[24:20] = send_cycle[4:0]; tx_header_i[120:116] = ~send_cycle[4:0]; // 遍历两个源节点
            tx_header_i[29:25] = ~send_cycle[4:0]; tx_header_i[125:121] = send_cycle[4:0]; // 遍历两个目的节点
            tx_header_i[32:30] = send_cycle[2:0]; tx_header_i[128:126] = ~send_cycle[2:0]; // 遍历两个 plane identity
            tx_header_i[37:33] = 5'((send_cycle % 31) + 1); tx_header_i[133:129] = 5'(31 - (send_cycle % 31)); // 遍历两个非零 hop limit
            tx_header_i[45:38] = send_cycle[7:0]; tx_header_i[141:134] = ~send_cycle[7:0]; // 遍历两个 link epoch
            tx_header_i[57:46] = send_cycle[11:0]; tx_header_i[153:142] = ~send_cycle[11:0]; // 遍历两个 collective identity
            tx_header_i[69:58] = 12'(send_cycle*2); tx_header_i[165:154] = 12'(send_cycle*2+1); // 写入两个 chunk identity
            tx_header_i[81:70] = 12'(send_cycle*2); tx_header_i[177:166] = 12'(send_cycle*2+1); // 写入两个 modulo packet sequence
            tx_header_i[87:82] = 6'd0; tx_header_i[183:178] = 6'd0; // 单 flit packet 固定使用 flit sequence 零
            tx_payload_i[511:0] = {512{send_cycle[0]}}; tx_payload_i[31:0] = send_cycle*2; // 交替驱动 lane 零完整 payload 并保留全局 identity
            tx_payload_i[1023:512] = {512{~send_cycle[0]}}; tx_payload_i[543:512] = send_cycle*2+1; // 交替驱动 lane 一完整 payload 并保留全局 identity
            tx_payload_bytes_i[6:0] = 7'((send_cycle * 2) % 65); tx_payload_bytes_i[13:7] = 7'(((send_cycle * 2) + 1) % 65); // 遍历双 lane 全部合法 payload 长度编码
            if (tx_ready_o != 2'b11) $fatal(1, "normal bonded source backpressure ready=%b cycle=%0d", tx_ready_o, send_cycle); // 要求满带宽 source 无 backpressure
        end // 结束 normal 双 lane stimulus
        @(negedge clk); tx_valid_i = 2'b00; // 停止 normal source
        wait (normal_tx_flits == NORMAL_FLITS); // 等待 physical TX 满带宽窗口完成
        wait (normal_rx_flits == NORMAL_FLITS); // 等待 logical RX 满带宽窗口完成
        normal_tx_monitor = 1'b0; // 关闭 normal TX 监测
        normal_rx_monitor = 1'b0; // 关闭 normal RX 监测
        suppress_slice1_ack = 1'b1; // 保留 odd fault packet 为未确认状态
        @(negedge clk); // 准备发送 fault pair
        tx_valid_i = 2'b11; // 同周期发送 healthy 和将丢失的 packet
        tx_header_i = 192'd0; // 重建确定的 fault pair header identity
        tx_header_i[7:4] = 4'd0; tx_header_i[103:100] = 4'd0; // 写入 fault pair DATA message type
        tx_header_i[10:8] = 3'd2; tx_header_i[106:104] = 3'd2; // 写入 fault pair AllReduce opcode
        tx_header_i[15:13] = 3'd2; tx_header_i[111:109] = 3'd2; // 写入 fault pair collective VC
        tx_header_i[17] = 1'b1; tx_header_i[113] = 1'b1; // 写入 fault pair SOP
        tx_header_i[18] = 1'b1; tx_header_i[114] = 1'b1; // 写入 fault pair EOP
        tx_header_i[24:20] = 5'd3; tx_header_i[120:116] = 5'd3; // 写入 fault pair source
        tx_header_i[29:25] = 5'd29; tx_header_i[125:121] = 5'd29; // 写入 fault pair destination
        tx_header_i[37:33] = 5'd31; tx_header_i[133:129] = 5'd31; // 写入 fault pair hop limit
        tx_header_i[57:46] = 12'hA35; tx_header_i[153:142] = 12'hA35; // 写入 fault pair collective identity
        tx_header_i[69:58] = 12'(FAULT_BASE); tx_header_i[81:70] = 12'(FAULT_BASE); // 配置 even packet 到 slice 零
        tx_header_i[165:154] = 12'(FAULT_BASE+1); tx_header_i[177:166] = 12'(FAULT_BASE+1); // 配置 odd packet 到 slice 一
        tx_payload_i[511:0] = {512{1'b0}}; tx_payload_i[31:0] = FAULT_BASE; // 构造 healthy fault-phase 全宽 payload
        tx_payload_i[1023:512] = {512{1'b1}}; tx_payload_i[543:512] = FAULT_BASE+1; // 构造待 replay 全宽 payload
        tx_payload_bytes_i = {7'd64, 7'd64}; // 为 fault replay 使用完整 payload 并固定重传身份
        if (tx_ready_o != 2'b11) $fatal(1, "fault pair not accepted ready=%b", tx_ready_o); // 要求 fault pair 被正常注入
        @(negedge clk); tx_valid_i = 2'b00; slice_fault_i = 2'b10; #0.01; // 在 codec 输出前隔离 slice 一并等待组合状态稳定
        if (!degraded_o || active_slice_mask_o != 2'b01) $fatal(1, "bonded port failed to enter degraded mode"); // 检查单 slice 降级状态
        @(negedge clk); // 等待 replay entry 完整
        nack_valid_i = 2'b10; // 对 origin slice 一发送精确 NACK
        nack_collective_id_i[23:12] = 12'hA35; // 配置 NACK collective identity
        nack_packet_seq_i[23:12] = 12'(FAULT_BASE+1); // 配置 NACK packet sequence
        @(negedge clk); nack_valid_i = 2'b00; suppress_slice1_ack = 1'b0; // 结束单周期 NACK 并恢复 ACK
        wait (total_rx_flits == FAULT_BASE + 2); // 等待 healthy packet 和跨 slice replay 提交
        if (!retry_seen) $fatal(1, "cross-slice replay packet was not observed"); // 要求 fault packet exact-once 提交
        degraded_tx_flits = 0; // 清零 replay 之后的 degraded TX 统计
        degraded_rx_flits = 0; // 清零 replay 之后的 degraded RX 统计
        degraded_tx_monitor = 1'b1; // 启用单 slice TX 满带宽监测
        degraded_rx_monitor = 1'b1; // 启用单 slice RX 满带宽监测
        for (degraded_index = 0; degraded_index < DEGRADED_FLITS; degraded_index = degraded_index + 1) begin // 连续驱动单 slice 降级流
            @(negedge clk); // 在下降沿更新单 lane stimulus
            tx_valid_i = 2'b01; // 仅驱动 lane 零以匹配单 slice 吞吐
            tx_header_i[95:0] = {96{degraded_index[0]}}; // 翻转 healthy lane 调用方 header 全宽
            tx_header_i[7:4] = 4'd0; tx_header_i[10:8] = 3'd2; tx_header_i[15:13] = 3'd2; // 重建合法 DATA AllReduce VC
            tx_header_i[12:11] = degraded_index[1:0]; tx_header_i[16] = degraded_index[0]; // 遍历 dtype 和 phase
            tx_header_i[17] = 1'b1; tx_header_i[18] = 1'b1; tx_header_i[19] = 1'b0; // 重建单 flit packet flags
            tx_header_i[24:20] = degraded_index[4:0]; tx_header_i[29:25] = ~degraded_index[4:0]; // 遍历 source 和 destination
            tx_header_i[32:30] = degraded_index[2:0]; tx_header_i[37:33] = 5'((degraded_index % 31) + 1); // 遍历 plane 和非零 hop limit
            tx_header_i[45:38] = degraded_index[7:0]; tx_header_i[57:46] = 12'hA35; // 遍历 epoch 并保持 collective identity
            tx_header_i[69:58] = 12'(FAULT_BASE + 2 + degraded_index); // 更新 degraded chunk identity
            tx_header_i[81:70] = 12'(FAULT_BASE + 2 + degraded_index); // 更新 degraded packet sequence
            tx_header_i[87:82] = 6'd0; // 单 flit degraded packet 固定使用 flit sequence 零
            tx_payload_i[511:0] = {512{degraded_index[0]}}; tx_payload_i[31:0] = FAULT_BASE + 2 + degraded_index; // 构造 degraded 全宽翻转 payload identity
            if (!tx_ready_o[0]) $fatal(1, "degraded source backpressure index=%0d", degraded_index); // 要求 healthy slice 连续接收
        end // 结束 degraded 连续 stimulus
        @(negedge clk); tx_valid_i = 2'b00; // 停止 degraded source
        wait (degraded_tx_flits == DEGRADED_FLITS); // 等待 degraded physical TX 完成
        wait (degraded_rx_flits == DEGRADED_FLITS); // 等待 degraded logical RX 完成
        degraded_tx_monitor = 1'b0; // 关闭 degraded TX 监测
        degraded_rx_monitor = 1'b0; // 关闭 degraded RX 监测
        repeat (2) @(posedge clk); #0.01; // 等待最后一个 reorder slot 完成提交释放
        if (total_rx_flits != NORMAL_FLITS + 2 + DEGRADED_FLITS) $fatal(1, "bonded total RX mismatch got=%0d", total_rx_flits); // 检查最终 exact-once 数量
        if (stripe_packet_count_o[31:0] != (NORMAL_FLITS/2 + 1 + DEGRADED_FLITS)) $fatal(1, "slice0 stripe count mismatch got=%0d", stripe_packet_count_o[31:0]); // 检查 slice 零 packet 计数
        if (stripe_packet_count_o[63:32] != (NORMAL_FLITS/2 + 1)) $fatal(1, "slice1 stripe count mismatch got=%0d", stripe_packet_count_o[63:32]); // 检查 slice 一 packet 计数
        if (duplicate_drop_o || reorder_occupancy_o != 9'd0 || link_down_o) $fatal(1, "unexpected final bonded state duplicate=%b occupancy=%0d down=%b", duplicate_drop_o, reorder_occupancy_o, link_down_o); // 检查最终清空和健康状态
        $display("TB_KDLINK_V2_BONDED_PORT_PASS normal_flits=%0d normal_GBps=128.000 degraded_flits=%0d degraded_GBps=64.000 bubbles=0 cross_slice_replay=1 exact_once=1", NORMAL_FLITS, DEGRADED_FLITS); // 报告 K3 全部验收结果
        $finish; // 结束仿真
    end // 结束主 stimulus
    initial begin // 设置 K3 仿真超时
        #40000; // 等待最大允许仿真时间
        $fatal(1, "KDLink-v2 bonded port timeout"); // 超时报错避免仿真挂起
    end // 结束超时保护
endmodule // 结束双 slice bonded port 测试平台
