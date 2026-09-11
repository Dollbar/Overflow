// SRAM-backed receive FIFO model comparison and independent payload scoreboard.
// 日期 2026-09-08；实际外部 SRAM 模型不是期望值来源。
`timescale 1ps/1ps // 使用统一皮秒精度验证两种 UPLI 静态周期。
module upli_receive_storage_tb; // 检查同步控制器、真实存储映射及逐字顺序的测试模块。
    parameter integer C_DEPTH = 5; // 运行时选择的 elaboration 逻辑容量。
    parameter integer C_DATA_WIDTH = 32; // 包括宽度 tiling 的整字节字宽。
    parameter integer C_HALF_PERIOD_PS = 320; // 常规或参考时钟的半周期。
    localparam integer C_COUNT_WIDTH = (C_DEPTH < 2) ? 1 : (C_DEPTH < 4) ? 2 : (C_DEPTH < 8) ? 3 : (C_DEPTH < 16) ? 4 : (C_DEPTH < 32) ? 5 : (C_DEPTH < 64) ? 6 : (C_DEPTH < 128) ? 7 : (C_DEPTH < 256) ? 8 : (C_DEPTH < 512) ? 9 : (C_DEPTH < 1024) ? 10 : (C_DEPTH < 2048) ? 11 : (C_DEPTH < 4096) ? 12 : (C_DEPTH < 8192) ? 13 : (C_DEPTH < 16384) ? 14 : (C_DEPTH < 32768) ? 15 : 16; // 计数必须表示零至完整容量。
    localparam integer C_VIEW_WIDTH = C_COUNT_WIDTH+C_DATA_WIDTH+2; // 打包占用、读数据及有效和 ready。
    reg clk; // 测试时钟由唯一时钟进程驱动。
    reg [C_DATA_WIDTH+2:0] stimulus; // 打包复位、消费、写有效和写数据。
    reg [C_VIEW_WIDTH-1:0] expected_before, expected_after; // oracle 生成的两个边界期望。
    wire write_ready, read_valid; // 实际 DUT 两侧的握手输出。
    wire [C_DATA_WIDTH-1:0] read_data; // 实际 SRAM 路径读出的字。
    wire [C_COUNT_WIDTH-1:0] count; // 实际总占用含所有读流水数据。
    wire [C_VIEW_WIDTH-1:0] observed; // 对比全部对外可见位。
    reg [C_DATA_WIDTH-1:0] scoreboard [0:65535]; // 独立保存真实接受的原始输入，不使用 oracle 数据。
    integer write_index, read_index, score_count; // scoreboard 的本地循环索引及有效字数。
    integer fd, fields, rows, burst, max_burst, reads; // 向量状态和连续消费检查计数。
    reg [4095:0] vector_path; // 由命令参数指定的相对或绝对向量路径。
    assign observed = {count, read_data, read_valid, write_ready}; // 零宽或未知元信息不绕过比较。
    upli_receive_storage #( // 实例化具有真实 KD28 SRAM 后端的接收 FIFO。
        .C_DEPTH(C_DEPTH), .C_DATA_WIDTH(C_DATA_WIDTH) // 控制器容量和宏宽度使用同一配置。
    ) Storage_Inst ( // 正式验证对象含控制器与外部存储映射。
        .i_clk(clk), .i_rstn(stimulus[C_DATA_WIDTH+2]), // 使用同步低有效复位。
        .i_write_valid(stimulus[C_DATA_WIDTH]), .i_write_data(stimulus[C_DATA_WIDTH-1:0]), .o_write_ready(write_ready), // 所有原始输入进入真正写路径。
        .i_read_ready(stimulus[C_DATA_WIDTH+1]), .o_read_valid(read_valid), .o_read_data(read_data), .o_count(count) // 从真正读数据建立独立 scoreboard。
    ); // 结束接收存储 DUT 实例。
    always #(C_HALF_PERIOD_PS) clk = ~clk; // 产生固定配置的验证时钟。
    initial begin // 读取独立向量并同步维护本地顺序检查器。
        clk = 1'b0; stimulus = {(C_DATA_WIDTH+3){1'b0}}; // 首沿前驱动全部输入到确定状态。
        rows = 0; write_index = 0; read_index = 0; score_count = 0; // 初始化向量行和独立队列状态。
        burst = 0; max_burst = 0; reads = 0; // 吞吐统计只计真实消费握手。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin $display("FAIL missing vectors"); $stop; end // 未指定向量不允许空跑通过。
        fd = $fopen(vector_path, "r"); // 以只读模式载入运行向量。
        if (fd == 0) begin $display("FAIL cannot open vectors"); $stop; end // 文件缺失明确失败。
        while (!$feof(fd)) begin // 逐行处理全部测试输入。
            @(negedge clk); // 远离 DUT 采样沿改变输入。
            fields = $fscanf(fd, "%h %h %h\n", stimulus, expected_before, expected_after); // 每行必须完整提供三列。
            if (fields != 3) begin $display("FAIL malformed vectors row=%0d", rows); $stop; end // 截断或损坏文件不能误报通过。
            #1; // 等待沿前组合 ready 与数据稳定。
            if ((rows != 0) && (observed !== expected_before)) begin $display("FAIL receive before row=%0d actual=%h expected=%h", rows, observed, expected_before); $stop; end // 首次 reset 之前不假设上电状态，其后全位比较。
            if (!stimulus[C_DATA_WIDTH+2]) begin // 同步复位同时取消测试端旧队列所有权。
                write_index = 0; read_index = 0; score_count = 0; burst = 0; // 不要求物理 SRAM 内容被清零。
            end else begin // 对实际边界握手做独立 payload 检查。
                if (read_valid && stimulus[C_DATA_WIDTH+1]) begin // 接收者本沿确实消费一个字。
                    if ((score_count == 0) || (read_data !== scoreboard[read_index])) begin $display("FAIL payload order row=%0d", rows); $stop; end // 重复、伪数据或错地址均不能混入输出。
                    read_index = (read_index+1) % 65536; score_count = score_count-1; // 从独立输入日志删除恰好一个字。
                    burst = burst+1; reads = reads+1; // 只统计连续发生的真实读握手。
                    if (burst > max_burst) max_burst = burst; // 记录达到的连续吞吐长度。
                end else burst = 0; // 任一空拍都打断连续读统计。
                if (write_ready && stimulus[C_DATA_WIDTH]) begin // 记录 DUT 真正接纳的输入值。
                    scoreboard[write_index] = stimulus[C_DATA_WIDTH-1:0]; // 独立期望直接来自输入，不从模型输出复制。
                    write_index = (write_index+1) % 65536; score_count = score_count+1; // 在消费之后加入新接受字。
                end // 结束实际写握手记录。
            end // 结束同步复位和正常 scoreboard 更新。
            @(posedge clk); #1; // 等待 DUT 与真实 SRAM 所有非阻塞更新完成。
            if (observed !== expected_after) begin $display("FAIL receive after row=%0d actual=%h expected=%h", rows, observed, expected_after); $stop; end // 检查完整读流水节拍及真实 payload。
            if ({{(32-C_COUNT_WIDTH){1'b0}}, count} != score_count) begin $display("FAIL independent occupancy row=%0d", rows); $stop; end // SRAM、在途及缓存总和不能增加逻辑容量。
            rows = rows+1; // 仅完整通过一行后递增有效采样沿。
        end // 结束全部独立向量检查。
        $fclose(fd); // 关闭只读向量句柄。
        if ((rows < 100) || (score_count != 0) || (max_burst < C_DEPTH)) begin $display("FAIL incomplete drain or throughput rows=%0d burst=%0d", rows, max_burst); $stop; end // 满容量预装后必须能连续逐拍排空。
        $display("PASS receive rows=%0d depth=%0d width=%0d period_ps=%0d reads=%0d max_burst=%0d", rows, C_DEPTH, C_DATA_WIDTH, 2*C_HALF_PERIOD_PS, reads, max_burst); // 明确报告此实际配置与连续吞吐。
        $finish; // 仅所有比较通过后正常结束。
    end // 结束接收存储主验证流程。
    initial begin #10000000000; $display("FAIL receive watchdog"); $stop; end // 工具挂起或时钟无进展时明确失败。
endmodule // 结束 upli_receive_storage_tb 数据与时序验证模块。
