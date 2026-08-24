`include "kdlink_defs.vh" // 引入六类操作和分层阶段冻结编码
module kdlink_hierarchical_collective_ctrl ( // 定义六类操作的分层 leaf 与跨域命令控制器
    input wire clk_i, // 接收分层集合通信控制时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire descriptor_valid_i, // 接收跨域集合通信描述符有效位
    output wire descriptor_ready_o, // 返回跨域集合通信描述符许可
    input wire [2:0] descriptor_opcode_i, // 接收六类 KDLink 操作编码
    input wire [31:0] descriptor_group_id_i, // 接收全局通信组标识
    input wire [63:0] descriptor_transaction_id_i, // 接收全局事务标识
    input wire [7:0] descriptor_topology_epoch_i, // 接收描述符拓扑代次
    input wire [7:0] descriptor_local_domain_i, // 接收当前 leaf 域标识
    input wire [7:0] descriptor_source_domain_i, // 接收点对点源域或集合通信发起域
    input wire [7:0] descriptor_destination_domain_i, // 接收点对点目的域
    input wire group_found_i, // 接收组表精确命中状态
    input wire group_local_member_i, // 接收当前域属于通信组的状态
    input wire [255:0] group_member_mask_i, // 接收二百五十六域通信组成员位图
    input wire [8:0] group_member_count_i, // 接收通信组成员数量
    input wire [7:0] group_root_domain_i, // 接收通信组根域标识
    output reg command_valid_o, // 输出分层执行命令有效位
    input wire command_ready_i, // 接收分层执行命令许可
    output reg [1:0] command_phase_o, // 输出 leaf 准备、跨域、leaf 完成或全局完成阶段
    output reg [2:0] command_opcode_o, // 输出冻结的操作编码
    output reg [7:0] command_destination_domain_o, // 输出当前跨域命令目的域
    output reg [31:0] command_group_id_o, // 输出当前命令通信组标识
    output reg [63:0] command_transaction_id_o, // 输出当前命令全局事务标识
    output reg [7:0] command_topology_epoch_o, // 输出当前命令拓扑代次
    output reg [7:0] command_root_domain_o, // 输出当前命令通信组根域
    output wire busy_o, // 输出控制器正执行描述符的状态
    output reg descriptor_error_o // 输出非法描述符或组表不匹配 sticky 错误
); // 结束分层集合通信控制器端口声明
    localparam [2:0] STATE_IDLE = 3'd0; // 定义等待描述符状态
    localparam [2:0] STATE_LEAF_PREPARE = 3'd1; // 定义 leaf 内准备阶段
    localparam [2:0] STATE_INTERDOMAIN = 3'd2; // 定义跨域成员遍历阶段
    localparam [2:0] STATE_LEAF_FINISH = 3'd3; // 定义 leaf 内完成阶段
    localparam [2:0] STATE_COMPLETE = 3'd4; // 定义端到端完成阶段
    reg [2:0] state_q; // 保存当前分层执行状态
    reg [2:0] opcode_q; // 保存当前操作编码
    reg [31:0] group_id_q; // 保存当前通信组标识
    reg [63:0] transaction_id_q; // 保存当前全局事务标识
    reg [7:0] topology_epoch_q; // 保存当前拓扑代次
    reg [7:0] local_domain_q; // 保存当前 leaf 域标识
    reg [7:0] source_domain_q; // 保存当前点对点源域
    reg [7:0] destination_domain_q; // 保存当前点对点目的域
    reg [255:0] member_mask_q; // 保存当前通信组成员位图
    reg [8:0] member_count_q; // 保存当前通信组成员数量
    reg [7:0] root_domain_q; // 保存当前通信组根域
    reg [7:0] member_cursor_q; // 保存跨域成员顺序遍历位置
    wire opcode_valid; // 标记描述符操作属于冻结六类操作
    wire point_to_point_valid; // 标记点对点端点和本地域成员关系合法
    wire collective_membership_valid; // 标记集合通信本地域成员关系合法
    wire descriptor_contract_valid; // 汇总描述符和组表合同合法性
    wire current_member_selected; // 标记当前遍历域需要产生跨域命令
    wire final_cursor; // 标记成员遍历到二百五十五号域
    wire command_fire; // 标记当前分层命令完成握手
    wire unused_member_count; // 汇总已验证但不控制成员游标的数量字段
    assign opcode_valid = descriptor_opcode_i <= `KDL_OPCODE_POINT_TO_POINT; // 限定冻结的零至五号操作
    assign point_to_point_valid = group_member_mask_i[descriptor_source_domain_i] && group_member_mask_i[descriptor_destination_domain_i] && (descriptor_source_domain_i != descriptor_destination_domain_i) && ((descriptor_local_domain_i == descriptor_source_domain_i) || (descriptor_local_domain_i == descriptor_destination_domain_i)); // 检查点对点端点均在组内且当前域参与
    assign collective_membership_valid = group_local_member_i && group_member_mask_i[descriptor_local_domain_i]; // 交叉检查组表本地域成员结果
    assign descriptor_contract_valid = opcode_valid && group_found_i && (group_member_count_i != 9'd0) && (group_member_count_i <= 9'd256) && group_member_mask_i[group_root_domain_i] && ((descriptor_opcode_i == `KDL_OPCODE_POINT_TO_POINT) ? point_to_point_valid : collective_membership_valid); // 汇总六类操作、成员数、根成员和本地域关系合同
    assign descriptor_ready_o = state_q == STATE_IDLE; // 仅空闲状态接受新描述符
    assign busy_o = state_q != STATE_IDLE; // 非空闲状态均报告控制器忙
    assign current_member_selected = member_mask_q[member_cursor_q] && (member_cursor_q != local_domain_q); // 集合通信向除本地域外每个成员发出跨域命令
    assign final_cursor = member_cursor_q == 8'hff; // 检查已经遍历最后一个可寻址域
    assign command_fire = command_valid_o && command_ready_i; // 汇总分层命令 valid-ready 握手
    assign unused_member_count = ^member_count_q; // 记录组表成员数量已经进入冻结执行上下文
    always @(*) begin // 组合形成当前分层阶段命令
        command_valid_o = 1'b0; // 默认当前没有分层命令
        command_phase_o = `KDL_HIER_PHASE_LEAF_PREPARE; // 默认阶段编码为 leaf 准备
        command_opcode_o = opcode_q; // 默认输出已冻结操作编码
        command_destination_domain_o = local_domain_q; // 默认本地阶段目标为当前 leaf 域
        command_group_id_o = group_id_q; // 输出已冻结通信组标识
        command_transaction_id_o = transaction_id_q; // 输出已冻结全局事务标识
        command_topology_epoch_o = topology_epoch_q; // 输出已冻结拓扑代次
        command_root_domain_o = root_domain_q; // 输出已冻结通信组根域
        case (state_q) // 按分层执行状态形成命令
            STATE_LEAF_PREPARE: begin // 启动现有三十二节点 leaf 数据面准备或打包
                command_valid_o = 1'b1; // 持续声明 leaf 准备命令直至握手
                command_phase_o = `KDL_HIER_PHASE_LEAF_PREPARE; // 标记 leaf 准备阶段
            end // 结束 leaf 准备命令
            STATE_INTERDOMAIN: begin // 发出跨域成员传输命令
                command_phase_o = `KDL_HIER_PHASE_INTERDOMAIN; // 标记跨域执行阶段
                if (opcode_q == `KDL_OPCODE_POINT_TO_POINT) begin // 点对点仅由源域产生一条远端命令
                    if (local_domain_q == source_domain_q) begin // 当前域为点对点源域时发出传输
                        command_valid_o = 1'b1; // 声明点对点跨域命令有效
                        command_destination_domain_o = destination_domain_q; // 选择点对点目的域
                    end // 结束点对点源域命令形成
                end else if (current_member_selected) begin // 集合通信当前游标命中另一成员域
                    command_valid_o = 1'b1; // 声明当前成员跨域命令有效
                    command_destination_domain_o = member_cursor_q; // 输出当前通信组成员域
                end // 结束集合通信成员命令形成
            end // 结束跨域执行命令
            STATE_LEAF_FINISH: begin // 启动现有 leaf 数据面解包、归约完成或广播
                command_valid_o = 1'b1; // 持续声明 leaf 完成命令直至握手
                command_phase_o = `KDL_HIER_PHASE_LEAF_FINISH; // 标记 leaf 完成阶段
            end // 结束 leaf 完成命令
            STATE_COMPLETE: begin // 产生全局事务完成阶段命令
                command_valid_o = 1'b1; // 持续声明全局完成命令直至握手
                command_phase_o = `KDL_HIER_PHASE_COMPLETE; // 标记端到端完成阶段
            end // 结束全局完成命令
            default: begin // 空闲或非法状态保持命令无效
                command_valid_o = 1'b0; // 禁止空闲或非法状态输出命令
            end // 结束空闲或非法状态处理
        endcase // 结束分层阶段命令选择
    end // 结束分层命令组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新描述符、成员遍历和阶段状态
        if (!rst_n_i) begin // 低有效复位清除全部执行上下文
            state_q <= STATE_IDLE; // 复位后等待新描述符
            opcode_q <= 3'd0; // 清零当前操作编码
            group_id_q <= 32'd0; // 清零当前通信组标识
            transaction_id_q <= 64'd0; // 清零当前全局事务标识
            topology_epoch_q <= 8'd0; // 清零当前拓扑代次
            local_domain_q <= 8'd0; // 清零当前 leaf 域
            source_domain_q <= 8'd0; // 清零当前点对点源域
            destination_domain_q <= 8'd0; // 清零当前点对点目的域
            member_mask_q <= 256'd0; // 清零当前通信组成员位图
            member_count_q <= 9'd0; // 清零当前通信组成员数量
            root_domain_q <= 8'd0; // 清零当前通信组根域
            member_cursor_q <= 8'd0; // 清零成员遍历游标
            descriptor_error_o <= 1'b0; // 清除描述符 sticky 错误
        end else begin // 正常推进分层执行状态机
            case (state_q) // 按当前分层状态提交握手结果
                STATE_IDLE: begin // 等待并验证新的跨域描述符
                    if (descriptor_valid_i && descriptor_ready_o) begin // 接受一个描述符和同步组表查询结果
                        if (descriptor_contract_valid) begin // 合同合法时冻结全部执行上下文
                            opcode_q <= descriptor_opcode_i; // 保存六类操作编码
                            group_id_q <= descriptor_group_id_i; // 保存全局通信组标识
                            transaction_id_q <= descriptor_transaction_id_i; // 保存全局事务标识
                            topology_epoch_q <= descriptor_topology_epoch_i; // 保存拓扑代次
                            local_domain_q <= descriptor_local_domain_i; // 保存当前 leaf 域
                            source_domain_q <= descriptor_source_domain_i; // 保存点对点源域
                            destination_domain_q <= descriptor_destination_domain_i; // 保存点对点目的域
                            member_mask_q <= group_member_mask_i; // 保存二百五十六域成员位图
                            member_count_q <= group_member_count_i; // 保存通信组成员数量
                            root_domain_q <= group_root_domain_i; // 保存通信组根域
                            member_cursor_q <= 8'd0; // 从零号域开始确定性成员遍历
                            state_q <= STATE_LEAF_PREPARE; // 首先进入 leaf 数据面准备阶段
                        end else descriptor_error_o <= 1'b1; // sticky 报告非法操作、代次或成员关系
                    end // 结束新描述符接收
                end // 结束等待描述符状态
                STATE_LEAF_PREPARE: begin // 等待 leaf 准备命令被现有三十二节点数据面接受
                    if (command_fire) begin // leaf 准备命令已接受
                        member_cursor_q <= 8'd0; // 初始化跨域成员遍历游标
                        state_q <= STATE_INTERDOMAIN; // 进入显式跨域执行阶段
                    end // 结束 leaf 准备握手处理
                end // 结束 leaf 准备状态
                STATE_INTERDOMAIN: begin // 确定性遍历全部二百五十六域成员位
                    if (opcode_q == `KDL_OPCODE_POINT_TO_POINT) begin // 点对点源域至多发出一条跨域命令
                        if ((local_domain_q != source_domain_q) || command_fire) state_q <= STATE_LEAF_FINISH; // 目的域直接等待本地完成而源域在命令握手后推进
                    end else if (current_member_selected) begin // 当前游标命中另一通信组成员
                        if (command_fire) begin // 当前成员跨域命令已接受
                            if (final_cursor) state_q <= STATE_LEAF_FINISH; // 最后域命令完成后进入 leaf 完成阶段
                            else member_cursor_q <= member_cursor_q + 8'd1; // 推进到下一可寻址域
                        end // 结束成员命令握手处理
                    end else if (final_cursor) state_q <= STATE_LEAF_FINISH; // 最后域无需命令时直接结束成员遍历
                    else member_cursor_q <= member_cursor_q + 8'd1; // 跳过非成员或当前本地域
                end // 结束跨域成员遍历状态
                STATE_LEAF_FINISH: begin // 等待 leaf 数据面完成解包、归约或广播
                    if (command_fire) state_q <= STATE_COMPLETE; // leaf 完成命令握手后进入全局完成阶段
                end // 结束 leaf 完成状态
                STATE_COMPLETE: begin // 等待全局完成命令被事务层接受
                    if (command_fire) state_q <= STATE_IDLE; // 完成命令握手后释放执行上下文
                end // 结束全局完成状态
                default: begin // 非法状态恢复并报告 sticky 错误
                    state_q <= STATE_IDLE; // 恢复到等待描述符状态
                    descriptor_error_o <= 1'b1; // 记录非法状态恢复
                end // 结束非法状态处理
            endcase // 结束分层执行状态提交选择
        end // 结束正常分层执行推进
    end // 结束分层集合通信控制时序逻辑
endmodule // 结束 kdlink_hierarchical_collective_ctrl
