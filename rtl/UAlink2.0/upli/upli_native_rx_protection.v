`timescale 1ns/1ps // 保护转换与原生接收共用同一组合时隙。
`default_nettype none // 禁止保护字段漏接形成隐式网络。
module upli_native_rx_protection #( // 原生接收保护模块，检查原码并对数据错误逐拍归一化poison。
    parameter integer CHANNEL_KIND = 0, // Request、Read、Write、OrigData依次编码零至三。
    parameter integer C_PAYLOAD_WIDTH = (CHANNEL_KIND==0)?184:(CHANNEL_KIND==1)?619:(CHANNEL_KIND==2)?101:580 // 固定原生完整负载宽度。
)( // 原生字段和收到的保护码必须在同一观察边界稳定。
    input wire i_auth_enabled, // 本地授权profile资格，启用不表示密码学认证已通过。
    input wire i_check_enable, // 检测资格由共同reset及真实头资格提供。
    input wire i_valid, // 入口valid零仍检查其valid parity。
    input wire [1:0] i_port, i_vc, // 原始端口及VC参与控制保护。
    input wire i_pool, // 原始共享池选择参与控制保护。
    input wire [C_PAYLOAD_WIDTH-1:0] i_payload, // 全宽原始负载不能按BE或错误状态遮蔽。
    input wire [12:0] i_received_parity, // 收到的原生十三位保护码。
    output wire [C_PAYLOAD_WIDTH-1:0] o_payload, // 仅在数据错误时置原生poison位，其他位保留。
    output wire [12:0] o_parity, // 归一化后字段的真实公共保护码。
    output wire [12:0] o_errors, // 收到的原始保护码错误，不能由重生成掩盖。
    output wire o_control_error, o_data_error, o_auth_error, // 三类真实保护错误分别暴露。
    output wire o_auth_profile_error // Auth inactive profile下非零授权单独诊断。
); // 结束逐拍保护转换接口。
    wire [67:0] control_before, control_after; // poison变化必须同步更新控制保护。
    wire [56:0] address; // Request独立地址保护，保持全部五十七位。
    wire [63:0] auth, byte_enable; // 授权独立分类，BE属于原生数据错误。
    wire [511:0] data; // 八个完整六十四位组，不能只保护启用字节。
    wire detected_data; // 由实际收到的data或BE校验错误产生。
    wire [14:0] received_errors, generated_parity; // 公共primitive统一位置输出。
    wire [14:0] unused_original_parity, unused_generated_errors; // 原码检查与新码生成的非消费输出明确终止。
    wire [1:0] unused_credit_errors, unused_credit_parity; // 正向通道没有信用事件，相关输入固定零。
    wire unused_generated_control, unused_generated_data, unused_generated_auth; // 生成实例不请求检查。
    assign o_errors = received_errors[12:0]; // 仅公开该原生通道的十三个保护组。
    assign o_parity = generated_parity[12:0]; // 新保护覆盖完整归一化字段。
    assign unused_credit_errors = received_errors[14:13]; // 不把反向信用和正向有效混为一谈。
    assign unused_credit_parity = generated_parity[14:13]; // 信用输入全零因此无信用保护动作。
    assign o_data_error = detected_data; // poison不自动等同于新检测错误。
    assign o_auth_profile_error = i_check_enable && i_valid && !i_auth_enabled && (auth != 64'd0); // 本地inactive资格不伪装为规范控制错误。
    generate // 固定kind决定精确字段布局。
        if (CHANNEL_KIND == 0) begin : gen_kind_0 // 原生通道0的完整字段展开。
            assign control_before = {i_payload[97:87],i_payload[21:16],i_payload[15:8],i_payload[27:22],i_payload[7:0],i_vc,i_payload[183:182],i_payload[117:108],i_payload[107:98],i_port,i_payload[86:85],i_pool}; // 精确映射control_before，完整保留协议字段。
            assign address = i_payload[84:28]; // 精确映射address，完整保留协议字段。
            assign auth = i_payload[181:118]; // 精确映射auth，完整保留协议字段。
            assign data = 512'd0; // 精确映射data，完整保留协议字段。
            assign byte_enable = 64'd0; // 精确映射byte_enable，完整保留协议字段。
            assign o_payload = i_payload; // 精确映射o_payload，完整保留协议字段。
            assign control_after = {o_payload[97:87],o_payload[21:16],o_payload[15:8],o_payload[27:22],o_payload[7:0],i_vc,o_payload[183:182],o_payload[117:108],o_payload[107:98],i_port,o_payload[86:85],i_pool}; // 归一化poison之后的完整控制保护。
        end // 结束通道0字段映射。
        else if (CHANNEL_KIND == 1) begin : gen_kind_1 // 原生通道1的完整字段展开。
            assign control_before = {20'd0,i_payload[1:0],i_payload[534:524],i_payload[9:6],i_payload[5:4],i_payload[3],i_payload[523:522],i_vc,i_payload[554:545],i_payload[544:535],i_port,i_payload[2],i_pool}; // 精确映射control_before，完整保留协议字段。
            assign address = 57'd0; // 精确映射address，完整保留协议字段。
            assign auth = i_payload[618:555]; // 精确映射auth，完整保留协议字段。
            assign data = i_payload[521:10]; // 精确映射data，完整保留协议字段。
            assign byte_enable = 64'd0; // 精确映射byte_enable，完整保留协议字段。
            assign o_payload = {i_payload[618:3],(i_payload[2] | detected_data),i_payload[1:0]}; // 精确映射o_payload，完整保留协议字段。
            assign control_after = {20'd0,o_payload[1:0],o_payload[534:524],o_payload[9:6],o_payload[5:4],o_payload[3],o_payload[523:522],i_vc,o_payload[554:545],o_payload[544:535],i_port,o_payload[2],i_pool}; // 归一化poison之后的完整控制保护。
        end // 结束通道1字段映射。
        else if (CHANNEL_KIND == 2) begin : gen_kind_2 // 原生通道2的完整字段展开。
            assign control_before = {26'd0,i_payload[36:35],i_payload[34:24],i_payload[23:20],i_payload[19:10],i_payload[9:0],i_port,i_vc,i_pool}; // 精确映射control_before，完整保留协议字段。
            assign address = 57'd0; // 精确映射address，完整保留协议字段。
            assign auth = i_payload[100:37]; // 精确映射auth，完整保留协议字段。
            assign data = 512'd0; // 精确映射data，完整保留协议字段。
            assign byte_enable = 64'd0; // 精确映射byte_enable，完整保留协议字段。
            assign o_payload = i_payload; // 精确映射o_payload，完整保留协议字段。
            assign control_after = {26'd0,o_payload[36:35],o_payload[34:24],o_payload[23:20],o_payload[19:10],o_payload[9:0],i_port,i_vc,i_pool}; // 归一化poison之后的完整控制保护。
        end // 结束通道2字段映射。
        else if (CHANNEL_KIND == 3) begin : gen_kind_3 // 原生通道3的完整字段展开。
            assign control_before = {59'd0,i_pool,i_vc,i_port,i_payload[3:2],i_payload[0],i_payload[1]}; // 精确映射control_before，完整保留协议字段。
            assign address = 57'd0; // 精确映射address，完整保留协议字段。
            assign auth = 64'd0; // 精确映射auth，完整保留协议字段。
            assign data = i_payload[579:68]; // 精确映射data，完整保留协议字段。
            assign byte_enable = i_payload[67:4]; // 精确映射byte_enable，完整保留协议字段。
            assign o_payload = {i_payload[579:1],(i_payload[0] | detected_data)}; // 精确映射o_payload，完整保留协议字段。
            assign control_after = {59'd0,i_pool,i_vc,i_port,o_payload[3:2],o_payload[0],o_payload[1]}; // 归一化poison之后的完整控制保护。
        end // 结束通道3字段映射。
        else begin : gen_invalid // 未支持kind拒绝展开，不构造假的原生字段。
            upli_native_rx_protection_kind_invalid u_invalid(); // 参数非法应在编译发现。
        end // 结束kind保护。
        if (C_PAYLOAD_WIDTH != ((CHANNEL_KIND==0)?184:(CHANNEL_KIND==1)?619:(CHANNEL_KIND==2)?101:580)) begin : gen_invalid_width // 防止显式参数导致有效字段截断。
            upli_native_rx_protection_width_invalid u_invalid(); // 不接受错误封套接口宽度。
        end // 结束完整负载宽度检查。
    endgenerate // 结束原生常量布局。
    upli_parity #(.CHANNEL_KIND(CHANNEL_KIND)) u_check ( // 实际检查原始收到的保护码。
        .i_check_enable(i_check_enable), .i_valid(i_valid), .i_control(control_before), // valid零仍由primitive按规定检查。
        .i_address(address), .i_auth(auth), .i_data(data), .i_byte_enable(byte_enable), // 不对masked或poison数据遮蔽。
        .i_credit_valid(4'd0), .i_credit_pool(4'd0), .i_credit_vc(8'd0), .i_credit_num(8'd0), // 正向层不检查虚构信用。
        .i_received_parity({2'd0,i_received_parity}), .o_parity(unused_original_parity), .o_errors(received_errors), // 校验收到码而不是重新生成的码。
        .o_control_error(o_control_error), .o_data_error(detected_data), .o_auth_error(o_auth_error) // 控制、数据、授权分类独立。
    ); // 结束入口真实保护检查。
    upli_parity #(.CHANNEL_KIND(CHANNEL_KIND)) u_generate ( // 归一化poison之后建立下一保护边界。
        .i_check_enable(1'b0), .i_valid(i_valid), .i_control(control_after), // 新Error位与控制校验一起更新。
        .i_address(address), .i_auth(auth), .i_data(data), .i_byte_enable(byte_enable), // 完整数据/BE保持并生成新保护。
        .i_credit_valid(4'd0), .i_credit_pool(4'd0), .i_credit_vc(8'd0), .i_credit_num(8'd0), // 正向存储封套不混入信用。
        .i_received_parity(15'd0), .o_parity(generated_parity), .o_errors(unused_generated_errors), // 生成模式无伪造的接收检查。
        .o_control_error(unused_generated_control), .o_data_error(unused_generated_data), .o_auth_error(unused_generated_auth) // 无检查输出明确终止。
    ); // 结束新保护生成实例。
endmodule // 结束原生逐拍保护归一化模块。
`default_nettype wire // 恢复后续独立源码的网络默认规则。
