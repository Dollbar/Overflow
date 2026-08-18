module coll_fp16_to_fp32 ( // 定义 IEEE FP16 到 FP32 精确扩展单元
    input  wire [15:0] value_i, // 接收 FP16 编码
    output reg [31:0] value_o // 输出精确 FP32 编码
); // 结束端口声明
    reg [9:0] fraction_shift_d; // 保存移除 hidden bit 后的 FP16 subnormal fraction
    reg [3:0] leading_d; // 保存十位 fraction 前导零数量
    always @(*) begin // 组合执行 FP16 分类和扩展
        leading_d = 4'd10; // 默认 fraction 全零
        fraction_shift_d = 10'd0; // 默认 fraction 全零无需归一化
        if (|value_i[9:5]) begin // 在高五位组内执行最多五级优先选择
            if (value_i[9]) begin leading_d = 4'd0; fraction_shift_d = value_i[9:0] << 1; end // fraction 位九为首个一
            else if (value_i[8]) begin leading_d = 4'd1; fraction_shift_d = value_i[9:0] << 2; end // fraction 位八为首个一
            else if (value_i[7]) begin leading_d = 4'd2; fraction_shift_d = value_i[9:0] << 3; end // fraction 位七为首个一
            else if (value_i[6]) begin leading_d = 4'd3; fraction_shift_d = value_i[9:0] << 4; end // fraction 位六为首个一
            else begin leading_d = 4'd4; fraction_shift_d = value_i[9:0] << 5; end // fraction 位五为首个一
        end else if (|value_i[4:0]) begin // 在低五位组内执行最多五级优先选择
            if (value_i[4]) begin leading_d = 4'd5; fraction_shift_d = value_i[9:0] << 6; end // fraction 位四为首个一
            else if (value_i[3]) begin leading_d = 4'd6; fraction_shift_d = value_i[9:0] << 7; end // fraction 位三为首个一
            else if (value_i[2]) begin leading_d = 4'd7; fraction_shift_d = value_i[9:0] << 8; end // fraction 位二为首个一
            else if (value_i[1]) begin leading_d = 4'd8; fraction_shift_d = value_i[9:0] << 9; end // fraction 位一为首个一
            else begin leading_d = 4'd9; fraction_shift_d = 10'd0; end // fraction 位零为首个一且剩余 fraction 为零
        end // 结束分层 fraction 首一选择
        if (value_i[14:10] == 5'h1F) begin // 检查 NaN 或 infinity
            if (value_i[9:0] != 10'd0) value_o = 32'h7FC00000; // canonicalize NaN
            else value_o = {value_i[15], 8'hFF, 23'd0}; // 精确扩展 infinity
        end else if (value_i[14:10] == 5'd0) begin // 检查 zero 或 subnormal
            if (value_i[9:0] == 10'd0) value_o = {value_i[15], 31'd0}; // 保留 signed zero
            else value_o = {value_i[15], (8'd112 - {4'd0, leading_d}), fraction_shift_d, 13'd0}; // 归一化并扩展 FP16 subnormal
        end else begin // 处理 FP16 normal
            value_o = {value_i[15], ({3'd0, value_i[14:10]} + 8'd112), value_i[9:0], 13'd0}; // 调整 exponent bias 并零扩展 fraction
        end // 结束 FP16 分类选择
    end // 结束 FP16 扩展组合逻辑
endmodule // 结束 FP16 到 FP32 扩展单元
