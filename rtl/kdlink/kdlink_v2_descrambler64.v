module kdlink_v2_descrambler64 ( // 定义单 PCS lane 的 64-bit 自同步解扰器
    input wire clk_i, // 接收 PCS 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire valid_i, // 接收一个扰码 data block 有效位
    input wire [63:0] data_i, // 接收低位优先的扰码 block
    output reg valid_o, // 输出注册化解扰 block 有效位
    output reg [63:0] data_o // 输出注册化解扰数据
); // 结束端口声明
    reg [57:0] state_q; // 保存最近五十八个接收扰码 bit
    reg [57:0] state_d; // 保存组合展开后的下一解扰状态
    reg [63:0] descrambled_d; // 保存组合展开后的解扰结果
    integer bit_index; // 提供六十四位展开索引
    always @(*) begin // 并行展开六十四次解扰递推
        state_d = state_q; // 从当前接收状态开始
        descrambled_d = 64'd0; // 默认解扰结果为零
        for (bit_index = 0; bit_index < 64; bit_index = bit_index + 1) begin // 按低位优先递推每个扰码 bit
            descrambled_d[bit_index] = data_i[bit_index] ^ state_d[38] ^ state_d[57]; // 使用历史扰码 bit 恢复原始数据
            state_d = {state_d[56:0], data_i[bit_index]}; // 将当前接收扰码 bit 移入自同步状态
        end // 结束六十四位递推
    end // 结束解扰组合展开
    always @(posedge clk_i or negedge rst_n_i) begin // 注册解扰结果和状态
        if (!rst_n_i) begin // 检测复位有效
            state_q <= {58{1'b1}}; // 使用与发送端一致的全一初始状态
            valid_o <= 1'b0; // 清除输出有效位
            data_o <= 64'd0; // 清零输出数据
        end else begin // 处理正常解扰传输
            valid_o <= valid_i; // 注册输入有效位
            if (valid_i) begin // 仅在 data block 有效时推进状态
                state_q <= state_d; // 提交六十四位接收后状态
                data_o <= descrambled_d; // 注册解扰结果
            end // 结束有效 data block 处理
        end // 结束正常解扰传输
    end // 结束解扰状态注册
endmodule // 结束单 lane 解扰器
