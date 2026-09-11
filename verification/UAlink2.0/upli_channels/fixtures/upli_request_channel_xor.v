`timescale 1ns/1ps // 原生同钟接口的组合发送字段层，不含延时状态。
`default_nettype none // 禁止隐式网络掩盖原生字段接错。
module upli_request_channel ( // 原生Request字段发送模块，信用与TDM唯一所有权属于外部真实burst sender。
    input wire i_rstn, // 共同接口复位时屏蔽有效与所有字段。
    input wire i_valid, // 真实sender已获准发出的Request事件，不是候选valid。
    output wire o_valid, // 原生ReqVld，与实际信用消耗同一沿。
    input wire [1:0] i_asi, // 保留原生asi全部2位输入。
    output wire [1:0] o_asi, // 有效周期原样输出asi，无效时零。
    input wire [63:0] i_auth_tag, // 保留原生auth_tag全部64位输入。
    output wire [63:0] o_auth_tag, // 有效周期原样输出auth_tag，无效时零。
    input wire [9:0] i_src, // 保留原生src全部10位输入。
    output wire [9:0] o_src, // 有效周期原样输出src，无效时零。
    input wire [9:0] i_dst, // 保留原生dst全部10位输入。
    output wire [9:0] o_dst, // 有效周期原样输出dst，无效时零。
    input wire [10:0] i_tag, // 保留原生tag全部11位输入。
    output wire [10:0] o_tag, // 有效周期原样输出tag，无效时零。
    input wire [1:0] i_num_beats, // 保留原生num_beats全部2位输入。
    output wire [1:0] o_num_beats, // 有效周期原样输出num_beats，无效时零。
    input wire [56:0] i_address, // 保留原生address全部57位输入。
    output wire [56:0] o_address, // 有效周期原样输出address，无效时零。
    input wire [5:0] i_command, // 保留原生command全部6位输入。
    output wire [5:0] o_command, // 有效周期原样输出command，无效时零。
    input wire [5:0] i_length, // 保留原生length全部6位输入。
    output wire [5:0] o_length, // 有效周期原样输出length，无效时零。
    input wire [7:0] i_attr, // 保留原生attr全部8位输入。
    output wire [7:0] o_attr, // 有效周期原样输出attr，无效时零。
    input wire [7:0] i_metadata, // 保留原生metadata全部8位输入。
    output wire [7:0] o_metadata, // 有效周期原样输出metadata，无效时零。
    input wire [1:0] i_port, // 保留原生port全部2位输入。
    output wire [1:0] o_port, // 有效周期原样输出port，无效时零。
    input wire [1:0] i_vc, // 保留原生vc全部2位输入。
    output wire [1:0] o_vc, // 有效周期原样输出vc，无效时零。
    input wire [0:0] i_pool, // 保留原生pool全部1位输入。
    output wire [0:0] o_pool, // 有效周期原样输出pool，无效时零。
    output wire o_valid_parity, // ReqVld每周期的偶校验位。
    output wire o_auth_tag_parity, // 只保护完整64位授权标签。
    output wire o_address_parity, // 只保护完整57位请求地址。
    output wire o_control_parity // 保护规范明确列出的68位请求控制字段。
); // 结束原生发送端口，无ready、缓存或额外信用。
    assign o_valid = i_rstn && i_valid; // reset优先且不延后或重新预约真实发送事件。
    assign o_asi = i_asi & {2{o_valid}}; // 完整asi字段透传且确定无效输出。
    assign o_auth_tag = i_auth_tag & {64{o_valid}}; // 完整auth_tag字段透传且确定无效输出。
    assign o_src = i_src & {10{o_valid}}; // 完整src字段透传且确定无效输出。
    assign o_dst = i_dst & {10{o_valid}}; // 完整dst字段透传且确定无效输出。
    assign o_tag = i_tag & {11{o_valid}}; // 完整tag字段透传且确定无效输出。
    assign o_num_beats = i_num_beats & {2{o_valid}}; // 完整num_beats字段透传且确定无效输出。
    assign o_address = i_address & {57{o_valid}}; // 完整address字段透传且确定无效输出。
    assign o_command = i_command & {6{o_valid}}; // 完整command字段透传且确定无效输出。
    assign o_length = i_length & {6{o_valid}}; // 完整length字段透传且确定无效输出。
    assign o_attr = i_attr & {8{o_valid}}; // 完整attr字段透传且确定无效输出。
    assign o_metadata = i_metadata & {8{o_valid}}; // 完整metadata字段透传且确定无效输出。
    assign o_port = i_port & {2{o_valid}}; // 完整port字段透传且确定无效输出。
    assign o_vc = i_vc & {2{o_valid}}; // 完整vc字段透传且确定无效输出。
    assign o_pool = i_pool & {1{o_valid}}; // 完整pool字段透传且确定无效输出。
    assign o_valid_parity = o_valid; // 单比特偶校验复制valid本身。
    assign o_auth_tag_parity = ^o_auth_tag; // 授权标签独立偶校验，不混入地址或控制。
    assign o_address_parity = ^o_address; // 地址含全部高位及低位，不截断保护。
    assign o_control_parity = ^{o_tag, o_length, o_attr, o_command, o_metadata, o_vc, o_asi, o_src, o_dst, o_port, o_num_beats, o_pool}; // Table2-2定义的68位控制集合。
endmodule // 结束upli_request_channel无状态字段与parity发送模块，不声明完整Request接收功能。
`default_nettype wire // 恢复后续独立源码编译默认值。
