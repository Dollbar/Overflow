// Credit capacity invariant; proof harness only, not a deliverable IP top.
// 日期 2026-09-08；证明复位可达状态，不假设内部计数器不会越界。
`timescale 1ps/1ps // 与被验证模块使用相同的声明精度，不产生仿真延时。
module upli_credit_bounds #( // 信用余额边界证明模块，只观察真实 DUT 状态而不切断内部反馈路径。
    parameter integer C_NUM_PORTS = 1, // 证明配置的有效端口数。
    parameter integer C_CREDIT_WIDTH = 4, // 每个账户余额的实际位宽。
    parameter integer C_INIT_CYCLES = 2, // 初始化连续采样阈值。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = 20'hf4310 // 每端口五账户的独立容量常量。
) ( // 环境输入保持任意二进制，不约束发送和归还的合法性。
    input wire i_clk, // 单一上升沿时钟，SAT 每步对应一个同步状态转移。
    input wire i_rstn, // 同步低有效复位，基例实际施加一个复位沿。
    input wire [35:0] i_events, // 除复位外与逐拍仿真向量相同的输入打包。
    output wire o_violation // 任一账户大于其容量则违反目标不变式。
); // 结束证明 harness 的参数与接口。
    localparam [31:0] C_PORT_LIMIT = C_NUM_PORTS; // 显式无符号常量别名供参数化属性展开及静态分析使用。
    wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] balances; // 被测寄存器的实际沿后余额。
    wire [C_NUM_PORTS*5-1:0] violations; // 逐账户独立比较，不复用 DUT 的越界判断。
    wire [3:0] unused_initialized; // 初始化标志不作为假设或归纳切点。
    wire unused_error; // 错误输出不作为环境合法性约束。
    genvar gen_port, gen_account; // 仅用于常量展开端口及五种账户属性。
    upli_credit_bank #( // 原样实例化当前信用银行，不使用替代算术模型。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), // 选择本次证明的真实规模。
        .C_DEFAULT_CAPACITY({C_CREDIT_WIDTH{1'b1}}), .C_CAPACITIES(C_CAPACITIES), // 显式逐账户容量避免窄默认值截断。
        .C_INIT_CYCLES(C_INIT_CYCLES) // 保留初始化资格对合法更新的影响。
    ) Credit_Inst ( // 命名端口映射避免打包顺序的隐含连接。
        .i_clk(i_clk), .i_rstn(i_rstn), // 全部状态只由真实复位和时钟驱动。
        .i_credit_connected(i_events[35]), .i_beats_connected(i_events[34]), // 不假设连接标志一致也能证明容量安全。
        .i_credit_valid(i_events[33:30]), .i_credit_pool(i_events[29:26]), // 四端口可同时归还信用。
        .i_credit_vc(i_events[25:18]), .i_credit_num(i_events[17:10]), // 两位编码保持任意取值。
        .i_credit_init_done(i_events[9:6]), .i_send_valid(i_events[5]), // 连续初始化及发送事件均不受形式环境限制。
        .i_send_port(i_events[4:3]), .i_send_vc(i_events[2:1]), .i_send_pool(i_events[0]), // 允许非法发送用于检验保持行为。
        .o_balances(balances), .o_init_confirmed(unused_initialized), .o_error(unused_error) // 只用独立余额比较形成证明属性。
    ); // 结束被测银行的完整实例。
    generate // 每账户使用独立容量作直接无符号比较。
        for (gen_port = 0; gen_port < C_PORT_LIMIT; gen_port = gen_port + 1) begin : gen_ports // 使用显式常量边界展开全部有效端口。
            for (gen_account = 0; gen_account < 5; gen_account = gen_account + 1) begin : gen_bounds // 每端口独立验证五类账户。
                localparam integer C_OFFSET = (gen_port*5+gen_account)*C_CREDIT_WIDTH; // 常量计算本账户打包偏移。
                localparam [C_CREDIT_WIDTH-1:0] C_CAPACITY = C_CAPACITIES[C_OFFSET +: C_CREDIT_WIDTH]; // 直接取得参数容量，不复用 DUT 检查逻辑。
                if (C_CAPACITY == {C_CREDIT_WIDTH{1'b1}}) begin : gen_full_range // 全位宽最大容量的上界由类型恒等满足，不证明回绕是否合法。
                    wire unused_full_balance; // 明确该分支余额仍来自真实状态但不影响恒真上界。
                    assign unused_full_balance = &balances[C_OFFSET +: C_CREDIT_WIDTH]; // 将类型恒真属性与数据功能检查分开记录。
                    assign violations[gen_port*5+gen_account] = 1'b0; // 不是假设 DUT 正确；任何同宽无符号值均不大于最大值。
                end else begin : gen_bounded // 非满位宽容量必须由独立比较证明归纳闭合。
                    assign violations[gen_port*5+gen_account] = balances[C_OFFSET +: C_CREDIT_WIDTH] > C_CAPACITY; // 不把内部 error 信号当作容量是否安全的依据。
                end // 结束类型恒真与实际有界属性分支。
            end // 结束本端口五类账户的边界属性。
        end // 结束全部端口边界属性展开。
    endgenerate // 结束编译时属性展开。
    assign o_violation = |violations; // 所有账户同时满足上界才允许归纳证明成功。
endmodule // 结束 upli_credit_bounds 复位可达状态证明 harness。
