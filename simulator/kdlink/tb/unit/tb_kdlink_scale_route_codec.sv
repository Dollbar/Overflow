`timescale 1ns/1ps // 定义百万端点路由编解码自检时间单位
module tb_kdlink_scale_route_codec; // 定义 schema-4 与五级 radix-8 联合自检
    logic [14:0] source_domain; // 驱动十五位源 leaf 域
    logic [14:0] destination_domain; // 驱动十五位目的 leaf 域
    logic [4:0] source_node; // 驱动源 leaf 节点
    logic [4:0] destination_node; // 驱动目的 leaf 节点
    logic [15:0] topology_epoch; // 驱动十六位拓扑代次
    logic [7:0] domain_hop_limit; // 驱动八位跨域跳数
    logic [2:0] logical_plane; // 驱动八平面编号
    logic [1:0] slice_mask; // 驱动 bonded slice 掩码
    logic [2:0] route_policy; // 驱动路由策略
    logic [4:0] packet_flit_count; // 驱动 packet flit 数
    logic [11:0] expected_packet_sequence; // 驱动 packet 序号
    logic [63:0] global_transaction_id; // 驱动六十四位全局事务标识
    logic [31:0] group_id; // 驱动三十二位通信组标识
    logic [2:0] logical_vc; // 驱动逻辑虚通道
    logic [2:0] route_depth; // 驱动活动路由深度
    wire [511:0] encoded_payload; // 观察 schema-4 编码结果
    logic [511:0] decoder_payload; // 驱动独立解码输入
    wire [14:0] decoded_source_domain; // 观察解码源域
    wire [14:0] decoded_destination_domain; // 观察解码目的域
    wire [4:0] decoded_source_node; // 观察解码源节点
    wire [4:0] decoded_destination_node; // 观察解码目的节点
    wire [15:0] decoded_topology_epoch; // 观察解码拓扑代次
    wire [7:0] decoded_domain_hop_limit; // 观察解码跨域跳数
    wire [2:0] decoded_logical_plane; // 观察解码平面
    wire [1:0] decoded_slice_mask; // 观察解码 slice 掩码
    wire [2:0] decoded_route_policy; // 观察解码策略
    wire [4:0] decoded_packet_flit_count; // 观察解码 packet 长度
    wire [11:0] decoded_expected_packet_sequence; // 观察解码 packet 序号
    wire [63:0] decoded_global_transaction_id; // 观察解码事务标识
    wire [31:0] decoded_group_id; // 观察解码通信组
    wire [2:0] decoded_logical_vc; // 观察解码逻辑 VC
    wire [2:0] decoded_route_depth; // 观察解码路由深度
    wire decoded_payload_valid; // 观察 schema-4 payload 合法性
    logic [7:0] active_egress_mask; // 驱动五级共享出口可用掩码
    wire [2:0] digit0; // 观察根级 radix-8 数位
    wire [2:0] digit1; // 观察第二级 radix-8 数位
    wire [2:0] digit2; // 观察第三级 radix-8 数位
    wire [2:0] digit3; // 观察第四级 radix-8 数位
    wire [2:0] digit4; // 观察 leaf 前 radix-8 数位
    wire active0; // 观察根级选择出口可用性
    wire active1; // 观察第二级选择出口可用性
    wire active2; // 观察第三级选择出口可用性
    wire active3; // 观察第四级选择出口可用性
    wire active4; // 观察 leaf 前选择出口可用性
    wire valid_destination0; // 观察满规模目的域合法性
    wire [2:0] remaining0; // 观察根级剩余深度
    wire [2:0] remaining4; // 观察末级剩余深度
    wire final0; // 观察根级末级标志
    wire final4; // 观察第五级末级标志
    wire [2:0] rank0; // 观察根级 escape 等级
    wire [2:0] rank4; // 观察第五级 escape 等级
    logic [14:0] partial_destination; // 驱动非二次幂 profile 目的域
    wire partial_valid; // 观察非二次幂 profile 范围检查
    wire [2:0] partial_digit; // 观察非二次幂 profile 根级数位
    wire [2:0] digit_single; // 观察单级 profile 目的数位
    wire [2:0] digit_two0; // 观察两级 profile 高位数位
    wire [2:0] digit_two1; // 观察两级 profile 低位数位
    wire [2:0] digit_four0; // 观察四级 profile 最高数位
    wire [2:0] digit_four1; // 观察四级 profile 次高数位
    wire [2:0] digit_four2; // 观察四级 profile 次低数位
    wire [2:0] digit_four3; // 观察四级 profile 最低数位
    wire active_single; // 观察单级 profile 出口状态
    wire active_two0; // 观察两级 profile 高位出口状态
    wire active_two1; // 观察两级 profile 低位出口状态
    wire active_four0; // 观察四级 profile 最高位出口状态
    wire active_four1; // 观察四级 profile 次高位出口状态
    wire active_four2; // 观察四级 profile 次低位出口状态
    wire active_four3; // 观察四级 profile 最低位出口状态
    logic [14:0] irregular_destination; // 驱动三十三七十八和一万五千一百三十二NPU部署的目的叶域
    wire irregular_valid2; // 观察三十三NPU对应两叶域范围检查
    wire irregular_valid3; // 观察七十八NPU对应三叶域范围检查
    wire irregular_valid473; // 观察一万五千一百三十二NPU对应四百七十三叶域范围检查
    wire [2:0] irregular_digit2; // 观察两叶域单级数位
    wire [2:0] irregular_digit3; // 观察三叶域单级数位
    wire [2:0] irregular_digit473_0; // 观察四百七十三叶域三级最高数位
    wire [2:0] irregular_digit473_1; // 观察四百七十三叶域三级中间数位
    wire [2:0] irregular_digit473_2; // 观察四百七十三叶域三级最低数位
    integer domain_index; // 遍历全部 leaf 域
    kdlink_scale_route_context_encoder u_encoder ( // 实例化 schema-4 编码器
        .source_domain_i(source_domain), .destination_domain_i(destination_domain), // 连接十五位域字段
        .source_node_i(source_node), .destination_node_i(destination_node), // 连接 leaf 内节点字段
        .topology_epoch_i(topology_epoch), .domain_hop_limit_i(domain_hop_limit), // 连接拓扑代次和跳数
        .logical_plane_i(logical_plane), .slice_mask_i(slice_mask), // 连接平面和 slice 字段
        .route_policy_i(route_policy), .packet_flit_count_i(packet_flit_count), // 连接策略和 packet 长度
        .expected_packet_sequence_i(expected_packet_sequence), .global_transaction_id_i(global_transaction_id), // 连接序号和事务标识
        .group_id_i(group_id), .logical_vc_i(logical_vc), .route_depth_i(route_depth), // 连接通信组、逻辑 VC 和深度
        .payload_o(encoded_payload) // 观察完整编码 payload
    ); // 结束编码器实例
    kdlink_scale_route_context_decoder u_decoder ( // 实例化独立 schema-4 解码器
        .payload_i(decoder_payload), // 连接可注入非法位的 payload
        .source_domain_o(decoded_source_domain), .destination_domain_o(decoded_destination_domain), // 观察十五位域字段
        .source_node_o(decoded_source_node), .destination_node_o(decoded_destination_node), // 观察 leaf 内节点字段
        .topology_epoch_o(decoded_topology_epoch), .domain_hop_limit_o(decoded_domain_hop_limit), // 观察拓扑代次和跳数
        .logical_plane_o(decoded_logical_plane), .slice_mask_o(decoded_slice_mask), // 观察平面和 slice 字段
        .route_policy_o(decoded_route_policy), .packet_flit_count_o(decoded_packet_flit_count), // 观察策略和 packet 长度
        .expected_packet_sequence_o(decoded_expected_packet_sequence), .global_transaction_id_o(decoded_global_transaction_id), // 观察序号和事务标识
        .group_id_o(decoded_group_id), .logical_vc_o(decoded_logical_vc), .route_depth_o(decoded_route_depth), // 观察通信组、逻辑 VC 和深度
        .payload_valid_o(decoded_payload_valid) // 观察完整 payload 合法性
    ); // 结束解码器实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(32768), .STAGE_INDEX(0)) u_digit0 ( // 实例化五级 profile 根级
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit0), // 连接目的域、出口掩码和数位
        .profile_valid_o(), .destination_valid_o(valid_destination0), .selected_egress_active_o(active0), // 观察范围和出口状态
        .final_stage_o(final0), .remaining_stages_o(remaining0), .escape_rank_o(rank0) // 观察层次元数据
    ); // 结束根级数位实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(32768), .STAGE_INDEX(1)) u_digit1 ( // 实例化五级 profile 第二级
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit1), // 连接第二级数位选择
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(active1), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察第二级出口状态
    ); // 结束第二级数位实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(32768), .STAGE_INDEX(2)) u_digit2 ( // 实例化五级 profile 第三级
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit2), // 连接第三级数位选择
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(active2), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察第三级出口状态
    ); // 结束第三级数位实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(32768), .STAGE_INDEX(3)) u_digit3 ( // 实例化五级 profile 第四级
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit3), // 连接第四级数位选择
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(active3), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察第四级出口状态
    ); // 结束第四级数位实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(32768), .STAGE_INDEX(4)) u_digit4 ( // 实例化五级 profile 第五级
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit4), // 连接第五级数位选择
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(active4), // 观察第五级出口状态
        .final_stage_o(final4), .remaining_stages_o(remaining4), .escape_rank_o(rank4) // 观察末级层次元数据
    ); // 结束第五级数位实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(500), .STAGE_INDEX(0)) u_partial ( // 实例化非二次幂三级 profile
        .destination_domain_i(partial_destination), .active_egress_mask_i(8'hff), .selected_egress_o(partial_digit), // 连接非满规模目的域
        .profile_valid_o(), .destination_valid_o(partial_valid), .selected_egress_active_o(), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察范围检查
    ); // 结束非二次幂 profile 实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(8), .STAGE_INDEX(0)) u_digit_single ( // 实例化完整单级 radix-8 profile
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit_single), // 连接最低三位目的数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(active_single), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察单级出口状态
    ); // 结束单级 profile 实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(64), .STAGE_INDEX(0)) u_digit_two0 ( // 实例化两级 profile 高位路由级
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit_two0), // 连接六位目的域高数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(active_two0), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察两级高位出口状态
    ); // 结束两级高位实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(64), .STAGE_INDEX(1)) u_digit_two1 ( // 实例化两级 profile 低位路由级
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit_two1), // 连接六位目的域低数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(active_two1), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察两级低位出口状态
    ); // 结束两级低位实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(4096), .STAGE_INDEX(0)) u_digit_four0 ( // 实例化四级 profile 最高路由级
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit_four0), // 连接十二位目的域最高数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(active_four0), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察四级最高出口状态
    ); // 结束四级最高实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(4096), .STAGE_INDEX(1)) u_digit_four1 ( // 实例化四级 profile 次高路由级
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit_four1), // 连接十二位目的域次高数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(active_four1), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察四级次高出口状态
    ); // 结束四级次高实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(4096), .STAGE_INDEX(2)) u_digit_four2 ( // 实例化四级 profile 次低路由级
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit_four2), // 连接十二位目的域次低数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(active_four2), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察四级次低出口状态
    ); // 结束四级次低实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(4096), .STAGE_INDEX(3)) u_digit_four3 ( // 实例化四级 profile 最低路由级
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit_four3), // 连接十二位目的域最低数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(active_four3), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察四级最低出口状态
    ); // 结束四级最低实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(2), .STAGE_INDEX(0)) u_irregular_two ( // 实例化三十三NPU部署的两叶域单级路由
        .destination_domain_i(irregular_destination), .active_egress_mask_i(8'hff), .selected_egress_o(irregular_digit2), // 连接不规则目的域和全开出口
        .profile_valid_o(), .destination_valid_o(irregular_valid2), .selected_egress_active_o(), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察两叶域范围检查
    ); // 结束两叶域不规则实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(3), .STAGE_INDEX(0)) u_irregular_three ( // 实例化七十八NPU部署的三叶域单级路由
        .destination_domain_i(irregular_destination), .active_egress_mask_i(8'hff), .selected_egress_o(irregular_digit3), // 连接不规则目的域和全开出口
        .profile_valid_o(), .destination_valid_o(irregular_valid3), .selected_egress_active_o(), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察三叶域范围检查
    ); // 结束三叶域不规则实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(473), .STAGE_INDEX(0)) u_irregular_473_0 ( // 实例化一万五千一百三十二NPU部署的三级根路由
        .destination_domain_i(irregular_destination), .active_egress_mask_i(8'hff), .selected_egress_o(irregular_digit473_0), // 连接四百七十三叶域目的编号
        .profile_valid_o(), .destination_valid_o(irregular_valid473), .selected_egress_active_o(), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察大规模非整叶范围检查
    ); // 结束四百七十三叶域根级实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(473), .STAGE_INDEX(1)) u_irregular_473_1 ( // 实例化四百七十三叶域中间路由级
        .destination_domain_i(irregular_destination), .active_egress_mask_i(8'hff), .selected_egress_o(irregular_digit473_1), // 连接四百七十三叶域目的编号
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察中间数位
    ); // 结束四百七十三叶域中间级实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(473), .STAGE_INDEX(2)) u_irregular_473_2 ( // 实例化四百七十三叶域最低路由级
        .destination_domain_i(irregular_destination), .active_egress_mask_i(8'hff), .selected_egress_o(irregular_digit473_2), // 连接四百七十三叶域目的编号
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 观察最低数位
    ); // 结束四百七十三叶域最低级实例
    task automatic check_round_trip; // 检查 schema-4 位级往返
        begin // 开始组合传播和断言
            #0.1; // 等待编码器稳定
            decoder_payload = encoded_payload; // 将编码结果送入独立解码器
            #0.1; // 等待解码器稳定
            if (!decoded_payload_valid) $fatal(1, "valid scale Route Context was rejected"); // 要求合法 payload 被接受
            if (encoded_payload[511:191] != 321'd0) $fatal(1, "scale Route Context reserved bits are not zero"); // 要求保留位恒零
            if ({decoded_route_depth, decoded_logical_vc, decoded_group_id, decoded_global_transaction_id, decoded_expected_packet_sequence, decoded_packet_flit_count, decoded_route_policy, decoded_slice_mask, decoded_logical_plane, decoded_domain_hop_limit, decoded_topology_epoch, decoded_destination_node, decoded_source_node, decoded_destination_domain, decoded_source_domain} != encoded_payload[190:0]) $fatal(1, "scale Route Context round-trip mismatch"); // 要求全部字段位级一致
        end // 结束位级往返检查
    endtask // 结束 check_round_trip
    initial begin // 执行边界、穷举数位和非法位测试
        source_domain = 15'h5555; destination_domain = 15'h2aaa; source_node = 5'h15; destination_node = 5'h0a; // 驱动互补地址位型
        topology_epoch = 16'ha55a; domain_hop_limit = 8'd6; logical_plane = 3'd7; slice_mask = 2'b11; // 驱动合法拓扑字段
        route_policy = 3'd0; packet_flit_count = 5'd16; expected_packet_sequence = 12'ha5a; // 驱动合法 packet 边界
        global_transaction_id = 64'ha55a_5aa5_f00f_0ff0; group_id = 32'h55aa_a55a; logical_vc = 3'd5; route_depth = 3'd5; // 驱动事务与路由字段
        decoder_payload = 512'd0; active_egress_mask = 8'hff; partial_destination = 15'd0; irregular_destination = 15'd0; // 初始化独立测试输入
        check_round_trip(); // 检查第一组完整字段
        source_domain = 15'h2aaa; destination_domain = 15'h5555; source_node = 5'h0a; destination_node = 5'h15; // 翻转地址位型
        topology_epoch = 16'h5aa5; logical_plane = 3'd2; slice_mask = 2'b01; packet_flit_count = 5'd1; // 翻转拓扑和长度字段
        expected_packet_sequence = 12'h5a5; global_transaction_id = 64'h5aa5_a55a_0ff0_f00f; group_id = 32'haa55_5aa5; logical_vc = 3'd2; // 翻转事务位型
        check_round_trip(); // 检查第二组完整字段
        decoder_payload = encoded_payload; decoder_payload[511] = 1'b1; #0.1; // 注入最高保留位
        if (decoded_payload_valid) $fatal(1, "nonzero scale reserved bit was accepted"); // 要求拒绝非零保留位
        decoder_payload = encoded_payload; decoder_payload[190:188] = 3'd0; #0.1; // 注入零路由深度
        if (decoded_payload_valid) $fatal(1, "zero scale route depth was accepted"); // 要求拒绝零深度
        for (domain_index = 0; domain_index < 32768; domain_index = domain_index + 1) begin // 穷举全部十五位 leaf 域
            destination_domain = domain_index[14:0]; #0.001; // 驱动当前目的域并等待传播
            if (!valid_destination0) $fatal(1, "full-scale destination was rejected"); // 要求全部三万二千七百六十八域有效
            if ({digit0, digit1, digit2, digit3, digit4} != destination_domain) $fatal(1, "five-stage radix-8 digit mismatch"); // 要求五级数位重构完整十五位域
            if (!(active0 && active1 && active2 && active3 && active4)) $fatal(1, "active full-scale egress was rejected"); // 要求全开掩码接受每个数位
        end // 结束全部 leaf 域遍历
        for (domain_index = 0; domain_index < 256; domain_index = domain_index + 1) begin // 穷举全部八位出口活动掩码
            active_egress_mask = domain_index[7:0]; destination_domain = domain_index[0] ? 15'h7fff : 15'd0; #0.001; // 在全零和全一目的数位间交替并驱动掩码
            if ({active_single, active_two0, active_two1, active_four0, active_four1, active_four2, active_four3, active0, active1, active2, active3, active4} != {active_egress_mask[digit_single], active_egress_mask[digit_two0], active_egress_mask[digit_two1], active_egress_mask[digit_four0], active_egress_mask[digit_four1], active_egress_mask[digit_four2], active_egress_mask[digit_four3], active_egress_mask[digit0], active_egress_mask[digit1], active_egress_mask[digit2], active_egress_mask[digit3], active_egress_mask[digit4]}) $fatal(1, "radix-8 active mask projection mismatch"); // 要求所有 profile 精确映射所选出口可用位
        end // 结束出口活动掩码穷举
        destination_domain = 15'h7fff; active_egress_mask = 8'h7f; #0.1; // 关闭七号出口并选择全七数位
        if (active0 || active1 || active2 || active3 || active4) $fatal(1, "disabled radix-8 egress was accepted"); // 要求五级均识别失效出口
        if (final0 || !final4 || remaining0 != 3'd5 || remaining4 != 3'd1 || rank0 != 3'd1 || rank4 != 3'd5) $fatal(1, "scale stage metadata mismatch"); // 要求剩余深度和 escape 等级单调
        partial_destination = 15'd499; #0.1; // 驱动非二次幂 profile 最大合法域
        if (!partial_valid || partial_digit != 3'd7) $fatal(1, "partial profile upper valid destination failed"); // 要求边界内目的域有效且高数位正确
        partial_destination = 15'd500; #0.1; // 驱动第一个越界域
        if (partial_valid) $fatal(1, "partial profile out-of-range destination was accepted"); // 要求非二次幂空洞被拒绝
        irregular_destination = 15'd1; #0.1; // 驱动三十三NPU部署的最后合法叶域
        if (!irregular_valid2 || irregular_digit2 != 3'd1) $fatal(1, "33-NPU two-leaf route boundary failed"); // 要求两叶域部署接受叶域一
        irregular_destination = 15'd2; #0.1; // 驱动两叶域越界且三叶域合法的目的叶域
        if (irregular_valid2 || !irregular_valid3 || irregular_digit3 != 3'd2) $fatal(1, "78-NPU three-leaf route boundary failed"); // 要求三叶域部署仅接受零至二
        irregular_destination = 15'd472; #0.1; // 驱动一万五千一百三十二NPU部署的最后合法叶域
        if (irregular_valid2 || irregular_valid3 || !irregular_valid473 || {irregular_digit473_0, irregular_digit473_1, irregular_digit473_2} != 9'o730) $fatal(1, "15132-NPU 473-leaf route boundary failed"); // 要求四百七十三叶域末地址按七三零数位路由
        irregular_destination = 15'd473; #0.1; // 驱动四百七十三叶域部署第一个空洞域
        if (irregular_valid473) $fatal(1, "15132-NPU inactive leaf domain was accepted"); // 要求超出活动叶域范围的目的被拒绝
        destination_domain = 15'h0fed; active_egress_mask = 8'hff; #0.1; // 驱动四种 profile 可比较的十二位样例
        if (digit_single != destination_domain[2:0] || {digit_two0, digit_two1} != destination_domain[5:0] || {digit_four0, digit_four1, digit_four2, digit_four3} != destination_domain[11:0]) $fatal(1, "one two or four-stage radix reconstruction mismatch"); // 要求一、二、四级 profile 位段重构正确
        $display("TB_KDLINK_SCALE_ROUTE_CODEC_PASS irregular_totals=33,78,15132 leaves=2,3,473"); // 输出不规则跨叶规模验证通过签名
        $finish; // 结束自校验仿真
    end // 结束主测试序列
endmodule // 结束 tb_kdlink_scale_route_codec
