module coll_fp32_to_bf16 ( // 定义 IEEE FP32 到 BF16 RNE 舍入单元
    input  wire [31:0] value_i, // 接收 FP32 编码
    output wire [15:0] value_o // 输出 BF16 编码
); // 结束端口声明
    wire is_nan; // 指示输入为 NaN
    wire round_up; // 指示 BF16 截断低十六位需 RNE 增一
    wire [15:0] rounded; // 保存普通 BF16 舍入结果
    assign is_nan = (value_i[30:23] == 8'hFF) && (value_i[22:0] != 23'd0); // 检查 NaN 分类
    assign round_up = (value_i[15:0] > 16'h8000) || ((value_i[15:0] == 16'h8000) && value_i[16]); // 执行 ties-to-even 判定
    assign rounded = value_i[31:16] + round_up; // 对 BF16 保留高半字执行舍入
    assign value_o = is_nan ? 16'h7FC0 : rounded; // NaN canonicalize 否则输出 RNE BF16
endmodule // 结束 FP32 到 BF16 RNE 单元
