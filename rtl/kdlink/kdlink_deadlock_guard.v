module kdlink_deadlock_guard ( // 定义 adaptive 至 escape 的单向无死锁转换检查器
    input wire [2:0] current_plane_i, // 接收当前虚网络所属平面
    input wire [2:0] next_plane_i, // 接收下一跳申请平面
    input wire [2:0] current_escape_rank_i, // 接收当前 escape 依赖等级
    input wire [2:0] next_escape_rank_i, // 接收下一跳 escape 依赖等级
    output wire transition_allowed_o, // 输出平面与等级转换满足无环合同状态
    output wire escape_monotonic_o // 输出 escape 等级严格递增状态
); // 结束无死锁转换检查器端口声明
    assign escape_monotonic_o = next_escape_rank_i > current_escape_rank_i; // escape 通道依赖只能从根向 leaf 严格递增
    assign transition_allowed_o = (current_plane_i == 3'd0) ? ((next_plane_i == 3'd0) && escape_monotonic_o) : ((next_plane_i == current_plane_i) || ((next_plane_i == 3'd0) && escape_monotonic_o)); // adaptive 可保持本平面或单向进入 escape 而 escape 永不返回 adaptive
endmodule // 结束 kdlink_deadlock_guard
