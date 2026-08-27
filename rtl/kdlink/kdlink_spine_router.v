`include "kdlink_defs.vh" // 引入 KDLink schema、消息类型和虚通道常量
module kdlink_spine_router ( // 定义支持四域和八域 profile 的单入口八出口确定性 spine 路由器
    input wire clk_i, // 接收 spine 路由器工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [3:0] domain_count_i, // 接收当前 profile 的有效域数量且只允许四或八
    input wire [7:0] active_domain_mask_i, // 接收可达 leaf domain 掩码
    input wire ingress_valid_i, // 接收已由上游可靠端点提交的 Route Context 或数据 flit
    output reg ingress_ready_o, // 返回上游 flit 接收许可
    input wire [639:0] ingress_flit_i, // 接收完整 KDLink flit
    output reg [7:0] egress_valid_o, // 向八个 leaf-down 出口分别声明 flit 有效位
    input wire [7:0] egress_ready_i, // 接收八个 leaf-down 出口许可
    output reg [5119:0] egress_flit_o, // 输出八个独立六百四十位 leaf-down flit
    output wire route_active_o, // 指示后继 packet 正锁定到一个 leaf-down 出口
    output wire [2:0] selected_egress_o, // 输出当前锁定的目标域出口
    output reg protocol_error_o, // sticky 指示 Route Context 或 packet 配对错误
    output reg escape_violation_o // sticky 指示 profile、跳数或确定性 escape 合同错误
); // 结束 spine 路由器端口声明
    localparam STATE_CONTEXT = 1'b0; // 定义等待 Route Context 的状态
    localparam STATE_PACKET = 1'b1; // 定义转发上下文绑定 packet 的状态
    reg state_q; // 保存当前 spine packet 锁定状态
    reg [2:0] selected_egress_q; // 保存当前 packet 的 leaf-down 出口
    reg [4:0] expected_flit_count_q; // 保存后继 packet 声明的 flit 数
    reg [4:0] accepted_flit_count_q; // 保存后继 packet 已转发的 flit 数
    reg [11:0] expected_packet_sequence_q; // 保存后继 packet 的期望序号
    reg [2:0] expected_vc_q; // 保存后继 packet 的逻辑 VC
    reg [4:0] expected_source_node_q; // 保存后继 packet 的源节点
    reg [4:0] expected_destination_node_q; // 保存后继 packet 的目标节点
    reg [2:0] expected_plane_q; // 保存后继 packet 的逻辑 plane
    reg [639:0] routed_context_flit_d; // 形成域跳数递减后的 Route Context flit
    wire [95:0] ingress_header; // 提取上游九十六位协议 header
    wire [511:0] ingress_payload; // 提取上游五百一十二位 payload
    wire [3:0] ingress_schema; // 提取上游 schema
    wire [3:0] ingress_message_type; // 提取上游消息类型
    wire [2:0] ingress_vc; // 提取上游物理 VC
    wire ingress_sop; // 提取上游 SOP
    wire ingress_eop; // 提取上游 EOP
    wire ingress_retry; // 提取上游 replay 标志
    wire [4:0] ingress_source_node; // 提取上游源节点
    wire [4:0] ingress_destination_node; // 提取上游目标节点
    wire [2:0] ingress_plane; // 提取上游逻辑 plane
    wire [11:0] ingress_packet_sequence; // 提取上游 packet 序号
    wire [5:0] ingress_flit_sequence; // 提取上游 flit 序号
    wire [6:0] ingress_payload_bytes; // 提取上游有效 payload 字节数
    wire route_candidate; // 标记层次 schema 或 Route Context 消息候选
    wire route_header_valid; // 标记 Route Context header 合法
    wire route_payload_valid; // 标记 Route Context payload 合法
    wire profile_valid; // 标记当前域数量 profile 为四域或八域
    wire destination_valid; // 标记目标域编号属于当前 profile 且处于 active 状态
    wire route_forward_valid; // 标记 Route Context 可进入确定性 leaf-down 路径
    wire data_identity_valid; // 标记后继 packet flit 身份和边界与上下文一致
    wire expected_last_flit; // 标记当前 flit 应为声明的最后一拍
    wire context_fire; // 标记 Route Context 完成 leaf-down 出口握手
    wire packet_fire; // 标记合法数据 flit 完成 leaf-down 出口握手
    wire invalid_context_fire; // 标记非法 Route Context 被消费
    wire invalid_packet_fire; // 标记非法后继 packet flit 被消费
    wire [7:0] route_source_domain; // 接收解码后的源域
    wire [7:0] route_destination_domain; // 接收解码后的目标域
    wire [4:0] route_source_node; // 接收解码后的源节点
    wire [4:0] route_destination_node; // 接收解码后的目标节点
    wire [7:0] route_topology_epoch; // 接收解码后的拓扑代次
    wire [7:0] route_domain_hop_limit; // 接收解码后的跨域跳数上限
    wire [2:0] route_logical_plane; // 接收解码后的逻辑 plane
    wire [1:0] route_slice_mask; // 接收解码后的 bonded slice 掩码
    wire [2:0] route_policy; // 接收解码后的路由策略
    wire [4:0] route_packet_flit_count; // 接收解码后的后继 packet 长度
    wire [11:0] route_expected_packet_sequence; // 接收解码后的后继 packet 序号
    wire [63:0] route_global_transaction_id; // 接收解码后的端到端事务标识
    wire [31:0] route_group_id; // 接收解码后的通信组标识
    wire [2:0] route_logical_vc; // 接收解码后的逻辑 VC
    wire unused_route_metadata; // 汇总已验证但不参与出口选择的上下文字段
    assign ingress_header = ingress_flit_i[607:512]; // 提取协议 header 并忽略输入 CRC
    assign ingress_payload = ingress_flit_i[511:0]; // 提取 Route Context 或数据 payload
    assign ingress_schema = ingress_header[3:0]; // 提取 schema 字段
    assign ingress_message_type = ingress_header[7:4]; // 提取消息类型字段
    assign ingress_vc = ingress_header[15:13]; // 提取物理 VC 字段
    assign ingress_sop = ingress_header[17]; // 提取 SOP 字段
    assign ingress_eop = ingress_header[18]; // 提取 EOP 字段
    assign ingress_retry = ingress_header[19]; // 提取 replay 字段
    assign ingress_source_node = ingress_header[24:20]; // 提取源节点字段
    assign ingress_destination_node = ingress_header[29:25]; // 提取目标节点字段
    assign ingress_plane = ingress_header[32:30]; // 提取 plane 字段
    assign ingress_packet_sequence = ingress_header[81:70]; // 提取 packet 序号字段
    assign ingress_flit_sequence = ingress_header[87:82]; // 提取 flit 序号字段
    assign ingress_payload_bytes = ingress_header[94:88]; // 提取有效 payload 字节数字段
    assign route_candidate = (ingress_schema == `KDL_ROUTE_SCHEMA) || (ingress_message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT); // 捕获 schema 和消息类型的非法组合
    assign route_header_valid = (ingress_schema == `KDL_ROUTE_SCHEMA) && (ingress_message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT) && ingress_sop && ingress_eop && !ingress_header[95] && (ingress_flit_sequence == 6'd0) && (ingress_payload_bytes == 7'd64) && ((!ingress_retry && (ingress_vc == route_logical_vc)) || (ingress_retry && (ingress_vc == `KDL_VC_ROLE_REPLAY))); // 检查单 flit Route Context header
    assign profile_valid = (domain_count_i == 4'd4) || (domain_count_i == 4'd8); // 只接受冻结的四域和八域 profile
    assign destination_valid = (route_destination_domain < {4'd0, domain_count_i}) && active_domain_mask_i[route_destination_domain[2:0]]; // 检查目标域范围和 active 掩码
    assign route_forward_valid = route_header_valid && route_payload_valid && profile_valid && destination_valid && (route_domain_hop_limit > 8'd1); // 要求 spine 转发后仍保留一跳到目标 leaf
    assign expected_last_flit = ({1'b0, accepted_flit_count_q} + 6'd1) == {1'b0, expected_flit_count_q}; // 比较当前 flit 与声明 packet 长度
    assign data_identity_valid = !route_candidate && (ingress_schema == `KDL_SCHEMA_VERSION) && (ingress_packet_sequence == expected_packet_sequence_q) && (ingress_source_node == expected_source_node_q) && (ingress_destination_node == expected_destination_node_q) && (ingress_plane == expected_plane_q) && ((!ingress_retry && (ingress_vc == expected_vc_q)) || (ingress_retry && (ingress_vc == `KDL_VC_ROLE_REPLAY))) && ((accepted_flit_count_q == 5'd0) ? (ingress_sop && (ingress_flit_sequence == 6'd0)) : (!ingress_sop && (ingress_flit_sequence == {1'b0, accepted_flit_count_q}))) && (ingress_eop == expected_last_flit); // 检查 packet 身份、顺序和边界
    assign context_fire = (state_q == STATE_CONTEXT) && ingress_valid_i && route_forward_valid && egress_ready_i[route_destination_domain[2:0]]; // 汇总合法上下文出口握手
    assign packet_fire = (state_q == STATE_PACKET) && ingress_valid_i && data_identity_valid && egress_ready_i[selected_egress_q]; // 汇总合法数据出口握手
    assign invalid_context_fire = (state_q == STATE_CONTEXT) && ingress_valid_i && !route_forward_valid; // 汇总非法上下文消费事件
    assign invalid_packet_fire = (state_q == STATE_PACKET) && ingress_valid_i && !data_identity_valid; // 汇总非法数据消费事件
    assign route_active_o = state_q == STATE_PACKET; // 输出 packet 锁定状态
    assign selected_egress_o = selected_egress_q; // 输出当前目标域出口
    assign unused_route_metadata = ^{route_source_domain, route_topology_epoch, route_slice_mask, route_policy, route_global_transaction_id, route_group_id}; // 汇总合法性覆盖的非选择字段
    kdlink_route_context_decoder u_route_decoder ( // 实例化冻结 Route Context 解码器
        .payload_i(ingress_payload), // 连接输入 payload
        .source_domain_o(route_source_domain), // 接收源域解码结果
        .destination_domain_o(route_destination_domain), // 接收目标域解码结果
        .source_node_o(route_source_node), // 接收源节点解码结果
        .destination_node_o(route_destination_node), // 接收目标节点解码结果
        .topology_epoch_o(route_topology_epoch), // 接收拓扑代次解码结果
        .domain_hop_limit_o(route_domain_hop_limit), // 接收域跳数解码结果
        .logical_plane_o(route_logical_plane), // 接收逻辑 plane 解码结果
        .slice_mask_o(route_slice_mask), // 接收 bonded slice 掩码解码结果
        .route_policy_o(route_policy), // 接收确定性 escape 策略解码结果
        .packet_flit_count_o(route_packet_flit_count), // 接收后继 packet 长度解码结果
        .expected_packet_sequence_o(route_expected_packet_sequence), // 接收后继 packet 序号解码结果
        .global_transaction_id_o(route_global_transaction_id), // 接收端到端事务身份解码结果
        .group_id_o(route_group_id), // 接收通信组身份解码结果
        .logical_vc_o(route_logical_vc), // 接收逻辑 VC 解码结果
        .payload_valid_o(route_payload_valid) // 接收 payload 合法性结果
    ); // 结束 Route Context 解码器实例
    always @(*) begin // 组合形成唯一 leaf-down 出口和输入反压
        ingress_ready_o = 1'b0; // 默认阻挡输入
        egress_valid_o = 8'd0; // 默认全部 leaf-down 出口无效
        egress_flit_o = 5120'd0; // 默认清零全部 leaf-down flit
        routed_context_flit_d = ingress_flit_i; // 默认复制输入 Route Context flit
        routed_context_flit_d[41:34] = route_domain_hop_limit - 8'd1; // 将 payload 域跳数精确递减一
        routed_context_flit_d[639:608] = 32'd0; // 清零待由下游可靠端点重新生成的 CRC
        case (state_q) // 按上下文或 packet 状态选择出口
            STATE_CONTEXT: begin // 验证并转发 Route Context
                if (route_forward_valid) begin // 只发送满足 profile 和 escape 合同的上下文
                    egress_valid_o[route_destination_domain[2:0]] = ingress_valid_i; // 选择目标域 leaf-down 出口
                    egress_flit_o[route_destination_domain[2:0]*640 +: 640] = routed_context_flit_d; // 输出跳数递减后的上下文
                    ingress_ready_o = egress_ready_i[route_destination_domain[2:0]]; // 使用目标出口许可反压输入
                end else ingress_ready_o = 1'b1; // 消费非法上下文并报告错误
            end // 结束 Route Context 出口选择
            STATE_PACKET: begin // 将完整后继 packet 锁定到已选目标域
                if (data_identity_valid) begin // 只转发身份和边界合法的数据 flit
                    egress_valid_o[selected_egress_q] = ingress_valid_i; // 保持唯一 leaf-down 出口有效
                    egress_flit_o[selected_egress_q*640 +: 640] = ingress_flit_i; // 保持后继数据内容
                    ingress_ready_o = egress_ready_i[selected_egress_q]; // 使用锁定出口许可反压输入
                end else ingress_ready_o = 1'b1; // 消费非法数据并报告协议错误
            end // 结束 packet 锁定转发
            /* verilator coverage_off */ // STRUCTURAL: the one-bit state exhaustively encodes context and packet.
            default: begin // 保护非法状态
                ingress_ready_o = 1'b0; // 非法状态禁止继续消费
            end // 结束非法状态保护
            /* verilator coverage_on */
        endcase // 结束 spine 出口状态选择
    end // 结束 spine 路由组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新出口锁定、packet 计数和 sticky 错误
        if (!rst_n_i) begin // 低有效复位清除全部路由状态
            state_q <= STATE_CONTEXT; // 复位后等待 Route Context
            selected_egress_q <= 3'd0; // 清零目标域出口
            expected_flit_count_q <= 5'd0; // 清零后继 packet 长度
            accepted_flit_count_q <= 5'd0; // 清零已转发 flit 计数
            expected_packet_sequence_q <= 12'd0; // 清零后继 packet 序号
            expected_vc_q <= 3'd0; // 清零逻辑 VC
            expected_source_node_q <= 5'd0; // 清零源节点
            expected_destination_node_q <= 5'd0; // 清零目标节点
            expected_plane_q <= 3'd0; // 清零逻辑 plane
            protocol_error_o <= 1'b0; // 清除 sticky 协议错误
            escape_violation_o <= 1'b0; // 清除 sticky escape 错误
        end else if (context_fire) begin // 捕获已进入 leaf-down 出口的 Route Context
            state_q <= STATE_PACKET; // 锁定后继 packet 出口
            selected_egress_q <= route_destination_domain[2:0]; // 保存目标域出口
            expected_flit_count_q <= route_packet_flit_count; // 保存后继 packet 长度
            accepted_flit_count_q <= 5'd0; // 清零后继 packet 计数
            expected_packet_sequence_q <= route_expected_packet_sequence; // 保存后继 packet 序号
            expected_vc_q <= route_logical_vc; // 保存后继 packet 逻辑 VC
            expected_source_node_q <= route_source_node; // 保存后继 packet 源节点
            expected_destination_node_q <= route_destination_node; // 保存后继 packet 目标节点
            expected_plane_q <= route_logical_plane; // 保存后继 packet plane
        end else if (invalid_context_fire) begin // 消费不满足 spine 合同的 Route Context
            protocol_error_o <= 1'b1; // sticky 报告非法上下文
            if (!profile_valid || !destination_valid || (route_domain_hop_limit <= 8'd1) || (route_policy != 3'd0)) escape_violation_o <= 1'b1; // 区分 profile 跳数和 escape 合同错误
        end else if (packet_fire) begin // 推进合法后继 packet
            if (expected_last_flit) begin // 最后一拍已离开 spine
                state_q <= STATE_CONTEXT; // 返回等待下一个 Route Context
                accepted_flit_count_q <= 5'd0; // 清零 packet 计数
            end else accepted_flit_count_q <= accepted_flit_count_q + 5'd1; // 推进有界 packet 计数
        end else if (invalid_packet_fire) begin // 消费非法后继 packet flit
            protocol_error_o <= 1'b1; // sticky 报告 packet 配对错误
            if (ingress_eop || expected_last_flit) begin // 在可识别 packet 边界恢复
                state_q <= STATE_CONTEXT; // 返回等待下一个 Route Context
                accepted_flit_count_q <= 5'd0; // 清零 packet 计数
            end else accepted_flit_count_q <= accepted_flit_count_q + 5'd1; // 排空当前有界 packet
        end // 结束 spine 状态推进选择
    end // 结束 spine 路由时序逻辑
endmodule // 结束 kdlink_spine_router 模块
