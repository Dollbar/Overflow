module coll_int32_reduction ( // 定义十六 lane INT32 modulo reduction 流水
    input wire clk_i, input wire rst_n_i, input wire valid_i, // 接收 reduction 时钟复位和输入有效
    input wire [511:0] local_i, input wire [511:0] remote_i, // 接收十六 lane 本地和远端操作数
    input wire [63:0] byte_valid_i, // 接收尾 flit 字节有效掩码
    output wire valid_o, output wire [511:0] result_o, output wire [63:0] byte_valid_o // 输出对齐结果和 metadata
); // 结束端口声明
    reg valid_block_q; reg [63:0] byte_valid_block_q; reg [511:0] local_block_q; // 保存八位分块候选级 metadata
    reg [7:0] block0_sum_q [0:15]; reg block0_carry_q [0:15]; // 保存最低八位实际和及进位
    reg [7:0] block1_sum0_q [0:15]; reg [7:0] block1_sum1_q [0:15]; reg block1_carry0_q [0:15]; reg block1_carry1_q [0:15]; // 保存第二八位块候选
    reg [7:0] block2_sum0_q [0:15]; reg [7:0] block2_sum1_q [0:15]; reg block2_carry0_q [0:15]; reg block2_carry1_q [0:15]; // 保存第三八位块候选
    reg [7:0] block3_sum0_q [0:15]; reg [7:0] block3_sum1_q [0:15]; // 保存最高八位块候选
    reg [31:0] assembled_sum_d [0:15]; reg carry1_d [0:15]; reg carry2_d [0:15]; // 保存候选选择组合结果和中间进位
    reg valid_sum_q; reg [63:0] byte_valid_sum_q; reg [511:0] local_sum_q; reg [31:0] sum_q [0:15]; // 保存完整三十二位和及 metadata
    reg valid_q; reg [63:0] byte_valid_q; reg [511:0] result_q; // 保存最终输出级
    integer lane_index; // 提供静态十六 lane 索引
    assign valid_o = valid_q; assign result_o = result_q; assign byte_valid_o = byte_valid_q; // 展平输出寄存结果
    always @(*) begin // 组合选择四个八位块的 carry-select 候选
        for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 遍历十六个 INT32 lane
            assembled_sum_d[lane_index][7:0] = block0_sum_q[lane_index]; // 最低八位直接使用实际和
            if (block0_carry_q[lane_index]) begin assembled_sum_d[lane_index][15:8] = block1_sum1_q[lane_index]; carry1_d[lane_index] = block1_carry1_q[lane_index]; end
            else begin assembled_sum_d[lane_index][15:8] = block1_sum0_q[lane_index]; carry1_d[lane_index] = block1_carry0_q[lane_index]; end // 选择第二块候选
            if (carry1_d[lane_index]) begin assembled_sum_d[lane_index][23:16] = block2_sum1_q[lane_index]; carry2_d[lane_index] = block2_carry1_q[lane_index]; end
            else begin assembled_sum_d[lane_index][23:16] = block2_sum0_q[lane_index]; carry2_d[lane_index] = block2_carry0_q[lane_index]; end // 选择第三块候选
            if (carry2_d[lane_index]) assembled_sum_d[lane_index][31:24] = block3_sum1_q[lane_index]; else assembled_sum_d[lane_index][31:24] = block3_sum0_q[lane_index]; // 选择最高块候选且丢弃 modulo carry
        end // 结束全部 lane 候选选择
    end // 结束 carry-select 组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新三级八位分块 INT32 reduction 流水
        if (!rst_n_i) begin // 检测复位有效
            valid_block_q <= 1'b0; byte_valid_block_q <= 64'd0; local_block_q <= 512'd0; valid_sum_q <= 1'b0; byte_valid_sum_q <= 64'd0; local_sum_q <= 512'd0; // 清零前两级 metadata
            valid_q <= 1'b0; byte_valid_q <= 64'd0; result_q <= 512'd0; // 清零输出级
            for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 清零全部 lane 分块寄存器
                block0_sum_q[lane_index] <= 8'd0; block0_carry_q[lane_index] <= 1'b0;
                block1_sum0_q[lane_index] <= 8'd0; block1_sum1_q[lane_index] <= 8'd0; block1_carry0_q[lane_index] <= 1'b0; block1_carry1_q[lane_index] <= 1'b0;
                block2_sum0_q[lane_index] <= 8'd0; block2_sum1_q[lane_index] <= 8'd0; block2_carry0_q[lane_index] <= 1'b0; block2_carry1_q[lane_index] <= 1'b0;
                block3_sum0_q[lane_index] <= 8'd0; block3_sum1_q[lane_index] <= 8'd0; sum_q[lane_index] <= 32'd0;
            end // 结束全部 lane 复位
        end else begin // 处理 reduction 正常流水
            valid_block_q <= valid_i; byte_valid_block_q <= byte_valid_i; local_block_q <= local_i; // 锁存输入 metadata
            for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 并行形成每个八位块候选
                {block0_carry_q[lane_index], block0_sum_q[lane_index]} <= {1'b0, local_i[lane_index*32 +: 8]} + {1'b0, remote_i[lane_index*32 +: 8]};
                {block1_carry0_q[lane_index], block1_sum0_q[lane_index]} <= {1'b0, local_i[lane_index*32+8 +: 8]} + {1'b0, remote_i[lane_index*32+8 +: 8]};
                {block1_carry1_q[lane_index], block1_sum1_q[lane_index]} <= {1'b0, local_i[lane_index*32+8 +: 8]} + {1'b0, remote_i[lane_index*32+8 +: 8]} + 9'd1;
                {block2_carry0_q[lane_index], block2_sum0_q[lane_index]} <= {1'b0, local_i[lane_index*32+16 +: 8]} + {1'b0, remote_i[lane_index*32+16 +: 8]};
                {block2_carry1_q[lane_index], block2_sum1_q[lane_index]} <= {1'b0, local_i[lane_index*32+16 +: 8]} + {1'b0, remote_i[lane_index*32+16 +: 8]} + 9'd1;
                block3_sum0_q[lane_index] <= local_i[lane_index*32+24 +: 8] + remote_i[lane_index*32+24 +: 8];
                block3_sum1_q[lane_index] <= local_i[lane_index*32+24 +: 8] + remote_i[lane_index*32+24 +: 8] + 1'b1;
            end // 结束八位块候选形成
            valid_sum_q <= valid_block_q; byte_valid_sum_q <= byte_valid_block_q; local_sum_q <= local_block_q; // 前推完整和级 metadata
            for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) sum_q[lane_index] <= assembled_sum_d[lane_index]; // 锁存完整三十二位和
            valid_q <= valid_sum_q; byte_valid_q <= byte_valid_sum_q; // 前推最终输出 metadata
            for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 选择有效 lane reduction 或本地保持值
                if (&byte_valid_sum_q[lane_index*4 +: 4]) result_q[lane_index*32 +: 32] <= sum_q[lane_index];
                else result_q[lane_index*32 +: 32] <= local_sum_q[lane_index*32 +: 32];
            end // 结束最终 lane 选择
        end // 结束正常流水
    end // 结束 INT32 reduction 流水
endmodule // 结束 INT32 reduction 模块
