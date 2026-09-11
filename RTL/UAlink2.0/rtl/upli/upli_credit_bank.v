// UPLI single-channel credit bank; Common 2.0 sections 2.6 and 4.3.
// 日期 2026-09-08；同步信用寄存器，不含数据存储、调度器或线上 RAS 状态机。
// Capacity/init widths are local implementation limits, not protocol maxima.
// 本地错误整沿保持；集成层仍须在真实发送前确保信用资格，不能撤销已发送数据。
`timescale 1ps/1ps // 统一仿真编译单位精度，不在可综合逻辑中引入延时。
module upli_credit_bank #( // 信用银行模块为一个 UPLI 通道提供所有配置端口的独立账户。
    parameter integer C_NUM_PORTS = 1, // 实际端口数量仅允许一、二或四。
    parameter integer C_CREDIT_WIDTH = 4, // 单个账户计数器宽度，支持三至十六位。
    parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY = 8, // 未逐账户覆盖时使用的接收容量。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = {C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 低位起依次为每端口 VC0..3 和共享池。
    parameter integer C_INIT_COUNT_WIDTH = 4, // 连续初始化采样计数器的位宽。
    parameter integer C_INIT_CYCLES = 2 // 过滤阈值必须大于一且能用计数器表示。
) ( // 按连接、信用返回、发送事件和状态分组声明原生接口。
    input wire i_clk, // 全部输入输出属于同一 UPLI 上升沿时钟域。
    input wire i_rstn, // 同步低有效复位，优先清空信用及初始化状态。
    input wire i_credit_connected, // 当前通道信用返回方向已经建立连接。
    input wire i_beats_connected, // 两个连接方向均完成，但不包含信用资格。
    input wire [3:0] i_credit_valid, // 每端口独立返回有效，不受发送 TDM 限制。
    input wire [3:0] i_credit_pool, // 有效返回选择共享池而非专用 VC 账户。
    input wire [7:0] i_credit_vc, // 每端口两位 VC 元信息，低两位对应端口零。
    input wire [7:0] i_credit_num, // 每端口两位编码，实际归还数量为编码加一。
    input wire [3:0] i_credit_init_done, // 接收侧初始信用发布完成的持续电平。
    input wire i_send_valid, // 本通道当前沿确实发送一拍的事件。
    input wire [1:0] i_send_port, // 已发一拍所消耗的端口账户。
    input wire [1:0] i_send_vc, // 已发一拍对应的 VC，池账户跨 VC 共享。
    input wire i_send_pool, // 已发一拍消耗共享池时置位。
    output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_balances, // 注册余额，顺序与容量参数一致。
    output wire [3:0] o_init_confirmed, // 各端口经过连续采样后的粘滞确认标志。
    output wire o_error // 上一个采样沿被本地账本拒绝的诊断，不是协议线上字段。
); // 结束参数与接口定义。
    wire [3:0] flag_port_error; // 每端口返回、初始化及发送资格错误的组合归约。
    wire flag_edge_error; // 整个通道同沿原子更新的阻断条件。
    reg reg_error_o; // 当前沿诊断输出寄存器，下一合法沿清零。
    genvar gen_port, gen_account; // 常量展开端口与五类账户，避免运行时动态索引。
    assign flag_edge_error = |flag_port_error; // 任一账户错误均保持整沿所有状态。
    assign o_error = reg_error_o; // 对外只暴露注册诊断，避免组合错误毛刺。
    always @(posedge i_clk) begin // 注册当前采样沿的本地诊断结果。
        if (!i_rstn) reg_error_o <= 1'b0; // 同步复位压过任何错误输入。
        else reg_error_o <= flag_edge_error; // 合法沿自动清除上一沿诊断。
    end // 结束本地错误寄存器更新。

    generate // 仅以常量参数选择合法硬件规模。
        if (((C_NUM_PORTS != 1) && (C_NUM_PORTS != 2) && (C_NUM_PORTS != 4)) || (C_CREDIT_WIDTH < 3) || (C_CREDIT_WIDTH > 16) || (C_INIT_COUNT_WIDTH < 1) || (C_INIT_COUNT_WIDTH > 16) || (C_INIT_CYCLES < 2) || ((C_INIT_CYCLES >> C_INIT_COUNT_WIDTH) != 0)) begin : gen_invalid // 非法参数不能静默形成截断状态机。
            upli_credit_parameters_invalid Invalid_Inst (); // 有意未定义模块使层次检查拒绝非法配置。
        end // 结束非法参数 elaboration 防护。
        for (gen_port = 0; gen_port < 4; gen_port = gen_port + 1) begin : gen_ports // 保留四位协议形状，未使用端口明确禁用。
            localparam [1:0] C_PORT = gen_port[1:0]; // 将生成索引转换为两位端口比较常量。
            wire flag_send_port; // 当前发送事件是否指向本端口。
            assign flag_send_port = i_send_valid && (i_send_port == C_PORT); // 无效发送的元信息不参与检查。
            if (gen_port < C_NUM_PORTS) begin : gen_active // 只为启用端口生成状态寄存器。
                localparam integer C_INIT_LAST_VALUE = C_INIT_CYCLES - 1; // 保存阈值前一拍的完整常量，避免窄位宽先截断阈值。
                localparam integer C_INIT_BITS = (C_INIT_CYCLES <= 2) ? 1 : // 最短过滤只需记录一个已采样的高电平。
                    (C_INIT_CYCLES <= 4) ? 2 : (C_INIT_CYCLES <= 8) ? 3 : // 三至八拍过滤使用精确的饱和计数宽度。
                    (C_INIT_CYCLES <= 16) ? 4 : (C_INIT_CYCLES <= 32) ? 5 : // 只存储实际可能到达的初始化计数范围。
                    (C_INIT_CYCLES <= 64) ? 6 : (C_INIT_CYCLES <= 128) ? 7 : // 阈值范围由原参数合法性检查约束。
                    (C_INIT_CYCLES <= 256) ? 8 : (C_INIT_CYCLES <= 512) ? 9 : // 常量选择在 elaboration 完成，不形成数据路径。
                    (C_INIT_CYCLES <= 1024) ? 10 : (C_INIT_CYCLES <= 2048) ? 11 : // 保留长初始化过滤的参数能力。
                    (C_INIT_CYCLES <= 4096) ? 12 : (C_INIT_CYCLES <= 8192) ? 13 : // 不将计数优化错误解释为协议阈值上限。
                    (C_INIT_CYCLES <= 16384) ? 14 : (C_INIT_CYCLES <= 32768) ? 15 : 16; // 最大有效参数仍由十六位计数表示。
                localparam [C_INIT_BITS-1:0] C_INIT_LAST = C_INIT_LAST_VALUE[C_INIT_BITS-1:0]; // 在确认不会溢出的范围中显式取位。
                reg [C_INIT_BITS-1:0] cnt_init; // 只实现可达计数位，避免冗余高位进位链和保持扇出。
                reg reg_init_o; // 初始化已确认后保持至复位的状态。
                wire [4:0] flag_account_error; // 四个专用 VC 和单共享池的算术错误。
                wire flag_control_error; // 连接方向或沿前初始化资格不满足。
                assign o_init_confirmed[gen_port] = reg_init_o; // 未确认端口不能在确认同沿旁路发送。
                assign flag_control_error = (i_credit_valid[gen_port] && !i_credit_connected) || (!reg_init_o && i_credit_init_done[gen_port] && !i_credit_connected) || (flag_send_port && (!i_beats_connected || !i_credit_connected || !reg_init_o)); // 已确认后忽略 done 后续电平变化。
                assign flag_port_error[gen_port] = flag_control_error || (|flag_account_error); // 汇总本端口控制和账户越界。
                always @(posedge i_clk) begin // 连续初始化计数只在合法沿前进。
                    if (!i_rstn) cnt_init <= {C_INIT_BITS{1'b0}}; // 同步复位清除短脉冲历史。
                    else if (!flag_edge_error && !reg_init_o) begin // 确认后冻结计数且错误沿不改变历史。
                        if (!i_credit_init_done[gen_port]) cnt_init <= {C_INIT_BITS{1'b0}}; // 低电平打断未完成的连续采样。
                        else if (cnt_init != C_INIT_LAST) cnt_init <= cnt_init + {{(C_INIT_BITS-1){1'b0}}, 1'b1}; // 显式位宽加一且确认阈值处饱和。
                    end // 结束未确认端口的合法沿计数更新。
                end // 结束初始化连续采样计数器。
                always @(posedge i_clk) begin // 独立寄存初始化完成标志。
                    if (!i_rstn) reg_init_o <= 1'b0; // 复位后必须重新接收初始信用。
                    else if (!flag_edge_error && !reg_init_o && i_credit_init_done[gen_port] && (cnt_init == C_INIT_LAST)) reg_init_o <= 1'b1; // 连续阈值到达后沿后确认并粘滞保持。
                end // 结束初始化确认状态寄存器。
                for (gen_account = 0; gen_account < 5; gen_account = gen_account + 1) begin : gen_accounts // 每端口五个物理独立计数器。
                    localparam [1:0] C_VC = gen_account[1:0]; // 专用账户使用 VC 编码，池分支不使用此比较。
                    localparam [C_CREDIT_WIDTH-1:0] C_CAPACITY = C_CAPACITIES[(gen_port*5+gen_account)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 常量提取本账户配置容量。
                    reg [C_CREDIT_WIDTH-1:0] cnt_balance_o; // 发送方持有的沿前可用信用数量。
                    wire flag_return_account, flag_send_account; // 本账户匹配的归还与消耗事件。
                    wire [2:0] return_count; // 三位表示实际一至四个信用，禁止两位加法回绕。
                    wire [C_CREDIT_WIDTH+2:0] next_balance; // 扩展算术同时容纳最大余额、四信用返回及下溢检测。
                    wire unused_balance_upper; // 上界已由并行比较证明，高位不参与状态存储。
                    wire [4:0] flag_excess; // 预先比较增加零至四个信用是否超容量，避免错误路径串联加减器。
                    reg [1:0] flag_return_excess; // 低位为不发送的返回越界，高位为同账户发送的返回越界。
                    localparam [C_CREDIT_WIDTH:0] C_LIMIT_ONE = {1'b0, C_CAPACITY} - {{(C_CREDIT_WIDTH-2){1'b0}}, 3'd1}; // 容量减一的扩展常量，容量不足另行检测。
                    localparam [C_CREDIT_WIDTH:0] C_LIMIT_TWO = {1'b0, C_CAPACITY} - {{(C_CREDIT_WIDTH-2){1'b0}}, 3'd2}; // 容量减二的扩展常量。
                    localparam [C_CREDIT_WIDTH:0] C_LIMIT_THREE = {1'b0, C_CAPACITY} - {{(C_CREDIT_WIDTH-2){1'b0}}, 3'd3}; // 容量减三的扩展常量。
                    localparam [C_CREDIT_WIDTH:0] C_LIMIT_FOUR = {1'b0, C_CAPACITY} - {{(C_CREDIT_WIDTH-2){1'b0}}, 3'd4}; // 容量减四的扩展常量。
                    assign flag_return_account = i_credit_valid[gen_port] && ((gen_account == 4) ? i_credit_pool[gen_port] : (!i_credit_pool[gen_port] && (i_credit_vc[gen_port*2 +: 2] == C_VC))); // 共享池不以 VC 再分账户。
                    assign flag_send_account = flag_send_port && ((gen_account == 4) ? i_send_pool : (!i_send_pool && (i_send_vc == C_VC))); // 每个发送事件仅消耗一个匹配账户。
                    assign return_count = flag_return_account ? ({1'b0, i_credit_num[gen_port*2 +: 2]} + 3'd1) : 3'd0; // 无效归还时忽略全部元信息。
                    assign next_balance = {3'b000, cnt_balance_o} + {{C_CREDIT_WIDTH{1'b0}}, return_count} - {{(C_CREDIT_WIDTH+2){1'b0}}, flag_send_account}; // 同拍收发按净值更新，但另查沿前非空。
                    assign unused_balance_upper = |next_balance[C_CREDIT_WIDTH+2:C_CREDIT_WIDTH]; // 显式标记通过独立上界检查后丢弃的算术高位。
                    assign flag_excess[0] = 1'b0; // 复位后余额不超过容量的不变式保证净增零无需上溢检查。
                    assign flag_excess[1] = C_LIMIT_ONE[C_CREDIT_WIDTH] || ({1'b0, cnt_balance_o} > C_LIMIT_ONE); // 常量减法借位表示容量小于一。
                    assign flag_excess[2] = C_LIMIT_TWO[C_CREDIT_WIDTH] || ({1'b0, cnt_balance_o} > C_LIMIT_TWO); // 常量减法借位表示容量小于二。
                    assign flag_excess[3] = C_LIMIT_THREE[C_CREDIT_WIDTH] || ({1'b0, cnt_balance_o} > C_LIMIT_THREE); // 常量减法借位表示容量小于三。
                    assign flag_excess[4] = C_LIMIT_FOUR[C_CREDIT_WIDTH] || ({1'b0, cnt_balance_o} > C_LIMIT_FOUR); // 常量减法借位表示容量小于四。
                    always @(*) begin // 组合选择净增量的预计算上界，不依赖余额加减结果。
                        flag_return_excess = 2'b00; // 两种假设均完整默认赋值，避免组合锁存器。
                        case (i_credit_num[gen_port*2 +: 2]) // 返回编码只在本账户归还有效时参与最终检查。
                            2'd0: flag_return_excess = {flag_excess[0], flag_excess[1]}; // 一信用归还的两种净增量为零和一。
                            2'd1: flag_return_excess = {flag_excess[1], flag_excess[2]}; // 两信用归还的两种净增量为一和二。
                            2'd2: flag_return_excess = {flag_excess[2], flag_excess[3]}; // 三信用归还的两种净增量为二和三。
                            2'd3: flag_return_excess = {flag_excess[3], flag_excess[4]}; // 四信用归还的两种净增量为三和四。
                            default: flag_return_excess = 2'b00; // 二进制输入已穷举，默认保持确定性组合输出。
                        endcase // 结束信用编码对应净增量选择。
                    end // 结束与算术数据路径并行的越界检查。
                    assign flag_account_error[gen_account] = (flag_send_account && (cnt_balance_o == {C_CREDIT_WIDTH{1'b0}})) || (flag_return_account && (flag_send_account ? flag_return_excess[1] : flag_return_excess[0])); // 消耗只需非空检查，只有有效增加可能突破容量上界。
                    assign o_balances[(gen_port*5+gen_account)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH] = cnt_balance_o; // 所有余额均来自当前寄存器状态。
                    always @(posedge i_clk) begin // 更新本账户信用，不引入额外流水延迟。
                        if (!i_rstn) cnt_balance_o <= {C_CREDIT_WIDTH{1'b0}}; // 复位后发送方没有任何信用。
                        else if (!flag_edge_error) cnt_balance_o <= next_balance[C_CREDIT_WIDTH-1:0]; // 只在整沿合法时提交显式截取的已检查结果。
                    end // 结束独立信用余额寄存器更新。
                end // 结束本端口五个账户生成循环。
            end else begin : gen_unused // 不启用的协议端口不生成信用存储。
                wire unused_credit_fields; // 标明未启用端口的无效元信息有意不参与状态计算。
                assign unused_credit_fields = &{i_credit_pool[gen_port], i_credit_vc[gen_port*2 +: 2], i_credit_num[gen_port*2 +: 2]}; // 仅消除未用引脚歧义，不影响任何功能输出。
                assign o_init_confirmed[gen_port] = 1'b0; // 未实现端口永远不具备初始化资格。
                assign flag_port_error[gen_port] = i_credit_valid[gen_port] || i_credit_init_done[gen_port] || flag_send_port; // 本地集成契约禁止使用未配置端口。
            end // 结束有效与未使用端口的生成分支。
        end // 结束四端口协议形状的生成循环。
    endgenerate // 结束信用银行参数化硬件结构。
endmodule // 结束 upli_credit_bank 单通道信用银行模块。
