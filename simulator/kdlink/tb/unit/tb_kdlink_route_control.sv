`timescale 1ns/1ps // 定义平面、代次和无死锁控制自检时间单位
module tb_kdlink_route_control; // 定义多平面故障切换与双代路由控制联合自检
    logic clk; // 产生拓扑控制时钟
    logic rst_n; // 驱动低有效复位
    logic [63:0] transaction_id; // 驱动平面散列事务标识
    logic [7:0] active_plane_mask; // 驱动活动平面掩码
    logic [7:0] failed_plane_mask; // 驱动故障平面掩码
    logic adaptive_enable; // 驱动自适应选择使能
    logic force_escape; // 驱动强制 escape 选择
    wire selection_valid; // 观察安全平面存在状态
    wire [2:0] selected_plane; // 观察选中平面
    wire escape_selected; // 观察 escape 选择状态
    wire adaptive_fallback; // 观察自适应回退状态
    logic prepare_valid; // 驱动拓扑 prepare 请求
    logic [15:0] prepare_epoch; // 驱动影子拓扑代次
    logic [7:0] prepare_plane_mask; // 驱动影子活动平面
    logic commit_valid; // 驱动拓扑 commit 请求
    logic [15:0] commit_epoch; // 驱动待提交代次
    logic previous_drained; // 驱动上一代次排空状态
    wire [15:0] current_epoch; // 观察当前拓扑代次
    wire [7:0] current_plane_mask; // 观察当前活动平面
    wire [15:0] previous_epoch; // 观察上一排空代次
    wire previous_epoch_valid; // 观察双代窗口状态
    wire route_reset; // 观察换路重发脉冲
    wire config_error; // 观察代次配置 sticky 错误
    logic [2:0] current_plane; // 驱动无死锁检查当前平面
    logic [2:0] next_plane; // 驱动无死锁检查下一平面
    logic [2:0] current_rank; // 驱动当前 escape 等级
    logic [2:0] next_rank; // 驱动下一 escape 等级
    wire transition_allowed; // 观察平面转换许可
    wire escape_monotonic; // 观察 escape 等级单调性
    integer mask_index; // 遍历平面可用组合
    integer transaction_index; // 遍历事务散列起点
    integer failed_index; // 遍历代表性故障平面组合
    integer current_plane_index; // 穷举无死锁检查当前平面
    integer next_plane_index; // 穷举无死锁检查下一平面
    integer current_rank_index; // 穷举当前 escape 等级
    integer next_rank_index; // 穷举下一 escape 等级
    kdlink_plane_selector u_selector ( // 实例化八平面故障感知选择器
        .global_transaction_id_i(transaction_id), .active_plane_mask_i(active_plane_mask), .failed_plane_mask_i(failed_plane_mask), // 连接事务和可用平面状态
        .adaptive_enable_i(adaptive_enable), .force_escape_i(force_escape), // 连接注入策略
        .selection_valid_o(selection_valid), .selected_plane_o(selected_plane), // 观察选择结果
        .escape_selected_o(escape_selected), .adaptive_fallback_o(adaptive_fallback) // 观察 escape 使用原因
    ); // 结束平面选择器实例
    kdlink_route_epoch_manager #(.RESET_EPOCH(16'h0100), .RESET_PLANE_MASK(8'hff)) u_epoch ( // 实例化双代拓扑管理器
        .clk_i(clk), .rst_n_i(rst_n), .prepare_valid_i(prepare_valid), // 连接时钟、复位和 prepare 有效位
        .prepare_epoch_i(prepare_epoch), .prepare_plane_mask_i(prepare_plane_mask), // 连接影子代次和平面掩码
        .commit_valid_i(commit_valid), .commit_epoch_i(commit_epoch), .previous_drained_i(previous_drained), // 连接原子提交和排空状态
        .current_epoch_o(current_epoch), .current_plane_mask_o(current_plane_mask), // 观察当前拓扑状态
        .previous_epoch_o(previous_epoch), .previous_epoch_valid_o(previous_epoch_valid), // 观察上一排空代次
        .route_reset_o(route_reset), .config_error_o(config_error) // 观察换路脉冲和 sticky 错误
    ); // 结束拓扑代次管理器实例
    kdlink_deadlock_guard u_guard ( // 实例化 adaptive 至 escape 单向转换检查器
        .current_plane_i(current_plane), .next_plane_i(next_plane), // 连接当前和下一平面
        .current_escape_rank_i(current_rank), .next_escape_rank_i(next_rank), // 连接当前和下一 escape 等级
        .transition_allowed_o(transition_allowed), .escape_monotonic_o(escape_monotonic) // 观察无环合同
    ); // 结束无死锁检查器实例
    always #0.5 clk = ~clk; // 产生一纳秒时钟周期
    task automatic pulse_prepare(input [15:0] epoch_value, input [7:0] mask_value); // 发送单周期影子拓扑准备
        begin // 开始 prepare 请求
            @(negedge clk); prepare_epoch = epoch_value; prepare_plane_mask = mask_value; prepare_valid = 1'b1; // 驱动影子拓扑
            @(negedge clk); prepare_valid = 1'b0; // 完成 prepare 请求
        end // 结束 prepare 请求
    endtask // 结束 pulse_prepare
    task automatic pulse_commit(input [15:0] epoch_value); // 发送单周期拓扑原子提交
        begin // 开始 commit 请求
            @(negedge clk); commit_epoch = epoch_value; commit_valid = 1'b1; // 驱动待提交代次
            @(negedge clk); commit_valid = 1'b0; #0.1; // 完成提交并等待输出稳定
        end // 结束 commit 请求
    endtask // 结束 pulse_commit
    initial begin // 执行平面穷举、双代切换和无死锁转换测试
        clk = 1'b0; rst_n = 1'b0; transaction_id = 64'd0; active_plane_mask = 8'hff; failed_plane_mask = 8'd0; // 初始化平面状态
        adaptive_enable = 1'b1; force_escape = 1'b0; prepare_valid = 1'b0; prepare_epoch = 16'd0; prepare_plane_mask = 8'd0; // 初始化策略和 prepare 接口
        commit_valid = 1'b0; commit_epoch = 16'd0; previous_drained = 1'b0; // 初始化 commit 和排空接口
        current_plane = 3'd0; next_plane = 3'd0; current_rank = 3'd0; next_rank = 3'd1; // 初始化无死锁检查输入
        repeat (3) @(negedge clk); rst_n = 1'b1; #0.1; // 释放硬复位
        for (mask_index = 1; mask_index < 256; mask_index = mask_index + 1) begin // 穷举全部非空活动平面组合
            active_plane_mask = mask_index[7:0]; failed_plane_mask = 8'd0; // 驱动当前活动组合且无故障
            for (transaction_index = 0; transaction_index < 16; transaction_index = transaction_index + 1) begin // 覆盖全部三位散列起点及重复周期
                transaction_id = (transaction_index[0] ? 64'haaaa_aaaa_aaaa_aaaa : 64'h5555_5555_5555_5555) ^ {56'd0, transaction_index[7:0]}; #0.001; // 驱动全宽互补事务散列并等待组合传播
                if (!selection_valid || !active_plane_mask[selected_plane]) $fatal(1, "plane selector chose unavailable active plane"); // 要求任一非空组合得到活动平面
                if ((active_plane_mask & 8'hfe) != 8'd0 && selected_plane == 3'd0) $fatal(1, "adaptive injection consumed reserved escape plane"); // 自适应可用时不得占用 plane0
            end // 结束事务散列遍历
        end // 结束活动平面组合遍历
        active_plane_mask = 8'hff; failed_plane_mask = 8'hfe; transaction_id = 64'd5; #0.1; // 故障全部自适应平面
        if (!selection_valid || selected_plane != 3'd0 || !escape_selected || !adaptive_fallback) $fatal(1, "adaptive plane failure did not fall back to escape"); // 要求回退 plane0
        failed_plane_mask = 8'hff; #0.1; // 故障全部八平面
        if (selection_valid) $fatal(1, "all-failed plane set admitted traffic"); // 要求停止新流量
        active_plane_mask = 8'hff; failed_plane_mask = 8'd0; force_escape = 1'b1; #0.1; // 强制确定性 escape
        if (!selection_valid || selected_plane != 3'd0 || !escape_selected) $fatal(1, "forced escape did not select plane zero"); // 要求强制 plane0
        active_plane_mask = 8'hfe; failed_plane_mask = 8'd0; adaptive_enable = 1'b0; force_escape = 1'b0; #0.1; // 禁用自适应且不提供 escape 平面
        if (selection_valid) $fatal(1, "disabled adaptive mode used a non-escape plane"); // 要求无 plane0 时停止注入
        adaptive_enable = 1'b1; active_plane_mask = 8'hff; // 恢复完整自适应平面集合
        for (failed_index = 0; failed_index < 256; failed_index = failed_index + 1) begin // 穷举全部实时故障掩码翻转
            failed_plane_mask = failed_index[7:0]; transaction_id = failed_index[0] ? 64'hffff_ffff_ffff_ffff : 64'd0; #0.001; // 交替全宽事务图样并驱动故障集合
            if (selection_valid && failed_plane_mask[selected_plane]) $fatal(1, "plane selector chose a failed plane"); // 要求选择结果排除所有故障平面
        end // 结束故障掩码穷举
        failed_plane_mask = 8'd0; // 恢复无故障拓扑供代次测试
        if (current_epoch != 16'h0100 || current_plane_mask != 8'hff || previous_epoch_valid) $fatal(1, "route epoch reset profile mismatch"); // 要求复位 profile 正确
        pulse_prepare(16'h0101, 8'b1111_1101); // 准备保留 plane0 但禁用 plane1 的新拓扑
        if (current_epoch != 16'h0100) $fatal(1, "prepared route epoch became visible before commit"); // 要求 prepare 不改变当前转发
        pulse_commit(16'h0101); // 原子发布新拓扑代次
        if (current_epoch != 16'h0101 || current_plane_mask != 8'b1111_1101 || previous_epoch != 16'h0100 || !previous_epoch_valid || !route_reset) $fatal(1, "route epoch atomic commit mismatch"); // 要求双代窗口和换路脉冲建立
        pulse_prepare(16'h0102, 8'hff); // 在上一代尚未排空时尝试第三代 prepare
        if (!config_error || current_epoch != 16'h0101) $fatal(1, "third concurrent route epoch was not rejected"); // 要求严格限制当前加上一代
        previous_drained = 1'b1; @(negedge clk); previous_drained = 1'b0; #0.1; // 报告上一代已经完全排空
        if (previous_epoch_valid) $fatal(1, "drained previous route epoch remained accepted"); // 要求关闭旧代次窗口
        pulse_commit(16'hf0f0); // 在无影子代次时注入不匹配提交
        pulse_prepare(16'ha55a, 8'ha5); pulse_commit(16'ha55a); // 发布高翻转第二代拓扑字段
        if (current_epoch != 16'ha55a || current_plane_mask != 8'ha5 || !previous_epoch_valid) $fatal(1, "second route epoch commit mismatch"); // 要求第二轮完整字段原子发布
        previous_drained = 1'b1; @(negedge clk); previous_drained = 1'b0; #0.1; // 排空第二轮上一代窗口
        pulse_prepare(16'h5aa5, 8'h5b); pulse_commit(16'h5aa5); // 发布互补第三代拓扑字段且保留 plane0
        if (current_epoch != 16'h5aa5 || current_plane_mask != 8'h5b) $fatal(1, "complement route epoch commit mismatch"); // 要求互补字段完成发布
        current_plane = 3'd0; next_plane = 3'd0; current_rank = 3'd2; next_rank = 3'd3; #0.1; // 检查 escape 内严格递增
        if (!transition_allowed || !escape_monotonic) $fatal(1, "monotonic escape transition was rejected"); // 要求允许根向 leaf 依赖
        next_plane = 3'd2; #0.1; // 尝试从 escape 返回 adaptive
        if (transition_allowed) $fatal(1, "escape network returned to adaptive plane"); // 要求禁止形成回边
        current_plane = 3'd4; next_plane = 3'd0; next_rank = 3'd3; #0.1; // 尝试从 adaptive 单向进入 escape
        if (!transition_allowed) $fatal(1, "adaptive network could not enter monotonic escape"); // 要求允许 Duato escape 转换
        current_plane = 3'd0; next_plane = 3'd0; current_rank = 3'd3; next_rank = 3'd2; #0.1; // 尝试 escape 等级倒退
        if (transition_allowed || escape_monotonic) $fatal(1, "nonmonotonic escape dependency was accepted"); // 要求拒绝潜在依赖环
        for (current_plane_index = 0; current_plane_index < 8; current_plane_index = current_plane_index + 1) begin // 穷举当前八个逻辑平面
            for (next_plane_index = 0; next_plane_index < 8; next_plane_index = next_plane_index + 1) begin // 穷举下一跳八个逻辑平面
                for (current_rank_index = 0; current_rank_index < 8; current_rank_index = current_rank_index + 1) begin // 穷举当前 escape 等级
                    for (next_rank_index = 0; next_rank_index < 8; next_rank_index = next_rank_index + 1) begin // 穷举下一 escape 等级
                        current_plane = current_plane_index[2:0]; next_plane = next_plane_index[2:0]; current_rank = current_rank_index[2:0]; next_rank = next_rank_index[2:0]; #0.001; // 驱动完整转换空间
                        if (escape_monotonic != (next_rank_index > current_rank_index)) $fatal(1, "escape rank comparator mismatch"); // 要求等级单调输出精确
                        if (transition_allowed != ((current_plane_index == 0) ? ((next_plane_index == 0) && (next_rank_index > current_rank_index)) : ((next_plane_index == current_plane_index) || ((next_plane_index == 0) && (next_rank_index > current_rank_index))))) $fatal(1, "deadlock transition truth table mismatch"); // 要求平面转换满足单向 escape 合同
                    end // 结束下一等级穷举
                end // 结束当前等级穷举
            end // 结束下一平面穷举
        end // 结束无死锁转换全空间验证
        previous_drained = 1'b1; pulse_prepare(16'hffff, 8'hff); pulse_commit(16'hffff); previous_drained = 1'b0; // 在明确排空许可下发布全位翻转拓扑
        if (current_epoch != 16'hffff || current_plane_mask != 8'hff) $fatal(1, "all-one route epoch commit mismatch current=%04x mask=%02x previous_valid=%0d error=%0d", current_epoch, current_plane_mask, previous_epoch_valid, config_error); // 要求全位拓扑状态原子发布
        rst_n = 1'b0; repeat (2) @(negedge clk); // 最终复位覆盖影子、当前和上一代寄存器回落
        $display("TB_KDLINK_ROUTE_CONTROL_PASS"); // 输出 manifest 约定的通过签名
        $finish; // 结束自校验仿真
    end // 结束主测试序列
endmodule // 结束 tb_kdlink_route_control
