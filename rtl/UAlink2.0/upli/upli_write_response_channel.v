// Native UPLI Write Response TX fields; Common 2.0 Table 2-18 and sections 2.5/2.7.8/3.1.1.
// 日期2026-09-11；组合发送字段与公共偶校验，不含接收、信用或命令执行状态。
`timescale 1ns/1ps // 与公共保护原语一致的编译单位，不在硬件中产生延时。
`default_nettype none // 禁止隐式网络掩盖完整原生字段的连接错误。
module upli_write_response_channel ( // 原生 Write Response 组合发送模块，发出资格由上游负责。
    input wire i_rstn, // 共同接口复位在此组合层屏蔽原生有效及字段。
    input wire i_valid, // 已具备连接与信用资格的实际响应事件，不是未接受候选。
    output wire o_valid, // 与输入事件同周期的原生 WrRspVld。
    input wire [1:0] i_type_info, // 接收原请求类别提示的全部2位。
    output wire [1:0] o_type_info, // 有效周期完整保留原请求类别提示，其余周期为零。
    input wire [10:0] i_tag, // 接收原请求完整事务标签的全部11位。
    output wire [10:0] o_tag, // 有效周期完整保留原请求完整事务标签，其余周期为零。
    input wire [3:0] i_status, // 接收响应状态编码的全部4位。
    output wire [3:0] o_status, // 有效周期完整保留响应状态编码，其余周期为零。
    input wire [9:0] i_src, // 接收响应源物理加速器标识的全部10位。
    output wire [9:0] o_src, // 有效周期完整保留响应源物理加速器标识，其余周期为零。
    input wire [9:0] i_dst, // 接收用于返回路由的目标物理加速器标识的全部10位。
    output wire [9:0] o_dst, // 有效周期完整保留用于返回路由的目标物理加速器标识，其余周期为零。
    input wire [1:0] i_port, // 接收本拍响应端口及其独立 TDM 相位的全部2位。
    output wire [1:0] o_port, // 有效周期完整保留本拍响应端口及其独立 TDM 相位，其余周期为零。
    input wire [1:0] i_vc, // 接收原事务虚拟通道的全部2位。
    output wire [1:0] o_vc, // 有效周期完整保留原事务虚拟通道，其余周期为零。
    input wire i_pool, // 接收本拍实际消耗的信用类型的全部1位。
    output wire o_pool, // 有效周期完整保留本拍实际消耗的信用类型，其余周期为零。
    input wire [63:0] i_auth_tag, // 接收完整响应授权标签的全部64位。
    output wire [63:0] o_auth_tag, // 有效周期完整保留完整响应授权标签，其余周期为零。
    output wire o_valid_parity, // 每周期保护 WrRspVld 的独立偶校验。
    output wire o_auth_tag_parity, // 独立保护完整授权标签，不替代认证验证。
    output wire o_control_parity // 保护规范指定的四十二位响应控制字段。
); // 结束原生发送端口，不增加 ready 或新的信用接口。
    wire [14:0] parity_all; // 公共原语统一保护码，仅输出本通道的三个发送组。
    wire unused_parity_groups; // 显式收集本 TX 接口不使用的其他通道与信用保护位。
    wire [14:0] unused_errors; // 本实例关闭接收检查，因此不暴露误导性的 RAS 诊断。
    wire unused_control_error, unused_data_error, unused_auth_error; // 公共原语的接收分类输出在发送模式下不使用。
    assign o_valid = i_rstn && i_valid; // 复位优先且不插入保存、预约或额外流水。
    assign o_type_info = i_type_info & {2{o_valid}}; // 保留原请求类别提示全部位并确定闲置输出。
    assign o_tag = i_tag & {11{o_valid}}; // 保留原请求完整事务标签全部位并确定闲置输出。
    assign o_status = i_status & {4{o_valid}}; // 保留响应状态编码全部位并确定闲置输出。
    assign o_src = i_src & {10{o_valid}}; // 保留响应源物理加速器标识全部位并确定闲置输出。
    assign o_dst = i_dst & {10{o_valid}}; // 保留用于返回路由的目标物理加速器标识全部位并确定闲置输出。
    assign o_port = i_port & {2{o_valid}}; // 保留本拍响应端口及其独立 TDM 相位全部位并确定闲置输出。
    assign o_vc = i_vc & {2{o_valid}}; // 保留原事务虚拟通道全部位并确定闲置输出。
    assign o_pool = i_pool & {1{o_valid}}; // 保留本拍实际消耗的信用类型全部位并确定闲置输出。
    assign o_auth_tag = i_auth_tag & {64{o_valid}}; // 保留完整响应授权标签全部位并确定闲置输出。
    assign o_valid_parity = parity_all[0]; // 原生有效保护对应统一原语的第一位。
    assign o_auth_tag_parity = parity_all[3]; // 授权标签有独立保护组，不混入控制校验。
    assign o_control_parity = parity_all[1]; // 四十二位控制组对应统一保护码的控制位。
    assign unused_parity_groups = ^{parity_all[14:4],parity_all[2]}; // 写响应不使用地址、数据、字节使能及本实例信用组。
    upli_parity #( // 复用公共真实保护原语，不重新实现发送校验算法。
        .CHANNEL_KIND(2) // 固定选择 Write Response 的四十二位控制组。
    ) u_parity ( // 每个字段先完成输出限定，再由相同输出字段生成保护码。
        .i_check_enable(1'b0), // 纯发送实例不对不存在的收到校验码做检查。
        .i_valid(o_valid), // 校验实际原生有效，不校验被屏蔽的候选有效。
        .i_control({26'd0,o_type_info,o_tag,o_status,o_src,o_dst,o_port,o_vc,o_pool}), // 低四十二位完整包含规定控制字段，上部补零。
        .i_address(57'd0), // 本通道不存在独立地址字段。
        .i_auth(o_auth_tag), // 已按有效周期限定的完整六十四位授权标签。
        .i_data(512'd0), // Write Response 无原生 Data 字段。
        .i_byte_enable(64'd0), // Write Response 无原生字节使能字段。
        .i_credit_valid(4'd0), // 信用返回方向由独立接收与信用管理模块处理。
        .i_credit_pool(4'd0), // 此实例不承担信用返回保护。
        .i_credit_vc(8'd0), // 无本地接收信用 VC 输入。
        .i_credit_num(8'd0), // 无本地接收信用数量输入。
        .i_received_parity(15'd0), // 接收检查关闭，输入零不代表收到合法协议。
        .o_parity(parity_all), // 只将实际生成的发送保护组接到原生输出。
        .o_errors(unused_errors), // 明确未使用的接收逐组诊断。
        .o_control_error(unused_control_error), // 接收控制分类不属于当前 TX 接口。
        .o_data_error(unused_data_error), // 接收数据分类不属于当前 TX 接口。
        .o_auth_error(unused_auth_error) // 接收授权校验分类不属于当前 TX 接口。
    ); // 结束公共 Write Response 偶校验原语实例。
endmodule // 结束 upli_write_response_channel 原生组合发送模块。
`default_nettype wire // 恢复后续独立源码的默认网络设置。
