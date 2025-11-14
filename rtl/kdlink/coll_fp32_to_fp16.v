module coll_fp32_to_fp16 ( // 定义 IEEE FP32 到 FP16 RNE 舍入单元
    input  wire [31:0] value_i, // 接收 FP32 编码
    output reg [15:0] value_o // 输出 FP16 编码
); // 结束端口声明
    reg signed [9:0] target_exp_d; // 保存换算后的 FP16 biased exponent
    reg [10:0] rounded_normal_d; // 保存 normal fraction 舍入结果
    reg [24:0] mantissa_ext_d; // 保存含 hidden bit 的 FP32 尾数
    reg [5:0] sub_shift_d; // 保存 FP16 subnormal 总右移位数
    reg [4:0] sub_guard_index_d; // 保存 subnormal guard 位有效索引
    reg [24:0] sub_trunc_d; // 保存 subnormal 截断整数
    reg sub_guard_d; // 保存 subnormal guard bit
    reg sub_sticky_d; // 保存 subnormal sticky bit
    reg [24:0] sub_mask_d; // 保存 subnormal 被丢弃位 mask
    always @(*) begin // 组合执行 FP32 分类和 FP16 RNE
        target_exp_d = $signed({2'b00, value_i[30:23]}) - 10'sd112; // 从 FP32 bias 换算到 FP16 bias
        rounded_normal_d = {1'b0, value_i[22:13]} + (value_i[12] && (|value_i[11:0] || value_i[13])); // 对 normal fraction 执行 RNE
        mantissa_ext_d = {1'b0, 1'b1, value_i[22:0]}; // 构造二十四位含 hidden bit 尾数
        sub_shift_d = 6'd14 - target_exp_d[5:0]; // 计算 subnormal 尾数右移总量
        sub_guard_index_d = sub_shift_d[4:0] - 1'b1; // 计算二十五位尾数内 guard 索引
        sub_trunc_d = (sub_shift_d >= 6'd25) ? 25'd0 : (mantissa_ext_d >> sub_shift_d); // 截断 subnormal 尾数
        sub_guard_d = (sub_shift_d == 6'd0 || sub_shift_d > 6'd25) ? 1'b0 : mantissa_ext_d[sub_guard_index_d]; // 提取 subnormal guard bit
        sub_mask_d = (sub_shift_d <= 6'd1) ? 25'd0 : ((25'd1 << (sub_shift_d-1'b1)) - 1'b1); // 构造 guard 以下 sticky mask
        sub_sticky_d = |(mantissa_ext_d & sub_mask_d); // 归约 subnormal sticky bit
        if (value_i[30:23] == 8'hFF) begin // 检查 NaN 或 infinity
            if (value_i[22:0] != 23'd0) value_o = 16'h7E00; // canonicalize FP16 NaN
            else value_o = {value_i[31], 5'h1F, 10'd0}; // 输出 FP16 infinity
        end else if (value_i[30:0] == 31'd0) begin // 检查 signed zero
            value_o = {value_i[31], 15'd0}; // 保留 signed zero
        end else if (target_exp_d >= 10'sd31) begin // 检查 FP16 overflow
            value_o = {value_i[31], 5'h1F, 10'd0}; // RNE overflow 输出 infinity
        end else if (target_exp_d >= 10'sd1) begin // 处理 FP16 normal 范围
            if (rounded_normal_d[10]) begin // 检查 fraction 舍入进位
                if (target_exp_d >= 10'sd30) value_o = {value_i[31], 5'h1F, 10'd0}; // exponent 再进位后溢出
                else value_o = {value_i[31], target_exp_d[4:0] + 1'b1, 10'd0}; // exponent 增一并清零 fraction
            end else begin // 处理无 fraction 进位 normal
                value_o = {value_i[31], target_exp_d[4:0], rounded_normal_d[9:0]}; // 输出舍入 FP16 normal
            end // 结束 normal fraction 进位选择
        end else if (target_exp_d >= -10'sd10) begin // 处理可舍入为 FP16 subnormal 的范围
            if ((sub_trunc_d + (sub_guard_d && (sub_sticky_d || sub_trunc_d[0]))) >= 25'h400) value_o = {value_i[31], 5'd1, 10'd0}; // subnormal 舍入成为最小 normal
            else value_o = {value_i[31], 5'd0, (sub_trunc_d[9:0] + (sub_guard_d && (sub_sticky_d || sub_trunc_d[0])))}; // 输出舍入 FP16 subnormal
        end else begin // 处理低于 FP16 最小 subnormal
            value_o = {value_i[31], 15'd0}; // underflow 舍入为 signed zero
        end // 结束 FP32 到 FP16 分类选择
    end // 结束 FP16 舍入组合逻辑
endmodule // 结束 FP32 到 FP16 RNE 单元
