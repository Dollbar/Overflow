`timescale 1ns/1ps // 定义 KDSwitch permutation 测试时间单位
module tb_kdlink_switch32_permutation; // 定义双 slice 三十二端口无争用吞吐测试
    localparam integer MEASURE_CYCLES = 1000; // 固定连续 permutation 测量周期
    logic clk; // 生成一 GHz switch 时钟
    logic rst_n; // 生成低有效复位
    logic [63:0] ingress_valid_i; // 驱动双 slice ingress valid
    wire [63:0] ingress_ready_o; // 观察双 slice ingress ready
    logic [40959:0] ingress_flit_i; // 驱动双 slice ingress flit
    wire [63:0] egress_valid_o; // 观察双 slice egress valid
    logic [63:0] egress_ready_i; // 驱动双 slice egress ready
    wire [40959:0] egress_flit_o; // 观察双 slice egress flit
    wire [63:0] escape_pending_o; // 观察 escape pending
    wire [1:0] protocol_error_o; // 观察 switch 错误
    integer drive_cycle; // 提供输入周期序号
    integer drive_slice; // 提供输入 slice 索引
    integer drive_input; // 提供输入 port 索引
    integer check_slice; // 提供输出 slice 索引
    integer check_output; // 提供输出 port 索引
    integer flat_port; // 保存 packed port 索引
    integer destination; // 保存 permutation destination
    integer expected_source; // 保存 permutation 预期 source
    integer seen [0:63]; // 记录每个 egress 已输出 flit 数
    integer bubbles; // 统计活跃窗口气泡
    integer source_stalls; // 统计 source backpressure
    logic stream_started; // 标记 permutation 输出已经启动
    logic stress_mode; // 标记性能检查后的双 slice 拥塞覆盖阶段
    kdlink_switch32 u_dut ( // 实例化双 slice KDSwitch
        .clk_i(clk), .rst_n_i(rst_n), .ingress_valid_i(ingress_valid_i), .ingress_ready_o(ingress_ready_o), .ingress_flit_i(ingress_flit_i), // 连接双 slice ingress
        .egress_valid_o(egress_valid_o), .egress_ready_i(egress_ready_i), .egress_flit_o(egress_flit_o), .escape_pending_o(escape_pending_o), .protocol_error_o(protocol_error_o) // 连接双 slice egress 和状态
    ); // 结束 KDSwitch 实例
    initial begin // 生成一 GHz 时钟
        clk = 1'b0; // 初始化时钟为低
        forever #0.5 clk = ~clk; // 生成一纳秒周期
    end // 结束时钟生成
    always @(posedge clk or negedge rst_n) begin // 检查双 slice permutation 输出
        if (!rst_n) begin // 检测复位有效
            bubbles = 0; // 清零气泡计数
            source_stalls = 0; // 清零 source stall 计数
            stream_started = 1'b0; // 清除输出启动标志
            for (flat_port = 0; flat_port < 64; flat_port = flat_port + 1) seen[flat_port] = 0; // 清零全部 egress 计数
        end else if (!stress_mode) begin // 处理正常输出检查
            if (|egress_valid_o) stream_started = 1'b1; // 捕获 permutation 输出启动
            if (|(ingress_valid_i & ~ingress_ready_o)) source_stalls = source_stalls + 1; // 统计任意 ingress backpressure 周期
            for (check_slice = 0; check_slice < 2; check_slice = check_slice + 1) begin // 检查两个独立 slice
                for (check_output = 0; check_output < 32; check_output = check_output + 1) begin // 检查全部 egress
                    flat_port = check_slice*32 + check_output; // 形成 packed egress 索引
                    expected_source = (check_output - (check_slice + 1) + 32) & 31; // 反解固定 permutation source
                    if (egress_valid_o[flat_port]) begin // 检查本 egress 有效输出
                        if (egress_flit_o[flat_port*640 +: 16] != seen[flat_port][15:0]) $fatal(1, "permutation sequence mismatch slice=%0d output=%0d seen=%0d data=%0d", check_slice, check_output, seen[flat_port], egress_flit_o[flat_port*640 +: 16]); // 检查周期序号
                        if (egress_flit_o[flat_port*640 + 16 +: 5] != expected_source[4:0] || egress_flit_o[flat_port*640 + 21] != check_slice[0]) $fatal(1, "permutation identity mismatch slice=%0d output=%0d", check_slice, check_output); // 检查 source 和 slice identity
                        if (egress_flit_o[flat_port*640 + 537 +: 5] != check_output[4:0]) $fatal(1, "permutation destination mismatch slice=%0d output=%0d", check_slice, check_output); // 检查路由 destination 保持
                        seen[flat_port] = seen[flat_port] + 1; // 累计本 egress flit
                    end else if (stream_started && seen[flat_port] < MEASURE_CYCLES) begin // 检查启动后的周期性气泡
                        bubbles = bubbles + 1; // 累计气泡
                    end // 结束本 egress 输出检查
                end // 结束全部 egress 检查
            end // 结束双 slice 检查
        end // 结束正常输出检查
    end // 结束 permutation scoreboard
    initial begin // 执行双 slice permutation 连续流
        rst_n = 1'b0; // 初始保持复位
        ingress_valid_i = 64'd0; // 初始清除 ingress valid
        ingress_flit_i = 40960'd0; // 初始清零 ingress flit
        egress_ready_i = {64{1'b1}}; // 配置全部 egress 持续接收
        stress_mode = 1'b0; // 初始选择 permutation 性能检查
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        for (drive_cycle = 0; drive_cycle < MEASURE_CYCLES; drive_cycle = drive_cycle + 1) begin // 连续驱动固定测量窗口
            @(negedge clk); // 在下降沿更新输入
            ingress_valid_i = {64{1'b1}}; // 双 slice 全部 ingress 同拍有效
            ingress_flit_i = 40960'd0; // 清零 flit 后重建字段
            for (drive_slice = 0; drive_slice < 2; drive_slice = drive_slice + 1) begin // 构造两个独立 slice traffic
                for (drive_input = 0; drive_input < 32; drive_input = drive_input + 1) begin // 构造三十二 ingress permutation
                    flat_port = drive_slice*32 + drive_input; // 形成 packed ingress 索引
                    destination = (drive_input + drive_slice + 1) & 31; // 为本 slice 构造一一 permutation
                    ingress_flit_i[flat_port*640 +: 16] = drive_cycle[15:0]; // 写入周期序号
                    ingress_flit_i[flat_port*640 + 16 +: 5] = drive_input[4:0]; // 写入 source identity
                    ingress_flit_i[flat_port*640 + 21] = drive_slice[0]; // 写入 slice identity
                    ingress_flit_i[flat_port*640 + 525 +: 3] = drive_input[2:0]; // 写入八 VC 分布
                    ingress_flit_i[flat_port*640 + 537 +: 5] = destination[4:0]; // 写入最终 destination
                end // 结束 ingress flit 构造
            end // 结束双 slice traffic 构造
        end // 结束连续测量窗口
        @(negedge clk); ingress_valid_i = 64'd0; // 停止全部 ingress 输入
        wait (seen[0] == MEASURE_CYCLES && seen[32] == MEASURE_CYCLES); // 等待代表 egress 排空
        repeat (4) @(posedge clk); #0.01; // 等待全部 egress 状态稳定
        for (flat_port = 0; flat_port < 64; flat_port = flat_port + 1) begin // 检查全部 egress 最终计数
            if (seen[flat_port] != MEASURE_CYCLES) $fatal(1, "permutation final count mismatch port=%0d seen=%0d", flat_port, seen[flat_port]); // 要求每端口完整传输
        end // 结束最终计数检查
        if (bubbles != 0 || source_stalls != 0 || protocol_error_o != 2'b00) $fatal(1, "permutation performance failure bubbles=%0d stalls=%0d error=%b", bubbles, source_stalls, protocol_error_o); // 要求无气泡无停顿无错误
        @(negedge clk); // 在完成性能计分后开始拥塞覆盖
        stress_mode = 1'b1;
        ingress_valid_i = 64'hffff_ffff_ffff_ffff;
        ingress_flit_i = 40960'd0;
        for (drive_slice = 0; drive_slice < 2; drive_slice = drive_slice + 1) begin
            for (drive_input = 0; drive_input < 32; drive_input = drive_input + 1) begin
                flat_port = drive_slice*32 + drive_input;
                ingress_flit_i[flat_port*640 +: 16] = {10'd0, drive_slice[0], drive_input[4:0]};
                ingress_flit_i[flat_port*640 + 16 +: 5] = drive_input[4:0];
                ingress_flit_i[flat_port*640 + 525 +: 3] = 3'd0;
                ingress_flit_i[flat_port*640 + 537 +: 5] = 5'd0;
            end
        end
        egress_ready_i = 64'hffff_fffe_ffff_fffe; // 同时阻塞两个 slice 的 destination 零
        repeat (48) @(posedge clk); // 将 escape VOQ 推进到背压与 pending 状态
        if ((ingress_ready_o == 64'hffff_ffff_ffff_ffff) ||
            (escape_pending_o == 64'd0))
            $fatal(1, "dual-slice congestion did not produce ready/pending transitions ready=%h pending=%h",
                ingress_ready_o, escape_pending_o);
        @(negedge clk); ingress_valid_i = 64'd0; egress_ready_i = 64'hffff_ffff_ffff_ffff;
        repeat (160) @(posedge clk); // 释放背压并排空两个 slice 队列
        for (drive_cycle = 0; drive_cycle < 64; drive_cycle = drive_cycle + 1) begin
            @(negedge clk);
            egress_ready_i = 64'ha55a_c33c_f00f_6996 ^ {8{drive_cycle[7:0]}};
        end
        @(negedge clk); egress_ready_i = 64'hffff_ffff_ffff_ffff;
        if (protocol_error_o != 2'b00) $fatal(1, "post-performance congestion protocol error=%b", protocol_error_o);
        $display("TB_KDLINK_SWITCH32_PERMUTATION_PASS cycles=%0d ports=32 slices=2 output_flits_per_cycle=64 payload_GBps=4096.000 bubbles=0 source_stalls=0", MEASURE_CYCLES); // 报告单 plane 聚合 payload 吞吐
        $finish; // 结束测试
    end // 结束主测试流程
    initial begin // 设置仿真超时
        #5000; // 等待最大测试时长
        $fatal(1, "KDLink switch32 permutation timeout"); // 超时失败
    end // 结束超时保护
endmodule // 结束 permutation 测试
