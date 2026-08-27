`include "kdlink_defs.vh" // 引入 KDLink schema、消息类型和虚通道常量
module kdlink_scale_route_stage #( // 定义百万端点一至五级 radix-8 转发级
    parameter integer DOMAIN_COUNT = 32768, // 指定活动 leaf 域数量
    parameter integer STAGE_INDEX = 0 // 指定从根向 leaf 的零起始路由级
) ( // 开始 scale 路由级端口声明
    input wire clk_i, // 接收路由级工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [15:0] current_topology_epoch_i, // 接收当前已提交拓扑代次
    input wire [15:0] previous_topology_epoch_i, // 接收迁移窗口上一拓扑代次
    input wire previous_epoch_valid_i, // 接收上一代次仍可排空指示
    input wire scale_capability_enable_i, // 接收对端已经协商 schema-4 能力指示
    input wire [7:0] active_egress_mask_i, // 接收当前 plane 的八出口可用掩码
    input wire ingress_valid_i, // 接收 Route Context 或绑定数据有效位
    output reg ingress_ready_o, // 返回输入接收许可
    input wire [639:0] ingress_flit_i, // 接收完整 KDLink flit
    output reg [7:0] egress_valid_o, // 输出八个子树出口有效位
    input wire [7:0] egress_ready_i, // 接收八个子树出口许可
    output reg [5119:0] egress_flit_o, // 输出八个独立完整 KDLink flit
    output wire route_active_o, // 输出后继 packet 正被锁定状态
    output wire [2:0] selected_egress_o, // 输出锁定的 radix-8 出口
    output wire final_stage_o, // 输出当前级紧邻目的 leaf 状态
    output wire [2:0] escape_rank_o, // 输出单调 escape 依赖等级
    output reg protocol_error_o, // 输出 context 与 packet 合同 sticky 错误
    output reg escape_violation_o, // 输出深度、跳数或出口 sticky 错误
    output reg topology_epoch_violation_o // 输出拓扑代次窗口 sticky 错误
); // 结束 scale 路由级端口声明
    localparam STATE_CONTEXT = 1'b0; // 定义等待 Route Context 状态
    localparam STATE_PACKET = 1'b1; // 定义锁定后继 packet 状态
    localparam integer STAGE_COUNT = (DOMAIN_COUNT <= 8) ? 1 : ((DOMAIN_COUNT <= 64) ? 2 : ((DOMAIN_COUNT <= 512) ? 3 : ((DOMAIN_COUNT <= 4096) ? 4 : 5))); // 计算活动 radix-8 路由深度
    localparam [2:0] STAGE_COUNT_VALUE = (STAGE_COUNT == 5) ? 3'd5 : ((STAGE_COUNT == 4) ? 3'd4 : ((STAGE_COUNT == 3) ? 3'd3 : ((STAGE_COUNT == 2) ? 3'd2 : 3'd1))); // 将活动深度冻结为三位常量
    reg state_q; // 保存当前上下文或 packet 状态
    reg [2:0] selected_egress_q; // 保存当前 packet 锁定出口
    reg [4:0] expected_flit_count_q; // 保存 Route Context 声明的 packet flit 数
    reg [4:0] accepted_flit_count_q; // 保存当前 packet 已接受 flit 数
    reg [11:0] expected_packet_sequence_q; // 保存后继 packet 序号
    reg [2:0] expected_vc_q; // 保存后继 packet 逻辑虚通道
    reg [4:0] expected_source_node_q; // 保存后继 packet 源节点
    reg [4:0] expected_destination_node_q; // 保存后继 packet 目的节点
    reg [2:0] expected_plane_q; // 保存后继 packet 逻辑 plane
    reg [639:0] routed_context_flit_d; // 组合形成跳数递减后的 Route Context
    wire [3:0] ingress_schema; // 提取输入 schema
    wire [3:0] ingress_message_type; // 提取输入消息类型
    wire [2:0] ingress_vc; // 提取输入物理虚通道
    wire ingress_sop; // 提取输入 SOP
    wire ingress_eop; // 提取输入 EOP
    wire ingress_retry; // 提取输入 replay 标志
    wire [4:0] ingress_source_node; // 提取输入源节点
    wire [4:0] ingress_destination_node; // 提取输入目的节点
    wire [2:0] ingress_plane; // 提取输入 plane
    wire [11:0] ingress_packet_sequence; // 提取输入 packet 序号
    wire [5:0] ingress_flit_sequence; // 提取输入 flit 序号
    wire [6:0] ingress_payload_bytes; // 提取输入有效 payload 字节数
    wire route_candidate; // 标记 schema-4 或 Route Context 类型候选
    wire route_header_valid; // 标记 Route Context header 合法
    wire route_payload_valid; // 标记 schema-4 payload 合法
    wire profile_valid; // 标记实例参数形成受支持 profile
    wire destination_valid; // 标记目的域属于活动范围
    wire selected_egress_active; // 标记确定性出口可用
    wire hop_budget_valid; // 标记跳数足够穿越剩余级和目的 leaf
    wire route_depth_valid; // 标记声明深度匹配实例 profile
    wire topology_epoch_valid; // 标记 Route Context 属于双代窗口
    wire route_forward_valid; // 标记 Route Context 可继续转发
    wire data_identity_valid; // 标记后继数据身份和边界合法
    wire expected_last_flit; // 标记当前 flit 应为 packet 尾拍
    wire context_fire; // 标记合法上下文完成握手
    wire packet_fire; // 标记合法数据完成握手
    wire invalid_context_fire; // 标记非法上下文被消费
    wire invalid_packet_fire; // 标记非法数据被消费
    wire [14:0] route_source_domain; // 接收解码后的十五位源域
    wire [14:0] route_destination_domain; // 接收解码后的十五位目的域
    wire [4:0] route_source_node; // 接收解码后的源节点
    wire [4:0] route_destination_node; // 接收解码后的目的节点
    wire [15:0] route_topology_epoch; // 接收解码后的十六位拓扑代次
    wire [7:0] route_domain_hop_limit; // 接收解码后的跨域跳数
    wire [2:0] route_logical_plane; // 接收解码后的逻辑 plane
    wire [1:0] route_slice_mask; // 接收解码后的 slice 掩码
    wire [2:0] route_policy; // 接收解码后的路由策略
    wire [4:0] route_packet_flit_count; // 接收解码后的 packet 长度
    wire [11:0] route_expected_packet_sequence; // 接收解码后的 packet 序号
    wire [63:0] route_global_transaction_id; // 接收解码后的全局事务标识
    wire [31:0] route_group_id; // 接收解码后的通信组标识
    wire [2:0] route_logical_vc; // 接收解码后的逻辑虚通道
    wire [2:0] route_depth; // 接收解码后的活动路由深度
    wire [2:0] route_egress; // 接收当前级 radix-8 目的数位
    wire [2:0] remaining_stages; // 接收含当前级在内的剩余级数
    wire unused_route_metadata; // 汇总已校验但不参与组合选择的字段
    assign ingress_schema = ingress_flit_i[515:512]; // 从 header 提取 schema
    assign ingress_message_type = ingress_flit_i[519:516]; // 从 header 提取消息类型
    assign ingress_vc = ingress_flit_i[527:525]; // 从 header 提取物理 VC
    assign ingress_sop = ingress_flit_i[529]; // 从 header 提取 SOP
    assign ingress_eop = ingress_flit_i[530]; // 从 header 提取 EOP
    assign ingress_retry = ingress_flit_i[531]; // 从 header 提取 replay 标志
    assign ingress_source_node = ingress_flit_i[536:532]; // 从 header 提取源节点
    assign ingress_destination_node = ingress_flit_i[541:537]; // 从 header 提取目的节点
    assign ingress_plane = ingress_flit_i[544:542]; // 从 header 提取 plane
    assign ingress_packet_sequence = ingress_flit_i[593:582]; // 从 header 提取 packet 序号
    assign ingress_flit_sequence = ingress_flit_i[599:594]; // 从 header 提取 flit 序号
    assign ingress_payload_bytes = ingress_flit_i[606:600]; // 从 header 提取有效 payload 字节数
    assign route_candidate = (ingress_schema == `KDL_SCALE_SCHEMA) || (ingress_message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT); // 捕获 schema 和消息类型的非法组合
    assign route_header_valid = (ingress_schema == `KDL_SCALE_SCHEMA) && (ingress_message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT) && ingress_sop && ingress_eop && !ingress_flit_i[607] && (ingress_flit_sequence == 6'd0) && (ingress_payload_bytes == 7'd64) && (ingress_source_node == route_source_node) && (ingress_destination_node == route_destination_node) && (ingress_plane == route_logical_plane) && ((!ingress_retry && (ingress_vc == route_logical_vc)) || (ingress_retry && (ingress_vc == `KDL_VC_ROLE_REPLAY))); // 检查单 flit schema-4 header 与 payload 身份一致
    assign topology_epoch_valid = (route_topology_epoch == current_topology_epoch_i) || (previous_epoch_valid_i && (route_topology_epoch == previous_topology_epoch_i)); // 接受当前代次和受控排空的上一代次
    assign route_depth_valid = route_depth == STAGE_COUNT_VALUE; // 要求源端声明深度与实例 profile 一致
    assign hop_budget_valid = route_domain_hop_limit > {5'd0, remaining_stages}; // 保留全部剩余路由级和目的 leaf 所需跳数
    assign route_forward_valid = scale_capability_enable_i && route_header_valid && route_payload_valid && profile_valid && destination_valid && selected_egress_active && hop_budget_valid && route_depth_valid && topology_epoch_valid && (route_policy == 3'd0); // 汇总能力协商和 Route Context 转发合同
    assign expected_last_flit = ({1'b0, accepted_flit_count_q} + 6'd1) == {1'b0, expected_flit_count_q}; // 比较当前 flit 与声明 packet 长度
    assign data_identity_valid = !route_candidate && (ingress_schema == `KDL_SCHEMA_VERSION) && (ingress_packet_sequence == expected_packet_sequence_q) && (ingress_source_node == expected_source_node_q) && (ingress_destination_node == expected_destination_node_q) && (ingress_plane == expected_plane_q) && ((!ingress_retry && (ingress_vc == expected_vc_q)) || (ingress_retry && (ingress_vc == `KDL_VC_ROLE_REPLAY))) && ((accepted_flit_count_q == 5'd0) ? (ingress_sop && (ingress_flit_sequence == 6'd0)) : (!ingress_sop && (ingress_flit_sequence == {1'b0, accepted_flit_count_q}))) && (ingress_eop == expected_last_flit); // 检查 packet 身份、顺序和边界
    assign context_fire = (state_q == STATE_CONTEXT) && ingress_valid_i && route_forward_valid && egress_ready_i[route_egress]; // 汇总合法上下文出口握手
    assign packet_fire = (state_q == STATE_PACKET) && ingress_valid_i && data_identity_valid && egress_ready_i[selected_egress_q]; // 汇总合法数据出口握手
    assign invalid_context_fire = (state_q == STATE_CONTEXT) && ingress_valid_i && !route_forward_valid; // 汇总非法上下文消费事件
    assign invalid_packet_fire = (state_q == STATE_PACKET) && ingress_valid_i && !data_identity_valid; // 汇总非法数据消费事件
    assign route_active_o = state_q == STATE_PACKET; // 输出 packet 出口锁定状态
    assign selected_egress_o = selected_egress_q; // 输出当前锁定出口
    assign unused_route_metadata = ^{route_source_domain, route_slice_mask, route_global_transaction_id, route_group_id}; // 汇总非选择字段以记录完整解码覆盖
    kdlink_scale_route_context_decoder u_route_decoder ( // 实例化冻结 schema-4 解码器
        .payload_i(ingress_flit_i[511:0]), // 连接输入 payload
        .source_domain_o(route_source_domain), .destination_domain_o(route_destination_domain), // 接收十五位域字段
        .source_node_o(route_source_node), .destination_node_o(route_destination_node), // 接收 leaf 内节点字段
        .topology_epoch_o(route_topology_epoch), .domain_hop_limit_o(route_domain_hop_limit), // 接收拓扑代次和跳数
        .logical_plane_o(route_logical_plane), .slice_mask_o(route_slice_mask), // 接收平面和 slice 字段
        .route_policy_o(route_policy), .packet_flit_count_o(route_packet_flit_count), // 接收策略和 packet 长度
        .expected_packet_sequence_o(route_expected_packet_sequence), .global_transaction_id_o(route_global_transaction_id), // 接收序号和事务标识
        .group_id_o(route_group_id), .logical_vc_o(route_logical_vc), .route_depth_o(route_depth), // 接收通信组、逻辑 VC 和深度
        .payload_valid_o(route_payload_valid) // 接收完整 payload 合法性
    ); // 结束 schema-4 解码器实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(DOMAIN_COUNT), .STAGE_INDEX(STAGE_INDEX)) u_digit_selector ( // 实例化共享 profile 数位选择器
        .destination_domain_i(route_destination_domain), .active_egress_mask_i(active_egress_mask_i), // 连接目的域和出口掩码
        .selected_egress_o(route_egress), .profile_valid_o(profile_valid), // 接收选择数位和 profile 状态
        .destination_valid_o(destination_valid), .selected_egress_active_o(selected_egress_active), // 接收目的域和出口状态
        .final_stage_o(final_stage_o), .remaining_stages_o(remaining_stages), .escape_rank_o(escape_rank_o) // 输出层次元数据
    ); // 结束路由数位选择器实例
    always @(*) begin // 按上下文或 packet 状态形成唯一出口
        ingress_ready_o = 1'b0; // 默认反压未知状态
        egress_valid_o = 8'd0; // 默认所有出口无效
        egress_flit_o = 5120'd0; // 默认清零所有出口数据
        routed_context_flit_d = ingress_flit_i; // 默认复制输入 Route Context
        routed_context_flit_d[63:56] = route_domain_hop_limit - 8'd1; // 精确递减 schema-4 跳数字段
        routed_context_flit_d[639:608] = 32'd0; // 清零待下游可靠端点重算的 CRC
        case (state_q) // 按当前协议状态选择输出行为
            STATE_CONTEXT: begin // 验证并转发新的 Route Context
                if (route_forward_valid) begin // 仅转发满足全部合同的上下文
                    egress_valid_o[route_egress] = ingress_valid_i; // 驱动确定性子树出口
                    egress_flit_o[route_egress*640 +: 640] = routed_context_flit_d; // 输出跳数递减后的上下文
                    ingress_ready_o = egress_ready_i[route_egress]; // 使用目标出口许可反压输入
                end else ingress_ready_o = 1'b1; // 消费非法上下文并报告 sticky 错误
            end // 结束 Route Context 输出选择
            STATE_PACKET: begin // 将完整后继 packet 锁定到已选择子树
                if (data_identity_valid) begin // 仅转发身份和边界合法的数据
                    egress_valid_o[selected_egress_q] = ingress_valid_i; // 保持锁定出口有效
                    egress_flit_o[selected_egress_q*640 +: 640] = ingress_flit_i; // 保持数据 flit 内容不变
                    ingress_ready_o = egress_ready_i[selected_egress_q]; // 使用锁定出口许可反压输入
                end else ingress_ready_o = 1'b1; // 消费非法数据并报告协议错误
            end // 结束后继 packet 输出选择
            /* verilator coverage_off */ // 一位状态已经穷举零和一，保留 default 仅满足 ASIC 防御式编码规范
            default: ingress_ready_o = 1'b0; // 非法状态禁止继续消费输入
            /* verilator coverage_on */ // 恢复后续可达路由级逻辑覆盖统计
        endcase // 结束状态输出选择
    end // 结束组合输出逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 packet 锁定、计数和 sticky 错误
        if (!rst_n_i) begin // 低有效复位清除全部状态
            state_q <= STATE_CONTEXT; // 复位后等待 Route Context
            selected_egress_q <= 3'd0; // 清零锁定出口
            expected_flit_count_q <= 5'd0; // 清零期望 packet 长度
            accepted_flit_count_q <= 5'd0; // 清零已接受 flit 数
            expected_packet_sequence_q <= 12'd0; // 清零期望 packet 序号
            expected_vc_q <= 3'd0; // 清零期望逻辑 VC
            expected_source_node_q <= 5'd0; // 清零期望源节点
            expected_destination_node_q <= 5'd0; // 清零期望目的节点
            expected_plane_q <= 3'd0; // 清零期望 plane
            protocol_error_o <= 1'b0; // 清除协议 sticky 错误
            escape_violation_o <= 1'b0; // 清除 escape sticky 错误
            topology_epoch_violation_o <= 1'b0; // 清除代次 sticky 错误
        end else if (context_fire) begin // 捕获已离开当前级的合法上下文
            state_q <= STATE_PACKET; // 锁定后继 packet 到同一出口
            selected_egress_q <= route_egress; // 保存当前 radix-8 出口
            expected_flit_count_q <= route_packet_flit_count; // 保存后继 packet 长度
            accepted_flit_count_q <= 5'd0; // 清零后继 packet 计数
            expected_packet_sequence_q <= route_expected_packet_sequence; // 保存后继 packet 序号
            expected_vc_q <= route_logical_vc; // 保存后继 packet 逻辑 VC
            expected_source_node_q <= route_source_node; // 保存后继 packet 源节点
            expected_destination_node_q <= route_destination_node; // 保存后继 packet 目的节点
            expected_plane_q <= route_logical_plane; // 保存后继 packet plane
        end else if (invalid_context_fire) begin // 消费不满足当前路由级合同的上下文
            protocol_error_o <= 1'b1; // sticky 报告非法 Route Context
            if (!profile_valid || !destination_valid || !selected_egress_active || !hop_budget_valid || !route_depth_valid || (route_policy != 3'd0)) escape_violation_o <= 1'b1; // sticky 区分路由与 escape 合同错误
            if (!topology_epoch_valid) topology_epoch_violation_o <= 1'b1; // sticky 区分超出双代窗口的上下文
        end else if (packet_fire) begin // 推进合法后继 packet
            if (expected_last_flit) begin // 最后一拍已经离开当前级
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
    end // 结束 scale 路由级时序逻辑
endmodule // 结束 kdlink_scale_route_stage
