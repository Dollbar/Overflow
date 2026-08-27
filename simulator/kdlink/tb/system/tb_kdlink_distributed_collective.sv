`timescale 1ns/1ps // 定义分布式通信组与树控制自检时间单位
module tb_kdlink_distributed_collective; // 定义原子组代次和六类有界子树操作自检
    logic clk; // 产生组目录和控制器时钟
    logic rst_n; // 驱动低有效复位
    logic config_valid; // 驱动组目录配置请求
    logic [1:0] config_action; // 驱动 prepare、commit 或 invalidate 动作
    logic [3:0] config_index; // 驱动物理组目录条目
    logic [31:0] config_group_id; // 驱动全局通信组标识
    logic [15:0] config_epoch; // 驱动通信组拓扑代次
    logic [7:0] config_child_mask; // 驱动当前节点八子树掩码
    logic [31:0] config_local_mask; // 驱动 leaf 本地成员掩码
    logic [20:0] config_member_count; // 驱动子树成员总数
    logic [19:0] config_root_endpoint; // 驱动二十位通信组根端点
    logic query_valid; // 驱动活动组目录查询
    logic [31:0] query_group_id; // 驱动查询组标识
    logic [15:0] query_epoch; // 驱动查询拓扑代次
    wire query_found; // 观察活动条目精确命中
    wire [7:0] query_child_mask; // 观察活动八子树掩码
    wire [31:0] query_local_mask; // 观察活动 leaf 本地掩码
    wire [20:0] query_member_count; // 观察活动子树成员总数
    wire [19:0] query_root_endpoint; // 观察活动根端点
    wire [2:0] query_level; // 观察当前节点层次
    wire config_error; // 观察目录配置 sticky 错误
    wire leaf_query_found; // 观察 leaf 目录活动键命中
    wire [31:0] leaf_query_local_mask; // 观察 leaf 目录本地成员掩码
    wire [2:0] leaf_query_level; // 观察 leaf 目录冻结层次
    wire leaf_config_error; // 观察 leaf 目录配置 sticky 错误
    logic descriptor_valid; // 驱动集合通信描述符
    wire descriptor_ready; // 观察描述符许可
    logic [2:0] descriptor_opcode; // 驱动六类操作编码
    logic [14:0] descriptor_destination_domain; // 驱动点对点目的 leaf 域
    wire command_valid; // 观察树阶段命令有效位
    logic command_ready; // 驱动树阶段命令许可
    wire [2:0] command_phase; // 观察树阶段编码
    wire [2:0] command_opcode; // 观察冻结操作编码
    wire [2:0] command_child; // 观察当前子树编号
    wire [31:0] command_local_mask; // 观察冻结的leaf本地成员掩码
    wire [31:0] command_group_id; // 观察冻结通信组标识
    wire [63:0] command_transaction_id; // 观察冻结事务标识
    wire [15:0] command_epoch; // 观察冻结拓扑代次
    wire busy; // 观察树控制器忙状态
    wire descriptor_error; // 观察描述符 sticky 错误
    logic [31:0] descriptor_group_id; // 驱动可翻转描述符组标识
    logic [63:0] descriptor_transaction_id; // 驱动可翻转描述符事务标识
    logic [15:0] descriptor_epoch; // 驱动可翻转描述符拓扑代次
    logic control_group_found; // 驱动控制器目录命中状态
    logic [7:0] control_child_mask; // 驱动控制器当前层子树掩码
    logic [31:0] control_local_mask; // 驱动控制器 leaf 本地成员掩码
    logic [20:0] control_member_count; // 驱动控制器子树成员总数
    logic [19:0] control_root_endpoint; // 驱动控制器根端点
    logic [2:0] control_level; // 驱动控制器当前层级
    integer opcode_index; // 遍历全部六类操作
    integer command_count; // 统计当前操作命令总数
    integer gather_count; // 统计向根汇聚子树命令数
    integer scatter_count; // 统计向下分发子树命令数
    integer exchange_count; // 统计子树交换命令数
    integer watchdog; // 限制树操作等待周期
    logic [31:0] irregular_leaf_mask [0:4]; // 保存二三三十三七十八和一万五千一百三十二NPU规模的末叶掩码
    integer irregular_leaf_count [0:4]; // 保存各不规则规模末叶有效成员数
    kdlink_group_directory #(.ENTRY_COUNT(16), .INDEX_WIDTH(4), .NODE_LEVEL(0)) u_directory ( // 实例化根级有界组目录
        .clk_i(clk), .rst_n_i(rst_n), .config_valid_i(config_valid), .config_ready_o(), // 连接时钟、复位和配置握手
        .config_action_i(config_action), .config_index_i(config_index), // 连接配置动作和物理条目
        .config_group_id_i(config_group_id), .config_topology_epoch_i(config_epoch), // 连接通信组精确键
        .config_child_mask_i(config_child_mask), .config_local_member_mask_i(config_local_mask), // 连接有界内部或 leaf 掩码
        .config_subtree_member_count_i(config_member_count), .config_root_endpoint_i(config_root_endpoint), // 连接成员总数和根端点
        .query_valid_i(query_valid), .query_group_id_i(query_group_id), .query_topology_epoch_i(query_epoch), // 连接活动目录查询
        .query_found_o(query_found), .query_child_mask_o(query_child_mask), .query_local_member_mask_o(query_local_mask), // 观察命中和成员掩码
        .query_subtree_member_count_o(query_member_count), .query_root_endpoint_o(query_root_endpoint), .query_level_o(query_level), // 观察活动目录元数据
        .config_error_o(config_error) // 观察配置 sticky 错误
    ); // 结束根级组目录实例
    kdlink_group_directory #(.ENTRY_COUNT(1), .INDEX_WIDTH(1), .NODE_LEVEL(5)) u_leaf_directory ( // 实例化最小 leaf 目录以验证层次互斥合同
        .clk_i(clk), .rst_n_i(rst_n), .config_valid_i(config_valid), .config_ready_o(), // 复用配置时序并独立检查 leaf payload
        .config_action_i(config_action), .config_index_i(config_index[0]), // 将物理条目限制到单槽 leaf 目录
        .config_group_id_i(config_group_id), .config_topology_epoch_i(config_epoch), // 连接 leaf 通信组精确键
        .config_child_mask_i(config_child_mask), .config_local_member_mask_i(config_local_mask), // 连接互斥子树与本地成员掩码
        .config_subtree_member_count_i(config_member_count), .config_root_endpoint_i(config_root_endpoint), // 连接 leaf 成员总数和根端点
        .query_valid_i(query_valid), .query_group_id_i(query_group_id), .query_topology_epoch_i(query_epoch), // 连接活动 leaf 查询
        .query_found_o(leaf_query_found), .query_child_mask_o(), .query_local_member_mask_o(leaf_query_local_mask), // 观察 leaf 命中和本地掩码
        .query_subtree_member_count_o(), .query_root_endpoint_o(), .query_level_o(leaf_query_level), // 观察冻结 leaf 层级
        .config_error_o(leaf_config_error) // 观察 leaf 非法配置 sticky 错误
    ); // 结束最小 leaf 目录实例
    kdlink_collective_tree_ctrl u_controller ( // 实例化六类分布式树操作控制器
        .clk_i(clk), .rst_n_i(rst_n), .descriptor_valid_i(descriptor_valid), .descriptor_ready_o(descriptor_ready), // 连接描述符握手
        .descriptor_opcode_i(descriptor_opcode), .descriptor_group_id_i(descriptor_group_id), // 连接操作和可变通信组标识
        .descriptor_transaction_id_i(descriptor_transaction_id), .descriptor_topology_epoch_i(descriptor_epoch), // 连接可变事务和拓扑代次
        .descriptor_destination_domain_i(descriptor_destination_domain), // 连接点对点目的域
        .group_found_i(control_group_found), .group_child_mask_i(control_child_mask), .group_local_member_mask_i(control_local_mask), // 连接可控目录查询结果
        .group_subtree_member_count_i(control_member_count), .group_root_endpoint_i(control_root_endpoint), .group_level_i(control_level), // 连接可控目录元数据
        .command_valid_o(command_valid), .command_ready_i(command_ready), .command_phase_o(command_phase), // 连接树阶段命令握手
        .command_opcode_o(command_opcode), .command_child_o(command_child), .command_local_member_mask_o(command_local_mask), // 观察操作、子树编号和leaf成员掩码
        .command_group_id_o(command_group_id), .command_transaction_id_o(command_transaction_id), // 观察冻结组和事务标识
        .command_topology_epoch_o(command_epoch), .command_subtree_member_count_o(), .command_root_endpoint_o(), // 观察冻结代次
        .busy_o(busy), .descriptor_error_o(descriptor_error) // 观察控制状态
    ); // 结束树控制器实例
    always #0.5 clk = ~clk; // 产生一纳秒时钟周期
    task automatic configure_action(input [1:0] action_value); // 发送一个组目录配置动作
        begin // 开始单周期配置请求
            @(negedge clk); config_action = action_value; config_valid = 1'b1; // 驱动配置动作
            @(negedge clk); config_valid = 1'b0; #0.1; // 完成配置并等待查询传播
            @(negedge clk); #0.1; // 等待一级目录配置流水完成动作判定
        end // 结束配置请求
    endtask // 结束 configure_action
    task automatic run_operation(input [2:0] opcode_value, input integer expected_commands, input integer expected_gather, input integer expected_scatter, input integer expected_exchange); // 执行并检查一种树操作
        begin // 开始描述符和阶段计数
            command_ready = 1'b0; descriptor_opcode = opcode_value; descriptor_valid = 1'b1; #0.1; // 反压首命令并驱动待接受描述符
            if (!descriptor_ready) $fatal(1, "tree controller was not ready for descriptor"); // 要求操作间控制器返回空闲
            @(posedge clk); #0.1; descriptor_valid = 1'b0; // 跨过明确上升沿后完成描述符握手
            command_count = 0; gather_count = 0; scatter_count = 0; exchange_count = 0; watchdog = 0; // 清零当前操作统计
            #0.1; // 等待描述符握手后的 leaf 准备命令稳定
            if (!command_valid || command_phase != 3'd0) $fatal(1, "tree controller did not emit leaf prepare phase busy=%0d error=%0d found=%0d level=%0d child=%02x", busy, descriptor_error, query_found, query_level, query_child_mask); // 要求每类操作均先准备现有 leaf 数据面
            if ((control_level == 3'd5) && (command_local_mask != control_local_mask)) $fatal(1, "tree controller changed irregular leaf membership mask"); // 要求部分叶域只有有效NPU参与集合操作
            @(posedge clk); #0.1; // 保持一周期反压以验证准备状态稳定等待
            if (!command_valid || command_phase != 3'd0 || !busy) $fatal(1, "tree controller did not hold prepare command under backpressure"); // 要求 ready 关闭时不推进状态
            command_count = command_count + 1; // 计入即将在下一上升沿握手的 leaf 准备命令
            command_ready = 1'b1; // 完成观察后允许全部树命令无反压执行
            while ((busy || descriptor_valid) && (watchdog < 80)) begin // 等待有界树操作完成
                @(posedge clk); #0.1; // 在时钟后观察完成握手的命令
                if (command_valid && command_ready) begin // 统计当前树阶段命令
                    command_count = command_count + 1; // 增加命令总数
                    if (command_phase == 3'd1) gather_count = gather_count + 1; // 统计 gather 子树命令
                    if (command_phase == 3'd2) scatter_count = scatter_count + 1; // 统计 scatter 子树命令
                    if (command_phase == 3'd3) exchange_count = exchange_count + 1; // 统计 exchange 子树命令
                    if ((command_phase >= 3'd1) && (command_phase <= 3'd3) && (opcode_value != 3'd5) && !control_child_mask[command_child]) $fatal(1, "tree controller emitted command for nonmember child"); // 要求非 P2P 操作仅访问目录标记子树
                    if (command_opcode != opcode_value || command_group_id != descriptor_group_id || command_transaction_id != descriptor_transaction_id || command_epoch != descriptor_epoch) $fatal(1, "tree controller did not freeze descriptor identity"); // 要求完整操作身份稳定
                end // 结束命令统计
                watchdog = watchdog + 1; // 推进等待上限
            end // 结束树操作等待
            if (watchdog >= 80 || command_count != expected_commands || gather_count != expected_gather || scatter_count != expected_scatter || exchange_count != expected_exchange) $fatal(1, "distributed tree operation phase count mismatch opcode=%0d commands=%0d", opcode_value, command_count); // 要求六类操作使用预期有界阶段
        end // 结束一种树操作检查
    endtask // 结束 run_operation
    initial begin // 执行影子提交、查询和六类操作测试
        clk = 1'b0; rst_n = 1'b0; config_valid = 1'b0; config_action = 2'd0; config_index = 4'd3; // 初始化时钟、复位和配置动作
        config_group_id = 32'h1234_5678; config_epoch = 16'h0200; config_child_mask = 8'b1000_0101; config_local_mask = 32'd0; // 初始化根级三个成员子树
        config_member_count = 21'd1_000_000; config_root_endpoint = 20'habcde; // 驱动百万级子树计数和二十位根端点
        query_valid = 1'b1; query_group_id = 32'h1234_5678; query_epoch = 16'h0200; // 持续查询待提交精确键
        descriptor_valid = 1'b0; descriptor_opcode = 3'd0; descriptor_destination_domain = 15'h7000; command_ready = 1'b1; // 初始化树控制接口并令 P2P 选择七号子树
        descriptor_group_id = 32'h1234_5678; descriptor_transaction_id = 64'h0123_4567_89ab_cdef; descriptor_epoch = 16'h0200; // 初始化可冻结描述符身份
        control_group_found = 1'b1; control_child_mask = 8'b1000_0101; control_local_mask = 32'd0; control_member_count = 21'd1_000_000; // 初始化根级控制目录形状
        control_root_endpoint = 20'habcde; control_level = 3'd0; // 初始化控制器根端点和根层级
        command_count = 0; gather_count = 0; scatter_count = 0; exchange_count = 0; watchdog = 0; // 清零测试统计
        irregular_leaf_mask[0] = 32'h00000003; irregular_leaf_count[0] = 2; // 定义总规模二NPU的完整单叶掩码
        irregular_leaf_mask[1] = 32'h00000007; irregular_leaf_count[1] = 3; // 定义总规模三NPU的完整单叶掩码
        irregular_leaf_mask[2] = 32'h00000001; irregular_leaf_count[2] = 1; // 定义总规模三十三NPU的末叶掩码
        irregular_leaf_mask[3] = 32'h00003fff; irregular_leaf_count[3] = 14; // 定义总规模七十八NPU的末叶掩码
        irregular_leaf_mask[4] = 32'h0fffffff; irregular_leaf_count[4] = 28; // 定义总规模一万五千一百三十二NPU的末叶掩码
        repeat (3) @(negedge clk); rst_n = 1'b1; #0.1; // 释放硬复位
        configure_action(2'd0); // prepare 新组代次到影子 bank
        if (query_found) $fatal(1, "prepared group generation became visible before commit"); // 要求 prepare 不改变活动查询
        configure_action(2'd1); // 原子提交影子组代次
        if (!query_found || query_child_mask != 8'b1000_0101 || query_local_mask != 32'd0 || query_member_count != 21'd1_000_000 || query_root_endpoint != 20'habcde || query_level != 3'd0) $fatal(1, "committed distributed group directory mismatch"); // 要求活动查询返回全部有界字段
        for (opcode_index = 0; opcode_index < 3; opcode_index = opcode_index + 1) begin // 检查三类双遍集合操作并翻转冻结上下文
            descriptor_group_id = opcode_index[0] ? 32'haaaa_aaaa : 32'h5555_5555; descriptor_transaction_id = opcode_index[0] ? 64'haaaa_aaaa_aaaa_aaaa : 64'h5555_5555_5555_5555; descriptor_epoch = opcode_index[0] ? 16'ha55a : 16'h5aa5; // 为每类操作驱动互补身份
            run_operation(opcode_index[2:0], 9, 3, 3, 0); // 要求 RS、AG、AR 各遍历三子树两遍
        end // 结束双遍操作覆盖
        descriptor_group_id = 32'h0f0f_f0f0; descriptor_transaction_id = 64'h0f0f_f0f0_a5a5_5a5a; descriptor_epoch = 16'h0ff0; run_operation(3'd3, 6, 0, 0, 3); // 检查 AllToAll 遍历三子树一次
        descriptor_group_id = 32'hf0f0_0f0f; descriptor_transaction_id = 64'hf0f0_0f0f_5a5a_a5a5; descriptor_epoch = 16'hf00f; run_operation(3'd4, 6, 0, 0, 3); // 检查 AllToAllV 遍历三子树一次
        descriptor_group_id = 32'hffff_0000; descriptor_transaction_id = 64'hffff_0000_ffff_0000; descriptor_epoch = 16'hffff; run_operation(3'd5, 4, 0, 0, 1); // 检查 P2P 仅遍历目的七号子树一次
        if (descriptor_error || config_error) $fatal(1, "valid distributed collective raised sticky error"); // 要求全部合法操作无错误
        for (opcode_index = 0; opcode_index < 16; opcode_index = opcode_index + 1) begin // 第一轮覆盖根目录全部十六个物理槽
            config_index = opcode_index[3:0]; config_group_id = 32'haaaa_aaa0 ^ opcode_index[31:0]; config_epoch = 16'ha550 ^ opcode_index[15:0]; // 驱动高位图样活动键
            config_child_mask = 8'ha5 ^ opcode_index[7:0]; config_local_mask = 32'd0; config_member_count = 21'h155555 ^ opcode_index[20:0]; config_root_endpoint = 20'haaaa0 ^ opcode_index[19:0]; // 驱动第一轮有界根目录载荷
            configure_action(2'd0); configure_action(2'd1); // 依次准备并提交当前物理槽
        end // 结束第一轮根目录填充
        for (opcode_index = 0; opcode_index < 16; opcode_index = opcode_index + 1) begin // 第二轮用互补字段覆盖全部根目录槽
            config_index = opcode_index[3:0]; config_group_id = 32'h5555_5550 ^ opcode_index[31:0]; config_epoch = 16'h5aa0 ^ opcode_index[15:0]; // 驱动互补活动键
            config_child_mask = 8'h5a ^ opcode_index[7:0]; config_local_mask = 32'd0; config_member_count = 21'h0aaaaa ^ opcode_index[20:0]; config_root_endpoint = 20'h55550 ^ opcode_index[19:0]; // 驱动第二轮有界根目录载荷
            configure_action(2'd0); configure_action(2'd1); // 原子替换当前物理槽
            query_group_id = config_group_id; query_epoch = config_epoch; #0.1; // 查询刚提交的精确键
            if (!query_found || query_child_mask != config_child_mask || query_member_count != config_member_count || query_root_endpoint != config_root_endpoint) $fatal(1, "bulk root directory replacement mismatch"); // 要求每个槽的互补字段可见
        end // 结束第二轮根目录覆盖
        config_index = 4'd1; config_group_id = 32'h5555_5550; config_epoch = 16'h5aa0; config_child_mask = 8'h3c; config_local_mask = 32'd0; config_member_count = 21'h12345; config_root_endpoint = 20'h54321; // 准备复制零号槽的活动键
        configure_action(2'd0); configure_action(2'd1); // 尝试将重复活动键提交到另一物理槽
        if (!config_error) $fatal(1, "duplicate active group key was accepted"); // 要求活动键全目录唯一
        config_index = 4'd15; configure_action(2'd2); // 显式失效一个活动目录槽
        query_group_id = 32'h5555_555f; query_epoch = 16'h5aaf; #0.1; // 查询已经失效的十五号键
        if (query_found) $fatal(1, "invalidated group directory entry remained visible"); // 要求 invalidate 同时关闭活动与影子 bank
        configure_action(2'd3); // 注入保留配置动作编码
        if (!config_error) $fatal(1, "reserved group directory action was accepted"); // 要求非法动作维持 sticky 错误
        config_index = 4'd0; config_group_id = 32'hffff_ffff; config_epoch = 16'hffff; config_child_mask = 8'd0; config_local_mask = 32'hffff_ffff; config_member_count = 21'h1fffff; config_root_endpoint = 20'hfffff; // 驱动单槽 leaf 目录全位翻转载荷
        query_group_id = config_group_id; query_epoch = config_epoch; configure_action(2'd0); configure_action(2'd1); // 准备、提交并查询 leaf 条目
        if (!leaf_query_found || leaf_query_local_mask != 32'hffff_ffff || leaf_query_level != 3'd5) $fatal(1, "leaf group directory contract mismatch"); // 要求 leaf 仅保存本地成员位图
        for (opcode_index = 0; opcode_index < 5; opcode_index = opcode_index + 1) begin // 逐项验证五个不规则总规模对应的完整或末叶成员形状
            config_group_id = 32'h1357_0000 + opcode_index[31:0]; config_epoch = 16'h2400 + opcode_index[15:0]; // 为当前不规则末叶生成唯一活动键
            config_child_mask = 8'd0; config_local_mask = irregular_leaf_mask[opcode_index]; config_member_count = irregular_leaf_count[opcode_index][20:0]; config_root_endpoint = 20'd0; // 驱动精确有效成员掩码和计数
            query_group_id = config_group_id; query_epoch = config_epoch; configure_action(2'd0); configure_action(2'd1); // 原子替换、提交并查询当前leaf条目
            if (!leaf_query_found || leaf_query_local_mask != irregular_leaf_mask[opcode_index] || leaf_query_level != 3'd5) $fatal(1, "irregular leaf group mask mismatch case=%0d", opcode_index); // 要求目录不引入未配置NPU成员
            control_level = 3'd5; control_child_mask = 8'd0; control_local_mask = irregular_leaf_mask[opcode_index]; control_member_count = irregular_leaf_count[opcode_index][20:0]; // 将同一部分成员形状送入树控制器
            descriptor_group_id = config_group_id; descriptor_transaction_id = 64'h1513_2000_0000_0000 + {32'd0, opcode_index[31:0]}; descriptor_epoch = config_epoch; // 驱动当前不规则规模集合操作身份
            run_operation(3'd0, 3, 0, 0, 0); // 要求部分leaf只执行本地准备、完成和提交且保持成员掩码
        end // 结束五个不规则规模leaf成员验证
        control_child_mask = 8'h80; control_local_mask = 32'd0; control_member_count = 21'h155555; control_root_endpoint = 20'ha5a5a; // 切换为逐层 P2P 单子树目录
        for (opcode_index = 0; opcode_index < 5; opcode_index = opcode_index + 1) begin // 覆盖五个 radix-8 内部层次的目的数位选择
            control_level = opcode_index[2:0]; descriptor_destination_domain = (15'd7 << ((4-opcode_index)*3)); // 令当前层目的数位选择七号子树
            descriptor_group_id = 32'ha5a5_5a5a ^ opcode_index[31:0]; descriptor_transaction_id = 64'ha5a5_5a5a_f0f0_0f0f ^ {32'd0, opcode_index[31:0]}; descriptor_epoch = 16'ha55a ^ opcode_index[15:0]; // 驱动逐层变化描述符身份
            run_operation(3'd5, 4, 0, 0, 1); // 要求每个内部层 P2P 仅生成一个交换子树命令
        end // 结束五级内部层次遍历
        control_level = 3'd5; control_child_mask = 8'd0; control_local_mask = 32'hffff_ffff; control_member_count = 21'h1fffff; control_root_endpoint = 20'hfffff; descriptor_destination_domain = 15'h7fff; // 切换到全位翻转 leaf 本地成员形状
        descriptor_group_id = 32'hffff_ffff; descriptor_transaction_id = 64'hffff_ffff_ffff_ffff; descriptor_epoch = 16'hffff; run_operation(3'd0, 3, 0, 0, 0); // 要求 leaf collective 仅执行准备、完成和提交
        run_operation(3'd5, 3, 0, 0, 0); // 要求 leaf P2P 同样不产生远端子树命令
        descriptor_opcode = 3'd7; descriptor_valid = 1'b1; #0.1; @(posedge clk); #0.1; descriptor_valid = 1'b0; // 注入保留操作码描述符
        if (!descriptor_error || busy) $fatal(1, "invalid collective descriptor was not rejected"); // 要求非法描述符 sticky 报错且不启动操作
        rst_n = 1'b0; repeat (2) @(negedge clk); // 最终复位覆盖双 bank 目录和冻结控制上下文清零
        $display("TB_KDLINK_DISTRIBUTED_COLLECTIVE_PASS irregular_totals=2,3,33,78,15132 final_leaf_members=2,3,1,14,28"); // 输出不规则规模通信组验证通过签名
        $finish; // 结束自校验仿真
    end // 结束主测试序列
endmodule // 结束 tb_kdlink_distributed_collective
