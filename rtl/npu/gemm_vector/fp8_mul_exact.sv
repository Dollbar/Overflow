`timescale 1ns/1ps // 定义FP8精确乘法器仿真时间单位与时间精度

module fp8_mul_exact ( // 定义规格化与舍入之前的一级流水FP8精确乘法器
    input  logic                    clk_i, // 输入FP8精确乘法一级流水工作时钟
    input  logic                    rst_i, // 输入同步高有效复位信号
    input  logic                    clear_i, // 输入同步高有效流水线清空信号
    input  logic                    valid_i, // 标识当前两个解码操作数有效
    input  fp8_pkg::fp8_decoded_t a_i, // 输入第一个已经完成分类和规格化的FP8操作数
    input  fp8_pkg::fp8_decoded_t b_i, // 输入第二个已经完成分类和规格化的FP8操作数
    output logic                    valid_o, // 标识当前内部精确乘积对应有效输入事务
    output fp8_pkg::fp8_product_t product_o // 输出未规格化且未舍入的内部精确乘积
); // 结束FP8精确乘法器端口声明

logic a_is_finite_nonzero_comb; // 标识当前第一个操作数为Normal或已规格化的Subnormal
logic b_is_finite_nonzero_comb; // 标识当前第二个操作数为Normal或已规格化的Subnormal
logic multiply_invalid_comb; // 标识当前无穷乘零形成IEEE无效操作和NaN结果
logic [7:0] significand_product_comb; // 接收四位无符号Booth Radix-4组合乘法器生成的精确Q2.6尾数
fp8_pkg::fp8_product_t product_comb; // 保存输入侧完整计算后的未规格化精确乘积
fp8_pkg::fp8_product_t product_s1; // 保存一级寄存后的完整未规格化精确乘积

booth_radix4_u4 u_significand_multiplier ( // 例化FP8统一四位有效数专用纯组合Radix-4乘法器
    .a_i       (a_i.significand), // 连接第一个统一Q1.3有效数
    .b_i       (b_i.significand), // 连接第二个统一Q1.3有效数
    .product_o (significand_product_comb) // 接收八位Q2.6组合精确尾数乘积
); // 结束FP8有效数Radix-4乘法器实例端口映射

always_comb begin // 在一级输入侧建立普通有限数和无穷乘零的分类条件
    a_is_finite_nonzero_comb = a_i.is_normal || a_i.is_subnormal; // 合并当前第一个操作数的两种有限非零分类
    b_is_finite_nonzero_comb = b_i.is_normal || b_i.is_subnormal; // 合并当前第二个操作数的两种有限非零分类
    multiply_invalid_comb = (a_i.is_inf && b_i.is_zero) || (a_i.is_zero && b_i.is_inf); // 检测当前操作数形成的IEEE无穷乘零无效操作
end // 结束FP8精确乘法输入分类逻辑

always_comb begin // 在一级寄存器之前按IEEE特殊值优先级生成完整精确乘积结构
    product_comb = '0; // 默认清零指数、尾数和全部互斥分类标志
    product_comb.sign = a_i.sign ^ b_i.sign; // 对普通数、零和无穷统一计算当前操作数乘积符号
    if (a_i.is_nan || b_i.is_nan || multiply_invalid_comb) begin // 优先处理当前操作数的NaN传播和无穷乘零
        product_comb.is_nan = 1'b1; // 将无效乘法或NaN输入统一分类为canonical NaN路径
    end else if (a_i.is_inf || b_i.is_inf) begin // 处理至少一个有效无穷操作数的乘积
        product_comb.is_inf = 1'b1; // 输出由符号异或确定正负的无穷分类
    end else if (a_i.is_zero || b_i.is_zero) begin // 处理至少一个有符号零操作数的乘积
        product_comb.is_zero = 1'b1; // 输出由符号异或确定正负的零分类
    end else if (a_is_finite_nonzero_comb && b_is_finite_nonzero_comb) begin // 处理Normal与Subnormal任意组合的有限乘法
        product_comb.exponent = {a_i.exponent[7], a_i.exponent} + {b_i.exponent[7], b_i.exponent}; // 在九位有符号域精确相加两个当前无偏指数
        product_comb.significand = significand_product_comb; // 采用当前Booth组合网络的八位Q2.6精确尾数
    end else begin // 对不可能由fp8_unpack产生的空分类输入保持确定结果
        product_comb.is_nan = 1'b1; // 将非法内部解码状态防御性地送入canonical NaN路径
    end // 结束输入侧全部FP8乘法类别选择
end // 结束完整精确乘积组合生成逻辑

always_ff @(posedge clk_i) begin // 在时钟上升沿复位、清空或采样完整FP8精确乘积
    if (rst_i) begin // 同步复位优先于正常输入采样
        product_s1 <= '0; // 清零一级寄存的完整精确乘积
        valid_o <= 1'b0; // 丢弃复位时尚未输出的事务
    end else if (clear_i) begin // 同步清空仅中断有效状态以限制清空信号扇出
        valid_o <= 1'b0; // 丢弃清空周期输入和流水中的精确乘积
    end else begin // 正常周期推进一级有效状态并按有效条件采样数据
        valid_o <= valid_i; // 将当前输入有效状态推进到一级输出
        product_s1 <= product_comb; // 每拍采样组合乘积以移除数据保持反馈多路器并由valid_o限定事务资格
    end // 结束同步控制与正常流水推进分支
end // 结束FP8完整精确乘积一级流水寄存逻辑

always_comb begin // 将一级完整乘积寄存器直接驱动到模块输出
    product_o = product_s1; // 无效周期保持最近数据并仅由valid_o限定产品结构的事务资格
end // 结束一级寄存精确乘积输出逻辑

endmodule // 结束fp8_mul_exact一级流水精确乘法器模块
