`timescale 1ns/1ps // 定义 scheduler 测试时间单位
module tb_kdlink_v2_context_scheduler16; // 定义十六 context scheduler 自校验测试
    logic clk; // 生成一 GHz 测试时钟
    logic rst_n; // 生成低有效复位
    logic submit_valid_i; // 驱动 descriptor 提交有效位
    wire submit_ready_o; // 观察 descriptor 提交许可
    logic [511:0] descriptor_i; // 驱动 descriptor 数据
    wire allocate_valid_o; // 观察 context 分配完成脉冲
    wire [3:0] allocate_index_o; // 观察分配 context 索引
    logic [15:0] blocked_i; // 驱动 context 阻塞位图
    wire issue_valid_o; // 观察调度输出有效位
    logic issue_ready_i; // 驱动调度输出许可
    wire [3:0] issue_index_o; // 观察调度 context 索引
    wire [511:0] issue_descriptor_o; // 观察调度 descriptor
    logic complete_valid_i; // 驱动 context 完成有效位
    logic [3:0] complete_index_i; // 驱动完成 context 索引
    wire [15:0] active_o; // 观察 active context 位图
    wire descriptor_error_o; // 观察 descriptor 错误脉冲
    wire duplicate_error_o; // 观察重复 collective ID 脉冲
    integer context_index; // 提供 context 分配和回收循环索引
    integer issue_count; // 记录已消费 issue 数量
    integer fairness_count [0:15]; // 记录各 context 获得服务次数
    integer blocked_count [0:15]; // 记录阻塞测试服务次数
    kdlink_v2_context_scheduler16 u_dut ( // 实例化十六 context scheduler
        .clk_i(clk), .rst_n_i(rst_n), // 连接时钟和复位
        .submit_valid_i(submit_valid_i), .submit_ready_o(submit_ready_o), .descriptor_i(descriptor_i), // 连接 descriptor 提交接口
        .allocate_valid_o(allocate_valid_o), .allocate_index_o(allocate_index_o), // 连接 context 分配结果
        .blocked_i(blocked_i), .issue_valid_o(issue_valid_o), .issue_ready_i(issue_ready_i), .issue_index_o(issue_index_o), .issue_descriptor_o(issue_descriptor_o), // 连接 packet-boundary issue 接口
        .complete_valid_i(complete_valid_i), .complete_index_i(complete_index_i), .active_o(active_o), // 连接 context 完成和状态接口
        .descriptor_error_o(descriptor_error_o), .duplicate_error_o(duplicate_error_o) // 连接 descriptor 错误状态
    ); // 结束 scheduler 实例
    always #0.5 clk = ~clk; // 生成一 GHz 时钟
    initial begin // 执行 context 分配、错误和公平性测试
        clk = 1'b0; // 初始化时钟
        rst_n = 1'b0; // 保持复位有效
        submit_valid_i = 1'b0; // 清除 descriptor 提交
        descriptor_i = 512'd0; // 清零 descriptor
        blocked_i = 16'd0; // 默认所有 context runnable
        issue_ready_i = 1'b0; // 分配阶段阻塞 issue 消费
        complete_valid_i = 1'b0; // 清除 context 完成
        complete_index_i = 4'd0; // 清零完成索引
        issue_count = 0; // 清零 issue 计数
        for (context_index = 0; context_index < 16; context_index = context_index + 1) begin // 初始化公平性计数
            fairness_count[context_index] = 0; // 清零全 context 服务计数
            blocked_count[context_index] = 0; // 清零阻塞测试服务计数
        end // 结束公平性计数初始化
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        for (context_index = 0; context_index < 16; context_index = context_index + 1) begin // 分配全部十六 context
            @(negedge clk); // 在下降沿建立 descriptor
            descriptor_i = 512'd0; // 清零 descriptor 后写合法字段
            descriptor_i[2:0] = (context_index[2:0] < 3'd6) ? context_index[2:0] : context_index[2:0] - 3'd6; // 覆盖六种合法 opcode
            descriptor_i[4:3] = context_index[1:0]; // 覆盖四种 dtype
            descriptor_i[9:5] = context_index[4:0]; // 写入 local node
            descriptor_i[15:10] = 6'd32; // 写入固定节点数
            descriptor_i[24:21] = 4'd2; // 写入 descriptor 版本
            descriptor_i[36:25] = context_index[11:0]; // 写入唯一 collective ID
            descriptor_i[56:49] = 8'hFF; // 启用全部 plane
            descriptor_i[58:57] = 2'b11; // 启用双 slice
            submit_valid_i = 1'b1; // 提交当前 descriptor
            @(posedge clk); #0.01; // 等待分配结果更新
            if (!allocate_valid_o || allocate_index_o != context_index[3:0]) $fatal(1, "allocation mismatch index=%0d valid=%b got=%0d", context_index, allocate_valid_o, allocate_index_o); // 要求按最低空闲索引分配
        end // 结束十六 context 分配
        @(negedge clk); submit_valid_i = 1'b0; // 停止 descriptor 提交
        @(posedge clk); #0.01; // 等待 active bitmap 稳定
        if (active_o != 16'hFFFF || submit_ready_o) $fatal(1, "full context table mismatch active=%h ready=%b", active_o, submit_ready_o); // 要求全部 context active 且无空闲许可
        @(negedge clk); // 建立重复 descriptor 激励
        descriptor_i[36:25] = 12'd3; // 使用 active collective ID
        submit_valid_i = 1'b1; // 提交重复 descriptor
        @(posedge clk); #0.01; // 等待错误脉冲
        if (!duplicate_error_o || descriptor_error_o || allocate_valid_o) $fatal(1, "duplicate descriptor classification mismatch"); // 要求只报告重复错误
        @(negedge clk); // 建立 malformed descriptor 激励
        descriptor_i[24:21] = 4'd1; // 写入非法 descriptor 版本
        descriptor_i[36:25] = 12'd100; // 避免重复 ID 干扰分类
        submit_valid_i = 1'b1; // 提交非法 descriptor
        @(posedge clk); #0.01; // 等待错误脉冲
        if (!descriptor_error_o || duplicate_error_o || allocate_valid_o) $fatal(1, "malformed descriptor classification mismatch"); // 要求只报告格式错误
        @(negedge clk); submit_valid_i = 1'b0; issue_ready_i = 1'b1; blocked_i = 16'd0; // 启动全 context 公平调度
        while (issue_count < 32) begin // 消费两个完整 round-robin 轮次
            @(posedge clk); #0.01; // 在时钟后采样 issue
            if (issue_valid_o && issue_ready_i) begin // 统计一次有效 issue
                if (issue_descriptor_o[36:25] != {8'd0, issue_index_o}) $fatal(1, "descriptor/index mismatch index=%0d id=%0d", issue_index_o, issue_descriptor_o[36:25]); // 要求 descriptor 与 context 对应
                fairness_count[issue_index_o] = fairness_count[issue_index_o] + 1; // 累加该 context 服务次数
                issue_count = issue_count + 1; // 累加总服务次数
            end // 结束有效 issue 统计
        end // 结束全 context 公平调度
        for (context_index = 0; context_index < 16; context_index = context_index + 1) begin // 检查两轮公平性
            if (fairness_count[context_index] != 2) $fatal(1, "fairness mismatch context=%0d count=%0d", context_index, fairness_count[context_index]); // 要求每 context 恰好两次
        end // 结束公平性检查
        @(negedge clk); blocked_i = 16'hAAAA; issue_count = 0; // 阻塞全部奇数 context
        repeat (2) @(posedge clk); #0.01; // 排空阻塞生效前已经进入两级 issue pipeline 的选择
        while (issue_count < 16) begin // 消费两个偶数 context 轮次
            @(posedge clk); #0.01; // 在时钟后采样 issue
            if (issue_valid_o && issue_ready_i) begin // 统计一次有效 issue
                if (issue_index_o[0]) $fatal(1, "blocked context issued index=%0d", issue_index_o); // 禁止奇数阻塞 context 获得服务
                blocked_count[issue_index_o] = blocked_count[issue_index_o] + 1; // 累加偶数 context 服务次数
                issue_count = issue_count + 1; // 累加阻塞测试服务次数
            end // 结束阻塞测试统计
        end // 结束阻塞调度窗口
        for (context_index = 0; context_index < 16; context_index = context_index + 2) begin // 检查偶数 context 公平性
            if (blocked_count[context_index] != 2) $fatal(1, "blocked fairness mismatch context=%0d count=%0d", context_index, blocked_count[context_index]); // 要求每个 runnable context 两次
        end // 结束阻塞公平性检查
        @(negedge clk); issue_ready_i = 1'b0; blocked_i = 16'hFFFF; // 停止 issue 并阻塞全部 context
        for (context_index = 0; context_index < 16; context_index = context_index + 1) begin // 逐项释放全部 context
            @(negedge clk); complete_valid_i = 1'b1; complete_index_i = context_index[3:0]; // 提交一个完成索引
            @(posedge clk); #0.01; // 等待 active 状态更新
            if (active_o[context_index]) $fatal(1, "context release failed index=%0d", context_index); // 要求目标 context 已释放
        end // 结束全部 context 释放
        @(negedge clk); complete_valid_i = 1'b0; // 停止完成提交
        @(posedge clk); #0.01; // 等待状态稳定
        if (active_o != 16'd0) $fatal(1, "context table did not drain active=%h", active_o); // 要求 active table 清空
        $display("TB_KDLINK_V2_CONTEXT_SCHEDULER16_PASS contexts=16 fairness_rounds=2 blocked_fairness=PASS duplicate=PASS malformed=PASS"); // 报告 scheduler 测试通过
        $finish; // 结束测试
    end // 结束主测试流程
    initial begin // 设置仿真超时
        #1000; // 等待最大测试时长
        $fatal(1, "KDLink-v2 context scheduler timeout"); // 超时失败
    end // 结束超时保护
endmodule // 结束 scheduler 测试
