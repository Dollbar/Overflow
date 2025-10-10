`timescale 1ns/1ps // 定义四位无符号Booth Radix-4乘法器的仿真时间单位与时间精度

module booth_radix4_u4 ( // 定义供FP8有效数使用的四位无符号纯组合乘法器
    input  logic [3:0] a_i, // 输入四位无符号被乘数
    input  logic [3:0] b_i, // 输入四位无符号乘数
    output logic [7:0] product_o // 输出八位无符号精确乘积
); // 结束四位无符号Booth Radix-4乘法器端口声明

logic [2:0] booth_group_0; // 保存最低Radix-4重叠编码组b1、b0与附加零
logic [2:0] booth_group_1; // 保存中间Radix-4重叠编码组b3、b2与b1
logic [2:0] booth_group_2; // 保存无符号最高位补零形成的第三个编码组
logic [7:0] multiplicand_x1; // 保存零扩展到八位的一倍被乘数
logic [7:0] multiplicand_x2; // 保存零扩展到八位的二倍被乘数
logic [7:0] multiplicand_x1_shift2; // 保存权重为四的一倍被乘数
logic [7:0] multiplicand_x2_shift2; // 保存权重为四的二倍被乘数
logic [7:0] multiplicand_x1_shift4; // 保存无符号最高修正组使用的十六倍被乘数
logic [7:0] partial_product_0; // 保存最低编码组生成的八位二进制补码部分积
logic [7:0] partial_product_1; // 保存中间编码组生成的八位二进制补码部分积
logic [7:0] partial_product_2; // 保存最高无符号修正组生成的八位部分积
logic [7:0] partial_sum_01; // 保存前两个部分积的模二百五十六和

always_comb begin // 建立无符号扩展、重叠编码组与各组移位基数
    booth_group_0 = {b_i[1:0], 1'b0}; // 在乘数最低位右侧补零形成第零组
    booth_group_1 = b_i[3:1]; // 复用乘数相邻位形成权重为四的第一组
    booth_group_2 = {2'b00, b_i[3]}; // 在乘数最高位左侧补两个零消除无符号符号扩展
    multiplicand_x1 = {4'b0000, a_i}; // 将四位无符号被乘数零扩展到部分积宽度
    multiplicand_x2 = {3'b000, a_i, 1'b0}; // 左移被乘数一位建立二倍被乘数
    multiplicand_x1_shift2 = multiplicand_x1 << 2; // 左移两位建立第一组正一倍部分积基数
    multiplicand_x2_shift2 = multiplicand_x2 << 2; // 左移两位建立第一组正二倍部分积基数
    multiplicand_x1_shift4 = multiplicand_x1 << 4; // 左移四位建立最高无符号修正部分积
end // 结束Booth编码输入与部分积基数生成逻辑

always_comb begin // 按Modified Booth表生成最低权重部分积
    partial_product_0 = 8'h00; // 默认将未知或零倍编码映射为零部分积
    case (booth_group_0) // 将三位重叠编码译码为零、正负一倍或正负二倍
        3'b000, 3'b111: partial_product_0 = 8'h00; // 编码零和七选择零倍被乘数
        3'b001, 3'b010: partial_product_0 = multiplicand_x1; // 编码一和二选择正一倍被乘数
        3'b011: partial_product_0 = multiplicand_x2; // 编码三选择正二倍被乘数
        3'b100: partial_product_0 = (~multiplicand_x2) + 8'd1; // 编码四选择负二倍被乘数的八位补码
        3'b101, 3'b110: partial_product_0 = (~multiplicand_x1) + 8'd1; // 编码五和六选择负一倍被乘数的八位补码
        default: partial_product_0 = 8'h00; // 为四态仿真异常编码提供确定零输出
    endcase // 结束最低Radix-4编码组译码
end // 结束最低权重部分积生成逻辑

always_comb begin // 按Modified Booth表生成权重为四的中间部分积
    partial_product_1 = 8'h00; // 默认将未知或零倍编码映射为零部分积
    case (booth_group_1) // 将三位重叠编码译码为移位后的零、正负一倍或正负二倍
        3'b000, 3'b111: partial_product_1 = 8'h00; // 编码零和七选择零倍被乘数
        3'b001, 3'b010: partial_product_1 = multiplicand_x1_shift2; // 编码一和二选择正一倍被乘数再乘四
        3'b011: partial_product_1 = multiplicand_x2_shift2; // 编码三选择正二倍被乘数再乘四
        3'b100: partial_product_1 = (~multiplicand_x2_shift2) + 8'd1; // 编码四选择负二倍移位部分积的八位补码
        3'b101, 3'b110: partial_product_1 = (~multiplicand_x1_shift2) + 8'd1; // 编码五和六选择负一倍移位部分积的八位补码
        default: partial_product_1 = 8'h00; // 为四态仿真异常编码提供确定零输出
    endcase // 结束中间Radix-4编码组译码
end // 结束中间权重部分积生成逻辑

always_comb begin // 生成四位无符号乘数所需的最高修正部分积
    partial_product_2 = 8'h00; // 默认在乘数最高位为零时不加入修正量
    case (booth_group_2) // 译码最高位左侧补零得到的有限编码集合
        3'b000: partial_product_2 = 8'h00; // 乘数最高位为零时选择零倍被乘数
        3'b001: partial_product_2 = multiplicand_x1_shift4; // 乘数最高位为一时加入十六倍被乘数
        default: partial_product_2 = 8'h00; // 为理论不可达编码提供确定零输出
    endcase // 结束最高无符号修正组译码
end // 结束最高无符号修正部分积生成逻辑

always_comb begin // 使用八位补码模加法合并三个Radix-4部分积
    partial_sum_01 = partial_product_0 + partial_product_1; // 合并最低和中间部分积并保留八位结果
    product_o = partial_sum_01 + partial_product_2; // 加入最高无符号修正后形成精确四乘四乘积
end // 结束Booth Radix-4部分积求和逻辑

endmodule // 结束四位无符号Booth Radix-4纯组合乘法器模块
