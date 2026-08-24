`include "kdlink_defs.vh" // 引入 KDLink schema、消息类型和虚通道常量
module kdlink_route_pair_tx ( // 定义 Route Context 与后继 packet 的可靠发送屏障
    input wire clk_i, // 接收发送控制器工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire ingress_valid_i, // 接收上游 Route Context 或后继数据 flit 有效位
    output reg ingress_ready_o, // 返回上游 flit 接收许可
    input wire [639:0] ingress_flit_i, // 接收上游完整 KDLink flit
    output reg tx_valid_o, // 向可靠端点声明一个待发送 flit
    input wire tx_ready_i, // 接收可靠端点入口许可
    output reg [95:0] tx_header_o, // 输出已恢复逻辑 VC 的链路发送 header
    output reg [511:0] tx_payload_o, // 输出链路发送 payload
    output reg [6:0] tx_payload_bytes_o, // 输出链路发送有效 payload 字节数
    input wire ack_valid_i, // 接收可靠端点同步到 core 域的 ACK 事件
    input wire ack_phase_i, // 接收 ACK phase 身份
    input wire [11:0] ack_collective_id_i, // 接收 ACK collective 身份
    input wire [11:0] ack_packet_seq_i, // 接收 ACK packet 序号身份
    output wire waiting_for_ack_o, // 指示 Route Context 已发送且后继数据仍被屏障阻挡
    output reg pair_complete_o, // 单周期指示一个上下文数据对完成发送
    output reg protocol_error_o // sticky 指示 Route Context 或后继 packet 配对错误
); // 结束 Route Context 发送屏障端口声明
    localparam [1:0] STATE_CONTEXT = 2'd0; // 定义等待 Route Context 的状态
    localparam [1:0] STATE_ACK = 2'd1; // 定义等待 Route Context ACK 的状态
    localparam [1:0] STATE_DATA = 2'd2; // 定义发送上下文绑定 packet 的状态
    reg [1:0] state_q; // 保存当前发送屏障状态
    reg ack_phase_q; // 保存待确认 Route Context 的 phase
    reg [11:0] ack_collective_id_q; // 保存待确认 Route Context 的 collective 身份
    reg [11:0] ack_packet_seq_q; // 保存待确认 Route Context 的 packet 序号
    reg [4:0] expected_flit_count_q; // 保存后继 packet 声明的 flit 数
    reg [4:0] accepted_flit_count_q; // 保存后继 packet 已发送的 flit 数
    reg [11:0] expected_packet_sequence_q; // 保存后继 packet 的期望序号
    reg [2:0] expected_vc_q; // 保存后继 packet 的逻辑 VC
    reg [4:0] expected_source_node_q; // 保存后继 packet 的源节点
    reg [4:0] expected_destination_node_q; // 保存后继 packet 的目标节点
    reg [2:0] expected_plane_q; // 保存后继 packet 的逻辑 plane
    wire [95:0] ingress_header; // 提取上游 flit 的九十六位协议 header
    wire [511:0] ingress_payload; // 提取上游 flit 的五百一十二位 payload
    wire [3:0] ingress_schema; // 提取上游 schema
    wire [3:0] ingress_message_type; // 提取上游消息类型
    wire [2:0] ingress_vc; // 提取上游物理虚通道
    wire ingress_phase; // 提取上游 phase
    wire ingress_sop; // 提取上游 SOP 标志
    wire ingress_eop; // 提取上游 EOP 标志
    wire ingress_retry; // 提取上游 replay 标志
    wire [4:0] ingress_source_node; // 提取上游源节点
    wire [4:0] ingress_destination_node; // 提取上游目标节点
    wire [2:0] ingress_plane; // 提取上游逻辑 plane
    wire [11:0] ingress_collective_id; // 提取上游 collective 身份
    wire [11:0] ingress_packet_sequence; // 提取上游 packet 序号
    wire [5:0] ingress_flit_sequence; // 提取上游 packet 内 flit 序号
    wire [6:0] ingress_payload_bytes; // 提取上游有效 payload 字节数
    wire route_candidate; // 标记层次 schema 或 Route Context 消息候选
    wire route_header_valid; // 标记 Route Context header 合法
    wire route_payload_valid; // 标记 Route Context payload 合法
    wire data_identity_valid; // 标记后继数据 flit 身份与上下文一致
    wire expected_last_flit; // 标记当前数据 flit 应为声明的最后一拍
    wire context_fire; // 标记合法 Route Context 进入可靠端点
    wire data_fire; // 标记合法后继数据进入可靠端点
    wire invalid_context_fire; // 标记非法 Route Context 被消费
    wire invalid_data_fire; // 标记非法后继数据被消费
    wire matching_ack; // 标记 ACK 身份与待确认 Route Context 一致
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
    wire [2:0] route_logical_vc; // 接收解码后的逻辑虚通道
    wire unused_route_metadata; // 汇总已验证但不参与屏障状态的 Route Context 字段
    assign ingress_header = ingress_flit_i[607:512]; // 提取上游协议 header 并忽略待重新生成的 CRC
    assign ingress_payload = ingress_flit_i[511:0]; // 提取上游 payload
    assign ingress_schema = ingress_header[3:0]; // 提取 schema 字段
    assign ingress_message_type = ingress_header[7:4]; // 提取消息类型字段
    assign ingress_vc = ingress_header[15:13]; // 提取物理 VC 字段
    assign ingress_phase = ingress_header[16]; // 提取 phase 字段
    assign ingress_sop = ingress_header[17]; // 提取 SOP 字段
    assign ingress_eop = ingress_header[18]; // 提取 EOP 字段
    assign ingress_retry = ingress_header[19]; // 提取 replay 字段
    assign ingress_source_node = ingress_header[24:20]; // 提取源节点字段
    assign ingress_destination_node = ingress_header[29:25]; // 提取目标节点字段
    assign ingress_plane = ingress_header[32:30]; // 提取 plane 字段
    assign ingress_collective_id = ingress_header[57:46]; // 提取 collective 身份字段
    assign ingress_packet_sequence = ingress_header[81:70]; // 提取 packet 序号字段
    assign ingress_flit_sequence = ingress_header[87:82]; // 提取 flit 序号字段
    assign ingress_payload_bytes = ingress_header[94:88]; // 提取有效 payload 字节数字段
    assign route_candidate = (ingress_schema == `KDL_ROUTE_SCHEMA) || (ingress_message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT); // 捕获 schema 和消息类型的非法组合
    assign route_header_valid = (ingress_schema == `KDL_ROUTE_SCHEMA) && (ingress_message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT) && ingress_sop && ingress_eop && !ingress_header[95] && (ingress_flit_sequence == 6'd0) && (ingress_payload_bytes == 7'd64) && ((!ingress_retry && (ingress_vc == route_logical_vc)) || (ingress_retry && (ingress_vc == `KDL_VC_ROLE_REPLAY))); // 检查单 flit Route Context header
    assign expected_last_flit = ({1'b0, accepted_flit_count_q} + 6'd1) == {1'b0, expected_flit_count_q}; // 比较当前数据 flit 与声明长度
    assign data_identity_valid = !route_candidate && (ingress_schema == `KDL_SCHEMA_VERSION) && (ingress_packet_sequence == expected_packet_sequence_q) && (ingress_source_node == expected_source_node_q) && (ingress_destination_node == expected_destination_node_q) && (ingress_plane == expected_plane_q) && ((!ingress_retry && (ingress_vc == expected_vc_q)) || (ingress_retry && (ingress_vc == `KDL_VC_ROLE_REPLAY))) && ((accepted_flit_count_q == 5'd0) ? (ingress_sop && (ingress_flit_sequence == 6'd0)) : (!ingress_sop && (ingress_flit_sequence == {1'b0, accepted_flit_count_q}))) && (ingress_eop == expected_last_flit); // 检查完整 packet 身份、顺序和边界
    assign context_fire = (state_q == STATE_CONTEXT) && ingress_valid_i && route_header_valid && route_payload_valid && tx_ready_i; // 汇总合法 Route Context 发送握手
    assign data_fire = (state_q == STATE_DATA) && ingress_valid_i && data_identity_valid && tx_ready_i; // 汇总合法数据发送握手
    assign invalid_context_fire = (state_q == STATE_CONTEXT) && ingress_valid_i && !(route_header_valid && route_payload_valid); // 汇总非法 Route Context 消费事件
    assign invalid_data_fire = (state_q == STATE_DATA) && ingress_valid_i && !data_identity_valid; // 汇总非法后继数据消费事件
    assign matching_ack = ack_valid_i && (ack_phase_i == ack_phase_q) && (ack_collective_id_i == ack_collective_id_q) && (ack_packet_seq_i == ack_packet_seq_q); // 比较 ACK 与屏障保存身份
    assign waiting_for_ack_o = state_q == STATE_ACK; // 输出生产屏障等待状态
    assign unused_route_metadata = ^{route_source_domain, route_destination_domain, route_topology_epoch, route_domain_hop_limit, route_slice_mask, route_policy, route_global_transaction_id, route_group_id}; // 汇总不直接控制发送状态的已验证字段
    kdlink_route_context_decoder u_route_decoder ( // 实例化冻结 Route Context 解码与字段合法性检查器
        .payload_i(ingress_payload), // 连接待发送上下文 payload
        .source_domain_o(route_source_domain), // 接收源域解码结果
        .destination_domain_o(route_destination_domain), // 接收目标域解码结果
        .source_node_o(route_source_node), // 接收源节点解码结果
        .destination_node_o(route_destination_node), // 接收目标节点解码结果
        .topology_epoch_o(route_topology_epoch), // 接收拓扑代次解码结果
        .domain_hop_limit_o(route_domain_hop_limit), // 接收域跳数解码结果
        .logical_plane_o(route_logical_plane), // 接收逻辑 plane 解码结果
        .slice_mask_o(route_slice_mask), // 接收 bonded slice 掩码解码结果
        .route_policy_o(route_policy), // 接收路由策略解码结果
        .packet_flit_count_o(route_packet_flit_count), // 接收后继 packet 长度解码结果
        .expected_packet_sequence_o(route_expected_packet_sequence), // 接收后继 packet 序号解码结果
        .global_transaction_id_o(route_global_transaction_id), // 接收端到端事务身份解码结果
        .group_id_o(route_group_id), // 接收通信组身份解码结果
        .logical_vc_o(route_logical_vc), // 接收后继 packet 逻辑 VC 解码结果
        .payload_valid_o(route_payload_valid) // 接收上下文 payload 合法性结果
    ); // 结束 Route Context 解码器实例
    always @(*) begin // 组合形成可靠端点发送接口和上游反压
        ingress_ready_o = 1'b0; // 默认阻挡上游输入
        tx_valid_o = 1'b0; // 默认不向可靠端点发送
        tx_header_o = ingress_header; // 默认复制上游 header
        tx_payload_o = ingress_payload; // 默认复制上游 payload
        tx_payload_bytes_o = ingress_payload_bytes; // 默认复制上游有效字节数
        tx_header_o[19] = 1'b0; // 在新物理跳发送前清除上游 replay 标志
        case (state_q) // 按屏障状态选择发送行为
            STATE_CONTEXT: begin // 验证并发送 Route Context
                tx_header_o[15:13] = route_logical_vc; // 恢复上下文声明的逻辑 VC
                if (route_header_valid && route_payload_valid) begin // 仅向可靠端点提交合法上下文
                    tx_valid_o = ingress_valid_i; // 传递上下文有效位
                    ingress_ready_o = tx_ready_i; // 使用可靠端点许可反压上游
                end else ingress_ready_o = 1'b1; // 消费非法上下文以避免输入死锁
            end // 结束 Route Context 发送选择
            STATE_ACK: begin // 保持后继数据直到匹配 ACK 到达
                ingress_ready_o = 1'b0; // 对上游施加生产级 ACK 屏障
            end // 结束 ACK 等待选择
            STATE_DATA: begin // 验证并发送上下文绑定的后继 packet
                tx_header_o[15:13] = expected_vc_q; // 恢复新物理跳的逻辑 VC
                if (data_identity_valid) begin // 仅向可靠端点提交身份与边界合法的数据
                    tx_valid_o = ingress_valid_i; // 传递数据有效位
                    ingress_ready_o = tx_ready_i; // 使用可靠端点许可反压上游
                end else ingress_ready_o = 1'b1; // 消费非法数据并报告协议错误
            end // 结束后继 packet 发送选择
            default: begin // 保护非法状态
                ingress_ready_o = 1'b0; // 非法状态禁止继续消费
            end // 结束非法状态保护
        endcase // 结束发送屏障状态选择
    end // 结束可靠端点发送接口组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新发送屏障、packet 计数和 sticky 错误
        if (!rst_n_i) begin // 低有效复位清除全部发送状态
            state_q <= STATE_CONTEXT; // 复位后等待新的 Route Context
            ack_phase_q <= 1'b0; // 清零待确认 phase
            ack_collective_id_q <= 12'd0; // 清零待确认 collective 身份
            ack_packet_seq_q <= 12'd0; // 清零待确认 packet 序号
            expected_flit_count_q <= 5'd0; // 清零后继 packet 长度
            accepted_flit_count_q <= 5'd0; // 清零已发送 flit 计数
            expected_packet_sequence_q <= 12'd0; // 清零后继 packet 序号
            expected_vc_q <= 3'd0; // 清零后继 packet 逻辑 VC
            expected_source_node_q <= 5'd0; // 清零后继 packet 源节点
            expected_destination_node_q <= 5'd0; // 清零后继 packet 目标节点
            expected_plane_q <= 3'd0; // 清零后继 packet plane
            pair_complete_o <= 1'b0; // 清除配对完成脉冲
            protocol_error_o <= 1'b0; // 清除 sticky 协议错误
        end else begin // 处理正常发送状态推进
            pair_complete_o <= 1'b0; // 默认配对完成脉冲无效
            if (state_q == STATE_ACK) begin // 仅由身份匹配 ACK 释放生产屏障
                if (matching_ack) state_q <= STATE_DATA; // 匹配 ACK 后允许发送后继 packet
            end else if (context_fire) begin // 捕获已进入可靠端点的 Route Context
                state_q <= STATE_ACK; // 进入等待该上下文 ACK 的状态
                ack_phase_q <= ingress_phase; // 保存上下文 phase 身份
                ack_collective_id_q <= ingress_collective_id; // 保存上下文 collective 身份
                ack_packet_seq_q <= ingress_packet_sequence; // 保存上下文 packet 序号
                expected_flit_count_q <= route_packet_flit_count; // 保存后继 packet 声明长度
                accepted_flit_count_q <= 5'd0; // 清零后继 packet 发送计数
                expected_packet_sequence_q <= route_expected_packet_sequence; // 保存后继 packet 序号
                expected_vc_q <= route_logical_vc; // 保存后继 packet 逻辑 VC
                expected_source_node_q <= route_source_node; // 保存后继 packet 源节点
                expected_destination_node_q <= route_destination_node; // 保存后继 packet 目标节点
                expected_plane_q <= route_logical_plane; // 保存后继 packet plane
            end else if (invalid_context_fire) begin // 消费非法 Route Context
                protocol_error_o <= 1'b1; // sticky 报告上下文错误
            end else if (data_fire) begin // 推进合法后继 packet
                if (expected_last_flit) begin // 最后一拍已进入可靠端点
                    state_q <= STATE_CONTEXT; // 返回等待下一 Route Context
                    accepted_flit_count_q <= 5'd0; // 清零 packet 发送计数
                    pair_complete_o <= 1'b1; // 报告上下文数据对发送完成
                end else accepted_flit_count_q <= accepted_flit_count_q + 5'd1; // 推进有界 packet 发送计数
            end else if (invalid_data_fire) begin // 消费非法后继 packet flit
                protocol_error_o <= 1'b1; // sticky 报告 packet 配对错误
                if (ingress_eop || expected_last_flit) begin // 在可识别边界恢复下一上下文
                    state_q <= STATE_CONTEXT; // 返回等待下一 Route Context
                    accepted_flit_count_q <= 5'd0; // 清零 packet 发送计数
                end else accepted_flit_count_q <= accepted_flit_count_q + 5'd1; // 继续有界排空当前 packet
            end else if (state_q != STATE_CONTEXT && state_q != STATE_DATA) begin // 捕获除 ACK 等待外的非法状态
                state_q <= STATE_CONTEXT; // 恢复到等待上下文状态
                protocol_error_o <= 1'b1; // sticky 记录非法状态恢复
            end // 结束发送状态推进选择
        end // 结束正常发送状态处理
    end // 结束发送屏障时序逻辑
endmodule // 结束 kdlink_route_pair_tx 模块
