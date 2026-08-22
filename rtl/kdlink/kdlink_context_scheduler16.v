module kdlink_context_scheduler16 ( // 定义十六 context packet-boundary scheduler
    input wire clk_i, // 接收 control 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire submit_valid_i, // 接收 descriptor 提交有效位
    output wire submit_ready_o, // 返回 descriptor 分配许可
    input wire [511:0] descriptor_i, // 接收 KDLink descriptor
    output reg allocate_valid_o, // 输出 context 分配完成脉冲
    output reg [3:0] allocate_index_o, // 输出已分配 context 索引
    input wire [15:0] blocked_i, // 接收各 context 临时阻塞状态
    output reg issue_valid_o, // 输出 packet-boundary issue 有效位
    input wire issue_ready_i, // 接收 packet-boundary issue 消费能力
    output reg [3:0] issue_index_o, // 输出被调度 context 索引
    output reg [511:0] issue_descriptor_o, // 输出被调度 context descriptor
    output reg [31:0] reservation_count_o, // 输出每个 context 在两级 issue 流水中的保留数量
    input wire complete_valid_i, // 接收 context 完成有效位
    input wire [3:0] complete_index_i, // 接收完成 context 索引
    output wire [15:0] active_o, // 输出 active context bitmap
    output reg descriptor_error_o, // 指示 descriptor 字段非法
    output reg duplicate_error_o // 指示 collective identity 重复
); // 结束端口声明
    reg [15:0] active_q; // 保存十六 context active bitmap
    reg [511:0] descriptor_q [0:15]; // 保存十六个已锁存 descriptor
    reg [1:0] group_rr_q; // 保存四个 context 组之间的 round-robin 起点
    reg [1:0] lane_rr_q [0:3]; // 保存每组四个 context 的 round-robin 起点
    reg select_valid_q; // 保存已注册 winner 选择有效位
    reg [3:0] select_index_q; // 保存已注册 winner context 索引
    /* verilator lint_off WIDTHEXPAND */ // 四位 round-robin 指针与 integer 扫描偏移按 modulo 十六截断
    reg free_valid_d; // 标记存在空闲 context
    reg [3:0] free_index_d; // 保存最低空闲 context 索引
    reg duplicate_d; // 标记 collective ID 与 active context 重复
    reg descriptor_valid_d; // 标记 descriptor 固定字段合法
    reg [3:0] group_valid_d; // 保存四组局部 winner 有效位
    reg [7:0] group_lane_d; // 保存四组局部 winner lane
    reg winner_valid_d; // 标记存在 runnable context winner
    reg [3:0] winner_index_d; // 保存 runnable context winner
    integer context_index; // 提供 context 扫描索引
    integer group_index; // 提供四个 context 组扫描索引
    integer lane_offset; // 提供组内 round-robin 扫描偏移
    integer group_offset; // 提供组间 round-robin 扫描偏移
    integer lane_candidate; // 保存组内候选 lane
    integer context_candidate; // 保存组内候选 context 索引
    integer group_candidate; // 保存组间候选索引
    wire output_ready; // 标记 issue 输出弹性级可以更新
    wire select_ready; // 标记 winner 选择弹性级可以更新
    assign active_o = active_q; // 输出 active context bitmap
    assign submit_ready_o = free_valid_d && descriptor_valid_d && !duplicate_d; // 仅合法且不重复 descriptor 可以分配
    assign output_ready = !issue_valid_o || issue_ready_i; // issue 输出为空或被消费时允许推进
    assign select_ready = !select_valid_q || output_ready; // winner 选择为空或将推进时允许新仲裁
    always @(*) begin // 独立统计两级 issue 流水对各 context 的输入保留量
        reservation_count_o = 32'd0; // 默认 issue 流水没有保留输入
        if (issue_valid_o) reservation_count_o[issue_index_o*2 +: 2] = 2'd1; // 统计输出级尚未消费的 context 输入
        if (select_valid_q) reservation_count_o[select_index_q*2 +: 2] = reservation_count_o[select_index_q*2 +: 2] + 2'd1; // 统计选择级尚未推进的 context 输入
    end // 结束 issue reservation 统计
    always @(*) begin // 检查 descriptor、空闲 context 和 runnable winner
        free_valid_d = 1'b0; // 默认无空闲 context
        free_index_d = 4'd0; // 默认空闲索引为零
        duplicate_d = 1'b0; // 默认 collective identity 不重复
        descriptor_valid_d = 1'b1; // 默认 descriptor 合法
        group_valid_d = 4'd0; // 默认全部 context 组无局部 winner
        group_lane_d = 8'd0; // 默认全部局部 winner lane 为零
        winner_valid_d = 1'b0; // 默认无 runnable winner
        winner_index_d = 4'd0; // 默认 winner 索引为零
        if (descriptor_i[2:0] > 3'd5 || descriptor_i[15:10] != 6'd32 || descriptor_i[24:21] != 4'd2 || descriptor_i[56:49] == 8'd0 || descriptor_i[58:57] == 2'd0 || descriptor_i[63:62] != 2'd0 || descriptor_i[223:192] == 32'd0 || descriptor_i[511:416] != 96'd0) descriptor_valid_d = 1'b0; // 验证 opcode、节点数、版本、长度、资源 mask 和 reserved
        for (context_index = 0; context_index < 16; context_index = context_index + 1) begin // 扫描全部 context 状态
            if (!free_valid_d && !active_q[context_index]) begin // 捕获最低空闲 context
                free_valid_d = 1'b1; // 标记存在空闲 context
                free_index_d = context_index[3:0]; // 保存空闲 context 索引
            end // 结束空闲 context 捕获
            if (active_q[context_index] && (descriptor_q[context_index][36:25] == descriptor_i[36:25])) duplicate_d = 1'b1; // 检查 active collective ID 重复
        end // 结束 context 状态扫描
        for (group_index = 0; group_index < 4; group_index = group_index + 1) begin // 并行计算四个四路局部 winner
            for (lane_offset = 0; lane_offset < 4; lane_offset = lane_offset + 1) begin // 从本组 round-robin 起点扫描四个 context
                lane_candidate = (lane_rr_q[group_index] + lane_offset) & 3; // 形成组内 modulo 四候选
                context_candidate = group_index*4 + lane_candidate; // 形成完整 context 候选索引
                if (!group_valid_d[group_index] && active_q[context_candidate] && !blocked_i[context_candidate] && !(complete_valid_i && (complete_index_i == context_candidate[3:0]))) begin // 捕获本组首个未完成 runnable context
                    group_valid_d[group_index] = 1'b1; // 标记本组存在局部 winner
                    group_lane_d[group_index*2 +: 2] = lane_candidate[1:0]; // 保存本组 winner lane
                end // 结束本组 winner 捕获
            end // 结束组内 context 扫描
        end // 结束四组局部 winner 计算
        for (group_offset = 0; group_offset < 4; group_offset = group_offset + 1) begin // 从组 round-robin 起点扫描四组
            group_candidate = (group_rr_q + group_offset) & 3; // 形成 modulo 四组候选
            if (!winner_valid_d && group_valid_d[group_candidate]) begin // 捕获首个存在局部 winner 的组
                winner_valid_d = 1'b1; // 标记最终 winner 有效
                winner_index_d = {group_candidate[1:0], group_lane_d[group_candidate*2 +: 2]}; // 合成四位 context winner 索引
            end // 结束最终 winner 捕获
        end // 结束组间 winner 扫描
    end // 结束 scheduler 组合检查
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 context table 和 packet-boundary issue
        if (!rst_n_i) begin // 检测复位有效
            active_q <= 16'd0; // 清零 active context bitmap
            group_rr_q <= 2'd0; // 清零 context 组 round-robin 起点
            select_valid_q <= 1'b0; // 清除 winner 选择有效位
            select_index_q <= 4'd0; // 清零 winner 选择索引
            allocate_valid_o <= 1'b0; // 清除分配完成脉冲
            allocate_index_o <= 4'd0; // 清零分配索引
            issue_valid_o <= 1'b0; // 清除 issue 有效位
            issue_index_o <= 4'd0; // 清零 issue 索引
            issue_descriptor_o <= 512'd0; // 清零 issue descriptor
            descriptor_error_o <= 1'b0; // 清除 descriptor error
            duplicate_error_o <= 1'b0; // 清除 duplicate error
            for (group_index = 0; group_index < 4; group_index = group_index + 1) lane_rr_q[group_index] <= 2'd0; // 清零全部组内 round-robin 起点
        end else begin // 处理正常 context 调度
            allocate_valid_o <= 1'b0; // 默认本周期无分配完成
            descriptor_error_o <= submit_valid_i && !descriptor_valid_d; // 报告非法 descriptor 脉冲
            duplicate_error_o <= submit_valid_i && descriptor_valid_d && duplicate_d; // 仅合法 descriptor 报告重复 collective ID 脉冲
            if (submit_valid_i && submit_ready_o) begin // 接受一个合法 descriptor
                active_q[free_index_d] <= 1'b1; // 标记新 context active
                descriptor_q[free_index_d] <= descriptor_i; // 锁存 descriptor 全部字段
                allocate_valid_o <= 1'b1; // 报告分配完成
                allocate_index_o <= free_index_d; // 输出分配 context 索引
            end // 结束 descriptor 分配
            if (complete_valid_i) active_q[complete_index_i] <= 1'b0; // 完成时释放指定 context
            if (output_ready) begin // issue 输出寄存级空闲或本周期被消费
                issue_valid_o <= select_valid_q; // 将已注册 winner 推进到 issue 输出
                if (select_valid_q) begin // 检查存在已注册 winner
                    issue_index_o <= select_index_q; // 输出已注册 context 索引
                    issue_descriptor_o <= descriptor_q[select_index_q]; // 用注册索引读取锁存 descriptor
                end // 结束已注册 winner 输出
            end // 结束 issue 输出寄存级更新
            if (select_ready) begin // winner 选择级可以接受新仲裁结果
                select_valid_q <= winner_valid_d; // 注册下一 runnable winner 有效位
                select_index_q <= winner_index_d; // 注册下一 winner 索引
                if (winner_valid_d) begin // 仅在选择有效时推进分层公平性状态
                    group_rr_q <= winner_index_d[3:2] + 2'd1; // 下一 packet 从后继 context 组开始
                    lane_rr_q[winner_index_d[3:2]] <= winner_index_d[1:0] + 2'd1; // 本组下次从后继 context 开始
                end // 结束公平性状态更新
            end // 结束 winner 选择级更新
        end // 结束正常 context 调度
    end // 结束 context table 更新
    /* verilator lint_on WIDTHEXPAND */ // 恢复 scheduler 算术宽度检查
endmodule // 结束十六 context scheduler
