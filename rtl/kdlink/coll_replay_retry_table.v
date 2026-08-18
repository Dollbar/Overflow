module coll_replay_retry_table #( // 定义每 replay entry 七次重试限幅表
    parameter ENTRIES = 8, parameter INDEX_WIDTH = 3 // 配置 replay entry 数量和索引宽度
) ( // 开始端口声明
    input wire clk_i, input wire rst_n_i, // 接收 link core 时钟和低有效异步复位
    input wire reset_valid_i, input wire [INDEX_WIDTH-1:0] reset_index_i, // 接收新 packet entry retry 清零事件
    input wire request_valid_i, input wire [INDEX_WIDTH-1:0] request_index_i, // 接收匹配 NACK retry 请求
    output wire request_allowed_o, output wire request_exhausted_o, output wire [2:0] request_count_o // 输出当前 retry 许可上限和计数
); // 结束端口声明
    reg [2:0] retry_count_q [0:ENTRIES-1]; // 保存每 entry 零至七次已启动 replay 数量
    integer entry_index; // 提供固定 entry 复位索引
    assign request_count_o = retry_count_q[request_index_i]; // 输出当前请求 entry 已使用次数
    assign request_allowed_o = request_valid_i && (retry_count_q[request_index_i] < 3'd7); // 七次以内允许启动 replay
    assign request_exhausted_o = request_valid_i && (retry_count_q[request_index_i] == 3'd7); // 第八次请求报告 exhausted
    always @(posedge clk_i or negedge rst_n_i) begin // 更新每 entry retry 计数
        if (!rst_n_i) begin // 检测复位有效
            for (entry_index = 0; entry_index < ENTRIES; entry_index = entry_index + 1) retry_count_q[entry_index] <= 3'd0; // 清零全部 retry 计数
        end else begin // 处理正常 retry 更新
            if (reset_valid_i) retry_count_q[reset_index_i] <= 3'd0; // 新 packet 占用 entry 时清零历史 retry
            if (request_allowed_o) retry_count_q[request_index_i] <= retry_count_q[request_index_i] + 1'b1; // 仅允许的请求增加计数且在七饱和
        end // 结束 retry 更新选择
    end // 结束 retry 计数时序逻辑
endmodule // 结束 replay retry table
