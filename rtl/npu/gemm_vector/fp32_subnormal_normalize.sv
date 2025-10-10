`timescale 1ns/1ps // 定义FP32 Subnormal两级规格化流水模块的仿真时间单位与时间精度

module fp32_subnormal_normalize ( // 定义在LZC和动态左移之间打一拍的FP32规格化模块
    input  logic                    clk_i, // 输入规格化流水工作时钟
    input  logic                    rst_i, // 输入同步高有效复位信号
    input  fp8_pkg::fp32_unpacked_t unpacked_i, // 输入字段解包和分类后的FP32中间结构
    output fp8_pkg::fp32_decoded_t  decoded_o // 输出延后一拍的统一规格化FP32结构
); // 结束FP32 Subnormal流水规格化模块端口声明

logic [23:0] subnormal_raw_comb; // 保存包含固定零隐藏位的二十四位Subnormal原始有效数
logic [31:0] lzc_input_comb; // 保存填充到三十二位的LZC输入向量
logic [15:0] lzc_stage16_comb; // 保存平衡LZC树选中的十六位候选区
logic [7:0] lzc_stage8_comb; // 保存平衡LZC树选中的八位候选区
logic [3:0] lzc_stage4_comb; // 保存平衡LZC树选中的四位候选区
logic [1:0] lzc_stage2_comb; // 保存平衡LZC树选中的两位候选区
logic [4:0] lzc_count_comb; // 保存填充向量对应的五位前导零计数
logic [4:0] normalize_shift_comb; // 保存直接驱动下一级左移器的规格化移位量

logic sign_comb; // 保存第一级需要旁路的符号位
logic signed [9:0] exponent_comb; // 保存第一级已经完成Subnormal修正的十位无偏指数
logic [23:0] significand_comb; // 保存第一级需要旁路的二十四位有效数

always_comb begin // 在第一级组合路径中准备可直接寄存的旁路元数据
    sign_comb = unpacked_i.sign; // 旁路输入符号位
    exponent_comb = unpacked_i.exponent; // 默认旁路Normal、零和特殊值的基础无偏指数
    significand_comb = unpacked_i.significand; // 旁路完整有效数以保持NaN等特殊值行为
    if (unpacked_i.is_subnormal) begin // Subnormal在寄存器前完成指数修正以消除输出侧串行减法
        exponent_comb = -10'sd126 - $signed({5'b00000, normalize_shift_comb}); // 使用LZC移位量生成最终无偏指数
    end // 结束Subnormal指数修正选择
end // 结束可直接寄存元数据生成逻辑

always_comb begin // 在第一级组合路径中完成二十四位原始有效数LZC
    subnormal_raw_comb = {1'b0, unpacked_i.significand[22:0]}; // 在二十三位小数前保留Subnormal零隐藏位
    lzc_input_comb = {subnormal_raw_comb, 8'b00000000}; // 将二十四位原始有效数映射到三十二位LZC高位
    if (|lzc_input_comb[31:16]) begin // 最高十六位存在一时选择高半区
        lzc_count_comb[4] = 1'b0; // 高半区命中时前导零小于十六
        lzc_stage16_comb = lzc_input_comb[31:16]; // 将高半区送入下一级定位
    end else begin // 最高十六位全零时选择低半区
        lzc_count_comb[4] = 1'b1; // 低半区命中时增加十六个前导零
        lzc_stage16_comb = lzc_input_comb[15:0]; // 将低半区送入下一级定位
    end // 结束十六位候选区选择
    if (|lzc_stage16_comb[15:8]) begin // 当前候选区高八位存在一时选择高八位
        lzc_count_comb[3] = 1'b0; // 高八位命中时不增加八个前导零
        lzc_stage8_comb = lzc_stage16_comb[15:8]; // 将高八位送入下一级定位
    end else begin // 当前候选区高八位全零时选择低八位
        lzc_count_comb[3] = 1'b1; // 低八位命中时增加八个前导零
        lzc_stage8_comb = lzc_stage16_comb[7:0]; // 将低八位送入下一级定位
    end // 结束八位候选区选择
    if (|lzc_stage8_comb[7:4]) begin // 当前候选区高四位存在一时选择高四位
        lzc_count_comb[2] = 1'b0; // 高四位命中时不增加四个前导零
        lzc_stage4_comb = lzc_stage8_comb[7:4]; // 将高四位送入下一级定位
    end else begin // 当前候选区高四位全零时选择低四位
        lzc_count_comb[2] = 1'b1; // 低四位命中时增加四个前导零
        lzc_stage4_comb = lzc_stage8_comb[3:0]; // 将低四位送入下一级定位
    end // 结束四位候选区选择
    if (|lzc_stage4_comb[3:2]) begin // 当前候选区高两位存在一时选择高两位
        lzc_count_comb[1] = 1'b0; // 高两位命中时不增加两个前导零
        lzc_stage2_comb = lzc_stage4_comb[3:2]; // 将高两位送入最后一级定位
    end else begin // 当前候选区高两位全零时选择低两位
        lzc_count_comb[1] = 1'b1; // 低两位命中时增加两个前导零
        lzc_stage2_comb = lzc_stage4_comb[1:0]; // 将低两位送入最后一级定位
    end // 结束两位候选区选择
    if (lzc_stage2_comb[1]) begin // 候选两位最高位为一时不增加末位前导零
        lzc_count_comb[0] = 1'b0; // 最高位命中时末位计数为零
    end else if (lzc_stage2_comb[0]) begin // 候选两位最低位为一时末位增加一个前导零
        lzc_count_comb[0] = 1'b1; // 最低位命中时末位计数为一
    end else begin // 候选两位均为零时由全零保护逻辑覆盖移位量
        lzc_count_comb[0] = 1'b1; // 最低位命中或全零时均保持确定结果
    end // 结束两位候选末位计数
    if (subnormal_raw_comb == 24'h000000) begin // 原始有效数全零时提供确定饱和移位量
        normalize_shift_comb = 5'd24; // 全零保护值等于二十四位输入宽度
    end else begin // 非零Subnormal的LZC结果就是所需规格化移位量
        normalize_shift_comb = lzc_count_comb; // 直接使用二十四位LZC结果而不再加一
    end // 结束全零与非零移位量选择
end // 结束第一级LZC和规格化移位量组合逻辑

logic sign_q; // 保存一级寄存后的符号位
logic signed [9:0] exponent_q; // 保存一级寄存后的最终十位无偏指数
logic [23:0] significand_q; // 保存一级寄存后的完整有效数
logic is_zero_q; // 保存一级寄存后的有符号零分类
logic is_subnormal_q; // 保存一级寄存后的Subnormal分类
logic is_normal_q; // 保存一级寄存后的Normal分类
logic is_inf_q; // 保存一级寄存后的无穷分类
logic is_nan_q; // 保存一级寄存后的NaN分类
logic [4:0] normalize_shift_q; // 保存一级寄存后的规格化移位量

always_ff @(posedge clk_i) begin // 在LZC和动态左移之间建立同步流水寄存边界
    if (rst_i) begin // 同步复位时清空旁路字段和一级中间结果
        sign_q <= 1'b0; // 清空符号位寄存值
        exponent_q <= 10'sd0; // 清空最终无偏指数寄存值
        significand_q <= 24'h000000; // 清空有效数寄存值
        is_zero_q <= 1'b0; // 清空有符号零分类寄存值
        is_subnormal_q <= 1'b0; // 清空Subnormal分类寄存值
        is_normal_q <= 1'b0; // 清空Normal分类寄存值
        is_inf_q <= 1'b0; // 清空无穷分类寄存值
        is_nan_q <= 1'b0; // 清空NaN分类寄存值
        normalize_shift_q <= 5'd0; // 清空规格化移位量寄存值
    end else begin // 正常周期采样第一级组合结果
        sign_q <= sign_comb; // 采样符号旁路字段
        exponent_q <= exponent_comb; // 采样已经完成Subnormal修正的最终指数
        significand_q <= significand_comb; // 采样完整有效数旁路字段
        is_zero_q <= unpacked_i.is_zero; // 直接采样有符号零分类以移除输出侧分类解码
        is_subnormal_q <= unpacked_i.is_subnormal; // 直接采样Subnormal分类以驱动规格化有效数选择
        is_normal_q <= unpacked_i.is_normal; // 直接采样Normal分类供后级有限数判断
        is_inf_q <= unpacked_i.is_inf; // 直接采样无穷分类供后级特殊值判断
        is_nan_q <= unpacked_i.is_nan; // 直接采样NaN分类供后级特殊值判断
        normalize_shift_q <= normalize_shift_comb; // 锁存动态左移器的控制移位量
    end // 结束同步复位和正常采样分支
end // 结束LZC到动态左移的流水寄存边界

logic [23:0] subnormal_normalized_comb; // 保存第二级动态左移后的规格化有效数

always_comb begin // 在第二级组合路径中完成动态左移和统一输出选择
    subnormal_normalized_comb = {1'b0, significand_q[22:0]} << normalize_shift_q; // 从寄存有效数重建Subnormal原始数并左移
    decoded_o = '0; // 默认清零统一规格化结构
    decoded_o.sign = sign_q; // 保留寄存后的FP32符号位
    decoded_o.exponent = exponent_q; // 直接输出寄存后的最终十位无偏指数
    decoded_o.significand = significand_q; // 默认沿用Normal或特殊值有效数
    decoded_o.is_zero = is_zero_q; // 直接输出寄存后的有符号零分类
    decoded_o.is_subnormal = is_subnormal_q; // 直接输出寄存后的Subnormal分类
    decoded_o.is_normal = is_normal_q; // 直接输出寄存后的Normal分类
    decoded_o.is_inf = is_inf_q; // 直接输出寄存后的无穷分类
    decoded_o.is_nan = is_nan_q; // 直接输出寄存后的NaN分类
    if (is_subnormal_q) begin // Subnormal使用寄存后的移位量和动态左移结果
        decoded_o.significand = subnormal_normalized_comb; // 输出包含隐藏位的一点二十三格式有效数
    end // 结束Subnormal规格化选择
end // 结束第二级动态左移和统一输出组合逻辑

endmodule // 结束FP32 Subnormal两级规格化流水模块
