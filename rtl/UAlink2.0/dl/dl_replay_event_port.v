module dl_replay_event_port #( // dl_replay_event_port模块：LLR接收事件和发送头的同域连接
    parameter integer C_EARLY_TX_METADATA = 0 // 非零时采用由集成层明确证明的提前发送源元数据资格
) ( // dl_replay_event_port模块：实际LLR接收事件与发送头连接
    input wire i_clk, // 同域接收或发送输入
    input wire i_rstn, // 同域接收或发送输入
    input wire i_link_reset, // 同域接收或发送输入
    input wire i_rx_event_valid, // 同域接收或发送输入
    input wire i_rx_event_discard, // 同域接收或发送输入
    input wire i_rx_crc_ok, // 同域接收或发送输入
    input wire [23:0] i_rx_header, // 同域接收或发送输入
    input wire [7:0] i_rx_replay_limit, // 同域接收或发送输入
    input wire i_tx_flit_send, // 同域接收或发送输入
    input wire i_tx_payload, // 同域接收或发送输入
    input wire i_tx_replay, // 同域接收或发送输入
    input wire i_tx_first_replay, // 同域接收或发送输入
    input wire [8:0] i_tx_sequence, // 同域接收或发送输入
    input wire i_tx_metadata_ok, // 仅提前模式使用，默认模式仍执行完整原始元数据保护
    input wire i_tx_new_group, // 同域接收或发送输入
    output wire o_rx_ingress_event, // 完整状态或本拍原生事件观察
    output wire o_rx_accept, // 完整状态或本拍原生事件观察
    output wire o_rx_payload_accept, // 完整状态或本拍原生事件观察
    output wire o_rx_sequence_valid, // 完整状态或本拍原生事件观察
    output wire [8:0] o_rx_sequence, // 完整状态或本拍原生事件观察
    output wire o_rx_replay_request, // 完整状态或本拍原生事件观察
    output wire o_rx_command_valid, // 完整状态或本拍原生事件观察
    output wire o_rx_command_request, // 完整状态或本拍原生事件观察
    output wire [8:0] o_rx_command_target, // 完整状态或本拍原生事件观察
    output wire o_rx_crc_error, // 完整状态或本拍原生事件观察
    output wire o_rx_zero_sequence, // 完整状态或本拍原生事件观察
    output wire o_rx_zero_command, // 完整状态或本拍原生事件观察
    output wire o_rx_backpressure_drop, // 完整状态或本拍原生事件观察
    output wire o_rx_unexpected, // 完整状态或本拍原生事件观察
    output wire o_rx_ambiguous_drop, // 完整状态或本拍原生事件观察
    output wire o_rx_replay_drop, // 完整状态或本拍原生事件观察
    output wire [8:0] o_rx_last_sequence, // 完整状态或本拍原生事件观察
    output wire [2:0] o_rx_bad_crc_count, // 完整状态或本拍原生事件观察
    output wire [7:0] o_rx_unexpected_count, // 完整状态或本拍原生事件观察
    output wire o_rx_ambiguous, // 完整状态或本拍原生事件观察
    output wire o_rx_replay, // 完整状态或本拍原生事件观察
    output wire [23:0] o_tx_header, // 完整状态或本拍原生事件观察
    output wire o_tx_header_valid, // 完整状态或本拍原生事件观察
    output wire o_tx_metadata_error, // 完整状态或本拍原生事件观察
    output wire [2:0] o_tx_explicit_count, // 完整状态或本拍原生事件观察
    output wire [1:0] o_tx_request_count, // 完整状态或本拍原生事件观察
    output wire [8:0] o_tx_request_sequence, // 完整状态或本拍原生事件观察
    output wire o_tx_group_used, // 完整状态或本拍原生事件观察
    output wire [8:0] o_rx_effective_sequence // 完整状态或本拍原生事件观察
); // 结束端口声明
assign o_rx_effective_sequence = o_rx_accept ? o_rx_sequence : o_rx_last_sequence; // 只有本拍接纳才旁路新序号，未接纳保持当前状态
dl_replay_receiver u_receiver ( // 实例化u_receiver，共享唯一时钟和复位
    .i_clk(i_clk), // 原生接口直接连接
    .i_rstn(i_rstn), // 原生接口直接连接
    .i_link_reset(i_link_reset), // 原生接口直接连接
    .i_event_valid(i_rx_event_valid), // 原生接口直接连接
    .i_event_discard(i_rx_event_discard), // 原生接口直接连接
    .i_crc_ok(i_rx_crc_ok), // 原生接口直接连接
    .i_header(i_rx_header), // 原生接口直接连接
    .i_replay_limit(i_rx_replay_limit), // 原生接口直接连接
    .o_ingress_event(o_rx_ingress_event), // 原生接口直接连接
    .o_accept(o_rx_accept), // 原生接口直接连接
    .o_payload_accept(o_rx_payload_accept), // 原生接口直接连接
    .o_sequence_valid(o_rx_sequence_valid), // 原生接口直接连接
    .o_sequence(o_rx_sequence), // 原生接口直接连接
    .o_replay_request(o_rx_replay_request), // 原生接口直接连接
    .o_command_valid(o_rx_command_valid), // 原生接口直接连接
    .o_command_request(o_rx_command_request), // 原生接口直接连接
    .o_command_target(o_rx_command_target), // 原生接口直接连接
    .o_crc_error(o_rx_crc_error), // 原生接口直接连接
    .o_zero_sequence(o_rx_zero_sequence), // 原生接口直接连接
    .o_zero_command(o_rx_zero_command), // 原生接口直接连接
    .o_backpressure_drop(o_rx_backpressure_drop), // 原生接口直接连接
    .o_unexpected(o_rx_unexpected), // 原生接口直接连接
    .o_ambiguous_drop(o_rx_ambiguous_drop), // 原生接口直接连接
    .o_replay_drop(o_rx_replay_drop), // 原生接口直接连接
    .o_last_sequence(o_rx_last_sequence), // 原生接口直接连接
    .o_bad_crc_count(o_rx_bad_crc_count), // 原生接口直接连接
    .o_unexpected_count(o_rx_unexpected_count), // 原生接口直接连接
    .o_ambiguous(o_rx_ambiguous), // 原生接口直接连接
    .o_replay(o_rx_replay) // 原生接口直接连接
); // 结束u_receiver实例端口连接
dl_replay_header_tx #(.C_EARLY_TX_METADATA(C_EARLY_TX_METADATA)) u_header_tx ( // 实例化u_header_tx，共享唯一时钟和复位
    .i_clk(i_clk), // 原生接口直接连接
    .i_rstn(i_rstn), // 原生接口直接连接
    .i_link_reset(i_link_reset), // 原生接口直接连接
    .i_flit_send(i_tx_flit_send), // 原生接口直接连接
    .i_payload(i_tx_payload), // 原生接口直接连接
    .i_replay(i_tx_replay), // 原生接口直接连接
    .i_first_replay(i_tx_first_replay), // 原生接口直接连接
    .i_tx_sequence(i_tx_sequence), // 原生接口直接连接
    .i_tx_metadata_ok(i_tx_metadata_ok), // 显式传递可选提前资格，接收序号仍由原接收器检查
    .i_rx_sequence(o_rx_effective_sequence), // 原生接口直接连接
    .i_rx_request(o_rx_replay_request), // 原生接口直接连接
    .i_new_group(i_tx_new_group), // 原生接口直接连接
    .o_header(o_tx_header), // 原生接口直接连接
    .o_header_valid(o_tx_header_valid), // 原生接口直接连接
    .o_metadata_error(o_tx_metadata_error), // 原生接口直接连接
    .o_explicit_count(o_tx_explicit_count), // 原生接口直接连接
    .o_request_count(o_tx_request_count), // 原生接口直接连接
    .o_request_sequence(o_tx_request_sequence), // 原生接口直接连接
    .o_group_used(o_tx_group_used) // 原生接口直接连接
); // 结束u_header_tx实例端口连接
endmodule // 结束dl_replay_event_port模块
