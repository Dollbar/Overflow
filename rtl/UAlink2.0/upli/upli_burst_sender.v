// UPLI normal complete-staged sender; Common 2.0 sections 2.5 and 2.7.8.
// 日期2026-09-08；真实信用银行和每端口完整尾部所有权，不包含命令编码及异常恢复。
`timescale 1ps/1ps // 编译单位精度，不在可综合逻辑中引入延时。
module upli_burst_sender #( // 原生正常突发及本地完整候选发送模块。
    parameter integer C_NUM_PORTS = 1, // 一个 station 的有效端口只允许一、二或四。
    parameter integer C_CREDIT_WIDTH = 4, // 本地每账户计数位宽为三至十六。
    parameter integer C_REQUEST_WIDTH = 96, // 本地 opaque 容器位宽，不是标准线上字段打包。
    parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY = 4, // 默认完整四拍容量能用最小三位账户表示。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_REQ_CAPACITIES = {C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // Req 各端口 VC0..3 和 pool 的独立容量。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_DATA_CAPACITIES = {C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // OrigData 独立容量，不与 Req 共享账户。
    parameter integer C_INIT_COUNT_WIDTH = 4, // 初始化过滤计数的参数上限位宽。
    parameter integer C_INIT_CYCLES = 2 // 连续确认长度必须大于一并能用计数器表示。
) ( // 全部接口属于同一 UPLI 同步域。
    input wire i_clk, // 唯一公共上升沿时钟。
    input wire i_rstn, // 同步低有效 reset，清除全部已接受所有权及诊断。
    input wire i_credit_connected, // Comp 到 Orig 的信用返回方向已经连接。
    input wire i_beats_connected, // 两个方向共同具备发拍资格，必须保持到 reset。
    input wire i_candidate_valid, // 上游完整候选有效，本地握手不增加原生 ready。
    input wire [1:0] i_candidate_port, // 已解码的目标 station port。
    input wire [1:0] i_candidate_vc, // 候选原始 VC 编号。
    input wire i_candidate_pool, // 请求本身使用共享池信用。
    input wire i_candidate_has_data, // 本地解码属性，非新协议线上字段。
    input wire [1:0] i_candidate_num_beats, // 数据数减一的两位编码。
    input wire [3:0] i_candidate_data_pools, // 每个有效数据字预先选择专用 VC 或 pool。
    input wire [C_REQUEST_WIDTH-1:0] i_candidate_request, // 候选请求透明负载，编码由后续独立模块负责。
    input wire [2047:0] i_candidate_data, // 全部四份原生 512 位数据，低片段为首字。
    input wire [255:0] i_candidate_byte_enable, // 每份数据独立的 64 位 ByteEn，低片段对应首字。
    input wire [3:0] i_candidate_error, // 每份数据独立的 Error 属性。
    input wire [3:0] i_req_credit_valid, // Req 各 port 独立返回有效。
    input wire [3:0] i_req_credit_pool, // Req 返回选择共享池。
    input wire [7:0] i_req_credit_vc, // Req 每 port 两位返回 VC。
    input wire [7:0] i_req_credit_num, // Req 每 port 两位信用数量减一。
    input wire [3:0] i_req_credit_init_done, // Req 初始信用发布完成持续电平。
    input wire [3:0] i_data_credit_valid, // OrigData 各 port 独立返回有效。
    input wire [3:0] i_data_credit_pool, // OrigData 返回选择共享池。
    input wire [7:0] i_data_credit_vc, // OrigData 每 port 两位返回 VC。
    input wire [7:0] i_data_credit_num, // OrigData 每 port 两位信用数量减一。
    input wire [3:0] i_data_credit_init_done, // OrigData 初始信用发布完成持续电平。
    output wire o_candidate_accepted, // 本沿请求实际发送即完成完整候选所有权转移。
    output wire o_req_valid, // 实际原生请求有效。
    output wire [1:0] o_req_port, // 实际请求的 port。
    output wire [1:0] o_req_vc, // 实际请求的 VC。
    output wire o_req_pool, // 实际请求消耗共享池信用。
    output wire [C_REQUEST_WIDTH-1:0] o_req_payload, // 与实际请求同沿的透明容器。
    output wire o_data_valid, // 实际 OrigData 发出有效。
    output wire [1:0] o_data_port, // 当前字所属原始 port。
    output wire [1:0] o_data_vc, // 当前字所属原始 VC，不被 read overlay 覆盖。
    output wire o_data_pool, // 当前字实际消耗的 pool 或专用账户。
    output wire [1:0] o_data_offset, // 原 burst 中当前字的序号。
    output wire o_data_last, // 原 burst 仅最后一个有效字置位。
    output wire [511:0] o_data_payload, // 当前原生 512 位数据。
    output wire [63:0] o_data_byte_enable, // 当前字完整 ByteEn。
    output wire o_data_error, // 当前字原 Error 属性。
    output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_req_balances, // 真实 Req 银行沿前注册余额。
    output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_data_balances, // 真实 OrigData 银行余额，包含未发的预约信用。
    output wire [3:0] o_req_init, // Req 各 port 已完成连续确认。
    output wire [3:0] o_data_init, // OrigData 各 port 已完成连续确认。
    output wire o_req_credit_error, // 真实 Req 银行的单沿注册诊断。
    output wire o_data_credit_error, // 真实 OrigData 银行的单沿注册诊断。
    output wire o_credit_error_sticky, // 直到共同 reset 清除的本地诊断，不是协议恢复。
    output wire [3:0] o_busy, // 每 port 尚有未发尾部的注册所有权。
    output wire o_tdm_known, // 首个实际请求已经建立 TDM 相位。
    output wire [1:0] o_tdm_port // 当前共享 Req/OrigData 时隙。
); // 结束外部接口声明。
    localparam [31:0] C_PORTS = C_NUM_PORTS; // 显式非负静态 port 边界，也能被轻量常量解析器识别。
    localparam [31:0] C_TAILS = C_NUM_PORTS*3; // 命名全部尾槽数量，不生成运行时边界逻辑。
    wire [C_NUM_PORTS*3*577-1:0] selected_tails; // 各静态尾槽经有效 port/offset 解码后的数据。
    wire [576:0] first_word; // 仅首拍可从当前候选直接发送。
    reg [576:0] tail_word; // 当前所有静态尾槽的互斥组合选择。
    reg reg_credit_error; // 记住前沿银行诊断，当前银行诊断另行直接汇总。
    integer idx_tail; // 组合归约的常量边界循环，不形成额外状态。
    genvar gen_port, gen_tail; // 展开每 port 的三个固定尾槽。
    assign o_req_payload = i_candidate_request & {C_REQUEST_WIDTH{o_req_valid}}; // 无效请求负载归零且不改变接受沿。
    assign first_word = {i_candidate_data[0 +: 512], i_candidate_byte_enable[0 +: 64], i_candidate_error[0]} & {577{o_data_valid && (o_data_offset == 2'd0)}}; // 首数据严格与请求同沿。
    assign {o_data_payload, o_data_byte_enable, o_data_error} = first_word | tail_word; // 首拍与静态尾槽互斥，所有无效数据字段为零。
    assign o_credit_error_sticky = reg_credit_error || o_req_credit_error || o_data_credit_error; // 当前银行注册诊断立即可见且随后被保持。
    always @(posedge i_clk) begin // 独立的本地粘滞诊断寄存器。
        if (!i_rstn) reg_credit_error <= 1'b0; // 同步 reset 唯一清除诊断的途径。
        else if (o_req_credit_error || o_data_credit_error) reg_credit_error <= 1'b1; // 不静默丢失下一合法沿就清除的银行错误。
    end // 结束粘滞诊断寄存器。
    always @(*) begin // 组合 OR 选择互斥的静态尾槽。
        tail_word = 577'd0; // 完整默认赋值，不形成组合锁存器。
        for (idx_tail = 32'd0; idx_tail < C_TAILS; idx_tail = idx_tail + 32'd1) begin // elaboration 后为固定规模选择网络。
            tail_word = tail_word | selected_tails[idx_tail*577 +: 577]; // 不动态读取未授权 SRAM 或要求读延迟。
        end // 结束所有静态尾槽归约。
    end // 结束组合尾部负载选择。
    generate // 只按常量参数生成实际寄存存储。
        if (C_REQUEST_WIDTH < 1) begin : gen_invalid_request // 透明容器不允许零或负位宽。
            upli_burst_request_width_invalid Invalid_Inst (); // 非法配置必须在层次检查被拒绝。
        end // 结束请求宽度防护，其他参数由实际子模块检查。
        for (gen_port = 32'd0; gen_port < C_PORTS; gen_port = gen_port + 32'd1) begin : gen_ports // 每 port 独立拥有三份尾数据。
            localparam [1:0] C_PORT = gen_port[1:0]; // 两位常量端口编号。
            wire flag_capture; // 当前沿接受本 port 的新带数据请求。
            assign flag_capture = o_candidate_accepted && i_candidate_has_data && (i_candidate_port == C_PORT); // read overlay 及被拒候选均不得写入。
            for (gen_tail = 32'd1; gen_tail <= 32'd3; gen_tail = gen_tail + 32'd1) begin : gen_tails // 首拍无需存储，尾部为 offset 一至三。
                localparam [1:0] C_OFFSET = gen_tail[1:0]; // 静态槽对应原始序号。
                reg [576:0] reg_payload; // 一个原子字包括 data、ByteEn 和 Error。
                assign selected_tails[(gen_port*3+gen_tail-1)*577 +: 577] = reg_payload & {577{o_data_valid && (o_data_port == C_PORT) && (o_data_offset == C_OFFSET)}}; // 只输出控制器拥有的有效原始字。
                always @(posedge i_clk) begin // 一个固定尾槽的独立时序块。
                    if (!i_rstn) reg_payload <= 577'd0; // 同步 reset 不保留旧事务数据。
                    else if (flag_capture) begin // 接受后立即获得全部声明尾部，无需上游保持。
                        if (i_candidate_num_beats >= C_OFFSET) reg_payload <= {i_candidate_data[gen_tail*512 +: 512], i_candidate_byte_enable[gen_tail*64 +: 64], i_candidate_error[gen_tail]}; // 同时采样原始数据及所有属性。
                        else reg_payload <= 577'd0; // 未声明尾槽不保存无效候选字段。
                    end // 结束实际接受时的完整捕获。
                end // 结束固定尾槽寄存器。
            end // 结束三个尾槽展开。
        end // 结束实际 port 的独立存储展开。
    endgenerate // 结束静态暂存硬件结构。
    upli_burst_control #( // 沿用独立已验证的正常突发准入和时隙控制。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH) // 与真实银行形状一致。
    ) Control_Inst ( // 输入来自真实银行注册值，不能旁路本沿返回。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_beats_connected(i_beats_connected), // 同步域和双向资格。
        .i_candidate_valid(i_candidate_valid), .i_candidate_port(i_candidate_port), .i_candidate_vc(i_candidate_vc), // 原候选描述符。
        .i_candidate_pool(i_candidate_pool), .i_candidate_has_data(i_candidate_has_data), .i_candidate_num_beats(i_candidate_num_beats), .i_candidate_data_pools(i_candidate_data_pools), // 全笔信用预约需求。
        .i_req_balances(o_req_balances), .i_data_balances(o_data_balances), .i_req_init(o_req_init), .i_data_init(o_data_init), // 沿前完整银行状态。
        .o_candidate_accepted(o_candidate_accepted), .o_req_valid(o_req_valid), .o_req_port(o_req_port), .o_req_vc(o_req_vc), .o_req_pool(o_req_pool), // 实际请求发出。
        .o_data_valid(o_data_valid), .o_data_port(o_data_port), .o_data_vc(o_data_vc), .o_data_pool(o_data_pool), .o_data_offset(o_data_offset), .o_data_last(o_data_last), // 实际数据由原描述符连续发出。
        .o_busy(o_busy), .o_tdm_known(o_tdm_known), .o_tdm_port(o_tdm_port) // 注册状态供集成观察。
    ); // 结束正常突发控制器实例。
    upli_credit_bank #( // 独立 Req 通道的真实银行，不共享 OrigData 余额。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), .C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY), .C_CAPACITIES(C_REQ_CAPACITIES), // 显式传递默认及逐账户容量，避免最窄计数截断默认八信用。
        .C_INIT_COUNT_WIDTH(C_INIT_COUNT_WIDTH), .C_INIT_CYCLES(C_INIT_CYCLES) // 沿前初始化确认过滤。
    ) Req_Bank_Inst ( // 只按实际请求发出一次扣减。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_credit_connected(i_credit_connected), .i_beats_connected(i_beats_connected), // 共同域及实际连接方向。
        .i_credit_valid(i_req_credit_valid), .i_credit_pool(i_req_credit_pool), .i_credit_vc(i_req_credit_vc), .i_credit_num(i_req_credit_num), .i_credit_init_done(i_req_credit_init_done), // 独立逐 port 返回。
        .i_send_valid(o_req_valid), .i_send_port(o_req_port), .i_send_vc(o_req_vc), .i_send_pool(o_req_pool), // 请求原生事件直接送入真实银行。
        .o_balances(o_req_balances), .o_init_confirmed(o_req_init), .o_error(o_req_credit_error) // 对外保留实际余额与本地错误。
    ); // 结束 Req 信用银行实例。
    upli_credit_bank #( // 独立 OrigData 通道银行保存尚未发出的预约信用。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), .C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY), .C_CAPACITIES(C_DATA_CAPACITIES), // 实际数据账户独立容量，最窄配置也覆盖子模块默认值。
        .C_INIT_COUNT_WIDTH(C_INIT_COUNT_WIDTH), .C_INIT_CYCLES(C_INIT_CYCLES) // 与 Req 各自独立的确认状态。
    ) Data_Bank_Inst ( // 不在接受时预扣整个 burst，只扣本沿一个字。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_credit_connected(i_credit_connected), .i_beats_connected(i_beats_connected), // 数据发送的共同连接资格。
        .i_credit_valid(i_data_credit_valid), .i_credit_pool(i_data_credit_pool), .i_credit_vc(i_data_credit_vc), .i_credit_num(i_data_credit_num), .i_credit_init_done(i_data_credit_init_done), // 实际 OrigData 返回。
        .i_send_valid(o_data_valid), .i_send_port(o_data_port), .i_send_vc(o_data_vc), .i_send_pool(o_data_pool), // 原生实际数据事件唯一消耗信用。
        .o_balances(o_data_balances), .o_init_confirmed(o_data_init), .o_error(o_data_credit_error) // 错误诊断不能静默清除。
    ); // 结束 OrigData 银行实例。
endmodule // 结束正常完整暂存突发发送器。
