`timescale 1ns/1ps // 定义 bonded reorder 单元仿真时间单位
module tb_kdlink_v2_bonded_reorder; // 定义双十六 flit packet 并行重排自校验测试
    localparam integer TEST_PAIRS = 256; // 遍历二百五十六组相邻 packet 以覆盖全部窗口槽和序号位
    logic clk; // 生成 reorder 时钟
    logic rst_n; // 生成低有效复位
    logic [1:0] accept_valid_i; // 驱动双 slice 输入 valid
    logic [191:0] accept_header_i; // 驱动双 slice 输入 header
    logic [1023:0] accept_payload_i; // 驱动双 slice 输入 payload
    logic [13:0] accept_payload_bytes_i; // 驱动双 slice 输入字节数
    wire [1:0] output_valid_o; // 观察双 context 输出 valid
    wire [191:0] output_header_o; // 观察双 context 输出 header
    wire [1023:0] output_payload_o; // 观察双 context 输出 payload
    wire [13:0] output_payload_bytes_o; // 观察双 context 输出字节数
    wire [8:0] occupancy_o; // 观察 reorder occupancy
    wire duplicate_drop_o; // 观察 duplicate drop
    wire window_error_o; // 观察 window error
    integer send_flit; // 提供输入 flit sequence
    integer output_cycles; // 统计双 context 输出周期
    integer expected_pair; // 记录当前预期相邻 packet pair
    integer send_pair; // 提供输入 packet pair 序号
    integer lane0_expected; // 记录偶 context 预期 flit
    integer lane1_expected; // 记录奇 context 预期 flit
    integer expected_bytes0; // 保存偶 context 预期 payload 字节数
    integer expected_bytes1; // 保存奇 context 预期 payload 字节数
    logic expected_toggle; // 保存当前输出全宽数据翻转模式
    logic stream_started; // 标记双 context 输出已经开始
    kdlink_v2_bonded_reorder u_dut ( // 实例化双 context reorder
        .clk_i(clk), .rst_n_i(rst_n), .accept_valid_i(accept_valid_i), .accept_header_i(accept_header_i), .accept_payload_i(accept_payload_i), .accept_payload_bytes_i(accept_payload_bytes_i), // 连接双 slice 输入
        .output_valid_o(output_valid_o), .output_header_o(output_header_o), .output_payload_o(output_payload_o), .output_payload_bytes_o(output_payload_bytes_o), // 连接双 context 输出
        .occupancy_o(occupancy_o), .duplicate_drop_o(duplicate_drop_o), .window_error_o(window_error_o) // 连接 reorder 状态
    ); // 结束 reorder 实例
    initial begin // 生成一 GHz reorder 时钟
        clk = 1'b0; // 初始化时钟为低
        forever #0.5 clk = ~clk; // 生成一纳秒周期时钟
    end // 结束时钟生成
    always @(negedge clk or negedge rst_n) begin // 检查双多 flit packet 并行输出
        if (!rst_n) begin // 检测复位有效
            output_cycles = 0; // 清零输出周期统计
            expected_pair = 0; // 清零预期 packet pair
            lane0_expected = 0; // 清零偶 context 预期 flit
            lane1_expected = 0; // 清零奇 context 预期 flit
            stream_started = 1'b0; // 清除输出启动标志
        end else if (|output_valid_o) begin // 检查 reorder 输出有效
            stream_started = 1'b1; // 标记输出流启动
            if (output_valid_o != 2'b11) $fatal(1, "multi-flit reorder lost a context valid=%b", output_valid_o); // 要求两个 packet context 同周期推进
            expected_toggle = expected_pair[0] ^ lane0_expected[0]; // 重建当前 flit 的全宽交替模式
            expected_bytes0 = ((expected_pair * 2) + lane0_expected) % 65; // 重建偶 packet 合法字节数
            expected_bytes1 = ((expected_pair * 2) + lane1_expected + 17) % 65; // 重建奇 packet 合法字节数
            if (output_header_o[81:70] != 12'(expected_pair * 2) || output_header_o[87:82] != lane0_expected[5:0]) $fatal(1, "context0 order mismatch pair=%0d seq=%0d flit=%0d", expected_pair, output_header_o[81:70], output_header_o[87:82]); // 检查偶 packet flit 顺序
            if (output_header_o[177:166] != 12'((expected_pair * 2) + 1) || output_header_o[183:178] != lane1_expected[5:0]) $fatal(1, "context1 order mismatch pair=%0d seq=%0d flit=%0d", expected_pair, output_header_o[177:166], output_header_o[183:178]); // 检查奇 packet flit 顺序
            if (output_payload_o[511:32] != {480{expected_toggle}} || output_payload_o[31:0] != {expected_pair[15:0], lane0_expected[15:0]}) $fatal(1, "context0 full payload mismatch pair=%0d flit=%0d", expected_pair, lane0_expected); // 检查偶 context 完整 payload
            if (output_payload_o[1023:544] != {480{~expected_toggle}} || output_payload_o[543:512] != {expected_pair[15:0], lane1_expected[15:0]}) $fatal(1, "context1 full payload mismatch pair=%0d flit=%0d", expected_pair, lane1_expected); // 检查奇 context 完整 payload
            if (output_payload_bytes_o[6:0] != expected_bytes0[6:0] || output_payload_bytes_o[13:7] != expected_bytes1[6:0]) $fatal(1, "payload byte mismatch pair=%0d flit=%0d", expected_pair, lane0_expected); // 检查零到六十四字节 metadata
            lane0_expected = lane0_expected + 1; // 推进偶 context 预期 flit
            lane1_expected = lane1_expected + 1; // 推进奇 context 预期 flit
            output_cycles = output_cycles + 1; // 累计双 context 输出周期
            if (lane0_expected == 16) begin // 检测当前双 packet 完成
                lane0_expected = 0; // 复位偶 context flit 预期值
                lane1_expected = 0; // 复位奇 context flit 预期值
                expected_pair = expected_pair + 1; // 推进下一 packet pair
                stream_started = 1'b0; // 允许 pair 间等待但保持 pair 内零气泡要求
            end // 结束当前双 packet 完成处理
        end else if (stream_started && lane0_expected < 16) begin // 检查单个 packet pair 启动后的中间气泡
            $fatal(1, "multi-flit reorder bubble pair=%0d flit=%0d", expected_pair, lane0_expected); // 报告双 context 气泡
        end // 结束输出检查
    end // 结束双 context scoreboard
    initial begin // 执行两个十六 flit packet 同步输入
        rst_n = 1'b0; // 初始保持复位有效
        accept_valid_i = 2'b00; // 初始清除输入 valid
        accept_header_i = 192'd0; // 初始清零 header
        accept_payload_i = 1024'd0; // 初始清零 payload
        accept_payload_bytes_i = {7'd64, 7'd64}; // 配置两个完整 payload
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        for (send_pair = 0; send_pair < TEST_PAIRS; send_pair = send_pair + 1) begin // 依次遍历全部 packet pair
            for (send_flit = 0; send_flit < 16; send_flit = send_flit + 1) begin // 连续输入当前两个十六 flit packet
                @(negedge clk); // 在下降沿更新双 context 输入
                accept_valid_i = 2'b11; // 两个 context 每周期各输入一个 flit
                accept_header_i[95:0] = {96{send_pair[0] ^ send_flit[0]}}; accept_header_i[191:96] = {96{~(send_pair[0] ^ send_flit[0])}}; // 交替驱动全宽 header 后重建顺序字段
                accept_header_i[81:70] = 12'(send_pair * 2); accept_header_i[177:166] = 12'((send_pair * 2) + 1); // 配置当前相邻 packet sequence
                accept_header_i[87:82] = send_flit[5:0]; accept_header_i[183:178] = send_flit[5:0]; // 配置两个 context flit sequence
                accept_header_i[17] = (send_flit == 0); accept_header_i[113] = (send_flit == 0); // 配置两个 SOP 标志
                accept_header_i[18] = (send_flit == 15); accept_header_i[114] = (send_flit == 15); // 配置两个 EOP 标志
                accept_payload_i[511:0] = {512{send_pair[0] ^ send_flit[0]}}; accept_payload_i[31:0] = {send_pair[15:0], send_flit[15:0]}; // 构造全宽翻转偶 context payload 并保留 tag
                accept_payload_i[1023:512] = {512{~(send_pair[0] ^ send_flit[0])}}; accept_payload_i[543:512] = {send_pair[15:0], send_flit[15:0]}; // 构造全宽翻转奇 context payload 并保留 tag
                accept_payload_bytes_i[6:0] = 7'(((send_pair * 2) + send_flit) % 65); // 遍历偶 context 合法 payload 字节数
                accept_payload_bytes_i[13:7] = 7'(((send_pair * 2) + send_flit + 17) % 65); // 遍历奇 context 合法 payload 字节数
                if (send_pair[1]) begin // 每两组交换物理 slice 以覆盖双 lane 全部窗口地址
                    accept_header_i = {accept_header_i[95:0], accept_header_i[191:96]}; // 将奇 packet 放到物理 lane 零
                    accept_payload_i = {accept_payload_i[511:0], accept_payload_i[1023:512]}; // 同步交换对应 payload
                    accept_payload_bytes_i = {accept_payload_bytes_i[6:0], accept_payload_bytes_i[13:7]}; // 同步交换有效字节数 metadata
                end // 结束物理 slice 交替映射
            end // 结束当前十六 flit 双 context 输入
            @(negedge clk); accept_valid_i = 2'b00; // 停止当前双 context 输入
            wait (expected_pair == (send_pair + 1)); // 等待当前双 packet 全部有序输出
        end // 结束全部 packet pair 遍历
        wait (output_cycles == TEST_PAIRS * 16); // 确认全部双 lane flit 已提交
        repeat (2) @(posedge clk); #0.01; // 等待最后两个 slot 释放
        if (occupancy_o != 9'd0 || window_error_o || duplicate_drop_o) $fatal(1, "multi-flit reorder final state occupancy=%0d window=%b duplicate=%b", occupancy_o, window_error_o, duplicate_drop_o); // 检查最终窗口清空
        $display("TB_KDLINK_V2_BONDED_REORDER_PASS packets=%0d flits_per_packet=16 output_flits_per_cycle=2 pair_internal_bubbles=0", TEST_PAIRS * 2); // 报告多 flit packet 双 context 通过
        $finish; // 结束仿真
    end // 结束主 stimulus
    initial begin // 设置 reorder 单元仿真超时
        #20000; // 等待全部 packet pair 覆盖操作完成
        $fatal(1, "KDLink-v2 bonded reorder timeout"); // 超时报错避免挂起
    end // 结束超时保护
endmodule // 结束 bonded reorder 测试平台
