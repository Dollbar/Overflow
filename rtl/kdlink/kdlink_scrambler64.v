module kdlink_scrambler64 ( // 定义单 PCS lane 的 64-bit 自同步扰码器
    input wire clk_i, // 接收 PCS 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire valid_i, // 接收一个 64-bit data block 有效位
    input wire [63:0] data_i, // 接收低位优先的 data block
    output reg valid_o, // 输出注册化扰码 block 有效位
    output reg [63:0] data_o // 输出注册化扰码数据
); // 结束端口声明
    reg [57:0] state_q; // 保存 x^58+x^39+1 自同步扰码状态
    reg [57:0] state_d; // 保存组合展开后的下一扰码状态
    reg [63:0] scrambled_d; // 保存组合展开后的扰码结果
    integer bit_index; // 提供六十四位展开索引
    always @(*) begin // 并行展开六十四次扰码递推
        state_d = state_q; // 从当前扰码状态开始
        scrambled_d = 64'd0; // 默认扰码结果为零
        for (bit_index = 0; bit_index < 64; bit_index = bit_index + 1) begin // 按低位优先递推每个数据 bit
            scrambled_d[bit_index] = data_i[bit_index] ^ state_d[38] ^ state_d[57]; // 应用 x^39 和 x^58 feedback tap
            state_d = {state_d[56:0], scrambled_d[bit_index]}; // 将已发送扰码 bit 移入自同步状态
        end // 结束六十四位递推
    end // 结束扰码组合展开
    always @(posedge clk_i or negedge rst_n_i) begin // 注册扰码结果和状态
        if (!rst_n_i) begin // 检测复位有效
            state_q <= {58{1'b1}}; // 使用全一状态初始化扰码器
            valid_o <= 1'b0; // 清除输出有效位
            data_o <= 64'd0; // 清零输出数据
        end else begin // 处理正常扰码传输
            valid_o <= valid_i; // 注册输入有效位
            if (valid_i) begin // 仅在 data block 有效时推进状态
                state_q <= state_d; // 提交六十四位扰码后状态
                data_o <= scrambled_d; // 注册扰码结果
            end // 结束有效 data block 处理
        end // 结束正常扰码传输
    end // 结束扰码状态注册
endmodule // 结束单 lane 扰码器
