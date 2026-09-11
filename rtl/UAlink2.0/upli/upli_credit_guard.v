// UPLI credit integrity guard; Common 2.0 section 3.1.1 and native credit groups.
// 日期2026-09-11；仅提供完整性诊断，不改变信用、连接或恢复状态。
`timescale 1ns/1ps // 与公共保护原语保持相同编译时间单位，硬件无延时。
`default_nettype none // 禁止隐式网络遗漏完整四端口保护字段。
module upli_credit_guard ( // 信用完整性检查模块，无状态且不充当信用银行或准入器。
    input wire i_check_enable, // 只限定诊断使能，不是原生信用ready或有效位。
    input wire [3:0] i_credit_valid, // 全部四个端口有效位每周期参与保护。
    input wire [3:0] i_credit_pool, // 所有端口的原始Pool位，未激活端口也不遮蔽。
    input wire [7:0] i_credit_vc, // 每端口两位VC，最低两位对应port0。
    input wire [7:0] i_credit_num, // 每端口数量编码原样参与保护，不在此解释信用数。
    input wire i_credit_valid_parity, // 实际收到的四位valid独立保护码。
    input wire i_credit_parity, // 实际收到的完整二十位Pool、VC与Num保护码。
    output wire o_valid_error, // 使能时报告valid组失配，包括所有valid为零的周期。
    output wire o_control_error, // 使能且任一valid为一时报告完整控制组失配。
    output wire o_error, // 两个信用保护组诊断的并集，不包含账户语义。
    output wire o_integrity_ok // enable限定的未检出错误；禁止解释为信用、建连或初始化许可。
); // 结束只读诊断接口，InitDone明确不属于保护输入。
    wire [14:0] errors; // 公共原语按组输出，仅信用组被本模块消费。
    wire [14:0] unused_generated_parity; // 接收检查不以重新生成的值覆盖收到的保护码。
    wire [12:0] unused_noncredit_errors; // 非信用输入固定零，不向调用方制造其它通道诊断。
    wire unused_control_error, unused_data_error, unused_auth_error; // 公共分类输出不是本组件额外的恢复接口。
    assign o_valid_error = errors[13]; // 直接消费公共valid信用保护位。
    assign o_control_error = errors[14]; // 直接消费公共完整控制信用保护位。
    assign o_error = o_valid_error || o_control_error; // 保持两个独立原因同时可见。
    assign o_integrity_ok = !o_error; // 检查关闭时为一仅表示未报告失配，不表示检查已执行。
    assign unused_noncredit_errors = errors[12:0]; // 未用组完整终止，方便层次检查其输入恒零。
    upli_parity #(.CHANNEL_KIND(0)) Parity_Inst ( // 使用唯一公共原语的信用保护部分，不重复XOR。
        .i_check_enable(i_check_enable), .i_valid(1'b0), // 只开启信用接收检查，原生通道valid固定无事件。
        .i_control(68'd0), .i_address(57'd0), .i_auth(64'd0), // 无Request控制、地址或认证字段。
        .i_data(512'd0), .i_byte_enable(64'd0), // 无数据或ByteEn保护输入。
        .i_credit_valid(i_credit_valid), .i_credit_pool(i_credit_pool), // 原始完整四端口信用字段不做有效掩码。
        .i_credit_vc(i_credit_vc), .i_credit_num(i_credit_num), // 二十位控制组逐位保持接收值。
        .i_received_parity({i_credit_parity,i_credit_valid_parity,13'd0}), // 高两位是实际信用码，其它组没有收到的通道事件。
        .o_parity(unused_generated_parity), .o_errors(errors), // 只输出比较结果，不改写任何信用流。
        .o_control_error(unused_control_error), .o_data_error(unused_data_error), .o_auth_error(unused_auth_error) // 明确终止未使用的总分类输出。
    ); // 结束唯一真实信用校验原语实例。
endmodule // 结束无状态信用完整性诊断组件。
`default_nettype wire // 恢复后续独立源码的默认网络声明规则。
