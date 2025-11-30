`timescale 1ns/1ps // 定义一 GHz 仿真的时间单位与精度
module tb_kdlink_v2_slice; // 定义 KDLink-v2 slice 连续流与 CRC fault 自校验测试平台
    localparam integer GOOD_FLITS = 10000; // 定义连续正常 flit 数量
    localparam integer TOTAL_FLITS = GOOD_FLITS + 1; // 增加一条 fault flit
    logic clk; // 生成 slice 测试时钟
    logic rst_n; // 生成低有效复位
    logic tx_valid_i; // 驱动 TX 输入有效
    logic [95:0] tx_header_i; // 驱动 TX header
    logic [511:0] tx_payload_i; // 驱动 TX payload
    logic [6:0] tx_payload_bytes_i; // 驱动 TX payload 字节数
    logic tx_fault_i; // 标记当前输入需要在链路注入 fault
    wire tx_valid_o; // 观察 packetizer 输出有效
    wire [639:0] tx_flit_o; // 观察 packetizer 输出 flit
    wire [639:0] loopback_flit; // 保存 fault 注入后的 loopback flit
    wire rx_valid_o; // 观察 depacketizer 输出有效
    wire rx_crc_good_o; // 观察 RX CRC 结果
    wire [95:0] rx_header_o; // 观察 RX header
    wire [511:0] rx_payload_o; // 观察 RX payload
    wire [6:0] rx_payload_bytes_o; // 观察 RX payload 字节数
    wire checked_header_valid; // 观察 endpoint header 检查结果
    wire [7:0] checked_header_error; // 观察 endpoint header 错误位图
    logic checker_override; // 控制 header checker 定向错误矩阵
    logic [95:0] checker_header_i; // 保存 header checker 定向输入
    logic [4:0] checker_local_node_i; // 保存 header checker 本地节点输入
    logic checker_endpoint_i; // 保存 header checker endpoint 模式
    wire [95:0] checker_selected_header; // 选择流量 header 或定向测试 header
    logic fault_pipe [0:304]; // 将输入 fault 标志对齐到 TX CRC 流水输出
    logic [511:0] expected_payload [0:GOOD_FLITS-1]; // 保存正常 flit payload scoreboard
    logic [95:0] expected_header; // 保存当前完整 RX header 期望值
    integer send_index; // 记录 stimulus flit 索引
    integer align_index; // 提供 fault 对齐流水索引
    integer tx_count; // 统计 TX 输出 flit 数量
    integer rx_count; // 统计 RX 输出 flit 数量
    logic tx_stream_started; // 标记 TX 连续流已经启动
    logic rx_stream_started; // 标记 RX 连续流已经启动
    assign loopback_flit = fault_pipe[304] ? (tx_flit_o ^ 640'd1) : tx_flit_o; // 对最后一条 flit payload bit零注入错误
    assign checker_selected_header = checker_override ? checker_header_i : rx_header_o; // 在正常流和错误矩阵之间选择检查对象
    kdlink_v2_slice u_slice ( // 实例化被测 KDLink-v2 codec slice
        .clk_i(clk), .rst_n_i(rst_n), .tx_valid_i(tx_valid_i), .tx_header_i(tx_header_i), // 连接 TX 时钟复位有效和 header
        .tx_payload_i(tx_payload_i), .tx_payload_bytes_i(tx_payload_bytes_i), .tx_valid_o(tx_valid_o), .tx_flit_o(tx_flit_o), // 连接 TX payload 和 flit
        .rx_valid_i(tx_valid_o), .rx_flit_i(loopback_flit), .rx_valid_o(rx_valid_o), .rx_crc_good_o(rx_crc_good_o), // 连接本地 loopback 和 CRC 状态
        .rx_header_o(rx_header_o), .rx_payload_o(rx_payload_o), .rx_payload_bytes_o(rx_payload_bytes_o) // 连接 RX header 和 payload
    ); // 结束 codec slice 实例
    kdlink_v2_header_checker u_header_checker ( // 实例化 endpoint header 合法性检查器
        .header_i(checker_selected_header), .local_node_i(checker_local_node_i), .endpoint_check_i(checker_endpoint_i), // 连接接收 header 与可控检查模式
        .valid_o(checked_header_valid), .error_o(checked_header_error) // 连接 header 检查结果
    ); // 结束 header checker 实例
    initial begin // 生成一 GHz slice 时钟
        clk = 1'b0; // 初始化时钟为低
        forever #0.5 clk = ~clk; // 生成一纳秒时钟周期
    end // 结束时钟生成
    always @(*) begin // 按当前 RX 序号重建完整合法 header
        expected_header = 96'd0; // 默认全部 header 字段为零
        expected_header[3:0] = 4'd2; // 重建 packetizer 强制协议版本
        expected_header[10:8] = 3'(rx_count % 6); // 重建六种 operation opcode
        expected_header[12:11] = rx_count[1:0]; // 重建 dtype
        expected_header[15:13] = (rx_count % 6) <= 2 ? 3'd2 : ((rx_count % 6) <= 4 ? 3'd3 : 3'd4); // 重建 opcode 对应 VC
        expected_header[16] = rx_count[0]; // 重建 collective phase
        expected_header[17] = (rx_count & 15) == 0; // 重建 packet SOP
        expected_header[18] = (rx_count & 15) == 15; // 重建 packet EOP
        expected_header[24:20] = rx_count[4:0]; // 重建 source node
        expected_header[29:25] = 5'd29; // 重建 endpoint destination
        expected_header[32:30] = rx_count[2:0]; // 重建 fabric plane
        expected_header[37:33] = 5'((rx_count % 31) + 1); // 重建非零 hop limit
        expected_header[45:38] = rx_count[7:0]; // 重建 link epoch
        expected_header[57:46] = rx_count[11:0]; // 重建 collective identity
        expected_header[69:58] = rx_count[11:0]; // 重建 chunk identity
        expected_header[81:70] = rx_count[11:0]; // 重建 packet identity
        expected_header[87:82] = 6'(rx_count); // 重建 packet 内 flit sequence
        expected_header[94:88] = 7'(rx_count % 65); // 重建 packetizer 强制有效字节数
    end // 结束完整 header 重建
    always @(posedge clk or negedge rst_n) begin // 更新 fault 对齐流水
        if (!rst_n) begin // 检测复位有效
            for (align_index = 0; align_index <= 304; align_index = align_index + 1) fault_pipe[align_index] <= 1'b0; // 清零全部 fault 对齐级
        end else begin // 处理正常 fault 对齐
            fault_pipe[0] <= tx_fault_i && tx_valid_i; // 锁存当前输入 fault 标志
            for (align_index = 1; align_index <= 304; align_index = align_index + 1) fault_pipe[align_index] <= fault_pipe[align_index-1]; // 传递 fault 对齐流水
        end // 结束 fault 对齐更新
    end // 结束 fault 对齐时序逻辑
    always @(negedge clk or negedge rst_n) begin // 检查 TX 连续输出
        if (!rst_n) begin // 检测复位有效
            tx_count <= 0; // 清零 TX 输出计数
            tx_stream_started <= 1'b0; // 清除 TX 连续流启动标志
        end else begin // 处理正常 TX 检查
            if (tx_valid_o) begin // 检测 TX 输出 flit
                tx_stream_started <= 1'b1; // 标记 TX 连续流已经启动
                tx_count <= tx_count + 1; // 增加 TX 输出计数
            end else if (tx_stream_started && (tx_count < TOTAL_FLITS)) begin // 检测连续流中间气泡
                $fatal(1, "KDLink-v2 TX stream bubble count=%0d", tx_count); // 报告 TX 气泡错误
            end // 结束 TX 输出检查
        end // 结束正常 TX 检查
    end // 结束 TX scoreboard
    always @(negedge clk or negedge rst_n) begin // 检查 RX 连续输出和数据顺序
        if (!rst_n) begin // 检测复位有效
            rx_count <= 0; // 清零 RX 输出计数
            rx_stream_started <= 1'b0; // 清除 RX 连续流启动标志
        end else begin // 处理正常 RX 检查
            if (rx_valid_o) begin // 检测 RX 输出 flit
                rx_stream_started <= 1'b1; // 标记 RX 连续流已经启动
                if (rx_count < GOOD_FLITS) begin // 检查正常 flit 区间
                    if (!rx_crc_good_o) $fatal(1, "KDLink-v2 good flit failed CRC index=%0d", rx_count); // 要求正常 flit CRC通过
                    if (!checked_header_valid || checked_header_error != 8'd0) $fatal(1, "KDLink-v2 header rejected index=%0d error=%02x", rx_count, checked_header_error); // 要求 header合法
                    if (rx_payload_o != expected_payload[rx_count]) $fatal(1, "KDLink-v2 payload mismatch index=%0d", rx_count); // 检查 payload 顺序与内容
                    if (rx_header_o != expected_header) $fatal(1, "KDLink-v2 full header mismatch index=%0d got=%h expected=%h", rx_count, rx_header_o, expected_header); // 检查完整九十六位 header
                    if (rx_payload_bytes_o != 7'(rx_count % 65)) $fatal(1, "KDLink-v2 payload length mismatch index=%0d", rx_count); // 检查动态有效字节数
                end else begin // 检查最后一条 fault flit
                    if (rx_crc_good_o) $fatal(1, "KDLink-v2 injected fault escaped CRC"); // 要求 fault 被 CRC 检出
                end // 结束正常与 fault flit选择
                rx_count <= rx_count + 1; // 增加 RX 输出计数
            end else if (rx_stream_started && (rx_count < TOTAL_FLITS)) begin // 检测 RX 连续流中间气泡
                $fatal(1, "KDLink-v2 RX stream bubble count=%0d", rx_count); // 报告 RX 气泡错误
            end // 结束 RX 输出检查
        end // 结束正常 RX 检查
    end // 结束 RX scoreboard
    initial begin // 执行连续流 stimulus
        rst_n = 1'b0; // 初始保持复位有效
        tx_valid_i = 1'b0; // 初始清除 TX 有效
        tx_header_i = 96'd0; // 初始清零 TX header
        tx_payload_i = 512'd0; // 初始清零 TX payload
        tx_payload_bytes_i = 7'd64; // 配置完整 payload
        tx_fault_i = 1'b0; // 初始不注入 fault
        checker_override = 1'b0; // 初始检查正常接收流 header
        checker_header_i = 96'd0; // 清零定向 header 输入
        checker_local_node_i = 5'd29; // 配置正常 endpoint 节点
        checker_endpoint_i = 1'b1; // 默认启用 endpoint 目的检查
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        for (send_index = 0; send_index < TOTAL_FLITS; send_index = send_index + 1) begin // 连续驱动一万零一条 flit
            @(negedge clk); // 在下降沿更新下一拍 stimulus
            tx_valid_i = 1'b1; // 持续保持 TX 输入有效
            tx_header_i = {96{send_index[0]}}; // 翻转调用方 header 全宽并由 packetizer 规范化保留字段
            tx_header_i[7:4] = 4'd0; // 写入 DATA message type
            tx_header_i[10:8] = 3'(send_index % 6); // 遍历六种 operation opcode
            tx_header_i[12:11] = send_index[1:0]; // 遍历四种 reduction dtype
            tx_header_i[15:13] = (send_index % 6) <= 2 ? 3'd2 : ((send_index % 6) <= 4 ? 3'd3 : 3'd4); // 写入 opcode 对应合法 VC
            tx_header_i[16] = send_index[0]; // 交替写入 collective phase
            tx_header_i[17] = (send_index & 15) == 0; // 每十六 flit 写入 SOP
            tx_header_i[18] = (send_index & 15) == 15; // 每十六 flit 写入 EOP
            tx_header_i[19] = 1'b0; // 正常 traffic 清除 retry 标志
            tx_header_i[24:20] = send_index[4:0]; // 遍历最终源节点
            tx_header_i[29:25] = 5'd29; // 写入最终目的节点
            tx_header_i[32:30] = send_index[2:0]; // 遍历 fabric plane
            tx_header_i[37:33] = 5'((send_index % 31) + 1); // 遍历一到三十一 hop limit
            tx_header_i[45:38] = send_index[7:0]; // 遍历 link epoch
            tx_header_i[57:46] = send_index[11:0]; // 遍历 collective identity
            tx_header_i[69:58] = send_index[11:0]; // 写入条带 chunk identity
            tx_header_i[81:70] = send_index[11:0]; // 写入 modulo packet sequence
            tx_header_i[87:82] = 6'(send_index); // 遍历 packet 内 flit sequence
            tx_payload_bytes_i = 7'(send_index % 65); // 遍历协议合法的零到六十四有效字节
            tx_payload_i = {512{send_index[0]}}; // 使用交替全零全一模式覆盖完整五百一十二位数据通路
            tx_payload_i[31:0] = send_index[31:0]; // 保留低位顺序 identity
            tx_fault_i = (send_index == GOOD_FLITS); // 只对最后一条 flit 注入 fault
            if (send_index < GOOD_FLITS) expected_payload[send_index] = tx_payload_i; // 保存完整 payload scoreboard
        end // 结束连续 stimulus循环
        @(negedge clk); tx_valid_i = 1'b0; tx_fault_i = 1'b0; // 结束连续输入流
        wait (rx_count == TOTAL_FLITS); // 等待全部 RX 检查完成
        if (tx_count != TOTAL_FLITS) $fatal(1, "KDLink-v2 TX count mismatch got=%0d", tx_count); // 检查 TX flit总数
        checker_override = 1'b1; // 切换到 header checker 定向错误矩阵
        checker_header_i = 96'd0; // 构造合法 DATA header 基线
        checker_header_i[3:0] = 4'd2; checker_header_i[7:4] = 4'd0; checker_header_i[10:8] = 3'd2; checker_header_i[15:13] = 3'd2; // 配置合法版本消息 opcode 和 VC
        checker_header_i[29:25] = 5'd29; checker_header_i[37:33] = 5'd31; checker_header_i[94:88] = 7'd64; // 配置合法目的跳数和字节数
        #0.01; if (!checked_header_valid || checked_header_error != 8'h00) $fatal(1, "header checker legal baseline failed error=%h", checked_header_error); // 检查合法基线
        checker_header_i[3:0] = 4'd3; #0.01; if (checked_header_valid || checked_header_error != 8'h01) $fatal(1, "header version error matrix failed error=%h", checked_header_error); checker_header_i[3:0] = 4'd2; // 覆盖错误版本
        checker_header_i[7:4] = 4'd8; checker_header_i[15:13] = 3'd7; #0.01; if (checked_header_valid || checked_header_error != 8'h02) $fatal(1, "header message error matrix failed error=%h", checked_header_error); checker_header_i[7:4] = 4'd0; checker_header_i[15:13] = 3'd2; // 覆盖非法消息类型
        checker_header_i[10:8] = 3'd7; #0.01; if (checked_header_valid || checked_header_error != 8'h04) $fatal(1, "header opcode error matrix failed error=%h", checked_header_error); checker_header_i[10:8] = 3'd2; // 覆盖非法 DATA opcode
        checker_header_i[94:88] = 7'd65; #0.01; if (checked_header_valid || checked_header_error != 8'h08) $fatal(1, "header bytes error matrix failed error=%h", checked_header_error); checker_header_i[94:88] = 7'd64; // 覆盖超长 payload
        checker_header_i[95] = 1'b1; #0.01; if (checked_header_valid || checked_header_error != 8'h10) $fatal(1, "header reserved error matrix failed error=%h", checked_header_error); checker_header_i[95] = 1'b0; // 覆盖保留位错误
        checker_header_i[29:25] = 5'd28; #0.01; if (checked_header_valid || checked_header_error != 8'h20) $fatal(1, "header destination error matrix failed error=%h", checked_header_error); checker_header_i[29:25] = 5'd29; // 覆盖 endpoint 目的不匹配
        checker_endpoint_i = 1'b0; checker_header_i[37:33] = 5'd0; #0.01; if (checked_header_valid || checked_header_error != 8'h40) $fatal(1, "header hop error matrix failed error=%h", checked_header_error); checker_endpoint_i = 1'b1; checker_header_i[37:33] = 5'd31; // 覆盖 router hop 耗尽
        checker_header_i[15:13] = 3'd7; #0.01; if (checked_header_valid || checked_header_error != 8'h80) $fatal(1, "header VC error matrix failed error=%h", checked_header_error); checker_header_i[15:13] = 3'd2; // 覆盖消息与 VC 映射错误
        checker_override = 1'b0; // 恢复正常流 header 选择
        $display("TB_KDLINK_V2_SLICE_PASS good_flits=%0d fault_flits=1 tx_bubbles=0 rx_bubbles=0 payload_GBps=64.000 header_error_matrix=PASS", GOOD_FLITS); // 报告 K2 连续流和错误矩阵通过
        $finish; // 结束仿真
    end // 结束主 stimulus
    initial begin // 设置 K2 仿真超时
        #15000; // 等待最大允许仿真时间
        $fatal(1, "KDLink-v2 slice timeout"); // 超时报错避免仿真挂起
    end // 结束仿真超时保护
endmodule // 结束 KDLink-v2 slice 测试平台
