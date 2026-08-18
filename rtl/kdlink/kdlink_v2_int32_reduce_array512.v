module kdlink_v2_int32_reduce_array512 ( // 定义五百一十二 bank 规则化 INT32 reduction 阵列
    input wire clk_i, // 接收 reduction 阵列工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [511:0] valid_i, // 接收每 bank reduction 有效位
    input wire [49151:0] header_i, // 接收每 bank 九十六位协议 header
    input wire [262143:0] local_i, // 接收每 bank 五百一十二位本地 operand
    input wire [262143:0] remote_i, // 接收每 bank 五百一十二位远端 operand
    output reg [511:0] valid_o, // 输出每 bank reduction 有效位
    output reg [49151:0] header_o, // 输出每 bank 对齐协议 header
    output reg [262143:0] result_o // 输出每 bank 十六 lane INT32 modulo SUM
); // 结束端口声明
    integer endpoint_index; // 提供五百一十二 bank 循环索引
    integer lane_index; // 提供每 bank 十六个 INT32 lane 循环索引
    always @(posedge clk_i or negedge rst_n_i) begin // 更新规则化单拍 reduction 阵列
        if (!rst_n_i) begin // 检测复位有效
            valid_o <= 512'd0; // 清除全部 reduction 有效位
            for (endpoint_index = 0; endpoint_index < 512; endpoint_index = endpoint_index + 1) begin // 清零全部 bank 输出状态
                header_o[endpoint_index*96 +: 96] <= 96'd0; // 清零当前 bank header
                result_o[endpoint_index*512 +: 512] <= 512'd0; // 清零当前 bank result
            end // 结束全部 bank 复位
        end else begin // 处理正常 reduction 阵列输入
            valid_o <= valid_i; // 注册全部 bank reduction 有效位
            header_o <= header_i; // 注册全部 bank header metadata
            for (endpoint_index = 0; endpoint_index < 512; endpoint_index = endpoint_index + 1) begin // 遍历全部 endpoint bank
                if (valid_i[endpoint_index]) begin // 仅对有效 bank 更新 result
                    for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 遍历当前 bank 十六个 INT32 lane
                        result_o[endpoint_index*512 + lane_index*32 +: 32] <= local_i[endpoint_index*512 + lane_index*32 +: 32] + remote_i[endpoint_index*512 + lane_index*32 +: 32]; // 执行逐 lane modulo SUM
                    end // 结束当前 bank lane reduction
                end // 结束当前有效 bank 更新
            end // 结束全部 endpoint bank reduction
        end // 结束正常 reduction 阵列处理
    end // 结束 reduction 阵列时序逻辑
endmodule // 结束五百一十二 bank reduction 阵列
