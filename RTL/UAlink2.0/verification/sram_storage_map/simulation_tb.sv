`timescale 1ns/1ps // 使用确定的数字仿真时间单位。
`default_nettype none // 禁止隐式连线隐藏测试错误。
module simulation_tb; // 比较实际宏映射器与平坦逻辑存储。
    parameter WIDTH = 40; // 从编译命令指定完整逻辑字宽。
    parameter DEPTH = 5; // 从编译命令指定合法逻辑地址数量。
    parameter ADDR_WIDTH = (DEPTH < 2) ? 1 : $clog2(DEPTH + 1); // 默认使用生产包装器计数宽度并保留二次幂深度额外高位。
    parameter MAPPED_DEPTH = (DEPTH < 2) ? 2 : DEPTH; // 生产包装器把单字逻辑存储映射到至少两个字。
    localparam AW = ADDR_WIDTH; // 按显式生产参数声明读写接口。
    reg wc = 0, rc = 0, we = 0, re = 0; // 分别驱动两个时钟及使能。
    reg [AW-1:0] wa = 0, ra = 0; // 驱动逻辑地址而不计算宏行列。
    reg [WIDTH-1:0] wd = 0; // 驱动完整逻辑数据字。
    wire [WIDTH-1:0] q; // 观察完整逻辑读出字。
    reg [WIDTH-1:0] memory [0:DEPTH-1]; // 独立参考仅使用逻辑地址索引。
    reg initialized [0:DEPTH-1]; // 禁止把未知初值用作可比较预期。
    reg seen_read [0:DEPTH-1], seen_write [0:DEPTH-1]; // 记录全部合法地址的实际访问。
    reg [WIDTH-1:0] expected, ones = 0, zeros = 0; // 保存上次读值与逐位观测覆盖。
    reg valid = 0; // 首次有效读之前不约束无复位输出。
    integer fd, status, mode, wi, ri, w_enable, r_enable, n; // 解码独立刺激文件。
    integer cycles = 0, checks = 0, reads = 0, writes = 0, holds = 0; // 记录已执行操作。
    integer rbw = 0, disabled_writes = 0, padding_checks = 0; // 记录冲突和使能覆盖。
    integer read_addresses = 0, write_addresses = 0; // 统计实际覆盖的地址分母。
    reg [4095:0] vector_path; // 接收运行目录中的刺激文件路径。
    kd28_fifo_sdp_storage_map #(.DATA_WIDTH(WIDTH), .DEPTH(MAPPED_DEPTH), .ADDR_WIDTH(AW)) dut ( // 实例化未替换的被测逻辑映射器。
        .write_clk_i(wc), .write_cs_i(we), .write_addr_i(wa), .write_data_i(wd), // 连接独立写端口。
        .read_clk_i(rc), .read_cs_i(re), .read_addr_i(ra), .read_data_o(q) // 连接独立读端口。
    ); // 完成实际被测模块实例。
    integer pad_bit; // 逐位检查宏物理输出中不属于逻辑字的填充。
        always @(posedge rc) begin // 只在有效读时检查选定银行的物理填充位。
            if (re && dut.PHYSICAL_WIDTH > WIDTH) begin // 未读或没有填充时无需检查。
                #1; // 等待真实模型的非阻塞寄存器更新。
                for (pad_bit = WIDTH; pad_bit < dut.PHYSICAL_WIDTH; pad_bit = pad_bit + 1) // 遍历全部物理填充位。
                    if (dut.bank_read_data[dut.read_bank_q*dut.PHYSICAL_WIDTH+pad_bit] !== 1'b0) // 每个填充位必须已写为零。
                    $fatal(1, "FAIL padding cycle=%0d address=%0d", cycles, ra); // 填充错误必须使实际仿真失败。
                padding_checks = padding_checks + 1; // 保存补充检查执行次数。
            end // 结束有效读检查。
        end // 结束填充位监控。
    // 逻辑整字预期完全不依赖上述物理常量。
    initial begin // 逐个执行刺激并独立维护逻辑存储语义。
        for (n = 0; n < DEPTH; n = n + 1) begin // 初始化参考有效位而不初始化被测宏。
            initialized[n] = 0; seen_read[n] = 0; seen_write[n] = 0; // 清空地址访问记录。
        end // 完成参考记录初始化。
        if (!$value$plusargs("vectors=%s", vector_path)) $fatal(1, "FAIL missing vectors"); // 要求显式刺激路径。
        fd = $fopen(vector_path, "r"); // 打开运行时生成的刺激文件。
        if (!fd) $fatal(1, "FAIL cannot open vectors"); // 缺失刺激不能伪装为通过。
        status = $fscanf(fd, "%d %d %d %d %d %h\n", mode, w_enable, wi, r_enable, ri, wd); // 读取首个操作而不读取任何预期值。
        while (status == 6) begin // 只执行完整合法的刺激记录。
            if (wi < 0 || wi >= DEPTH || ri < 0 || ri >= DEPTH) $fatal(1, "FAIL invalid logical address"); // 仅验证承诺的合法地址空间。
            we = w_enable; re = r_enable; wa = wi; ra = ri; // 时钟低电平阶段准备输入。
            #2; // 给组合路径稳定时间并检查异步地址改变。
            if (valid) begin // 输出有定义后始终验证无读沿保持。
                if (q !== expected) $fatal(1, "FAIL preedge_hold cycle=%0d mode=%0d re=%0d ra=%0d got=%h expected=%h", cycles, mode, re, ra, q, expected); // 检测组合银行旁路等错误。
                checks = checks + 1; // 统计实际整字比较。
            end // 完成边沿前保持检查。
            if ((mode & 2) && re) begin // 参考读只依赖读沿及读使能。
                if (!initialized[ri]) $fatal(1, "FAIL reference read before initialization"); // 不利用未知数据掩盖比较。
                expected = memory[ri]; valid = 1; // 在写更新之前取旧值，定义同沿读先于写。
                seen_read[ri] = 1; reads = reads + 1; // 累加逻辑读覆盖。
                if ((mode & 1) && we && wi == ri) rbw = rbw + 1; // 记录实际同沿同地址冲突。
            end else if (valid) holds = holds + 1; // 记录没有有效读时的保持检查。
            if ((mode & 1) && we) begin // 参考写只依赖写沿及写使能。
                memory[wi] = wd; initialized[wi] = 1; // 完整字写入直接逻辑索引，不使用银行算法。
                seen_write[wi] = 1; writes = writes + 1; // 累加逻辑写覆盖。
            end // 完成参考写入。
            if ((mode & 1) && !we) disabled_writes = disabled_writes + 1; // 记录禁止写入的真实边沿。
            if (mode & 1) wc = 1; // 发出本操作的写时钟边沿。
            if (mode & 2) rc = 1; // 同一仿真时刻可发出读边沿。
            #2; // 等待真实宏模型及映射器寄存器更新。
            if (valid) begin // 比较全部位并严格拒绝未知值。
                if (q !== expected) $fatal(1, "FAIL data cycle=%0d mode=%0d we=%0d wa=%0d re=%0d ra=%0d got=%h expected=%h", cycles, mode, we, wa, re, ra, q, expected); // 错误必须产生非零运行返回值。
                checks = checks + 1; // 保存完整字比较次数。
                ones = ones | q; zeros = zeros | ~q; // 检查每一位都实际观察过零与一。
            end // 完成整字检查。
            wc = 0; rc = 0; cycles = cycles + 1; // 返回低电平并推进操作计数。
            status = $fscanf(fd, "%d %d %d %d %d %h\n", mode, w_enable, wi, r_enable, ri, wd); // 读取下个操作。
        end // 完成全部刺激操作。
        if (status != -1) $fatal(1, "FAIL malformed vector"); // 拒绝不完整刺激文件。
        for (n = 0; n < DEPTH; n = n + 1) begin // 独立统计所有合法地址覆盖。
            if (seen_read[n]) read_addresses = read_addresses + 1; // 统计确实比较过的地址。
            if (seen_write[n]) write_addresses = write_addresses + 1; // 统计确实写过的地址。
        end // 完成地址覆盖统计。
        if (read_addresses != DEPTH || write_addresses != DEPTH) $fatal(1, "FAIL address coverage"); // 要求全部逻辑地址均被访问。
        if (ones !== {WIDTH{1'b1}} || zeros !== {WIDTH{1'b1}}) $fatal(1, "FAIL full word bit coverage"); // 要求完整字每位的两种取值。
        if (rbw == 0 || disabled_writes == 0 || holds == 0) $fatal(1, "FAIL operation coverage"); // 防止代表性检查被跳过。
        $display("PASS cycles=%0d checks=%0d reads=%0d writes=%0d holds=%0d rbw=%0d disabled_writes=%0d padding_checks=%0d read_addresses=%0d write_addresses=%0d bits_both_values=%0d logical_depth=%0d mapped_depth=%0d address_width=%0d", cycles, checks, reads, writes, holds, rbw, disabled_writes, padding_checks, read_addresses, write_addresses, WIDTH, DEPTH, dut.DEPTH, $bits(dut.write_addr_i)); // 输出可审计的实际覆盖计数。
        $fclose(fd); $finish; // 正常完成并关闭刺激文件。
    end // 结束独立逻辑存储比较流程。
endmodule // 结束自校验测试台。
`default_nettype wire // 恢复后续文件的默认连线行为。
