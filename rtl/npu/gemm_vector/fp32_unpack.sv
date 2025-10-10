`timescale 1ns/1ps // 定义IEEE FP32字段解包模块的仿真时间单位与时间精度

module fp32_unpack ( // 定义只负责字段拆分和数值分类的FP32组合解包器
    input  logic                   [31:0] data_i, // 输入一个原始IEEE FP32编码
    output fp8_pkg::fp32_unpacked_t unpacked_o // 输出Subnormal规格化前的中间解码结构
); // 结束fp32_unpack端口声明

logic [7:0] exp_field; // 保存IEEE FP32八位偏置指数域
logic [22:0] frac_field; // 保存IEEE FP32二十三位小数域

always_comb begin // 仅执行符号、字段拆分、分类和基础指数生成
    exp_field = data_i[30:23]; // 提取原始FP32指数域
    frac_field = data_i[22:0]; // 提取原始FP32小数域
    unpacked_o = '0; // 默认清零中间数值和全部互斥分类标志
    unpacked_o.sign = data_i[31]; // 保留所有FP32编码的符号位
    unpacked_o.significand = {1'b0, frac_field}; // 无条件直通小数域以消除指数分类到Subnormal LZC输入的假依赖
    if (exp_field == 8'h00) begin // 处理零指数域对应的零或Subnormal
        if (frac_field == 23'h000000) begin // 指数和小数均为零时识别有符号零
            unpacked_o.is_zero = 1'b1; // 声明当前编码为正零或负零
        end else begin // 零指数与非零小数构成Subnormal中间值
            unpacked_o.exponent = -10'sd126; // 记录Subnormal未规格化表示的基础指数
            unpacked_o.is_subnormal = 1'b1; // 声明当前编码为FP32非规格数
        end // 结束零指数域的零与Subnormal分类
    end else if (exp_field == 8'hff) begin // 处理全一指数域对应的无穷或NaN
        if (frac_field == 23'h000000) begin // 全一指数且零小数编码有符号无穷
            unpacked_o.is_inf = 1'b1; // 声明当前编码为正无穷或负无穷
        end else begin // 全一指数且非零小数编码NaN
            unpacked_o.is_nan = 1'b1; // 声明当前编码为NaN并保留原始payload
        end // 结束全一指数域的无穷与NaN分类
    end else begin // 处理指数既非零也非全一的规格化有限数
        unpacked_o.exponent = $signed({2'b00, exp_field}) - 10'sd127; // 生成规格化数的无偏指数
        unpacked_o.significand[23] = 1'b1; // 仅由Normal分类补入隐藏位而不再门控原始小数域
        unpacked_o.is_normal = 1'b1; // 声明当前编码为规格化有限数
    end // 结束FP32全部编码分类
end // 结束FP32字段解包组合逻辑

endmodule // 结束只负责字段和分类的FP32解包器
