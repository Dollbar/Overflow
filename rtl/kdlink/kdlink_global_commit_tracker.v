`include "kdlink_defs.vh" // 引入全局提交状态编码
module kdlink_global_commit_tracker #( // 定义带输入流水和重放保护期的十六槽目的端提交去重窗口
    parameter [11:0] REPLAY_GRACE_CYCLES = 12'd4095 // 配置事务槽身份不得被不同事务覆盖的重放保护周期
) ( // 开始目的端全局提交跟踪器端口声明
    input wire clk_i, // 接收目的端提交跟踪时钟
    input wire rst_n_i, // 接收低有效异步硬复位
    input wire route_reset_i, // 接收不得清除提交历史的路由软复位事件
    input wire commit_valid_i, // 接收本地消费者已原子提交事务事件
    output wire commit_ready_o, // 返回提交事件接收许可
    input wire [7:0] source_domain_i, // 接收原事务源域标识
    input wire [7:0] destination_domain_i, // 接收原事务目的域标识
    input wire [4:0] source_node_i, // 接收原事务源节点标识
    input wire [4:0] destination_node_i, // 接收原事务目的节点标识
    input wire [7:0] topology_epoch_i, // 接收本次到达使用的拓扑代次
    input wire [63:0] global_transaction_id_i, // 接收全局事务标识
    output reg deliver_valid_o, // 输出仅首次提交时有效的本地交付脉冲
    output reg [63:0] deliver_transaction_id_o, // 输出首次交付的全局事务标识
    output reg global_ack_valid_o, // 输出首次或重复到达均产生的全局确认脉冲
    output reg [7:0] global_ack_source_domain_o, // 输出确认对应的原事务源域
    output reg [7:0] global_ack_destination_domain_o, // 输出确认对应的原事务目的域
    output reg [4:0] global_ack_source_node_o, // 输出确认对应的原事务源节点
    output reg [4:0] global_ack_destination_node_o, // 输出确认对应的原事务目的节点
    output reg [7:0] global_ack_topology_epoch_o, // 输出确认应沿用的到达拓扑代次
    output reg [63:0] global_ack_transaction_id_o, // 输出确认对应的全局事务标识
    output reg [1:0] global_ack_status_o, // 输出全局确认提交状态
    output reg duplicate_seen_o // 输出观察到重复事务的 sticky 状态
); // 结束目的端全局提交跟踪器端口声明
    reg history_valid_q [0:15]; // 保存十六个提交历史槽有效位
    reg [89:0] history_identity_q [0:15]; // 保存十六个完整端点事务身份
    reg [11:0] history_age_q [0:15]; // 保存提交历史保护期年龄
    reg pending_valid_q; // 保存输入流水中已经握手的提交事件
    reg [89:0] pending_identity_q; // 保存输入流水中的完整端点事务身份
    reg [7:0] pending_topology_epoch_q; // 保存输入流水中的到达拓扑代次
    wire [89:0] current_identity; // 拼接当前输入完整端点事务身份
    wire [3:0] current_history_index; // 解码当前输入直接映射历史槽
    wire [3:0] pending_history_index; // 解码输入流水直接映射历史槽
    wire [15:0] current_slot_select_w; // 并行解码当前输入映射历史槽
    wire [15:0] pending_slot_select_w; // 并行解码流水输入映射历史槽
    wire [15:0] current_slot_match_w; // 并行比较当前输入与选中历史身份
    wire [15:0] current_slot_expired_w; // 并行检查当前输入选中历史保护期
    wire [15:0] pending_slot_match_w; // 并行比较流水输入与选中历史身份
    wire [15:0] pending_slot_expired_w; // 并行检查流水输入选中历史保护期
    wire current_history_match; // 标记当前输入匹配已提交历史身份
    wire current_history_expired; // 标记当前输入映射历史槽已经超过保护期
    wire current_conflicts_pending; // 标记当前输入与流水提交竞争同一直接映射槽
    wire current_matches_pending; // 标记当前输入是流水提交的背靠背重复到达
    wire commit_fire; // 标记本周期当前输入被流水接受
    wire pending_history_match; // 标记流水提交匹配已提交历史身份
    wire pending_history_expired; // 标记流水提交映射历史槽已经超过保护期
    wire pending_is_duplicate; // 标记流水提交是保护期内重复到达
    genvar history_g; // 声明提交历史槽生成循环变量
    assign current_identity = {source_domain_i, destination_domain_i, source_node_i, destination_node_i, global_transaction_id_i}; // 拼接当前完整端点事务身份
    assign current_history_index = global_transaction_id_i[3:0]; // 使用当前事务标识低四位选择历史槽
    assign pending_history_index = pending_identity_q[3:0]; // 使用流水事务标识低四位选择历史槽
    assign current_history_match = |current_slot_match_w; // 平衡归约选中槽的当前输入完整身份比较
    assign current_history_expired = |current_slot_expired_w; // 平衡归约选中槽的当前输入保护期检查
    assign current_conflicts_pending = pending_valid_q && (current_history_index == pending_history_index); // 检查当前输入是否命中尚未写入历史的流水槽
    assign current_matches_pending = current_conflicts_pending && (current_identity == pending_identity_q); // 允许同一身份背靠背进入流水并由历史旁路去重
    assign commit_ready_o = current_conflicts_pending ? current_matches_pending : (!history_valid_q[current_history_index] || current_history_match || current_history_expired); // 对流水同槽冲突优先执行身份旁路否则检查已提交历史
    assign commit_fire = commit_valid_i && commit_ready_o; // 汇总当前提交输入握手事件
    assign pending_history_match = |pending_slot_match_w; // 平衡归约选中槽的流水提交完整身份比较
    assign pending_history_expired = |pending_slot_expired_w; // 平衡归约选中槽的流水提交保护期检查
    assign pending_is_duplicate = pending_history_match && !pending_history_expired; // 仅保护期内的完整身份匹配按重复提交处理
    always @(posedge clk_i or negedge rst_n_i) begin // 更新输入流水、本地交付、全局确认和 sticky 状态
        if (!rst_n_i) begin // 硬复位重新建立提交协议会话
            pending_valid_q <= 1'b0; // 清除提交输入流水有效位
            pending_identity_q <= 90'd0; // 清零提交输入流水身份
            pending_topology_epoch_q <= 8'd0; // 清零提交输入流水拓扑代次
            deliver_valid_o <= 1'b0; // 清除本地交付脉冲
            deliver_transaction_id_o <= 64'd0; // 清零本地交付事务标识
            global_ack_valid_o <= 1'b0; // 清除全局确认脉冲
            global_ack_source_domain_o <= 8'd0; // 清零确认原事务源域
            global_ack_destination_domain_o <= 8'd0; // 清零确认原事务目的域
            global_ack_source_node_o <= 5'd0; // 清零确认原事务源节点
            global_ack_destination_node_o <= 5'd0; // 清零确认原事务目的节点
            global_ack_topology_epoch_o <= 8'd0; // 清零确认拓扑代次
            global_ack_transaction_id_o <= 64'd0; // 清零确认事务标识
            global_ack_status_o <= `KDL_GLOBAL_STATUS_COMMITTED; // 复位确认状态为已提交编码
            duplicate_seen_o <= 1'b0; // 清除重复事务 sticky 状态
        end else begin // 正常推进提交输入流水和目的端去重结果
            pending_valid_q <= commit_fire; // 仅将已经握手的当前提交装入输入流水
            pending_identity_q <= current_identity; // 每周期采样输入身份以切断接收许可到宽数据寄存器的组合路径
            pending_topology_epoch_q <= topology_epoch_i; // 每周期采样到达拓扑代次并由流水有效位限定其语义
            deliver_valid_o <= 1'b0; // 默认本周期不产生首次本地交付
            global_ack_valid_o <= 1'b0; // 默认本周期不产生全局确认
            if (pending_valid_q) begin // 处理上一周期已经握手的提交事件
                global_ack_valid_o <= 1'b1; // 首次和重复提交均返回全局确认
                global_ack_source_domain_o <= pending_identity_q[89:82]; // 输出流水原事务源域
                global_ack_destination_domain_o <= pending_identity_q[81:74]; // 输出流水原事务目的域
                global_ack_source_node_o <= pending_identity_q[73:69]; // 输出流水原事务源节点
                global_ack_destination_node_o <= pending_identity_q[68:64]; // 输出流水原事务目的节点
                global_ack_topology_epoch_o <= pending_topology_epoch_q; // 沿用流水到达使用的拓扑代次
                global_ack_transaction_id_o <= pending_identity_q[63:0]; // 输出流水全局事务标识
                global_ack_status_o <= `KDL_GLOBAL_STATUS_COMMITTED; // 报告目的端已经原子提交
                if (pending_is_duplicate) duplicate_seen_o <= 1'b1; // sticky 记录重复到达并抑制再次交付
                else begin // 空槽或保护期满后的新身份允许首次本地可见
                    deliver_valid_o <= 1'b1; // 产生仅一次的本地交付脉冲
                    deliver_transaction_id_o <= pending_identity_q[63:0]; // 输出首次交付事务标识
                end // 结束首次提交处理
            end // 结束流水提交事件处理
        end // 结束正常提交处理
    end // 结束公共提交输出时序逻辑
    generate // 为每个提交历史槽生成唯一时序驱动器
        /* verilator lint_off WIDTHTRUNC */ // 生成常量范围已经证明适合四位提交历史槽编号
        for (history_g = 32'd0; history_g < 32'd16; history_g = history_g + 32'd1) begin : g_commit_history // 展开十六个独立提交历史槽
            localparam [3:0] HISTORY_INDEX = history_g; // 将当前生成历史槽编号冻结为四位常量
            assign current_slot_select_w[history_g] = current_history_index == HISTORY_INDEX; // 将当前输入索引并行解码为独热选择
            assign pending_slot_select_w[history_g] = pending_history_index == HISTORY_INDEX; // 将流水输入索引并行解码为独热选择
            assign current_slot_match_w[history_g] = current_slot_select_w[history_g] && history_valid_q[history_g] && (history_identity_q[history_g] == current_identity); // 在固定槽内并行比较当前身份
            assign current_slot_expired_w[history_g] = current_slot_select_w[history_g] && (history_age_q[history_g] >= REPLAY_GRACE_CYCLES); // 在固定槽内并行比较当前保护年龄
            assign pending_slot_match_w[history_g] = pending_slot_select_w[history_g] && history_valid_q[history_g] && (history_identity_q[history_g] == pending_identity_q); // 在固定槽内并行比较流水身份
            assign pending_slot_expired_w[history_g] = pending_slot_select_w[history_g] && (history_age_q[history_g] >= REPLAY_GRACE_CYCLES); // 在固定槽内并行比较流水保护年龄
            always @(posedge clk_i or negedge rst_n_i) begin // 更新当前常量编号提交历史槽
                if (!rst_n_i) begin // 硬复位清除当前提交历史槽
                    history_valid_q[history_g] <= 1'b0; // 清除提交历史槽有效位
                    history_identity_q[history_g] <= 90'd0; // 清零完整提交历史身份
                    history_age_q[history_g] <= 12'd0; // 清零提交历史保护年龄
                end else if (pending_valid_q && !pending_is_duplicate && (pending_history_index == HISTORY_INDEX)) begin // 流水首次提交或保护期满的新身份选中当前槽
                    history_valid_q[history_g] <= 1'b1; // 标记当前提交历史槽有效
                    history_identity_q[history_g] <= pending_identity_q; // 原子保存完整流水提交身份
                    history_age_q[history_g] <= 12'd0; // 从零开始新的重放保护期
                end else if (history_valid_q[history_g] && (history_age_q[history_g] != 12'hfff)) begin // 有效历史槽尚未达到年龄计数饱和值
                    history_age_q[history_g] <= history_age_q[history_g] + 12'd1; // 推进当前提交历史保护年龄
                end // 结束当前提交历史槽推进
            end // 结束当前提交历史槽时序逻辑
        end // 结束提交历史槽生成循环
        /* verilator lint_on WIDTHTRUNC */ // 恢复后续逻辑的常量截断检查
    endgenerate // 结束提交历史槽时序驱动器生成
    wire unused_route_reset; // 标记路由软复位不得参与提交历史清除
    assign unused_route_reset = route_reset_i; // 保留显式软复位接口并表达提交历史跨换路保存语义
endmodule // 结束 kdlink_global_commit_tracker
