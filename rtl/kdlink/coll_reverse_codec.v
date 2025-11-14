`include "collective_defs.vh" // 引入 reverse control 字段编码
module coll_reverse_codec ( // 定义 reverse control word 构造和 CRC 检查流水
    input  wire clk_i, // 接收 link core 时钟
    input  wire rst_n_i, // 接收低有效异步复位
    input  wire tx_valid_i, // 接收待编码 reverse metadata 有效
    input  wire [3:0] message_type_i, // 接收 reverse 消息类型
    input  wire [1:0] vc_i, // 接收关联 forward VC
    input  wire [7:0] link_epoch_i, // 接收当前 link epoch
    input  wire [11:0] collective_id_i, // 接收 collective ID
    input  wire phase_i, // 接收 data phase
    input  wire [15:0] packet_seq_i, // 接收 packet sequence
    input  wire [6:0] credit_delta_i, // 接收本次 credit 增量
    input  wire [7:0] status_i, // 接收 ACK NACK 或 link 状态
    input  wire [15:0] credit_total_i, // 接收累计 credit 总数
    output wire tx_valid_o, // 指示编码 reverse word 有效
    output wire [95:0] tx_word_o, // 输出带 CRC reverse word
    input  wire rx_valid_i, // 接收待检查 reverse word 有效
    input  wire [95:0] rx_word_i, // 接收 reverse control word
    output wire rx_valid_o, // 指示检查完成 reverse word 有效
    output wire rx_crc_good_o, // 指示 reverse CRC 正确
    output wire [79:0] rx_body_o // 输出与 CRC 对齐的 reverse body
); // 结束端口声明
    reg [79:0] tx_body_d; // 保存组合构造的 reverse body
    reg [79:0] tx_body_q [0:5]; // 保存五级编码数据对齐流水
    reg [79:0] rx_body_q [0:5]; // 保存五级检查数据对齐流水
    reg [15:0] tx_crc_q [0:5]; // 保存五级 TX CRC 状态
    reg [15:0] rx_crc_q [0:5]; // 保存五级 RX CRC 状态
    reg [15:0] rx_expected_q [0:5]; // 保存五级接收 CRC 对齐副本
    reg tx_valid_q [0:5]; // 保存五级 TX 有效流水
    reg rx_valid_q [0:5]; // 保存五级 RX 有效流水
    always @(*) begin // 组合构造八十位 reverse body
        tx_body_d = 80'd0; // 默认清零 body 和保留位
        tx_body_d[3:0] = 4'd1; // 写入协议版本一
        tx_body_d[7:4] = message_type_i; // 写入 reverse 消息类型
        tx_body_d[9:8] = vc_i; // 写入关联 VC
        tx_body_d[17:10] = link_epoch_i; // 写入 link epoch
        tx_body_d[29:18] = collective_id_i; // 写入 collective ID
        tx_body_d[30] = phase_i; // 写入 data phase
        tx_body_d[46:31] = packet_seq_i; // 写入 packet sequence
        tx_body_d[53:47] = credit_delta_i; // 写入 credit 增量
        tx_body_d[61:54] = status_i; // 写入消息状态
        tx_body_d[63:62] = 2'd0; // 保持保留字段为零
        tx_body_d[79:64] = credit_total_i; // 写入累计 credit 总数
    end // 结束 reverse body 构造
    always @(posedge clk_i or negedge rst_n_i) begin // 锁存 reverse codec 输入级
        if (!rst_n_i) begin // 检测复位有效
            tx_body_q[0] <= 80'd0; // 清零 TX body 输入级
            rx_body_q[0] <= 80'd0; // 清零 RX body 输入级
            tx_crc_q[0] <= 16'hFFFF; // 初始化 TX CRC 状态
            rx_crc_q[0] <= 16'hFFFF; // 初始化 RX CRC 状态
            rx_expected_q[0] <= 16'd0; // 清零 RX 期望 CRC
            tx_valid_q[0] <= 1'b0; // 清除 TX 输入有效
            rx_valid_q[0] <= 1'b0; // 清除 RX 输入有效
        end else begin // 处理 codec 输入级正常运行
            tx_body_q[0] <= tx_body_d; // 锁存待编码 reverse body
            rx_body_q[0] <= rx_word_i[79:0]; // 锁存待检查 reverse body
            tx_crc_q[0] <= 16'hFFFF; // 为新 TX word 装载 CRC 初值
            rx_crc_q[0] <= 16'hFFFF; // 为新 RX word 装载 CRC 初值
            rx_expected_q[0] <= rx_word_i[95:80]; // 锁存接收 CRC 字段
            tx_valid_q[0] <= tx_valid_i; // 锁存 TX 有效
            rx_valid_q[0] <= rx_valid_i; // 锁存 RX 有效
        end // 结束 codec 输入级复位选择
    end // 结束 codec 输入级时序逻辑
    genvar stage_index; // 提供五级 reverse CRC 生成索引
    generate // 为每两个字节生成一级 reverse CRC 流水
        for (stage_index = 0; stage_index < 5; stage_index = stage_index + 1) begin : g_reverse_crc // 生成当前双字节 CRC 级
            wire [15:0] tx_crc_b0; // 保存 TX 首字节 CRC 结果
            wire [15:0] tx_crc_b1; // 保存 TX 次字节 CRC 结果
            wire [15:0] rx_crc_b0; // 保存 RX 首字节 CRC 结果
            wire [15:0] rx_crc_b1; // 保存 RX 次字节 CRC 结果
            coll_crc16_byte u_tx_b0 (.crc_i(tx_crc_q[stage_index]), .data_i(tx_body_q[stage_index][stage_index*16 +: 8]), .crc_o(tx_crc_b0)); // 更新 TX 首字节 CRC
            coll_crc16_byte u_tx_b1 (.crc_i(tx_crc_b0), .data_i(tx_body_q[stage_index][stage_index*16+8 +: 8]), .crc_o(tx_crc_b1)); // 更新 TX 次字节 CRC
            coll_crc16_byte u_rx_b0 (.crc_i(rx_crc_q[stage_index]), .data_i(rx_body_q[stage_index][stage_index*16 +: 8]), .crc_o(rx_crc_b0)); // 更新 RX 首字节 CRC
            coll_crc16_byte u_rx_b1 (.crc_i(rx_crc_b0), .data_i(rx_body_q[stage_index][stage_index*16+8 +: 8]), .crc_o(rx_crc_b1)); // 更新 RX 次字节 CRC
            always @(posedge clk_i or negedge rst_n_i) begin // 更新当前 reverse CRC 流水级
                if (!rst_n_i) begin // 检测复位有效
                    tx_body_q[stage_index+1] <= 80'd0; // 清零下一级 TX body
                    rx_body_q[stage_index+1] <= 80'd0; // 清零下一级 RX body
                    tx_crc_q[stage_index+1] <= 16'hFFFF; // 初始化下一级 TX CRC
                    rx_crc_q[stage_index+1] <= 16'hFFFF; // 初始化下一级 RX CRC
                    rx_expected_q[stage_index+1] <= 16'd0; // 清零下一级 RX 期望 CRC
                    tx_valid_q[stage_index+1] <= 1'b0; // 清除下一级 TX 有效
                    rx_valid_q[stage_index+1] <= 1'b0; // 清除下一级 RX 有效
                end else begin // 处理当前 reverse CRC 级正常运行
                    tx_body_q[stage_index+1] <= tx_body_q[stage_index]; // 传递 TX body 对齐副本
                    rx_body_q[stage_index+1] <= rx_body_q[stage_index]; // 传递 RX body 对齐副本
                    tx_crc_q[stage_index+1] <= tx_crc_b1; // 锁存 TX 双字节 CRC 结果
                    rx_crc_q[stage_index+1] <= rx_crc_b1; // 锁存 RX 双字节 CRC 结果
                    rx_expected_q[stage_index+1] <= rx_expected_q[stage_index]; // 传递 RX 期望 CRC
                    tx_valid_q[stage_index+1] <= tx_valid_q[stage_index]; // 传递 TX 有效
                    rx_valid_q[stage_index+1] <= rx_valid_q[stage_index]; // 传递 RX 有效
                end // 结束当前 reverse CRC 级复位选择
            end // 结束当前 reverse CRC 时序逻辑
        end // 结束当前 reverse CRC 级
    endgenerate // 结束 reverse CRC 流水生成
    assign tx_valid_o = tx_valid_q[5]; // 输出编码完成有效标志
    assign tx_word_o = {tx_crc_q[5], tx_body_q[5]}; // 拼接 reverse CRC 和 body
    assign rx_valid_o = rx_valid_q[5]; // 输出检查完成有效标志
    assign rx_crc_good_o = (rx_crc_q[5] == rx_expected_q[5]); // 比较重算和接收 reverse CRC
    assign rx_body_o = rx_body_q[5]; // 输出检查对齐后的 reverse body
endmodule // 结束 reverse control codec
