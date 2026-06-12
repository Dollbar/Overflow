`timescale 1ns/1ps
`default_nettype none
// 单Station production事务组合器；四个稳定本地端口各由唯一tl_port同时拥有RX和TX状态。
// 本模块覆盖core source/data按端口分发、实际owner反馈闭环及native TL反压稳定性。
// native TL之后仍需显式packet-boundary owner提供SOP/EOP，才能接Station scheduled TX的重放、CRC和速率节拍。
module endpoint_station_transaction_composer #( // 闭合core至唯一owner并在包边界生成前公开逐端口native TL接口。
 parameter integer WIDTH=8, // 每端口credit计数宽度。
 parameter integer HEADER_DEPTH=2, // 每端口header队列深度。
 parameter integer BANK_DEPTH=3, // 每端口data bank深度。
 parameter integer RX_DEPTH=40, // 每端口唯一RX FIFO深度。
 parameter integer HEADER_COUNT_WIDTH=(HEADER_DEPTH<2)?1:(HEADER_DEPTH<4)?2:3, // header计数宽度。
 parameter integer DATA_COUNT_WIDTH=(BANK_DEPTH<2)?1:(BANK_DEPTH<4)?2:3, // data计数宽度。
 parameter integer RX_COUNT_WIDTH=(RX_DEPTH<2)?1:(RX_DEPTH<4)?2:(RX_DEPTH<8)?3:(RX_DEPTH<16)?4:(RX_DEPTH<32)?5:(RX_DEPTH<64)?6:7, // RX计数宽度。
 parameter integer ORIGINATOR_CAPACITY=4, // 应用请求Tag槽容量。
 parameter integer COMPLETER_CAPACITY=4,parameter integer RUNTIME_ACTIVE_ENABLE=0,parameter integer MESSAGE_ENABLE=0,parameter integer MESSAGE_TOKEN_WIDTH=16,parameter integer NORMAL_WRITE_ENABLE=0,parameter integer FULL_READ_ENABLE=0,parameter integer ATOMIC_ENABLE=0,parameter integer ATOMIC_TX_CLOSE_ENABLE=0,parameter integer ATOMIC_TOKEN_WIDTH=16,parameter integer ORDINARY_ORDERING_ENABLE=0,parameter integer PACKET_BOUNDARY_ENABLE=0, // 目的端事务槽容量及可选运行时模式。
 parameter [3:0] ACTIVE_PORT_MASK=4'b0101 // 默认2x2只激活稀疏端口零和二。
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire i_remote_request_admission_enable,input wire [3:0] i_active_mask, // Station drain只阻止新远端事务。
 input wire [3:0] i_port_link_reset,input wire [3:0] i_start,input wire [3:0] i_shared, // 四个稳定本地端口链路控制。
 input wire [80*WIDTH-1:0] i_capacities, // 四端口二十类RX容量配置。
 input wire [3:0] i_rx_valid,input wire [2047:0] i_rx_flit,input wire [7:0] i_rx_msg, // 已验证Station DL到TL的逐端口RX输入。
 output wire [3:0] o_rx_ready,output wire [3:0] o_rx_taken, // 唯一owner逐端口RX接纳资格和事件。
 output wire [3:0] o_tx_tl_valid,output wire [2047:0] o_tx_tl_flit,output wire [7:0] o_tx_tl_msg,output wire [3:0] o_tx_tl_packet_sop,o_tx_tl_packet_eop, // 唯一owner逐端口native TL候选。
 input wire [3:0] i_tx_tl_ready, // 后续包边界owner和scheduled TX逐端口返回的真实ready。
 output wire o_retired_valid,output wire o_retired_ready,output wire [511:0] o_retired_flit, // 进入core的锁定退休记录观察。
 output wire [1:0] o_retired_msg,output wire [5:0] o_retired_classes,output wire [79:0] o_retired_releases,output wire [1:0] o_retired_port, // 同一退休winner的完整metadata。
 input wire [9:0] i_local_id, // 本地组件身份。
 input wire i_request_valid,output wire o_request_ready,input wire [1:0] i_request_port, // 应用Read请求与稳定端口归属。
 input wire [10:0] i_request_tag,input wire [56:0] i_request_address,input wire [9:0] i_request_dst, // 应用Read请求字段。
 input wire [5:0] i_request_length,input wire [7:0] i_request_attr, // 应用Read长度和属性。
 input wire i_request_is_write,input wire i_request_full,input wire [1:0] i_request_asi,input wire [7:0] i_request_metadata,input wire [2047:0] i_request_data,input wire [255:0] i_request_be,
 input wire[3:0] i_order_profile_valid,input wire[7:0] i_order_mode,input wire[31:0] i_order_epoch,input wire[3:0] i_order_affinity_valid,input wire[7:0] i_order_actual_vc,output wire[3:0] o_order_busy,output wire[3:0] o_order_quiescent,output wire[3:0] o_order_error,
 output wire o_complete_valid,input wire i_complete_ready,output wire [1:0] o_complete_port, // Read完成握手和原端口归属。
 output wire [10:0] o_complete_tag,output wire [3:0] o_complete_status,output wire [511:0] o_complete_data,output wire o_complete_data_valid, // Read完成内容。
 output wire o_complete_is_write,output wire [2047:0] o_complete_data_full,output wire [255:0] o_complete_mask,
 output wire o_mem_valid,input wire i_mem_ready,output wire [1:0] o_mem_slot, // 目的端Read后端命令握手。
 output wire [56:0] o_mem_address,output wire [5:0] o_mem_length,output wire [7:0] o_mem_attr, // Read后端命令字段。
 output wire [1:0] o_mem_asi,output wire [7:0] o_mem_metadata, // Read后端ASI和metadata。
 input wire i_mem_result_valid,output wire o_mem_result_ready,input wire [1:0] i_mem_result_slot, // Read后端结果握手。
 input wire [511:0] i_mem_result_data,input wire [3:0] i_mem_result_status, // Read后端结果内容。
 input wire [2047:0] i_mem_result_data_full,output wire [255:0] o_mem_be,
 output wire o_write_mem_valid,input wire i_write_mem_ready,output wire [1:0] o_write_mem_slot,output wire [56:0] o_write_mem_address,output wire [5:0] o_write_mem_length,output wire [7:0] o_write_mem_attr,output wire [1:0] o_write_mem_asi,output wire [7:0] o_write_mem_metadata,output wire [2047:0] o_write_mem_data,output wire [255:0] o_write_mem_be,
 input wire i_write_mem_result_valid,output wire o_write_mem_result_ready,input wire [1:0] i_write_mem_result_slot,input wire [3:0] i_write_mem_result_status,output wire [7:0] o_write_completer_count,
 input wire[31:0] i_atomic_profile_valid,input wire[31:0] i_atomic_two_operand,input wire i_atomic_order_profile_valid,input wire[1:0] i_atomic_order_mode,input wire[7:0] i_atomic_order_epoch,output wire[3:0] o_atomic_backend_valid,input wire[3:0] i_atomic_backend_ready,output wire[4*ATOMIC_TOKEN_WIDTH-1:0] o_atomic_backend_token,output wire[511:0] o_atomic_backend_header,output wire[7:0] o_atomic_backend_port,output wire[2047:0] o_atomic_backend_operands,output wire[1023:0] o_atomic_backend_byte_enable,output wire[3:0] o_atomic_backend_atomic_return,output wire[19:0] o_atomic_backend_op_type,output wire[7:0] o_atomic_backend_op_size,input wire[3:0] i_atomic_backend_result_valid,output wire[3:0] o_atomic_backend_result_ready,input wire[4*ATOMIC_TOKEN_WIDTH-1:0] i_atomic_backend_result_token,input wire[15:0] i_atomic_backend_result_status,input wire[2047:0] i_atomic_backend_result_data,output wire[3:0] o_atomic_response_valid,input wire[3:0] i_atomic_response_ready,output wire[4*ATOMIC_TOKEN_WIDTH-1:0] o_atomic_response_token,output wire[3:0] o_atomic_response_atomic_return,output wire[7:0] o_atomic_response_port,output wire[43:0] o_atomic_response_tag,output wire[39:0] o_atomic_response_src,output wire[39:0] o_atomic_response_dst,output wire[15:0] o_atomic_response_status,output wire[2047:0] o_atomic_response_data,output wire[3:0] o_atomic_response_data_valid,
 output wire o_message_backend_valid,input wire i_message_backend_ready,output wire[MESSAGE_TOKEN_WIDTH-1:0] o_message_backend_token,output wire[127:0] o_message_backend_header,output wire[1:0] o_message_backend_port,output wire[2047:0] o_message_backend_data,output wire[255:0] o_message_backend_be,
 input wire i_message_result_valid,output wire o_message_result_ready,input wire[MESSAGE_TOKEN_WIDTH-1:0] i_message_result_token,input wire i_message_result_is_read,input wire[1:0] i_message_result_num_beats,input wire[3:0] i_message_result_status,input wire[2047:0] i_message_result_data,input wire[3:0] i_message_result_poison,output wire o_message_busy,output wire[7:0] o_message_reason,
 output wire [1:0] o_source_valid,output wire [511:0] o_source_control,output wire [3:0] o_source_port, // core两类source观察。
 output wire [3:0] o_data_valid,output wire [511:0] o_data0,output wire [511:0] o_data1, // core四类data观察。
 output wire [7:0] o_outstanding_count,output wire [7:0] o_completer_count,output wire o_core_error, // core占用和错误观察。
 output wire [3:0] o_start_ready,output wire [3:0] o_start_taken,output wire [3:0] o_local_done, // 逐端口本地credit初始化状态。
 output wire [3:0] o_peer_done,output wire [3:0] o_peer_shared, // 逐端口对端credit初始化状态。
 output wire [80*(WIDTH+1)-1:0] o_capacity,output wire [80*(WIDTH+1)-1:0] o_available,output wire [80*(WIDTH+1)-1:0] o_pending, // 四个独立credit账本观察。
 output wire [359:0] o_tx_validation_state,output wire [3:0] o_port_idle,output wire [3:0] o_port_error, // 四个唯一owner的TX验证及状态。
 output wire o_dispatch_error,output wire [3:0] o_remote_request_reject_pulse,output wire o_error // drain拒绝为非致命逐端口RAS事件；其余为聚合失败关闭诊断。
);
 wire [7:0] port_header_taken; // 四个唯一owner的两类真实header发送事件，供闭环证据观察。
 wire core_request_header_taken; // 按Request稳定端口归属返回core的真实header事件。

 endpoint_station_transaction_rx_composer #( // 复用并闭合已审核的四owner RX组合器。
  .WIDTH(WIDTH),.HEADER_DEPTH(HEADER_DEPTH),.BANK_DEPTH(BANK_DEPTH),.RX_DEPTH(RX_DEPTH), // 保持所有owner存储配置一致。
  .HEADER_COUNT_WIDTH(HEADER_COUNT_WIDTH),.DATA_COUNT_WIDTH(DATA_COUNT_WIDTH),.RX_COUNT_WIDTH(RX_COUNT_WIDTH), // 保持计数宽度配置一致。
  .ORIGINATOR_CAPACITY(ORIGINATOR_CAPACITY),.COMPLETER_CAPACITY(COMPLETER_CAPACITY),.TX_CLOSE_ENABLE(1),.RUNTIME_ACTIVE_ENABLE(RUNTIME_ACTIVE_ENABLE),.MESSAGE_ENABLE(MESSAGE_ENABLE),.MESSAGE_TOKEN_WIDTH(MESSAGE_TOKEN_WIDTH),.NORMAL_WRITE_ENABLE(NORMAL_WRITE_ENABLE),.FULL_READ_ENABLE(FULL_READ_ENABLE),.ATOMIC_ENABLE(ATOMIC_ENABLE),.ATOMIC_TX_CLOSE_ENABLE(ATOMIC_TX_CLOSE_ENABLE),.ATOMIC_TOKEN_WIDTH(ATOMIC_TOKEN_WIDTH),.ORDINARY_ORDERING_ENABLE(ORDINARY_ORDERING_ENABLE),.PACKET_BOUNDARY_ENABLE(PACKET_BOUNDARY_ENABLE),.ACTIVE_PORT_MASK(ACTIVE_PORT_MASK)) u_composer( // 启用同一组tl_port的TX闭环且不增加账本。
  .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_remote_request_admission_enable(i_remote_request_admission_enable),.i_active_mask(i_active_mask),.i_port_link_reset(i_port_link_reset),.i_start(i_start),.i_shared(i_shared),.i_capacities(i_capacities), // 连接Station和credit控制。
  .i_rx_valid(i_rx_valid),.i_rx_flit(i_rx_flit),.i_rx_msg(i_rx_msg),.o_rx_ready(o_rx_ready),.o_rx_taken(o_rx_taken), // 连接逐端口RX边界。
  .o_port_tx_valid(o_tx_tl_valid),.o_port_tx_flit(o_tx_tl_flit),.o_port_tx_msg(o_tx_tl_msg),.o_port_tx_packet_sop(o_tx_tl_packet_sop),.o_port_tx_packet_eop(o_tx_tl_packet_eop),.i_port_tx_ready(i_tx_tl_ready), // 内部边界与native候选同行并由同一ready确认。
  .o_retired_valid(o_retired_valid),.o_retired_ready(o_retired_ready),.o_retired_flit(o_retired_flit),.o_retired_msg(o_retired_msg), // 公开进入core的退休握手。
  .o_retired_classes(o_retired_classes),.o_retired_releases(o_retired_releases),.o_retired_port(o_retired_port), // 公开同winner完整退休metadata。
  .i_local_id(i_local_id),.i_request_valid(i_request_valid),.o_request_ready(o_request_ready),.i_request_port(i_request_port), // 连接应用请求握手与归属。
  .i_request_tag(i_request_tag),.i_request_address(i_request_address),.i_request_dst(i_request_dst),.i_request_length(i_request_length),.i_request_attr(i_request_attr), // 连接应用请求内容。
  .i_request_is_write(i_request_is_write),.i_request_full(i_request_full),.i_request_asi(i_request_asi),.i_request_metadata(i_request_metadata),.i_request_data(i_request_data),.i_request_be(i_request_be),
  .i_order_profile_valid(i_order_profile_valid),.i_order_mode(i_order_mode),.i_order_epoch(i_order_epoch),.i_order_affinity_valid(i_order_affinity_valid),.i_order_actual_vc(i_order_actual_vc),.o_order_busy(o_order_busy),.o_order_quiescent(o_order_quiescent),.o_order_error(o_order_error),
  .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag), // 连接应用完成握手。
  .o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid), // 连接应用完成内容。
  .o_complete_is_write(o_complete_is_write),.o_complete_data_full(o_complete_data_full),.o_complete_mask(o_complete_mask),
  .o_mem_valid(o_mem_valid),.i_mem_ready(i_mem_ready),.o_mem_slot(o_mem_slot),.o_mem_address(o_mem_address),.o_mem_length(o_mem_length), // 连接Read后端命令。
  .o_mem_attr(o_mem_attr),.o_mem_asi(o_mem_asi),.o_mem_metadata(o_mem_metadata), // 连接Read后端命令属性。
  .i_mem_result_valid(i_mem_result_valid),.o_mem_result_ready(o_mem_result_ready),.i_mem_result_slot(i_mem_result_slot), // 连接Read后端结果握手。
  .i_mem_result_data(i_mem_result_data),.i_mem_result_status(i_mem_result_status), // 连接Read后端结果内容。
  .i_mem_result_data_full(i_mem_result_data_full),.o_mem_be(o_mem_be),.o_write_mem_valid(o_write_mem_valid),.i_write_mem_ready(i_write_mem_ready),.o_write_mem_slot(o_write_mem_slot),.o_write_mem_address(o_write_mem_address),.o_write_mem_length(o_write_mem_length),.o_write_mem_attr(o_write_mem_attr),.o_write_mem_asi(o_write_mem_asi),.o_write_mem_metadata(o_write_mem_metadata),.o_write_mem_data(o_write_mem_data),.o_write_mem_be(o_write_mem_be),.i_write_mem_result_valid(i_write_mem_result_valid),.o_write_mem_result_ready(o_write_mem_result_ready),.i_write_mem_result_slot(i_write_mem_result_slot),.i_write_mem_result_status(i_write_mem_result_status),.o_write_completer_count(o_write_completer_count),
  .i_atomic_profile_valid(i_atomic_profile_valid),.i_atomic_two_operand(i_atomic_two_operand),.i_atomic_order_profile_valid(i_atomic_order_profile_valid),.i_atomic_order_mode(i_atomic_order_mode),.i_atomic_order_epoch(i_atomic_order_epoch),.o_atomic_backend_valid(o_atomic_backend_valid),.i_atomic_backend_ready(i_atomic_backend_ready),.o_atomic_backend_token(o_atomic_backend_token),.o_atomic_backend_header(o_atomic_backend_header),.o_atomic_backend_port(o_atomic_backend_port),.o_atomic_backend_operands(o_atomic_backend_operands),.o_atomic_backend_byte_enable(o_atomic_backend_byte_enable),.o_atomic_backend_atomic_return(o_atomic_backend_atomic_return),.o_atomic_backend_op_type(o_atomic_backend_op_type),.o_atomic_backend_op_size(o_atomic_backend_op_size),.i_atomic_backend_result_valid(i_atomic_backend_result_valid),.o_atomic_backend_result_ready(o_atomic_backend_result_ready),.i_atomic_backend_result_token(i_atomic_backend_result_token),.i_atomic_backend_result_status(i_atomic_backend_result_status),.i_atomic_backend_result_data(i_atomic_backend_result_data),.o_atomic_response_valid(o_atomic_response_valid),.i_atomic_response_ready(i_atomic_response_ready),.o_atomic_response_token(o_atomic_response_token),.o_atomic_response_atomic_return(o_atomic_response_atomic_return),.o_atomic_response_port(o_atomic_response_port),.o_atomic_response_tag(o_atomic_response_tag),.o_atomic_response_src(o_atomic_response_src),.o_atomic_response_dst(o_atomic_response_dst),.o_atomic_response_status(o_atomic_response_status),.o_atomic_response_data(o_atomic_response_data),.o_atomic_response_data_valid(o_atomic_response_data_valid),
  .o_message_backend_valid(o_message_backend_valid),.i_message_backend_ready(i_message_backend_ready),.o_message_backend_token(o_message_backend_token),.o_message_backend_header(o_message_backend_header),.o_message_backend_port(o_message_backend_port),.o_message_backend_data(o_message_backend_data),.o_message_backend_be(o_message_backend_be),
  .i_message_result_valid(i_message_result_valid),.o_message_result_ready(o_message_result_ready),.i_message_result_token(i_message_result_token),.i_message_result_is_read(i_message_result_is_read),.i_message_result_num_beats(i_message_result_num_beats),.i_message_result_status(i_message_result_status),.i_message_result_data(i_message_result_data),.i_message_result_poison(i_message_result_poison),.o_message_busy(o_message_busy),.o_message_reason(o_message_reason),
  .o_source_valid(o_source_valid),.o_source_control(o_source_control),.o_source_port(o_source_port),.i_source_captured(2'd0),.i_request_header_taken(1'b0), // 闭合模式忽略外部反馈并保留core观察输出。
  .o_data_valid(o_data_valid),.o_data0(o_data0),.o_data1(o_data1),.i_data_accepted(4'd0), // 闭合模式由同一组tl_port返回真实data接纳。
  .o_outstanding_count(o_outstanding_count),.o_completer_count(o_completer_count),.o_core_error(o_core_error), // 公开core状态。
  .o_start_ready(o_start_ready),.o_start_taken(o_start_taken),.o_local_done(o_local_done),.o_peer_done(o_peer_done),.o_peer_shared(o_peer_shared), // 公开逐端口初始化状态。
  .o_capacity(o_capacity),.o_available(o_available),.o_pending(o_pending),.o_tx_validation_state(o_tx_validation_state), // 公开四套唯一账本与验证状态。
  .o_port_idle(o_port_idle),.o_port_error(o_port_error),.o_dispatch_error(o_dispatch_error), // 公开逐端口和路由错误。
  .o_port_header_taken(port_header_taken),.o_tx_request_header_taken(core_request_header_taken),.o_remote_request_reject_pulse(o_remote_request_reject_pulse),.o_error(o_error)); // 保留真实反馈、拒绝观察并聚合失败关闭。
endmodule // 结束单Station production事务组合器。
`default_nettype wire
