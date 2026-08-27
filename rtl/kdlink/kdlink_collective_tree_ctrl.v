`include "kdlink_defs.vh" // 引入六类 KDLink 操作冻结编码
module kdlink_collective_tree_ctrl ( // 定义仅遍历八个本地子树的分布式集合通信控制器
    input wire clk_i, // 接收树控制器工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire descriptor_valid_i, // 接收新的集合通信描述符
    output wire descriptor_ready_o, // 返回描述符接收许可
    input wire [2:0] descriptor_opcode_i, // 接收零至五号六类操作编码
    input wire [31:0] descriptor_group_id_i, // 接收全局通信组标识
    input wire [63:0] descriptor_transaction_id_i, // 接收全局事务标识
    input wire [15:0] descriptor_topology_epoch_i, // 接收十六位拓扑代次
    input wire [14:0] descriptor_destination_domain_i, // 接收点对点目的 leaf 域
    input wire group_found_i, // 接收当前节点组目录精确命中状态
    input wire [7:0] group_child_mask_i, // 接收当前节点至多八个有成员子树
    input wire [31:0] group_local_member_mask_i, // 接收 leaf 节点至多三十二个本地成员
    input wire [20:0] group_subtree_member_count_i, // 接收当前节点子树成员总数
    input wire [19:0] group_root_endpoint_i, // 接收二十位通信组根端点
    input wire [2:0] group_level_i, // 接收当前节点零至五级层次
    output reg command_valid_o, // 输出一个有界子树或本地执行命令
    input wire command_ready_i, // 接收命令许可
    output reg [2:0] command_phase_o, // 输出 leaf、gather、scatter、exchange、finish 或 complete 阶段
    output reg [2:0] command_opcode_o, // 输出冻结六类操作编码
    output reg [2:0] command_child_o, // 输出当前八子树编号
    output reg [31:0] command_local_member_mask_o, // 输出 leaf 本地三十二成员掩码
    output reg [31:0] command_group_id_o, // 输出冻结通信组标识
    output reg [63:0] command_transaction_id_o, // 输出冻结全局事务标识
    output reg [15:0] command_topology_epoch_o, // 输出冻结拓扑代次
    output reg [20:0] command_subtree_member_count_o, // 输出冻结子树成员总数
    output reg [19:0] command_root_endpoint_o, // 输出冻结通信组根端点
    output wire busy_o, // 输出控制器非空闲状态
    output reg descriptor_error_o // 输出非法描述符或目录状态 sticky 错误
); // 结束分布式集合通信控制器端口声明
    localparam [2:0] PHASE_LEAF_PREPARE = 3'd0; // 定义本地 leaf 数据面准备阶段
    localparam [2:0] PHASE_CHILD_GATHER = 3'd1; // 定义子树向根方向汇聚阶段
    localparam [2:0] PHASE_CHILD_SCATTER = 3'd2; // 定义根向子树分发阶段
    localparam [2:0] PHASE_CHILD_EXCHANGE = 3'd3; // 定义子树间直接交换阶段
    localparam [2:0] PHASE_LEAF_FINISH = 3'd4; // 定义本地 leaf 完成阶段
    localparam [2:0] PHASE_COMPLETE = 3'd5; // 定义端到端事务完成阶段
    localparam [2:0] STATE_IDLE = 3'd0; // 定义等待描述符状态
    localparam [2:0] STATE_PREPARE = 3'd1; // 定义 leaf 准备状态
    localparam [2:0] STATE_FIRST_PASS = 3'd2; // 定义 gather 或 exchange 第一遍子树状态
    localparam [2:0] STATE_SECOND_PASS = 3'd3; // 定义 scatter 第二遍子树状态
    localparam [2:0] STATE_FINISH = 3'd4; // 定义 leaf 完成状态
    localparam [2:0] STATE_COMPLETE = 3'd5; // 定义事务完成状态
    reg [2:0] state_q; // 保存当前树执行状态
    reg [2:0] opcode_q; // 保存冻结操作编码
    reg [31:0] group_id_q; // 保存冻结通信组标识
    reg [63:0] transaction_id_q; // 保存冻结全局事务标识
    reg [15:0] topology_epoch_q; // 保存冻结拓扑代次
    reg [7:0] child_mask_q; // 保存当前节点有界八子树掩码
    reg [31:0] local_member_mask_q; // 保存 leaf 本地三十二成员掩码
    reg [20:0] subtree_member_count_q; // 保存当前节点子树成员总数
    reg [19:0] root_endpoint_q; // 保存通信组根端点
    reg [2:0] level_q; // 保存当前节点层次
    reg [2:0] destination_child_q; // 保存点对点在当前级的目的子树数位
    reg [2:0] child_cursor_q; // 保存零至七号有界子树游标
    wire opcode_valid; // 标记描述符属于冻结六类操作
    wire node_shape_valid; // 标记内部或 leaf 目录形状合法
    wire p2p_child_valid; // 标记点对点目的子树属于通信组
    wire descriptor_contract_valid; // 汇总描述符和分布式目录合同
    wire child_selected; // 标记当前游标子树需要产生命令
    wire final_child; // 标记游标已经到七号子树
    wire command_fire; // 标记当前命令完成握手
    wire two_pass_operation; // 标记 RS、AG、AR 需要树上汇聚与分发
    wire exchange_operation; // 标记 AllToAll、AllToAllV 或 P2P 使用交换阶段
    reg [2:0] destination_digit_d; // 组合选择点对点目的域当前层次数位
    assign opcode_valid = descriptor_opcode_i <= `KDL_OPCODE_POINT_TO_POINT; // 限定零至五号六类操作
    assign node_shape_valid = ((group_level_i < 3'd5) && (group_child_mask_i != 8'd0) && (group_local_member_mask_i == 32'd0)) || ((group_level_i == 3'd5) && (group_child_mask_i == 8'd0) && (group_local_member_mask_i != 32'd0)); // 检查目录只携带当前节点有界状态
    assign p2p_child_valid = (group_level_i == 3'd5) || group_child_mask_i[destination_digit_d]; // 内部节点要求点对点目的子树属于组
    assign descriptor_contract_valid = opcode_valid && group_found_i && node_shape_valid && (group_subtree_member_count_i != 21'd0) && ((descriptor_opcode_i != `KDL_OPCODE_POINT_TO_POINT) || p2p_child_valid); // 汇总六类操作和目录合同
    assign descriptor_ready_o = state_q == STATE_IDLE; // 仅空闲状态接受新描述符
    assign busy_o = state_q != STATE_IDLE; // 非空闲状态均报告忙
    assign child_selected = (opcode_q == `KDL_OPCODE_POINT_TO_POINT) ? (child_cursor_q == destination_child_q) : child_mask_q[child_cursor_q]; // P2P 只走一个子树而其他操作遍历成员子树
    assign final_child = child_cursor_q == 3'd7; // 检查已经遍历最后一个有界子树
    assign command_fire = command_valid_o && command_ready_i; // 汇总命令握手
    assign two_pass_operation = opcode_q <= `KDL_OPCODE_ALL_REDUCE; // RS、AG、AR 均执行汇聚与分发两遍
    assign exchange_operation = opcode_q >= 3'd3; // AllToAll、AllToAllV 和 P2P 执行交换一遍
    always @(*) begin // 按当前层次选择点对点目的域 radix-8 数位
        case (group_level_i) // 消费目的域从高到低的五个数位
            3'd0: destination_digit_d = descriptor_destination_domain_i[14:12]; // 根级选择最高三位
            3'd1: destination_digit_d = descriptor_destination_domain_i[11:9]; // 第二级选择位十一至九
            3'd2: destination_digit_d = descriptor_destination_domain_i[8:6]; // 第三级选择位八至六
            3'd3: destination_digit_d = descriptor_destination_domain_i[5:3]; // 第四级选择位五至三
            default: destination_digit_d = descriptor_destination_domain_i[2:0]; // 第五级或 leaf 使用最低三位
        endcase // 结束点对点目的数位选择
    end // 结束目的子树组合选择
    always @(*) begin // 形成当前树阶段的唯一有界命令
        command_valid_o = 1'b0; // 默认当前无命令
        command_phase_o = PHASE_LEAF_PREPARE; // 默认命令阶段为 leaf 准备
        command_opcode_o = opcode_q; // 输出冻结操作编码
        command_child_o = child_cursor_q; // 输出当前有界子树游标
        command_local_member_mask_o = local_member_mask_q; // 输出 leaf 本地成员掩码
        command_group_id_o = group_id_q; // 输出冻结组标识
        command_transaction_id_o = transaction_id_q; // 输出冻结事务标识
        command_topology_epoch_o = topology_epoch_q; // 输出冻结拓扑代次
        command_subtree_member_count_o = subtree_member_count_q; // 输出冻结子树成员总数
        command_root_endpoint_o = root_endpoint_q; // 输出冻结根端点
        case (state_q) // 按树状态选择命令阶段
            STATE_PREPARE: begin command_valid_o = 1'b1; command_phase_o = PHASE_LEAF_PREPARE; end // 发出一次本地准备命令
            STATE_FIRST_PASS: begin // 遍历第一遍有成员子树
                command_phase_o = two_pass_operation ? PHASE_CHILD_GATHER : PHASE_CHILD_EXCHANGE; // 按操作选择汇聚或交换
                command_valid_o = (level_q < 3'd5) && child_selected; // leaf 无远端子树命令
            end // 结束第一遍子树命令
            STATE_SECOND_PASS: begin command_phase_o = PHASE_CHILD_SCATTER; command_valid_o = (level_q < 3'd5) && child_selected; end // 遍历第二遍分发子树
            STATE_FINISH: begin command_valid_o = 1'b1; command_phase_o = PHASE_LEAF_FINISH; end // 发出一次本地完成命令
            STATE_COMPLETE: begin command_valid_o = 1'b1; command_phase_o = PHASE_COMPLETE; end // 发出一次事务完成命令
            default: command_valid_o = 1'b0; // 空闲或非法状态禁止命令
        endcase // 结束树阶段命令选择
    end // 结束集合通信命令组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新描述符上下文、子树游标和阶段状态
        if (!rst_n_i) begin // 复位清除全部执行上下文
            state_q <= STATE_IDLE; opcode_q <= 3'd0; group_id_q <= 32'd0; transaction_id_q <= 64'd0; // 清除状态和描述符身份
            topology_epoch_q <= 16'd0; child_mask_q <= 8'd0; local_member_mask_q <= 32'd0; // 清除代次和目录掩码
            subtree_member_count_q <= 21'd0; root_endpoint_q <= 20'd0; level_q <= 3'd0; // 清除目录元数据
            destination_child_q <= 3'd0; child_cursor_q <= 3'd0; descriptor_error_o <= 1'b0; // 清除游标和 sticky 错误
        end else begin // 正常推进树执行状态机
            case (state_q) // 按当前状态提交握手结果
                STATE_IDLE: begin // 等待并验证同步目录查询结果
                    if (descriptor_valid_i && descriptor_ready_o) begin // 接受一个新描述符
                        if (descriptor_contract_valid) begin // 冻结合法描述符和有界目录状态
                            opcode_q <= descriptor_opcode_i; group_id_q <= descriptor_group_id_i; transaction_id_q <= descriptor_transaction_id_i; // 保存操作和事务身份
                            topology_epoch_q <= descriptor_topology_epoch_i; child_mask_q <= group_child_mask_i; local_member_mask_q <= group_local_member_mask_i; // 保存代次和成员掩码
                            subtree_member_count_q <= group_subtree_member_count_i; root_endpoint_q <= group_root_endpoint_i; level_q <= group_level_i; // 保存目录元数据
                            destination_child_q <= destination_digit_d; child_cursor_q <= 3'd0; state_q <= STATE_PREPARE; // 初始化子树游标并进入准备阶段
                        end else descriptor_error_o <= 1'b1; // sticky 报告非法操作或目录状态
                    end // 结束描述符接收
                end // 结束空闲状态
                STATE_PREPARE: if (command_fire) begin child_cursor_q <= 3'd0; state_q <= STATE_FIRST_PASS; end // 准备握手后进入第一遍子树
                STATE_FIRST_PASS: begin // 遍历至多八个本地子树
                    if ((level_q == 3'd5) || (!child_selected && final_child) || (child_selected && final_child && command_fire)) begin // leaf 或最后子树已经完成
                        child_cursor_q <= 3'd0; // 为可能的第二遍重置游标
                        if (two_pass_operation && (level_q < 3'd5)) state_q <= STATE_SECOND_PASS; // 三类树 collective 进入分发遍
                        else state_q <= STATE_FINISH; // 三类交换操作或 leaf 进入本地完成
                    end else if (!child_selected || command_fire) child_cursor_q <= child_cursor_q + 3'd1; // 跳过非成员或握手后推进游标
                end // 结束第一遍子树状态
                STATE_SECOND_PASS: begin // 再次遍历至多八个成员子树
                    if ((!child_selected && final_child) || (child_selected && final_child && command_fire)) state_q <= STATE_FINISH; // 最后子树完成后进入本地完成
                    else if (!child_selected || command_fire) child_cursor_q <= child_cursor_q + 3'd1; // 跳过非成员或握手后推进游标
                end // 结束第二遍子树状态
                STATE_FINISH: if (command_fire) state_q <= STATE_COMPLETE; // 本地完成握手后产生全局完成
                STATE_COMPLETE: if (command_fire) state_q <= STATE_IDLE; // 全局完成握手后释放执行上下文
                /* verilator coverage_off */ // FORMAL: state_q remains in the six-state reachable set after reset.
                default: begin state_q <= STATE_IDLE; descriptor_error_o <= 1'b1; end // 非法状态恢复并 sticky 报错
                /* verilator coverage_on */
            endcase // 结束树执行状态提交选择
        end // 结束正常树控制推进
    end // 结束分布式集合通信控制时序逻辑
`ifdef FORMAL
    always @(*) assert (state_q <= STATE_COMPLETE); // Prove the defensive illegal-state branch unreachable from the reset state.
`endif
endmodule // 结束 kdlink_collective_tree_ctrl
