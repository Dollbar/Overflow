// UPLI credit-bank model comparison; Common 2.0 section 2.6.
// 日期 2026-09-08；自检台仅检查本地信用银行，不代表完整协议认证。
`timescale 1ps/1ps // 精度覆盖默认 640 ps 和参考 6400 ps 的接口周期。
module upli_credit_tb; // 信用银行逐拍参考比较与同步性自检模块。
    parameter integer C_NUM_PORTS = 1; // 本轮配置的实际 UPLI 端口数量。
    parameter integer C_CREDIT_WIDTH = 4; // 每个信用账户的余额位宽。
    parameter integer C_INIT_CYCLES = 2; // 初始化连续高电平确认阈值。
    parameter integer C_HALF_PERIOD_PS = 320; // 接口时钟的仿真半周期。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = 20'hf4310; // 由生成器显式传入的非均匀容量。
    localparam integer C_BALANCE_BITS = C_NUM_PORTS*5*C_CREDIT_WIDTH; // 打包全部端口五类信用账户。
    reg i_clk; // 由测试过程生成的唯一时钟。
    reg [36:0] stimulus; // 四列向量中的三十七位物理输入。
    reg [C_BALANCE_BITS-1:0] expected_balances; // 来自既有 Python 账本的沿后余额。
    reg [3:0] expected_init; // 参考模型给出的已确认端口标志。
    reg expected_error; // 参考模型拒绝本沿时的本地诊断期望。
    wire [C_BALANCE_BITS-1:0] balances; // DUT 的寄存器余额观测输出。
    wire [3:0] initialized; // DUT 的初始化确认状态。
    wire error; // DUT 的注册错误输出，不是线上 RAS 字段。
    wire [C_BALANCE_BITS+4:0] observed; // 所有输出合并便于同步性检查。
    reg [C_BALANCE_BITS+4:0] before_edge; // 输入改变前的寄存器状态快照。
    reg [4095:0] vector_path; // 运行入口提供的相对或绝对向量文件路径。
    integer fd; // 只读向量文件句柄。
    integer fields; // 每行读取成功的字段数量，用于拒绝截断文件。
    integer row; // 已比较的向量行数。
    assign observed = {balances, initialized, error}; // 将全部注册输出纳入每沿检查。

    // 一个通道的全部端口共享本实例，信用返回不经过 TDM 选择。
    upli_credit_bank #( // 实例参数与向量配置严格一致。
        .C_NUM_PORTS(C_NUM_PORTS), // 选择一、二或四个有效端口。
        .C_CREDIT_WIDTH(C_CREDIT_WIDTH), // 每账户余额的位宽参数。
        .C_CAPACITIES(C_CAPACITIES), // 逐账户容量包含零、边界与非均匀值。
        .C_DEFAULT_CAPACITY({C_CREDIT_WIDTH{1'b1}}), // 避免窄位宽默认值截断，容量仍由打包值指定。
        .C_INIT_CYCLES(C_INIT_CYCLES) // 配置连续采样过滤长度。
    ) Credit_Inst ( // 通过固定输入打包映射连接待测信用银行。
        .i_clk(i_clk), .i_rstn(stimulus[36]), // 唯一时钟与同步低有效复位。
        .i_credit_connected(stimulus[35]), .i_beats_connected(stimulus[34]), // 信用方向与双向连接资格。
        .i_credit_valid(stimulus[33:30]), .i_credit_pool(stimulus[29:26]), // 四端口归还有效与共享池选择。
        .i_credit_vc(stimulus[25:18]), .i_credit_num(stimulus[17:10]), // 每端口两个编码字段。
        .i_credit_init_done(stimulus[9:6]), .i_send_valid(stimulus[5]), // 初始化电平和单拍发送事件。
        .i_send_port(stimulus[4:3]), .i_send_vc(stimulus[2:1]), .i_send_pool(stimulus[0]), // 本沿消耗的账户元信息。
        .o_balances(balances), .o_init_confirmed(initialized), .o_error(error) // 全部状态输出直接比较参考模型。
    ); // 结束信用银行的命名端口实例。

    initial begin // 依次读入向量，在上升沿前后检查稳定性与计算结果。
        i_clk = 1'b0; stimulus = 37'b0; row = 0; // 首沿复位输入由生成文件明确给出。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin // 文件路径必须显式传入，避免绑定工作目录。
            $display("FAIL missing VECTORS argument"); $stop; // 缺少测试输入须以非零退出报告。
        end // 结束必需向量参数检查。
        fd = $fopen(vector_path, "r"); // 仅打开生成向量，不访问规范或工艺库。
        if (fd == 0) begin // 文件打开失败时不能误报空测试通过。
            $display("FAIL cannot open vectors"); $stop; // 中止无输入的仿真。
        end // 结束文件句柄检查。
        before_edge = observed; // 第一沿之前不比较未复位的状态。
        fields = $fscanf(fd, "%h %h %h %h", stimulus, expected_balances, expected_init, expected_error); // 四列宽度由契约定义。
        while (fields == 4) begin // 只处理完整输入与期望行。
            #(C_HALF_PERIOD_PS-1); // 留出沿前组合稳定时间。
            if ((row > 0) && (observed !== before_edge)) begin // 同步输入不能在采样沿之间改写状态。
                $display("FAIL asynchronous update row=%0d", row); $stop; // 报告寄存器同步性错误。
            end // 结束沿前稳定性比较。
            #1 i_clk = 1'b1; // 唯一上升沿采样信用、发送和初始化状态。
            #1; // 等待非阻塞赋值完成。
            if (observed !== {expected_balances, expected_init, expected_error}) begin // 每个账户与诊断都必须一致。
                $display("FAIL row=%0d stimulus=%h actual=%h expected=%h", row, stimulus, observed, {expected_balances, expected_init, expected_error}); $stop; // 打印第一处逐拍差异。
            end // 结束参考模型沿后检查。
            #(C_HALF_PERIOD_PS-1) i_clk = 1'b0; // 完成周期并准备下一行激励。
            row = row + 1; before_edge = observed; // 保存已经验证的状态快照。
            fields = $fscanf(fd, "%h %h %h %h", stimulus, expected_balances, expected_init, expected_error); // 读取下一完整四列向量。
        end // 结束有限向量文件处理循环。
        if ((fields != -1) || !$feof(fd) || (row <= 2048)) begin // 拒绝畸形尾行和缺少定向场景的文件。
            $display("FAIL malformed or short vectors rows=%0d fields=%0d", row, fields); $stop; // 不将截断输入视为通过。
        end // 结束文件完整性与数量检查。
        $fclose(fd); // 关闭只读向量文件。
        $display("PASS credit rows=%0d ports=%0d width=%0d init=%0d period_ps=%0d", row, C_NUM_PORTS, C_CREDIT_WIDTH, C_INIT_CYCLES, C_HALF_PERIOD_PS*2); // 全部输出比较通过后报告。
        $finish; // 正常退出已验证的仿真配置。
    end // 结束向量驱动自检主过程。

    initial begin // 独立超时保护避免非法文件或时序错误无限运行。
        #(64'd1000000000000); // 有限上限足够覆盖本阶段三种测试信用位宽。
        $display("FAIL credit watchdog timeout"); $stop; // 超时明确作为失败退出。
    end // 结束独立看门狗过程。
endmodule // 结束 upli_credit_tb 信用银行自检模块。
