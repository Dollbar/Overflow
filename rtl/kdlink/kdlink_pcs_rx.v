module kdlink_pcs_rx ( // 定义单 slice 十 lane 64b/66b PCS 接收器
    input wire clk_i, // 接收 PCS 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [9:0] lane_valid_i, // 接收十 lane 独立 block 有效位
    input wire [659:0] lane_blocks_i, // 接收十个可能偏斜的 66-bit block
    output wire flit_valid_o, // 输出恢复后的 640-bit logical flit 有效位
    output wire [639:0] flit_o, // 输出恢复后的 640-bit logical flit
    output reg block_lock_o, // 指示连续合法 sync header 已建立 block lock
    output reg deskew_locked_o, // 指示已通过 alignment marker 建立 lane deskew
    output reg block_error_o, // 指示非法或混合 sync header
    output wire deskew_overflow_o // 指示 lane skew 超过八周期
); // 结束端口声明
    wire deskew_valid; // 保存 deskew 后共同 block group 有效位
    wire [659:0] deskew_blocks; // 保存 deskew 后十 lane block
    reg data_group_d; // 标记十 lane 全部为 data block
    reg control_group_d; // 标记十 lane 全部为 control block
    reg training_match_d; // 标记十 lane 全部匹配训练 pattern
    reg marker_match_d; // 标记十 lane 全部匹配同一 alignment marker
    reg [4:0] valid_header_count_q; // 累计建立 block lock 所需合法 header group
    reg [3:0] training_count_q; // 累计训练 control group
    wire [9:0] descrambled_valid; // 保存十 lane 解扰输出有效位
    wire [639:0] descrambled_data; // 保存十 lane 解扰数据
    integer lane_index; // 提供十 lane control 检查索引
    kdlink_pcs_deskew10 u_deskew ( // 实例化十 lane 弹性 deskew FIFO
        .clk_i(clk_i), .rst_n_i(rst_n_i), .lane_valid_i(lane_valid_i), .lane_blocks_i(lane_blocks_i), // 连接可能偏斜的 lane blocks
        .blocks_valid_o(deskew_valid), .blocks_o(deskew_blocks), .overflow_o(deskew_overflow_o) // 连接对齐 block group 和 overflow
    ); // 结束 deskew 实例
    always @(*) begin // 检查十 lane sync header 和 control pattern
        data_group_d = deskew_valid; // 默认有效 group 为 data 候选
        control_group_d = deskew_valid; // 默认有效 group 为 control 候选
        training_match_d = deskew_valid; // 默认有效 group 为训练候选
        marker_match_d = deskew_valid; // 默认有效 group 为 marker 候选
        for (lane_index = 0; lane_index < 10; lane_index = lane_index + 1) begin // 检查每个 lane block
            if (deskew_blocks[lane_index*66 +: 2] != 2'b01) data_group_d = 1'b0; // 任一 lane 非 01 时取消 data group
            if (deskew_blocks[lane_index*66 +: 2] != 2'b10) control_group_d = 1'b0; // 任一 lane 非 10 时取消 control group
            if (deskew_blocks[lane_index*66 + 18 +: 48] != 48'h4B44_4C32_5452 || deskew_blocks[lane_index*66 + 10 +: 8] != 8'd0 || deskew_blocks[lane_index*66 + 2 +: 8] != lane_index[7:0]) training_match_d = 1'b0; // 检查 training signature 和 lane identity
            if (deskew_blocks[lane_index*66 + 50 +: 16] != 16'hA11E || deskew_blocks[lane_index*66 + 2 +: 8] != lane_index[7:0] || deskew_blocks[lane_index*66 + 10 +: 16] != deskew_blocks[10 +: 16]) marker_match_d = 1'b0; // 检查 marker signature、lane identity 和共同 sequence
        end // 结束十 lane block 检查
        training_match_d = training_match_d && control_group_d; // 训练 pattern 只允许出现在 control group
        marker_match_d = marker_match_d && control_group_d; // alignment marker 只允许出现在 control group
    end // 结束 block group 检查
    genvar descrambler_index; // 提供十 lane 解扰器生成索引
    generate // 为十 lane 生成独立自同步解扰状态
        for (descrambler_index = 0; descrambler_index < 10; descrambler_index = descrambler_index + 1) begin : g_descrambler // 生成单 PCS lane 解扰器
            kdlink_descrambler64 u_descrambler ( // 实例化单 lane 解扰器
                .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(data_group_d && block_lock_o && deskew_locked_o), .data_i(deskew_blocks[descrambler_index*66 + 2 +: 64]), // 连接扰码 data block
                .valid_o(descrambled_valid[descrambler_index]), .data_o(descrambled_data[descrambler_index*64 +: 64]) // 连接恢复 data word
            ); // 结束单 lane 解扰器实例
        end // 结束十 lane 解扰器生成
    endgenerate // 结束解扰器生成
    assign flit_valid_o = &descrambled_valid; // 十 lane 同拍解扰完成时输出 logical flit
    assign flit_o = descrambled_data; // 按低 lane 优先重组 640-bit flit
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 block lock、training 和 deskew 状态
        if (!rst_n_i) begin // 检测复位有效
            block_lock_o <= 1'b0; // 清除 block lock
            deskew_locked_o <= 1'b0; // 清除 deskew lock
            block_error_o <= 1'b0; // 清除 block error
            valid_header_count_q <= 5'd0; // 清零合法 header 计数
            training_count_q <= 4'd0; // 清零训练 group 计数
        end else begin // 处理正常 PCS 接收状态
            block_error_o <= 1'b0; // 默认本周期无 block error
            if (deskew_valid) begin // 仅在完整 block group 到达时更新 lock
                if (data_group_d || control_group_d) begin // 检查十 lane sync header 一致合法
                    if (valid_header_count_q < 5'd16) valid_header_count_q <= valid_header_count_q + 5'd1; // 累计连续合法 header group
                    if (valid_header_count_q >= 5'd15) block_lock_o <= 1'b1; // 第十六组后建立 block lock
                end else begin // 处理非法或混合 sync header
                    valid_header_count_q <= 5'd0; // 清零连续合法 header 计数
                    training_count_q <= 4'd0; // 清零训练计数
                    block_lock_o <= 1'b0; // 丢失 block lock
                    deskew_locked_o <= 1'b0; // 非法 lane group 同时丢失 deskew lock
                    block_error_o <= 1'b1; // 报告 block error 脉冲
                end // 结束 sync header 合法性处理
                if (training_match_d) begin // 检查训练 control group
                    if (training_count_q < 4'd8) training_count_q <= training_count_q + 4'd1; // 累计训练 group
                end // 结束训练 group 处理
                if (marker_match_d && block_lock_o && (training_count_q >= 4'd8)) deskew_locked_o <= 1'b1; // 合法训练后由 marker 建立 deskew lock
            end // 结束完整 block group 处理
            if (deskew_overflow_o) begin // 检查 deskew FIFO overflow
                deskew_locked_o <= 1'b0; // overflow 后撤销 deskew lock
                block_error_o <= 1'b1; // 将 overflow 报告为 block error
            end // 结束 deskew overflow 处理
        end // 结束正常 PCS 状态
    end // 结束 PCS 接收状态更新
endmodule // 结束 PCS 接收器
