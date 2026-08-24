`timescale 1ns/1ps // 定义FP8公共包关联设计的仿真时间单位与时间精度

package fp8_pkg; // 定义FP32辅助流水线与精确归约的公共类型

typedef enum logic [1:0] { // 定义后续FP8量化与封装共用的舍入模式枚举
    RNE = 2'b00, // 选择最接近且中点取偶舍入模式
    RTZ = 2'b01, // 选择向零截断舍入模式
    RUP = 2'b10, // 选择向正无穷方向舍入模式
    RDN = 2'b11 // 选择向负无穷方向舍入模式
} fp8_rounding_e; // 结束FP8舍入模式枚举定义

typedef enum logic [1:0] { // 定义四输入归约流水线传递的紧凑特殊结果状态
    FP8_REDUCE_NORMAL = 2'b00, // 标识结果应由普通有限数归约与舍入路径产生
    FP8_REDUCE_NAN = 2'b01, // 标识结果应旁路为统一FP32 canonical NaN
    FP8_REDUCE_POS_INF = 2'b10, // 标识结果应旁路为FP32正无穷
    FP8_REDUCE_NEG_INF = 2'b11 // 标识结果应旁路为FP32负无穷
} fp8_reduce_special_e; // 结束归约流水线特殊结果状态枚举定义

typedef enum logic [1:0] { // 定义精确和为零时用于恢复IEEE零符号的紧凑状态
    FP8_ZERO_SIGN_ROUNDING = 2'b00, // 标识抵消或混合符号零并按当前舍入模式选择符号
    FP8_ZERO_SIGN_POSITIVE = 2'b01, // 标识全部输入均为正零并强制输出正零
    FP8_ZERO_SIGN_NEGATIVE = 2'b10, // 标识全部输入均为负零并强制输出负零
    FP8_ZERO_SIGN_RESERVED = 2'b11 // 保留编码并按舍入模式处理以提供确定的容错行为
} fp8_reduce_zero_sign_e; // 结束归约流水线零符号状态枚举定义

typedef struct packed { // 定义FP8解包后供乘加数据通路使用的统一结构
    logic              sign; // 保存原始FP8数值的符号位
    logic signed [7:0] exponent; // 保存正规化有限数的无偏有符号指数
    logic        [3:0] significand; // 保存按一点三小数位对齐的正规化有效数
    logic              is_zero; // 标识当前解码结果为正零或负零
    logic              is_subnormal; // 标识当前解码结果来自非规格数
    logic              is_normal; // 标识当前解码结果为普通规格化有限数
    logic              is_inf; // 标识当前解码结果为正无穷或负无穷
    logic              is_nan; // 标识当前解码结果为非数
} fp8_decoded_t; // 结束FP8统一解码结果结构定义

typedef struct packed { // 定义与独立尾数数据通路并行推进的FP8乘法元数据结构
    logic              sign; // 保存FP8操作数符号位以供流水乘积符号计算
    logic signed [7:0] exponent; // 保存FP8操作数无偏指数以供流水指数相加
    logic              is_zero; // 保存FP8操作数有符号零分类
    logic              is_subnormal; // 保存FP8操作数非规格有限数分类
    logic              is_normal; // 保存FP8操作数规格化有限数分类
    logic              is_inf; // 保存FP8操作数有符号无穷分类
    logic              is_nan; // 保存FP8操作数NaN分类
} fp8_mul_metadata_t; // 结束FP8乘法并行流水元数据结构定义

typedef struct packed { // 定义FP8乘法在规格化和舍入之前的内部精确乘积结构
    logic              sign; // 保存两个FP8操作数符号异或得到的乘积符号
    logic signed [8:0] exponent; // 保存两个无偏指数相加得到的精确乘积指数
    logic        [7:0] significand; // 保存两个统一Q1.3有效数相乘得到的Q2.6原始尾数
    logic              is_zero; // 标识精确乘积为正零或负零
    logic              is_inf; // 标识精确乘积为正无穷或负无穷
    logic              is_nan; // 标识精确乘积为NaN或无穷乘零的无效结果
} fp8_product_t; // 结束FP8内部精确乘积结构定义

typedef struct packed { // 定义IEEE FP32解包后供乘加对阶使用的统一结构
    logic               sign; // 保存原始IEEE FP32编码的符号位
    logic signed [9:0]  exponent; // 保存规格化有限数的无偏有符号指数
    logic        [23:0] significand; // 保存包含隐藏位的一点二十三格式有效数
    logic               is_zero; // 标识当前解码结果为正零或负零
    logic               is_subnormal; // 标识当前解码结果来自FP32非规格数
    logic               is_normal; // 标识当前解码结果为普通FP32规格化有限数
    logic               is_inf; // 标识当前解码结果为正无穷或负无穷
    logic               is_nan; // 标识当前解码结果为quiet或signaling NaN
} fp32_decoded_t; // 结束IEEE FP32统一解码结果结构定义

typedef struct packed { // 定义FP32字段分类与Subnormal规格化前的中间结构
    logic               sign; // 保存原始IEEE FP32编码的符号位
    logic signed [9:0]  exponent; // 保存分类阶段得到的基础无偏指数
    logic        [23:0] significand; // 保存Normal含隐藏位或Subnormal不含隐藏位的有效数
    logic               is_zero; // 标识当前FP32编码为正零或负零
    logic               is_subnormal; // 标识当前FP32编码为非规格数
    logic               is_normal; // 标识当前FP32编码为规格化有限数
    logic               is_inf; // 标识当前FP32编码为正无穷或负无穷
    logic               is_nan; // 标识当前FP32编码为NaN
} fp32_unpacked_t; // 结束FP32解包中间结构定义

endpackage // 结束fp8_pkg公共类型与常量包
