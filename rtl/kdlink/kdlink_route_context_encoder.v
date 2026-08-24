module kdlink_route_context_encoder ( // 定义跨域路由上下文五百一十二位编码器
    input wire [7:0] source_domain_i, // 接收源域标识
    input wire [7:0] destination_domain_i, // 接收目标域标识
    input wire [4:0] source_node_i, // 接收源域内节点标识
    input wire [4:0] destination_node_i, // 接收目标域内节点标识
    input wire [7:0] topology_epoch_i, // 接收拓扑代次
    input wire [7:0] domain_hop_limit_i, // 接收跨域跳数上限
    input wire [2:0] logical_plane_i, // 接收逻辑交换 plane
    input wire [1:0] slice_mask_i, // 接收 bonded slice 使能掩码
    input wire [2:0] route_policy_i, // 接收路由策略编码
    input wire [4:0] packet_flit_count_i, // 接收后继 packet flit 数
    input wire [11:0] expected_packet_sequence_i, // 接收后继 packet 序号
    input wire [63:0] global_transaction_id_i, // 接收端到端事务标识
    input wire [31:0] group_id_i, // 接收全局通信组标识
    input wire [2:0] logical_vc_i, // 接收后继 packet 的逻辑虚通道
    output wire [511:0] payload_o // 输出位级冻结的路由上下文 payload
); // 结束路由上下文编码器端口声明
    assign payload_o[165:0] = {logical_vc_i, group_id_i, global_transaction_id_i, expected_packet_sequence_i, packet_flit_count_i, route_policy_i, slice_mask_i, logical_plane_i, domain_hop_limit_i, topology_epoch_i, destination_node_i, source_node_i, destination_domain_i, source_domain_i}; // 按冻结位图拼接全部可变 Route Context 字段
    /* verilator coverage_off */ // 排除协议强制恒零且不可翻转的保留字段
    assign payload_o[511:166] = 346'd0; // 按协议合同永久清零全部保留位
    /* verilator coverage_on */ // 恢复后续可变逻辑的覆盖率插桩
endmodule // 结束 kdlink_route_context_encoder

/* verilator lint_off DECLFILENAME */ // 同一冻结字段源文件同时提供配套 decoder design unit
module kdlink_route_context_decoder ( // 定义跨域路由上下文五百一十二位解码与合法性检查器
    input wire [511:0] payload_i, // 接收待检查的路由上下文 payload
    output wire [7:0] source_domain_o, // 输出源域标识
    output wire [7:0] destination_domain_o, // 输出目标域标识
    output wire [4:0] source_node_o, // 输出源域内节点标识
    output wire [4:0] destination_node_o, // 输出目标域内节点标识
    output wire [7:0] topology_epoch_o, // 输出拓扑代次
    output wire [7:0] domain_hop_limit_o, // 输出跨域跳数上限
    output wire [2:0] logical_plane_o, // 输出逻辑交换 plane
    output wire [1:0] slice_mask_o, // 输出 bonded slice 使能掩码
    output wire [2:0] route_policy_o, // 输出路由策略编码
    output wire [4:0] packet_flit_count_o, // 输出后继 packet flit 数
    output wire [11:0] expected_packet_sequence_o, // 输出后继 packet 序号
    output wire [63:0] global_transaction_id_o, // 输出端到端事务标识
    output wire [31:0] group_id_o, // 输出全局通信组标识
    output wire [2:0] logical_vc_o, // 输出后继 packet 的逻辑虚通道
    output wire payload_valid_o // 输出本实现增量支持的字段合法性
); // 结束路由上下文解码器端口声明
    assign source_domain_o = payload_i[7:0]; // 提取源域标识
    assign destination_domain_o = payload_i[15:8]; // 提取目标域标识
    assign source_node_o = payload_i[20:16]; // 提取源域内节点标识
    assign destination_node_o = payload_i[25:21]; // 提取目标域内节点标识
    assign topology_epoch_o = payload_i[33:26]; // 提取拓扑代次
    assign domain_hop_limit_o = payload_i[41:34]; // 提取跨域跳数上限
    assign logical_plane_o = payload_i[44:42]; // 提取逻辑交换 plane
    assign slice_mask_o = payload_i[46:45]; // 提取 bonded slice 使能掩码
    assign route_policy_o = payload_i[49:47]; // 提取路由策略编码
    assign packet_flit_count_o = payload_i[54:50]; // 提取后继 packet flit 数
    assign expected_packet_sequence_o = payload_i[66:55]; // 提取后继 packet 序号
    assign global_transaction_id_o = payload_i[130:67]; // 提取端到端事务标识
    assign group_id_o = payload_i[162:131]; // 提取全局通信组标识
    assign logical_vc_o = payload_i[165:163]; // 提取不受链路 replay VC 改写影响的逻辑虚通道
    assign payload_valid_o = (domain_hop_limit_o != 8'd0) && (slice_mask_o != 2'd0) && (route_policy_o == 3'd0) && (packet_flit_count_o >= 5'd1) && (packet_flit_count_o <= 5'd16) && (logical_vc_o <= 3'd5) && (payload_i[511:166] == 346'd0); // 检查首个实现增量允许的全部约束
endmodule // 结束 kdlink_route_context_decoder
/* verilator lint_on DECLFILENAME */ // 恢复后续源文件的 design-unit 文件名检查
