module kdlink_v2_switch_rr_arbiter32 ( // 定义三十二请求分层 round-robin 仲裁器
    input wire clk_i, // 接收 switch 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire enable_i, // 接收本周期仲裁许可
    input wire [31:0] request_i, // 接收三十二路请求
    output reg grant_valid_o, // 输出注册化 grant 有效位
    output reg [4:0] grant_index_o // 输出注册化 grant 索引
); // 结束端口声明
    reg [2:0] group_rr_q; // 保存八组之间的 round-robin 起点
    reg [1:0] lane_rr_q [0:7]; // 保存每组四 lane 的 round-robin 起点
    /* verilator lint_off WIDTHEXPAND */ // round-robin 指针与 integer 扫描偏移按固定 modulo 范围截断
    reg [7:0] group_valid_d; // 保存八组局部 winner 有效位
    reg [15:0] group_lane_d; // 保存八组局部 winner lane
    reg winner_valid_d; // 保存最终 winner 有效位
    reg [4:0] winner_index_d; // 保存最终 winner 索引
    integer group_index; // 提供组索引
    integer lane_offset; // 提供组内扫描偏移
    integer group_offset; // 提供组间扫描偏移
    integer lane_candidate; // 保存组内候选索引
    integer group_candidate; // 保存组间候选索引
    always @(*) begin // 计算分层 round-robin winner
        group_valid_d = 8'd0; // 默认全部组无 winner
        group_lane_d = 16'd0; // 默认全部组 winner lane 为零
        for (group_index = 0; group_index < 8; group_index = group_index + 1) begin // 并行计算八个四路局部 winner
            for (lane_offset = 0; lane_offset < 4; lane_offset = lane_offset + 1) begin // 从本组 round-robin 起点扫描四 lane
                lane_candidate = (lane_rr_q[group_index] + lane_offset) & 3; // 形成组内 modulo 四候选
                if (!group_valid_d[group_index] && request_i[group_index*4 + lane_candidate]) begin // 捕获本组首个有效请求
                    group_valid_d[group_index] = 1'b1; // 标记本组存在 winner
                    group_lane_d[group_index*2 +: 2] = lane_candidate[1:0]; // 保存本组 winner lane
                end // 结束局部 winner 捕获
            end // 结束组内扫描
        end // 结束八组局部 winner 计算
        winner_valid_d = 1'b0; // 默认最终无 winner
        winner_index_d = 5'd0; // 默认最终 winner 索引为零
        for (group_offset = 0; group_offset < 8; group_offset = group_offset + 1) begin // 从组 round-robin 起点扫描八组
            group_candidate = (group_rr_q + group_offset) & 7; // 形成 modulo 八组候选
            if (!winner_valid_d && group_valid_d[group_candidate]) begin // 捕获首个有局部 winner 的组
                winner_valid_d = 1'b1; // 标记最终 winner 有效
                winner_index_d = {group_candidate[2:0], group_lane_d[group_candidate*2 +: 2]}; // 合成五位 winner 索引
            end // 结束最终 winner 捕获
        end // 结束组间扫描
    end // 结束分层 winner 计算
    always @(posedge clk_i or negedge rst_n_i) begin // 注册 grant 并更新公平性指针
        if (!rst_n_i) begin // 检测复位有效
            group_rr_q <= 3'd0; // 清零组 round-robin 起点
            grant_valid_o <= 1'b0; // 清除注册 grant 有效位
            grant_index_o <= 5'd0; // 清零注册 grant 索引
            for (group_index = 0; group_index < 8; group_index = group_index + 1) lane_rr_q[group_index] <= 2'd0; // 清零全部局部 round-robin 起点
        end else begin // 处理正常仲裁
            grant_valid_o <= enable_i && winner_valid_d; // 注册仲裁有效位
            grant_index_o <= winner_index_d; // 注册仲裁 winner 索引
            if (enable_i && winner_valid_d) begin // 仅在 grant 成立时推进公平性状态
                group_rr_q <= winner_index_d[4:2] + 3'd1; // 下一次从后继组开始
                lane_rr_q[winner_index_d[4:2]] <= winner_index_d[1:0] + 2'd1; // 本组下一次从后继 lane 开始
            end // 结束公平性状态更新
        end // 结束正常仲裁
    end // 结束 grant 注册
    /* verilator lint_on WIDTHEXPAND */ // 恢复 round-robin 算术宽度检查
endmodule // 结束三十二请求仲裁器
