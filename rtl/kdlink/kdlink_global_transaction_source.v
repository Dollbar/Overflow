`include "kdlink_defs.vh" // 引入全局提交状态编码
module kdlink_global_transaction_source #( // 定义带槽位复用保护期的十六槽端到端事务保留和重传控制器
    parameter [11:0] REPLAY_GRACE_CYCLES = 12'd4095 // 配置完成事务槽不得立即分配给新身份的重放保护周期
) ( // 开始全局事务源端口声明
    input wire clk_i, // 接收事务控制时钟
    input wire rst_n_i, // 接收低有效异步硬复位
    input wire issue_valid_i, // 接收新全局事务请求有效位
    output wire issue_ready_o, // 返回新全局事务接收许可
    input wire [63:0] issue_transaction_id_i, // 接收新全局事务标识
    input wire [7:0] issue_topology_epoch_i, // 接收新全局事务拓扑代次
    input wire [11:0] issue_timeout_quanta_i, // 接收新全局事务超时周期数
    output wire send_valid_o, // 输出首次发送或重传命令有效位
    input wire send_ready_i, // 接收发送命令许可
    output wire [63:0] send_transaction_id_o, // 输出待发送全局事务标识
    output wire [7:0] send_topology_epoch_o, // 输出待发送拓扑代次
    output wire [3:0] send_retry_count_o, // 输出当前端到端重试次数
    input wire commit_valid_i, // 接收目的端全局提交确认有效位
    input wire [63:0] commit_transaction_id_i, // 接收已提交全局事务标识
    input wire [7:0] commit_topology_epoch_i, // 接收已提交拓扑代次
    input wire [1:0] commit_status_i, // 接收全局提交状态
    input wire route_reset_i, // 接收路由软复位和重选路径事件
    input wire [7:0] route_topology_epoch_i, // 接收软复位后的新拓扑代次
    output reg completion_valid_o, // 输出一次性源端完成脉冲
    output reg [63:0] completion_transaction_id_o, // 输出完成的全局事务标识
    output reg protocol_error_o, // 输出重复事务或非法确认 sticky 错误
    output reg retry_exhausted_o, // 输出端到端重试预算耗尽 sticky 错误
    output reg [4:0] outstanding_count_o // 输出当前保留事务数量
); // 结束全局事务源端口声明
    reg valid_q [0:15]; // 保存十六个事务槽有效位
    reg send_pending_q [0:15]; // 保存十六个事务槽待发送状态
    reg [63:0] transaction_id_q [0:15]; // 保存十六个全局事务标识
    reg [7:0] topology_epoch_q [0:15]; // 保存十六个事务拓扑代次
    reg [11:0] timeout_quanta_q [0:15]; // 保存十六个事务超时门限
    reg [11:0] age_q [0:15]; // 保存十六个事务等待计数
    reg [3:0] retry_count_q [0:15]; // 保存十六个事务重试计数
    reg [11:0] reuse_cooldown_q [0:15]; // 保存十六个事务槽完成后的身份复用保护倒计时
    reg free_found_d; // 标记组合扫描找到空闲事务槽
    reg [3:0] free_index_d; // 保存最低编号空闲事务槽
    reg duplicate_issue_d; // 标记输入事务标识仍在保留表中
    reg send_found_d; // 标记组合扫描找到待发送事务
    reg [3:0] send_index_d; // 保存最低编号待发送事务槽
    reg send_valid_q; // 保存已寄存发送命令有效状态
    reg [3:0] send_index_q; // 保存已寄存发送命令事务槽
    reg [63:0] send_transaction_id_q; // 保存已寄存发送命令事务标识
    reg [7:0] send_topology_epoch_q; // 保存已寄存发送命令拓扑代次
    reg [3:0] send_retry_count_q; // 保存已寄存发送命令重试计数
    reg commit_valid_q; // 保存一级流水后的全局确认有效位
    reg [63:0] commit_transaction_id_q; // 保存一级流水后的确认事务标识
    reg [7:0] commit_topology_epoch_q; // 保存一级流水后的确认拓扑代次
    reg [1:0] commit_status_q; // 保存一级流水后的全局确认状态
    reg commit_decision_valid_q; // 保存二级流水后的确认判定有效位
    reg commit_decision_success_q; // 保存二级流水后的确认精确匹配结果
    reg [3:0] commit_decision_index_q; // 保存二级流水后的确认事务槽编号
    reg [63:0] commit_decision_id_q; // 保存二级流水后的确认事务标识
    reg commit_found_d; // 标记确认匹配当前保留事务
    reg retry_exhaust_event_d; // 标记任一事务本周期耗尽端到端重试预算
    wire [3:0] issue_index; // 使用全局事务标识低四位选择固定源事务槽
    wire [3:0] commit_index; // 使用确认事务标识低四位选择固定源事务槽
    wire commit_success; // 标记目的端确认精确匹配并报告已提交
    integer scan_i; // 声明组合扫描循环变量
    genvar slot_g; // 声明事务槽生成循环变量
    always @(*) begin // 组合扫描空闲槽、重复标识、发送候选和确认匹配
        free_found_d = !valid_q[issue_index] && (reuse_cooldown_q[issue_index] == 12'd0); // 仅将未占用且已度过重放保护期的映射槽视为空闲
        free_index_d = issue_index; // 固定使用事务标识低四位映射槽
        duplicate_issue_d = valid_q[issue_index] && (transaction_id_q[issue_index] == issue_transaction_id_i); // 检查映射槽保存同一未完成事务
        send_found_d = 1'b0; // 默认没有待发送事务
        send_index_d = 4'd0; // 默认发送事务槽编号为零
        commit_found_d = valid_q[commit_index] && (transaction_id_q[commit_index] == commit_transaction_id_q) && (topology_epoch_q[commit_index] == commit_topology_epoch_q); // 直接检查流水确认映射槽的完整身份和代次
        retry_exhaust_event_d = 1'b0; // 默认没有事务耗尽重试预算
        for (scan_i = 32'd0; scan_i < 32'd16; scan_i = scan_i + 32'd1) begin // 扫描固定十六个事务槽
            if (valid_q[scan_i] && send_pending_q[scan_i] && !send_found_d) begin // 捕获最低编号待发送事务
                send_found_d = 1'b1; // 记录已经找到发送候选
                send_index_d = scan_i[3:0]; // 保存发送事务槽编号
            end // 结束发送候选捕获
            if (valid_q[scan_i] && (retry_count_q[scan_i] == 4'hf) && (route_reset_i || (!send_pending_q[scan_i] && (age_q[scan_i] + 12'd1 >= timeout_quanta_q[scan_i])))) retry_exhaust_event_d = 1'b1; // 汇总换路或超时触发的重试预算耗尽事件
        end // 结束固定事务槽组合扫描
    end // 结束事务表组合扫描
    assign issue_index = issue_transaction_id_i[3:0]; // 解码新事务固定槽编号
    assign commit_index = commit_transaction_id_q[3:0]; // 解码流水确认事务固定槽编号
    assign commit_success = commit_decision_valid_q && commit_decision_success_q; // 汇总二级流水后的合法全局提交事件
    assign issue_ready_o = free_found_d && !duplicate_issue_d && (issue_timeout_quanta_i != 12'd0); // 仅允许合法非重复事务进入空闲槽
    assign send_valid_o = send_valid_q; // 输出已寄存待发送事务有效状态
    assign send_transaction_id_o = send_transaction_id_q; // 输出已寄存事务标识
    assign send_topology_epoch_o = send_topology_epoch_q; // 输出已寄存事务拓扑代次
    assign send_retry_count_o = send_retry_count_q; // 输出已寄存事务重试计数
    always @(posedge clk_i or negedge rst_n_i) begin // 更新公共完成脉冲和 sticky 协议状态
        if (!rst_n_i) begin // 硬复位清除公共事务状态
            completion_valid_o <= 1'b0; // 清除源端完成脉冲
            completion_transaction_id_o <= 64'd0; // 清零完成事务标识
            protocol_error_o <= 1'b0; // 清除协议 sticky 错误
            retry_exhausted_o <= 1'b0; // 清除重试耗尽 sticky 错误
            outstanding_count_o <= 5'd0; // 清零当前保留事务数量
            send_valid_q <= 1'b0; // 清除已寄存发送命令有效位
            send_index_q <= 4'd0; // 清零已寄存发送事务槽
            send_transaction_id_q <= 64'd0; // 清零已寄存发送事务标识
            send_topology_epoch_q <= 8'd0; // 清零已寄存发送拓扑代次
            send_retry_count_q <= 4'd0; // 清零已寄存发送重试计数
            commit_valid_q <= 1'b0; // 清除全局确认流水有效位
            commit_transaction_id_q <= 64'd0; // 清零流水确认事务标识
            commit_topology_epoch_q <= 8'd0; // 清零流水确认拓扑代次
            commit_status_q <= `KDL_GLOBAL_STATUS_COMMITTED; // 复位流水确认状态为已提交
            commit_decision_valid_q <= 1'b0; // 清除确认判定流水有效位
            commit_decision_success_q <= 1'b0; // 清除确认判定匹配结果
            commit_decision_index_q <= 4'd0; // 清零确认判定事务槽编号
            commit_decision_id_q <= 64'd0; // 清零确认判定事务标识
        end else begin // 正常推进公共事务状态
            commit_valid_q <= commit_valid_i; // 每周期寄存外部全局确认有效位
            commit_transaction_id_q <= commit_transaction_id_i; // 每周期寄存外部确认事务标识
            commit_topology_epoch_q <= commit_topology_epoch_i; // 每周期寄存外部确认拓扑代次
            commit_status_q <= commit_status_i; // 每周期寄存外部全局确认状态
            commit_decision_valid_q <= commit_valid_q; // 将一级流水确认推进到判定级
            commit_decision_success_q <= commit_found_d && (commit_status_q == `KDL_GLOBAL_STATUS_COMMITTED); // 寄存完整身份、代次和状态匹配结果
            commit_decision_index_q <= commit_index; // 寄存确认映射事务槽编号
            commit_decision_id_q <= commit_transaction_id_q; // 寄存确认事务标识
            completion_valid_o <= commit_success; // 仅精确匹配的已提交确认产生完成脉冲
            if (commit_success) completion_transaction_id_o <= commit_decision_id_q; // 保存已完成全局事务标识
            if ((issue_valid_i && duplicate_issue_d) || (commit_decision_valid_q && !commit_decision_success_q)) protocol_error_o <= 1'b1; // sticky 报告重复事务或非法确认
            if (retry_exhaust_event_d) retry_exhausted_o <= 1'b1; // sticky 报告任一事务重试预算耗尽
            if ((issue_valid_i && issue_ready_o) && !commit_success) outstanding_count_o <= outstanding_count_o + 5'd1; // 仅新事务进入时增加保留数量
            else if (!(issue_valid_i && issue_ready_o) && commit_success) outstanding_count_o <= outstanding_count_o - 5'd1; // 仅事务完成时减少保留数量
            if (route_reset_i || (commit_success && send_valid_q && (send_transaction_id_q == commit_decision_id_q))) send_valid_q <= 1'b0; // 换路或对应事务提前完成时撤销旧发送命令
            else if (send_valid_q && send_ready_i) send_valid_q <= 1'b0; // 发送命令握手后释放输出寄存器
            else if (!send_valid_q && send_found_d) begin // 空闲输出寄存器捕获下一待发送事务
                send_valid_q <= 1'b1; // 标记寄存发送命令有效
                send_index_q <= send_index_d; // 保存发送事务槽编号
                send_transaction_id_q <= transaction_id_q[send_index_d]; // 保存发送事务标识
                send_topology_epoch_q <= topology_epoch_q[send_index_d]; // 保存发送拓扑代次
                send_retry_count_q <= retry_count_q[send_index_d]; // 保存发送重试计数
            end // 结束发送命令寄存
        end // 结束公共事务状态推进
    end // 结束公共事务状态时序逻辑
    generate // 为每个固定事务槽生成唯一时序驱动器
        /* verilator lint_off WIDTHTRUNC */ // 生成常量范围已证明适合四位事务槽编号
        for (slot_g = 32'd0; slot_g < 32'd16; slot_g = slot_g + 32'd1) begin : g_transaction_slot // 展开十六个独立事务槽
            localparam [3:0] SLOT_INDEX = slot_g; // 将当前生成槽编号冻结为四位常量
            always @(posedge clk_i or negedge rst_n_i) begin // 更新当前常量编号事务槽
                if (!rst_n_i) begin // 硬复位清除当前事务槽
                    valid_q[slot_g] <= 1'b0; // 清除事务槽有效位
                    send_pending_q[slot_g] <= 1'b0; // 清除事务槽待发送状态
                    transaction_id_q[slot_g] <= 64'd0; // 清零事务槽全局标识
                    topology_epoch_q[slot_g] <= 8'd0; // 清零事务槽拓扑代次
                    timeout_quanta_q[slot_g] <= 12'd0; // 清零事务槽超时门限
                    age_q[slot_g] <= 12'd0; // 清零事务槽等待计数
                    retry_count_q[slot_g] <= 4'd0; // 清零事务槽重试计数
                    reuse_cooldown_q[slot_g] <= 12'd0; // 清零事务槽身份复用保护倒计时
                end else if (valid_q[slot_g]) begin // 推进当前有效事务槽
                    if (route_reset_i) begin // 路由软复位要求当前未完成事务换代重发
                        topology_epoch_q[slot_g] <= route_topology_epoch_i; // 更新事务使用的新拓扑代次
                        age_q[slot_g] <= 12'd0; // 清零换路等待计数
                        send_pending_q[slot_g] <= 1'b1; // 将事务重新置为待发送
                        if (retry_count_q[slot_g] != 4'hf) retry_count_q[slot_g] <= retry_count_q[slot_g] + 4'd1; // 未耗尽时增加端到端重试计数
                    end else if (commit_success && (commit_decision_index_q == SLOT_INDEX)) begin // 二级流水确认匹配时释放当前事务
                        valid_q[slot_g] <= 1'b0; // 释放已完成事务槽
                        send_pending_q[slot_g] <= 1'b0; // 清除已完成事务发送状态
                        age_q[slot_g] <= 12'd0; // 清零已完成事务等待计数
                        reuse_cooldown_q[slot_g] <= REPLAY_GRACE_CYCLES; // 启动与目的端去重窗口一致的槽身份复用保护期
                    end else if (send_valid_o && send_ready_i && (send_index_q == SLOT_INDEX)) begin // 当前寄存发送命令被下游接受
                        send_pending_q[slot_g] <= 1'b0; // 转入等待目的端全局确认状态
                        age_q[slot_g] <= 12'd0; // 从零开始统计确认等待时间
                    end else if (!send_pending_q[slot_g]) begin // 等待确认期间推进超时计数
                        if (age_q[slot_g] + 12'd1 >= timeout_quanta_q[slot_g]) begin // 到达事务声明的超时门限
                            age_q[slot_g] <= 12'd0; // 清零等待计数以开始下一次尝试
                            if (retry_count_q[slot_g] != 4'hf) begin // 仅在仍有重试预算时重新发送
                                retry_count_q[slot_g] <= retry_count_q[slot_g] + 4'd1; // 增加端到端重试计数
                                send_pending_q[slot_g] <= 1'b1; // 重新置为待发送状态
                            end // 结束仍有重试预算处理
                        end else age_q[slot_g] <= age_q[slot_g] + 12'd1; // 未超时时推进等待计数
                    end // 结束等待确认超时处理
                end else if (reuse_cooldown_q[slot_g] != 12'd0) begin // 空闲槽仍处于旧身份重放保护期
                    reuse_cooldown_q[slot_g] <= reuse_cooldown_q[slot_g] - 12'd1; // 每周期递减槽身份复用保护倒计时
                end else if (issue_valid_i && issue_ready_o && (free_index_d == SLOT_INDEX)) begin // 捕获分配到当前槽的新全局事务
                    valid_q[slot_g] <= 1'b1; // 占用当前空闲事务槽
                    send_pending_q[slot_g] <= 1'b1; // 新事务立即进入待发送状态
                    transaction_id_q[slot_g] <= issue_transaction_id_i; // 保存新全局事务标识
                    topology_epoch_q[slot_g] <= issue_topology_epoch_i; // 保存新事务拓扑代次
                    timeout_quanta_q[slot_g] <= issue_timeout_quanta_i; // 保存新事务超时门限
                    age_q[slot_g] <= 12'd0; // 清零新事务等待计数
                    retry_count_q[slot_g] <= 4'd0; // 清零新事务重试计数
                end // 结束新事务捕获
            end // 结束当前事务槽时序逻辑
        end // 结束固定事务槽生成循环
        /* verilator lint_on WIDTHTRUNC */ // 恢复后续逻辑的常量截断检查
    endgenerate // 结束事务槽时序驱动器生成
endmodule // 结束 kdlink_global_transaction_source
