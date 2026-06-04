`timescale 1ns/1ps // 定义 Route Context 发送屏障自校验仿真时间单位
module tb_kdlink_route_pair_tx; // 定义互补身份、ACK 屏障、packet 顺序和错误恢复测试
    logic clk; // 生成发送控制器工作时钟
    logic rst_n; // 驱动低有效复位
    logic ingress_valid; // 驱动上游 flit 有效位
    wire ingress_ready; // 观察上游接收许可
    logic [639:0] ingress_flit; // 驱动上游完整 flit
    wire tx_valid; // 观察可靠端点发送有效位
    logic tx_ready; // 驱动可靠端点接收许可
    wire [95:0] tx_header; // 观察恢复逻辑 VC 的 header
    wire [511:0] tx_payload; // 观察发送 payload
    wire [6:0] tx_payload_bytes; // 观察发送有效字节数
    logic ack_valid; // 驱动 core 域 ACK 事件
    logic ack_phase; // 驱动 ACK phase
    logic [11:0] ack_collective_id; // 驱动 ACK collective 身份
    logic [11:0] ack_packet_seq; // 驱动 ACK packet 身份
    wire waiting_for_ack; // 观察生产 ACK 屏障状态
    wire pair_complete; // 观察上下文数据对完成脉冲
    wire protocol_error; // 观察 sticky 协议错误
    logic [7:0] source_domain; // 配置上下文源域
    logic [7:0] destination_domain; // 配置上下文目标域
    logic [4:0] source_node; // 配置上下文源节点
    logic [4:0] destination_node; // 配置上下文目标节点
    logic [7:0] topology_epoch; // 配置上下文拓扑代次
    logic [7:0] domain_hop_limit; // 配置上下文域跳数
    logic [2:0] logical_plane; // 配置上下文逻辑 plane
    logic [1:0] slice_mask; // 配置上下文 slice 掩码
    logic [2:0] route_policy; // 配置上下文路由策略
    logic [4:0] packet_flit_count; // 配置后继 packet 长度
    logic [11:0] expected_packet_sequence; // 配置后继 packet 序号
    logic [63:0] global_transaction_id; // 配置上下文事务标识
    logic [31:0] group_id; // 配置上下文通信组
    logic [2:0] logical_vc; // 配置后继 packet 逻辑 VC
    wire [511:0] route_payload; // 观察编码后的上下文 payload
    kdlink_route_context_encoder u_encoder ( // 实例化位级冻结的 Route Context 编码器
        .source_domain_i(source_domain), .destination_domain_i(destination_domain), // 连接源域和目标域配置
        .source_node_i(source_node), .destination_node_i(destination_node), // 连接源节点和目标节点配置
        .topology_epoch_i(topology_epoch), .domain_hop_limit_i(domain_hop_limit), // 连接拓扑代次和跳数配置
        .logical_plane_i(logical_plane), .slice_mask_i(slice_mask), // 连接 plane 和 slice 配置
        .route_policy_i(route_policy), .packet_flit_count_i(packet_flit_count), // 连接路由策略和 packet 长度配置
        .expected_packet_sequence_i(expected_packet_sequence), // 连接后继 packet 序号配置
        .global_transaction_id_i(global_transaction_id), .group_id_i(group_id), // 连接事务和通信组配置
        .logical_vc_i(logical_vc), .payload_o(route_payload) // 连接逻辑 VC 并观察编码结果
    ); // 结束 Route Context 编码器实例
    kdlink_route_pair_tx u_dut ( // 实例化生产 Route Context ACK 屏障控制器
        .clk_i(clk), .rst_n_i(rst_n), // 连接时钟和复位
        .ingress_valid_i(ingress_valid), .ingress_ready_o(ingress_ready), .ingress_flit_i(ingress_flit), // 连接上游流接口
        .tx_valid_o(tx_valid), .tx_ready_i(tx_ready), .tx_header_o(tx_header), // 连接可靠端点 header 流接口
        .tx_payload_o(tx_payload), .tx_payload_bytes_o(tx_payload_bytes), // 连接可靠端点 payload 流接口
        .ack_valid_i(ack_valid), .ack_phase_i(ack_phase), // 连接 ACK 有效位和 phase
        .ack_collective_id_i(ack_collective_id), .ack_packet_seq_i(ack_packet_seq), // 连接 ACK 身份字段
        .waiting_for_ack_o(waiting_for_ack), .pair_complete_o(pair_complete), // 观察屏障和完成状态
        .protocol_error_o(protocol_error) // 观察 sticky 协议错误
    ); // 结束 ACK 屏障控制器实例
    always #0.5 clk = ~clk; // 生成一 GHz 逻辑仿真时钟
    function automatic [639:0] make_context_flit ( // 构造单 flit Route Context
        input context_phase, input [11:0] context_collective_id, input [11:0] context_packet_seq
    ); // 结束上下文构造器端口声明
        reg [639:0] value; // 保存正在构造的完整 flit
        begin // 开始填写冻结 header 与 payload
            value = 640'd0; // 默认清零 CRC、header 和 payload
            value[511:0] = route_payload; // 写入编码后的上下文 payload
            value[515:512] = 4'd3; value[519:516] = 4'd8; // 写入 Route Context schema 和消息类型
            value[527:525] = logical_vc; value[528] = context_phase; // 写入逻辑 VC 和 phase
            value[529] = 1'b1; value[530] = 1'b1; // 标记单 flit 上下文的 SOP 和 EOP
            value[536:532] = source_node; value[541:537] = destination_node; // 镜像上下文节点字段
            value[544:542] = logical_plane; value[569:558] = context_collective_id; // 写入 plane 和 collective 身份
            value[593:582] = context_packet_seq; value[606:600] = 7'd64; // 写入 packet 身份和完整 payload 长度
            make_context_flit = value; // 返回构造完成的上下文 flit
        end // 结束上下文 flit 构造
    endfunction // 结束 make_context_flit
    function automatic [639:0] make_data_flit ( // 构造后继数据 packet 的一个 flit
        input [5:0] flit_sequence, input packet_retry, input [6:0] payload_bytes, input [511:0] payload
    ); // 结束数据构造器端口声明
        reg [639:0] value; // 保存正在构造的数据 flit
        begin // 开始填写后继 packet 身份与边界
            value = 640'd0; value[511:0] = payload; // 默认清零并写入测试 payload
            value[515:512] = 4'd2; value[519:516] = 4'd0; // 写入普通数据 schema 和消息类型
            value[527:525] = packet_retry ? 3'd6 : logical_vc; // replay 输入使用物理 VC6
            value[529] = (flit_sequence == 6'd0); // 首拍设置 SOP
            value[530] = (flit_sequence == packet_flit_count - 5'd1); // 声明匹配长度的 EOP
            value[531] = packet_retry; // 驱动上游 retry 标志以检查新跳清除
            value[536:532] = source_node; value[541:537] = destination_node; // 写入与上下文一致的节点身份
            value[544:542] = logical_plane; value[593:582] = expected_packet_sequence; // 写入 plane 和 packet 序号
            value[599:594] = flit_sequence; value[606:600] = payload_bytes; // 写入 flit 序号和有效字节数
            make_data_flit = value; // 返回构造完成的数据 flit
        end // 结束数据 flit 构造
    endfunction // 结束 make_data_flit
    task automatic apply_reset; // 施加可重复低有效复位
        begin // 开始复位全部测试接口
            rst_n = 1'b0; ingress_valid = 1'b0; ingress_flit = 640'd0; // 拉低复位并撤销上游输入
            ack_valid = 1'b0; ack_phase = 1'b0; ack_collective_id = 12'd0; ack_packet_seq = 12'd0; // 清零 ACK 接口
            repeat (3) @(posedge clk); // 保持复位覆盖多个时钟边沿
            rst_n = 1'b1; repeat (2) @(posedge clk); // 释放复位并等待状态稳定
        end // 结束可重复复位
    endtask // 结束 apply_reset
    task automatic send_flit (input [639:0] flit); // 向屏障控制器发送并检查一个合法 flit
        begin // 开始 valid-ready 握手
            @(negedge clk); ingress_flit = flit; ingress_valid = 1'b1; // 在非采样沿驱动稳定输入
            @(posedge clk); while (!ingress_ready) @(posedge clk); // 保持输入直到完成握手
            if (!tx_valid) $fatal(1, "accepted route-pair flit was not forwarded"); // 要求合法输入同步提交到可靠端点
            if (tx_header[19] || tx_header[15:13] != logical_vc) $fatal(1, "hop-local retry/VC normalization failed"); // 要求新跳清除 retry 并恢复逻辑 VC
            @(negedge clk); ingress_valid = 1'b0; ingress_flit = 640'd0; // 握手后安全撤销输入
        end // 结束单 flit 发送
    endtask // 结束 send_flit
    task automatic pulse_ack (input event_phase, input [11:0] event_collective_id, input [11:0] event_packet_seq); // 发送一个 ACK 事件
        begin // 开始单周期 ACK 激励
            @(negedge clk); ack_phase = event_phase; ack_collective_id = event_collective_id; ack_packet_seq = event_packet_seq; ack_valid = 1'b1; // 稳定驱动 ACK 身份
            @(posedge clk); @(negedge clk); ack_valid = 1'b0; // 完成采样后撤销 ACK 有效位
        end // 结束 ACK 事件发送
    endtask // 结束 pulse_ack
    task automatic run_pair ( // 运行一个完整上下文、屏障和数据 packet
        input context_phase, input [11:0] context_collective_id, input [11:0] context_packet_seq,
        input packet_retry, input [6:0] payload_bytes, input [511:0] first_payload, input [511:0] second_payload
    ); // 结束完整配对任务端口声明
        integer index; // 遍历后继 packet flit
        begin // 开始执行完整生产配对协议
            #0.1; send_flit(make_context_flit(context_phase, context_collective_id, context_packet_seq)); // 发送合法 Route Context
            if (!waiting_for_ack) $fatal(1, "Route Context did not arm ACK barrier"); // 要求上下文发送后立即进入屏障
            @(negedge clk); ingress_flit = make_data_flit(6'd0, packet_retry, payload_bytes, first_payload); ingress_valid = 1'b1; // 在 ACK 前立即尝试发送数据
            repeat (2) begin @(posedge clk); if (ingress_ready || tx_valid) $fatal(1, "data crossed Route Context ACK barrier"); end // 要求真实屏障持续阻挡后继数据
            @(negedge clk); ingress_valid = 1'b0; ingress_flit = 640'd0; // 撤销被阻挡的数据尝试
            pulse_ack(~context_phase, ~context_collective_id, ~context_packet_seq); // 发送所有身份均不匹配的 ACK
            if (!waiting_for_ack) $fatal(1, "unrelated ACK released Route Context barrier"); // 要求忽略无关 ACK
            pulse_ack(context_phase, context_collective_id, context_packet_seq); // 发送身份完全匹配的 ACK
            if (waiting_for_ack) $fatal(1, "matching ACK did not release Route Context barrier"); // 要求匹配 ACK 释放后继 packet
            for (index = 0; index < packet_flit_count; index = index + 1) begin // 发送声明长度的完整后继 packet
                send_flit(make_data_flit(index[5:0], packet_retry, payload_bytes, index[0] ? second_payload : first_payload)); // 交替 payload 并保持身份有序
            end // 结束后继 packet 发送循环
            if (!pair_complete) $fatal(1, "complete packet did not raise pair completion pulse"); // 要求最后一拍产生完成脉冲
            @(posedge clk); // 等待控制器返回上下文接收状态
        end // 结束完整配对协议
    endtask // 结束 run_pair
    initial begin // 执行两组互补位型、retry 归一化和非法上下文测试
        clk = 1'b0; rst_n = 1'b0; ingress_valid = 1'b0; ingress_flit = 640'd0; tx_ready = 1'b1; // 初始化公共时序和上游接口
        ack_valid = 1'b0; ack_phase = 1'b0; ack_collective_id = 12'd0; ack_packet_seq = 12'd0; // 初始化 ACK 接口
        source_domain = 8'hAA; destination_domain = 8'h55; source_node = 5'h15; destination_node = 5'h0A; // 配置第一组交替域节点身份
        topology_epoch = 8'hAA; domain_hop_limit = 8'h55; logical_plane = 3'h5; slice_mask = 2'h3; route_policy = 3'h0; // 配置第一组合法路由字段
        packet_flit_count = 5'd16; expected_packet_sequence = 12'hAAA; global_transaction_id = 64'hAAAA_AAAA_AAAA_AAAA; group_id = 32'h5555_5555; logical_vc = 3'h5; // 配置第一组 packet 和事务身份
        apply_reset(); // 进入第一组生产屏障场景
        run_pair(1'b1, 12'hAAA, 12'hAAA, 1'b0, 7'h2A, {512{1'b1}}, 512'hAAAA_AAAA_AAAA_AAAA); // 运行非 replay 的十六 flit 配对
        source_domain = 8'h55; destination_domain = 8'hAA; source_node = 5'h0A; destination_node = 5'h15; // 翻转全部域节点身份位
        topology_epoch = 8'h55; domain_hop_limit = 8'hAA; logical_plane = 3'h2; slice_mask = 2'h1; // 翻转全部路由字段位
        packet_flit_count = 5'd15; expected_packet_sequence = 12'h555; global_transaction_id = 64'h5555_5555_5555_5555; group_id = 32'hAAAA_AAAA; logical_vc = 3'h2; // 翻转全部 packet 和事务身份位
        run_pair(1'b0, 12'h555, 12'h555, 1'b1, 7'h15, 512'h5555_5555_5555_5555, {512{1'b0}}); // 运行上游 replay 输入并检查新跳归一化
        route_policy = 3'h7; #0.1; // 注入不支持的路由策略以覆盖非法上下文恢复
        @(negedge clk); ingress_flit = make_context_flit(1'b1, 12'hFFF, 12'hFFF); ingress_valid = 1'b1; // 驱动非法 Route Context
        @(posedge clk); if (!ingress_ready || tx_valid) $fatal(1, "invalid Route Context handling mismatch"); // 要求消费非法输入但不提交可靠端点
        @(negedge clk); ingress_valid = 1'b0; ingress_flit = 640'd0; // 撤销非法上下文输入
        @(posedge clk); if (!protocol_error) $fatal(1, "invalid Route Context did not set sticky error"); // 要求 sticky 错误置位
        apply_reset(); // 再次复位以检查 sticky 错误和状态可恢复
        if (protocol_error || waiting_for_ack) $fatal(1, "route-pair reset recovery failed"); // 要求复位清除错误和屏障状态
        $display("TB_KDLINK_ROUTE_PAIR_TX_PASS"); // 输出 manifest 要求的精确通过签名
        $finish; // 结束自校验仿真
    end // 结束测试主序列
endmodule // 结束 tb_kdlink_route_pair_tx
