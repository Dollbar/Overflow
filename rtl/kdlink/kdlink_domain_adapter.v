`include "kdlink_defs.vh" // 引入 KDLink schema 消息类型和 VC 编码
module kdlink_domain_adapter ( // 定义单流本地与跨域 packet 分类适配器
    input wire clk_i, // 接收适配器工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [7:0] local_domain_i, // 接收当前 leaf domain 标识
    input wire ingress_valid_i, // 接收已由可靠端点提交的输入 flit 有效位
    output reg ingress_ready_o, // 返回输入 flit 接收许可
    input wire [639:0] ingress_flit_i, // 接收六百四十位 KDLink flit
    output reg local_valid_o, // 输出本地域数据 flit 有效位
    input wire local_ready_i, // 接收本地域数据路径许可
    output reg [639:0] local_flit_o, // 输出本地域数据 flit
    output reg remote_valid_o, // 输出跨域 Route Context 或数据 flit 有效位
    input wire remote_ready_i, // 接收跨域可靠链路许可
    output reg [639:0] remote_flit_o, // 输出跨域 Route Context 或数据 flit
    output reg protocol_error_o // 输出 sticky Route Context 或 packet 配对错误
); // 结束 domain adapter 端口声明
    localparam [1:0] STATE_IDLE = 2'd0; // 定义等待普通 flit 或 Route Context 的状态
    localparam [1:0] STATE_LOCAL_PACKET = 2'd1; // 定义向本地域锁定转发后继 packet 的状态
    localparam [1:0] STATE_REMOTE_PACKET = 2'd2; // 定义向跨域链路锁定转发后继 packet 的状态
    reg [1:0] state_q; // 保存当前 Route Context 配对状态
    reg [4:0] expected_flit_count_q; // 保存后继 packet 声明的 flit 数
    reg [4:0] accepted_flit_count_q; // 保存后继 packet 已接受的 flit 数
    reg [11:0] expected_packet_sequence_q; // 保存后继 packet 期望序号
    reg [2:0] expected_vc_q; // 保存 Route Context 所在虚通道
    reg [4:0] expected_source_node_q; // 保存 Route Context 声明的源节点
    reg [4:0] expected_destination_node_q; // 保存 Route Context 声明的目标节点
    reg [2:0] expected_plane_q; // 保存 Route Context 声明的逻辑 plane
    wire [3:0] ingress_schema; // 提取输入 flit schema 值
    wire [3:0] ingress_message_type; // 提取输入 flit消息类型
    wire [2:0] ingress_vc; // 提取输入 flit 虚通道
    wire ingress_retry; // 提取输入 flit replay 标志
    wire ingress_sop; // 提取输入 flit packet 首拍标志
    wire ingress_eop; // 提取输入 flit packet 尾拍标志
    wire [4:0] ingress_source_node; // 提取输入 flit 源节点
    wire [4:0] ingress_destination_node; // 提取输入 flit 目标节点
    wire [2:0] ingress_plane; // 提取输入 flit 逻辑 plane
    wire [11:0] ingress_packet_sequence; // 提取输入 flit packet 序号
    wire [6:0] ingress_payload_bytes; // 提取输入 flit 有效 payload 字节数
    wire route_candidate; // 标记输入 flit 使用层次 schema 或 Route Context 类型
    wire route_header_valid; // 标记 Route Context header 字段满足单 flit 合同
    wire route_payload_valid; // 标记 Route Context payload 字段满足首增量合同
    wire [7:0] route_source_domain; // 保存解码后的源域标识
    wire [7:0] route_destination_domain; // 保存解码后的目标域标识
    wire [4:0] route_source_node; // 保存解码后的源域内节点
    wire [4:0] route_destination_node; // 保存解码后的目标域内节点
    wire [7:0] route_topology_epoch; // 保存解码后的拓扑代次
    wire [7:0] route_domain_hop_limit; // 保存解码后的跨域跳数上限
    wire [2:0] route_logical_plane; // 保存解码后的逻辑 plane
    wire [1:0] route_slice_mask; // 保存解码后的 bonded slice 掩码
    wire [2:0] route_policy; // 保存解码后的路由策略
    wire [4:0] route_packet_flit_count; // 保存解码后的后继 packet flit 数
    wire [11:0] route_expected_packet_sequence; // 保存解码后的后继 packet 序号
    wire [63:0] route_global_transaction_id; // 保存解码后的端到端事务标识
    wire [31:0] route_group_id; // 保存解码后的全局通信组标识
    wire [2:0] route_logical_vc; // 保存解码后的后继 packet 逻辑虚通道
    wire accepted_ingress; // 标记本周期完成输入 flit 握手
    wire expected_last_flit; // 标记当前接受 flit 应为声明的 packet 尾拍
    assign ingress_schema = ingress_flit_i[515:512]; // 从 header 提取四位 schema
    assign ingress_message_type = ingress_flit_i[519:516]; // 从 header 提取四位消息类型
    assign ingress_vc = ingress_flit_i[527:525]; // 从 header 提取三位虚通道
    assign ingress_retry = ingress_flit_i[531]; // 从 header 提取 replay 标志
    assign ingress_sop = ingress_flit_i[529]; // 从 header 提取 SOP 标志
    assign ingress_eop = ingress_flit_i[530]; // 从 header 提取 EOP 标志
    assign ingress_source_node = ingress_flit_i[536:532]; // 从 header 提取源节点
    assign ingress_destination_node = ingress_flit_i[541:537]; // 从 header 提取目标节点
    assign ingress_plane = ingress_flit_i[544:542]; // 从 header 提取逻辑 plane
    assign ingress_packet_sequence = ingress_flit_i[593:582]; // 从 header 提取 packet 序号
    assign ingress_payload_bytes = ingress_flit_i[606:600]; // 从 header 提取有效 payload 字节数
    assign route_candidate = (ingress_schema == `KDL_ROUTE_SCHEMA) || (ingress_message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT); // 捕获层次 schema 和 Route Context 类型的非法组合
    assign route_header_valid = (ingress_schema == `KDL_ROUTE_SCHEMA) && (ingress_message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT) && ingress_sop && ingress_eop && (ingress_payload_bytes == 7'd64) && ((ingress_retry && (ingress_vc == `KDL_VC_ROLE_REPLAY)) || (!ingress_retry && (ingress_vc == route_logical_vc))); // 检查单 flit Route Context header 及逻辑 VC 镜像
    assign accepted_ingress = ingress_valid_i && ingress_ready_o; // 汇总输入 valid-ready 握手
    assign expected_last_flit = ({1'b0, accepted_flit_count_q} + 6'd1) == {1'b0, expected_flit_count_q}; // 比较当前 flit 与声明 packet 长度
    kdlink_route_context_decoder u_route_decoder ( // 实例化 Route Context payload 解码器
        .payload_i(ingress_flit_i[511:0]), // 连接输入 flit payload
        .source_domain_o(route_source_domain), // 接收源域解码结果
        .destination_domain_o(route_destination_domain), // 接收目标域解码结果
        .source_node_o(route_source_node), // 接收源节点解码结果
        .destination_node_o(route_destination_node), // 接收目标节点解码结果
        .topology_epoch_o(route_topology_epoch), // 接收拓扑代次解码结果
        .domain_hop_limit_o(route_domain_hop_limit), // 接收跨域跳数解码结果
        .logical_plane_o(route_logical_plane), // 接收逻辑 plane 解码结果
        .slice_mask_o(route_slice_mask), // 接收 slice 掩码解码结果
        .route_policy_o(route_policy), // 接收路由策略解码结果
        .packet_flit_count_o(route_packet_flit_count), // 接收后继 packet 长度解码结果
        .expected_packet_sequence_o(route_expected_packet_sequence), // 接收后继 packet 序号解码结果
        .global_transaction_id_o(route_global_transaction_id), // 接收端到端事务标识解码结果
        .group_id_o(route_group_id), // 接收全局通信组解码结果
        .logical_vc_o(route_logical_vc), // 接收后继 packet 逻辑虚通道解码结果
        .payload_valid_o(route_payload_valid) // 接收 payload 合法性结果
    ); // 结束 Route Context payload 解码器实例
    always @(*) begin // 组合形成本地或跨域单一输出路径
        ingress_ready_o = 1'b0; // 默认反压输入
        local_valid_o = 1'b0; // 默认本地输出无效
        local_flit_o = ingress_flit_i; // 默认本地输出保持当前输入 flit
        remote_valid_o = 1'b0; // 默认跨域输出无效
        remote_flit_o = ingress_flit_i; // 默认跨域输出保持当前输入 flit
        case (state_q) // 按 Route Context 配对状态选择唯一输出
            STATE_IDLE: begin // 处理普通本地流量或新的 Route Context
                if (route_candidate) begin // 识别 Route Context 或层次 schema 异常
                    if (route_header_valid && route_payload_valid) begin // 接受字段完整的 Route Context
                        if (route_destination_domain == local_domain_i) ingress_ready_o = 1'b1; // 目标域命中时仅消费上下文并等待本地 packet
                        else begin // 目标域未命中时将上下文可靠转发到跨域链路
                            remote_valid_o = ingress_valid_i; // 向跨域链路声明 Route Context 有效
                            ingress_ready_o = remote_ready_i; // 使用跨域链路许可反压 Route Context
                        end // 结束跨域 Route Context 转发
                    end else ingress_ready_o = 1'b1; // 消费非法上下文并由时序逻辑报告错误
                end else begin // 普通 schema-2 流量直接进入本地域路径
                    local_valid_o = ingress_valid_i; // 向本地域声明普通 flit 有效
                    ingress_ready_o = local_ready_i; // 使用本地域许可反压普通 flit
                end // 结束普通本地流量处理
            end // 结束空闲状态输出选择
            STATE_LOCAL_PACKET: begin // 将上下文绑定的完整 packet 锁定到本地域
                local_valid_o = ingress_valid_i; // 向本地域声明后继 packet flit 有效
                ingress_ready_o = local_ready_i; // 使用本地域许可反压后继 packet
            end // 结束本地 packet 输出选择
            STATE_REMOTE_PACKET: begin // 将上下文绑定的完整 packet 锁定到跨域链路
                remote_valid_o = ingress_valid_i; // 向跨域链路声明后继 packet flit 有效
                ingress_ready_o = remote_ready_i; // 使用跨域链路许可反压后继 packet
            end // 结束跨域 packet 输出选择
            default: begin // 对非法状态保持全部输出反压
                ingress_ready_o = 1'b0; // 阻止非法状态继续接收输入
            end // 结束非法状态保护
        endcase // 结束 Route Context 配对状态输出选择
    end // 结束本地与跨域输出组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 Route Context 配对、packet 计数和 sticky 错误
        if (!rst_n_i) begin // 低有效复位清除全部上下文状态
            state_q <= STATE_IDLE; // 复位进入等待上下文状态
            expected_flit_count_q <= 5'd0; // 清零期望 packet 长度
            accepted_flit_count_q <= 5'd0; // 清零已接受 packet 长度
            expected_packet_sequence_q <= 12'd0; // 清零期望 packet 序号
            expected_vc_q <= 3'd0; // 清零期望虚通道
            expected_source_node_q <= 5'd0; // 清零期望源节点
            expected_destination_node_q <= 5'd0; // 清零期望目标节点
            expected_plane_q <= 3'd0; // 清零期望逻辑 plane
            protocol_error_o <= 1'b0; // 清除 sticky 协议错误
        end else if (accepted_ingress) begin // 仅在输入握手时推进上下文和 packet 状态
            case (state_q) // 按当前状态提交握手结果
                STATE_IDLE: begin // 捕获 Route Context 或保持普通本地透传
                    if (route_candidate) begin // 处理 Route Context 候选 flit
                        if (route_header_valid && route_payload_valid) begin // 捕获合法 Route Context
                            expected_flit_count_q <= route_packet_flit_count; // 保存后继 packet 声明长度
                            accepted_flit_count_q <= 5'd0; // 清零后继 packet 接收计数
                            expected_packet_sequence_q <= route_expected_packet_sequence; // 保存后继 packet 序号
                            expected_vc_q <= route_logical_vc; // 保存不受 replay 改写影响的逻辑虚通道
                            expected_source_node_q <= route_source_node; // 保存上下文源节点
                            expected_destination_node_q <= route_destination_node; // 保存上下文目标节点
                            expected_plane_q <= route_logical_plane; // 保存上下文逻辑 plane
                            if (route_destination_domain == local_domain_i) state_q <= STATE_LOCAL_PACKET; // 目标域命中后等待本地 packet
                            else state_q <= STATE_REMOTE_PACKET; // 目标域未命中后等待跨域 packet
                        end else protocol_error_o <= 1'b1; // sticky 报告非法 Route Context
                    end // 结束 Route Context 候选处理
                end // 结束空闲状态提交
                STATE_LOCAL_PACKET, STATE_REMOTE_PACKET: begin // 检查并推进上下文绑定的后继 packet
                    if (route_candidate) protocol_error_o <= 1'b1; // 禁止 Route Context 嵌套在已绑定 packet 中
                    if (accepted_flit_count_q == 5'd0) begin // 检查后继 packet 首拍身份
                        if (!ingress_sop) protocol_error_o <= 1'b1; // 首拍缺少 SOP 时报告错误
                        if (ingress_packet_sequence != expected_packet_sequence_q) protocol_error_o <= 1'b1; // packet 序号不匹配时报告错误
                        if (!((!ingress_retry && (ingress_vc == expected_vc_q)) || (ingress_retry && (ingress_vc == `KDL_VC_ROLE_REPLAY)))) protocol_error_o <= 1'b1; // packet 物理 VC 与保存的逻辑 VC 或 replay 映射不匹配时报告错误
                        if (ingress_source_node != expected_source_node_q) protocol_error_o <= 1'b1; // packet 源节点不匹配时报告错误
                        if (ingress_destination_node != expected_destination_node_q) protocol_error_o <= 1'b1; // packet 目标节点不匹配时报告错误
                        if (ingress_plane != expected_plane_q) protocol_error_o <= 1'b1; // packet plane 不匹配时报告错误
                    end else if (ingress_sop) protocol_error_o <= 1'b1; // packet 中间再次出现 SOP 时报告错误
                    if (ingress_eop != expected_last_flit) protocol_error_o <= 1'b1; // EOP 与 Route Context 声明长度不一致时报告错误
                    if (ingress_eop) begin // EOP 到达后释放 packet 输出所有权
                        state_q <= STATE_IDLE; // 返回等待普通流量或新上下文状态
                        accepted_flit_count_q <= 5'd0; // 清零 packet 接收计数
                    end else if (accepted_flit_count_q < 5'd31) accepted_flit_count_q <= accepted_flit_count_q + 5'd1; // 未到 EOP 时推进有界 flit 计数
                    else protocol_error_o <= 1'b1; // 超出计数范围时保持状态并报告错误
                end // 结束上下文绑定 packet 提交
                default: begin // 非法状态恢复到空闲并报告错误
                    state_q <= STATE_IDLE; // 恢复到等待上下文状态
                    protocol_error_o <= 1'b1; // sticky 记录非法状态恢复
                end // 结束非法状态恢复
            endcase // 结束状态提交选择
        end // 结束输入握手状态推进
    end // 结束 Route Context 配对时序逻辑
    wire unused_route_metadata; // 汇总首增量尚未消费但已验证的上下文字段
    assign unused_route_metadata = ^{route_source_domain, route_topology_epoch, route_domain_hop_limit, route_slice_mask, route_policy, route_global_transaction_id, route_group_id}; // 防止工具把合法性相关解码字段误报为悬空
endmodule // 结束 kdlink_domain_adapter
