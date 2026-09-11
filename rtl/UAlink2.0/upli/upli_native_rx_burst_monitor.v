`timescale 1ns/1ps // 原生事件与既有TDM观察状态使用共同采样沿。
`default_nettype none // burst诊断完整字段禁止隐式漏接。
module upli_native_rx_burst_monitor #( // 原生接收burst观察模块，不产生业务过滤或Drop。
    parameter integer C_NUM_PORTS = 1 // 只允许一、二或四端口配置。
)( // 当前时隙直接来自唯一既有TDM观察器。
    input wire i_clk, i_rstn, // 同域时钟和同步低有效共同复位。
    input wire i_tdm_known, // 既有ReqData相位在当前沿前是否已经建立。
    input wire [1:0] i_tdm_port, // 既有ReqData当前沿预期时隙，不在本层重新推进。
    input wire i_req_valid, // 原始native请求事件，不使用FIFO退休事件代替。
    input wire [1:0] i_req_port, // 原始完整物理端口字段。
    input wire i_req_class_known, i_req_has_data, // 外层已确认的命令分类，本层不猜opcode。
    input wire [1:0] i_req_vc, i_req_num_beats, // 原始VC和数据拍数减一编码。
    input wire i_data_valid, // 原始OrigData有效事件，不从存储accepted重建。
    input wire [1:0] i_data_port, i_data_vc, i_data_offset, // 当前数据的原始端口、VC与相对序号。
    input wire i_data_last, // 当前数据最后一拍标志，poison不允许缩短正常burst。
    output wire [9:0] o_error, // 当前沿诊断：port、首配对、孤立数据、覆盖、缺尾、offset、last、VC、分类、相位资格。
    output wire [9:0] o_error_sticky, // 首次失败后保持诊断至reset，不声称复同步。
    output wire [C_NUM_PORTS-1:0] o_active // 各端口原始尾部跟踪所有权，仅作观察。
); // 结束无ready和无credit接口的监测模块。
    localparam [31:0] C_PORTS = C_NUM_PORTS; // 常量展开全部实际端口。
    localparam [2:0] C_PORT_LIMIT = C_NUM_PORTS[2:0]; // 与原生编号零扩展后精确比较。
    reg [9:0] reg_error; // 第一组错误之后冻结所有上下文，直到共同复位。
    wire flag_check; // 此profile只跟踪尚未出现结构错误的epoch。
    wire [C_NUM_PORTS*10-1:0] port_errors; // 每端口独立检查后只做组合归约。
    reg [9:0] combined_errors; // 归约所有实际端口的当前错误。
    integer index_port; // 常量边界组合循环索引。
    genvar p; // 每端口保存最多三个尾部的边界描述符。
    assign flag_check = i_rstn && !(|reg_error); // 历史错误不被后续合法事件当作自动恢复。
    assign o_error_sticky = reg_error; // 同步历史状态原样输出。
    assign o_error = combined_errors & {10{flag_check}}; // 复位和已冻结epoch不再生成新解释。
    always @(*) begin // 全量默认赋值避免组合锁存。
        combined_errors = 10'd0; // 每周期重新归约局部诊断。
        combined_errors[0] = (i_req_valid && ({1'b0,i_req_port} >= C_PORT_LIMIT)) || (i_data_valid && ({1'b0,i_data_port} >= C_PORT_LIMIT)); // 有效非法port独立诊断。
        combined_errors[8] = i_req_valid && !i_req_class_known; // 未确认命令不能伪装为无数据请求。
        combined_errors[9] = (|o_active) && (!i_tdm_known || ({1'b0,i_tdm_port} >= C_PORT_LIMIT)); // 活动上下文要求既有时隙源仍可用。
        for (index_port = 32'd0; index_port < C_PORTS; index_port = index_port+32'd1) begin // 归约已静态展开端口错误。
            combined_errors = combined_errors | port_errors[index_port*10 +: 10]; // 不添加新的相位状态。
        end // 结束端口诊断归约。
    end // 结束当前错误组合生成。
    always @(posedge i_clk) begin // 首次错误当沿被历史状态保存。
        if (!i_rstn) reg_error <= 10'd0; // reset是本地诊断profile唯一清除方式。
        else reg_error <= reg_error | o_error; // 没有ack或自动重新学习路径。
    end // 结束诊断历史寄存。
    generate // 按配置展开独立物理端口上下文。
        if ((C_NUM_PORTS != 1) && (C_NUM_PORTS != 2) && (C_NUM_PORTS != 4)) begin : gen_invalid // 未配置模式必须明确拒绝。
            upli_native_rx_burst_monitor_ports_invalid Invalid_Ports_Inst (); // 非法配置在elaboration失败。
        end // 结束参数保护。
        for (p = 32'd0; p < C_PORTS; p = p+32'd1) begin : gen_ports // 每端口不与其他端口共享burst所有权。
            localparam [1:0] C_PORT = p[1:0]; // 原生端口常量完整两位。
            reg reg_active; // 当前端口仍期待数据尾部。
            reg [1:0] reg_offset, reg_last_offset, reg_vc; // 下一序号、最终序号和原请求VC。
            wire flag_request, flag_data, flag_start, flag_due, flag_owned; // 当前事件与既有上下文对应关系。
            wire [1:0] expected_offset, expected_vc; // 本拍应有的序号和VC。
            wire expected_last; // 最后标志依据原始请求拍数而非当前数据值。
            assign o_active[p] = reg_active; // 调试输出不拥有业务接纳资格。
            assign flag_request = i_req_valid && (i_req_port == C_PORT); // 原始有效请求指向本端口。
            assign flag_data = i_data_valid && (i_data_port == C_PORT); // 原始有效数据指向本端口。
            assign flag_start = flag_request && i_req_class_known && i_req_has_data && !reg_active; // Read叠加不能覆盖既有尾部。
            assign flag_due = reg_active && i_tdm_known && (i_tdm_port == C_PORT); // 只借用既有相位判断本周期必须有尾部。
            assign flag_owned = flag_start || flag_due; // 首拍来自同沿请求，尾部来自既有上下文。
            assign expected_offset = reg_active ? reg_offset : 2'd0; // 首数据必须从零开始。
            assign expected_vc = reg_active ? reg_vc : i_req_vc; // Read叠加的VC不能覆盖原数据上下文。
            assign expected_last = reg_active ? (reg_offset == reg_last_offset) : (i_req_num_beats == 2'd0); // 单拍和多拍最终边界使用同一原始Num编码。
            assign port_errors[p*10 +: 10] = {2'd0,(flag_data && flag_owned && (i_data_vc != expected_vc)),(flag_data && flag_owned && (i_data_last != expected_last)),(flag_data && flag_owned && (i_data_offset != expected_offset)),(flag_due && !flag_data),(flag_request && i_req_class_known && i_req_has_data && reg_active),(flag_data && !reg_active && !flag_start),(flag_start && !flag_data),1'b0}; // Pool、数据和poison不用于改变正常burst边界。
            always @(posedge i_clk) begin // 有效epoch才推进描述符，任何当前错误都冻结所有端口。
                if (!i_rstn) begin // 共同复位取消所有旧尾部所有权。
                    reg_active <= 1'b0; // 下一epoch从没有期待尾部开始。
                    reg_offset <= 2'd0; // 无旧序号残留。
                    reg_last_offset <= 2'd0; // 无旧最终边界残留。
                    reg_vc <= 2'd0; // 无旧VC身份残留。
                end else if (flag_check && !(|o_error)) begin // 纯诊断profile不会消费错误事件重建上下文。
                    if (flag_start && (i_req_num_beats != 2'd0)) begin // 首拍正确配对且声明还有尾部才建立上下文。
                        reg_active <= 1'b1; // 后续该port的每一个时隙必须送尾部。
                        reg_offset <= 2'd1; // 首拍已观察，下一拍序号为一。
                        reg_last_offset <= i_req_num_beats; // 保存原始请求最终序号。
                        reg_vc <= i_req_vc; // 保存原请求VC用于全部尾部比较。
                    end else if (flag_due && flag_data) begin // 正确观察一个既定尾部。
                        if (reg_offset == reg_last_offset) reg_active <= 1'b0; // 原始最终拍结束当前上下文。
                        else reg_offset <= reg_offset+2'd1; // 其余尾部只推进一个相对序号。
                    end // 结束正常首拍或尾部状态更新。
                end // 结束尚未失效epoch状态更新。
            end // 结束本port尾部描述符寄存。
        end // 结束全部物理端口上下文。
    endgenerate // 结束有限配置结构。
endmodule // 结束不实现TDM调度、Drop、信用或事务执行的burst观察模块。
`default_nettype wire // 恢复后续独立编译单元默认网络规则。
