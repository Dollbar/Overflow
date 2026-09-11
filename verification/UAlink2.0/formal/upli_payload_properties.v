// Independent integer-ledger and shift-queue specification for the actual sender.
// 日期2026-09-08；完整字均为符号输入，无银行或存储切点，连接资格固定有效。
`timescale 1ps/1ps // 统一数字形式夹具精度，SAT 不声明模拟物理时钟。
module upli_payload_properties #( // 真实银行、准入和完整负载的独立形式比较模块。
    parameter integer C_NUM_PORTS = 1, // 有限证明展开的一、二或四个 port。
    parameter integer C_CREDIT_WIDTH = 4, // 真实账户计数宽度，保留全部高位。
    parameter integer C_REQUEST_WIDTH = 96, // 本地不透明请求容器，非标准打包。
    parameter [C_CREDIT_WIDTH-1:0] C_CAPACITY = 4, // 默认容量四，不抽象信用状态。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_REQ_CAPACITIES = {C_NUM_PORTS*5{C_CAPACITY}}, // 独立请求账户容量。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_DATA_CAPACITIES = {C_NUM_PORTS*5{C_CAPACITY}}, // 独立数据账户容量。
    parameter integer C_INIT_CYCLES = 2 // 连续过滤阈值，和实际银行同一契约。
) ( // 连接保持有效；全部返回、候选及重复 reset 自由变化。
    input wire i_clk, // 唯一共同上升沿时钟。
    input wire i_rstn, // 共同同步低有效 reset。
    input wire i_candidate_valid, // 本地完整候选有效。
    input wire [1:0] i_candidate_port, // 含未实现编码的自由 port。
    input wire [1:0] i_candidate_vc, // 任意四 VC。
    input wire i_candidate_pool, // 请求信用选择。
    input wire i_candidate_has_data, // 本地候选数据属性。
    input wire [1:0] i_candidate_num_beats, // 一至四字的长度减一。
    input wire [3:0] i_candidate_data_pools, // 全部有效及未声明 pool 位均自由。
    input wire [C_REQUEST_WIDTH-1:0] i_candidate_request, // 全位宽符号不透明请求。
    input wire [2047:0] i_candidate_data, // 四个完整符号 512 位字，不抽样少数位。
    input wire [255:0] i_candidate_byte_enable, // 全部原 ByteEn 符号输入。
    input wire [3:0] i_candidate_error, // 四个原 Error 符号输入。
    input wire [27:0] i_req_return, // 请求 valid/pool/vc/num/init 完整原生返回组合。
    input wire [27:0] i_data_return, // 数据独立返回组合，非法输入也不假定不存在。
    output wire o_violation, // 任意完整事件、余额、初始化、诊断或所有权不匹配。
    output wire [C_NUM_PORTS+11:0] o_groups, // 十二种外部／银行性质和每 port 完整队列性质分别作为归纳结论。
    output wire o_partition_gap // 检查分组并集恰好等于原始总性质，不能悄悄丢掉字段。
); // 结束完整数字比较接口。
    localparam [31:0] C_PORTS = C_NUM_PORTS; // 独立参考静态端口边界。
    localparam integer C_BANK_BITS = C_NUM_PORTS*5*C_CREDIT_WIDTH; // 一个通道的全部账户宽度。
    localparam [1:0] C_LAST_PORT = (C_NUM_PORTS == 4) ? 2'd3 : (C_NUM_PORTS == 2) ? 2'd1 : 2'd0; // 显式末 port 回零，不复用 DUT 模掩码。
    wire accepted, req_valid, req_pool, data_valid, data_pool, data_last, data_error, known, sticky; // 实际完整事件及诊断。
    wire [1:0] req_port, req_vc, data_port, data_vc, offset, phase; // 实际原生元数据与相位。
    wire [3:0] busy, req_init, data_init, ref_busy; // 实际与独立参考所有权。
    wire [C_REQUEST_WIDTH-1:0] req_payload; // 实际请求全部负载。
    wire [511:0] data_payload; // 实际数据全部位。
    wire [63:0] byte_enable; // 实际当前有效字节。
    wire [C_BANK_BITS-1:0] req_balances, data_balances; // 实际两个银行的寄存余额。
    wire [1:0] actual_errors; // 实际 Req 和 OrigData 的注册单沿错误。
    wire [2*C_BANK_BITS-1:0] ref_balances; // 独立整数账本，低半为 Req。
    wire [7:0] ref_init; // 独立确认位，低四位为 Req。
    wire [1:0] ref_errors, edge_errors; // 独立注册错误与本沿错误归约。
    wire [2*C_NUM_PORTS*5-1:0] ref_range_error; // 同时证明参考余额处于容量内，排除不可达归纳初态。
    wire [2*C_NUM_PORTS-1:0] ref_init_error; // 连续初始化隐藏阶段的关联不变式，不作为假设。
    wire [2*C_NUM_PORTS-1:0] observed_init_stage; // 证明脚本只读连接真实银行 cnt_init，绝不能作为自由输入或断开实际驱动。
    wire [C_NUM_PORTS*10-1:0] observed_descriptors; // 只读真实 offset、末 offset、原 VC 和 pool 计划，低位为 offset。
    wire [C_NUM_PORTS*1731-1:0] observed_words; // 只读真实三份静态尾槽，低片段为 offset 一。
    wire [C_NUM_PORTS-1:0] ref_burst_error; // 剩余完整队列与真实静态描述符的归纳关联，不限定自由输入。
    wire [55:0] returns; // 独立按通道提取输入，低半为 Req。
    localparam [2*C_BANK_BITS-1:0] C_ALL_CAPACITIES = {C_DATA_CAPACITIES, C_REQ_CAPACITIES}; // 真实编译期常量，不能借普通连线初始化 localparam。
    wire [C_NUM_PORTS-1:0] requests; // 根据参考余额和初始化求出的独立准入。
    wire [C_NUM_PORTS*586-1:0] port_data; // 每 port 九位控制加 577 位完整字。
    wire ref_req; // 不读取 DUT 接受信号的参考发请求资格。
    reg [585:0] ref_data; // 独立时隙选择的完整数据事件。
    reg ref_known, ref_sticky; // 参考相位已建立和粘滞诊断状态。
    reg [1:0] ref_phase; // 参考每个周期连续推进的相位。
    reg [31:0] pool_count; // 独立整数逐拍求和，不采用能力阈值网络。
    wire [31:0] vc_count; // 完整专用信用需求。
    integer idx_beat, idx_port; // 固定边界参考组合循环。
    genvar gen_ch, gen_port, gen_account; // 分通道、port、账户的实际参考状态展开。
    assign returns = {i_data_return, i_req_return}; // 两个原生通道独立输入。
    assign ref_req = |requests; // 独立参考至多一个 port 准入。
    assign vc_count = {30'd0, i_candidate_num_beats}+32'd1-pool_count; // 原长度减 pool 个数得到完整 VC 需求。
    assign o_violation = (accepted != ref_req) || (req_valid != ref_req) || ({req_port, req_vc, req_pool} != {i_candidate_port & {2{ref_req}}, i_candidate_vc & {2{ref_req}}, i_candidate_pool && ref_req}) || (req_payload != (i_candidate_request & {C_REQUEST_WIDTH{ref_req}})) || ({data_valid, data_port, data_vc, data_pool, offset, data_last, data_payload, byte_enable, data_error} != ref_data) || ({data_balances, req_balances} != ref_balances) || ({data_init, req_init} != ref_init) || (actual_errors != ref_errors) || (sticky != ref_sticky) || (busy != ref_busy) || (known != ref_known) || (phase != ref_phase) || (|ref_range_error) || (|ref_init_error) || (|ref_burst_error) || (ref_phase > C_LAST_PORT) || (!ref_known && (ref_phase != 2'd0)); // 事件及增强不变式一起证明，不能假设掉不可达状态。
    assign o_groups[0] = (accepted != ref_req) || (req_valid != ref_req) || ({req_port, req_vc, req_pool} != {i_candidate_port & {2{ref_req}}, i_candidate_vc & {2{ref_req}}, i_candidate_pool && ref_req}) || (req_payload != (i_candidate_request & {C_REQUEST_WIDTH{ref_req}})); // 请求全部控制和透明负载独立结论。
    assign o_groups[1] = ({data_valid, data_port, data_vc, data_pool, offset, data_last} != ref_data[585:577]); // 九位完整数据控制结论。
    assign o_groups[2] = (data_payload != ref_data[576:65]); // 全部五百一十二位数据，不能替换为抽样切片。
    assign o_groups[3] = (byte_enable != ref_data[64:1]); // 六十四位 ByteEn 单独结论。
    assign o_groups[4] = (data_error != ref_data[0]); // 当前完整字的原 Error 属性。
    assign o_groups[5] = (req_balances != ref_balances[0 +: C_BANK_BITS]); // 所有实际 Req 账户状态。
    assign o_groups[6] = (data_balances != ref_balances[C_BANK_BITS +: C_BANK_BITS]); // 所有实际 OrigData 账户状态。
    assign o_groups[7] = ({data_init, req_init} != ref_init); // 两路全部初始化确认位。
    assign o_groups[8] = (actual_errors != ref_errors) || (sticky != ref_sticky); // 单沿错误及跨沿粘滞诊断。
    assign o_groups[9] = (busy != ref_busy) || (known != ref_known) || (phase != ref_phase) || (ref_phase > C_LAST_PORT) || (!ref_known && (ref_phase != 2'd0)); // 全部所有权和相位等价及范围。
    assign o_groups[10] = |ref_range_error; // 完整账本的容量范围不变式。
    assign o_groups[11] = |ref_init_error; // 初始化隐藏阶段关联不变式。
    assign o_groups[12 +: C_NUM_PORTS] = ref_burst_error; // 每个实际 port 的完整未发送数据队列关联。
    assign o_partition_gap = (o_violation != (|o_groups)); // 先证明分组完全，再逐组证明同一归纳前提下的后态。
    upli_burst_sender #( // 实际产品，包括真实两个银行和全部暂存字。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), .C_REQUEST_WIDTH(C_REQUEST_WIDTH), // 有限配置展开实际硬件。
        .C_DEFAULT_CAPACITY(C_CAPACITY), .C_REQ_CAPACITIES(C_REQ_CAPACITIES), .C_DATA_CAPACITIES(C_DATA_CAPACITIES), .C_INIT_CYCLES(C_INIT_CYCLES) // 实际与参考接受同一容量契约。
    ) Sender_Inst ( // 所有实际内部状态保留，不暴露为自由输入。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_credit_connected(1'b1), .i_beats_connected(1'b1), // 正常已连接 profile，不证明真实 FSM 握手。
        .i_candidate_valid(i_candidate_valid), .i_candidate_port(i_candidate_port), .i_candidate_vc(i_candidate_vc), .i_candidate_pool(i_candidate_pool), // 完整自由候选。
        .i_candidate_has_data(i_candidate_has_data), .i_candidate_num_beats(i_candidate_num_beats), .i_candidate_data_pools(i_candidate_data_pools), // 完整长度和分配。
        .i_candidate_request(i_candidate_request), .i_candidate_data(i_candidate_data), .i_candidate_byte_enable(i_candidate_byte_enable), .i_candidate_error(i_candidate_error), // 所有 payload 位自由。
        .i_req_credit_valid(i_req_return[24 +: 4]), .i_req_credit_pool(i_req_return[20 +: 4]), .i_req_credit_vc(i_req_return[12 +: 8]), .i_req_credit_num(i_req_return[4 +: 8]), .i_req_credit_init_done(i_req_return[0 +: 4]), // 实际 Req 返回。
        .i_data_credit_valid(i_data_return[24 +: 4]), .i_data_credit_pool(i_data_return[20 +: 4]), .i_data_credit_vc(i_data_return[12 +: 8]), .i_data_credit_num(i_data_return[4 +: 8]), .i_data_credit_init_done(i_data_return[0 +: 4]), // 实际 OrigData 返回。
        .o_candidate_accepted(accepted), .o_req_valid(req_valid), .o_req_port(req_port), .o_req_vc(req_vc), .o_req_pool(req_pool), .o_req_payload(req_payload), // 实际请求事件全部比较。
        .o_data_valid(data_valid), .o_data_port(data_port), .o_data_vc(data_vc), .o_data_pool(data_pool), .o_data_offset(offset), .o_data_last(data_last), // 实际数据元信息全部比较。
        .o_data_payload(data_payload), .o_data_byte_enable(byte_enable), .o_data_error(data_error), // 不减少被证明的数据位宽。
        .o_req_balances(req_balances), .o_data_balances(data_balances), .o_req_init(req_init), .o_data_init(data_init), // 实际银行寄存状态全部比较。
        .o_req_credit_error(actual_errors[0]), .o_data_credit_error(actual_errors[1]), .o_credit_error_sticky(sticky), // 实际独立诊断及粘滞均比较。
        .o_busy(busy), .o_tdm_known(known), .o_tdm_port(phase) // 实际调度所有权及相位。
    ); // 结束完整真实发送器实例。
    always @(*) begin // 独立整数计算所有声明拍的 pool 需求。
        pool_count = 32'd0; // 完整默认值，忽略未声明高位。
        for (idx_beat = 32'd0; idx_beat < 32'd4; idx_beat = idx_beat+32'd1) begin // 固定四次参考循环。
            if (({30'd0, i_candidate_num_beats} >= idx_beat) && i_candidate_data_pools[idx_beat]) pool_count = pool_count+32'd1; // 每个声明的 pool 拍加一。
        end // 结束独立完整需求求和。
    end // 结束独立信用需求参考。
    always @(*) begin // 归约唯一参考时隙的控制与完整负载。
        ref_data = 586'd0; // 所有无效字段零。
        for (idx_port = 32'd0; idx_port < C_PORTS; idx_port = idx_port+32'd1) begin // 固定有效 port 展开。
            ref_data = ref_data | port_data[idx_port*586 +: 586]; // 参考相位确保互斥，不读 DUT 输出。
        end // 结束完整数据参考归约。
    end // 结束组合参考数据事件。
    always @(posedge i_clk) begin // 独立参考相位有效状态。
        if (!i_rstn) ref_known <= 1'b0; // reset 取消旧相位。
        else if (ref_req) ref_known <= 1'b1; // 只由独立准入建立。
    end // 结束参考相位资格。
    always @(posedge i_clk) begin // 独立参考末 port 回零计数。
        if (!i_rstn) ref_phase <= 2'd0; // 同步新 epoch 起点。
        else if (ref_known) ref_phase <= (ref_phase == C_LAST_PORT) ? 2'd0 : ref_phase+2'd1; // idle 也推进。
        else if (ref_req) ref_phase <= (i_candidate_port == C_LAST_PORT) ? 2'd0 : i_candidate_port+2'd1; // 首次参考请求选相位。
    end // 结束参考 TDM 状态。
    always @(posedge i_clk) begin // 独立在错误发生沿置位，而非复制 DUT 的延迟 OR 结构。
        if (!i_rstn) ref_sticky <= 1'b0; // 共同同步 reset 清除。
        else if (|edge_errors) ref_sticky <= 1'b1; // 任一账本错误保持到 reset。
    end // 结束独立粘滞诊断参考。
    generate // 独立整数账本及初始化计数，不使用第二个产品银行。
        for (gen_ch = 32'd0; gen_ch < 32'd2; gen_ch = gen_ch+32'd1) begin : gen_channels // 请求和数据分别具有原子更新边界。
            wire [27:0] returned; // 当前通道完整返回输入。
            wire unused_return_metadata; // 未配置 port 的无效元信息有意不参与参考账本。
            wire [3:0] port_errors; // 各 port 算术与未实现输入错误。
            wire send_valid, send_pool; // 独立参考实际发拍的信用类型。
            wire [1:0] send_port, send_vc; // 独立参考发拍元数据。
            reg reg_error; // 本通道参考注册单沿诊断。
            assign returned = returns[gen_ch*28 +: 28]; // 常量提取独立通道。
            assign unused_return_metadata = &returned; // 显式标记剩余无效字段，不改变任何功能或性质。
            assign send_valid = (gen_ch == 0) ? ref_req : ref_data[585]; // 数据有效来自独立队列事件。
            assign send_port = (gen_ch == 0) ? i_candidate_port : ref_data[583 +: 2]; // 无效发送时字段不参与账本。
            assign send_vc = (gen_ch == 0) ? i_candidate_vc : ref_data[581 +: 2]; // 原始数据 VC 来自独立参考描述符。
            assign send_pool = (gen_ch == 0) ? i_candidate_pool : ref_data[580]; // 原始数据 pool 来自右移序列。
            assign edge_errors[gen_ch] = |port_errors; // 任一账户错误只冻结这个通道。
            assign ref_errors[gen_ch] = reg_error; // 注册单沿错误直接比较。
            always @(posedge i_clk) begin // 独立错误寄存器不隐含恢复动作。
                if (!i_rstn) reg_error <= 1'b0; // reset 压过非法输入。
                else reg_error <= edge_errors[gen_ch]; // 下一合法沿错误清除。
            end // 结束参考单沿诊断。
            for (gen_port = 32'd0; gen_port < 32'd4; gen_port = gen_port+32'd1) begin : gen_bank_ports // 保留四位原生形状。
                if (gen_port < C_NUM_PORTS) begin : gen_active // 启用 port 拥有五个独立整数账户。
                    localparam [1:0] C_PORT = gen_port[1:0]; // 静态 port 编码。
                    reg [31:0] cnt_streak; // 独立已采样连续高电平次数，非 DUT 的阈值前一拍计数。
                    reg reg_initialized; // 确认后粘滞直到共同 reset。
                    wire [4:0] account_errors; // 五账户完整算术上限与下溢。
                    assign ref_init[gen_ch*4+gen_port] = reg_initialized; // 各通道独立初始化资格。
                    assign ref_init_error[gen_ch*C_NUM_PORTS+gen_port] = (reg_initialized ? (cnt_streak != C_INIT_CYCLES) : ((cnt_streak >= C_INIT_CYCLES) || (cnt_streak[0] != observed_init_stage[gen_ch*C_NUM_PORTS+gen_port]))); // 当前证明固定两拍过滤，实际一位阶段与独立已采样次数在未确认时一致。
                    assign port_errors[gen_port] = |account_errors; // 连接固定有效，启用 port 仅有账户算术错误。
                    always @(posedge i_clk) begin // 使用已采样次数的独立连续过滤参考。
                        if (!i_rstn) cnt_streak <= 32'd0; // reset 清除历史。
                        else if (!edge_errors[gen_ch] && !reg_initialized) begin // 错误沿只保持本通道参考状态。
                            if (returned[gen_port]) cnt_streak <= cnt_streak+32'd1; // 未确认时高电平累积次数。
                            else cnt_streak <= 32'd0; // 未确认低电平打断连续序列。
                        end // 结束合法未确认沿的独立计数。
                    end // 结束参考初始化连续计数。
                    always @(posedge i_clk) begin // 独立确认位使用完整次数与阈值比较。
                        if (!i_rstn) reg_initialized <= 1'b0; // 新 epoch 必须重新确认。
                        else if (!edge_errors[gen_ch] && returned[gen_port] && (cnt_streak+32'd1 >= C_INIT_CYCLES)) reg_initialized <= 1'b1; // 当前高电平计入次数，仅沿后生效。
                    end // 结束参考初始化确认。
                    for (gen_account = 32'd0; gen_account < 32'd5; gen_account = gen_account+32'd1) begin : gen_accounts // 每个账本账户独立保存余额。
                        localparam [1:0] C_VC = gen_account[1:0]; // 共享池分支忽略此常量。
                        localparam [C_CREDIT_WIDTH-1:0] C_LIMIT = C_ALL_CAPACITIES[(gen_ch*C_NUM_PORTS*5+gen_port*5+gen_account)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 本账户完整独立容量。
                        reg [C_CREDIT_WIDTH-1:0] cnt_balance; // 独立参考原始余额，不读取实际 DUT 银行。
                        wire returned_here, sent_here; // 当前账户实际归还与参考消耗。
                        wire [31:0] next_count; // 32 位整数算术覆盖最大 16 位余额、四信用归还和借位。
                        wire [C_CREDIT_WIDTH-1:0] checked_count; // 仅提交已由完整整数范围检查的低位。
                        assign returned_here = returned[24+gen_port] && ((gen_account == 4) ? returned[20+gen_port] : (!returned[20+gen_port] && (returned[12+gen_port*2 +: 2] == C_VC))); // 原生每通道每 port 仅返回一个账户。
                        assign sent_here = send_valid && (send_port == C_PORT) && ((gen_account == 4) ? send_pool : (!send_pool && (send_vc == C_VC))); // 单一实际参考 beat 只扣一个账户。
                        assign next_count = {{(32-C_CREDIT_WIDTH){1'b0}}, cnt_balance} + (returned_here ? ({30'd0, returned[4+gen_port*2 +: 2]}+32'd1) : 32'd0) - (sent_here ? 32'd1 : 32'd0); // 直接扩展加减，不采用 DUT 预计算容量减法阈值。
                        assign account_errors[gen_account] = (sent_here && (cnt_balance == {C_CREDIT_WIDTH{1'b0}})) || (next_count > {{(32-C_CREDIT_WIDTH){1'b0}}, C_LIMIT}); // 沿前非空独立于同沿净值，负值借位也超过合法容量。
                        assign ref_range_error[gen_ch*C_NUM_PORTS*5+gen_port*5+gen_account] = (cnt_balance > C_LIMIT); // 强化归纳性质本身，不通过 assume 限定银行状态。
                        assign checked_count = next_count[C_CREDIT_WIDTH-1:0]; // 显式窄化单独连线，不隐式丢弃整数检查高位。
                        assign ref_balances[(gen_ch*C_NUM_PORTS*5+gen_port*5+gen_account)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH] = cnt_balance; // 完整参考余额直接进入独立准入与比较。
                        always @(posedge i_clk) begin // 独立每账户整数账本提交。
                            if (!i_rstn) cnt_balance <= {C_CREDIT_WIDTH{1'b0}}; // reset 不预置信用。
                            else if (!edge_errors[gen_ch]) cnt_balance <= checked_count; // 整通道合法才提交已检查净值。
                        end // 结束独立参考余额更新。
                    end // 结束本 port 五账户展开。
                end else begin : gen_unused // 未实现 port 的控制必须被诊断。
                    assign ref_init[gen_ch*4+gen_port] = 1'b0; // 未实现 port 永不初始化。
                    assign port_errors[gen_port] = returned[24+gen_port] || returned[gen_port]; // 无效元信息不作为错误，有效或 done 才诊断。
                end // 结束参考银行 port 的有效分支。
            end // 结束四位参考银行 port 形状。
        end // 结束两个独立参考账本。
        for (gen_port = 32'd0; gen_port < 32'd4; gen_port = gen_port+32'd1) begin : gen_bursts // 独立参考剩余队列而非静态尾槽选择。
            if (gen_port < C_NUM_PORTS) begin : gen_active // 仅有效 port 保存独立完整负载。
                localparam [1:0] C_PORT = gen_port[1:0]; // 静态 port 编码。
                reg [1:0] cnt_remaining, cnt_next, reg_vc; // 剩余数量、递增 offset 和原始 VC 独立状态。
                reg [3:0] reg_pools; // 剩余 pool 按低位移出。
                reg [1730:0] reg_queue; // 三个完整尾字组成右移队列，不使用 DUT 的静态 offset 选槽。
                wire start, tail, slot; // 独立首字与当前 port 连续尾字。
                wire [4*C_CREDIT_WIDTH-1:0] request_vcs, data_vcs; // 参考账本的完整四专用账户。
                wire [C_CREDIT_WIDTH-1:0] req_count, data_count, pool_balance; // 先选择完整余额再作整数准入。
                wire [9:0] descriptor; // 真实原描述符仅用于性质，不驱动任何参考转移。
                wire [1730:0] words; // 真实静态槽只读观察值，不驱动参考队列。
                wire [5:0] queue_errors; // 六种仍有效的队列字关联覆盖全部 577 位。
                assign descriptor = observed_descriptors[gen_port*10 +: 10]; // 低至高为 offset、末 offset、VC、四个 pool。
                assign words = observed_words[gen_port*1731 +: 1731]; // 低至高为三个静态尾槽。
                assign queue_errors[0] = (cnt_next == 2'd1) && ({reg_pools[0], reg_queue[0 +: 577]} != {descriptor[7], words[0 +: 577]}); // 下一字为原 offset 一。
                assign queue_errors[1] = (cnt_next == 2'd1) && (cnt_remaining > 2'd1) && ({reg_pools[1], reg_queue[577 +: 577]} != {descriptor[8], words[577 +: 577]}); // 原 offset 二仍在第二队列槽。
                assign queue_errors[2] = (cnt_next == 2'd1) && (cnt_remaining > 2'd2) && ({reg_pools[2], reg_queue[1154 +: 577]} != {descriptor[9], words[1154 +: 577]}); // 原 offset 三仍在第三队列槽。
                assign queue_errors[3] = (cnt_next == 2'd2) && ({reg_pools[0], reg_queue[0 +: 577]} != {descriptor[8], words[577 +: 577]}); // 移位后原 offset 二成为队首。
                assign queue_errors[4] = (cnt_next == 2'd2) && (cnt_remaining > 2'd1) && ({reg_pools[1], reg_queue[577 +: 577]} != {descriptor[9], words[1154 +: 577]}); // 移位后原 offset 三成为第二字。
                assign queue_errors[5] = (cnt_next == 2'd3) && ({reg_pools[0], reg_queue[0 +: 577]} != {descriptor[9], words[1154 +: 577]}); // 仅余末字时原 offset 三成为队首。
                assign ref_burst_error[gen_port] = (cnt_remaining != 2'd0) && (!ref_known || !ref_init[gen_port] || !ref_init[4+gen_port] || (cnt_next == 2'd0) || (cnt_next != descriptor[1:0]) || ({1'b0, cnt_next}+{1'b0, cnt_remaining} != {1'b0, descriptor[3:2]}+3'd1) || (reg_vc != descriptor[5:4]) || (|queue_errors)); // 活动所有权必须来自双银行确认后的准入，逐字关联仅为一起证明的性质。
                assign request_vcs = ref_balances[gen_port*5*C_CREDIT_WIDTH +: 4*C_CREDIT_WIDTH]; // 独立参考请求专用账户。
                assign data_vcs = ref_balances[C_BANK_BITS+gen_port*5*C_CREDIT_WIDTH +: 4*C_CREDIT_WIDTH]; // 独立参考数据专用账户。
                assign req_count = i_candidate_pool ? ref_balances[(gen_port*5+4)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH] : request_vcs[i_candidate_vc*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 请求独立池或专用余额。
                assign data_count = data_vcs[i_candidate_vc*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 数据原 VC 的完整余额。
                assign pool_balance = ref_balances[C_BANK_BITS+(gen_port*5+4)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 数据共享池只按 port 分配。
                assign slot = !ref_known || (ref_phase == C_PORT); // 相位未建立时自由起始 port。
                assign requests[gen_port] = i_rstn && i_candidate_valid && (i_candidate_port == C_PORT) && slot && ref_init[gen_port] && (req_count != {C_CREDIT_WIDTH{1'b0}}) && (!i_candidate_has_data || ((cnt_remaining == 2'd0) && ref_init[4+gen_port] && ({{(32-C_CREDIT_WIDTH){1'b0}}, data_count} >= vc_count) && ({{(32-C_CREDIT_WIDTH){1'b0}}, pool_balance} >= pool_count))); // 独立全笔整数信用准入，不复用 DUT 能力位。
                assign start = requests[gen_port] && i_candidate_has_data; // 独立请求与首字同时发出。
                assign tail = i_rstn && ref_known && (ref_phase == C_PORT) && (cnt_remaining != 2'd0); // 正常活动尾部在每个自身 slot 必须发出。
                assign ref_busy[gen_port] = cnt_remaining != 2'd0; // 仅剩余字数定义参考所有权。
                assign port_data[gen_port*586 +: 586] = tail ? {1'b1, C_PORT, reg_vc, reg_pools[0], cnt_next, cnt_remaining == 2'd1, reg_queue[576:0]} : start ? {1'b1, C_PORT, i_candidate_vc, i_candidate_data_pools[0], 2'd0, i_candidate_num_beats == 2'd0, i_candidate_data[511:0], i_candidate_byte_enable[63:0], i_candidate_error[0]} : 586'd0; // 独立队列头构成当前完整字和原始元信息。
                always @(posedge i_clk) begin // 独立剩余字数倒数，不依赖 DUT 实际是否发出。
                    if (!i_rstn) cnt_remaining <= 2'd0; // reset 丢弃旧 burst。
                    else if (start) cnt_remaining <= i_candidate_num_beats; // 首字已发，尚余长度减一。
                    else if (tail) cnt_remaining <= cnt_remaining-2'd1; // 每个自己的 slot 退休一字。
                end // 结束独立剩余字数。
                always @(posedge i_clk) begin // 独立下一 offset 递增。
                    if (!i_rstn) cnt_next <= 2'd0; // reset 清除旧序号。
                    else if (start) cnt_next <= 2'd1; // 首字零已发。
                    else if (tail) cnt_next <= cnt_next+2'd1; // 非活动回绕值不作为输出使用。
                end // 结束参考原始 offset。
                always @(posedge i_clk) begin // 保存原始 VC，read overlay 不改写。
                    if (!i_rstn) reg_vc <= 2'd0; // reset 清除旧属性。
                    else if (start) reg_vc <= i_candidate_vc; // 只有新带数据接受才能取得所有权。
                end // 结束参考 VC 保存。
                always @(posedge i_clk) begin // 原 pool 计划顺序右移。
                    if (!i_rstn) reg_pools <= 4'd0; // reset 清除历史分配。
                    else if (start) reg_pools <= {1'b0, i_candidate_data_pools[3:1]}; // 首拍分配已消费。
                    else if (tail) reg_pools <= {1'b0, reg_pools[3:1]}; // 每个自己的 slot 进入下一分配。
                end // 结束参考 pool 序列。
                always @(posedge i_clk) begin // 独立三个完整字的右移队列。
                    if (!i_rstn) reg_queue <= 1731'd0; // reset 清除全部原负载。
                    else if (start) reg_queue <= {i_candidate_data[1536 +: 512], i_candidate_byte_enable[192 +: 64], i_candidate_error[3], i_candidate_data[1024 +: 512], i_candidate_byte_enable[128 +: 64], i_candidate_error[2], i_candidate_data[512 +: 512], i_candidate_byte_enable[64 +: 64], i_candidate_error[1]}; // 接受时完整捕获所有候选尾字，未声明字不会发出。
                    else if (tail) reg_queue <= {577'd0, reg_queue[1730:577]}; // 每个自己的 slot 移除完整队首。
                end // 结束独立完整尾部队列。
            end else begin : gen_unused // 未配置 port 不拥有数据。
                assign ref_busy[gen_port] = 1'b0; // 未实现所有权为零。
            end // 结束独立数据队列有效分支。
        end // 结束四位 burst 所有权观察形状。
    endgenerate // 结束独立账本、初始化及完整字队列。
endmodule // 结束 upli_payload_properties 完整包装器独立形式比较模块。
