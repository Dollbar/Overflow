// UPLI registered-return wire adapter; Common 2.0 sections 2.6 and 3.1.1.
// 日期2026-09-11；直接保护实际返回组，不增加采样周期、TDM或撤销条件。
`timescale 1ns/1ps // 与公共保护原语一致，硬件路径只有组合逻辑。
`default_nettype none // 防止返回元数据或保护组漏接时形成隐式网络。
module upli_credit_return_adapter ( // 信用返回保护模块，透明连接已有返回器的寄存输出。
    input wire [3:0] i_credit_valid, // 初始或正常返回器已实际驱动的四端口有效位。
    input wire [3:0] i_credit_pool, // 全部四端口原始共享账户选择。
    input wire [7:0] i_credit_vc, // 原账户VC，低两位对应port0。
    input wire [7:0] i_credit_num, // 四组原生信用数量减一编码。
    input wire [3:0] i_credit_init_done, // 初始化持续电平直接透传，不加入任何保护集合。
    output wire [3:0] o_credit_valid, // 原始有效位无新寄存器、ready或相位过滤。
    output wire [3:0] o_credit_pool, // 无效端口字段也按原值驱动并参与控制保护。
    output wire [7:0] o_credit_vc, // 实际线上VC值与原返回输出一致。
    output wire [7:0] o_credit_num, // 不重新批处理或解释返回数量。
    output wire [3:0] o_credit_init_done, // 不推迟或提前初始化完成电平。
    output wire o_credit_valid_parity, // 实际四位valid的独立偶校验。
    output wire o_credit_parity // 实际全部Pool、VC和Num的二十位偶校验。
); // 结束透明接口，不增加复位门控以取消已登记信用。
    wire [14:0] parity; // 公共生成器完整输出，只有信用两位被使用。
    wire [12:0] unused_noncredit_parity; // 明确终止本组件没有的原生通道保护码。
    wire [14:0] unused_errors; // TX生成模式不检查虚构的接收值。
    wire unused_control_error, unused_data_error, unused_auth_error; // 诊断分类不属于返回发送适配器职责。
    assign o_credit_valid = i_credit_valid; // 直接连接真实已登记的返回有效位。
    assign o_credit_pool = i_credit_pool; // 全字段透传，不因本端口valid为零遮蔽。
    assign o_credit_vc = i_credit_vc; // 保持最初接收时保存的VC身份。
    assign o_credit_num = i_credit_num; // 保持上游已确定的批次数量编码。
    assign o_credit_init_done = i_credit_init_done; // 完成电平独立于信用有效和parity。
    assign o_credit_valid_parity = parity[13]; // 直接使用公共四位valid生成结果。
    assign o_credit_parity = parity[14]; // 直接使用公共完整二十位控制生成结果。
    assign unused_noncredit_parity = parity[12:0]; // 不伪装成其它原生通道的发送保护层。
    upli_parity #(.CHANNEL_KIND(0)) Parity_Inst ( // 唯一公共生成器实际产生线上两位保护。
        .i_check_enable(1'b0), .i_valid(1'b0), // 只生成信用保护，没有原生通道发送事件。
        .i_control(68'd0), .i_address(57'd0), .i_auth(64'd0), // 所有非信用控制、地址及授权输入固定零。
        .i_data(512'd0), .i_byte_enable(64'd0), // 不将数据或初始化电平混入保护组。
        .i_credit_valid(o_credit_valid), .i_credit_pool(o_credit_pool), // 校验实际输出的全部valid和Pool字段。
        .i_credit_vc(o_credit_vc), .i_credit_num(o_credit_num), // 校验实际输出的全部VC与Num字段。
        .i_received_parity(15'd0), .o_parity(parity), .o_errors(unused_errors), // 生成模式不读取任何收到的信用保护码。
        .o_control_error(unused_control_error), .o_data_error(unused_data_error), .o_auth_error(unused_auth_error) // 总诊断显式终止，不建立额外策略。
    ); // 结束实际信用返回保护原语。
endmodule // 结束无状态返回组适配器。
`default_nettype wire // 恢复后续独立源码的默认网络声明规则。
