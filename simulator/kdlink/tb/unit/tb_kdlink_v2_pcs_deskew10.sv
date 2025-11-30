`timescale 1ns/1ps // 定义 PCS deskew 测试时间单位
module tb_kdlink_v2_pcs_deskew10; // 定义十 lane 固定偏斜恢复自校验测试
    localparam integer GROUPS = 64; // 固定待恢复 block group 数
    logic clk; // 生成一 GHz deskew 时钟
    logic rst_n; // 生成低有效复位
    logic [9:0] lane_valid_i; // 驱动十 lane 独立 valid
    logic [659:0] lane_blocks_i; // 驱动十 lane block
    wire blocks_valid_o; // 观察对齐 block group valid
    wire [659:0] blocks_o; // 观察对齐 blocks
    wire overflow_o; // 观察 deskew overflow
    integer channel_cycle; // 提供 skew channel 周期
    integer drive_lane; // 提供输入 lane 索引
    integer source_group; // 保存本 lane 当前 source group
    integer output_group; // 记录已恢复 group 数
    integer check_lane; // 提供输出 lane 索引
    integer bubbles; // 统计对齐流启动后的气泡
    logic output_started; // 标记对齐输出已经启动
    kdlink_v2_pcs_deskew10 u_dut ( // 实例化十 lane deskew FIFO
        .clk_i(clk), .rst_n_i(rst_n), .lane_valid_i(lane_valid_i), .lane_blocks_i(lane_blocks_i), // 连接偏斜 lane 输入
        .blocks_valid_o(blocks_valid_o), .blocks_o(blocks_o), .overflow_o(overflow_o) // 连接对齐 group 输出
    ); // 结束 deskew 实例
    initial begin // 生成一 GHz 时钟
        clk = 1'b0; // 初始化时钟为低
        forever #0.5 clk = ~clk; // 生成一纳秒周期
    end // 结束时钟生成
    always @(posedge clk or negedge rst_n) begin // 检查对齐 block group
        if (!rst_n) begin // 检测复位有效
            output_group = 0; // 清零输出 group 计数
            bubbles = 0; // 清零气泡计数
            output_started = 1'b0; // 清除输出启动标志
        end else if (blocks_valid_o) begin // 检查完整对齐 group
            output_started = 1'b1; // 标记对齐输出启动
            for (check_lane = 0; check_lane < 10; check_lane = check_lane + 1) begin // 检查十 lane group identity
                if (blocks_o[check_lane*66 + 2 +: 16] != output_group[15:0] || blocks_o[check_lane*66 + 18 +: 8] != check_lane[7:0]) $fatal(1, "deskew mismatch group=%0d lane=%0d data=%h", output_group, check_lane, blocks_o[check_lane*66 +: 66]); // 要求不同偏斜 lane 恢复同一 source group
            end // 结束十 lane identity 检查
            output_group = output_group + 1; // 累计恢复 group
        end else if (output_started && output_group < GROUPS) begin // 检查启动后的对齐流气泡
            bubbles = bubbles + 1; // 累计 deskew 气泡
        end // 结束对齐输出检查
    end // 结束 deskew scoreboard
    initial begin // 驱动十 lane 零到四周期固定偏斜
        rst_n = 1'b0; // 初始保持复位
        lane_valid_i = 10'd0; // 初始清除 lane valid
        lane_blocks_i = 660'd0; // 初始清零 lane blocks
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        for (channel_cycle = 0; channel_cycle < GROUPS + 5; channel_cycle = channel_cycle + 1) begin // 运行覆盖最大偏斜的 channel 周期
            @(negedge clk); // 在下降沿更新 lane 输入
            lane_valid_i = 10'd0; // 默认全部 lane 无效
            lane_blocks_i = 660'd0; // 默认全部 lane block 为零
            for (drive_lane = 0; drive_lane < 10; drive_lane = drive_lane + 1) begin // 为每 lane 应用零到四周期固定延迟
                source_group = channel_cycle - (drive_lane % 5); // 计算本 lane 当前到达的 source group
                if (source_group >= 0 && source_group < GROUPS) begin // 仅在 source group 有效范围内驱动 lane
                    lane_valid_i[drive_lane] = 1'b1; // 声明本 lane block 有效
                    lane_blocks_i[drive_lane*66 +: 2] = 2'b01; // 写入 data sync header
                    lane_blocks_i[drive_lane*66 + 2 +: 16] = source_group[15:0]; // 写入 source group identity
                    lane_blocks_i[drive_lane*66 + 18 +: 8] = drive_lane[7:0]; // 写入 lane identity
                end // 结束有效 source group 驱动
            end // 结束十 lane skew 构造
        end // 结束 channel 周期
        @(negedge clk); lane_valid_i = 10'd0; // 停止全部 lane 输入
        wait (output_group == GROUPS); // 等待全部 group 恢复
        repeat (2) @(posedge clk); #0.01; // 等待 deskew 状态稳定
        if (overflow_o || bubbles != 0) $fatal(1, "deskew performance failure overflow=%b bubbles=%0d", overflow_o, bubbles); // 要求四周期 skew 内无 overflow 和气泡
        $display("TB_KDLINK_V2_PCS_DESKEW10_PASS groups=%0d lanes=10 max_skew_cycles=4 bubbles=0 overflow=0", GROUPS); // 报告 deskew 验收结果
        $finish; // 结束测试
    end // 结束主测试流程
    initial begin // 设置仿真超时
        #500; // 等待最大测试时长
        $fatal(1, "KDLink-v2 PCS deskew timeout"); // 超时失败
    end // 结束超时保护
endmodule // 结束 deskew 测试
