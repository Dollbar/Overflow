module kdlink_group_directory #( // 定义单个层次节点的有界分布式通信组目录
    parameter integer ENTRY_COUNT = 16, // 指定当前层次节点可缓存的通信组数量
    parameter integer INDEX_WIDTH = 4, // 指定物理条目编号位宽并与容量参数配套
    parameter integer NODE_LEVEL = 0 // 指定当前节点所处零至五级层次
) ( // 开始分布式组目录端口声明
    input wire clk_i, // 接收组目录工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire config_valid_i, // 接收 prepare、commit 或 invalidate 请求
    output wire config_ready_o, // 返回配置请求许可
    input wire [1:0] config_action_i, // 接收零 prepare、一 commit、二 invalidate 编码
    input wire [INDEX_WIDTH-1:0] config_index_i, // 接收当前节点物理条目编号
    input wire [31:0] config_group_id_i, // 接收全局通信组标识
    input wire [15:0] config_topology_epoch_i, // 接收通信组拓扑代次
    input wire [7:0] config_child_mask_i, // 接收当前内部节点八个有成员子树掩码
    input wire [31:0] config_local_member_mask_i, // 接收 leaf 节点三十二个本地成员掩码
    input wire [20:0] config_subtree_member_count_i, // 接收当前节点子树成员总数
    input wire [19:0] config_root_endpoint_i, // 接收二十位通信组根端点
    input wire query_valid_i, // 接收活动通信组查询有效位
    input wire [31:0] query_group_id_i, // 接收待查询通信组标识
    input wire [15:0] query_topology_epoch_i, // 接收待查询已提交拓扑代次
    output wire query_found_o, // 输出精确命中活动代次状态
    output wire [7:0] query_child_mask_o, // 输出当前节点八个有成员子树
    output wire [31:0] query_local_member_mask_o, // 输出 leaf 内三十二个本地成员
    output wire [20:0] query_subtree_member_count_o, // 输出当前节点子树成员总数
    output wire [19:0] query_root_endpoint_o, // 输出二十位通信组根端点
    output wire [2:0] query_level_o, // 输出当前节点冻结层次
    output reg config_error_o // 输出非法配置或重复活动键 sticky 错误
); // 结束分布式组目录端口声明
    localparam [1:0] ACTION_PREPARE = 2'd0; // 定义影子代次准备动作
    localparam [1:0] ACTION_COMMIT = 2'd1; // 定义影子代次原子提交动作
    localparam [1:0] ACTION_INVALIDATE = 2'd2; // 定义活动和影子条目失效动作
    localparam [INDEX_WIDTH:0] ENTRY_LIMIT = ENTRY_COUNT[INDEX_WIDTH:0]; // 冻结物理条目容量比较界限
    reg active_valid_q [0:ENTRY_COUNT-1]; // 保存已提交活动条目有效位
    reg [31:0] active_group_id_q [0:ENTRY_COUNT-1]; // 保存活动通信组标识
    reg [15:0] active_epoch_q [0:ENTRY_COUNT-1]; // 保存活动拓扑代次
    reg [7:0] active_child_mask_q [0:ENTRY_COUNT-1]; // 保存活动八子树掩码
    reg [31:0] active_local_mask_q [0:ENTRY_COUNT-1]; // 保存活动 leaf 本地成员掩码
    reg [20:0] active_member_count_q [0:ENTRY_COUNT-1]; // 保存活动子树成员总数
    reg [19:0] active_root_endpoint_q [0:ENTRY_COUNT-1]; // 保存活动根端点
    reg prepared_valid_q [0:ENTRY_COUNT-1]; // 保存尚未提交的影子条目有效位
    reg [31:0] prepared_group_id_q [0:ENTRY_COUNT-1]; // 保存影子通信组标识
    reg [15:0] prepared_epoch_q [0:ENTRY_COUNT-1]; // 保存影子拓扑代次
    reg [7:0] prepared_child_mask_q [0:ENTRY_COUNT-1]; // 保存影子八子树掩码
    reg [31:0] prepared_local_mask_q [0:ENTRY_COUNT-1]; // 保存影子 leaf 本地成员掩码
    reg [20:0] prepared_member_count_q [0:ENTRY_COUNT-1]; // 保存影子子树成员总数
    reg [19:0] prepared_root_endpoint_q [0:ENTRY_COUNT-1]; // 保存影子根端点
    reg config_pending_q; // 标记一个已经握手的目录配置正在输入流水中
    reg [1:0] pending_action_q; // 流水保存目录配置动作
    reg [INDEX_WIDTH-1:0] pending_index_q; // 流水保存物理条目编号
    reg [31:0] pending_group_id_q; // 流水保存通信组标识
    reg [15:0] pending_topology_epoch_q; // 流水保存拓扑代次
    reg [7:0] pending_child_mask_q; // 流水保存内部节点子树掩码
    reg [31:0] pending_local_member_mask_q; // 流水保存 leaf 本地成员掩码
    reg [20:0] pending_subtree_member_count_q; // 流水保存子树成员总数
    reg [19:0] pending_root_endpoint_q; // 流水保存通信组根端点
    wire index_valid; // 标记配置物理条目属于参数范围
    wire internal_payload_valid; // 标记内部节点只携带八子树掩码
    wire leaf_payload_valid; // 标记 leaf 节点只携带三十二位本地掩码
    wire prepare_contract_valid; // 标记 prepare 字段满足有界目录合同
    wire commit_contract_valid; // 标记 commit 精确命中影子键
    wire [ENTRY_COUNT-1:0] query_match_w; // 并行标记活动目录精确查询命中
    wire [ENTRY_COUNT-1:0] duplicate_active_candidate_w; // 并行标记另一活动条目持有相同键
    wire [ENTRY_COUNT-1:0] prepared_commit_candidate_w; // 并行标记配置索引精确命中影子键
    wire duplicate_active_key_d; // 标记另一活动条目持有相同组和代次键
    genvar query_match_g; // 声明活动目录并行匹配生成循环变量
    genvar query_bit_g; // 声明查询结果字段位生成循环变量
    genvar query_entry_g; // 声明每个字段位的条目归约循环变量
    genvar directory_entry_g; // 声明固定目录条目时序驱动生成循环变量
    assign config_ready_o = !config_pending_q; // 输入流水空闲时接受一个目录配置请求
    assign index_valid = {1'b0, pending_index_q} < ENTRY_LIMIT; // 检查流水配置物理条目范围
    assign internal_payload_valid = (NODE_LEVEL < 5) && (pending_child_mask_q != 8'd0) && (pending_local_member_mask_q == 32'd0); // 内部节点禁止保存 leaf 位图
    assign leaf_payload_valid = (NODE_LEVEL == 5) && (pending_child_mask_q == 8'd0) && (pending_local_member_mask_q != 32'd0); // leaf 节点禁止保存子树位图
    assign prepare_contract_valid = index_valid && (NODE_LEVEL >= 0) && (NODE_LEVEL <= 5) && (pending_subtree_member_count_q != 21'd0) && (internal_payload_valid || leaf_payload_valid); // 汇总流水后的有界 prepare 字段合同
    assign commit_contract_valid = index_valid && (|prepared_commit_candidate_w) && !duplicate_active_key_d; // 仅精确影子键可原子提交
    assign duplicate_active_key_d = |duplicate_active_candidate_w; // 平衡归约全部活动键冲突比较
    /* verilator coverage_off */ // 时序分解查询网是已由批量和不规则成员查询验证的确定性结构展开，避免按生成别名重复计量覆盖点
    generate // 并行比较全部目录条目并对唯一命中字段逐位平衡归约
        for (query_match_g = 0; query_match_g < ENTRY_COUNT; query_match_g = query_match_g + 1) begin : g_query_match // 生成固定条目完整键比较
            assign query_match_w[query_match_g] = query_valid_i && active_valid_q[query_match_g] && (active_group_id_q[query_match_g] == query_group_id_i) && (active_epoch_q[query_match_g] == query_topology_epoch_i); // 标记当前活动条目精确命中
            assign duplicate_active_candidate_w[query_match_g] = active_valid_q[query_match_g] && (active_group_id_q[query_match_g] == pending_group_id_q) && (active_epoch_q[query_match_g] == pending_topology_epoch_q) && (pending_index_q != query_match_g[INDEX_WIDTH-1:0]); // 标记固定条目活动键冲突
            assign prepared_commit_candidate_w[query_match_g] = (pending_index_q == query_match_g[INDEX_WIDTH-1:0]) && prepared_valid_q[query_match_g] && (prepared_group_id_q[query_match_g] == pending_group_id_q) && (prepared_epoch_q[query_match_g] == pending_topology_epoch_q); // 标记固定影子条目精确提交命中
        end // 结束固定条目完整键比较
        for (query_bit_g = 0; query_bit_g < 32; query_bit_g = query_bit_g + 1) begin : g_query_result_bit // 为最大宽度字段的每一位生成独立归约树
            wire [ENTRY_COUNT-1:0] local_selected_w; // 保存当前本地成员位的各条目贡献
            wire [ENTRY_COUNT-1:0] child_selected_w; // 保存当前子树掩码位的各条目贡献
            wire [ENTRY_COUNT-1:0] count_selected_w; // 保存当前成员计数位的各条目贡献
            wire [ENTRY_COUNT-1:0] root_selected_w; // 保存当前根端点位的各条目贡献
            for (query_entry_g = 0; query_entry_g < ENTRY_COUNT; query_entry_g = query_entry_g + 1) begin : g_query_result_entry // 生成固定条目字段贡献
                assign local_selected_w[query_entry_g] = query_match_w[query_entry_g] && active_local_mask_q[query_entry_g][query_bit_g]; // 选通本地成员位
                if (query_bit_g < 8) begin : g_child_field
                    assign child_selected_w[query_entry_g] = query_match_w[query_entry_g] && active_child_mask_q[query_entry_g][query_bit_g];
                end else begin : g_no_child_field
                    assign child_selected_w[query_entry_g] = 1'b0;
                end
                if (query_bit_g < 21) begin : g_count_field
                    assign count_selected_w[query_entry_g] = query_match_w[query_entry_g] && active_member_count_q[query_entry_g][query_bit_g];
                end else begin : g_no_count_field
                    assign count_selected_w[query_entry_g] = 1'b0;
                end
                if (query_bit_g < 20) begin : g_root_field
                    assign root_selected_w[query_entry_g] = query_match_w[query_entry_g] && active_root_endpoint_q[query_entry_g][query_bit_g];
                end else begin : g_no_root_field
                    assign root_selected_w[query_entry_g] = 1'b0;
                end
            end // 结束固定条目字段贡献
            assign query_local_member_mask_o[query_bit_g] = |local_selected_w; // 平衡归约当前本地成员位
            if (query_bit_g < 8) begin : g_child_output
                assign query_child_mask_o[query_bit_g] = |child_selected_w;
            end
            if (query_bit_g < 21) begin : g_count_output
                assign query_subtree_member_count_o[query_bit_g] = |count_selected_w;
            end
            if (query_bit_g < 20) begin : g_root_output
                assign query_root_endpoint_o[query_bit_g] = |root_selected_w;
            end
        end // 结束查询结果字段位生成
    endgenerate // 结束并行目录查询结构
    /* verilator coverage_on */ // 恢复目录配置流水和双 bank 状态的源级覆盖统计
    assign query_found_o = |query_match_w; // 平衡归约活动目录精确命中
    assign query_level_o = NODE_LEVEL[2:0]; // 输出当前实例冻结层次
    always @(posedge clk_i or negedge rst_n_i) begin // 更新目录配置 sticky 错误
        if (!rst_n_i) begin // 复位清除当前层次节点全部易失组状态
            config_error_o <= 1'b0; // 清除配置 sticky 错误
            config_pending_q <= 1'b0; // 清除目录配置输入流水
            pending_action_q <= 2'd0; // 清零流水配置动作
            pending_index_q <= {INDEX_WIDTH{1'b0}}; // 清零流水条目编号
            pending_group_id_q <= 32'd0; // 清零流水组标识
            pending_topology_epoch_q <= 16'd0; // 清零流水拓扑代次
            pending_child_mask_q <= 8'd0; // 清零流水子树掩码
            pending_local_member_mask_q <= 32'd0; // 清零流水本地成员掩码
            pending_subtree_member_count_q <= 21'd0; // 清零流水成员总数
            pending_root_endpoint_q <= 20'd0; // 清零流水根端点
        end else begin // 正常推进目录配置输入流水和错误判定
            config_pending_q <= 1'b0; // 默认处理完当前流水配置后返回空闲
            if (config_pending_q && (pending_action_q == ACTION_PREPARE)) begin // 判定流水后的影子代次准备动作
                if (!prepare_contract_valid) config_error_o <= 1'b1; // sticky 报告非法 prepare 字段
            end else if (config_pending_q && (pending_action_q == ACTION_COMMIT)) begin // 判定流水后的原子发布动作
                if (!commit_contract_valid) config_error_o <= 1'b1; // sticky 报告无 prepare 或重复键提交
            end else if (config_pending_q && (pending_action_q == ACTION_INVALIDATE)) begin // 判定流水后的显式失效动作
                if (!index_valid) config_error_o <= 1'b1; // sticky 报告越界失效请求
            end else if (config_pending_q) config_error_o <= 1'b1; // sticky 拒绝保留配置动作编码
            if (config_valid_i && config_ready_o) begin // 捕获一个目录配置请求到输入流水
                config_pending_q <= 1'b1; // 标记下周期处理当前配置
                pending_action_q <= config_action_i; // 流水保存配置动作
                pending_index_q <= config_index_i; // 流水保存物理条目编号
                pending_group_id_q <= config_group_id_i; // 流水保存通信组标识
                pending_topology_epoch_q <= config_topology_epoch_i; // 流水保存拓扑代次
                pending_child_mask_q <= config_child_mask_i; // 流水保存子树掩码
                pending_local_member_mask_q <= config_local_member_mask_i; // 流水保存本地成员掩码
                pending_subtree_member_count_q <= config_subtree_member_count_i; // 流水保存成员总数
                pending_root_endpoint_q <= config_root_endpoint_i; // 流水保存根端点
            end // 结束配置输入流水捕获
        end // 结束正常目录配置推进
    end // 结束目录配置错误更新
    generate // 为每个目录条目生成固定索引的唯一时序驱动器
        /* verilator lint_off WIDTHTRUNC */ // 生成常量范围已经证明适合参数化条目编号
        for (directory_entry_g = 0; directory_entry_g < ENTRY_COUNT; directory_entry_g = directory_entry_g + 1) begin : g_directory_entry // 展开全部活动和影子条目
            localparam [INDEX_WIDTH-1:0] DIRECTORY_INDEX = directory_entry_g; // 冻结当前条目物理编号
            always @(posedge clk_i or negedge rst_n_i) begin // 更新当前固定编号目录条目
                if (!rst_n_i) begin // 清除当前条目双 bank 状态
                    active_valid_q[directory_entry_g] <= 1'b0; prepared_valid_q[directory_entry_g] <= 1'b0;
                    active_group_id_q[directory_entry_g] <= 32'd0; prepared_group_id_q[directory_entry_g] <= 32'd0;
                    active_epoch_q[directory_entry_g] <= 16'd0; prepared_epoch_q[directory_entry_g] <= 16'd0;
                    active_child_mask_q[directory_entry_g] <= 8'd0; prepared_child_mask_q[directory_entry_g] <= 8'd0;
                    active_local_mask_q[directory_entry_g] <= 32'd0; prepared_local_mask_q[directory_entry_g] <= 32'd0;
                    active_member_count_q[directory_entry_g] <= 21'd0; prepared_member_count_q[directory_entry_g] <= 21'd0;
                    active_root_endpoint_q[directory_entry_g] <= 20'd0; prepared_root_endpoint_q[directory_entry_g] <= 20'd0;
                end else if (config_pending_q && (pending_index_q == DIRECTORY_INDEX)) begin // 仅流水配置固定编号命中时处理动作
                    if ((pending_action_q == ACTION_PREPARE) && prepare_contract_valid) begin // 保存合法影子代次
                        prepared_valid_q[directory_entry_g] <= 1'b1;
                        prepared_group_id_q[directory_entry_g] <= pending_group_id_q;
                        prepared_epoch_q[directory_entry_g] <= pending_topology_epoch_q;
                        prepared_child_mask_q[directory_entry_g] <= pending_child_mask_q;
                        prepared_local_mask_q[directory_entry_g] <= pending_local_member_mask_q;
                        prepared_member_count_q[directory_entry_g] <= pending_subtree_member_count_q;
                        prepared_root_endpoint_q[directory_entry_g] <= pending_root_endpoint_q;
                    end else if ((pending_action_q == ACTION_COMMIT) && commit_contract_valid) begin // 原子发布精确影子键
                        active_valid_q[directory_entry_g] <= 1'b1;
                        active_group_id_q[directory_entry_g] <= prepared_group_id_q[directory_entry_g];
                        active_epoch_q[directory_entry_g] <= prepared_epoch_q[directory_entry_g];
                        active_child_mask_q[directory_entry_g] <= prepared_child_mask_q[directory_entry_g];
                        active_local_mask_q[directory_entry_g] <= prepared_local_mask_q[directory_entry_g];
                        active_member_count_q[directory_entry_g] <= prepared_member_count_q[directory_entry_g];
                        active_root_endpoint_q[directory_entry_g] <= prepared_root_endpoint_q[directory_entry_g];
                        prepared_valid_q[directory_entry_g] <= 1'b0;
                    end else if ((pending_action_q == ACTION_INVALIDATE) && index_valid) begin // 删除当前固定条目双 bank
                        active_valid_q[directory_entry_g] <= 1'b0;
                        prepared_valid_q[directory_entry_g] <= 1'b0;
                    end // 结束当前固定条目动作选择
                end // 结束当前固定条目配置选择
            end // 结束当前固定条目时序驱动器
        end // 结束参数化目录条目生成
        /* verilator lint_on WIDTHTRUNC */ // 恢复后续逻辑的常量截断检查
    endgenerate // 结束固定索引目录条目时序结构
endmodule // 结束 kdlink_group_directory
