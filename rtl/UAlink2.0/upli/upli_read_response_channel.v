`timescale 1ns/1ps // 原生同域组合字段层的仿真单位，不引入状态或延时。
`default_nettype none // 禁止隐式网络遗漏完整Read Response控制字段。
module upli_read_response_channel ( // 完整原生Read Response/Data发送字段模块，使用公共parity。
    input wire i_rstn, // 与实际发送调度器共用UPLI reset，仅组合屏蔽输出。
    input wire i_valid, // 已完成连接、信用及调度准入的真实发送事件。
    output wire o_valid, // 原生有效，不增加ready或重新扣减信用。
    input wire [1:0] i_port, // 完整原生port输入，保留全部2位。
    output wire [1:0] o_port, // 原样传递有效port字段，无效时确定零。
    input wire [63:0] i_auth_tag, // 完整原生auth_tag输入，保留全部64位。
    output wire [63:0] o_auth_tag, // 原样传递有效auth_tag字段，无效时确定零。
    input wire [9:0] i_src, // 完整原生src输入，保留全部10位。
    output wire [9:0] o_src, // 原样传递有效src字段，无效时确定零。
    input wire [9:0] i_dst, // 完整原生dst输入，保留全部10位。
    output wire [9:0] o_dst, // 原样传递有效dst字段，无效时确定零。
    input wire [10:0] i_tag, // 完整原生tag输入，保留全部11位。
    output wire [10:0] o_tag, // 原样传递有效tag字段，无效时确定零。
    input wire [1:0] i_num_beats, // 完整原生num_beats输入，保留全部2位。
    output wire [1:0] o_num_beats, // 原样传递有效num_beats字段，无效时确定零。
    input wire [511:0] i_data, // 完整原生data输入，保留全部512位。
    output wire [511:0] o_data, // 原样传递有效data字段，无效时确定零。
    input wire [3:0] i_status, // 完整原生status输入，保留全部4位。
    output wire [3:0] o_status, // 原样传递有效status字段，无效时确定零。
    input wire [1:0] i_offset, // 完整原生offset输入，保留全部2位。
    output wire [1:0] o_offset, // 原样传递有效offset字段，无效时确定零。
    input wire [0:0] i_last, // 完整原生last输入，保留全部1位。
    output wire [0:0] o_last, // 原样传递有效last字段，无效时确定零。
    input wire [0:0] i_data_error, // 完整原生data_error输入，保留全部1位。
    output wire [0:0] o_data_error, // 原样传递有效data_error字段，无效时确定零。
    input wire [1:0] i_type_info, // 完整原生type_info输入，保留全部2位。
    output wire [1:0] o_type_info, // 原样传递有效type_info字段，无效时确定零。
    input wire [1:0] i_vc, // 完整原生vc输入，保留全部2位。
    output wire [1:0] o_vc, // 原样传递有效vc字段，无效时确定零。
    input wire [0:0] i_pool, // 完整原生pool输入，保留全部1位。
    output wire [0:0] o_pool, // 原样传递有效pool字段，无效时确定零。
    output wire o_valid_parity, // RdRspVld的每周期偶校验。
    output wire o_auth_tag_parity, // 完整64位授权标签的独立偶校验。
    output wire [7:0] o_data_parity, // 每64位实际驱动数据一位偶校验，包含poison数据。
    output wire o_control_parity // 全部48位控制集合的独立偶校验。
); // 结束typed发送接口，本模块不建立响应收集或信用状态。
    wire [14:0] parity; // 公共原语完整输出，低位映射按统一约定。
    wire [14:0] unused_errors; // TX只生成parity，不把本地零received值当真实接收校验。
    wire unused_control_error, unused_data_error, unused_auth_error; // 公共检查输出在TX模式关闭。
    wire unused_parity; // 显式标记此通道不存在的信用、地址及ByteEn输出。
    assign o_valid = i_rstn && i_valid; // 同一reset条件不能与上游实际发送资格分离。
    assign o_port = i_port & {2{o_valid}}; // 完整port透传，不因status或DataError改写数据。
    assign o_auth_tag = i_auth_tag & {64{o_valid}}; // 完整auth_tag透传，不因status或DataError改写数据。
    assign o_src = i_src & {10{o_valid}}; // 完整src透传，不因status或DataError改写数据。
    assign o_dst = i_dst & {10{o_valid}}; // 完整dst透传，不因status或DataError改写数据。
    assign o_tag = i_tag & {11{o_valid}}; // 完整tag透传，不因status或DataError改写数据。
    assign o_num_beats = i_num_beats & {2{o_valid}}; // 完整num_beats透传，不因status或DataError改写数据。
    assign o_data = i_data & {512{o_valid}}; // 完整data透传，不因status或DataError改写数据。
    assign o_status = i_status & {4{o_valid}}; // 完整status透传，不因status或DataError改写数据。
    assign o_offset = i_offset & {2{o_valid}}; // 完整offset透传，不因status或DataError改写数据。
    assign o_last = i_last & {1{o_valid}}; // 完整last透传，不因status或DataError改写数据。
    assign o_data_error = i_data_error & {1{o_valid}}; // 完整data_error透传，不因status或DataError改写数据。
    assign o_type_info = i_type_info & {2{o_valid}}; // 完整type_info透传，不因status或DataError改写数据。
    assign o_vc = i_vc & {2{o_valid}}; // 完整vc透传，不因status或DataError改写数据。
    assign o_pool = i_pool & {1{o_valid}}; // 完整pool透传，不因status或DataError改写数据。
    upli_parity #(.CHANNEL_KIND(1)) u_parity ( // 使用真实公共Read Response保护组，不重复校验算法。
        .i_check_enable(1'b0), .i_valid(o_valid), // 生成始终工作，TX没有接收校验输入。
        .i_control({20'd0,o_type_info,o_tag,o_status,o_offset,o_last,o_num_beats,o_vc,o_src,o_dst,o_port,o_data_error,o_pool}), // 低48位严格包含Table2-15全部控制字段。
        .i_address(57'd0), .i_auth(o_auth_tag), .i_data(o_data), .i_byte_enable(64'd0), // Read Response含数据与授权，不含地址或ByteEn原生字段。
        .i_credit_valid(4'd0), .i_credit_pool(4'd0), .i_credit_vc(8'd0), .i_credit_num(8'd0), // 反向信用接口由独立接收与信用管理层处理。
        .i_received_parity(15'd0), .o_parity(parity), .o_errors(unused_errors), // 此处只生成真实发送字段的保护。
        .o_control_error(unused_control_error), .o_data_error(unused_data_error), .o_auth_error(unused_auth_error) // 不把禁用的检查输出伪装成RAS验证。
    ); // 结束公共parity实例。
    assign o_valid_parity = parity[0]; // 有效保护每周期由实际有效值生成。
    assign o_auth_tag_parity = parity[3]; // 授权保护独立于control与data。
    assign o_data_parity = parity[11:4]; // 低位对应Data[63:0]，所有八组均保留。
    assign o_control_parity = parity[1]; // 完整48位控制保护单独输出。
    assign unused_parity = ^{parity[14:12],parity[2]}; // Read Response没有本层信用返回、ByteEn或地址保护端口。
endmodule // 结束upli_read_response_channel原生组合发送字段模块。
`default_nettype wire // 恢复后续独立源码默认网络规则。
