`timescale 1ns/1ps // 定义FP8乘法处理单元的仿真时间单位与时间精度

module PE_FP8 #( // 定义权重驻留、激活向右传播和精确乘积输出的一级流水处理单元
    parameter bit DAZ = 1'b0 // 配置是否将FP8输入非规格数直接视为有符号零
) ( // 开始PE_FP8端口声明
    input  logic                    clk_i, // 输入驻留权重、激活转发和乘积流水共用工作时钟
    input  logic                    rst_i, // 输入同步高有效复位信号并使驻留权重失效
    input  logic                    clear_i, // 输入同步高有效流水清空信号并保留驻留权重
    input  logic                    weight_load_i, // 高电平时将B SRAM提供的FP8权重装入本PE驻留寄存器
    input  logic [7:0]              weight_i, // 输入当前需要驻留在本PE中的FP8权重编码
    input  fp8_pkg::fp8_format_e    weight_format_i, // 输入驻留权重采用的E4M3或E5M2格式
    input  logic                    act_valid_i, // 标识来自A SRAM或左侧PE的FP8操作数有效
    input  logic [7:0]              act_i, // 输入来自A SRAM或左侧PE的FP8操作数编码
    input  fp8_pkg::fp8_format_e    act_format_i, // 输入A操作数采用的E4M3或E5M2格式
    output logic                    weight_loaded_o, // 标识本PE已经装入可用于计算的驻留权重
    output logic                    act_valid_o, // 标识向右级PE转发的A操作数有效
    output logic [7:0]              act_o, // 输出寄存后向右传播的A操作数编码
    output fp8_pkg::fp8_format_e    act_format_o, // 输出与向右A操作数同步的FP8格式
    output logic                    product_valid_o, // 标识当前精确乘积对应一笔被接受的激活事务
    output fp8_pkg::fp8_product_t   product_o, // 输出供后续列归约树使用的未舍入FP8精确乘积
    output logic                    invalid_o // 标识当前有效乘积由无穷乘零产生IEEE无效操作
); // 结束PE_FP8端口声明

logic [7:0] weight_q; // 保存当前PE在一个矩阵计算块期间持续复用的FP8权重
fp8_pkg::fp8_format_e weight_format_q; // 保存与驻留FP8权重同步的E4M3或E5M2格式
logic compute_valid; // 标识当前激活可使用已驻留权重启动精确乘法
logic multiply_invalid_comb; // 标识当前FP8操作数组合形成无穷乘零
fp8_pkg::fp8_decoded_t act_decoded_comb; // 接收当前FP8激活的组合解包结果
fp8_pkg::fp8_decoded_t weight_decoded_comb; // 接收当前驻留权重的组合解包结果

assign compute_valid = act_valid_i && weight_loaded_o && !rst_i && !clear_i; // 同拍写入新权重时仍使用时钟沿前的驻留权重完成上一矩阵乘法
assign multiply_invalid_comb = (act_decoded_comb.is_inf && weight_decoded_comb.is_zero) || (act_decoded_comb.is_zero && weight_decoded_comb.is_inf); // 检测当前操作数形成的IEEE无穷乘零无效操作

always_ff @(posedge clk_i) begin // 在独立驻留寄存器中装载并保持当前PE的FP8权重和格式
    if (rst_i) begin // 同步复位时使驻留权重失效并恢复确定数据状态
        weight_loaded_o <= 1'b0; // 阻止复位后在未重新装载权重前启动计算
        weight_q <= 8'h00; // 将复位后的无效驻留权重编码清零
        weight_format_q <= fp8_pkg::FP8_E4M3; // 将复位后的无效权重格式恢复为E4M3
    end else if (weight_load_i) begin // 有效装载周期用B SRAM数据原子替换本PE驻留权重
        weight_loaded_o <= 1'b1; // 标记新驻留权重可从下一个周期开始参与计算
        weight_q <= weight_i; // 锁存当前B SRAM提供的八位FP8权重编码
        weight_format_q <= weight_format_i; // 锁存与当前权重编码对应的FP8格式
    end // 结束同步复位、权重装载和默认保持分支
end // 结束FP8驻留权重时序逻辑

always_ff @(posedge clk_i) begin // 独立寄存水平激活转发通道并限制clear只清除有效状态
    if (rst_i) begin // 同步复位时丢弃激活事务并清零可见转发端口
        act_valid_o <= 1'b0; // 清空向右转发的激活有效状态
        act_o <= 8'h00; // 清零向右转发的FP8激活编码
        act_format_o <= fp8_pkg::FP8_E4M3; // 将无效激活格式恢复为E4M3
    end else if (clear_i) begin // 流水清空仅中断激活有效状态而不改写操作数数据
        act_valid_o <= 1'b0; // 丢弃当前向右转发事务并保持无效数据稳定
    end else begin // 正常周期推进激活有效状态并按有效条件更新数据
        act_valid_o <= act_valid_i; // 将当前激活有效状态送入一拍水平传播通道
        if (act_valid_i) begin // 仅对有效激活更新转发数据以减少空拍翻转
            act_o <= act_i; // 将当前FP8激活寄存后向右传播
            act_format_o <= act_format_i; // 将当前激活格式与数据同步向右传播
        end // 结束有效激活转发数据更新条件
    end // 结束激活转发同步控制与正常推进分支
end // 结束水平激活转发时序逻辑

fp8_unpack #(.DAZ(DAZ)) u_unpack_act ( // 例化支持可选DAZ模式的FP8激活组合解包器
    .data_i    (act_i), // 连接从左侧到达的FP8激活编码
    .format_i  (act_format_i), // 连接当前激活输入格式
    .decoded_o (act_decoded_comb) // 接收FP8激活统一Q1.3解码结果
); // 结束FP8激活解包器实例

fp8_unpack #(.DAZ(DAZ)) u_unpack_weight ( // 例化支持可选DAZ模式的驻留权重组合解包器
    .data_i    (weight_q), // 连接当前PE内部持续复用的FP8权重编码
    .format_i  (weight_format_q), // 连接当前PE驻留权重格式
    .decoded_o (weight_decoded_comb) // 接收驻留权重统一Q1.3解码结果
); // 结束驻留权重解包器实例

fp8_mul_exact u_fp8_mul_exact ( // 例化一级流水的四位Radix-4尾数精确乘法器
    .clk_i     (clk_i), // 连接PE乘积流水工作时钟
    .rst_i     (rst_i), // 连接同步高有效复位信号
    .clear_i   (clear_i), // 连接同步高有效流水清空信号
    .valid_i   (compute_valid), // 仅为具备有效激活和驻留权重的事务启动乘法
    .a_i       (act_decoded_comb), // 连接当前组合解包的FP8激活
    .b_i       (weight_decoded_comb), // 连接当前组合解包的FP8驻留权重
    .valid_o   (product_valid_o), // 接收一级流水精确乘积有效状态
    .product_o (product_o) // 接收未规格化且未舍入的FP8精确乘积
); // 结束FP8精确乘法器实例

always_ff @(posedge clk_i) begin // 将乘法无效状态与一级精确乘积流水保持对齐
    if (rst_i || clear_i) begin // 同步复位或清空时丢弃无效操作状态
        invalid_o <= 1'b0; // 防止无有效乘积时残留invalid状态
    end else begin // 正常周期生成与当前被接受乘法事务对应的invalid状态
        invalid_o <= compute_valid && multiply_invalid_comb; // 仅对有效无穷乘零事务声明IEEE invalid
    end // 结束同步控制和正常invalid状态生成分支
end // 结束乘法invalid状态流水逻辑

endmodule // 结束PE_FP8一级流水精确乘法处理单元模块
