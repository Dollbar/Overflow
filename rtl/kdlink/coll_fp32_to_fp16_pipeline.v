module coll_fp32_to_fp16_pipeline ( // 定义八级 IEEE FP32 到 FP16 RNE 舍入流水
    input  wire clk_i, // 接收 reduction 时钟
    input  wire rst_n_i, // 接收低有效异步复位
    input  wire valid_i, // 接收 FP32 输入有效
    input  wire [31:0] value_i, // 接收 FP32 编码
    output reg valid_o, // 指示 FP16 舍入结果有效
    output reg [15:0] value_o // 输出 FP16 编码
); // 结束端口声明
    reg valid_class_q; reg [31:0] value_class_q; reg signed [9:0] target_exp_class_q; reg [10:0] rounded_normal_class_q; reg [25:0] shift_word_class_q; reg [5:0] sub_shift_class_q; // 保存分类级字段
    reg valid_low_q; reg [31:0] value_low_q; reg signed [9:0] target_exp_low_q; reg [10:0] rounded_normal_low_q; reg [25:0] shift_word_low_q; reg [3:0] sub_shift_low_q; reg sticky_low_q; // 保存四位及更高选择所需的高四位移位量
    reg valid_shift4_q; reg [31:0] value_shift4_q; reg signed [9:0] target_exp_shift4_q; reg [10:0] rounded_normal_shift4_q; reg [25:0] shift_word_shift4_q; reg [2:0] sub_shift_shift4_q; reg sticky_shift4_q; // 保存八位及更高选择所需的高三位移位量
    reg valid_shift8_q; reg [31:0] value_shift8_q; reg signed [9:0] target_exp_shift8_q; reg [10:0] rounded_normal_shift8_q; reg [25:0] shift_word_shift8_q; reg [1:0] sub_shift_shift8_q; reg sticky_shift8_q; // 保存十六位和超范围选择所需的高两位移位量
    reg valid_shift16_q; reg [31:0] value_shift16_q; reg signed [9:0] target_exp_shift16_q; reg [10:0] rounded_normal_shift16_q; reg [25:0] shift_word_shift16_q; reg sticky_shift16_q; // 保存十六位移位级字段
    reg valid_round_parts_q; reg [31:0] value_round_parts_q; reg signed [9:0] target_exp_round_parts_q; reg [10:0] rounded_normal_round_parts_q; // 保存 subnormal 分段舍入级元数据
    reg [12:0] rounded_sub_low_q; reg [12:0] rounded_sub_high0_q; reg [12:0] rounded_sub_high1_q; // 保存 subnormal 低半和高半候选
    reg valid_round_q; reg [31:0] value_round_q; reg signed [9:0] target_exp_round_q; reg [10:0] rounded_normal_round_q; reg [24:0] rounded_sub_round_q; // 保存 subnormal 候选拼接级字段
    reg signed [9:0] target_exp_d; reg [10:0] rounded_normal_d; reg [5:0] sub_shift_d; // 计算输入分类级中间量
    reg [25:0] shift_word_low_d; reg sticky_low_d; reg [25:0] shift_word_shift4_d; reg sticky_shift4_d; // 计算低两位和四位移位结果
    reg [25:0] shift_word_shift8_d; reg sticky_shift8_d; reg [25:0] shift_word_shift16_d; reg sticky_shift16_d; // 计算八位和十六位移位结果
    reg [12:0] rounded_sub_low_d; reg [12:0] rounded_sub_high0_d; reg [12:0] rounded_sub_high1_d; reg [15:0] packed_d; // 计算分段 subnormal RNE 和最终编码
    always @(*) begin // 组合计算输入 exponent 和 normal 舍入
        target_exp_d = $signed({2'b00, value_i[30:23]}) - 10'sd112; // 从 FP32 bias 换算到 FP16 bias
        rounded_normal_d = {1'b0, value_i[22:13]} + (value_i[12] && (|value_i[11:0] || value_i[13])); // 对 normal fraction 执行 RNE
        sub_shift_d = 6'd14 - target_exp_d[5:0]; // 计算 FP16 subnormal 总右移位数
    end // 结束输入分类组合逻辑
    always @(*) begin // 组合执行零至三位低半移位并累计 sticky
        shift_word_low_d = shift_word_class_q; sticky_low_d = 1'b0; // 默认不移位且无丢弃位
        case (sub_shift_class_q[1:0]) // 仅解码总移位量低两位
            2'd0: begin shift_word_low_d = shift_word_class_q; sticky_low_d = 1'b0; end // 不执行低半移位
            2'd1: begin shift_word_low_d = shift_word_class_q >> 1; sticky_low_d = shift_word_class_q[0]; end // 右移一位
            2'd2: begin shift_word_low_d = shift_word_class_q >> 2; sticky_low_d = |shift_word_class_q[1:0]; end // 右移两位
            default: begin shift_word_low_d = shift_word_class_q >> 3; sticky_low_d = |shift_word_class_q[2:0]; end // 右移三位
        endcase // 结束低半移位选择
    end // 结束低半移位组合逻辑
    always @(*) begin // 组合执行可选四位右移
        shift_word_shift4_d = shift_word_low_q; sticky_shift4_d = sticky_low_q; // 默认保持低半结果
        if (sub_shift_low_q[0]) begin shift_word_shift4_d = shift_word_low_q >> 4; sticky_shift4_d = sticky_low_q || |shift_word_low_q[3:0]; end // 移位四并累计丢弃位
    end // 结束四位移位组合逻辑
    always @(*) begin // 组合执行可选八位右移
        shift_word_shift8_d = shift_word_shift4_q; sticky_shift8_d = sticky_shift4_q; // 默认保持四位级结果
        if (sub_shift_shift4_q[0]) begin shift_word_shift8_d = shift_word_shift4_q >> 8; sticky_shift8_d = sticky_shift4_q || |shift_word_shift4_q[7:0]; end // 移位八并累计丢弃位
    end // 结束八位移位组合逻辑
    always @(*) begin // 组合执行可选十六位右移或超范围清零
        shift_word_shift16_d = shift_word_shift8_q; sticky_shift16_d = sticky_shift8_q; // 默认保持八位级结果
        if (sub_shift_shift8_q[1]) begin shift_word_shift16_d = 26'd0; sticky_shift16_d = sticky_shift8_q || |shift_word_shift8_q; end // 三十二位以上移位使有限尾数完全移出
        else if (sub_shift_shift8_q[0]) begin shift_word_shift16_d = shift_word_shift8_q >> 16; sticky_shift16_d = sticky_shift8_q || |shift_word_shift8_q[15:0]; end // 移位十六并累计丢弃位
    end // 结束十六位移位组合逻辑
    always @(*) begin // 组合执行 subnormal RNE 加法
        rounded_sub_low_d = {1'b0, shift_word_shift16_q[12:1]} + (shift_word_shift16_q[0] && (sticky_shift16_q || shift_word_shift16_q[1])); // 对保留尾数低十二位执行 RNE 增量
        rounded_sub_high0_d = shift_word_shift16_q[25:13]; rounded_sub_high1_d = shift_word_shift16_q[25:13] + 13'd1; // 并行形成高十三位模加一候选
    end // 结束 subnormal 舍入组合逻辑
    always @(*) begin // 组合执行最终 FP16 分类打包
        packed_d = {value_round_q[31], 15'd0}; // 默认 underflow 为 signed zero
        if (value_round_q[30:23] == 8'hFF) begin // 检查 NaN 或 infinity
            if (value_round_q[22:0] != 23'd0) packed_d = 16'h7E00; else packed_d = {value_round_q[31], 5'h1F, 10'd0}; // canonicalize NaN 或传播 infinity
        end else if (value_round_q[30:0] == 31'd0) packed_d = {value_round_q[31], 15'd0}; // 保留 signed zero
        else if (target_exp_round_q >= 10'sd31) packed_d = {value_round_q[31], 5'h1F, 10'd0}; // overflow 输出 infinity
        else if (target_exp_round_q >= 10'sd1) begin // 处理 FP16 normal 范围
            if (rounded_normal_round_q[10]) begin // 检查 fraction 舍入进位
                if (target_exp_round_q >= 10'sd30) packed_d = {value_round_q[31], 5'h1F, 10'd0}; else packed_d = {value_round_q[31], target_exp_round_q[4:0] + 1'b1, 10'd0}; // 处理 exponent 再进位
            end else packed_d = {value_round_q[31], target_exp_round_q[4:0], rounded_normal_round_q[9:0]}; // 输出无进位 normal
        end else if (target_exp_round_q >= -10'sd10) begin // 处理可舍入 subnormal 范围
            if (rounded_sub_round_q >= 25'h400) packed_d = {value_round_q[31], 5'd1, 10'd0}; else packed_d = {value_round_q[31], 5'd0, rounded_sub_round_q[9:0]}; // 输出最小 normal 或 subnormal
        end // 结束 FP16 分类选择
    end // 结束最终 FP16 打包组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新八级 FP16 舍入流水
        if (!rst_n_i) begin // 检测复位有效
            valid_class_q <= 1'b0; value_class_q <= 32'd0; target_exp_class_q <= 10'sd0; rounded_normal_class_q <= 11'd0; shift_word_class_q <= 26'd0; sub_shift_class_q <= 6'd0; // 清零分类级
            valid_low_q <= 1'b0; value_low_q <= 32'd0; target_exp_low_q <= 10'sd0; rounded_normal_low_q <= 11'd0; shift_word_low_q <= 26'd0; sub_shift_low_q <= 4'd0; sticky_low_q <= 1'b0; // 清零低半移位级
            valid_shift4_q <= 1'b0; value_shift4_q <= 32'd0; target_exp_shift4_q <= 10'sd0; rounded_normal_shift4_q <= 11'd0; shift_word_shift4_q <= 26'd0; sub_shift_shift4_q <= 3'd0; sticky_shift4_q <= 1'b0; // 清零四位移位级
            valid_shift8_q <= 1'b0; value_shift8_q <= 32'd0; target_exp_shift8_q <= 10'sd0; rounded_normal_shift8_q <= 11'd0; shift_word_shift8_q <= 26'd0; sub_shift_shift8_q <= 2'd0; sticky_shift8_q <= 1'b0; // 清零八位移位级
            valid_shift16_q <= 1'b0; value_shift16_q <= 32'd0; target_exp_shift16_q <= 10'sd0; rounded_normal_shift16_q <= 11'd0; shift_word_shift16_q <= 26'd0; sticky_shift16_q <= 1'b0; // 清零十六位移位级
            valid_round_parts_q <= 1'b0; value_round_parts_q <= 32'd0; target_exp_round_parts_q <= 10'sd0; rounded_normal_round_parts_q <= 11'd0; rounded_sub_low_q <= 13'd0; rounded_sub_high0_q <= 13'd0; rounded_sub_high1_q <= 13'd0; // 清零分段舍入候选级
            valid_round_q <= 1'b0; value_round_q <= 32'd0; target_exp_round_q <= 10'sd0; rounded_normal_round_q <= 11'd0; rounded_sub_round_q <= 25'd0; // 清零候选拼接级
            valid_o <= 1'b0; value_o <= 16'd0; // 清零输出打包级
        end else begin // 处理舍入流水正常前推
            valid_class_q <= valid_i; value_class_q <= value_i; target_exp_class_q <= target_exp_d; rounded_normal_class_q <= rounded_normal_d; shift_word_class_q <= {1'b0, 1'b1, value_i[22:0], 1'b0}; sub_shift_class_q <= sub_shift_d; // 锁存输入分类和带 guard 空位尾数
            valid_low_q <= valid_class_q; value_low_q <= value_class_q; target_exp_low_q <= target_exp_class_q; rounded_normal_low_q <= rounded_normal_class_q; shift_word_low_q <= shift_word_low_d; sub_shift_low_q <= sub_shift_class_q[5:2]; sticky_low_q <= sticky_low_d; // 锁存低半移位结果和剩余高四位移位量
            valid_shift4_q <= valid_low_q; value_shift4_q <= value_low_q; target_exp_shift4_q <= target_exp_low_q; rounded_normal_shift4_q <= rounded_normal_low_q; shift_word_shift4_q <= shift_word_shift4_d; sub_shift_shift4_q <= sub_shift_low_q[3:1]; sticky_shift4_q <= sticky_shift4_d; // 锁存四位移位结果和剩余高三位移位量
            valid_shift8_q <= valid_shift4_q; value_shift8_q <= value_shift4_q; target_exp_shift8_q <= target_exp_shift4_q; rounded_normal_shift8_q <= rounded_normal_shift4_q; shift_word_shift8_q <= shift_word_shift8_d; sub_shift_shift8_q <= sub_shift_shift4_q[2:1]; sticky_shift8_q <= sticky_shift8_d; // 锁存八位移位结果和剩余高两位移位量
            valid_shift16_q <= valid_shift8_q; value_shift16_q <= value_shift8_q; target_exp_shift16_q <= target_exp_shift8_q; rounded_normal_shift16_q <= rounded_normal_shift8_q; shift_word_shift16_q <= shift_word_shift16_d; sticky_shift16_q <= sticky_shift16_d; // 锁存十六位移位结果
            valid_round_parts_q <= valid_shift16_q; value_round_parts_q <= value_shift16_q; target_exp_round_parts_q <= target_exp_shift16_q; rounded_normal_round_parts_q <= rounded_normal_shift16_q; rounded_sub_low_q <= rounded_sub_low_d; rounded_sub_high0_q <= rounded_sub_high0_d; rounded_sub_high1_q <= rounded_sub_high1_d; // 锁存 subnormal 分段舍入候选
            valid_round_q <= valid_round_parts_q; value_round_q <= value_round_parts_q; target_exp_round_q <= target_exp_round_parts_q; rounded_normal_round_q <= rounded_normal_round_parts_q; rounded_sub_round_q <= {rounded_sub_low_q[12] ? rounded_sub_high1_q : rounded_sub_high0_q, rounded_sub_low_q[11:0]}; // 下一拍选择高半候选并拼接完整舍入结果
            valid_o <= valid_round_q; value_o <= packed_d; // 锁存最终 FP16 编码
        end // 结束舍入流水正常前推
    end // 结束八级 FP16 舍入流水
endmodule // 结束 FP32 到 FP16 RNE 流水
