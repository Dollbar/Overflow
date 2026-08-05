`timescale 1ns/1ps // 定义可靠 Route Context 联合仿真的时间单位
`include "kdlink_defs.vh" // 引入 KDLink schema 消息类型和 VC 编码
module tb_kdlink_route_context_reliable; // 定义 Route Context 经可靠端点 PCS 和 SerDes 重放的自校验测试
    localparam [11:0] CONTEXT_SEQUENCE = 12'd100; // 固定 Route Context packet 序号
    localparam [11:0] DATA_SEQUENCE = 12'd101; // 固定后继数据 packet 序号
    localparam [11:0] GLOBAL_COMMIT_SEQUENCE = 12'd102; // 固定反向全局提交 packet 序号
    logic phy_clk; // 生成 PCS 与可靠端点物理时钟
    logic core_a_clk; // 生成源端点核心时钟
    logic core_b_clk; // 生成目标端点和 domain adapter 核心时钟
    logic rst_n; // 驱动全部测试对象低有效复位
    logic admin_up; // 驱动数字 SerDes 管理链路状态
    logic training; // 驱动 PCS training block
    logic marker; // 驱动 PCS alignment marker
    logic [15:0] marker_sequence; // 驱动 alignment marker 序号
    logic a_tx_valid; // 驱动生产 Route Context 配对控制器上游有效位
    wire a_tx_ready; // 观察生产 Route Context 配对控制器上游许可
    logic [95:0] a_tx_header; // 驱动生产配对控制器上游 header
    logic [511:0] a_tx_payload; // 驱动生产配对控制器上游 payload
    logic [6:0] a_tx_bytes; // 驱动生产配对控制器上游有效 payload 字节数
    wire [639:0] a_ingress_flit; // 重构生产配对控制器使用的完整上游 flit
    wire pair_tx_valid; // 观察生产配对控制器向可靠端点发送有效位
    wire pair_tx_ready; // 观察源可靠端点对生产配对控制器的许可
    wire [95:0] pair_tx_header; // 观察生产配对控制器恢复逻辑 VC 后的 header
    wire [511:0] pair_tx_payload; // 观察生产配对控制器输出 payload
    wire [6:0] pair_tx_bytes; // 观察生产配对控制器输出有效 payload 字节数
    wire pair_waiting_ack; // 观察生产配对控制器的 Route Context ACK 屏障
    wire pair_complete; // 观察生产配对控制器完成一个上下文数据对
    wire pair_protocol_error; // 观察生产配对控制器 sticky 协议错误
    wire a_ack_valid; // 观察源可靠端点同步到核心域的 ACK 事件
    wire [2:0] a_ack_vc; // 观察源可靠端点 ACK 物理 VC
    wire a_ack_phase; // 观察源可靠端点 ACK phase
    wire [11:0] a_ack_collective; // 观察源可靠端点 ACK collective 身份
    wire [11:0] a_ack_sequence; // 观察源可靠端点 ACK packet 序号
    wire a_forward_valid; // 观察源端点 forward flit 有效位
    wire [639:0] a_forward_flit; // 观察源端点 forward flit
    wire [639:0] a_forward_flit_faulted; // 向 PCS 提供带选择性 CRC 故障的 forward flit
    wire b_forward_valid; // 观察目标端点空闲 forward flit 有效位
    wire [639:0] b_forward_flit; // 观察目标端点空闲 forward flit
    logic b_tx_valid; // 驱动目标端点反向全局提交发送有效位
    wire b_tx_ready; // 观察目标端点反向全局提交发送许可
    logic [95:0] b_tx_header; // 驱动目标端点反向全局提交 header
    logic [511:0] b_tx_payload; // 驱动目标端点反向全局提交 payload
    logic [6:0] b_tx_bytes; // 驱动目标端点反向全局提交有效字节数
    wire a_reverse_valid; // 观察源端点 reverse word 有效位
    wire [127:0] a_reverse_word; // 观察源端点 reverse word
    wire b_reverse_valid; // 观察目标端点 ACK 或 NACK 有效位
    wire [127:0] b_reverse_word; // 观察目标端点 ACK 或 NACK word
    wire a_reverse_rx_valid; // 连接源端点 reverse 接收有效位
    wire [127:0] a_reverse_rx_word; // 连接源端点 reverse 接收 word
    wire b_reverse_rx_valid; // 连接目标端点 reverse 接收有效位
    wire [127:0] b_reverse_rx_word; // 连接目标端点 reverse 接收 word
    wire a_pcs_blocks_valid; // 观察源 PCS 十 lane block group 有效位
    wire [659:0] a_pcs_blocks; // 观察源 PCS 十 lane block group
    wire b_pcs_blocks_valid; // 观察目标 PCS 十 lane block group 有效位
    wire [659:0] b_pcs_blocks; // 观察目标 PCS 十 lane block group
    wire [9:0] a_pcs_rx_lane_valid; // 连接源 PCS 十 lane 接收有效位
    wire [659:0] a_pcs_rx_lane_blocks; // 连接源 PCS 十 lane 接收 blocks
    wire [9:0] b_pcs_rx_lane_valid; // 连接目标 PCS 十 lane 接收有效位
    wire [659:0] b_pcs_rx_lane_blocks; // 连接目标 PCS 十 lane 接收 blocks
    wire a_pcs_rx_flit_valid; // 连接源端点 PCS 接收 flit 有效位
    wire [639:0] a_pcs_rx_flit; // 连接源端点 PCS 接收 flit
    wire b_pcs_rx_flit_valid; // 连接目标端点 PCS 接收 flit 有效位
    wire [639:0] b_pcs_rx_flit; // 连接目标端点 PCS 接收 flit
    wire a_block_lock; // 观察源 PCS block lock
    wire a_deskew_lock; // 观察源 PCS deskew lock
    wire b_block_lock; // 观察目标 PCS block lock
    wire b_deskew_lock; // 观察目标 PCS deskew lock
    wire a_block_error; // 观察源 PCS block 错误
    wire a_deskew_overflow; // 观察源 PCS deskew overflow
    wire b_block_error; // 观察目标 PCS block 错误
    wire b_deskew_overflow; // 观察目标 PCS deskew overflow
    wire full_duplex_up; // 观察数字 SerDes 双向链路训练完成
    wire b_commit_valid; // 观察目标可靠端点提交有效位
    wire b_commit_ready; // 将 domain adapter 许可返回目标可靠端点
    wire [95:0] b_commit_header; // 观察目标可靠端点提交 header
    wire [511:0] b_commit_payload; // 观察目标可靠端点提交 payload
    wire [6:0] b_commit_bytes; // 观察目标可靠端点提交有效字节数
    wire b_commit_last; // 观察目标可靠端点提交 packet 尾拍
    wire a_commit_valid; // 观察源可靠端点收到反向全局提交有效位
    wire [95:0] a_commit_header; // 观察源可靠端点收到反向全局提交 header
    wire [511:0] a_commit_payload; // 观察源可靠端点收到反向全局提交 payload
    wire [6:0] a_commit_bytes; // 观察源可靠端点收到反向全局提交有效字节数
    wire a_commit_last; // 观察源可靠端点收到反向全局提交尾拍
    wire [511:0] encoded_global_commit_payload; // 连接冻结全局提交编码器到目标端点发送 payload
    wire [7:0] decoded_global_source_domain; // 观察反向全局提交解码源域
    wire [7:0] decoded_global_destination_domain; // 观察反向全局提交解码目的域
    wire [4:0] decoded_global_source_node; // 观察反向全局提交解码源节点
    wire [4:0] decoded_global_destination_node; // 观察反向全局提交解码目的节点
    wire [7:0] decoded_global_epoch; // 观察反向全局提交解码拓扑代次
    wire [63:0] decoded_global_transaction_id; // 观察反向全局提交解码事务标识
    wire [1:0] decoded_global_status; // 观察反向全局提交解码状态
    wire decoded_global_valid; // 观察反向全局提交 payload 合法性
    logic source_issue_valid; // 驱动源端全局事务保留请求
    wire source_issue_ready; // 观察源端全局事务保留许可
    wire source_completion_valid; // 观察真实传回全局提交释放源事务
    wire [63:0] source_completion_transaction_id; // 观察释放的源事务标识
    wire source_protocol_error; // 观察源全局事务协议错误
    wire source_retry_exhausted; // 观察源全局事务重试耗尽
    wire [4:0] source_outstanding_count; // 观察源全局事务保留数量
    wire [639:0] b_commit_flit; // 重构供 domain adapter 消费的 flit
    wire b_local_valid; // 观察目标 domain adapter 本地输出有效位
    wire [639:0] b_local_flit; // 观察目标 domain adapter 本地输出 flit
    wire b_remote_valid; // 观察目标 domain adapter 意外远端输出有效位
    wire [639:0] b_remote_flit; // 观察目标 domain adapter 意外远端输出 flit
    wire adapter_protocol_error; // 观察目标 domain adapter sticky 协议错误
    wire [9:0] a_replay_occupancy; // 观察源端点 replay window 占用
    wire a_retry_exhausted; // 观察源端点 retry 耗尽错误
    wire b_retry_exhausted; // 观察目标端点 retry 耗尽错误
    wire a_credit_error; // 观察源端点 credit 错误
    wire b_credit_error; // 观察目标端点 credit 错误
    wire a_reverse_error; // 观察源端点 reverse 错误
    wire b_reverse_error; // 观察目标端点 reverse 错误
    wire a_protocol_error; // 观察源端点协议错误
    wire b_protocol_error; // 观察目标端点协议错误
    wire a_cdc_error; // 观察源端点 CDC FIFO 错误
    wire b_cdc_error; // 观察目标端点 CDC FIFO 错误
    logic context_fault_armed; // 标记 Route Context 首发 CRC 故障尚未注入
    logic data_fault_armed; // 标记后继 data 首发 CRC 故障尚未注入
    wire context_fault_now; // 标记当前周期注入 Route Context CRC 故障
    wire data_fault_now; // 标记当前周期注入 data CRC 故障
    integer context_fault_seen; // 统计 Route Context 首发故障次数
    integer data_fault_seen; // 统计 data 首发故障次数
    integer context_replay_seen; // 统计 Route Context replay 发送次数
    integer data_replay_seen; // 统计 data replay 发送次数
    integer local_commit_seen; // 统计目标域本地数据输出次数
    integer context_ack_seen; // 统计生产控制器观察到的 Route Context ACK
    integer blocked_data_cycles; // 统计数据在 Route Context ACK 前被生产屏障阻挡的核心周期
    integer pair_complete_seen; // 统计生产控制器完成的上下文数据对
    integer global_commit_seen; // 统计经过 PCS 和 SerDes 反向传回的全局提交
    logic data_attempt_active; // 标记测试上游已在 ACK 前尝试发送后继数据
    logic [31:0] local_marker; // 保存目标域本地数据标记
    logic local_retry_seen; // 保存目标域本地数据是否来自 VC6 replay
    integer timeout_count; // 限制等待条件的最大周期数

    always #0.5 phy_clk = ~phy_clk; // 生成一 GHz 物理时钟
    always #0.7 core_a_clk = ~core_a_clk; // 生成异步源核心时钟
    always #0.8 core_b_clk = ~core_b_clk; // 生成异步目标核心时钟
    assign context_fault_now = context_fault_armed && a_forward_valid && !a_forward_flit[531] && (a_forward_flit[593:582] == CONTEXT_SEQUENCE); // 只损坏 Route Context 首次物理发送
    assign data_fault_now = data_fault_armed && a_forward_valid && !a_forward_flit[531] && (a_forward_flit[593:582] == DATA_SEQUENCE); // 只损坏后继 data 首次物理发送
    assign a_forward_flit_faulted = (context_fault_now || data_fault_now) ? (a_forward_flit ^ 640'd1) : a_forward_flit; // 翻转 payload 一位使 flit CRC 检查失败
    assign a_ingress_flit = {32'd0, a_tx_header, a_tx_payload}; // 将上游 header 和 payload 重构为完整 flit
    assign b_commit_flit = {32'd0, b_commit_header, b_commit_payload}; // 将提交接口重构为 adapter 使用的六百四十位布局

    kdlink_route_pair_tx u_route_pair_tx ( // 实例化生产级 Route Context ACK 屏障
        .clk_i(core_a_clk), .rst_n_i(rst_n), // 连接源核心时钟和复位
        .ingress_valid_i(a_tx_valid), .ingress_ready_o(a_tx_ready), .ingress_flit_i(a_ingress_flit), // 连接测试上游完整 flit
        .tx_valid_o(pair_tx_valid), .tx_ready_i(pair_tx_ready), // 连接可靠端点入口握手
        .tx_header_o(pair_tx_header), .tx_payload_o(pair_tx_payload), .tx_payload_bytes_o(pair_tx_bytes), // 连接可靠端点发送内容
        .ack_valid_i(a_ack_valid), .ack_phase_i(a_ack_phase), // 接收 core 域 ACK 有效位和 phase
        .ack_collective_id_i(a_ack_collective), .ack_packet_seq_i(a_ack_sequence), // 接收 ACK 身份三元组
        .waiting_for_ack_o(pair_waiting_ack), .pair_complete_o(pair_complete), // 观察生产屏障状态和完成事件
        .protocol_error_o(pair_protocol_error) // 观察配对协议错误
    ); // 结束生产 Route Context ACK 屏障实例

    kdlink_reliable_endpoint #( // 实例化显式允许 Route Context 的源可靠端点
        .INITIAL_CREDITS(16'd8), // 为各 VC 提供八个初始发送 credit
        .REPLAY_SLOT_BITS(9), // 保持基线 replay window 深度
        .AUTO_LINK_MANAGEMENT(1'b0), // 由测试直接启用链路避免管理流量干扰
        .ALLOW_ROUTE_CONTEXT(1'b1) // 开启 schema 三 Route Context 发送与接收
    ) u_endpoint_a ( // 开始源可靠端点连接
        .core_clk_i(core_a_clk), .core_rst_n_i(rst_n), // 连接源核心时钟和复位
        .phy_clk_i(phy_clk), .phy_rst_n_i(rst_n), // 连接公共物理时钟和复位
        .local_node_i(5'd3), .peer_node_i(5'd29), .local_slice_i(1'b0), // 固定本跳端点 identity
        .link_enable_i(1'b1), .tx_service_grant_i(1'b1), .reverse_service_grant_i(1'b1), // 持续授权发送服务
        .link_epoch_i(8'h2a), .tx_valid_i(pair_tx_valid), .tx_ready_o(pair_tx_ready), // 连接 epoch 和生产配对控制器发送握手
        .tx_header_i(pair_tx_header), .tx_payload_i(pair_tx_payload), .tx_payload_bytes_i(pair_tx_bytes), // 连接生产配对控制器发送内容
        .rx_commit_valid_o(a_commit_valid), .rx_commit_ready_i(1'b1), .rx_commit_header_o(a_commit_header), .rx_commit_payload_o(a_commit_payload), // 接收目标端经 forward 物理方向返回的全局提交
        .rx_commit_payload_bytes_o(a_commit_bytes), .rx_commit_last_o(a_commit_last), // 观察反向全局提交边界
        .phy_forward_tx_valid_o(a_forward_valid), .phy_forward_tx_flit_o(a_forward_flit), // 连接源 forward 发送
        .phy_forward_rx_valid_i(a_pcs_rx_flit_valid), .phy_forward_rx_flit_i(a_pcs_rx_flit), // 连接源 forward 接收
        .phy_reverse_tx_valid_o(a_reverse_valid), .phy_reverse_tx_word_o(a_reverse_word), // 连接源 reverse 发送
        .phy_reverse_rx_valid_i(a_reverse_rx_valid), .phy_reverse_rx_word_i(a_reverse_rx_word), // 连接源 reverse 接收
        .tx_credit_count_o(), .replay_occupancy_o(a_replay_occupancy), .link_up_o(), .link_state_o(), // 观察 replay window 并忽略固定 link 状态
        .replay_timeout_o(), .tx_service_request_o(), .reverse_service_request_o(), // 本测试不采样服务请求状态
        .tx_ack_valid_o(a_ack_valid), .tx_ack_vc_o(a_ack_vc), .tx_ack_phase_o(a_ack_phase), // 导出 core 域 ACK 事件
        .tx_ack_collective_id_o(a_ack_collective), .tx_ack_packet_seq_o(a_ack_sequence), // 导出 ACK collective 和序号
        .retry_exhausted_o(a_retry_exhausted), .duplicate_drop_o(), .credit_error_o(a_credit_error), // 观察源可靠性错误
        .reverse_error_o(a_reverse_error), .protocol_error_o(a_protocol_error), .cdc_error_o(a_cdc_error) // 观察源协议与 CDC 错误
    ); // 结束源可靠端点实例

    kdlink_reliable_endpoint #( // 实例化显式允许 Route Context 的目标可靠端点
        .INITIAL_CREDITS(16'd8), // 为各 VC 提供八个初始发送 credit
        .REPLAY_SLOT_BITS(9), // 保持基线 replay window 深度
        .AUTO_LINK_MANAGEMENT(1'b0), // 由测试直接启用链路避免管理流量干扰
        .ALLOW_ROUTE_CONTEXT(1'b1) // 开启 schema 三 Route Context 发送与接收
    ) u_endpoint_b ( // 开始目标可靠端点连接
        .core_clk_i(core_b_clk), .core_rst_n_i(rst_n), // 连接目标核心时钟和复位
        .phy_clk_i(phy_clk), .phy_rst_n_i(rst_n), // 连接公共物理时钟和复位
        .local_node_i(5'd29), .peer_node_i(5'd3), .local_slice_i(1'b0), // 固定本跳端点 identity
        .link_enable_i(1'b1), .tx_service_grant_i(1'b1), .reverse_service_grant_i(1'b1), // 持续授权发送服务
        .link_epoch_i(8'h2a), .tx_valid_i(b_tx_valid), .tx_ready_o(b_tx_ready), // 连接目标端反向全局提交发送握手
        .tx_header_i(b_tx_header), .tx_payload_i(b_tx_payload), .tx_payload_bytes_i(b_tx_bytes), // 连接目标端反向全局提交内容
        .rx_commit_valid_o(b_commit_valid), .rx_commit_ready_i(b_commit_ready), // 将可靠提交直接交给 domain adapter
        .rx_commit_header_o(b_commit_header), .rx_commit_payload_o(b_commit_payload), // 连接提交 header 与 payload
        .rx_commit_payload_bytes_o(b_commit_bytes), .rx_commit_last_o(b_commit_last), // 连接提交字节数与尾拍
        .phy_forward_tx_valid_o(b_forward_valid), .phy_forward_tx_flit_o(b_forward_flit), // 连接目标 forward 发送
        .phy_forward_rx_valid_i(b_pcs_rx_flit_valid), .phy_forward_rx_flit_i(b_pcs_rx_flit), // 连接目标 forward 接收
        .phy_reverse_tx_valid_o(b_reverse_valid), .phy_reverse_tx_word_o(b_reverse_word), // 连接目标 reverse 发送
        .phy_reverse_rx_valid_i(b_reverse_rx_valid), .phy_reverse_rx_word_i(b_reverse_rx_word), // 连接目标 reverse 接收
        .tx_credit_count_o(), .replay_occupancy_o(), .link_up_o(), .link_state_o(), // 目标端发送状态未使用
        .replay_timeout_o(), .tx_service_request_o(), .reverse_service_request_o(), // 本测试不采样服务请求状态
        .retry_exhausted_o(b_retry_exhausted), .duplicate_drop_o(), .credit_error_o(b_credit_error), // 观察目标可靠性错误
        .reverse_error_o(b_reverse_error), .protocol_error_o(b_protocol_error), .cdc_error_o(b_cdc_error) // 观察目标协议与 CDC 错误
    ); // 结束目标可靠端点实例

    kdlink_domain_adapter u_domain_b ( // 实例化目标域 Route Context 消费和 packet 配对适配器
        .clk_i(core_b_clk), .rst_n_i(rst_n), .local_domain_i(8'd1), // 连接目标核心时钟复位和域标识
        .ingress_valid_i(b_commit_valid), .ingress_ready_o(b_commit_ready), .ingress_flit_i(b_commit_flit), // 连接可靠提交输入
        .local_valid_o(b_local_valid), .local_ready_i(1'b1), .local_flit_o(b_local_flit), // 连接持续可接收的本地输出
        .remote_valid_o(b_remote_valid), .remote_ready_i(1'b1), .remote_flit_o(b_remote_flit), // 观察不应使用的继续转发输出
        .protocol_error_o(adapter_protocol_error) // 观察上下文配对错误
    ); // 结束目标 domain adapter 实例

    kdlink_global_commit_codec u_global_commit_encoder ( // 实例化目的域全局提交 payload 编码器
        .source_domain_i(8'd1), .destination_domain_i(8'd0), // 编码确认返回方向的域身份
        .source_node_i(5'd29), .destination_node_i(5'd3), // 编码确认返回方向的 leaf 节点身份
        .topology_epoch_i(8'd7), .global_transaction_id_i(64'h0123_4567_89ab_cdef), // 编码原事务拓扑代次和全局标识
        .status_i(`KDL_GLOBAL_STATUS_COMMITTED), .payload_o(encoded_global_commit_payload) // 编码目的端已提交状态
    ); // 结束全局提交 payload 编码器实例

    kdlink_global_commit_decoder u_global_commit_decoder ( // 实例化源域全局提交 payload 解码器
        .payload_i(a_commit_payload), .source_domain_o(decoded_global_source_domain), // 解码确认源域
        .destination_domain_o(decoded_global_destination_domain), .source_node_o(decoded_global_source_node), // 解码确认目的域和源节点
        .destination_node_o(decoded_global_destination_node), .topology_epoch_o(decoded_global_epoch), // 解码确认目的节点和拓扑代次
        .global_transaction_id_o(decoded_global_transaction_id), .status_o(decoded_global_status), // 解码全局事务标识和提交状态
        .payload_valid_o(decoded_global_valid) // 检查全局提交保留位和状态编码
    ); // 结束全局提交 payload 解码器实例

    kdlink_global_transaction_source #(.REPLAY_GRACE_CYCLES(12'd32)) u_global_source ( // 实例化源端全局事务保留控制器
        .clk_i(core_a_clk), .rst_n_i(rst_n), .issue_valid_i(source_issue_valid), .issue_ready_o(source_issue_ready), // 连接源核心时钟复位和事务请求
        .issue_transaction_id_i(64'h0123_4567_89ab_cdef), .issue_topology_epoch_i(8'd7), .issue_timeout_quanta_i(12'hfff), // 保留与 Route Context 相同的全局事务身份
        .send_valid_o(), .send_ready_i(1'b1), .send_transaction_id_o(), .send_topology_epoch_o(), .send_retry_count_o(), // 本测试由 Route Context 数据路径执行已保留发送命令
        .commit_valid_i(a_commit_valid && (a_commit_header[7:4] == `KDL_MESSAGE_TYPE_GLOBAL_COMMIT) && decoded_global_valid), // 仅接受真实反向可靠传输后的合法消息九
        .commit_transaction_id_i(decoded_global_transaction_id), .commit_topology_epoch_i(decoded_global_epoch), .commit_status_i(decoded_global_status), // 连接解码后的全局提交身份
        .route_reset_i(1'b0), .route_topology_epoch_i(8'd7), // 本联合路径不额外触发路由软复位
        .completion_valid_o(source_completion_valid), .completion_transaction_id_o(source_completion_transaction_id), // 观察源事务释放
        .protocol_error_o(source_protocol_error), .retry_exhausted_o(source_retry_exhausted), .outstanding_count_o(source_outstanding_count) // 观察源端全局事务状态
    ); // 结束源端全局事务保留控制器实例

    kdlink_pcs u_pcs_a ( // 实例化源端单 slice 十 lane PCS
        .clk_i(phy_clk), .rst_n_i(rst_n), .tx_flit_valid_i(a_forward_valid), .tx_flit_i(a_forward_flit_faulted), // 连接源 forward flit 并允许选择性 CRC 损坏
        .tx_training_i(training), .tx_alignment_marker_i(marker), .tx_marker_sequence_i(marker_sequence), // 连接 PCS 训练控制
        .tx_blocks_valid_o(a_pcs_blocks_valid), .tx_blocks_o(a_pcs_blocks), // 输出源十 lane block group
        .rx_lane_valid_i(a_pcs_rx_lane_valid), .rx_lane_blocks_i(a_pcs_rx_lane_blocks), // 接收 SerDes 十 lane blocks
        .rx_flit_valid_o(a_pcs_rx_flit_valid), .rx_flit_o(a_pcs_rx_flit), // 输出恢复的 forward flit
        .rx_block_lock_o(a_block_lock), .rx_deskew_locked_o(a_deskew_lock), // 观察源 PCS 锁定
        .rx_block_error_o(a_block_error), .rx_deskew_overflow_o(a_deskew_overflow) // 观察源 PCS 错误
    ); // 结束源 PCS 实例

    kdlink_pcs u_pcs_b ( // 实例化目标端单 slice 十 lane PCS
        .clk_i(phy_clk), .rst_n_i(rst_n), .tx_flit_valid_i(b_forward_valid), .tx_flit_i(b_forward_flit), // 连接目标 forward flit
        .tx_training_i(training), .tx_alignment_marker_i(marker), .tx_marker_sequence_i(marker_sequence), // 连接 PCS 训练控制
        .tx_blocks_valid_o(b_pcs_blocks_valid), .tx_blocks_o(b_pcs_blocks), // 输出目标十 lane block group
        .rx_lane_valid_i(b_pcs_rx_lane_valid), .rx_lane_blocks_i(b_pcs_rx_lane_blocks), // 接收 SerDes 十 lane blocks
        .rx_flit_valid_o(b_pcs_rx_flit_valid), .rx_flit_o(b_pcs_rx_flit), // 输出恢复的 forward flit
        .rx_block_lock_o(b_block_lock), .rx_deskew_locked_o(b_deskew_lock), // 观察目标 PCS 锁定
        .rx_block_error_o(b_block_error), .rx_deskew_overflow_o(b_deskew_overflow) // 观察目标 PCS 错误
    ); // 结束目标 PCS 实例

    kdlink_serdes_link_model #( // 复用上游已存在的数字全双工 SerDes link model
        .PROPAGATION_CYCLES(4), // 配置每方向四周期传播延迟
        .MAX_LANE_SKEW_CYCLES(2), // 配置十 lane 最大两周期 skew
        .TRAINING_CYCLES(8) // 配置八周期数字训练时间
    ) u_forward_link ( // 开始十 lane 双向 SerDes 连接
        .clk_i(phy_clk), .rst_n_i(rst_n), .admin_up_i(admin_up), // 连接物理时钟复位和管理状态
        .a_to_b_lane_up_i(10'h3ff), .b_to_a_lane_up_i(10'h3ff), // 启用两个方向全部十条 lane
        .a_tx_group_valid_i(a_pcs_blocks_valid), .a_tx_group_blocks_i(a_pcs_blocks), // 连接源到目标 block group
        .b_tx_group_valid_i(b_pcs_blocks_valid), .b_tx_group_blocks_i(b_pcs_blocks), // 连接目标到源 block group
        .inject_a_to_b_drop_i(10'd0), .inject_a_to_b_corrupt_i(10'd0), // 禁用额外源到目标 lane 故障
        .inject_b_to_a_drop_i(10'd0), .inject_b_to_a_corrupt_i(10'd0), // 禁用额外目标到源 lane 故障
        .ber_period_groups_i(32'd0), .ber_lane_i(4'd0), // 禁用周期 BER 注入
        .a_rx_lane_valid_o(a_pcs_rx_lane_valid), .a_rx_lane_blocks_o(a_pcs_rx_lane_blocks), // 返回目标到源 blocks
        .b_rx_lane_valid_o(b_pcs_rx_lane_valid), .b_rx_lane_blocks_o(b_pcs_rx_lane_blocks), // 返回源到目标 blocks
        .a_to_b_state_o(), .b_to_a_state_o(), .full_duplex_up_o(full_duplex_up), // 观察训练完成状态
        .a_to_b_groups_o(), .b_to_a_groups_o(), .dropped_blocks_o(), .corrupted_blocks_o() // 忽略模型统计计数
    ); // 结束数字 SerDes link model 实例

    kdlink_reverse_channel_model #(.PROPAGATION_CYCLES(4)) u_reverse_link ( // 实例化独立可靠控制 reverse channel model
        .clk_i(phy_clk), .rst_n_i(rst_n), // 连接物理时钟和复位
        .a_tx_valid_i(a_reverse_valid), .a_tx_word_i(a_reverse_word), // 连接源 reverse 发送
        .b_tx_valid_i(b_reverse_valid), .b_tx_word_i(b_reverse_word), // 连接目标 ACK NACK 发送
        .inject_a_to_b_corrupt_i(1'b0), .inject_b_to_a_corrupt_i(1'b0), // 禁用 reverse 数据损坏
        .inject_a_to_b_drop_i(1'b0), .inject_b_to_a_drop_i(1'b0), // 禁用 reverse word 丢失
        .a_rx_valid_o(a_reverse_rx_valid), .a_rx_word_o(a_reverse_rx_word), // 返回 reverse word 到源端点
        .b_rx_valid_o(b_reverse_rx_valid), .b_rx_word_o(b_reverse_rx_word) // 返回 reverse word 到目标端点
    ); // 结束 reverse channel model 实例

    task automatic send_from_a; // 定义源核心 valid-ready 单 flit 发送任务
        input [95:0] header_value; // 接收待发送 header
        input [511:0] payload_value; // 接收待发送 payload
        begin // 开始保持输入直到端点接受
            @(negedge core_a_clk); // 在非采样沿驱动稳定输入
            a_tx_header = header_value; // 驱动源核心 header
            a_tx_header[94:88] = 7'd64; // 将有效字节数镜像进上游完整 flit header
            a_tx_payload = payload_value; // 驱动源核心 payload
            a_tx_bytes = 7'd64; // 两个测试 packet 均使用完整 payload
            a_tx_valid = 1'b1; // 声明源核心输入有效
            @(posedge core_a_clk); // 等待至少一个核心采样沿
            while (!a_tx_ready) @(posedge core_a_clk); // 在端点反压时保持输入稳定
            @(negedge core_a_clk); // 在握手后的非采样沿撤销输入
            a_tx_valid = 1'b0; // 撤销源核心输入有效
            a_tx_header = 96'd0; // 清零已发送 header
            a_tx_payload = 512'd0; // 清零已发送 payload
        end // 结束单 flit 发送任务
    endtask // 结束 send_from_a 任务

    task automatic send_from_b; // 定义目标核心经反向 forward 物理方向发送单 flit 任务
        input [95:0] header_value; // 接收待发送全局提交 header
        input [511:0] payload_value; // 接收待发送全局提交 payload
        begin // 开始保持目标端输入直到可靠端点接受
            @(negedge core_b_clk); // 在目标核心非采样沿驱动稳定输入
            b_tx_header = header_value; // 驱动目标端全局提交 header
            b_tx_header[94:88] = 7'd64; // 将完整 payload 长度写入 header
            b_tx_payload = payload_value; // 驱动编码后的全局提交 payload
            b_tx_bytes = 7'd64; // 声明完整六十四字节 payload
            b_tx_valid = 1'b1; // 声明目标端核心发送有效
            @(posedge core_b_clk); // 等待至少一个目标核心采样沿
            while (!b_tx_ready) @(posedge core_b_clk); // 在端点反压时保持输入稳定
            @(negedge core_b_clk); // 在握手后的非采样沿撤销输入
            b_tx_valid = 1'b0; // 撤销目标端核心发送有效
            b_tx_header = 96'd0; // 清零已发送 header
            b_tx_payload = 512'd0; // 清零已发送 payload
        end // 结束目标端单 flit 发送任务
    endtask // 结束 send_from_b 任务

    always @(posedge core_a_clk or negedge rst_n) begin // 证明生产屏障在 ACK 前阻挡已提出的数据请求
        if (!rst_n) begin // 复位清零 ACK 屏障 scoreboard
            context_ack_seen <= 0; // 清零 Route Context ACK 计数
            blocked_data_cycles <= 0; // 清零 ACK 前阻挡周期计数
            pair_complete_seen <= 0; // 清零上下文数据对完成计数
            global_commit_seen <= 0; // 清零反向全局提交计数
        end else begin // 在源核心域观察生产控制器握手
            if (a_ack_valid && (a_ack_sequence == CONTEXT_SEQUENCE)) context_ack_seen <= context_ack_seen + 1; // 统计同步后的上下文 ACK
            if (data_attempt_active && a_tx_valid && pair_waiting_ack && !a_tx_ready) blocked_data_cycles <= blocked_data_cycles + 1; // 统计真实上游数据被屏障反压的周期
            if (data_attempt_active && pair_tx_valid && (pair_tx_header[81:70] == DATA_SEQUENCE) && (context_ack_seen == 0)) $fatal(1, "production barrier released data before Route Context ACK"); // 禁止 ACK 前数据进入可靠端点
            if (pair_complete) pair_complete_seen <= pair_complete_seen + 1; // 统计生产控制器完成事件
            if (a_commit_valid && (a_commit_header[7:4] == `KDL_MESSAGE_TYPE_GLOBAL_COMMIT)) begin // 捕获经过反向 PCS 和 SerDes 的消息九提交
                if (!a_commit_header[17] || !a_commit_header[18] || !a_commit_last || (a_commit_bytes != 7'd64) || !decoded_global_valid) $fatal(1, "transported global commit boundary or payload was invalid"); // 检查消息九单 flit 边界和 payload 合同
                if (decoded_global_source_domain != 8'd1 || decoded_global_destination_domain != 8'd0 || decoded_global_source_node != 5'd29 || decoded_global_destination_node != 5'd3 || decoded_global_epoch != 8'd7 || decoded_global_transaction_id != 64'h0123_4567_89ab_cdef || decoded_global_status != `KDL_GLOBAL_STATUS_COMMITTED) $fatal(1, "transported global commit identity mismatch"); // 检查完整反向全局身份
                global_commit_seen <= global_commit_seen + 1; // 统计唯一全局提交 packet
            end // 结束反向全局提交捕获
        end // 结束生产屏障 scoreboard 更新
    end // 结束生产屏障 scoreboard

    always @(posedge phy_clk or negedge rst_n) begin // 统计故障注入和 replay 物理发送事件
        if (!rst_n) begin // 复位清零故障和 replay 统计
            context_fault_armed <= 1'b1; // 允许 Route Context 首发故障
            data_fault_armed <= 1'b1; // 允许 data 首发故障
            context_fault_seen <= 0; // 清零 Route Context 故障计数
            data_fault_seen <= 0; // 清零 data 故障计数
            context_replay_seen <= 0; // 清零 Route Context replay 计数
            data_replay_seen <= 0; // 清零 data replay 计数
        end else begin // 在正常运行周期捕获物理事件
            if (context_fault_now) begin // 首次 Route Context 故障实际进入 PCS
                context_fault_armed <= 1'b0; // 禁止重复损坏 Route Context replay
                context_fault_seen <= context_fault_seen + 1; // 记录一次 Route Context 故障
            end // 结束 Route Context 故障捕获
            if (data_fault_now) begin // 首次 data 故障实际进入 PCS
                data_fault_armed <= 1'b0; // 禁止重复损坏 data replay
                data_fault_seen <= data_fault_seen + 1; // 记录一次 data 故障
            end // 结束 data 故障捕获
            if (a_forward_valid && a_forward_flit[531] && (a_forward_flit[593:582] == CONTEXT_SEQUENCE)) context_replay_seen <= context_replay_seen + 1; // 统计 VC6 Route Context replay
            if (a_forward_valid && a_forward_flit[531] && (a_forward_flit[593:582] == DATA_SEQUENCE)) data_replay_seen <= data_replay_seen + 1; // 统计 VC6 data replay
            if (a_deskew_overflow || b_deskew_overflow) $fatal(1, "PCS deskew overflow during Route Context reliability test"); // 禁止 PCS deskew overflow
        end // 结束物理事件统计
    end // 结束物理事件统计逻辑

    always @(posedge core_b_clk or negedge rst_n) begin // 统计 adapter 最终本地数据交付
        if (!rst_n) begin // 复位清零本地交付 scoreboard
            local_commit_seen <= 0; // 清零本地数据输出计数
            local_marker <= 32'd0; // 清零最近本地 payload 标记
            local_retry_seen <= 1'b0; // 清零本地 replay 观察位
        end else if (b_local_valid) begin // 持续 ready 条件下捕获本地输出握手
            local_commit_seen <= local_commit_seen + 1; // 统计只应出现一次的数据交付
            local_marker <= b_local_flit[31:0]; // 保存数据 payload 标记
            local_retry_seen <= b_local_flit[531] && (b_local_flit[527:525] == `KDL_VC_ROLE_REPLAY); // 确认物理 replay VC 与 retry 标志同时存在
        end // 结束本地输出捕获
    end // 结束本地交付 scoreboard

    initial begin // 执行 Route Context 与 data 两阶段 NACK replay 自校验
        phy_clk = 1'b0; // 初始化物理时钟为低
        core_a_clk = 1'b0; // 初始化源核心时钟为低
        core_b_clk = 1'b0; // 初始化目标核心时钟为低
        rst_n = 1'b0; // 初始化全部 DUT 处于复位
        admin_up = 1'b0; // 初始化数字 SerDes 管理关闭
        training = 1'b0; // 初始化 PCS training 关闭
        marker = 1'b0; // 初始化 PCS marker 关闭
        marker_sequence = 16'h31a5; // 初始化确定性 marker 序号
        a_tx_valid = 1'b0; // 初始化源核心发送无效
        a_tx_header = 96'd0; // 初始化源核心 header
        a_tx_payload = 512'd0; // 初始化源核心 payload
        a_tx_bytes = 7'd64; // 初始化完整 payload 字节数
        b_tx_valid = 1'b0; // 初始化目标端反向全局提交发送无效
        b_tx_header = 96'd0; // 初始化目标端反向全局提交 header
        b_tx_payload = 512'd0; // 初始化目标端反向全局提交 payload
        b_tx_bytes = 7'd64; // 初始化目标端反向全局提交完整 payload 长度
        source_issue_valid = 1'b0; // 初始化源全局事务请求无效
        data_attempt_active = 1'b0; // 初始化尚未尝试发送后继数据
        repeat (12) @(posedge phy_clk); // 保持复位覆盖物理和核心时钟
        @(negedge phy_clk); // 在非采样沿释放物理控制
        rst_n = 1'b1; // 释放全部低有效复位
        admin_up = 1'b1; // 启用数字 SerDes link model
        wait (full_duplex_up); // 等待 SerDes 双向训练完成
        repeat (20) begin // 发送足够 PCS training blocks
            @(negedge phy_clk); // 在非采样沿更新 training
            training = 1'b1; // 驱动 PCS training block
        end // 结束 PCS training block 序列
        @(negedge phy_clk); // 在非采样沿结束 training
        training = 1'b0; // 切换 PCS 到 alignment marker
        repeat (4) begin // 发送足够 alignment markers
            @(negedge phy_clk); // 在非采样沿更新 marker
            marker = 1'b1; // 驱动 PCS alignment marker
        end // 结束 alignment marker 序列
        @(negedge phy_clk); // 在非采样沿结束 marker
        marker = 1'b0; // 切换 PCS 到数据状态
        wait (a_block_lock && a_deskew_lock && b_block_lock && b_deskew_lock); // 等待两端 PCS block lock 和 deskew lock
        @(negedge core_a_clk); // 在源核心非采样沿提出全局事务保留请求
        source_issue_valid = 1'b1; // 声明与随后 Route Context 相同的全局事务有效
        #0.1; // 等待源事务表组合许可稳定
        if (!source_issue_ready) $fatal(1, "global source did not retain the routed transaction"); // 要求源端在实际发送前保留事务
        @(negedge core_a_clk); // 保持请求跨过一个源核心采样沿
        source_issue_valid = 1'b0; // 撤销已接受的源全局事务请求

        a_tx_header = 96'd0; // 清零后构造 Route Context header
        a_tx_header[3:0] = `KDL_ROUTE_SCHEMA; // 写入层次路由 schema 三
        a_tx_header[7:4] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT; // 写入 Route Context 消息类型八
        a_tx_header[15:13] = `KDL_VC_ROLE_POINT_TO_POINT; // 首发使用后继 data 的逻辑 VC4
        a_tx_header[17] = 1'b1; // 标记 Route Context 单 flit SOP
        a_tx_header[18] = 1'b1; // 标记 Route Context 单 flit EOP
        a_tx_header[24:20] = 5'd3; // 写入源域内节点三
        a_tx_header[29:25] = 5'd29; // 写入目标域内节点二十九
        a_tx_header[32:30] = 3'd2; // 写入逻辑 plane 二
        a_tx_header[37:33] = 5'd2; // 提供端点接收后仍非零的 hop limit
        a_tx_header[45:38] = 8'h2a; // 写入当前可靠链路 epoch
        a_tx_header[81:70] = CONTEXT_SEQUENCE; // 写入 Route Context packet 序号
        a_tx_header[87:82] = 6'd0; // 写入单 flit packet 内序号零
        a_tx_payload = 512'd0; // 清零后构造 Route Context payload
        a_tx_payload[7:0] = 8'd0; // 写入源 domain 零
        a_tx_payload[15:8] = 8'd1; // 写入目标 domain 一
        a_tx_payload[20:16] = 5'd3; // 镜像源域内节点
        a_tx_payload[25:21] = 5'd29; // 镜像目标域内节点
        a_tx_payload[33:26] = 8'd7; // 写入 topology epoch 七
        a_tx_payload[41:34] = 8'd1; // 写入双域直连 hop limit 一
        a_tx_payload[44:42] = 3'd2; // 镜像逻辑 plane 二
        a_tx_payload[46:45] = 2'b11; // 允许两个 bonded slice
        a_tx_payload[49:47] = 3'd0; // 选择 deterministic route policy
        a_tx_payload[54:50] = 5'd1; // 声明后继 packet 为一个 flit
        a_tx_payload[66:55] = DATA_SEQUENCE; // 绑定后继 data packet 序号
        a_tx_payload[130:67] = 64'h0123_4567_89ab_cdef; // 写入全局事务标识
        a_tx_payload[162:131] = 32'h1020_3040; // 写入通信组标识
        a_tx_payload[165:163] = `KDL_VC_ROLE_POINT_TO_POINT; // 保存不受 replay VC 改写的逻辑 VC4
        send_from_a(a_tx_header, a_tx_payload); // 发送并故障重放 Route Context

        a_tx_header = 96'd0; // 清零后构造后继 data header
        a_tx_header[3:0] = `KDL_SCHEMA_VERSION; // 写入基线 schema 二
        a_tx_header[7:4] = `KDL_MESSAGE_TYPE_DATA; // 写入 DATA 消息类型
        a_tx_header[10:8] = `KDL_OPCODE_POINT_TO_POINT; // 写入点到点 opcode
        a_tx_header[15:13] = `KDL_VC_ROLE_POINT_TO_POINT; // 首发使用逻辑 VC4
        a_tx_header[17] = 1'b1; // 标记单 flit data SOP
        a_tx_header[18] = 1'b1; // 标记单 flit data EOP
        a_tx_header[24:20] = 5'd3; // 写入源域内节点三
        a_tx_header[29:25] = 5'd29; // 写入目标域内节点二十九
        a_tx_header[32:30] = 3'd2; // 镜像 Route Context 逻辑 plane
        a_tx_header[37:33] = 5'd2; // 提供端点接收后仍非零的 hop limit
        a_tx_header[45:38] = 8'h2a; // 写入当前可靠链路 epoch
        a_tx_header[81:70] = DATA_SEQUENCE; // 写入被 Route Context 绑定的 packet 序号
        a_tx_header[87:82] = 6'd0; // 写入单 flit packet 内序号零
        a_tx_payload = {512{1'b1}}; // 翻转完整数据总线以覆盖生产路径的全部 payload 位
        a_tx_payload[31:0] = 32'hcafe_3201; // 写入最终本地 scoreboard 标记
        data_attempt_active = 1'b1; // 在不等待 replay occupancy 的情况下立即尝试后继数据
        send_from_a(a_tx_header, a_tx_payload); // 由生产屏障等待上下文 ACK 后发送并故障重放 data
        data_attempt_active = 1'b0; // 标记后继数据已穿过生产屏障
        timeout_count = 0; // 清零最终交付等待计数
        while (((local_commit_seen == 0) || (a_replay_occupancy != 0)) && (timeout_count < 12000)) begin // 等待 data replay 唯一提交并收到 ACK
            @(posedge phy_clk); // 推进物理可靠链路
            timeout_count = timeout_count + 1; // 推进有界等待计数
        end // 结束最终交付等待
        b_tx_header = 96'd0; // 清零后构造反向全局提交 header
        b_tx_header[3:0] = `KDL_SCHEMA_VERSION; // 全局提交沿用基线 schema 二
        b_tx_header[7:4] = `KDL_MESSAGE_TYPE_GLOBAL_COMMIT; // 写入冻结消息类型九
        b_tx_header[15:13] = `KDL_VC_ROLE_CONTROL; // 首发使用控制 VC5
        b_tx_header[17] = 1'b1; // 标记全局提交单 flit SOP
        b_tx_header[18] = 1'b1; // 标记全局提交单 flit EOP
        b_tx_header[24:20] = 5'd29; // 写入确认发送节点二十九
        b_tx_header[29:25] = 5'd3; // 写入确认接收节点三
        b_tx_header[37:33] = 5'd2; // 提供反向本跳转发跳数
        b_tx_header[45:38] = 8'h2a; // 写入当前可靠链路 epoch
        b_tx_header[81:70] = GLOBAL_COMMIT_SEQUENCE; // 写入全局提交 packet 序号
        b_tx_header[87:82] = 6'd0; // 写入单 flit packet 内序号零
        send_from_b(b_tx_header, encoded_global_commit_payload); // 通过目标端点 PCS 和十 lane SerDes 返回消息九
        timeout_count = 0; // 清零全局提交返回等待计数
        while (((global_commit_seen == 0) || (source_outstanding_count != 0)) && (timeout_count < 12000)) begin // 等待真实消息九释放源事务
            @(posedge phy_clk); // 推进反向 forward 可靠传输和源事务确认流水
            timeout_count = timeout_count + 1; // 推进有界全局完成等待计数
        end // 结束全局提交返回等待
        repeat (20) @(posedge phy_clk); // 留出 duplicate 或迟到错误暴露窗口
        if (context_fault_seen != 1 || data_fault_seen != 1 || context_replay_seen != 1 || data_replay_seen != 1) $fatal(1, "fault/replay counts mismatch fault=%0d/%0d replay=%0d/%0d", context_fault_seen, data_fault_seen, context_replay_seen, data_replay_seen); // 检查两个 packet 均恰好故障并 replay 一次
        if (context_ack_seen != 1 || blocked_data_cycles == 0 || pair_complete_seen != 1) $fatal(1, "production ACK barrier evidence mismatch ack=%0d blocked_cycles=%0d complete=%0d", context_ack_seen, blocked_data_cycles, pair_complete_seen); // 要求真实 ACK 释放且数据曾被阻挡
        if (local_commit_seen != 1 || local_marker != 32'hcafe_3201 || !local_retry_seen) $fatal(1, "adapter delivery mismatch count=%0d marker=%h retry=%b", local_commit_seen, local_marker, local_retry_seen); // 检查 data replay 以 VC6 唯一交付本域
        if (global_commit_seen != 1 || source_outstanding_count != 0 || source_completion_transaction_id != 64'h0123_4567_89ab_cdef || source_protocol_error || source_retry_exhausted) $fatal(1, "global commit transport did not release the retained source transaction seen=%0d outstanding=%0d completion=%h error=%b exhausted=%b", global_commit_seen, source_outstanding_count, source_completion_transaction_id, source_protocol_error, source_retry_exhausted); // 检查消息九经联合物理路径完成源事务
        if (b_remote_valid || adapter_protocol_error || pair_protocol_error || a_retry_exhausted || b_retry_exhausted || a_credit_error || b_credit_error || a_reverse_error || b_reverse_error || a_protocol_error || b_protocol_error || a_cdc_error || b_cdc_error || a_block_error || b_block_error || a_deskew_overflow || b_deskew_overflow) $fatal(1, "unexpected reliability error adapter=%b pair=%b endpoint=%b%b%b%b%b%b pcs=%b%b%b%b", adapter_protocol_error, pair_protocol_error, a_credit_error, b_credit_error, a_reverse_error, b_reverse_error, a_protocol_error, b_protocol_error, a_block_error, b_block_error, a_deskew_overflow, b_deskew_overflow); // 禁止联合路径出现未预期错误
        $display("TB_KDLINK_ROUTE_CONTEXT_RELIABLE_PASS schema3=1 context_nack_replay=1 data_nack_replay=1 logical_vc_restore=1 production_ack_barrier=1 pcs=1 serdes_lanes=10 exact_once=1"); // 报告可追踪的联合验证证据
        $finish; // 正常结束自校验仿真
    end // 结束主测试序列

    initial begin // 提供全局仿真超时保护
        #100000; // 允许 CRC 流水 replay 和异步 CDC 完成
        $fatal(1, "KDLink Route Context reliability timeout"); // 报告联合路径未收敛
    end // 结束超时保护
endmodule // 结束 tb_kdlink_route_context_reliable
