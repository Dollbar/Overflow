`include "kdlink_defs.vh" // 引入全局提交状态编码
module kdlink_transaction_window #( // 定义可参数化百万端点源事务保留窗口
    parameter integer ENTRY_COUNT = 64, // 指定可同时保留的端到端事务数量
    parameter [15:0] REPLAY_GRACE_CYCLES = 16'd65535 // 指定已完成事务标识禁止复用周期
) ( // 开始源事务窗口端口声明
    input wire clk_i, // 接收事务窗口工作时钟
    input wire rst_n_i, // 接收低有效异步硬复位
    input wire issue_valid_i, // 接收新全局事务请求
    output wire issue_ready_o, // 返回新事务接收许可
    input wire [63:0] issue_transaction_id_i, // 接收新事务标识
    input wire [15:0] issue_topology_epoch_i, // 接收新事务十六位拓扑代次
    input wire [15:0] issue_timeout_quanta_i, // 接收新事务超时周期数
    output wire send_valid_o, // 输出首次发送或重传命令有效位
    input wire send_ready_i, // 接收发送命令许可
    output wire [63:0] send_transaction_id_o, // 输出待发送事务标识
    output wire [15:0] send_topology_epoch_o, // 输出待发送十六位拓扑代次
    output wire [3:0] send_retry_count_o, // 输出当前端到端重试次数
    input wire commit_valid_i, // 接收目的端全局提交确认
    input wire [63:0] commit_transaction_id_i, // 接收确认事务标识
    input wire [15:0] commit_topology_epoch_i, // 接收确认拓扑代次
    input wire [1:0] commit_status_i, // 接收全局提交状态
    input wire route_reset_i, // 接收路由软复位和重选路径事件
    input wire [15:0] route_topology_epoch_i, // 接收重选路径后的拓扑代次
    output reg completion_valid_o, // 输出一次性源端完成脉冲
    output reg [63:0] completion_transaction_id_o, // 输出已完成事务标识
    output reg protocol_error_o, // 输出重复事务或非法确认 sticky 错误
    output reg retry_exhausted_o, // 输出端到端重试预算耗尽 sticky 错误
    output reg window_overflow_o, // 输出保留窗口容量不足 sticky 错误
    output reg [8:0] outstanding_count_o // 输出当前保留事务数量
); // 结束源事务窗口端口声明
    reg valid_q [0:ENTRY_COUNT-1]; // 保存参数化事务槽有效位
    reg send_pending_q [0:ENTRY_COUNT-1]; // 保存事务待发送状态
    reg [63:0] transaction_id_q [0:ENTRY_COUNT-1]; // 保存完整事务标识
    reg [15:0] topology_epoch_q [0:ENTRY_COUNT-1]; // 保存十六位拓扑代次
    reg [15:0] timeout_quanta_q [0:ENTRY_COUNT-1]; // 保存事务超时门限
    reg [15:0] timeout_remaining_q [0:ENTRY_COUNT-1]; // 保存等待确认的剩余超时周期
    reg [3:0] retry_count_q [0:ENTRY_COUNT-1]; // 保存端到端重试次数
    reg [15:0] reuse_cooldown_q [0:ENTRY_COUNT-1]; // 保存已完成事务标识复用保护倒计时
    localparam integer SEARCH_BANK_SIZE = 4; // 将宽关联搜索拆成四槽局部编码组
    localparam integer SEARCH_BANK_COUNT = (ENTRY_COUNT + SEARCH_BANK_SIZE - 1) / SEARCH_BANK_SIZE; // 计算参数化搜索组数量
    wire [ENTRY_COUNT-1:0] free_candidate_w; // 并行标记完全空闲事务槽
    wire [ENTRY_COUNT-1:0] duplicate_candidate_w; // 并行标记活动或保护期重复事务身份
    wire [ENTRY_COUNT-1:0] send_candidate_w; // 并行标记待发送事务槽
    wire [ENTRY_COUNT-1:0] retry_exhaust_candidate_w; // 并行标记重试预算耗尽事件
    reg [ENTRY_COUNT-1:0] retry_exhaust_pending_q; // 流水保存各槽预算耗尽事件以切断宽归约关键路径
    reg [ENTRY_COUNT-1:0] duplicate_issue_pending_q; // 流水保存各槽重复签发比较结果
    wire [SEARCH_BANK_COUNT-1:0] free_bank_found_w; // 标记各四槽组存在空闲候选
    wire [SEARCH_BANK_COUNT-1:0] send_bank_found_w; // 标记各四槽组存在发送候选
    wire [1:0] free_bank_offset_w [0:SEARCH_BANK_COUNT-1]; // 保存各组最低编号空闲槽偏移
    wire [1:0] send_bank_offset_w [0:SEARCH_BANK_COUNT-1]; // 保存各组最低编号发送槽偏移
    reg free_found_d; // 标记关联扫描找到空闲槽
    integer free_index_d; // 保存最低编号空闲槽
    wire duplicate_issue_d; // 标记事务标识仍在保留或复用保护期
    wire commit_found_d; // 标记确认精确匹配保留事务
    wire [ENTRY_COUNT-1:0] commit_match_d; // 并行标记唯一精确匹配的确认事务槽
    reg [ENTRY_COUNT-1:0] commit_match_pending_q; // 流水保存并保留当前确认精确匹配事务槽
    reg send_found_d; // 标记关联扫描找到待发送事务
    integer send_index_d; // 保存最低编号待发送事务槽
    reg send_valid_q; // 保存反压稳定的发送命令有效位
    integer send_index_q; // 保存已寄存发送命令事务槽
    reg [63:0] send_transaction_id_q; // 保存已寄存发送事务标识
    reg [15:0] send_topology_epoch_q; // 保存已寄存发送拓扑代次
    reg [3:0] send_retry_count_q; // 保存已寄存发送重试次数
    reg issue_pending_q; // 标记一个已经握手的新事务正在分配流水中
    integer pending_issue_index_q; // 保存流水新事务的目标空闲槽
    reg [63:0] pending_issue_transaction_id_q; // 保存流水新事务标识
    reg [15:0] pending_issue_topology_epoch_q; // 保存流水新事务拓扑代次
    reg [15:0] pending_issue_timeout_quanta_q; // 保存流水新事务超时门限
    reg issue_probe_valid_q; // 标记一个 valid/ready 请求正在准入探测流水中
    reg [63:0] probe_issue_transaction_id_q; // 保存准入探测事务标识
    reg [15:0] probe_issue_topology_epoch_q; // 保存准入探测拓扑代次
    reg [15:0] probe_issue_timeout_quanta_q; // 保存准入探测超时门限
    reg issue_admission_valid_q; // 标记准入探测结果已经寄存并可返回 ready
    reg issue_admission_accept_q; // 保存请求容量、身份和超时合同准入结果
    integer issue_admission_index_q; // 保存已准入请求的目标空闲槽
    reg commit_pending_valid_q; // 标记一个确认事件正在判定流水中
    reg [63:0] pending_commit_transaction_id_q; // 保存流水确认事务标识
    reg [1:0] pending_commit_status_q; // 保存流水确认提交状态
    wire issue_fire; // 标记新事务完成输入握手
    wire issue_allocate; // 标记流水新事务在本周期写入保留槽
    wire send_fire; // 标记发送命令完成输出握手
    wire commit_success; // 标记确认完整身份、代次和状态匹配
    integer scan_i; // 声明关联和时序扫描变量
    integer bank_scan_i; // 声明分级搜索组扫描变量
    genvar candidate_g; // 声明并行事务条件生成循环变量
    genvar bank_g; // 声明四槽局部搜索组生成循环变量
    assign issue_ready_o = issue_admission_valid_q && issue_admission_accept_q && !issue_pending_q; // 仅返回已经流水判定且分配级空闲的请求许可
    assign issue_fire = issue_valid_i && issue_ready_o; // 汇总新事务输入握手
    assign issue_allocate = issue_pending_q; // 上周期握手的新事务在本周期写入保留槽
    assign send_valid_o = send_valid_q; // 输出已寄存发送命令有效位
    assign send_transaction_id_o = send_transaction_id_q; // 输出已寄存事务标识
    assign send_topology_epoch_o = send_topology_epoch_q; // 输出已寄存拓扑代次
    assign send_retry_count_o = send_retry_count_q; // 输出已寄存重试次数
    assign send_fire = send_valid_q && send_ready_i; // 汇总发送命令握手
    assign commit_success = commit_pending_valid_q && (|commit_match_pending_q) && (pending_commit_status_q == `KDL_GLOBAL_STATUS_COMMITTED); // 仅流水后精确匹配的已提交确认完成事务
    generate // 并行展开全部事务槽条件避免跨二十槽串行依赖
        for (candidate_g = 0; candidate_g < ENTRY_COUNT; candidate_g = candidate_g + 1) begin : g_transaction_candidate // 生成单槽独立比较条件
            assign free_candidate_w[candidate_g] = !valid_q[candidate_g] && (reuse_cooldown_q[candidate_g] == 16'd0); // 标记完全空闲槽
            assign duplicate_candidate_w[candidate_g] = (valid_q[candidate_g] || (reuse_cooldown_q[candidate_g] != 16'd0)) && (transaction_id_q[candidate_g] == probe_issue_transaction_id_q); // 标记准入探测请求的重复身份
            assign commit_match_d[candidate_g] = valid_q[candidate_g] && !commit_match_pending_q[candidate_g] && (transaction_id_q[candidate_g] == commit_transaction_id_i) && (topology_epoch_q[candidate_g] == commit_topology_epoch_i); // 标记未被前级确认保留的精确确认身份
            assign send_candidate_w[candidate_g] = valid_q[candidate_g] && send_pending_q[candidate_g]; // 标记待发送槽
            assign retry_exhaust_candidate_w[candidate_g] = valid_q[candidate_g] && (retry_count_q[candidate_g] == 4'hf) && (route_reset_i || (!send_pending_q[candidate_g] && (timeout_remaining_q[candidate_g] <= 16'd1))); // 标记单槽预算耗尽
        end // 结束单槽独立条件生成
        for (bank_g = 0; bank_g < SEARCH_BANK_COUNT; bank_g = bank_g + 1) begin : g_transaction_search_bank // 生成四槽局部优先编码器
            wire [3:0] local_free_w; // 保存当前搜索组空闲条件
            wire [3:0] local_send_w; // 保存当前搜索组发送条件
            if (bank_g*SEARCH_BANK_SIZE + 0 < ENTRY_COUNT) begin : g_candidate_0
                assign local_free_w[0] = free_candidate_w[bank_g*SEARCH_BANK_SIZE+0]; assign local_send_w[0] = send_candidate_w[bank_g*SEARCH_BANK_SIZE+0];
            end else begin : g_no_candidate_0
                assign local_free_w[0] = 1'b0; assign local_send_w[0] = 1'b0;
            end
            if (bank_g*SEARCH_BANK_SIZE + 1 < ENTRY_COUNT) begin : g_candidate_1
                assign local_free_w[1] = free_candidate_w[bank_g*SEARCH_BANK_SIZE+1]; assign local_send_w[1] = send_candidate_w[bank_g*SEARCH_BANK_SIZE+1];
            end else begin : g_no_candidate_1
                assign local_free_w[1] = 1'b0; assign local_send_w[1] = 1'b0;
            end
            if (bank_g*SEARCH_BANK_SIZE + 2 < ENTRY_COUNT) begin : g_candidate_2
                assign local_free_w[2] = free_candidate_w[bank_g*SEARCH_BANK_SIZE+2]; assign local_send_w[2] = send_candidate_w[bank_g*SEARCH_BANK_SIZE+2];
            end else begin : g_no_candidate_2
                assign local_free_w[2] = 1'b0; assign local_send_w[2] = 1'b0;
            end
            if (bank_g*SEARCH_BANK_SIZE + 3 < ENTRY_COUNT) begin : g_candidate_3
                assign local_free_w[3] = free_candidate_w[bank_g*SEARCH_BANK_SIZE+3]; assign local_send_w[3] = send_candidate_w[bank_g*SEARCH_BANK_SIZE+3];
            end else begin : g_no_candidate_3
                assign local_free_w[3] = 1'b0; assign local_send_w[3] = 1'b0;
            end
            assign free_bank_found_w[bank_g] = |local_free_w; // 平衡归约当前组空闲条件
            assign send_bank_found_w[bank_g] = |local_send_w; // 平衡归约当前组发送条件
            assign free_bank_offset_w[bank_g] = local_free_w[0] ? 2'd0 : local_free_w[1] ? 2'd1 : local_free_w[2] ? 2'd2 : 2'd3; // 仅在四槽内部选择最低编号空闲槽
            assign send_bank_offset_w[bank_g] = local_send_w[0] ? 2'd0 : local_send_w[1] ? 2'd1 : local_send_w[2] ? 2'd2 : 2'd3; // 仅在四槽内部选择最低编号发送槽
        end // 结束四槽搜索组生成
    endgenerate // 结束并行事务搜索结构
    assign duplicate_issue_d = |duplicate_candidate_w; // 平衡归约全部重复身份比较
    assign commit_found_d = |commit_match_d; // 平衡归约全部确认身份比较
    always @(*) begin // 在较少的四槽组之间选择最低编号候选
        free_found_d = 1'b0; // 默认没有空闲槽
        free_index_d = 0; // 默认空闲槽编号为零
        send_found_d = 1'b0; // 默认没有待发送事务
        send_index_d = 0; // 默认发送槽编号为零
        for (bank_scan_i = 0; bank_scan_i < SEARCH_BANK_COUNT; bank_scan_i = bank_scan_i + 1) begin // 扫描显著缩短后的搜索组结果
            if (free_bank_found_w[bank_scan_i] && !free_found_d) begin // 捕获最低编号非空搜索组
                free_found_d = 1'b1; // 记录已经找到空闲槽
                free_index_d = bank_scan_i*SEARCH_BANK_SIZE + {30'd0, free_bank_offset_w[bank_scan_i]}; // 合成完整空闲槽编号
            end // 结束空闲槽捕获
            if (send_bank_found_w[bank_scan_i] && !send_found_d) begin // 捕获最低编号非空发送搜索组
                send_found_d = 1'b1; // 记录已经找到发送候选
                send_index_d = bank_scan_i*SEARCH_BANK_SIZE + {30'd0, send_bank_offset_w[bank_scan_i]}; // 合成完整发送槽编号
            end // 结束发送候选捕获
        end // 结束搜索组扫描
    end // 结束事务窗口组合查找
    always @(posedge clk_i or negedge rst_n_i) begin // 更新事务表、发送寄存器和公共状态
        if (!rst_n_i) begin // 硬复位开始新的端到端协议会话
            completion_valid_o <= 1'b0; // 清除源端完成脉冲
            completion_transaction_id_o <= 64'd0; // 清零完成事务标识
            protocol_error_o <= 1'b0; // 清除协议 sticky 错误
            retry_exhausted_o <= 1'b0; // 清除重试耗尽 sticky 错误
            retry_exhaust_pending_q <= {ENTRY_COUNT{1'b0}}; // 清除预算耗尽事件流水
            duplicate_issue_pending_q <= {ENTRY_COUNT{1'b0}}; // 清除重复签发比较流水
            window_overflow_o <= 1'b0; // 清除窗口溢出 sticky 错误
            outstanding_count_o <= 9'd0; // 清零保留事务数量
            send_valid_q <= 1'b0; // 清除发送命令有效位
            send_index_q <= 0; // 清零发送命令槽编号
            send_transaction_id_q <= 64'd0; // 清零发送事务标识
            send_topology_epoch_q <= 16'd0; // 清零发送拓扑代次
            send_retry_count_q <= 4'd0; // 清零发送重试次数
            issue_pending_q <= 1'b0; // 清除新事务分配流水
            pending_issue_index_q <= 0; // 清零流水目标空闲槽
            pending_issue_transaction_id_q <= 64'd0; // 清零流水事务标识
            pending_issue_topology_epoch_q <= 16'd0; // 清零流水拓扑代次
            pending_issue_timeout_quanta_q <= 16'd0; // 清零流水超时门限
            issue_probe_valid_q <= 1'b0; // 清除请求准入探测流水
            probe_issue_transaction_id_q <= 64'd0; // 清零探测事务标识
            probe_issue_topology_epoch_q <= 16'd0; // 清零探测拓扑代次
            probe_issue_timeout_quanta_q <= 16'd0; // 清零探测超时门限
            issue_admission_valid_q <= 1'b0; // 清除寄存准入结果
            issue_admission_accept_q <= 1'b0; // 清除准入接受判定
            issue_admission_index_q <= 0; // 清零准入目标空闲槽
            commit_pending_valid_q <= 1'b0; // 清除确认判定流水
            commit_match_pending_q <= {ENTRY_COUNT{1'b0}}; // 清除流水确认匹配和槽保留
            pending_commit_transaction_id_q <= 64'd0; // 清零流水确认事务标识
            pending_commit_status_q <= 2'd0; // 清零流水确认提交状态
            for (scan_i = 0; scan_i < ENTRY_COUNT; scan_i = scan_i + 1) begin // 清除全部事务槽
                valid_q[scan_i] <= 1'b0; // 清除当前事务槽有效位
                send_pending_q[scan_i] <= 1'b0; // 清除当前事务待发送状态
                transaction_id_q[scan_i] <= 64'd0; // 清零当前事务标识
                topology_epoch_q[scan_i] <= 16'd0; // 清零当前拓扑代次
                timeout_quanta_q[scan_i] <= 16'd0; // 清零当前超时门限
                timeout_remaining_q[scan_i] <= 16'd0; // 清零当前剩余超时周期
                retry_count_q[scan_i] <= 4'd0; // 清零当前重试次数
                reuse_cooldown_q[scan_i] <= 16'd0; // 清零当前标识复用保护
            end // 结束事务槽复位扫描
        end else begin // 正常推进源事务窗口
            completion_valid_o <= commit_success; // 仅合法已提交确认产生一次性完成脉冲
            retry_exhaust_pending_q <= retry_exhaust_candidate_w; // 在单槽条件后建立归约流水边界
            duplicate_issue_pending_q <= duplicate_candidate_w & {ENTRY_COUNT{issue_probe_valid_q && !issue_admission_valid_q}}; // 在单槽探测身份比较后建立重复事件流水边界
            issue_pending_q <= issue_fire; // 仅将已经握手的新事务装入分配流水
            if (!issue_probe_valid_q && !issue_admission_valid_q && issue_valid_i) begin // 捕获一个保持到 ready 的新事务请求
                issue_probe_valid_q <= 1'b1; // 标记下周期执行容量和身份准入判定
                probe_issue_transaction_id_q <= issue_transaction_id_i; // 保存完整事务标识
                probe_issue_topology_epoch_q <= issue_topology_epoch_i; // 保存拓扑代次
                probe_issue_timeout_quanta_q <= issue_timeout_quanta_i; // 保存超时门限
            end // 结束准入探测请求捕获
            if (issue_probe_valid_q && !issue_admission_valid_q) begin // 寄存稳定请求的完整准入判定
                issue_admission_valid_q <= 1'b1; // 标记准入结果可返回给请求方
                issue_admission_accept_q <= free_found_d && !duplicate_issue_d && (probe_issue_timeout_quanta_q != 16'd0); // 保存容量、身份和超时合同结果
                issue_admission_index_q <= free_index_d; // 保存判定时选中的空闲槽
            end // 结束请求准入判定寄存
            if (issue_fire) begin // 捕获稳定的新事务分配上下文
                pending_issue_index_q <= issue_admission_index_q; // 保存已准入目标空闲槽
                pending_issue_transaction_id_q <= probe_issue_transaction_id_q; // 保存探测流水完整事务标识
                pending_issue_topology_epoch_q <= probe_issue_topology_epoch_q; // 保存探测流水拓扑代次
                pending_issue_timeout_quanta_q <= probe_issue_timeout_quanta_q; // 保存探测流水超时门限
                issue_probe_valid_q <= 1'b0; // 完成 valid/ready 握手后释放探测请求
                issue_admission_valid_q <= 1'b0; // 消耗当前准入结果
            end else if (issue_admission_valid_q && !issue_valid_i) begin // 请求方撤销未获许可的非法或溢出请求
                issue_probe_valid_q <= 1'b0; // 释放被撤销的探测请求
                issue_admission_valid_q <= 1'b0; // 丢弃已观察的拒绝结果
            end // 结束新事务分配上下文捕获
            commit_pending_valid_q <= commit_valid_i; // 将每个确认事件装入一级判定流水
            commit_match_pending_q <= commit_valid_i ? commit_match_d : {ENTRY_COUNT{1'b0}}; // 流水保存精确匹配并为背靠背确认保留目标槽
            if (commit_valid_i) begin // 捕获稳定的确认上下文
                pending_commit_transaction_id_q <= commit_transaction_id_i; // 保存确认事务标识
                pending_commit_status_q <= commit_status_i; // 保存确认提交状态
            end // 结束确认上下文捕获
            if (commit_success) completion_transaction_id_o <= pending_commit_transaction_id_q; // 保存流水后已完成事务标识
            if ((|duplicate_issue_pending_q) || (commit_pending_valid_q && !commit_success)) protocol_error_o <= 1'b1; // sticky 报告流水后的重复签发或非法确认
            if (issue_probe_valid_q && !issue_admission_valid_q && !free_found_d && !duplicate_issue_d && (probe_issue_timeout_quanta_q != 16'd0)) window_overflow_o <= 1'b1; // sticky 仅报告探测确认的真实容量不足
            if (|retry_exhaust_pending_q) retry_exhausted_o <= 1'b1; // sticky 报告流水后的任一事务重试耗尽
            if (issue_allocate && !commit_success) outstanding_count_o <= outstanding_count_o + 9'd1; // 仅流水新事务写入时增加保留数量
            else if (!issue_allocate && commit_success) outstanding_count_o <= outstanding_count_o - 9'd1; // 仅事务完成时减少保留数量
            if (route_reset_i || (commit_success && send_valid_q && (send_transaction_id_q == pending_commit_transaction_id_q))) send_valid_q <= 1'b0; // 换路或对应流水事务完成时撤销旧发送命令
            else if (send_fire) send_valid_q <= 1'b0; // 发送命令握手后释放输出寄存器
            else if (!send_valid_q && send_found_d) begin // 空闲输出寄存器捕获下一待发送事务
                send_valid_q <= 1'b1; // 标记寄存发送命令有效
                send_index_q <= send_index_d; // 保存发送事务槽编号
                send_transaction_id_q <= transaction_id_q[send_index_d]; // 保存发送事务标识
                send_topology_epoch_q <= topology_epoch_q[send_index_d]; // 保存发送拓扑代次
                send_retry_count_q <= retry_count_q[send_index_d]; // 保存发送重试次数
            end // 结束发送命令捕获
            for (scan_i = 0; scan_i < ENTRY_COUNT; scan_i = scan_i + 1) begin // 独占更新每个事务槽
                if (valid_q[scan_i]) begin // 推进当前活动事务
                    if (route_reset_i) begin // 路由软复位使全部未完成事务换代重发
                        topology_epoch_q[scan_i] <= route_topology_epoch_i; // 更新到新提交拓扑代次
                        timeout_remaining_q[scan_i] <= 16'd0; // 清零换路等待倒计时
                        if (retry_count_q[scan_i] != 4'hf) begin // 仍有端到端重试预算
                            retry_count_q[scan_i] <= retry_count_q[scan_i] + 4'd1; // 增加换路重试次数
                            send_pending_q[scan_i] <= 1'b1; // 重新置为待发送状态
                        end // 结束可重试换路处理
                    end else if (commit_success && commit_match_pending_q[scan_i]) begin // 流水精确确认直接释放唯一事务
                        valid_q[scan_i] <= 1'b0; // 释放已完成事务槽
                        send_pending_q[scan_i] <= 1'b0; // 清除已完成事务发送状态
                        timeout_remaining_q[scan_i] <= 16'd0; // 清零等待倒计时
                        reuse_cooldown_q[scan_i] <= REPLAY_GRACE_CYCLES; // 启动相同事务标识复用保护期
                    end else if (send_fire && (send_index_q == scan_i)) begin // 当前发送命令被下游接受
                        send_pending_q[scan_i] <= 1'b0; // 转入等待目的端确认状态
                        timeout_remaining_q[scan_i] <= timeout_quanta_q[scan_i]; // 从完整超时门限开始确认等待倒计时
                    end else if (!send_pending_q[scan_i]) begin // 等待确认期间推进超时
                        if (timeout_remaining_q[scan_i] <= 16'd1) begin // 到达事务超时门限
                            timeout_remaining_q[scan_i] <= 16'd0; // 清零等待倒计时以开始下一次尝试
                            if (retry_count_q[scan_i] != 4'hf) begin // 仍有重试预算时重新发送
                                retry_count_q[scan_i] <= retry_count_q[scan_i] + 4'd1; // 增加超时重试次数
                                send_pending_q[scan_i] <= 1'b1; // 重新置为待发送状态
                            end // 结束可重试超时处理
                        end else timeout_remaining_q[scan_i] <= timeout_remaining_q[scan_i] - 16'd1; // 未超时时递减剩余等待周期
                    end // 结束确认等待处理
                end else if (issue_allocate && (pending_issue_index_q == scan_i)) begin // 捕获流水分配到当前槽的新事务
                    valid_q[scan_i] <= 1'b1; // 占用当前空闲事务槽
                    send_pending_q[scan_i] <= 1'b1; // 新事务立即进入待发送状态
                    transaction_id_q[scan_i] <= pending_issue_transaction_id_q; // 保存流水完整事务标识
                    topology_epoch_q[scan_i] <= pending_issue_topology_epoch_q; // 保存流水十六位拓扑代次
                    timeout_quanta_q[scan_i] <= pending_issue_timeout_quanta_q; // 保存流水超时门限
                    timeout_remaining_q[scan_i] <= 16'd0; // 清零等待倒计时
                    retry_count_q[scan_i] <= 4'd0; // 清零重试次数
                    reuse_cooldown_q[scan_i] <= 16'd0; // 保持新事务槽无旧保护倒计时
                end else if (reuse_cooldown_q[scan_i] != 16'd0) reuse_cooldown_q[scan_i] <= reuse_cooldown_q[scan_i] - 16'd1; // 空闲槽逐周期递减标识复用保护
            end // 结束全部事务槽更新
        end // 结束正常事务窗口推进
    end // 结束源事务窗口时序逻辑
endmodule // 结束 kdlink_transaction_window
