`include "kdlink_defs.vh" // 引入全局提交状态编码
module kdlink_commit_window #( // 定义可参数化百万端点目的端完成历史窗口
    parameter integer ENTRY_COUNT = 64, // 指定同时受保护的完成历史条目数量
    parameter [15:0] REPLAY_GRACE_CYCLES = 16'd65535 // 指定完成身份抵御迟到重放的保护周期
) ( // 开始目的端完成历史窗口端口声明
    input wire clk_i, // 接收完成历史工作时钟
    input wire rst_n_i, // 接收低有效异步硬复位
    input wire route_reset_i, // 接收不得清除完成历史的路由软复位事件
    input wire commit_valid_i, // 接收本地消费者原子提交事件
    output wire commit_ready_o, // 返回提交事件接收许可
    input wire [14:0] source_domain_i, // 接收十五位原事务源域
    input wire [14:0] destination_domain_i, // 接收十五位原事务目的域
    input wire [4:0] source_node_i, // 接收原事务源节点
    input wire [4:0] destination_node_i, // 接收原事务目的节点
    input wire [15:0] topology_epoch_i, // 接收本次到达使用的拓扑代次
    input wire [63:0] global_transaction_id_i, // 接收六十四位全局事务标识
    output reg deliver_valid_o, // 输出仅首次提交时有效的本地交付脉冲
    output reg [63:0] deliver_transaction_id_o, // 输出首次交付的事务标识
    output reg global_ack_valid_o, // 输出首次或重复到达均产生的确认脉冲
    output reg [14:0] global_ack_source_domain_o, // 输出确认对应的原事务源域
    output reg [14:0] global_ack_destination_domain_o, // 输出确认对应的原事务目的域
    output reg [4:0] global_ack_source_node_o, // 输出确认对应的原事务源节点
    output reg [4:0] global_ack_destination_node_o, // 输出确认对应的原事务目的节点
    output reg [15:0] global_ack_topology_epoch_o, // 输出确认沿用的到达拓扑代次
    output reg [63:0] global_ack_transaction_id_o, // 输出确认对应的事务标识
    output reg [1:0] global_ack_status_o, // 输出全局提交状态
    output reg duplicate_seen_o, // 输出观察到重复事务的 sticky 状态
    output reg window_overflow_o, // 输出历史窗口无可替换条目的 sticky 状态
    output reg [8:0] history_count_o // 输出当前已占用的完成历史条目数量
); // 结束目的端完成历史窗口端口声明
    reg history_valid_q [0:ENTRY_COUNT-1]; // 保存参数化完成历史有效位
    reg [103:0] history_identity_q [0:ENTRY_COUNT-1]; // 保存二十位源目的端点与事务标识
    reg [15:0] history_age_q [0:ENTRY_COUNT-1]; // 保存每条完成历史保护年龄
    reg history_replaceable_q [0:ENTRY_COUNT-1]; // 保存每条历史已经越过重放保护期的流水状态
    localparam integer SEARCH_BANK_SIZE = 4; // 将宽历史搜索拆成四槽局部编码组
    localparam integer SEARCH_BANK_COUNT = (ENTRY_COUNT + SEARCH_BANK_SIZE - 1) / SEARCH_BANK_SIZE; // 计算参数化搜索组数量
    wire [103:0] current_identity; // 拼接当前输入的完整 exact-once 身份
    wire [ENTRY_COUNT-1:0] match_candidate_w; // 并行标记相同完成身份
    wire [ENTRY_COUNT-1:0] free_candidate_w; // 并行标记空闲或过期历史条目
    wire [SEARCH_BANK_COUNT-1:0] free_bank_found_w; // 标记各四槽组存在可替换条目
    wire [1:0] free_bank_offset_w [0:SEARCH_BANK_COUNT-1]; // 保存各组最低编号可替换条目偏移
    wire match_found_d; // 标记组合扫描找到相同完成身份
    reg free_found_d; // 标记组合扫描找到空闲或过期条目
    integer free_index_d; // 保存最低编号可替换条目
    reg pending_valid_q; // 标记一个已经握手的完成事件正在提交流水中
    reg pending_duplicate_q; // 保存流水完成事件是否命中受保护历史
    integer pending_free_index_q; // 保存流水首次完成事件的目标历史条目
    reg [103:0] pending_identity_q; // 保存流水完成事件的完整 exact-once 身份
    reg [15:0] pending_topology_epoch_q; // 保存流水完成事件的到达拓扑代次
    wire commit_fire; // 标记当前提交事件被接受
    wire new_commit_fire; // 标记首次完成事件被接受
    wire duplicate_commit_fire; // 标记重复完成事件被接受
    wire unused_route_reset; // 显式记录软复位不清除 exact-once 历史
    integer scan_i; // 声明组合和时序扫描变量
    integer bank_scan_i; // 声明分级搜索组扫描变量
    genvar candidate_g; // 声明并行历史条件生成循环变量
    genvar bank_g; // 声明四槽局部搜索组生成循环变量
    assign current_identity = {global_transaction_id_i, destination_node_i, source_node_i, destination_domain_i, source_domain_i}; // 形成不含路由代次的端到端完成身份
    assign commit_ready_o = !pending_valid_q && (match_found_d || free_found_d); // 提交流水空闲且重复身份或存在可替换条目时接受提交
    assign commit_fire = commit_valid_i && commit_ready_o; // 汇总提交输入握手
    assign new_commit_fire = pending_valid_q && !pending_duplicate_q; // 区分流水后的首次完成
    assign duplicate_commit_fire = pending_valid_q && pending_duplicate_q; // 区分流水后的跨 epoch 重复到达
    assign unused_route_reset = route_reset_i; // 声明路由软复位仅用于可观测性而不破坏历史
    generate // 并行展开身份比较并建立四槽局部可替换编码器
        for (candidate_g = 0; candidate_g < ENTRY_COUNT; candidate_g = candidate_g + 1) begin : g_history_candidate // 生成单条历史独立条件
            assign match_candidate_w[candidate_g] = history_valid_q[candidate_g] && !history_replaceable_q[candidate_g] && (history_identity_q[candidate_g] == current_identity); // 标记保护期内完整身份匹配
            assign free_candidate_w[candidate_g] = !history_valid_q[candidate_g] || history_replaceable_q[candidate_g]; // 标记空闲或已经流水确认保护期满的条目
        end // 结束单条历史条件生成
        for (bank_g = 0; bank_g < SEARCH_BANK_COUNT; bank_g = bank_g + 1) begin : g_history_search_bank // 生成四槽局部优先编码器
            wire [3:0] local_free_w; // 保存当前搜索组可替换条件
            if (bank_g*SEARCH_BANK_SIZE + 0 < ENTRY_COUNT) begin : g_candidate_0
                assign local_free_w[0] = free_candidate_w[bank_g*SEARCH_BANK_SIZE+0];
            end else begin : g_no_candidate_0
                assign local_free_w[0] = 1'b0;
            end
            if (bank_g*SEARCH_BANK_SIZE + 1 < ENTRY_COUNT) begin : g_candidate_1
                assign local_free_w[1] = free_candidate_w[bank_g*SEARCH_BANK_SIZE+1];
            end else begin : g_no_candidate_1
                assign local_free_w[1] = 1'b0;
            end
            if (bank_g*SEARCH_BANK_SIZE + 2 < ENTRY_COUNT) begin : g_candidate_2
                assign local_free_w[2] = free_candidate_w[bank_g*SEARCH_BANK_SIZE+2];
            end else begin : g_no_candidate_2
                assign local_free_w[2] = 1'b0;
            end
            if (bank_g*SEARCH_BANK_SIZE + 3 < ENTRY_COUNT) begin : g_candidate_3
                assign local_free_w[3] = free_candidate_w[bank_g*SEARCH_BANK_SIZE+3];
            end else begin : g_no_candidate_3
                assign local_free_w[3] = 1'b0;
            end
            assign free_bank_found_w[bank_g] = |local_free_w; // 平衡归约当前组可替换条件
            assign free_bank_offset_w[bank_g] = local_free_w[0] ? 2'd0 : local_free_w[1] ? 2'd1 : local_free_w[2] ? 2'd2 : 2'd3; // 仅在四槽内部选择最低编号条目
        end // 结束四槽搜索组生成
    endgenerate // 结束并行历史搜索结构
    assign match_found_d = |match_candidate_w; // 平衡归约全部完整身份比较
    always @(*) begin // 在较少的四槽组之间选择最低编号可替换条目
        free_found_d = 1'b0; // 默认历史窗口已满
        free_index_d = 0; // 默认可替换条目编号为零
        for (bank_scan_i = 0; bank_scan_i < SEARCH_BANK_COUNT; bank_scan_i = bank_scan_i + 1) begin // 扫描显著缩短后的搜索组结果
            if (free_bank_found_w[bank_scan_i] && !free_found_d) begin // 捕获最低编号非空搜索组
                free_found_d = 1'b1; // 记录已经找到可替换条目
                free_index_d = bank_scan_i*SEARCH_BANK_SIZE + {30'd0, free_bank_offset_w[bank_scan_i]}; // 合成完整可替换条目编号
            end // 结束可替换条目捕获
        end // 结束搜索组扫描
    end // 结束完成历史组合查找
    always @(posedge clk_i or negedge rst_n_i) begin // 更新完成历史、确认脉冲和 sticky 状态
        if (!rst_n_i) begin // 硬复位开始新的 exact-once 协议会话
            deliver_valid_o <= 1'b0; // 清除首次交付脉冲
            deliver_transaction_id_o <= 64'd0; // 清零首次交付事务标识
            global_ack_valid_o <= 1'b0; // 清除全局确认脉冲
            global_ack_source_domain_o <= 15'd0; // 清零确认源域
            global_ack_destination_domain_o <= 15'd0; // 清零确认目的域
            global_ack_source_node_o <= 5'd0; // 清零确认源节点
            global_ack_destination_node_o <= 5'd0; // 清零确认目的节点
            global_ack_topology_epoch_o <= 16'd0; // 清零确认拓扑代次
            global_ack_transaction_id_o <= 64'd0; // 清零确认事务标识
            global_ack_status_o <= `KDL_GLOBAL_STATUS_COMMITTED; // 复位确认状态为已提交编码
            duplicate_seen_o <= 1'b0; // 清除重复事务 sticky 状态
            window_overflow_o <= 1'b0; // 清除历史窗口溢出 sticky 状态
            history_count_o <= 9'd0; // 清零已占用历史数量
            pending_valid_q <= 1'b0; // 清除完成事件提交流水
            pending_duplicate_q <= 1'b0; // 清除流水重复状态
            pending_free_index_q <= 0; // 清零流水目标历史条目
            pending_identity_q <= 104'd0; // 清零流水完整身份
            pending_topology_epoch_q <= 16'd0; // 清零流水拓扑代次
            for (scan_i = 0; scan_i < ENTRY_COUNT; scan_i = scan_i + 1) begin // 清除全部历史有效位和内容
                history_valid_q[scan_i] <= 1'b0; // 清除当前历史有效位
                history_identity_q[scan_i] <= 104'd0; // 清零当前历史身份
                history_age_q[scan_i] <= 16'd0; // 清零当前历史年龄
                history_replaceable_q[scan_i] <= 1'b0; // 清除当前历史保护期满状态
            end // 结束历史复位扫描
        end else begin // 正常推进完成历史
            pending_valid_q <= commit_fire; // 仅将已经握手的完成事件装入提交流水
            if (commit_fire) begin // 捕获当前完成事件的稳定流水上下文
                pending_duplicate_q <= match_found_d; // 保存当前事件是否为保护期内重复
                pending_free_index_q <= free_index_d; // 保存首次事件的目标历史条目
                pending_identity_q <= current_identity; // 保存完整 exact-once 身份
                pending_topology_epoch_q <= topology_epoch_i; // 保存到达拓扑代次
            end // 结束完成事件流水捕获
            deliver_valid_o <= new_commit_fire; // 仅首次身份产生本地交付脉冲
            global_ack_valid_o <= pending_valid_q; // 首次和重复流水身份均返回确认
            if (pending_valid_q) begin // 捕获流水确认所需完整返回身份
                global_ack_source_domain_o <= pending_identity_q[14:0]; // 返回原事务源域
                global_ack_destination_domain_o <= pending_identity_q[29:15]; // 返回原事务目的域
                global_ack_source_node_o <= pending_identity_q[34:30]; // 返回原事务源节点
                global_ack_destination_node_o <= pending_identity_q[39:35]; // 返回原事务目的节点
                global_ack_topology_epoch_o <= pending_topology_epoch_q; // 返回本次到达使用的拓扑代次
                global_ack_transaction_id_o <= pending_identity_q[103:40]; // 返回全局事务标识
                global_ack_status_o <= `KDL_GLOBAL_STATUS_COMMITTED; // 报告目的端已经提交
            end // 结束确认身份捕获
            if (new_commit_fire) begin // 保存首次完成身份并产生一次性交付
                history_valid_q[pending_free_index_q] <= 1'b1; // 占用流水选定历史条目
                history_identity_q[pending_free_index_q] <= pending_identity_q; // 保存流水完整端点事务身份
                history_age_q[pending_free_index_q] <= 16'd0; // 从零开始保护新完成身份
                history_replaceable_q[pending_free_index_q] <= 1'b0; // 新身份重新进入受保护状态
                deliver_transaction_id_o <= pending_identity_q[103:40]; // 输出首次交付事务标识
                if (!history_valid_q[pending_free_index_q]) history_count_o <= history_count_o + 9'd1; // 仅占用空闲条目时增加已占用数量
            end // 结束首次完成处理
            if (duplicate_commit_fire) duplicate_seen_o <= 1'b1; // sticky 记录任一重复到达
            if (commit_valid_i && !pending_valid_q && !match_found_d && !free_found_d) window_overflow_o <= 1'b1; // sticky 仅记录真实保护窗口容量不足而不把流水忙误报为溢出
            for (scan_i = 0; scan_i < ENTRY_COUNT; scan_i = scan_i + 1) begin // 推进除本周期新写条目外的历史年龄
                if (history_valid_q[scan_i] && !(new_commit_fire && (pending_free_index_q == scan_i)) && !history_replaceable_q[scan_i]) begin // 推进尚未越过保护期的历史年龄
                    if (history_age_q[scan_i] + 16'd1 >= REPLAY_GRACE_CYCLES) history_replaceable_q[scan_i] <= 1'b1; // 在独立时序边界记录保护期满
                    else history_age_q[scan_i] <= history_age_q[scan_i] + 16'd1; // 未到保护期时推进年龄
                end // 结束历史保护年龄推进
            end // 结束历史年龄扫描
        end // 结束正常完成历史推进
    end // 结束目的端完成历史时序逻辑
endmodule // 结束 kdlink_commit_window
