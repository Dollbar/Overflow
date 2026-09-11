`timescale 1ns/1ps // 所有观察事件使用同一原生UPLI时钟域。
`default_nettype none // 接收观察器禁止隐式网络掩盖字段接线错误。
module upli_receive_tdm_monitor #( // 原生接收侧TDM观察模块，不产生流控或隔离动作。
    parameter integer C_NUM_PORTS = 1 // Common规定的端口配置为一、二或四。
)( // 四个原生有效事件共享一个采样时钟。
    input wire i_clk, // 原生UPLI采样时钟。
    input wire i_rstn, // 同步低有效复位，与被观察通道共同复位。
    input wire i_req_valid, // 实际Request有效事件，不是候选资格。
    input wire [1:0] i_req_port, // Request当前有效拍的原生端口编号。
    input wire i_data_valid, // 实际OrigData有效事件。
    input wire [1:0] i_data_port, // OrigData当前有效拍的原生端口编号。
    input wire i_rd_valid, // 实际Read Response有效事件。
    input wire [1:0] i_rd_port, // Read Response当前有效拍的原生端口编号。
    input wire i_wr_valid, // 实际Write Response有效事件。
    input wire [1:0] i_wr_port, // Write Response当前有效拍的原生端口编号。
    output wire [3:0] o_error, // 当前沿前组合诊断，低至高为Req、Data、Rd、Wr。
    output wire [3:0] o_error_sticky, // 各通道错误由共同上升沿捕获，保持直到复位。
    output wire [2:0] o_phase_known, // 低至高为ReqData、Rd、Wr三个独立相位组。
    output wire [5:0] o_expected_port // 每组两位，寄存状态表示当前待采样时隙。
); // 结束只观察的原生端口接口。
    localparam [1:0] C_LAST_PORT = (C_NUM_PORTS == 4) ? 2'd3 : ((C_NUM_PORTS == 2) ? 2'd1 : 2'd0); // 端口轮转边界宽度明确。
    localparam [1:0] C_UNUSED_PORT_MASK = (C_NUM_PORTS == 4) ? 2'd0 : ((C_NUM_PORTS == 2) ? 2'd2 : 2'd3); // 未配置的端口编号位掩码。
    wire [2:0] flag_group_error; // 由每组首通道检查独立相位和合法编号。
    wire flag_req_legal; // 请求端口可作为相位锚点的必要条件。
    wire flag_data_legal; // 无效端口不能作为合法数据事件。
    wire flag_data_known; // 数据使用既定相位，或同沿首次合法请求建立的相位。
    wire [1:0] data_expected; // 同沿首次请求允许其原始端口成为数据比较对象。
    reg [3:0] reg_error_sticky; // 错误保持仅作本地诊断，不改变发送或接收资格。
    genvar group_index; // 固定三个独立相位组的常量展开。
    assign flag_req_legal = (i_req_port & C_UNUSED_PORT_MASK) == 2'd0; // 对一、二端口配置拒绝未使用编号。
    assign flag_data_legal = (i_data_port & C_UNUSED_PORT_MASK) == 2'd0; // idle时该值不产生诊断。
    assign flag_data_known = o_phase_known[0] || (i_req_valid && flag_req_legal); // 单独OrigData不能建立共同相位。
    assign data_expected = o_phase_known[0] ? o_expected_port[1:0] : i_req_port; // 已建立相位优先，错误请求不重同步。
    assign o_error = {flag_group_error[2],flag_group_error[1],(i_rstn && i_data_valid && (!flag_data_legal || !flag_data_known || (i_data_port != data_expected))),flag_group_error[0]}; // 四个通道分别指出有效事件的当前错误。
    assign o_error_sticky = reg_error_sticky; // 同步状态直接输出，不伪造异步清除。
    always @(posedge i_clk) begin // 只在原生共同采样边沿记录诊断。
        if (!i_rstn) reg_error_sticky <= 4'd0; // 共同复位清除全部历史错误。
        else reg_error_sticky <= reg_error_sticky | o_error; // 当前诊断逐通道累计。
    end // 结束诊断保持寄存器。
    generate // 仅支持规范明确的静态端口配置。
        if ((C_NUM_PORTS != 1) && (C_NUM_PORTS != 2) && (C_NUM_PORTS != 4)) begin : gen_invalid // 非法配置必须在展开阶段失败。
            upli_receive_tdm_monitor_invalid_port_configuration u_invalid(); // 无可综合回退配置，避免误报有效监测。
        end // 结束非法参数检查。
        for (group_index = 32'd0; group_index < 32'd3; group_index = group_index + 32'd1) begin : gen_groups // ReqData共组，其余响应独立。
            wire observed_valid; // 只有各组规范指定的首通道能建立相位。
            wire [1:0] channel_port; // 当前组原生端口，未valid时没有意义。
            wire [1:0] observed_port; // 显式观察端口供合法学习和相位比较。
            wire flag_legal; // 当前有效事件的端口范围资格。
            wire [1:0] next_phase; // 已知相位无论idle或错误都按时钟继续推进。
            wire [1:0] learned_next; // 首次合法事件之后下一个时隙的期望端口。
            reg reg_known; // 当前组是否已经观察到合法首事件。
            reg [1:0] reg_phase; // 当前时隙的期望端口，未知时确定为零。
            if (group_index == 0) begin : gen_request // 共同相位只能由Request建立。
                assign observed_valid = i_req_valid; // OrigData不会单独触发相位学习。
                assign channel_port = i_req_port; // 完整两位请求编号。
            end else if (group_index == 1) begin : gen_read // Read Response首事件独立学习。
                assign observed_valid = i_rd_valid; // 只观察真实Read Response有效事件。
                assign channel_port = i_rd_port; // 不借用Request或Write相位。
            end else begin : gen_write // Write Response有独立相位。
                assign observed_valid = i_wr_valid; // 只观察真实Write Response有效事件。
                assign channel_port = i_wr_port; // 不借用Request或Read相位。
            end // 结束常量通道映射。
            assign observed_port = channel_port; // 原生两位端口不截断。
            assign flag_legal = (observed_port & C_UNUSED_PORT_MASK) == 2'd0; // 非法首事件不建立相位。
            assign next_phase = (reg_phase == C_LAST_PORT) ? 2'd0 : reg_phase + 2'd1; // 固定端口数的时钟轮转。
            assign learned_next = (observed_port == C_LAST_PORT) ? 2'd0 : observed_port + 2'd1; // 首拍端口定义当前沿，下沿前状态指向下一槽。
            assign flag_group_error[group_index] = i_rstn && observed_valid && (!flag_legal || (reg_known && (observed_port != reg_phase))); // idle编号忽略，已知错误不重同步。
            assign o_phase_known[group_index] = reg_known; // 公开当前沿前是否有相位依据。
            assign o_expected_port[group_index*2 +: 2] = reg_phase; // 各组低位优先布局。
            always @(posedge i_clk) begin // 学习状态只由合法首事件置位。
                if (!i_rstn) reg_known <= 1'b0; // 同步复位后允许重新学习。
                else if (observed_valid && flag_legal) reg_known <= 1'b1; // 合法首事件建相位，历史错误不清除此状态。
            end // 结束相位已知标志。
            always @(posedge i_clk) begin // 相位时钟始终与原生采样时钟一致。
                if (!i_rstn) reg_phase <= 2'd0; // 未知时确定输出零。
                else if (reg_known) reg_phase <= next_phase; // 已知后每周期推进，包括idle和协议错误。
                else if (observed_valid && flag_legal) reg_phase <= learned_next; // 第一次合法事件的下一槽。
            end // 结束相位寄存器。
        end // 结束三个组状态展开。
    endgenerate // 结束参数和通道结构。
endmodule // 结束本地接收TDM诊断观察器。
`default_nettype wire // 恢复后续独立编译单元默认网络规则。
