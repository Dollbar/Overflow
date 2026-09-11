// Normal credit return queue testbench with independent deque-model vectors.
// 日期 2026-09-08；验证退休元数据队列，不把局部握手当成 UPLI 数据总线。
`timescale 1ps/1ps // 测试时钟以皮秒表示，与其它 UPLI 局部门一致。
module upli_credit_return_tb; // 正常返回队列逐拍自检模块。
    parameter integer C_NUM_PORTS = 1; // 本次运行的有效端口数量。
    parameter integer C_DEPTH = 4; // 每端口退休元数据队列深度。
    parameter integer C_HALF_PERIOD_PS = 320; // 正常或参考时钟半周期。
    localparam integer C_COUNT_WIDTH = (C_DEPTH <= 1) ? 1 : ((C_DEPTH <= 3) ? 2 : ((C_DEPTH <= 7) ? 3 : ((C_DEPTH <= 15) ? 4 : 5))); // 容纳零至深度的计数位宽。
    localparam integer C_RESULT_WIDTH = 25+4*C_COUNT_WIDTH; // 返回总线、计数和组合 ready 的完整比较宽度。
    reg reg_clk; // 测试环境唯一生成的时钟，在初始化过程明确置零。
    reg [10:0] stimulus = 11'd0; // 复位、许可、退休有效及原始元数据输入。
    reg [10:0] next_stimulus; // 从文本读取的下一拍激励。
    reg expected_ready; // 输入稳定后的沿前组合空间指示期望。
    reg [C_RESULT_WIDTH-1:0] expected_result; // 模型沿后全部输出期望。
    reg [C_RESULT_WIDTH-2:0] previous_registered = {(C_RESULT_WIDTH-1){1'b0}}; // 检查注册输出不会在采样沿前跳变。
    wire ready; // DUT 当前选中端口的本地入队资格。
    wire [3:0] valid, pool; // 各端口注册的信用批次有效与类型。
    wire [7:0] vcs, nums; // 注册的原 VC 和实际数量减一编码。
    wire [4*C_COUNT_WIDTH-1:0] pending; // 各端口剩余队列长度。
    wire [C_RESULT_WIDTH-1:0] actual; // 全部观测输出的固定打包。
    reg [4095:0] vector_path; // 由命令行指定输入向量文件，不绑定主机目录。
    integer file_handle, fields, rows; // 文本输入句柄、字段数量和已比较拍数。
    upli_credit_return_queue #( // 实例化实际正常返回 RTL，不替换内部存储。
        .C_NUM_PORTS(C_NUM_PORTS), .C_DEPTH(C_DEPTH) // DUT 与向量生成器使用相同声明参数。
    ) Return_Inst ( // 以命名接口连接全部输入和输出。
        .i_clk(reg_clk), .i_rstn(stimulus[10]), .i_return_enable(stimulus[6 +: C_NUM_PORTS]), // 本地许可按启用端口裁剪，原生输出维持固定形状。
        .i_retire_valid(stimulus[5]), .i_retire_port(stimulus[4:3]), .i_retire_vc(stimulus[2:1]), .i_retire_pool(stimulus[0]), // 输入携带已退休记录的原始元数据。
        .o_retire_ready(ready), .o_credit_valid(valid), .o_credit_pool(pool), .o_credit_vc(vcs), .o_credit_num(nums), .o_pending_count(pending) // 所有可见输出均参与检查。
    ); // 结束真实 DUT 实例。
    assign actual = {ready, pending, valid, pool, vcs, nums}; // 使用与 Python 向量相同的声明打包而非共享状态算法。
    always #(C_HALF_PERIOD_PS) reg_clk = !reg_clk; // 仅测试环境允许定时翻转时钟。
    initial begin // 顺序读取和逐沿比较完整向量文件。
        reg_clk = 1'b0; // 在时钟翻转过程启动前提供确定初值。
        rows = 0; // 尚未通过任何有效输入行。
        if (!$value$plusargs("VECTORS=%s", vector_path)) $stop; // 缺向量文件参数直接失败。
        file_handle = $fopen(vector_path, "r"); // 打开用户指定的只读向量流。
        if (file_handle == 0) $stop; // 不把文件缺失当作空测试通过。
        while (!$feof(file_handle)) begin // 每次最多读一个模型采样行。
            fields = $fscanf(file_handle, "%h %h %h\n", next_stimulus, expected_ready, expected_result); // 三列分别绑定输入、沿前和沿后语义。
            if (fields != 3) $stop; // 截断或额外损坏字段必须被拒绝。
            @(negedge reg_clk); // 在非采样沿驱动下一组输入。
            stimulus = next_stimulus; // 正常翻转输入不应改变注册输出。
            #1; // 等待组合 ready 稳定，远短于最小半周期。
            if ((ready !== expected_ready) || ((rows != 0) && (actual[C_RESULT_WIDTH-2:0] !== previous_registered))) begin // 检查沿前空间与输出稳定性。
                $display("FAIL return preedge row=%0d ready=%b expected=%b", rows, ready, expected_ready); // 输出失败定位而非只报告最终计数。
                $stop; // 让 Verilator 以非零结束失败仿真。
            end // 结束沿前时序检查。
            @(posedge reg_clk); // 等待实际 DUT 状态更新沿。
            #1; // 在非阻塞赋值完成后比较注册输出。
            if (actual !== expected_result) begin // 对 VC/Pool、编码、计数和 ready 逐位比较。
                $display("FAIL return row=%0d input=%h actual=%h expected=%h", rows, stimulus, actual, expected_result); // 包括未启用许可位在内的完整输入参与失败定位。
                $stop; // 任意失配阻止测试通过。
            end // 结束沿后结果检查。
            previous_registered = actual[C_RESULT_WIDTH-2:0]; // 保存当前注册部分供下一沿前比较。
            rows = rows+1; // 只累计真实已比较的完整输入行。
        end // 结束文件向量回归循环。
        if (rows < 100) $stop; // 拒绝空文件或明显截断的小样本。
        $fclose(file_handle); // 关闭当前只读文件句柄。
        $display("PASS return rows=%0d ports=%0d depth=%0d period_ps=%0d", rows, C_NUM_PORTS, C_DEPTH, 2*C_HALF_PERIOD_PS); // 报告实际采样配置和检查数量。
        $finish; // 全部逐拍检查通过后正常结束。
    end // 结束正常返回队列向量自检过程。
    initial begin // 独立看门狗防止测试过程等待或时钟挂死。
        #1000000000; // 时间预算大于全部声明配置的正常向量时长。
        $display("FAIL return watchdog timeout"); // 超时不是通过或普通提前结束。
        $stop; // 超时必须产生工具非零结果。
    end // 结束独立测试超时保护。
endmodule // 结束 upli_credit_return_tb 自检模块。
