`timescale 1ns/1ps // 定义 Route Context 编解码自校验仿真时间单位
module tb_kdlink_route_context_codec; // 定义冻结字段、可变位与合法性自校验测试
    logic [7:0] source_domain; // 驱动源域标识
    logic [7:0] destination_domain; // 驱动目标域标识
    logic [4:0] source_node; // 驱动源节点标识
    logic [4:0] destination_node; // 驱动目标节点标识
    logic [7:0] topology_epoch; // 驱动拓扑代次
    logic [7:0] domain_hop_limit; // 驱动域跳数上限
    logic [2:0] logical_plane; // 驱动逻辑 plane
    logic [1:0] slice_mask; // 驱动 bonded slice 掩码
    logic [2:0] route_policy; // 驱动路由策略
    logic [4:0] packet_flit_count; // 驱动后继 packet 长度
    logic [11:0] expected_packet_sequence; // 驱动后继 packet 序号
    logic [63:0] global_transaction_id; // 驱动全局事务标识
    logic [31:0] group_id; // 驱动通信组标识
    logic [2:0] logical_vc; // 驱动逻辑虚通道
    wire [511:0] encoded_payload; // 观察编码后的冻结 payload
    logic [511:0] decoder_payload; // 驱动独立解码器输入
    wire [7:0] decoded_source_domain; // 观察解码源域
    wire [7:0] decoded_destination_domain; // 观察解码目标域
    wire [4:0] decoded_source_node; // 观察解码源节点
    wire [4:0] decoded_destination_node; // 观察解码目标节点
    wire [7:0] decoded_topology_epoch; // 观察解码拓扑代次
    wire [7:0] decoded_domain_hop_limit; // 观察解码域跳数
    wire [2:0] decoded_logical_plane; // 观察解码逻辑 plane
    wire [1:0] decoded_slice_mask; // 观察解码 slice 掩码
    wire [2:0] decoded_route_policy; // 观察解码路由策略
    wire [4:0] decoded_packet_flit_count; // 观察解码 packet 长度
    wire [11:0] decoded_expected_packet_sequence; // 观察解码 packet 序号
    wire [63:0] decoded_global_transaction_id; // 观察解码全局事务标识
    wire [31:0] decoded_group_id; // 观察解码通信组标识
    wire [2:0] decoded_logical_vc; // 观察解码逻辑虚通道
    wire decoded_payload_valid; // 观察完整 payload 合法性
    kdlink_route_context_encoder u_encoder ( // 实例化冻结格式编码器
        .source_domain_i(source_domain), // 连接源域激励
        .destination_domain_i(destination_domain), // 连接目标域激励
        .source_node_i(source_node), // 连接源节点激励
        .destination_node_i(destination_node), // 连接目标节点激励
        .topology_epoch_i(topology_epoch), // 连接拓扑代次激励
        .domain_hop_limit_i(domain_hop_limit), // 连接域跳数激励
        .logical_plane_i(logical_plane), // 连接逻辑 plane 激励
        .slice_mask_i(slice_mask), // 连接 slice 掩码激励
        .route_policy_i(route_policy), // 连接路由策略激励
        .packet_flit_count_i(packet_flit_count), // 连接 packet 长度激励
        .expected_packet_sequence_i(expected_packet_sequence), // 连接 packet 序号激励
        .global_transaction_id_i(global_transaction_id), // 连接事务标识激励
        .group_id_i(group_id), // 连接通信组激励
        .logical_vc_i(logical_vc), // 连接逻辑虚通道激励
        .payload_o(encoded_payload) // 观察编码结果
    ); // 结束编码器实例
    kdlink_route_context_decoder u_decoder ( // 实例化独立合法性解码器
        .payload_i(decoder_payload), // 连接可注入非法字段的 payload
        .source_domain_o(decoded_source_domain), // 观察源域结果
        .destination_domain_o(decoded_destination_domain), // 观察目标域结果
        .source_node_o(decoded_source_node), // 观察源节点结果
        .destination_node_o(decoded_destination_node), // 观察目标节点结果
        .topology_epoch_o(decoded_topology_epoch), // 观察拓扑代次结果
        .domain_hop_limit_o(decoded_domain_hop_limit), // 观察域跳数结果
        .logical_plane_o(decoded_logical_plane), // 观察 plane 结果
        .slice_mask_o(decoded_slice_mask), // 观察 slice 结果
        .route_policy_o(decoded_route_policy), // 观察策略结果
        .packet_flit_count_o(decoded_packet_flit_count), // 观察 packet 长度结果
        .expected_packet_sequence_o(decoded_expected_packet_sequence), // 观察 packet 序号结果
        .global_transaction_id_o(decoded_global_transaction_id), // 观察事务标识结果
        .group_id_o(decoded_group_id), // 观察通信组结果
        .logical_vc_o(decoded_logical_vc), // 观察逻辑 VC 结果
        .payload_valid_o(decoded_payload_valid) // 观察合法性结果
    ); // 结束解码器实例
    task automatic check_round_trip; // 检查全部冻结字段和保留位
        begin // 开始执行组合传播与逐字段检查
            #0.1; // 等待组合编码器稳定
            decoder_payload = encoded_payload; // 将编码结果送入独立解码器
            #0.1; // 等待组合解码器稳定
            if (!decoded_payload_valid) $fatal(1, "valid Route Context was rejected"); // 要求合法字段组合被接受
            if (encoded_payload[511:166] != 346'd0) $fatal(1, "reserved Route Context bits are not zero"); // 要求保留位永久为零
            if ({decoded_logical_vc, decoded_group_id, decoded_global_transaction_id, decoded_expected_packet_sequence, decoded_packet_flit_count, decoded_route_policy, decoded_slice_mask, decoded_logical_plane, decoded_domain_hop_limit, decoded_topology_epoch, decoded_destination_node, decoded_source_node, decoded_destination_domain, decoded_source_domain} != encoded_payload[165:0]) $fatal(1, "Route Context round-trip mismatch"); // 要求全部可变字段位级一致
        end // 结束编解码检查
    endtask // 结束 check_round_trip
    initial begin // 执行互补位型和每类非法字段测试
        source_domain = 8'h00; destination_domain = 8'h00; source_node = 5'h00; destination_node = 5'h00; // 初始化域和节点字段为零
        topology_epoch = 8'h00; domain_hop_limit = 8'h00; logical_plane = 3'h0; slice_mask = 2'h0; // 初始化拓扑与路由字段为零
        route_policy = 3'h0; packet_flit_count = 5'h00; expected_packet_sequence = 12'h000; // 初始化策略与 packet 字段为零
        global_transaction_id = 64'h0000_0000_0000_0000; group_id = 32'h0000_0000; logical_vc = 3'h0; // 初始化事务和 VC 字段为零
        decoder_payload = 512'd0; // 初始化解码输入为零
        #0.1; // 观察全零非法组合
        if (decoded_payload_valid) $fatal(1, "zero Route Context was accepted"); // 要求零 hop、零 slice 和零长度被拒绝
        source_domain = 8'hAA; destination_domain = 8'h55; source_node = 5'h15; destination_node = 5'h0A; // 驱动第一组互补域节点位型
        topology_epoch = 8'hAA; domain_hop_limit = 8'h55; logical_plane = 3'h5; slice_mask = 2'h3; // 驱动第一组合法拓扑位型
        route_policy = 3'h0; packet_flit_count = 5'd16; expected_packet_sequence = 12'hAAA; // 驱动合法边界长度和交替序号
        global_transaction_id = 64'hAAAA_AAAA_AAAA_AAAA; group_id = 32'h5555_5555; logical_vc = 3'h5; // 驱动第一组互补事务位型
        check_round_trip(); // 检查第一组合法位型
        source_domain = 8'h55; destination_domain = 8'hAA; source_node = 5'h0A; destination_node = 5'h15; // 翻转全部域节点位
        topology_epoch = 8'h55; domain_hop_limit = 8'hAA; logical_plane = 3'h2; slice_mask = 2'h1; // 翻转全部拓扑可变位
        packet_flit_count = 5'd15; expected_packet_sequence = 12'h555; // 翻转 packet 长度低位和全部序号位
        global_transaction_id = 64'h5555_5555_5555_5555; group_id = 32'hAAAA_AAAA; logical_vc = 3'h2; // 翻转全部事务和 VC 位
        check_round_trip(); // 检查第二组合法位型
        decoder_payload = encoded_payload; decoder_payload[49:47] = 3'h7; #0.1; // 注入不支持的路由策略
        if (decoded_payload_valid) $fatal(1, "unsupported route policy was accepted"); // 要求拒绝未知策略
        decoder_payload = encoded_payload; decoder_payload[54:50] = 5'd17; #0.1; // 注入超长 packet 声明
        if (decoded_payload_valid) $fatal(1, "oversized packet was accepted"); // 要求拒绝超过十六 flit
        decoder_payload = encoded_payload; decoder_payload[165:163] = 3'd7; #0.1; // 注入保留逻辑 VC
        if (decoded_payload_valid) $fatal(1, "reserved logical VC was accepted"); // 要求拒绝 VC6/VC7 作为逻辑数据 VC
        decoder_payload = encoded_payload; decoder_payload[511] = 1'b1; #0.1; // 注入非零保留位
        if (decoded_payload_valid) $fatal(1, "nonzero reserved bit was accepted"); // 要求冻结保留位检查生效
        route_policy = 3'h7; #0.1; route_policy = 3'h0; // 在编码器端翻转并恢复全部策略位
        source_domain = 8'h00; destination_domain = 8'h00; source_node = 5'h00; destination_node = 5'h00; // 将域和节点字段恢复为零以覆盖全部下降沿
        topology_epoch = 8'h00; domain_hop_limit = 8'h00; logical_plane = 3'h0; slice_mask = 2'h0; // 将拓扑和路由字段恢复为零
        packet_flit_count = 5'h00; expected_packet_sequence = 12'h000; // 将 packet 长度和序号恢复为零
        global_transaction_id = 64'h0000_0000_0000_0000; group_id = 32'h0000_0000; logical_vc = 3'h0; // 将事务和 VC 字段恢复为零
        decoder_payload = 512'd0; #0.1; // 返回全零位型以完成所有下降沿翻转
        $display("TB_KDLINK_ROUTE_CONTEXT_CODEC_PASS"); // 输出 manifest 要求的精确通过签名
        $finish; // 结束自校验仿真
    end // 结束测试主序列
endmodule // 结束 tb_kdlink_route_context_codec
