// Initial credit conservation properties; instrumented observation ports only.
// 日期 2026-09-08；额外观测端口由 Yosys 接到真实内部驱动，不切断或替换状态。
`timescale 1ps/1ps // 与 DUT 精度声明一致，不产生时钟延时。
module upli_credit_initialization_properties #( // 初始信用资源守恒与完成保持的形式检查模块。
    parameter integer C_NUM_PORTS = 1, // 本次证明的实际端口数。
    parameter integer C_CREDIT_WIDTH = 4, // 接收容量和 DUT 计数器位宽。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = 20'hf4310 // 本次证明的静态五账户容量。
) ( // 时钟、复位和连接输入均来自真实环境符号量。
    input wire i_clk, // 一个形式步骤对应一个同步上升沿。
    input wire i_rstn, // 同步复位既清 DUT 也清已观察发布总数。
    input wire i_credit_connected, // 不限制连接延迟，守恒属性亦允许暂停扫描。
    output wire o_violation // 任一资源守恒、元信息或完成保持属性不满足。
); // 结束形式检查模块接口。
    localparam [31:0] C_PORT_LIMIT = C_NUM_PORTS; // 显式常量边界供静态展开分析使用。
    wire [3:0] valid, pool, done; // DUT 真实输出的有效、池和完成电平。
    wire [7:0] vcs, nums; // 每端口真实输出的 VC 和数量编码。
    wire [C_NUM_PORTS*3-1:0] stages; // 脚本仅增加输出观测的真实账户阶段。
    wire [C_NUM_PORTS*C_CREDIT_WIDTH-1:0] issued; // 真实当前账户已调度数，绝不作为可任意驱动的输入。
    wire [C_NUM_PORTS*5-1:0] account_bad; // 独立累加器和 DUT 调度状态的守恒关系。
    wire [C_NUM_PORTS-1:0] control_bad; // 完成、非法阶段和池初始 VC 的属性归约。
    reg [3:0] previous_done; // 仅用于观察完成电平的粘滞性。
    genvar gen_port, gen_account; // 常量展开所有实际端口及其五账户。
    upli_credit_initializer Init_Inst ( // 此实例使用脚本先参数化且只增观测端口的真实 DUT。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_credit_connected(i_credit_connected), // 不增加假设合法余额或内部初始化状态的输入。
        .o_credit_valid(valid), .o_credit_pool(pool), .o_credit_vc(vcs), .o_credit_num(nums), .o_credit_init_done(done), // 原始功能端口全部保持真实连接。
        .o_formal_stages(stages), .o_formal_issued(issued) // 仅输出端口，不是 cut point 或可自由变化的替代值。
    ); // 结束保留原始驱动的 DUT 观测实例。
    always @(posedge i_clk) begin // 保存前一完成电平用于检查只能被复位撤销。
        if (!i_rstn) previous_done <= 4'b0000; // 同步复位不对复位前完成状态作保持要求。
        else previous_done <= done; // 记录真实 DUT 的旧完成输出。
    end // 结束完成状态历史寄存器。
    generate // 形式累加器与 RTL 当前账户计数的实现相互独立。
        for (gen_port = 0; gen_port < C_PORT_LIMIT; gen_port = gen_port + 1) begin : gen_ports // 验证每个有效端口而非只验证端口零。
            wire [2:0] stage; // 本端口真实扫描阶段观测。
            assign stage = stages[gen_port*3 +: 3]; // 固定三位切片不改变状态编码。
            assign control_bad[gen_port] = (stage > 3'd5) || (done[gen_port] && valid[gen_port]) || (previous_done[gen_port] && !done[gen_port]) || (valid[gen_port] && pool[gen_port] && (vcs[gen_port*2 +: 2] != 2'd0)); // 完成不得重叠初始批次，且初始池 VC 按本地契约固定零。
            for (gen_account = 0; gen_account < 5; gen_account = gen_account + 1) begin : gen_accounts // 独立累加全部五类资源，不能漏掉共享池。
                localparam [2:0] C_ACCOUNT = gen_account[2:0]; // 本账户与三位扫描阶段比较的常量。
                localparam [1:0] C_VC = gen_account[1:0]; // 专用 VC 匹配的双位常量。
                localparam [C_CREDIT_WIDTH-1:0] C_CAPACITY = C_CAPACITIES[(gen_port*5+gen_account)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 本账户必须恰好发布的静态容量。
                reg [C_CREDIT_WIDTH:0] cnt_seen; // 已在之前输出周期观察到的累计发布数量，额外一位防止容量处回绕隐藏。
                wire match; // 当前注册批次是否属于这个账户。
                wire [2:0] pending; // 当前尚未进入观察累加器的一至四信用。
                wire [C_CREDIT_WIDTH+1:0] advertised; // 历史加当前输出的完整扩展数量。
                wire [C_CREDIT_WIDTH+1:0] expected_scheduled; // 从真实扫描阶段导出的调度守恒目标。
                assign match = valid[gen_port] && ((gen_account == 4) ? pool[gen_port] : (!pool[gen_port] && (vcs[gen_port*2 +: 2] == C_VC))); // 通过输出元信息独立归属账户。
                assign pending = match ? ({1'b0, nums[gen_port*2 +: 2]} + 3'd1) : 3'd0; // 明确解释真实输出的数量加一编码。
                assign advertised = {1'b0, cnt_seen} + {{(C_CREDIT_WIDTH-1){1'b0}}, pending}; // 额外宽度保护观察加法，不复用 DUT 内部余额算法。
                assign expected_scheduled = (stage > C_ACCOUNT) ? {2'b00, C_CAPACITY} : ((stage == C_ACCOUNT) ? {2'b00, issued[gen_port*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]} : {(C_CREDIT_WIDTH+2){1'b0}}); // 过去账户已全发、当前账户等于真实计数、未来账户尚未发。
                assign account_bad[gen_port*5+gen_account] = (advertised != expected_scheduled) || (advertised > {2'b00, C_CAPACITY}) || (done[gen_port] && ({1'b0, cnt_seen} != {2'b00, C_CAPACITY})); // 把用于归纳的状态关系也作为待证明属性，不预先假设它成立。
                always @(posedge i_clk) begin // 独立观察已驱动的注册输出，不修改 DUT。
                    if (!i_rstn) cnt_seen <= {(C_CREDIT_WIDTH+1){1'b0}}; // 复位优先取消旧输出周期的信用累加。
                    else cnt_seen <= cnt_seen + {{(C_CREDIT_WIDTH-2){1'b0}}, pending}; // 正常周期按实际输出累计，越界由扩展属性捕获。
                end // 结束独立发布总数观察寄存器。
            end // 结束本端口五账户守恒属性。
        end // 结束有效端口属性展开。
    endgenerate // 结束初始信用形式检查结构。
    assign o_violation = (|account_bad) || (|control_bad); // 只有全部独立检查均成立才允许形式证明通过。
endmodule // 结束 upli_credit_initialization_properties 形式守恒检查模块。
