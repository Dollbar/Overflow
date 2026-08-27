/* verilator lint_off DECLFILENAME */ // 同一冻结字段源文件提供命名明确的 encoder 与 decoder design unit
module kdlink_scale_route_context_encoder ( // 定义百万端点 schema-4 路由上下文编码器
    input wire [14:0] source_domain_i, // 接收十五位源 leaf 域标识
    input wire [14:0] destination_domain_i, // 接收十五位目的 leaf 域标识
    input wire [4:0] source_node_i, // 接收源 leaf 内节点标识
    input wire [4:0] destination_node_i, // 接收目的 leaf 内节点标识
    input wire [15:0] topology_epoch_i, // 接收十六位拓扑代次
    input wire [7:0] domain_hop_limit_i, // 接收跨域跳数上限
    input wire [2:0] logical_plane_i, // 接收八平面选择
    input wire [1:0] slice_mask_i, // 接收 bonded slice 使能掩码
    input wire [2:0] route_policy_i, // 接收路由策略编码
    input wire [4:0] packet_flit_count_i, // 接收后继 packet flit 数
    input wire [11:0] expected_packet_sequence_i, // 接收后继 packet 序号
    input wire [63:0] global_transaction_id_i, // 接收端到端事务标识
    input wire [31:0] group_id_i, // 接收全局通信组标识
    input wire [2:0] logical_vc_i, // 接收后继 packet 逻辑虚通道
    input wire [2:0] route_depth_i, // 接收一至五级活动路由深度
    output wire [511:0] payload_o // 输出位级冻结的 schema-4 payload
); // 结束 schema-4 编码器端口声明
    assign payload_o[190:0] = {route_depth_i, logical_vc_i, group_id_i, global_transaction_id_i, expected_packet_sequence_i, packet_flit_count_i, route_policy_i, slice_mask_i, logical_plane_i, domain_hop_limit_i, topology_epoch_i, destination_node_i, source_node_i, destination_domain_i, source_domain_i}; // 拼接全部 schema-4 可变字段
    /* verilator coverage_off */ // 排除协议强制恒零保留字段
    assign payload_o[511:191] = 321'd0; // 永久清零 schema-4 保留字段
    /* verilator coverage_on */ // 恢复后续可变逻辑覆盖率
endmodule // 结束 kdlink_scale_route_context_encoder

module kdlink_scale_route_context_decoder ( // 定义百万端点 schema-4 路由上下文解码器
    input wire [511:0] payload_i, // 接收待检查的 schema-4 payload
    output wire [14:0] source_domain_o, // 输出十五位源 leaf 域标识
    output wire [14:0] destination_domain_o, // 输出十五位目的 leaf 域标识
    output wire [4:0] source_node_o, // 输出源 leaf 内节点标识
    output wire [4:0] destination_node_o, // 输出目的 leaf 内节点标识
    output wire [15:0] topology_epoch_o, // 输出十六位拓扑代次
    output wire [7:0] domain_hop_limit_o, // 输出跨域跳数上限
    output wire [2:0] logical_plane_o, // 输出八平面选择
    output wire [1:0] slice_mask_o, // 输出 bonded slice 掩码
    output wire [2:0] route_policy_o, // 输出路由策略编码
    output wire [4:0] packet_flit_count_o, // 输出后继 packet flit 数
    output wire [11:0] expected_packet_sequence_o, // 输出后继 packet 序号
    output wire [63:0] global_transaction_id_o, // 输出端到端事务标识
    output wire [31:0] group_id_o, // 输出全局通信组标识
    output wire [2:0] logical_vc_o, // 输出后继 packet 逻辑虚通道
    output wire [2:0] route_depth_o, // 输出一至五级活动路由深度
    output wire payload_valid_o // 输出 schema-4 字段合法性
); // 结束 schema-4 解码器端口声明
    assign source_domain_o = payload_i[14:0]; // 提取十五位源域
    assign destination_domain_o = payload_i[29:15]; // 提取十五位目的域
    assign source_node_o = payload_i[34:30]; // 提取源 leaf 节点
    assign destination_node_o = payload_i[39:35]; // 提取目的 leaf 节点
    assign topology_epoch_o = payload_i[55:40]; // 提取十六位拓扑代次
    assign domain_hop_limit_o = payload_i[63:56]; // 提取跨域跳数上限
    assign logical_plane_o = payload_i[66:64]; // 提取八平面选择
    assign slice_mask_o = payload_i[68:67]; // 提取 bonded slice 掩码
    assign route_policy_o = payload_i[71:69]; // 提取路由策略
    assign packet_flit_count_o = payload_i[76:72]; // 提取后继 packet 长度
    assign expected_packet_sequence_o = payload_i[88:77]; // 提取后继 packet 序号
    assign global_transaction_id_o = payload_i[152:89]; // 提取端到端事务标识
    assign group_id_o = payload_i[184:153]; // 提取全局通信组标识
    assign logical_vc_o = payload_i[187:185]; // 提取不受 hop replay 改写的逻辑 VC
    assign route_depth_o = payload_i[190:188]; // 提取活动路由级数
    assign payload_valid_o = (domain_hop_limit_o != 8'd0) && (slice_mask_o != 2'd0) && (route_policy_o == 3'd0) && (packet_flit_count_o >= 5'd1) && (packet_flit_count_o <= 5'd16) && (logical_vc_o <= 3'd5) && (route_depth_o >= 3'd1) && (route_depth_o <= 3'd5) && (payload_i[511:191] == 321'd0); // 汇总 schema-4 payload 合同
endmodule // 结束 kdlink_scale_route_context_decoder
/* verilator lint_on DECLFILENAME */ // 恢复后续 design-unit 文件名检查
