module kdlink_pcs_deskew10 ( // 定义十 lane 同时钟弹性 deskew FIFO
    input wire clk_i, // 接收 PCS 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [9:0] lane_valid_i, // 接收十 lane 独立 block 有效位
    input wire [659:0] lane_blocks_i, // 接收十个 66-bit lane block
    output wire blocks_valid_o, // 输出十 lane 已对齐共同有效位
    output wire [659:0] blocks_o, // 输出十个已对齐 66-bit block
    output reg overflow_o // 指示任一 lane skew 超过八周期
); // 结束端口声明
    reg [65:0] lane_mem_q [0:79]; // 保存十 lane 各八个 block
    reg [2:0] read_ptr_q [0:9]; // 保存每 lane deskew FIFO 读指针
    reg [2:0] write_ptr_q [0:9]; // 保存每 lane deskew FIFO 写指针
    reg [3:0] count_q [0:9]; // 保存每 lane deskew FIFO occupancy
    /* verilator lint_off WIDTHEXPAND */ // 固定八深度数组索引将三位指针扩展到 integer 地址
    wire [9:0] lane_nonempty; // 标记各 lane deskew FIFO 非空
    wire pop_all; // 标记十 lane 同拍弹出
    integer lane_index; // 提供十 lane 状态更新索引
    assign blocks_valid_o = &lane_nonempty; // 全部 lane 非空时形成对齐 block group
    assign pop_all = blocks_valid_o; // 无下游 backpressure 时每拍弹出完整 block group
    genvar deskew_index; // 提供 deskew lane 生成索引
    generate // 连接十 lane deskew FIFO 队首
        for (deskew_index = 0; deskew_index < 10; deskew_index = deskew_index + 1) begin : g_deskew_output // 生成单 lane deskew 输出
            assign lane_nonempty[deskew_index] = count_q[deskew_index] != 4'd0; // occupancy 非零时标记 lane 非空
            assign blocks_o[deskew_index*66 +: 66] = lane_mem_q[deskew_index*8 + read_ptr_q[deskew_index]]; // 输出本 lane 队首 block
        end // 结束单 lane 输出生成
    endgenerate // 结束 deskew 输出连接
    always @(posedge clk_i or negedge rst_n_i) begin // 更新十 lane deskew FIFO
        if (!rst_n_i) begin // 检测复位有效
            overflow_o <= 1'b0; // 清除 deskew overflow
            for (lane_index = 0; lane_index < 10; lane_index = lane_index + 1) begin // 清零全部 lane FIFO 状态
                read_ptr_q[lane_index] <= 3'd0; // 清零 lane 读指针
                write_ptr_q[lane_index] <= 3'd0; // 清零 lane 写指针
                count_q[lane_index] <= 4'd0; // 清零 lane occupancy
            end // 结束 lane FIFO 状态清零
        end else begin // 处理正常 deskew 传输
            overflow_o <= 1'b0; // 默认本周期无 overflow
            for (lane_index = 0; lane_index < 10; lane_index = lane_index + 1) begin // 独立更新十 lane FIFO
                case ({lane_valid_i[lane_index] && ((count_q[lane_index] < 4'd8) || pop_all), pop_all}) // 按本 lane push 和共同 pop 更新状态
                    2'b10: begin // 仅 lane push
                        lane_mem_q[lane_index*8 + write_ptr_q[lane_index]] <= lane_blocks_i[lane_index*66 +: 66]; // 写入 lane block
                        write_ptr_q[lane_index] <= write_ptr_q[lane_index] + 3'd1; // 推进 lane 写指针
                        count_q[lane_index] <= count_q[lane_index] + 4'd1; // 增加 lane occupancy
                    end // 结束仅 push 处理
                    2'b01: begin // 仅共同 pop
                        read_ptr_q[lane_index] <= read_ptr_q[lane_index] + 3'd1; // 推进 lane 读指针
                        count_q[lane_index] <= count_q[lane_index] - 4'd1; // 减少 lane occupancy
                    end // 结束仅 pop 处理
                    2'b11: begin // 同拍 lane push 和共同 pop
                        lane_mem_q[lane_index*8 + write_ptr_q[lane_index]] <= lane_blocks_i[lane_index*66 +: 66]; // 写入新的 lane block
                        write_ptr_q[lane_index] <= write_ptr_q[lane_index] + 3'd1; // 推进 lane 写指针
                        read_ptr_q[lane_index] <= read_ptr_q[lane_index] + 3'd1; // 推进 lane 读指针
                    end // 结束同拍 push/pop
                    default: begin // 处理 lane 空闲
                        count_q[lane_index] <= count_q[lane_index]; // 保持 lane occupancy
                    end // 结束 lane 空闲
                endcase // 结束 lane FIFO 更新
                if (lane_valid_i[lane_index] && (count_q[lane_index] >= 4'd8) && !pop_all) overflow_o <= 1'b1; // 报告超过八周期的 lane skew
            end // 结束十 lane FIFO 更新
        end // 结束正常 deskew 传输
    end // 结束 deskew FIFO 状态更新
    /* verilator lint_on WIDTHEXPAND */ // 恢复 deskew 数组索引宽度检查
endmodule // 结束十 lane deskew FIFO
