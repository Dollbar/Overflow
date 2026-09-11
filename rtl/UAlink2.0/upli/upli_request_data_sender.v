`default_nettype none
// UPLI normal complete-staged sender; Common 2.0 sections 2.5 and 2.7.8.
// 日期2026-09-08；真实信用银行和每端口完整尾部所有权，不包含命令编码及异常恢复。
`timescale 1ps/1ps // 编译单位精度，不在可综合逻辑中引入延时。
module upli_request_data_sender #( // 原生正常突发及本地完整候选发送模块。
    parameter integer C_NUM_PORTS = 1, // 一个 station 的有效端口只允许一、二或四。
    parameter integer C_CREDIT_WIDTH = 4, // 本地每账户计数位宽为三至十六。
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
    input wire [183:0] i_candidate_request, // 候选请求透明负载，编码由后续独立模块负责。
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
    output wire [183:0] o_req_payload, // 与实际请求同沿的透明容器。
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
    output wire [1:0] o_tdm_port, // 当前共享 Req/OrigData 时隙。
    output wire [1:0] o_req_asi,
    output wire [63:0] o_req_auth_tag,
    output wire [9:0] o_req_src,
    output wire [9:0] o_req_dst,
    output wire [10:0] o_req_tag,
    output wire [1:0] o_req_num_beats,
    output wire [56:0] o_req_address,
    output wire [5:0] o_req_command,
    output wire [5:0] o_req_length,
    output wire [7:0] o_req_attr,
    output wire [7:0] o_req_metadata,
    output wire o_req_valid_parity, o_req_auth_tag_parity, o_req_address_parity, o_req_control_parity,
    output wire o_data_valid_parity, o_data_byte_enable_parity, o_data_fields_parity,
    output wire [7:0] o_data_parity
);
    wire raw_o_req_valid;
    wire [1:0] raw_o_req_port;
    wire [1:0] raw_o_req_vc;
    wire raw_o_req_pool;
    wire [183:0] raw_o_req_payload;
    wire raw_o_data_valid;
    wire [1:0] raw_o_data_port;
    wire [1:0] raw_o_data_vc;
    wire raw_o_data_pool;
    wire [1:0] raw_o_data_offset;
    wire raw_o_data_last;
    wire [511:0] raw_o_data_payload;
    wire [63:0] raw_o_data_byte_enable;
    wire raw_o_data_error;
    wire [1:0] decoded_asi;
    wire [63:0] decoded_auth_tag;
    wire [9:0] decoded_src;
    wire [9:0] decoded_dst;
    wire [10:0] decoded_tag;
    wire [1:0] decoded_num_beats;
    wire [56:0] decoded_address;
    wire [5:0] decoded_command;
    wire [5:0] decoded_length;
    wire [7:0] decoded_attr;
    wire [7:0] decoded_metadata;
    assign {decoded_asi,decoded_auth_tag,decoded_src,decoded_dst,decoded_tag,decoded_num_beats,decoded_address,decoded_command,decoded_length,decoded_attr,decoded_metadata} = raw_o_req_payload;
    upli_burst_sender #(
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), .C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY), .C_REQ_CAPACITIES(C_REQ_CAPACITIES), .C_DATA_CAPACITIES(C_DATA_CAPACITIES), .C_INIT_COUNT_WIDTH(C_INIT_COUNT_WIDTH), .C_INIT_CYCLES(C_INIT_CYCLES), .C_REQUEST_WIDTH(184)
    ) u_shared_sender (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_credit_connected(i_credit_connected),
        .i_beats_connected(i_beats_connected),
        .i_candidate_valid(i_candidate_valid),
        .i_candidate_port(i_candidate_port),
        .i_candidate_vc(i_candidate_vc),
        .i_candidate_pool(i_candidate_pool),
        .i_candidate_has_data(i_candidate_has_data),
        .i_candidate_num_beats(i_candidate_num_beats),
        .i_candidate_data_pools(i_candidate_data_pools),
        .i_candidate_request(i_candidate_request),
        .i_candidate_data(i_candidate_data),
        .i_candidate_byte_enable(i_candidate_byte_enable),
        .i_candidate_error(i_candidate_error),
        .i_req_credit_valid(i_req_credit_valid),
        .i_req_credit_pool(i_req_credit_pool),
        .i_req_credit_vc(i_req_credit_vc),
        .i_req_credit_num(i_req_credit_num),
        .i_req_credit_init_done(i_req_credit_init_done),
        .i_data_credit_valid(i_data_credit_valid),
        .i_data_credit_pool(i_data_credit_pool),
        .i_data_credit_vc(i_data_credit_vc),
        .i_data_credit_num(i_data_credit_num),
        .i_data_credit_init_done(i_data_credit_init_done),
        .o_candidate_accepted(o_candidate_accepted),
        .o_req_valid(raw_o_req_valid),
        .o_req_port(raw_o_req_port),
        .o_req_vc(raw_o_req_vc),
        .o_req_pool(raw_o_req_pool),
        .o_req_payload(raw_o_req_payload),
        .o_data_valid(raw_o_data_valid),
        .o_data_port(raw_o_data_port),
        .o_data_vc(raw_o_data_vc),
        .o_data_pool(raw_o_data_pool),
        .o_data_offset(raw_o_data_offset),
        .o_data_last(raw_o_data_last),
        .o_data_payload(raw_o_data_payload),
        .o_data_byte_enable(raw_o_data_byte_enable),
        .o_data_error(raw_o_data_error),
        .o_req_balances(o_req_balances),
        .o_data_balances(o_data_balances),
        .o_req_init(o_req_init),
        .o_data_init(o_data_init),
        .o_req_credit_error(o_req_credit_error),
        .o_data_credit_error(o_data_credit_error),
        .o_credit_error_sticky(o_credit_error_sticky),
        .o_busy(o_busy),
        .o_tdm_known(o_tdm_known),
        .o_tdm_port(o_tdm_port)
    );
    upli_request_channel u_request (
        .i_rstn(i_rstn),
        .i_valid(raw_o_req_valid),
        .o_valid(o_req_valid),
        .i_asi(decoded_asi),
        .o_asi(o_req_asi),
        .i_auth_tag(decoded_auth_tag),
        .o_auth_tag(o_req_auth_tag),
        .i_src(decoded_src),
        .o_src(o_req_src),
        .i_dst(decoded_dst),
        .o_dst(o_req_dst),
        .i_tag(decoded_tag),
        .o_tag(o_req_tag),
        .i_num_beats(decoded_num_beats),
        .o_num_beats(o_req_num_beats),
        .i_address(decoded_address),
        .o_address(o_req_address),
        .i_command(decoded_command),
        .o_command(o_req_command),
        .i_length(decoded_length),
        .o_length(o_req_length),
        .i_attr(decoded_attr),
        .o_attr(o_req_attr),
        .i_metadata(decoded_metadata),
        .o_metadata(o_req_metadata),
        .i_port(raw_o_req_port),
        .o_port(o_req_port),
        .i_vc(raw_o_req_vc),
        .o_vc(o_req_vc),
        .i_pool(raw_o_req_pool),
        .o_pool(o_req_pool),
        .o_valid_parity(o_req_valid_parity),
        .o_auth_tag_parity(o_req_auth_tag_parity),
        .o_address_parity(o_req_address_parity),
        .o_control_parity(o_req_control_parity)
    );
    assign o_req_payload = {o_req_asi,o_req_auth_tag,o_req_src,o_req_dst,o_req_tag,o_req_num_beats,o_req_address,o_req_command,o_req_length,o_req_attr,o_req_metadata}; // Debug bundle reconstructed from actual native outputs.
    upli_orig_data_channel u_orig_data (
        .i_valid(raw_o_data_valid),
        .o_orig_data_valid(o_data_valid),
        .i_port_id(raw_o_data_port),
        .o_orig_data_port_id(o_data_port),
        .i_data(raw_o_data_payload),
        .o_orig_data(o_data_payload),
        .i_byte_en(raw_o_data_byte_enable),
        .o_orig_data_byte_en(o_data_byte_enable),
        .i_offset(raw_o_data_offset),
        .o_orig_data_offset(o_data_offset),
        .i_last(raw_o_data_last),
        .o_orig_data_last(o_data_last),
        .i_error(raw_o_data_error),
        .o_orig_data_error(o_data_error),
        .i_vc(raw_o_data_vc),
        .o_orig_data_vc(o_data_vc),
        .i_pool(raw_o_data_pool),
        .o_orig_data_pool(o_data_pool),
        .o_orig_data_valid_parity(o_data_valid_parity),
        .o_orig_data_parity(o_data_parity),
        .o_orig_data_byte_en_parity(o_data_byte_enable_parity),
        .o_orig_data_fields_parity(o_data_fields_parity)
    );
endmodule
`default_nettype wire
