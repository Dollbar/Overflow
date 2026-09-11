`timescale 1ns/1ps // 所有错误请求与业务边界使用同一原生时钟域。
`default_nettype none // 防止错误归属或Drop输出漏接形成隐式网络。
module upli_rx_role_fault_controller #( // 本地接收角色故障模块，保持Drop而不伪造Isolation恢复。
    parameter integer C_NUM_PORTS = 1, // 每角色一、二或四端口，错误不按受损PortID缩小。
    parameter integer C_NUM_ROLES = 1, // 单角色归约全部通道；双角色零为Originator、一为Completer。
    parameter integer C_IS_TL = 0 // 明确TL模式才把故障扩大到同TL的两个角色。
)( // 输入每一位均来自实际通道检测点，不从可疑payload猜角色。
    input wire i_clk, i_rstn, // 同域上升沿时钟和同步低有效共同reset。
    input wire [C_NUM_ROLES-1:0] i_fault_ack, // 仅确认本地通知，不清除Drop或恢复流量。
    input wire [C_NUM_ROLES-1:0] i_init_done_roles, // 初始化状态仅记录故障发生边界，不控制信用或连接。
    input wire [3:0] i_control_error, // bit零Req、一Rd、二Wr、三Data的原生控制保护错误。
    input wire [3:0] i_credit_control_error, // 该kind返回信用总线错误，接收角色与正向Beat相反，由实际guard的调用方阻止坏信用计账。
    input wire [3:0] i_auth_error, i_auth_profile_error, // 授权保护与本地profile违例分别保持来源。
    input wire [3:0] i_metadata_error, i_order_error, // 存储封套和顺序所有权一致性错误。
    input wire [3:0] i_storage_error, i_tdm_error, // 既有存储诊断及独立TDM诊断，使用本地fail-stop政策。
    input wire [3:0] i_data_error, // 已由native RX按拍poison的数据/BE错误，不触发Drop。
    output wire [C_NUM_ROLES-1:0] o_drop_roles, // 当前fatal当沿加上历史Drop，覆盖各角色全部通道。
    output wire [C_NUM_ROLES*C_NUM_PORTS-1:0] o_drop_ports, // 每角色低端口优先展开，角色间端口范围不混淆。
    output wire [C_NUM_ROLES-1:0] o_notify_roles, // 尚未确认或出现新错误来源的本地通知请求。
    output wire [C_NUM_ROLES-1:0] o_ack_accepted, // 沿前确认资格，新错误来源优先于同沿ack。
    output wire [C_NUM_ROLES-1:0] o_reset_required, // 保守profile只允许共同reset清除Drop。
    output wire [31:0] o_reason_sticky, // 每四位为一分类，低至高control/credit/auth/profile/meta/order/storage/tdm。
    output wire [C_NUM_ROLES-1:0] o_init_incomplete, // 首次进入Drop时初始化尚未完成的角色，保持至reset。
    output wire [3:0] o_data_error_observed // 原始按拍数据错误诊断，不是新的poison生成路径。
); // 结束唯一角色范围故障所有者接口。
    localparam [31:0] C_ROLE_LIMIT = C_NUM_ROLES; // 显式常量宽度供角色generate循环使用。
    wire [3:0] native_fatal_channels; // 正向Beat错误和反向信用错误分别归属角色。
    wire [3:0] native_new_channels; // 正向新原因不含credit分类。
    wire [3:0] fatal_channels; // 各检测通道是否存在必须请求fail-stop的原因。
    wire [31:0] current_reasons, new_reasons; // 分类来源位图完整保留，ack不清除证据。
    wire [3:0] new_channels; // 新原因属于哪个实际检测通道。
    wire [C_NUM_ROLES-1:0] role_fatal, role_new_reason; // 按明确角色/TL作用域归约。
    reg [C_NUM_ROLES-1:0] reg_drop; // 各角色Drop历史，只有共同reset清除。
    reg [C_NUM_ROLES-1:0] reg_acknowledged; // 每角色本地通知已确认状态。
    reg [C_NUM_ROLES-1:0] reg_init_incomplete; // 只记录首次故障时的初始化边界。
    reg [31:0] reg_reasons; // 原始分类和通道历史不会被ack擦除。
    genvar role_index; // 常量角色归属与端口范围展开。
    assign native_fatal_channels = i_control_error | i_auth_error | i_auth_profile_error | i_metadata_error | i_order_error | i_storage_error | i_tdm_error; // 正向Beat检测归属不含反向信用。
    assign fatal_channels = i_control_error | i_credit_control_error | i_auth_error | i_auth_profile_error | i_metadata_error | i_order_error | i_storage_error | i_tdm_error; // 数据/BE错误明确不在fatal集合内。
    assign current_reasons = {i_tdm_error,i_storage_error,i_order_error,i_metadata_error,i_auth_profile_error,i_auth_error,i_credit_control_error,i_control_error}; // 不混淆标准错误和本地策略原因。
    assign new_reasons = current_reasons & ~reg_reasons; // 同一持续原因不反复制造新来源通知。
    assign new_channels = native_new_channels | new_reasons[7:4]; // TL范围包括正向和反向所有新错误。
    assign native_new_channels = new_reasons[3:0] | new_reasons[11:8] | new_reasons[15:12] | new_reasons[19:16] | new_reasons[23:20] | new_reasons[27:24] | new_reasons[31:28]; // 逐分类保留通道位置进行归约。
    assign o_drop_roles = {C_NUM_ROLES{i_rstn}} & (reg_drop | role_fatal); // 当前错误必须在采样沿前阻断业务，不能晚一周期。
    assign o_notify_roles = o_drop_roles & (~reg_acknowledged | role_new_reason); // 新来源重新请求通知，但不改变Drop范围。
    assign o_ack_accepted = {C_NUM_ROLES{i_rstn}} & i_fault_ack & reg_drop & ~role_new_reason; // 尚未锁存Drop或出现新来源的同沿ack不被接受。
    assign o_reset_required = o_drop_roles; // ack不是恢复资格，外部必须共同清除所有事务/信用所有权。
    assign o_reason_sticky = reg_reasons; // 同步保存的证据位图直接输出。
    assign o_init_incomplete = reg_init_incomplete; // 初始化后来完成也不抹掉故障发生边界。
    assign o_data_error_observed = i_data_error & {4{i_rstn}}; // 数据错误在Drop中仍可诊断，不能靠它解除或触发Drop。
    always @(posedge i_clk) begin // 角色故障状态使用共同采样时钟。
        if (!i_rstn) reg_drop <= {C_NUM_ROLES{1'b0}}; // 共同reset取消全部本地Drop状态。
        else reg_drop <= reg_drop | role_fatal; // 锁存角色范围直到reset，不响应ack清除。
    end // 结束Drop状态寄存器。
    always @(posedge i_clk) begin // 通知确认独立于业务恢复。
        if (!i_rstn) reg_acknowledged <= {C_NUM_ROLES{1'b0}}; // 新reset轮次没有旧通知确认。
        else reg_acknowledged <= (reg_acknowledged | o_ack_accepted) & ~role_new_reason; // 新原因优先保留未确认通知。
    end // 结束本地ack状态。
    always @(posedge i_clk) begin // 分类和检测通道证据独立保持。
        if (!i_rstn) reg_reasons <= 32'd0; // reset边界清除旧事务轮次的原因。
        else reg_reasons <= reg_reasons | current_reasons; // 不对持续错误计数，只保留来源位。
    end // 结束原因位图寄存器。
    always @(posedge i_clk) begin // 初始化边界只在首次进入Drop时采样。
        if (!i_rstn) reg_init_incomplete <= {C_NUM_ROLES{1'b0}}; // reset之后无旧初始化故障记录。
        else reg_init_incomplete <= reg_init_incomplete | ((~reg_drop) & role_fatal & ~i_init_done_roles); // 不改变initializer、连接或可信返回队列。
    end // 结束初始化边界记录。
    generate // 明确拒绝没有定义作用域的参数组合。
        if (((C_NUM_PORTS != 1) && (C_NUM_PORTS != 2) && (C_NUM_PORTS != 4)) || ((C_NUM_ROLES != 1) && (C_NUM_ROLES != 2)) || ((C_IS_TL != 0) && (C_IS_TL != 1)) || ((C_IS_TL == 1) && (C_NUM_ROLES != 2))) begin : gen_invalid // TL必须同时具有两个角色。
            upli_rx_role_fault_controller_parameters_invalid u_invalid(); // 不用默认回退掩盖非法范围配置。
        end // 结束参数保护。
        for (role_index = 32'd0; role_index < C_ROLE_LIMIT; role_index = role_index + 32'd1) begin : gen_roles // 每个角色拥有独立Drop状态位。
            localparam [3:0] C_CHANNEL_MASK = (C_NUM_ROLES == 1) ? 4'b1111 : ((role_index == 0) ? 4'b0110 : 4'b1001); // Originator接Rd/Wr，Completer接Req/Data；单角色自然归约。
            localparam [3:0] C_CREDIT_MASK = (C_NUM_ROLES == 1) ? 4'b1111 : ((role_index == 0) ? 4'b1001 : 4'b0110); // Req/Data返回信用在Originator接收，Rd/Wr返回信用在Completer接收。
            assign role_fatal[role_index] = (C_IS_TL == 1) ? (|fatal_channels) : ((|(native_fatal_channels & C_CHANNEL_MASK)) || (|(i_credit_control_error & C_CREDIT_MASK))); // 只有明确TL配置才扩大到另一角色。
            assign role_new_reason[role_index] = (C_IS_TL == 1) ? (|new_channels) : ((|(native_new_channels & C_CHANNEL_MASK)) || (|(new_reasons[7:4] & C_CREDIT_MASK))); // 通知范围与相应Drop政策一致。
            assign o_drop_ports[role_index*C_NUM_PORTS +: C_NUM_PORTS] = {C_NUM_PORTS{o_drop_roles[role_index]}}; // 当前角色全部端口同沿阻断，不依赖受损PortID。
        end // 结束角色和端口范围展开。
    endgenerate // 结束常量范围结构。
endmodule // 结束本地接收角色故障保持控制器。
`default_nettype wire // 恢复后续独立编译源码默认网络规则。
