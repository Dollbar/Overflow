`timescale 1ns/1ps // 定义FP32舍入封装与特殊结果选择模块的仿真时间单位与时间精度

module fp32_round_pack #( // 定义规格化有效数舍入、IEEE FP32封装和特殊结果选择组合模块
    parameter bit FTZ = 1'b0 // 配置是否将特殊旁路中的FP32非规格结果刷新为有符号零
) ( // 开始fp32_round_pack端口声明
    input  logic        [26:0]            significand_i, // 输入带Guard、Round和Sticky位的规格化有效数
    input  logic signed [10:0]            exponent_i, // 输入规格化后的无偏指数
    input  logic                           sign_i, // 输入有限加减结果符号
    input  logic                           zero_i, // 输入有限加减结果精确为零的分类标志
    input  fp8_pkg::fp8_rounding_e         rounding_i, // 输入IEEE舍入方向
    input  logic                           special_valid_i, // 输入特殊结果已经确定的选择标志
    input  logic        [31:0]             special_result_i, // 输入流水对齐后的完整FP32特殊结果
    output logic        [31:0]             result_o // 输出普通有限路径或特殊旁路选择后的FP32编码
); // 结束fp32_round_pack端口声明

logic round_discarded_comb; // 标识Guard、Round或Sticky位至少存在一个一
logic round_increment_comb; // 标识当前舍入模式要求有效数增加一个ULP
logic [23:0] round_main_comb; // 保存舍入之前的二十四位主有效数
logic [21:0] round_prefix1_comb; // 保存小数字段低二十二位中覆盖相邻二位的全一前缀状态
logic [21:0] round_prefix2_comb; // 保存小数字段低二十二位中覆盖相邻四位的全一前缀状态
logic [21:0] round_prefix4_comb; // 保存小数字段低二十二位中覆盖相邻八位的全一前缀状态
logic [21:0] round_prefix8_comb; // 保存小数字段低二十二位中覆盖相邻十六位的全一前缀状态
(* keep = "true" *) logic [21:0] round_prefix16_comb; // 保存二十三位小数字段进位所需的低位全一前缀状态
(* keep = "true" *) logic round_all_ones_comb; // 标识完整二十四位主有效数全部为一
logic [22:0] round_carry_comb; // 保存条件加一进入二十三位FP32小数字段的并行进位
logic [22:0] rounded_fraction_comb; // 保存并行前缀条件加一后的二十三位FP32小数字段
logic round_overflow_comb; // 标识二十四位主有效数舍入产生最高进位
logic exponent_at_or_below_minus127_comb; // 标识舍入进位修正前指数不大于负一百二十七
logic exponent_minus127_comb; // 标识指数恰好为可由舍入进位修正的负一百二十七
logic exponent_below_minus127_comb; // 标识舍入进位无法修正的更小指数
logic exponent_above127_comb; // 标识输入指数已经大于FP32最大有限无偏指数
logic exponent_plus127_comb; // 标识输入指数恰好位于舍入溢出边界正一百二十七
logic [7:0] biased_exponent_base_comb; // 保存无舍入进位时加一百二十七得到的偏置指数
logic [7:0] biased_exponent_rounded_comb; // 保存有舍入进位时加一百二十八得到的偏置指数
logic [7:0] biased_exponent_comb; // 保存未溢出结果的八位FP32偏置指数
logic overflow_to_inf_comb; // 标识当前舍入方向要求溢出结果选择有符号无穷
logic round_saturate_to_max_comb; // 标识正一百二十七边界舍入后需要钳位到最大有限数
logic [7:0] finite_exponent_comb; // 保存字段级选择后的FP32偏置指数
logic [22:0] finite_fraction_comb; // 保存字段级选择后的FP32小数字段
logic [31:0] finite_result_comb; // 保存普通有限路径封装后的IEEE FP32结果

always_comb begin // 按RNE、RTZ、RUP或RDN计算主有效数舍入增量
    round_main_comb = significand_i[26:3]; // 提取隐藏位和二十三位小数构成主有效数
    round_discarded_comb = |significand_i[2:0]; // 合并Guard、Round与Sticky位判断结果是否精确
    round_increment_comb = 1'b0; // 默认采用向零截断且不增加主有效数
    case (rounding_i) // 根据当前事务舍入方向选择一个ULP增量
        fp8_pkg::RNE: round_increment_comb = significand_i[2] && (significand_i[1] || significand_i[0] || round_main_comb[0]); // 最接近且中点取偶使用GRS和当前最低位判定
        fp8_pkg::RTZ: round_increment_comb = 1'b0; // 向零舍入直接截断全部低位
        fp8_pkg::RUP: round_increment_comb = !sign_i && round_discarded_comb; // 正数存在丢弃位时向正无穷增加一个ULP
        fp8_pkg::RDN: round_increment_comb = sign_i && round_discarded_comb; // 负数存在丢弃位时向负无穷增加一个ULP
        default: round_increment_comb = significand_i[2] && (significand_i[1] || significand_i[0] || round_main_comb[0]); // 未知模式确定性回退到RNE
    endcase // 结束四种IEEE舍入方向选择
end // 结束有效数舍入组合逻辑

always_comb begin // 使用五层并行前缀网络完成二十四位主有效数条件加一
    round_prefix1_comb = round_main_comb[21:0] & {round_main_comb[20:0], 1'b1}; // 合并每个低位与相邻低一位的全一状态
    round_prefix2_comb = round_prefix1_comb & {round_prefix1_comb[19:0], 2'b11}; // 将低位全一前缀覆盖范围扩展到四位
    round_prefix4_comb = round_prefix2_comb & {round_prefix2_comb[17:0], 4'hf}; // 将低位全一前缀覆盖范围扩展到八位
    round_prefix8_comb = round_prefix4_comb & {round_prefix4_comb[13:0], 8'hff}; // 将低位全一前缀覆盖范围扩展到十六位
    round_prefix16_comb = round_prefix8_comb & {round_prefix8_comb[5:0], 16'hffff}; // 建立进入小数字段位一到位二十二的完整低位全一前缀
    round_all_ones_comb = &round_main_comb; // 使用平衡归约判断完整二十四位主有效数是否全一
    round_carry_comb = {round_prefix16_comb & {22{round_increment_comb}}, round_increment_comb}; // 并行生成条件加一进入二十三位小数字段的进位
    rounded_fraction_comb = round_main_comb[22:0] ^ round_carry_comb; // 使用异或合并原始小数位和并行进位得到舍入小数字段
    round_overflow_comb = round_increment_comb && round_all_ones_comb; // 全部主有效数位为一且需要加一时产生舍入进位
end // 结束二十四位并行前缀条件增量器

always_comb begin // 使用边界译码完成舍入后指数范围判定和FP32偏置转换
    exponent_at_or_below_minus127_comb = exponent_i[10] && ((&exponent_i[9:7]) == 1'b0 || (|exponent_i[6:1]) == 1'b0); // 译码全部不大于负一百二十七的十一位补码指数
    exponent_minus127_comb = exponent_i[10] && (&exponent_i[9:7]) && ((|exponent_i[6:1]) == 1'b0) && exponent_i[0]; // 单独识别可被舍入进位提升到负一百二十六的边界指数
    exponent_below_minus127_comb = exponent_at_or_below_minus127_comb && !exponent_minus127_comb; // 将不可被单次舍入进位修正的更小指数独立译码
    exponent_above127_comb = !exponent_i[10] && (|exponent_i[9:7]); // 正指数高位至少一个为一时数值已经大于正一百二十七
    exponent_plus127_comb = !exponent_i[10] && ((|exponent_i[9:7]) == 1'b0) && (&exponent_i[6:0]); // 单独识别可能因舍入进位溢出的正一百二十七边界
    biased_exponent_base_comb = exponent_i[7:0] + 8'd127; // 独立计算没有舍入最高进位时的FP32偏置指数
    biased_exponent_rounded_comb = {!exponent_i[7], exponent_i[6:0]}; // 利用加十六进制八零仅翻转最高位的性质计算舍入进位指数
    biased_exponent_comb = round_overflow_comb ? biased_exponent_rounded_comb : biased_exponent_base_comb; // 仅用末端选择器合并两条并行指数路径
end // 结束指数边界译码和偏置转换逻辑

always_comb begin // 将四种舍入方向的溢出策略归并为无穷或最大有限两种编码
    overflow_to_inf_comb = 1'b0; // 默认溢出结果钳位为同号最大有限数
    case (rounding_i) // 根据舍入方向选择溢出编码类别
        fp8_pkg::RNE: overflow_to_inf_comb = 1'b1; // 最接近偶数舍入的溢出结果选择无穷
        fp8_pkg::RTZ: overflow_to_inf_comb = 1'b0; // 向零舍入的溢出结果选择最大有限数
        fp8_pkg::RUP: overflow_to_inf_comb = !sign_i; // 向正无穷舍入仅让正数溢出到无穷
        fp8_pkg::RDN: overflow_to_inf_comb = sign_i; // 向负无穷舍入仅让负数溢出到无穷
        default: overflow_to_inf_comb = 1'b1; // 未知模式确定性回退到RNE无穷结果
    endcase // 结束溢出编码类别选择
    round_saturate_to_max_comb = exponent_plus127_comb && round_overflow_comb && !overflow_to_inf_comb; // 仅边界舍入且当前方向要求最大有限数时覆盖小数字段
end // 结束舍入方向相关溢出结果建立逻辑

always_comb begin // 按指数和小数字段分别处理边界以避免舍入进位驱动三十二位总选择器
    finite_exponent_comb = biased_exponent_comb; // 默认选择普通范围内舍入后的FP32偏置指数
    finite_fraction_comb = rounded_fraction_comb | {23{round_saturate_to_max_comb}}; // 边界定向溢出时将舍入产生的全零小数恢复为最大有限数全一小数
    if (zero_i || exponent_below_minus127_comb) begin // 精确零或无法由一次舍入进位修正的下溢结果输出同号零
        finite_exponent_comb = 8'h00; // 清零偏置指数域
        finite_fraction_comb = 23'h000000; // 清零小数字段
    end else if (exponent_minus127_comb) begin // 单独处理仅可能舍入到最小正规数的负一百二十七边界
        finite_exponent_comb = {7'b0000000, round_overflow_comb}; // 舍入最高进位直接成为最小正规数的偏置指数最低位
        finite_fraction_comb = 23'h000000; // 该边界无进位为零且有进位为精确一点零
    end else if (exponent_above127_comb) begin // 输入指数已经越过FP32最大有限范围时直接选择溢出编码字段
        finite_exponent_comb = overflow_to_inf_comb ? 8'hff : 8'hfe; // 根据舍入方向选择无穷或最大有限指数域
        finite_fraction_comb = overflow_to_inf_comb ? 23'h000000 : 23'h7fffff; // 根据舍入方向选择无穷或最大有限小数字段
    end else if (exponent_plus127_comb) begin // 正一百二十七边界仅需在偏置指数最低位处理无穷结果
        finite_exponent_comb = {7'h7f, round_overflow_comb && overflow_to_inf_comb}; // 无溢出或饱和时保持FE而无穷时生成FF
    end // 结束有限结果字段级零、下溢和溢出选择
    finite_result_comb = {sign_i, finite_exponent_comb, finite_fraction_comb}; // 连接字段级选择结果形成完整IEEE FP32编码
end // 结束IEEE FP32有限结果封装逻辑

always_comb begin // 在输出寄存器前选择特殊旁路或普通算术结果
    result_o = finite_result_comb; // 默认采用有限乘加路径舍入封装结果
    if (special_valid_i) begin // 特殊值路径已经确定完整结果时覆盖普通数据通路
        if (FTZ && (special_result_i[30:23] == 8'h00) && (special_result_i[22:0] != 23'h000000)) begin // FTZ模式仅刷新零乘积旁路出的FP32非规格ACC
            result_o = {special_result_i[31], 31'h00000000}; // 保留旁路结果符号并将非规格数刷新为零
        end else begin // 完整模式或非Subnormal特殊结果保持原始旁路编码
            result_o = special_result_i; // 选择流水对齐后的canonical NaN、无穷、零或ACC旁路结果
        end // 结束FTZ旁路非规格结果选择
    end // 结束特殊结果优先选择
end // 结束最终FP32结果选择逻辑

endmodule // 结束fp32_round_pack组合模块
