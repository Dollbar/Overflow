`include "kdlink_defs.vh" // 引入 KDLink schema、消息类型和虚通道常量
module kdlink_route_stage #( // 定义可组合为二百五十六域拓扑的固定 radix-8 路由级
    parameter integer DOMAIN_COUNT = 256, // 指定实例化拓扑的有效域数量
    parameter integer STAGE_INDEX = 0 // 指定当前路由级从根向 leaf 的零起始编号
) ( // 开始可扩展路由级端口声明
    input wire clk_i, // 接收路由级工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [7:0] active_egress_mask_i, // 接收当前 radix-8 出口可用掩码
    input wire ingress_valid_i, // 接收 Route Context 或其绑定数据 flit 有效位
    output reg ingress_ready_o, // 返回输入 flit 接收许可
    input wire [639:0] ingress_flit_i, // 接收完整 KDLink flit
    output reg [7:0] egress_valid_o, // 输出八个子树出口有效位
    input wire [7:0] egress_ready_i, // 接收八个子树出口许可
    output reg [5119:0] egress_flit_o, // 输出八个独立完整 KDLink flit
    output wire route_active_o, // 输出后继 packet 正被锁定的状态
    output wire [2:0] selected_egress_o, // 输出当前确定性 radix-8 出口
    output wire final_stage_o, // 输出当前实例是否为目的 leaf 前最后一级
    output reg protocol_error_o, // 输出 packet 配对 sticky 错误
    output reg escape_violation_o // 输出拓扑、跳数或 escape sticky 错误
); // 结束可扩展路由级端口声明
    localparam integer STAGE_COUNT = (DOMAIN_COUNT <= 8) ? 1 : ((DOMAIN_COUNT <= 64) ? 2 : 3); // 计算 radix-8 层次深度
    localparam integer REMAINING_STAGES = STAGE_COUNT - STAGE_INDEX; // 计算含当前级在内的剩余路由级数量
    localparam STATE_CONTEXT = 1'b0; // 定义等待 Route Context 的状态
    localparam STATE_PACKET = 1'b1; // 定义锁定后继 packet 的状态
    reg state_q; // 保存当前上下文或 packet 状态
    reg [2:0] selected_egress_q; // 保存当前 packet 锁定出口
    reg [4:0] expected_flit_count_q; // 保存 Route Context 声明的 packet flit 数
    reg [4:0] accepted_flit_count_q; // 保存当前 packet 已接受 flit 数
    reg [11:0] expected_packet_sequence_q; // 保存后继 packet 期望序号
    reg [2:0] expected_vc_q; // 保存后继 packet 逻辑虚通道
    reg [4:0] expected_source_node_q; // 保存后继 packet 源节点
    reg [4:0] expected_destination_node_q; // 保存后继 packet 目的节点
    reg [2:0] expected_plane_q; // 保存后继 packet 逻辑 plane
    reg [2:0] route_egress_d; // 组合形成当前路由级 radix-8 出口
    reg [639:0] routed_context_flit_d; // 组合形成跳数递减后的 Route Context flit
    wire [3:0] ingress_schema; // 提取输入 flit schema
    wire [3:0] ingress_message_type; // 提取输入 flit 消息类型
    wire [2:0] ingress_vc; // 提取输入 flit 物理虚通道
    wire ingress_sop; // 提取输入 flit SOP
    wire ingress_eop; // 提取输入 flit EOP
    wire ingress_retry; // 提取输入 flit replay 标志
    wire [4:0] ingress_source_node; // 提取输入 flit 源节点
    wire [4:0] ingress_destination_node; // 提取输入 flit 目的节点
    wire [2:0] ingress_plane; // 提取输入 flit plane
    wire [11:0] ingress_packet_sequence; // 提取输入 packet 序号
    wire [5:0] ingress_flit_sequence; // 提取输入 flit 序号
    wire [6:0] ingress_payload_bytes; // 提取输入有效 payload 字节数
    wire route_candidate; // 标记层次 schema 或 Route Context 类型候选
    wire route_header_valid; // 标记 Route Context header 满足单 flit 合同
    wire route_payload_valid; // 标记 Route Context payload 满足冻结合同
    wire profile_valid; // 标记参数形成受支持的层次路由级
    wire destination_valid; // 标记目的域属于实例化拓扑
    wire selected_egress_active; // 标记当前确定性出口处于可用状态
    wire hop_budget_valid; // 标记剩余跳数足以经过全部路由级和目的 leaf
    wire route_forward_valid; // 标记 Route Context 可从当前级继续转发
    wire data_identity_valid; // 标记后继数据 flit 身份和边界合法
    wire expected_last_flit; // 标记当前接受 flit 应为 packet 尾拍
    wire context_fire; // 标记合法 Route Context 完成出口握手
    wire packet_fire; // 标记合法数据 flit 完成出口握手
    wire invalid_context_fire; // 标记非法 Route Context 被消费
    wire invalid_packet_fire; // 标记非法后继数据 flit 被消费
    wire [7:0] route_source_domain; // 接收解码后的源域
    wire [7:0] route_destination_domain; // 接收解码后的目的域
    wire [4:0] route_source_node; // 接收解码后的源节点
    wire [4:0] route_destination_node; // 接收解码后的目的节点
    wire [7:0] route_topology_epoch; // 接收解码后的拓扑代次
    wire [7:0] route_domain_hop_limit; // 接收解码后的跨域跳数上限
    wire [2:0] route_logical_plane; // 接收解码后的逻辑 plane
    wire [1:0] route_slice_mask; // 接收解码后的 bonded slice 掩码
    wire [2:0] route_policy; // 接收解码后的路由策略
    wire [4:0] route_packet_flit_count; // 接收解码后的 packet flit 数
    wire [11:0] route_expected_packet_sequence; // 接收解码后的 packet 序号
    wire [63:0] route_global_transaction_id; // 接收解码后的全局事务标识
    wire [31:0] route_group_id; // 接收解码后的全局通信组标识
    wire [2:0] route_logical_vc; // 接收解码后的逻辑虚通道
    wire unused_route_metadata; // 汇总已验证但不参与出口选择的字段
    assign ingress_schema = ingress_flit_i[515:512]; // 从 header 提取 schema
    assign ingress_message_type = ingress_flit_i[519:516]; // 从 header 提取消息类型
    assign ingress_vc = ingress_flit_i[527:525]; // 从 header 提取物理虚通道
    assign ingress_sop = ingress_flit_i[529]; // 从 header 提取 SOP
    assign ingress_eop = ingress_flit_i[530]; // 从 header 提取 EOP
    assign ingress_retry = ingress_flit_i[531]; // 从 header 提取 replay 标志
    assign ingress_source_node = ingress_flit_i[536:532]; // 从 header 提取源节点
    assign ingress_destination_node = ingress_flit_i[541:537]; // 从 header 提取目的节点
    assign ingress_plane = ingress_flit_i[544:542]; // 从 header 提取 plane
    assign ingress_packet_sequence = ingress_flit_i[593:582]; // 从 header 提取 packet 序号
    assign ingress_flit_sequence = ingress_flit_i[599:594]; // 从 header 提取 flit 序号
    assign ingress_payload_bytes = ingress_flit_i[606:600]; // 从 header 提取有效 payload 字节数
    assign route_candidate = (ingress_schema == `KDL_ROUTE_SCHEMA) || (ingress_message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT); // 捕获 schema 和消息类型的非法组合
    assign route_header_valid = (ingress_schema == `KDL_ROUTE_SCHEMA) && (ingress_message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT) && ingress_sop && ingress_eop && !ingress_flit_i[607] && (ingress_flit_sequence == 6'd0) && (ingress_payload_bytes == 7'd64) && ((!ingress_retry && (ingress_vc == route_logical_vc)) || (ingress_retry && (ingress_vc == `KDL_VC_ROLE_REPLAY))); // 检查单 flit Route Context header
    assign profile_valid = (DOMAIN_COUNT >= 2) && (DOMAIN_COUNT <= 256) && (STAGE_INDEX >= 0) && (STAGE_INDEX < STAGE_COUNT); // 限定支持的域数量和当前级编号
    assign destination_valid = {24'd0, route_destination_domain} < DOMAIN_COUNT; // 检查目的域属于实例化拓扑
    assign selected_egress_active = active_egress_mask_i[route_egress_d]; // 检查确定性出口处于可用状态
    assign hop_budget_valid = {24'd0, route_domain_hop_limit} > REMAINING_STAGES; // 保留全部剩余路由级和目的 leaf 所需跳数
    assign route_forward_valid = route_header_valid && route_payload_valid && profile_valid && destination_valid && selected_egress_active && hop_budget_valid && (route_policy == 3'd0); // 汇总 Route Context 转发合同
    assign expected_last_flit = ({1'b0, accepted_flit_count_q} + 6'd1) == {1'b0, expected_flit_count_q}; // 比较当前 flit 与声明 packet 长度
    assign data_identity_valid = !route_candidate && (ingress_schema == `KDL_SCHEMA_VERSION) && (ingress_packet_sequence == expected_packet_sequence_q) && (ingress_source_node == expected_source_node_q) && (ingress_destination_node == expected_destination_node_q) && (ingress_plane == expected_plane_q) && ((!ingress_retry && (ingress_vc == expected_vc_q)) || (ingress_retry && (ingress_vc == `KDL_VC_ROLE_REPLAY))) && ((accepted_flit_count_q == 5'd0) ? (ingress_sop && (ingress_flit_sequence == 6'd0)) : (!ingress_sop && (ingress_flit_sequence == {1'b0, accepted_flit_count_q}))) && (ingress_eop == expected_last_flit); // 检查 packet 身份、顺序和边界
    assign context_fire = (state_q == STATE_CONTEXT) && ingress_valid_i && route_forward_valid && egress_ready_i[route_egress_d]; // 汇总合法上下文出口握手
    assign packet_fire = (state_q == STATE_PACKET) && ingress_valid_i && data_identity_valid && egress_ready_i[selected_egress_q]; // 汇总合法数据出口握手
    assign invalid_context_fire = (state_q == STATE_CONTEXT) && ingress_valid_i && !route_forward_valid; // 汇总非法上下文消费事件
    assign invalid_packet_fire = (state_q == STATE_PACKET) && ingress_valid_i && !data_identity_valid; // 汇总非法数据消费事件
    assign route_active_o = state_q == STATE_PACKET; // 输出 packet 出口锁定状态
    assign selected_egress_o = selected_egress_q; // 输出当前锁定出口
    assign final_stage_o = STAGE_INDEX == (STAGE_COUNT - 1); // 指示当前实例紧邻目的 leaf
    assign unused_route_metadata = ^{route_source_domain, route_topology_epoch, route_slice_mask, route_global_transaction_id, route_group_id}; // 汇总非选择字段以记录完整解码覆盖
    kdlink_route_context_decoder u_route_decoder ( // 实例化冻结 Route Context 解码器
        .payload_i(ingress_flit_i[511:0]), // 连接输入 payload
        .source_domain_o(route_source_domain), // 接收源域解码结果
        .destination_domain_o(route_destination_domain), // 接收目的域解码结果
        .source_node_o(route_source_node), // 接收源节点解码结果
        .destination_node_o(route_destination_node), // 接收目的节点解码结果
        .topology_epoch_o(route_topology_epoch), // 接收拓扑代次解码结果
        .domain_hop_limit_o(route_domain_hop_limit), // 接收域跳数解码结果
        .logical_plane_o(route_logical_plane), // 接收逻辑 plane 解码结果
        .slice_mask_o(route_slice_mask), // 接收 slice 掩码解码结果
        .route_policy_o(route_policy), // 接收路由策略解码结果
        .packet_flit_count_o(route_packet_flit_count), // 接收 packet 长度解码结果
        .expected_packet_sequence_o(route_expected_packet_sequence), // 接收 packet 序号解码结果
        .global_transaction_id_o(route_global_transaction_id), // 接收全局事务标识解码结果
        .group_id_o(route_group_id), // 接收通信组标识解码结果
        .logical_vc_o(route_logical_vc), // 接收逻辑虚通道解码结果
        .payload_valid_o(route_payload_valid) // 接收 payload 合法性结果
    ); // 结束 Route Context 解码器实例
    always @(*) begin // 按拓扑规模和当前级选择目的域 radix-8 数位
        route_egress_d = 3'd0; // 默认选择零号出口
        if (DOMAIN_COUNT < 9) route_egress_d = route_destination_domain[2:0]; // 单级拓扑使用目的域最低三位
        else if (DOMAIN_COUNT < 65) begin // 两级拓扑使用目的域的两个八进制数位
            if (STAGE_INDEX == 0) route_egress_d = route_destination_domain[5:3]; // 根级选择目的域中间三位
            else route_egress_d = route_destination_domain[2:0]; // 末级选择目的域最低三位
        end else begin // 三级拓扑覆盖六十五到二百五十六个域
            if (STAGE_INDEX == 0) route_egress_d = {1'b0, route_destination_domain[7:6]}; // 根级选择最多四个顶层子树
            else if (STAGE_INDEX == 1) route_egress_d = route_destination_domain[5:3]; // 中间级选择八个子树
            else route_egress_d = route_destination_domain[2:0]; // 末级选择目的 leaf
        end // 结束拓扑规模选择
    end // 结束确定性出口组合逻辑
    always @(*) begin // 组合形成唯一出口、反压和递减跳数后的上下文
        ingress_ready_o = 1'b0; // 默认反压输入
        egress_valid_o = 8'd0; // 默认全部出口无效
        egress_flit_o = 5120'd0; // 默认清零全部出口 flit
        routed_context_flit_d = ingress_flit_i; // 默认复制输入 flit
        routed_context_flit_d[41:34] = route_domain_hop_limit - 8'd1; // 精确递减 Route Context 域跳数
        routed_context_flit_d[639:608] = 32'd0; // 清零待下游可靠端点重新生成的 CRC
        case (state_q) // 按上下文或 packet 状态选择唯一出口
            STATE_CONTEXT: begin // 验证并转发新的 Route Context
                if (route_forward_valid) begin // 仅转发满足全部层次 escape 合同的上下文
                    egress_valid_o[route_egress_d] = ingress_valid_i; // 选择当前层次目的子树出口
                    egress_flit_o[route_egress_d*640 +: 640] = routed_context_flit_d; // 输出跳数递减后的 Route Context
                    ingress_ready_o = egress_ready_i[route_egress_d]; // 使用目标出口许可反压输入
                end else ingress_ready_o = 1'b1; // 消费非法上下文并报告 sticky 错误
            end // 结束 Route Context 输出选择
            STATE_PACKET: begin // 将完整后继 packet 锁定到已选择子树
                if (data_identity_valid) begin // 仅转发身份和边界均合法的数据 flit
                    egress_valid_o[selected_egress_q] = ingress_valid_i; // 保持唯一锁定出口有效
                    egress_flit_o[selected_egress_q*640 +: 640] = ingress_flit_i; // 保持后继数据 flit 内容
                    ingress_ready_o = egress_ready_i[selected_egress_q]; // 使用锁定出口许可反压输入
                end else ingress_ready_o = 1'b1; // 消费非法数据并报告协议错误
            end // 结束后继 packet 输出选择
            /* verilator coverage_off */ // STRUCTURAL: the one-bit state exhaustively encodes context and packet.
            default: ingress_ready_o = 1'b0; // 非法状态禁止继续消费输入
            /* verilator coverage_on */
        endcase // 结束路由级状态输出选择
    end // 结束可扩展路由级组合输出逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 packet 锁定、计数和 sticky 错误
        if (!rst_n_i) begin // 低有效复位清除路由级状态
            state_q <= STATE_CONTEXT; // 复位后等待 Route Context
            selected_egress_q <= 3'd0; // 清零 packet 锁定出口
            expected_flit_count_q <= 5'd0; // 清零期望 packet 长度
            accepted_flit_count_q <= 5'd0; // 清零已接受 flit 计数
            expected_packet_sequence_q <= 12'd0; // 清零期望 packet 序号
            expected_vc_q <= 3'd0; // 清零期望逻辑虚通道
            expected_source_node_q <= 5'd0; // 清零期望源节点
            expected_destination_node_q <= 5'd0; // 清零期望目的节点
            expected_plane_q <= 3'd0; // 清零期望 plane
            protocol_error_o <= 1'b0; // 清除 packet 配对 sticky 错误
            escape_violation_o <= 1'b0; // 清除层次 escape sticky 错误
        end else if (context_fire) begin // 捕获已离开当前级的合法 Route Context
            state_q <= STATE_PACKET; // 锁定后继 packet 到同一出口
            selected_egress_q <= route_egress_d; // 保存当前层次确定性出口
            expected_flit_count_q <= route_packet_flit_count; // 保存后继 packet 声明长度
            accepted_flit_count_q <= 5'd0; // 清零后继 packet 计数
            expected_packet_sequence_q <= route_expected_packet_sequence; // 保存后继 packet 序号
            expected_vc_q <= route_logical_vc; // 保存后继 packet 逻辑虚通道
            expected_source_node_q <= route_source_node; // 保存后继 packet 源节点
            expected_destination_node_q <= route_destination_node; // 保存后继 packet 目的节点
            expected_plane_q <= route_logical_plane; // 保存后继 packet plane
        end else if (invalid_context_fire) begin // 消费不满足当前路由级合同的上下文
            protocol_error_o <= 1'b1; // sticky 报告非法 Route Context
            if (!profile_valid || !destination_valid || !selected_egress_active || !hop_budget_valid || (route_policy != 3'd0)) escape_violation_o <= 1'b1; // sticky 区分拓扑和 escape 合同错误
        end else if (packet_fire) begin // 推进合法后继 packet
            if (expected_last_flit) begin // 最后一拍已经离开当前路由级
                state_q <= STATE_CONTEXT; // 返回等待下一个 Route Context
                accepted_flit_count_q <= 5'd0; // 清零 packet flit 计数
            end else accepted_flit_count_q <= accepted_flit_count_q + 5'd1; // 推进有界 packet flit 计数
        end else if (invalid_packet_fire) begin // 消费非法后继 packet flit
            protocol_error_o <= 1'b1; // sticky 报告 packet 配对错误
            if (ingress_eop || expected_last_flit) begin // 在可识别 packet 边界恢复上下文状态
                state_q <= STATE_CONTEXT; // 返回等待下一个 Route Context
                accepted_flit_count_q <= 5'd0; // 清零 packet flit 计数
            end else accepted_flit_count_q <= accepted_flit_count_q + 5'd1; // 排空当前有界 packet
        end // 结束路由级状态推进选择
    end // 结束可扩展路由级时序逻辑
endmodule // 结束 kdlink_route_stage
