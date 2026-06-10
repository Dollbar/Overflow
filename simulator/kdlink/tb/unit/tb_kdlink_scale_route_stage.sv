`timescale 1ns/1ps // 定义百万端点路由级自检时间单位
`include "kdlink_defs.vh" // 引入 KDLink schema 和消息类型常量
module tb_kdlink_scale_route_stage; // 定义 schema-4 context-before-data 转发自检
    logic clk; // 产生路由级工作时钟
    logic rst_n; // 驱动低有效复位
    logic [15:0] current_epoch; // 驱动当前拓扑代次
    logic [15:0] previous_epoch; // 驱动上一拓扑代次
    logic previous_epoch_valid; // 驱动双代排空窗口
    logic scale_capability_enable; // 驱动 schema-4 能力协商状态
    logic [7:0] active_egress_mask; // 驱动出口可用掩码
    logic ingress_valid; // 驱动输入有效位
    wire ingress_ready; // 观察输入许可
    logic [639:0] ingress_flit; // 驱动完整 KDLink flit
    wire [7:0] egress_valid; // 观察八出口有效位
    logic [7:0] egress_ready; // 驱动八出口许可
    wire [5119:0] egress_flit; // 观察八出口 flit
    wire route_active; // 观察后继 packet 锁定状态
    wire [2:0] selected_egress; // 观察锁定出口
    wire final_stage; // 观察末级标志
    wire [2:0] escape_rank; // 观察单调 escape 等级
    wire protocol_error; // 观察协议 sticky 错误
    wire escape_violation; // 观察 escape sticky 错误
    wire topology_epoch_violation; // 观察拓扑代次 sticky 错误
    logic [14:0] destination_domain; // 驱动十五位目的域
    logic [15:0] route_epoch; // 驱动 Route Context 拓扑代次
    logic [7:0] hop_limit; // 驱动 Route Context 跳数上限
    logic [4:0] packet_flit_count; // 驱动后继 packet 长度
    logic [2:0] route_depth; // 驱动声明路由深度
    logic [14:0] source_domain; // 驱动 Route Context 源域
    logic [4:0] source_node; // 驱动 Route Context 源节点
    logic [4:0] destination_node; // 驱动 Route Context 目的节点
    logic [2:0] logical_plane; // 驱动 Route Context 逻辑平面
    logic [1:0] slice_mask; // 驱动 Route Context slice 掩码
    logic [2:0] route_policy; // 驱动 Route Context 路由策略
    logic [11:0] packet_sequence; // 驱动绑定 packet 序号
    logic [63:0] transaction_id; // 驱动全局事务标识
    logic [31:0] group_id; // 驱动通信组标识
    logic [2:0] logical_vc; // 驱动绑定逻辑 VC
    logic retry_mode; // 驱动 context 和数据 replay 编码
    logic [63:0] data_pattern; // 驱动宽数据翻转图样
    wire [511:0] route_payload; // 观察编码后的 schema-4 payload
    logic [639:0] context_flit; // 暂存完整 Route Context flit
    logic [639:0] data_flit; // 暂存后继数据 flit
    logic [639:0] forwarded_context; // 暂存路由级输出上下文
    kdlink_scale_route_context_encoder u_encoder ( // 实例化 schema-4 payload 编码器
        .source_domain_i(source_domain), .destination_domain_i(destination_domain), // 驱动可变源域和目的域
        .source_node_i(source_node), .destination_node_i(destination_node), // 驱动 leaf 内节点身份
        .topology_epoch_i(route_epoch), .domain_hop_limit_i(hop_limit), // 驱动拓扑代次和跳数
        .logical_plane_i(logical_plane), .slice_mask_i(slice_mask), // 驱动平面和 bonded slice
        .route_policy_i(route_policy), .packet_flit_count_i(packet_flit_count), // 驱动确定性策略和 packet 长度
        .expected_packet_sequence_i(packet_sequence), .global_transaction_id_i(transaction_id), // 驱动 packet 序号和事务标识
        .group_id_i(group_id), .logical_vc_i(logical_vc), .route_depth_i(route_depth), // 驱动通信组、逻辑 VC 和深度
        .payload_o(route_payload) // 观察完整编码 payload
    ); // 结束 schema-4 编码器实例
    kdlink_scale_route_stage #(.DOMAIN_COUNT(32768), .STAGE_INDEX(0)) u_stage ( // 实例化满规模根路由级
        .clk_i(clk), .rst_n_i(rst_n), // 连接时钟和复位
        .current_topology_epoch_i(current_epoch), .previous_topology_epoch_i(previous_epoch), .previous_epoch_valid_i(previous_epoch_valid), // 连接双代拓扑窗口
        .scale_capability_enable_i(scale_capability_enable), // 连接 schema-4 能力协商状态
        .active_egress_mask_i(active_egress_mask), // 连接当前 plane 出口掩码
        .ingress_valid_i(ingress_valid), .ingress_ready_o(ingress_ready), .ingress_flit_i(ingress_flit), // 连接输入握手
        .egress_valid_o(egress_valid), .egress_ready_i(egress_ready), .egress_flit_o(egress_flit), // 连接八出口握手
        .route_active_o(route_active), .selected_egress_o(selected_egress), .final_stage_o(final_stage), .escape_rank_o(escape_rank), // 观察锁定和层次状态
        .protocol_error_o(protocol_error), .escape_violation_o(escape_violation), .topology_epoch_violation_o(topology_epoch_violation) // 观察 sticky 错误
    ); // 结束满规模根级实例
    always #0.5 clk = ~clk; // 产生一纳秒时钟周期
    task automatic reset_stage; // 将路由级恢复到等待上下文状态
        begin // 开始复位序列
            ingress_valid = 1'b0; ingress_flit = 640'd0; egress_ready = 8'hff; // 清除输入并打开全部出口
            rst_n = 1'b0; repeat (2) @(negedge clk); // 保持低有效复位两个周期
            rst_n = 1'b1; @(negedge clk); // 释放复位并等待稳定
        end // 结束复位序列
    endtask // 结束 reset_stage
    task automatic build_context; // 根据编码 payload 构造完整 Route Context
        begin // 开始填充冻结 header
            #0.1; context_flit = 640'd0; // 等待编码器稳定并清零 flit
            context_flit[511:0] = route_payload; // 写入 schema-4 payload
            context_flit[515:512] = `KDL_SCALE_SCHEMA; // 写入 schema-4 标识
            context_flit[519:516] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT; // 写入 Route Context 消息类型
            context_flit[527:525] = retry_mode ? `KDL_VC_ROLE_REPLAY : logical_vc; // 写入逻辑 VC 或 replay 专用物理 VC
            context_flit[529] = 1'b1; context_flit[530] = 1'b1; // 标记单 flit packet 边界
            context_flit[531] = retry_mode; // 写入 context replay 标志
            context_flit[536:532] = source_node; context_flit[541:537] = destination_node; // 写入与 payload 一致的节点身份
            context_flit[544:542] = logical_plane; // 写入与 payload 一致的 plane
            context_flit[593:582] = packet_sequence; // 写入绑定 packet 序号
            context_flit[599:594] = 6'd0; context_flit[606:600] = 7'd64; // 写入单 flit 序号和 payload 字节数
            context_flit[639:608] = 32'hdead_beef; // 写入应由转发器清除的旧 CRC
        end // 结束 Route Context 构造
    endtask // 结束 build_context
    task automatic accept_context(input [15:0] epoch_value); // 接受指定有效代次的上下文
        begin // 开始上下文反压和握手检查
            route_epoch = epoch_value; build_context(); // 构造指定代次上下文
            ingress_flit = context_flit; ingress_valid = 1'b1; egress_ready = 8'd0; #0.1; // 在出口反压下驱动上下文
            if (ingress_ready || egress_valid != (8'b1 << destination_domain[14:12])) $fatal(1, "scale context backpressure routing mismatch"); // 要求有效位定向但输入被反压
            @(negedge clk); egress_ready = 8'hff; #0.1; // 打开出口许可
            if (!ingress_ready || egress_valid != (8'b1 << destination_domain[14:12])) $fatal(1, "scale context route digit mismatch"); // 要求根级选择最高三位
            forwarded_context = egress_flit[destination_domain[14:12]*640 +: 640]; // 捕获动态选择出口上下文
            if (forwarded_context[63:56] != hop_limit - 8'd1 || forwarded_context[639:608] != 32'd0) $fatal(1, "scale context hop or CRC rewrite mismatch"); // 要求仅递减跳数并清零 CRC
            @(negedge clk); ingress_valid = 1'b0; ingress_flit = 640'd0; #0.1; // 完成上下文握手并撤销输入
            if (!route_active || selected_egress != destination_domain[14:12]) $fatal(1, "scale packet route lock was not established"); // 要求后继 packet 锁定同一出口
        end // 结束有效上下文接收
    endtask // 结束 accept_context
    task automatic drive_data_flit(input [5:0] flit_sequence, input logic sop_value, input logic eop_value); // 驱动一拍绑定数据
        begin // 开始构造和发送数据 flit
            data_flit = 640'd0; // 清零数据 flit
            data_flit[511:0] = {8{data_pattern}}; // 写入可切换的全宽数据图样
            data_flit[515:512] = `KDL_SCHEMA_VERSION; data_flit[527:525] = retry_mode ? `KDL_VC_ROLE_REPLAY : logical_vc; // 写入基础 schema 和逻辑或 replay VC
            data_flit[529] = sop_value; data_flit[530] = eop_value; // 写入 packet 边界
            data_flit[531] = retry_mode; // 写入数据 replay 标志
            data_flit[536:532] = source_node; data_flit[541:537] = destination_node; data_flit[544:542] = logical_plane; // 写入绑定节点和平面身份
            data_flit[593:582] = packet_sequence; data_flit[599:594] = flit_sequence; // 写入绑定 packet 和 flit 序号
            data_flit[606:600] = eop_value ? 7'd16 : 7'd64; // 写入有效 payload 字节数
            ingress_flit = data_flit; ingress_valid = 1'b1; #0.1; // 驱动数据并等待组合传播
            if (!ingress_ready || egress_valid != (8'b1 << selected_egress)) $fatal(1, "scale packet did not remain on locked egress"); // 要求完整 packet 保持锁定出口
            if (egress_flit[selected_egress*640 +: 640] != data_flit) $fatal(1, "scale packet payload changed in route stage"); // 要求数据 flit 位级透明
            @(negedge clk); ingress_valid = 1'b0; ingress_flit = 640'd0; #0.1; // 完成数据握手并撤销输入
        end // 结束数据 flit 发送
    endtask // 结束 drive_data_flit
    task automatic reject_data_flit(input logic eop_value); // 驱动身份不匹配的数据并检查有界恢复
        begin // 开始非法 packet flit 构造
            data_flit = {10{64'ha5a5_5a5a_f0f0_0f0f}}; // 使用高翻转图样覆盖完整输入 flit
            data_flit[515:512] = `KDL_SCHEMA_VERSION; data_flit[527:525] = logical_vc; // 写入合法基础 schema 和 VC
            data_flit[529] = 1'b0; data_flit[530] = eop_value; data_flit[531] = 1'b0; // 故意破坏首拍 SOP 并按参数控制恢复边界
            data_flit[536:532] = source_node; data_flit[541:537] = destination_node; data_flit[544:542] = logical_plane; // 保持其余 packet 身份匹配
            data_flit[593:582] = packet_sequence; data_flit[599:594] = 6'h3f; // 使用非法 flit 序号触发配对错误
            ingress_flit = data_flit; ingress_valid = 1'b1; #0.1; // 驱动非法数据并等待消费
            if (!ingress_ready || egress_valid != 8'd0) $fatal(1, "invalid scale packet flit was forwarded or blocked"); // 要求非法数据被消费且不进入出口
            @(negedge clk); ingress_valid = 1'b0; ingress_flit = 640'd0; #0.1; // 完成非法数据消费
        end // 结束非法 packet flit 构造
    endtask // 结束 reject_data_flit
    task automatic reject_context(input [15:0] epoch_value, input [7:0] hop_value, input [2:0] depth_value, input [7:0] mask_value); // 驱动预期拒绝的上下文
        begin // 开始非法上下文检查
            route_epoch = epoch_value; hop_limit = hop_value; route_depth = depth_value; active_egress_mask = mask_value; // 驱动指定非法条件
            build_context(); ingress_flit = context_flit; ingress_valid = 1'b1; #0.1; // 驱动上下文并等待组合传播
            if (!ingress_ready || egress_valid != 8'd0) $fatal(1, "invalid scale context was forwarded or blocked"); // 要求消费非法上下文且不转发
            @(negedge clk); ingress_valid = 1'b0; ingress_flit = 640'd0; #0.1; // 完成非法上下文消费
            if (!protocol_error || route_active) $fatal(1, "invalid scale context did not raise protocol error"); // 要求 sticky 报错且不进入 packet 状态
        end // 结束非法上下文检查
    endtask // 结束 reject_context
    initial begin // 执行有效路径、双代窗口和非法边界测试
        clk = 1'b0; rst_n = 1'b0; current_epoch = 16'h0100; previous_epoch = 16'h00ff; previous_epoch_valid = 1'b1; scale_capability_enable = 1'b1; // 初始化时钟、双代窗口和能力协商
        active_egress_mask = 8'hff; ingress_valid = 1'b0; ingress_flit = 640'd0; egress_ready = 8'hff; // 初始化握手信号
        destination_domain = 15'h5abc; route_epoch = 16'h0100; hop_limit = 8'd6; packet_flit_count = 5'd2; route_depth = 3'd5; // 初始化合法满规模上下文
        source_domain = 15'h0123; source_node = 5'd3; destination_node = 5'd17; logical_plane = 3'd2; slice_mask = 2'b11; route_policy = 3'd0; // 初始化路由和 leaf 身份字段
        packet_sequence = 12'h456; transaction_id = 64'h0123_4567_89ab_cdef; group_id = 32'h1020_3040; logical_vc = 3'd4; // 初始化事务、组和 VC 字段
        retry_mode = 1'b0; data_pattern = 64'h0123_4567_89ab_cdef; // 初始化普通发送模式和数据图样
        context_flit = 640'd0; data_flit = 640'd0; forwarded_context = 640'd0; // 清零测试暂存 flit
        reset_stage(); // 复位后开始当前代次测试
        if (final_stage || escape_rank != 3'd1) $fatal(1, "scale root stage metadata mismatch"); // 要求根级 escape 等级为一且非末级
        accept_context(16'h0100); // 接受当前拓扑代次
        drive_data_flit(6'd0, 1'b1, 1'b0); // 发送两拍 packet 首拍
        drive_data_flit(6'd1, 1'b0, 1'b1); // 发送两拍 packet 尾拍
        if (route_active || protocol_error || escape_violation || topology_epoch_violation) $fatal(1, "valid scale packet left sticky error or lock"); // 要求合法 packet 无错误并释放锁
        reset_stage(); destination_domain = 15'h2c43; source_domain = 15'h7edc; source_node = 5'h1c; destination_node = 5'h0e; logical_plane = 3'd5; slice_mask = 2'b01; // 切换为互补路由和节点字段
        packet_sequence = 12'hba9; transaction_id = 64'hfedc_ba98_7654_3210; group_id = 32'hefdf_cfbf; logical_vc = 3'd1; packet_flit_count = 5'd1; retry_mode = 1'b1; data_pattern = 64'hfedc_ba98_7654_3210; // 切换事务字段并覆盖 replay 单拍路径
        accept_context(16'h0100); drive_data_flit(6'd0, 1'b1, 1'b1); // 转发 replay VC context 和单拍数据 packet
        if (route_active || protocol_error) $fatal(1, "valid replay packet did not release route lock"); // 要求 replay 身份规则成功完成
        reset_stage(); retry_mode = 1'b0; packet_flit_count = 5'd2; accept_context(16'h0100); // 建立用于错误恢复的两拍 packet 锁
        reject_data_flit(1'b0); // 消费无边界非法中间拍并继续有界排空
        if (!route_active || !protocol_error) $fatal(1, "invalid middle flit did not preserve bounded drain state"); // 要求中间错误保持 packet 锁直到边界
        reject_data_flit(1'b1); // 消费非法尾拍并恢复等待上下文
        if (route_active || !protocol_error) $fatal(1, "invalid tail flit did not recover context state"); // 要求可识别尾拍解除 packet 锁
        destination_domain = 15'h5abc; source_domain = 15'h0123; source_node = 5'd3; destination_node = 5'd17; logical_plane = 3'd2; slice_mask = 2'b11; // 恢复后续错误分类的原始身份字段
        packet_sequence = 12'h456; transaction_id = 64'h0123_4567_89ab_cdef; group_id = 32'h1020_3040; logical_vc = 3'd4; data_pattern = 64'h0123_4567_89ab_cdef; // 恢复原始事务字段
        reset_stage(); accept_context(16'h00ff); // 要求双代窗口接受上一代次
        drive_data_flit(6'd0, 1'b1, 1'b0); drive_data_flit(6'd1, 1'b0, 1'b1); // 排空上一代次 packet
        reset_stage(); previous_epoch_valid = 1'b0; // 关闭上一代次排空窗口
        reject_context(16'h00ff, 8'd6, 3'd5, 8'hff); // 拒绝窗口外旧代次
        if (!topology_epoch_violation || escape_violation) $fatal(1, "scale stale epoch error classification mismatch"); // 要求旧代次独立分类
        reset_stage(); reject_context(16'h0100, 8'd5, 3'd5, 8'hff); // 拒绝不足以越过五级和 leaf 的跳数
        if (!escape_violation || topology_epoch_violation) $fatal(1, "scale hop budget error classification mismatch"); // 要求跳数错误归入 escape
        reset_stage(); reject_context(16'h0100, 8'd6, 3'd4, 8'hff); // 拒绝与实例 profile 不同的声明深度
        if (!escape_violation) $fatal(1, "scale route depth mismatch was not classified"); // 要求深度错误归入 escape
        reset_stage(); active_egress_mask = 8'hff; // 恢复后准备失效出口测试
        reject_context(16'h0100, 8'd6, 3'd5, ~(8'b1 << destination_domain[14:12])); // 拒绝目的 radix-8 出口失效
        if (!escape_violation) $fatal(1, "scale disabled egress was not classified"); // 要求出口失效归入 escape
        reset_stage(); active_egress_mask = 8'hff; scale_capability_enable = 1'b0; // 关闭 schema-4 能力协商并恢复出口
        reject_context(16'h0100, 8'd6, 3'd5, 8'hff); // 拒绝未协商的 schema-4 Route Context
        if (escape_violation || topology_epoch_violation) $fatal(1, "scale capability rejection was misclassified"); // 要求能力拒绝仅报告协议错误
        $display("TB_KDLINK_SCALE_ROUTE_STAGE_PASS"); // 输出 manifest 约定的通过签名
        $finish; // 结束自校验仿真
    end // 结束主测试序列
endmodule // 结束 tb_kdlink_scale_route_stage
