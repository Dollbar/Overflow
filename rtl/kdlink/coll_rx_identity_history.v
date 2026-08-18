module coll_rx_identity_history #( // 定义参数化已提交 packet identity 去重窗口
    parameter ENTRIES = 16, parameter INDEX_WIDTH = 4 // 配置生产十六项窗口和环形索引宽度
) ( // 开始端口声明
    input wire clk_i, input wire rst_n_i, // 接收 link core 时钟和低有效异步复位
    input wire [11:0] query_collective_id_i, input wire query_phase_i, input wire [15:0] query_packet_seq_i, input wire [2:0] query_src_rank_i, input wire [7:0] query_epoch_i, // 接收待查询 packet identity
    output reg [3:0] query_match_group_o, // 输出每四项归并的 duplicate 命中位
    input wire commit_valid_i, input wire [11:0] commit_collective_id_i, input wire commit_phase_i, input wire [15:0] commit_packet_seq_i, input wire [2:0] commit_src_rank_i, input wire [7:0] commit_epoch_i // 接收仅在 atomic commit 完成时写入的 identity
); // 结束端口声明
    reg [ENTRIES-1:0] history_valid_q; // 保存全部 committed identity 有效位
    reg [11:0] history_collective_q [0:ENTRIES-1]; // 保存 committed collective ID
    reg history_phase_q [0:ENTRIES-1]; // 保存 committed phase
    reg [15:0] history_packet_seq_q [0:ENTRIES-1]; // 保存 committed packet sequence
    reg [2:0] history_src_rank_q [0:ENTRIES-1]; // 保存 committed hop source rank
    reg [7:0] history_epoch_q [0:ENTRIES-1]; // 保存 committed link epoch
    reg [INDEX_WIDTH-1:0] history_write_ptr_q; // 保存 committed history 环形写指针
    integer history_index; // 提供固定 history 扫描索引
    always @(*) begin // 并行检查完整 committed replay history
        query_match_group_o = 4'd0; // 默认四组均未命中
        for (history_index = 0; history_index < ENTRIES; history_index = history_index + 1) begin // 扫描全部 committed identity
            if (history_valid_q[history_index] && history_collective_q[history_index] == query_collective_id_i && history_phase_q[history_index] == query_phase_i && history_packet_seq_q[history_index] == query_packet_seq_i && history_src_rank_q[history_index] == query_src_rank_i && history_epoch_q[history_index] == query_epoch_i) query_match_group_o[history_index/4] = 1'b1; // 每四项归并一个同 epoch 同 source 命中结果
        end // 结束 committed identity 扫描
    end // 结束 duplicate 组合检查
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 committed identity 环形窗口
        if (!rst_n_i) begin // 检测复位有效
            history_valid_q <= {ENTRIES{1'b0}}; // 清除全部 history valid
            history_write_ptr_q <= {INDEX_WIDTH{1'b0}}; // 清零环形写指针
            for (history_index = 0; history_index < ENTRIES; history_index = history_index + 1) begin // 清零全部 identity entry
                history_collective_q[history_index] <= 12'd0; history_phase_q[history_index] <= 1'b0; history_packet_seq_q[history_index] <= 16'd0; // 清零 collective phase 和 sequence
                history_src_rank_q[history_index] <= 3'd0; history_epoch_q[history_index] <= 8'd0; // 清零 source 和 epoch
            end // 结束 identity entry 复位
        end else if (commit_valid_i) begin // 检查完整 atomic commit 已完成
            history_valid_q[history_write_ptr_q] <= 1'b1; // 标记当前 history entry 有效
            history_collective_q[history_write_ptr_q] <= commit_collective_id_i; history_phase_q[history_write_ptr_q] <= commit_phase_i; // 保存 collective 和 phase
            history_packet_seq_q[history_write_ptr_q] <= commit_packet_seq_i; history_src_rank_q[history_write_ptr_q] <= commit_src_rank_i; history_epoch_q[history_write_ptr_q] <= commit_epoch_i; // 保存 sequence source 和 epoch
            history_write_ptr_q <= history_write_ptr_q + 1'b1; // 推进十六项环形写指针
        end // 结束 atomic commit history 写入
    end // 结束 committed identity 窗口更新
endmodule // 结束 RX identity history
