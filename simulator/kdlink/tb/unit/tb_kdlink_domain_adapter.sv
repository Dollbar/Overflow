`timescale 1ns/1ps // 定义 domain adapter 自校验仿真时间单位
module tb_kdlink_domain_adapter; // 定义双域 Route Context 和 packet 锁定自校验测试
    logic clk; // 生成适配器工作时钟
    logic rst_n; // 驱动两个 domain adapter 低有效复位
    logic a_ingress_valid; // 驱动源域输入有效位
    wire a_ingress_ready; // 观察源域输入许可
    logic [639:0] a_ingress_flit; // 驱动源域输入 flit
    wire a_local_valid; // 观察源域本地输出有效位
    wire [639:0] a_local_flit; // 观察源域本地输出 flit
    wire a_remote_valid; // 观察源域跨域输出有效位
    wire a_remote_ready; // 连接目标域输入许可
    wire [639:0] a_remote_flit; // 观察源域跨域输出 flit
    wire a_protocol_error; // 观察源域 sticky 协议错误
    wire b_ingress_ready; // 观察目标域输入许可
    wire b_local_valid; // 观察目标域本地输出有效位
    logic b_local_ready; // 驱动目标域本地输出许可
    wire [639:0] b_local_flit; // 观察目标域本地输出 flit
    wire b_remote_valid; // 观察目标域意外跨域输出有效位
    wire [639:0] b_remote_flit; // 观察目标域意外跨域输出 flit
    wire b_protocol_error; // 观察目标域 sticky 协议错误
    logic [7:0] route_source_domain; // 配置 Route Context 源域
    logic [7:0] route_destination_domain; // 配置 Route Context 目标域
    logic [4:0] route_source_node; // 配置 Route Context 源节点
    logic [4:0] route_destination_node; // 配置 Route Context 目标节点
    logic [7:0] route_topology_epoch; // 配置 Route Context 拓扑代次
    logic [7:0] route_domain_hop_limit; // 配置 Route Context 跨域跳数上限
    logic [2:0] route_logical_plane; // 配置 Route Context 逻辑 plane
    logic [1:0] route_slice_mask; // 配置 Route Context bonded slice 掩码
    logic [2:0] route_policy; // 配置 Route Context 路由策略
    logic [4:0] route_packet_flit_count; // 配置 Route Context 后继 packet 长度
    logic [11:0] route_expected_packet_sequence; // 配置 Route Context 后继 packet 序号
    logic [63:0] route_global_transaction_id; // 配置 Route Context 端到端事务标识
    logic [31:0] route_group_id; // 配置 Route Context 全局通信组
    logic [2:0] route_logical_vc; // 配置后继 packet 的逻辑虚通道
    wire [511:0] route_payload; // 接收 Route Context 编码 payload
    integer a_local_seen; // 统计源域本地输出 flit 数
    integer b_local_seen; // 统计目标域本地输出 flit 数
    integer b_remote_seen; // 统计目标域意外跨域输出 flit 数
    integer overlong_index; // 遍历超长 packet 的错误排空边界
    logic [31:0] b_last_marker; // 保存目标域最近接收的数据标记
    kdlink_route_context_encoder u_route_encoder ( // 实例化测试激励 Route Context 编码器
        .source_domain_i(route_source_domain), // 连接源域配置
        .destination_domain_i(route_destination_domain), // 连接目标域配置
        .source_node_i(route_source_node), // 连接源节点配置
        .destination_node_i(route_destination_node), // 连接目标节点配置
        .topology_epoch_i(route_topology_epoch), // 连接拓扑代次配置
        .domain_hop_limit_i(route_domain_hop_limit), // 连接跨域跳数配置
        .logical_plane_i(route_logical_plane), // 连接逻辑 plane 配置
        .slice_mask_i(route_slice_mask), // 连接 bonded slice 配置
        .route_policy_i(route_policy), // 连接路由策略配置
        .packet_flit_count_i(route_packet_flit_count), // 连接后继 packet 长度配置
        .expected_packet_sequence_i(route_expected_packet_sequence), // 连接后继 packet 序号配置
        .global_transaction_id_i(route_global_transaction_id), // 连接端到端事务标识配置
        .group_id_i(route_group_id), // 连接全局通信组配置
        .logical_vc_i(route_logical_vc), // 连接后继 packet 逻辑虚通道配置
        .payload_o(route_payload) // 接收冻结格式 payload
    ); // 结束测试 Route Context 编码器实例
    kdlink_domain_adapter u_domain_a ( // 实例化源 domain adapter
        .clk_i(clk), // 连接公共仿真时钟
        .rst_n_i(rst_n), // 连接公共低有效复位
        .local_domain_i(8'd0), // 固定源域标识为零
        .ingress_valid_i(a_ingress_valid), // 连接源域测试输入有效位
        .ingress_ready_o(a_ingress_ready), // 观察源域测试输入许可
        .ingress_flit_i(a_ingress_flit), // 连接源域测试输入 flit
        .local_valid_o(a_local_valid), // 观察源域本地输出有效位
        .local_ready_i(1'b1), // 源域本地输出持续可接收
        .local_flit_o(a_local_flit), // 观察源域本地输出 flit
        .remote_valid_o(a_remote_valid), // 连接源域跨域输出有效位
        .remote_ready_i(a_remote_ready), // 连接目标域输入许可
        .remote_flit_o(a_remote_flit), // 连接源域跨域输出 flit
        .protocol_error_o(a_protocol_error) // 观察源域 sticky 错误
    ); // 结束源 domain adapter 实例
    kdlink_domain_adapter u_domain_b ( // 实例化目标 domain adapter
        .clk_i(clk), // 连接公共仿真时钟
        .rst_n_i(rst_n), // 连接公共低有效复位
        .local_domain_i(8'd1), // 固定目标域标识为一
        .ingress_valid_i(a_remote_valid), // 直接接收源域跨域输出有效位
        .ingress_ready_o(b_ingress_ready), // 返回目标域输入许可
        .ingress_flit_i(a_remote_flit), // 直接接收源域跨域输出 flit
        .local_valid_o(b_local_valid), // 观察目标域本地输出有效位
        .local_ready_i(b_local_ready), // 驱动目标域本地输出许可
        .local_flit_o(b_local_flit), // 观察目标域本地输出 flit
        .remote_valid_o(b_remote_valid), // 观察目标域意外跨域输出有效位
        .remote_ready_i(1'b1), // 未使用的继续转发路径持续可接收
        .remote_flit_o(b_remote_flit), // 观察目标域意外跨域输出 flit
        .protocol_error_o(b_protocol_error) // 观察目标域 sticky 错误
    ); // 结束目标 domain adapter 实例
    assign a_remote_ready = b_ingress_ready; // 将目标域输入许可返回源域跨域输出
    always #0.5 clk = ~clk; // 生成一 GHz 逻辑仿真时钟
    function automatic [639:0] make_data_flit ( // 构造 schema-2 数据 packet flit
        input [11:0] packet_sequence, // 接收 packet 序号
        input [5:0] flit_sequence, // 接收 packet 内 flit 序号
        input packet_sop, // 接收 packet 首拍标志
        input packet_eop, // 接收 packet 尾拍标志
        input [31:0] marker // 接收 payload 数据标记
    ); // 结束数据 flit 构造器端口声明
        reg [639:0] value; // 保存正在构造的数据 flit
        begin // 开始构造冻结字段的数据 flit
            value = 640'd0; // 默认清零 payload 和 header
            value[31:0] = marker; // 写入便于 scoreboard 检查的数据标记
            value[515:512] = 4'd2; // 写入本地域 schema 值
            value[519:516] = 4'd0; // 写入 DATA 消息类型
            value[527:525] = 3'd4; // 写入 PointToPoint VC
            value[529] = packet_sop; // 写入 SOP 标志
            value[530] = packet_eop; // 写入 EOP 标志
            value[536:532] = 5'd3; // 写入源域内节点三
            value[541:537] = 5'd29; // 写入目标域内节点二十九
            value[544:542] = 3'd2; // 写入逻辑 plane 二
            value[593:582] = packet_sequence; // 写入 packet 序号
            value[599:594] = flit_sequence; // 写入 packet 内 flit 序号
            value[606:600] = 7'd64; // 写入完整 payload 字节数
            make_data_flit = value; // 返回构造完成的数据 flit
        end // 结束数据 flit 构造
    endfunction // 结束 make_data_flit
    function automatic [639:0] make_route_flit ( // 构造单 flit Route Context packet
        input [511:0] payload // 接收已编码 Route Context payload
    ); // 结束 Route Context flit 构造器端口声明
        reg [639:0] value; // 保存正在构造的 Route Context flit
        begin // 开始构造冻结字段的 Route Context flit
            value = 640'd0; // 默认清零完整 flit
            value[511:0] = payload; // 写入 Route Context payload
            value[515:512] = 4'd3; // 写入层次路由 schema 值
            value[519:516] = 4'd8; // 写入 Route Context 消息类型
            value[527:525] = 3'd4; // 写入与后继 packet 相同的 VC
            value[529] = 1'b1; // 标记 Route Context 单 flit packet 的 SOP
            value[530] = 1'b1; // 标记 Route Context 单 flit packet 的 EOP
            value[536:532] = route_source_node; // 镜像 Route Context 源节点
            value[541:537] = route_destination_node; // 镜像 Route Context 目标节点
            value[544:542] = route_logical_plane; // 镜像 Route Context 逻辑 plane
            value[606:600] = 7'd64; // 写入完整 Route Context payload 字节数
            make_route_flit = value; // 返回构造完成的 Route Context flit
        end // 结束 Route Context flit 构造
    endfunction // 结束 make_route_flit
    task automatic send_a ( // 向源 domain adapter 发送一个 valid-ready flit
        input [639:0] flit // 接收待发送测试 flit
    ); // 结束源域发送任务端口声明
        begin // 开始执行保持到握手的 flit 发送
            @(negedge clk); // 在非采样沿开始驱动稳定激励
            a_ingress_flit = flit; // 驱动源域输入 flit
            a_ingress_valid = 1'b1; // 声明源域输入 flit 有效
            @(posedge clk); // 等待至少一个采样边沿
            while (!a_ingress_ready) @(posedge clk); // 在反压期间保持 valid 和 flit 稳定
            @(negedge clk); // 在后继非采样沿安全撤销激励
            a_ingress_valid = 1'b0; // 握手后撤销源域输入有效位
            a_ingress_flit = 640'd0; // 握手后清零测试输入总线
        end // 结束单 flit valid-ready 发送
    endtask // 结束 send_a
    task automatic apply_reset; // 对两个 domain adapter 施加公共低有效复位
        begin // 开始执行可重复测试复位
            rst_n = 1'b0; // 拉低公共复位
            a_ingress_valid = 1'b0; // 复位期间撤销输入有效位
            a_ingress_flit = 640'd0; // 复位期间清零输入 flit
            b_local_ready = 1'b1; // 默认目标域本地输出持续可接收
            repeat (4) @(posedge clk); // 保持复位覆盖多个时钟边沿
            rst_n = 1'b1; // 释放公共复位
            repeat (2) @(posedge clk); // 等待复位释放后的稳定窗口
        end // 结束可重复测试复位
    endtask // 结束 apply_reset
    always @(posedge clk or negedge rst_n) begin // 统计两个域的成功输出并保存数据标记
        if (!rst_n) begin // 复位清零全部 scoreboard 状态
            a_local_seen <= 0; // 清零源域本地输出计数
            b_local_seen <= 0; // 清零目标域本地输出计数
            b_remote_seen <= 0; // 清零目标域跨域输出计数
            b_last_marker <= 32'd0; // 清零目标域最近数据标记
        end else begin // 在正常运行期间统计完成握手的输出
            if (a_local_valid) a_local_seen <= a_local_seen + 1; // 统计持续 ready 的源域本地输出
            if (b_local_valid && b_local_ready) begin // 捕获目标域本地输出握手
                b_local_seen <= b_local_seen + 1; // 增加目标域本地输出计数
                b_last_marker <= b_local_flit[31:0]; // 保存目标域最近 payload 数据标记
            end // 结束目标域本地输出捕获
            if (b_remote_valid) b_remote_seen <= b_remote_seen + 1; // 统计不应出现的目标域继续转发 flit
        end // 结束正常运行 scoreboard 更新
    end // 结束输出 scoreboard 时序逻辑
    initial begin // 执行本地、跨域、反压和异常 packet 自校验序列
        clk = 1'b0; // 初始化仿真时钟为低
        rst_n = 1'b0; // 初始化公共复位有效
        a_ingress_valid = 1'b0; // 初始化源域输入无效
        a_ingress_flit = 640'd0; // 初始化源域输入 flit
        b_local_ready = 1'b1; // 初始化目标域本地输出许可
        route_source_domain = 8'd0; // 初始化 Route Context 源域为零
        route_destination_domain = 8'd1; // 初始化 Route Context 目标域为一
        route_source_node = 5'd3; // 初始化 Route Context 源节点为三
        route_destination_node = 5'd29; // 初始化 Route Context 目标节点为二十九
        route_topology_epoch = 8'd7; // 初始化 Route Context 拓扑代次
        route_domain_hop_limit = 8'd1; // 初始化双域直连 hop limit
        route_logical_plane = 3'd2; // 初始化 Route Context 逻辑 plane
        route_slice_mask = 2'b11; // 初始化双 slice 可用掩码
        route_policy = 3'd0; // 初始化 deterministic escape 路由策略
        route_packet_flit_count = 5'd3; // 初始化后继 packet 长度为三 flit
        route_expected_packet_sequence = 12'd10; // 初始化后继 packet 序号
        route_global_transaction_id = 64'h0123_4567_89AB_CDEF; // 初始化端到端事务标识
        route_group_id = 32'h1020_3040; // 初始化全局通信组标识
        route_logical_vc = 3'd4; // 初始化 PointToPoint 逻辑虚通道
        apply_reset(); // 进入第一个自校验场景前复位 DUT
        send_a(make_data_flit(12'd1, 6'd0, 1'b1, 1'b1, 32'd100)); // 发送不带上下文的本地域单 flit packet
        repeat (2) @(posedge clk); // 等待本地域 scoreboard 提交
        if (a_local_seen != 1 || b_local_seen != 0) $fatal(1, "local bypass mismatch a=%0d b=%0d", a_local_seen, b_local_seen); // 检查普通流量只进入源域本地路径
        send_a(make_route_flit(route_payload)); // 发送目标域为一的合法 Route Context
        send_a(make_data_flit(12'd10, 6'd0, 1'b1, 1'b0, 32'd200)); // 发送跨域 packet 首拍
        send_a(make_data_flit(12'd10, 6'd1, 1'b0, 1'b0, 32'd201)); // 发送跨域 packet 中间拍
        send_a(make_data_flit(12'd10, 6'd2, 1'b0, 1'b1, 32'd202)); // 发送跨域 packet 尾拍
        repeat (3) @(posedge clk); // 等待双 adapter scoreboard 提交
        if (b_local_seen != 3 || b_last_marker != 32'd202 || b_remote_seen != 0) $fatal(1, "remote delivery mismatch local=%0d marker=%0d remote=%0d", b_local_seen, b_last_marker, b_remote_seen); // 检查上下文被目标域消费且数据完整交付
        if (a_protocol_error || b_protocol_error) $fatal(1, "unexpected protocol error on legal path a=%b b=%b", a_protocol_error, b_protocol_error); // 检查合法双域路径无协议错误
        apply_reset(); // 复位后测试目标域 backpressure 传播
        route_packet_flit_count = 5'd1; // 配置单 flit 后继 packet
        route_expected_packet_sequence = 12'd20; // 配置反压场景 packet 序号
        #0.1; // 等待组合编码器传播新的 Route Context 字段
        send_a(make_route_flit(route_payload)); // 发送反压场景 Route Context
        @(negedge clk); // 在非采样沿配置稳定 backpressure 激励
        b_local_ready = 1'b0; // 阻塞目标域本地输出
        a_ingress_flit = make_data_flit(12'd20, 6'd0, 1'b1, 1'b1, 32'd300); // 驱动等待许可的跨域数据 flit
        a_ingress_valid = 1'b1; // 声明等待许可的跨域数据有效
        repeat (3) @(posedge clk); // 保持目标域反压多个周期
        if (a_ingress_ready) $fatal(1, "remote backpressure did not reach source adapter a_state=%0d b_state=%0d a_remote_ready=%b b_ready=%b", u_domain_a.state_q, u_domain_b.state_q, a_remote_ready, b_local_ready); // 检查 backpressure 跨两个 adapter 传播
        @(negedge clk); // 在非采样沿解除目标域 backpressure
        b_local_ready = 1'b1; // 解除目标域本地输出阻塞
        @(posedge clk); // 等待被阻塞 flit 完成握手
        @(negedge clk); // 在后继非采样沿安全撤销激励
        a_ingress_valid = 1'b0; // 握手后撤销源域输入有效位
        repeat (2) @(posedge clk); // 等待 scoreboard 提交反压场景
        if (b_local_seen != 1 || b_last_marker != 32'd300) $fatal(1, "backpressure delivery mismatch count=%0d marker=%0d", b_local_seen, b_last_marker); // 检查解除反压后数据准确交付
        apply_reset(); // 复位后测试 packet 序号不匹配
        route_packet_flit_count = 5'd1; // 配置单 flit 后继 packet
        route_expected_packet_sequence = 12'd30; // 配置期望 packet 序号三十
        #0.1; // 等待组合编码器传播新的 Route Context 字段
        send_a(make_route_flit(route_payload)); // 发送序号检查 Route Context
        send_a(make_data_flit(12'd31, 6'd0, 1'b1, 1'b1, 32'd400)); // 发送错误 packet 序号
        repeat (2) @(posedge clk); // 等待目标域 sticky 错误提交
        if (!b_protocol_error) $fatal(1, "packet sequence mismatch was not detected"); // 要求目标域报告 packet 序号错误
        apply_reset(); // 复位后测试提前 EOP
        route_packet_flit_count = 5'd2; // 声明两 flit 后继 packet
        route_expected_packet_sequence = 12'd40; // 配置提前 EOP 场景 packet 序号
        #0.1; // 等待组合编码器传播新的 Route Context 字段
        send_a(make_route_flit(route_payload)); // 发送提前 EOP 场景 Route Context
        send_a(make_data_flit(12'd40, 6'd0, 1'b1, 1'b1, 32'd500)); // 在第一 flit 错误声明 EOP
        repeat (2) @(posedge clk); // 等待提前 EOP 错误提交
        if (!b_protocol_error) $fatal(1, "early EOP was not detected"); // 要求目标域报告提前 EOP
        apply_reset(); // 复位后测试延迟 EOP
        route_packet_flit_count = 5'd1; // 声明单 flit 后继 packet
        route_expected_packet_sequence = 12'd50; // 配置延迟 EOP 场景 packet 序号
        #0.1; // 等待组合编码器传播新的 Route Context 字段
        send_a(make_route_flit(route_payload)); // 发送延迟 EOP 场景 Route Context
        send_a(make_data_flit(12'd50, 6'd0, 1'b1, 1'b0, 32'd600)); // 在声明尾拍错误缺少 EOP
        send_a(make_data_flit(12'd50, 6'd1, 1'b0, 1'b1, 32'd601)); // 在额外 flit 才声明 EOP
        repeat (2) @(posedge clk); // 等待延迟 EOP 错误提交
        if (!b_protocol_error) $fatal(1, "late EOP was not detected"); // 要求目标域报告延迟 EOP
        apply_reset(); // 复位后测试嵌套 Route Context
        route_packet_flit_count = 5'd2; // 声明两 flit 后继 packet
        route_expected_packet_sequence = 12'd60; // 配置嵌套上下文场景 packet 序号
        #0.1; // 等待组合编码器传播新的 Route Context 字段
        send_a(make_route_flit(route_payload)); // 发送外层 Route Context
        send_a(make_route_flit(route_payload)); // 错误地用第二个 Route Context 替代后继数据
        repeat (2) @(posedge clk); // 等待嵌套上下文错误提交
        if (!b_protocol_error) $fatal(1, "nested Route Context was not detected"); // 要求目标域报告嵌套 Route Context
        apply_reset(); // 复位后测试超过内部有界计数的未终止 packet
        route_packet_flit_count = 5'd16; // 使用协议允许的最大声明长度
        route_expected_packet_sequence = 12'd80; // 配置超长排空场景 packet 序号
        #0.1; // 等待编码器传播最大长度字段
        send_a(make_route_flit(route_payload)); // 发送最大长度 Route Context
        for (overlong_index = 0; overlong_index < 32; overlong_index = overlong_index + 1) begin // 连续发送三十二拍且故意不声明 EOP
            send_a(make_data_flit(12'd80, overlong_index[5:0], overlong_index == 0, 1'b0, 32'h8000_0000 | overlong_index)); // 覆盖计数饱和错误路径
        end // 结束超长 packet 非末拍发送
        send_a(make_data_flit(12'd80, 6'd32, 1'b0, 1'b1, 32'h8000_0020)); // 最终用 EOP 释放两个 adapter 的 packet 所有权
        repeat (2) @(posedge clk); // 等待超长错误和恢复提交
        if (!a_protocol_error || !b_protocol_error) $fatal(1, "overlong packet count saturation was not detected a=%b b=%b", a_protocol_error, b_protocol_error); // 要求源域和目标域都报告超长 packet
        apply_reset(); // 复位后测试非法 slice mask
        route_slice_mask = 2'b00; // 配置禁止全部 bonded slice 的非法上下文
        route_packet_flit_count = 5'd1; // 保持其他 packet 长度字段合法
        route_expected_packet_sequence = 12'd70; // 配置非法上下文关联序号
        #0.1; // 等待组合编码器传播非法 slice mask
        send_a(make_route_flit(route_payload)); // 发送应在源域被消费的非法 Route Context
        repeat (2) @(posedge clk); // 等待源域 sticky 错误提交
        if (!a_protocol_error || b_protocol_error) $fatal(1, "invalid context isolation mismatch a=%b b=%b", a_protocol_error, b_protocol_error); // 检查非法上下文未泄漏到目标域
        $display("TB_KDLINK_DOMAIN_ADAPTER_PASS local=1 remote_packet=3 backpressure=1 sequence_error=1 early_eop=1 late_eop=1 nested_context=1 overlong_packet=1 malformed_context=1"); // 输出严格 PASS 签名和覆盖场景
        $finish; // 正常结束自校验仿真
    end // 结束主测试激励序列
    initial begin // 提供测试超时保护
        #100000; // 等待远大于正常测试长度的仿真时间
        $fatal(1, "KDLink domain adapter timeout"); // 超时表示握手或状态机未前进
    end // 结束测试超时保护
endmodule // 结束 tb_kdlink_domain_adapter
