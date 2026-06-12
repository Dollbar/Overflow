`timescale 1ns/1ps
`default_nettype none
// 单Station 2x2 production数字边界：transaction core经唯一tl_port、pacing、slot calendar进入独立DL replay context。
// 每个native TL输出是完整512-bit word；显式模式由上游descriptor owner保持SOP/EOP直到take，默认仍每word独立成包。
// 输出止于CRC系数输入候选；A19线上CRC octet位序未决，所有physical_valid必须保持零。
module endpoint_station_transaction_dl_composer #(
 parameter integer WIDTH=8,parameter integer HEADER_DEPTH=2,parameter integer BANK_DEPTH=3,parameter integer RX_DEPTH=40, // 唯一tl_port存储配置。
 parameter integer HEADER_COUNT_WIDTH=(HEADER_DEPTH<2)?1:(HEADER_DEPTH<4)?2:3,parameter integer DATA_COUNT_WIDTH=(BANK_DEPTH<2)?1:(BANK_DEPTH<4)?2:3, // TX计数宽度。
 parameter integer RX_COUNT_WIDTH=(RX_DEPTH<2)?1:(RX_DEPTH<4)?2:(RX_DEPTH<8)?3:(RX_DEPTH<16)?4:(RX_DEPTH<32)?5:(RX_DEPTH<64)?6:7, // RX计数宽度。
 parameter integer ORIGINATOR_CAPACITY=4,parameter integer COMPLETER_CAPACITY=4,parameter integer MESSAGE_ENABLE=0,parameter integer MESSAGE_TOKEN_WIDTH=16,parameter integer NORMAL_WRITE_ENABLE=0,parameter integer FULL_READ_ENABLE=0,parameter integer ATOMIC_ENABLE=0,parameter integer ATOMIC_TX_CLOSE_ENABLE=0,parameter integer ATOMIC_TOKEN_WIDTH=16,parameter integer ORDINARY_ORDERING_ENABLE=0,parameter integer REPLAY_DEPTH=4,parameter integer DYNAMIC_MODE_ENABLE=0,parameter integer EXPLICIT_PACKET_BOUNDARY_ENABLE=0,parameter integer INTERNAL_PACKET_BOUNDARY_ENABLE=0, // transaction、DL replay容量及managed模式使能。
 parameter integer REPLAY_ADDR_WIDTH=(REPLAY_DEPTH<=2)?1:(REPLAY_DEPTH<=4)?2:(REPLAY_DEPTH<=8)?3:(REPLAY_DEPTH<=16)?4:(REPLAY_DEPTH<=32)?5:(REPLAY_DEPTH<=64)?6:(REPLAY_DEPTH<=128)?7:8, // replay地址宽度。
 parameter [3:0] ACTIVE_PORT_MASK=4'b0101 // 本顶层冻结2x2稀疏端口零和二。
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire i_remote_request_admission_enable,input wire i_ras_rx_cleanup,input wire [3:0] i_port_link_reset, // Station公共时钟；drain准入与链路接收分离。
 input wire [3:0] i_start,input wire [3:0] i_shared,input wire [80*WIDTH-1:0] i_capacities,input wire [3:0] i_native_sop,input wire [3:0] i_native_eop,output wire [3:0] o_native_boundary_take, // credit初始化及与native word同握手推进的显式边界descriptor。
 input wire [1:0] i_requested_mode,input wire i_mode_commit,input wire [3:0] i_lane_up,output wire o_mode_commit_accept,output wire o_mode_error, // managed路径使用CSR请求模式；默认兼容2x2。
 output wire [1:0] o_active_mode,output wire [3:0] o_active_mask,output wire [3:0] o_port_slot_enable,output wire [1:0] o_slot_port,output wire o_slot_error, // 实际模式和公共日历观察。
 input wire [3:0] i_rate_valid,output wire [3:0] o_rate_ready,input wire [63:0] i_rate_code, // 四端口独立pacing配置。
 output wire [3:0] o_rate_accept,output wire [3:0] o_rate_error,output wire [3:0] o_rate_configured,output wire [63:0] o_active_rate_code, // pacing状态。
 input wire [3:0] i_tx_budget_available, // 外部逐端口resident预算资格。
 input wire [3:0] i_rx_frame_valid,output wire [3:0] o_rx_frame_ready,input wire [2047:0] i_rx_frame_data, // CRC/FEC验证后的DL frame输入。
 input wire [3:0] i_rx_frame_sop,input wire [3:0] i_rx_frame_eop,input wire [3:0] i_rx_fec_complete,input wire [3:0] i_rx_crc_ok, // 完整frame资格。
 output wire [3:0] o_tx_control_valid,input wire [3:0] i_tx_control_ready,output wire [3:0] o_tx_control_replay_request,output wire [35:0] o_tx_control_target, // 逐端口ACK/Replay控制。
 output wire [3:0] o_crc_input_valid,input wire [3:0] i_crc_input_ready,output wire [2047:0] o_crc_input_data, // A19之前的CRC输入候选。
 output wire [3:0] o_crc_input_sop,output wire [3:0] o_crc_input_eop,output wire [35:0] o_crc_input_sequence,output wire [3:0] o_crc_input_replay, // hop-local序列和重放标志。
 output wire [3:0] o_crc_required,output wire [3:0] o_physical_valid,output wire [31:0] o_tx_resident_count, // A19失败关闭及replay resident状态。
 input wire [9:0] i_local_id,input wire i_request_valid,output wire o_request_ready,input wire [1:0] i_request_port, // 应用Read请求握手与端口归属。
 input wire [10:0] i_request_tag,input wire [56:0] i_request_address,input wire [9:0] i_request_dst,input wire [5:0] i_request_length,input wire [7:0] i_request_attr, // 请求字段。
 input wire i_request_is_write,input wire i_request_full,input wire [1:0] i_request_asi,input wire [7:0] i_request_metadata,input wire [2047:0] i_request_data,input wire [255:0] i_request_be,
 input wire[3:0] i_order_profile_valid,input wire[7:0] i_order_mode,input wire[31:0] i_order_epoch,input wire[3:0] i_order_affinity_valid,input wire[7:0] i_order_actual_vc,output wire[3:0] o_order_busy,output wire[3:0] o_order_quiescent,output wire[3:0] o_order_error,
 output wire o_complete_valid,input wire i_complete_ready,output wire [1:0] o_complete_port,output wire [10:0] o_complete_tag, // 完成握手与身份。
 output wire [3:0] o_complete_status,output wire [511:0] o_complete_data,output wire o_complete_data_valid, // 完成结果。
 output wire o_complete_is_write,output wire [2047:0] o_complete_data_full,output wire [255:0] o_complete_mask,
 output wire o_mem_valid,input wire i_mem_ready,output wire [1:0] o_mem_slot,output wire [56:0] o_mem_address,output wire [5:0] o_mem_length, // Read后端命令。
 output wire [7:0] o_mem_attr,output wire [1:0] o_mem_asi,output wire [7:0] o_mem_metadata, // Read后端属性。
 input wire i_mem_result_valid,output wire o_mem_result_ready,input wire [1:0] i_mem_result_slot,input wire [511:0] i_mem_result_data,input wire [3:0] i_mem_result_status, // Read后端结果。
 input wire [2047:0] i_mem_result_data_full,output wire [255:0] o_mem_be,
 output wire o_write_mem_valid,input wire i_write_mem_ready,output wire [1:0] o_write_mem_slot,output wire [56:0] o_write_mem_address,output wire [5:0] o_write_mem_length,output wire [7:0] o_write_mem_attr,output wire [1:0] o_write_mem_asi,output wire [7:0] o_write_mem_metadata,output wire [2047:0] o_write_mem_data,output wire [255:0] o_write_mem_be,
 input wire i_write_mem_result_valid,output wire o_write_mem_result_ready,input wire [1:0] i_write_mem_result_slot,input wire [3:0] i_write_mem_result_status,output wire [7:0] o_write_completer_count,
 input wire[31:0] i_atomic_profile_valid,input wire[31:0] i_atomic_two_operand,input wire i_atomic_order_profile_valid,input wire[1:0] i_atomic_order_mode,input wire[7:0] i_atomic_order_epoch,output wire[3:0] o_atomic_backend_valid,input wire[3:0] i_atomic_backend_ready,output wire[4*ATOMIC_TOKEN_WIDTH-1:0] o_atomic_backend_token,output wire[511:0] o_atomic_backend_header,output wire[7:0] o_atomic_backend_port,output wire[2047:0] o_atomic_backend_operands,output wire[1023:0] o_atomic_backend_byte_enable,output wire[3:0] o_atomic_backend_atomic_return,output wire[19:0] o_atomic_backend_op_type,output wire[7:0] o_atomic_backend_op_size,input wire[3:0] i_atomic_backend_result_valid,output wire[3:0] o_atomic_backend_result_ready,input wire[4*ATOMIC_TOKEN_WIDTH-1:0] i_atomic_backend_result_token,input wire[15:0] i_atomic_backend_result_status,input wire[2047:0] i_atomic_backend_result_data,output wire[3:0] o_atomic_response_valid,input wire[3:0] i_atomic_response_ready,output wire[4*ATOMIC_TOKEN_WIDTH-1:0] o_atomic_response_token,output wire[3:0] o_atomic_response_atomic_return,output wire[7:0] o_atomic_response_port,output wire[43:0] o_atomic_response_tag,output wire[39:0] o_atomic_response_src,output wire[39:0] o_atomic_response_dst,output wire[15:0] o_atomic_response_status,output wire[2047:0] o_atomic_response_data,output wire[3:0] o_atomic_response_data_valid,
 output wire o_message_backend_valid,input wire i_message_backend_ready,output wire[MESSAGE_TOKEN_WIDTH-1:0] o_message_backend_token,output wire[127:0] o_message_backend_header,output wire[1:0] o_message_backend_port,output wire[2047:0] o_message_backend_data,output wire[255:0] o_message_backend_be,
 input wire i_message_result_valid,output wire o_message_result_ready,input wire[MESSAGE_TOKEN_WIDTH-1:0] i_message_result_token,input wire i_message_result_is_read,input wire[1:0] i_message_result_num_beats,input wire[3:0] i_message_result_status,input wire[2047:0] i_message_result_data,input wire[3:0] i_message_result_poison,output wire o_message_busy,output wire[7:0] o_message_reason,
 output wire [3:0] o_start_ready,output wire [3:0] o_start_taken,output wire [3:0] o_local_done,output wire [3:0] o_peer_done, // 唯一owner初始化状态。
 output wire [3:0] o_port_error,output wire [3:0] o_remote_request_reject_pulse,output wire o_transaction_error,output wire o_scheduled_error,output wire o_busy,output wire o_quiescent,output wire o_error, // 分层、非致命拒绝、静止状态和聚合诊断。
 output wire[2:0] o_ras_owner_ready,output wire[2:0] o_ras_missing_owners // 组合恢复owner资格；不是epoch证书。
);
 wire [3:0] native_valid,native_ready,native_packet_sop,native_packet_eop;wire [2047:0] native_flit;wire [7:0] native_msg; // 唯一tl_port native TL边界。
 wire [3:0] paced_valid,paced_ready,paced_sop,paced_eop,paced_flush,adapter_error; // pacing后完整word边界。
 wire [2047:0] paced_flit;wire [7:0] paced_msg; // scheduled内部观察。
 wire [3:0] rx_tl_valid,rx_tl_ready;wire [2047:0] rx_tl_data;wire [7:0] rx_tl_msg; // DL builder解包到唯一tl_port RX。
 wire [3:0] unused_builder_busy,unused_builder_quiescent,unused_builder_error;wire scheduled_busy,scheduled_quiescent; // builder状态观察。
 wire inactive_boundary_error;wire [7:0] outstanding_count,completer_count;wire [3:0] unused_peer_shared,port_idle;wire [359:0] tx_validation; // 静止状态与恢复owner状态。
 wire [80*(WIDTH+1)-1:0] capacity,available,pending;wire unused_dispatch,unused_core; // 唯一账本观察。
 wire[31:0] tx_unacked;wire[35:0] dl_rx_last;wire[11:0] dl_rx_bad_crc;wire[31:0] dl_rx_unexpected;wire[3:0] dl_rx_ambiguous,dl_rx_replay,dl_rx_quiescent;
 wire [3:0] effective_active_mask;wire [1:0] effective_requested_mode;
 assign effective_active_mask=(DYNAMIC_MODE_ENABLE!=0)?o_active_mask:ACTIVE_PORT_MASK;assign effective_requested_mode=(DYNAMIC_MODE_ENABLE!=0)?i_requested_mode:2'd1;
 assign o_native_boundary_take=native_valid&native_ready; // 每端口descriptor owner只在对应native word真实接纳时推进。
 assign inactive_boundary_error=i_rstn&&i_enable&&((|(i_rate_valid&~effective_active_mask))||(|(i_rx_frame_valid&~effective_active_mask))); // inactive配置或RX frame失败关闭。
 assign o_busy=scheduled_busy||o_message_busy||(|native_valid)||(|paced_valid)||(|outstanding_count)||(|completer_count)||(!(&(port_idle|~effective_active_mask)));
 assign o_quiescent=!o_busy&&scheduled_quiescent;
 assign o_error=o_transaction_error||o_scheduled_error||(|adapter_error)||inactive_boundary_error||(|o_physical_valid); // A19 physical放行也视为边界违规。

 genvar p;generate for(p=0;p<32'd4;p=p+1)begin:gen_packet_boundary // 四路只有pacing skid，不复制tl_port、credit或replay owner。
  endpoint_tl_word_packet_boundary_adapter #(.EXPLICIT_PACKET_BOUNDARY_ENABLE(EXPLICIT_PACKET_BOUNDARY_ENABLE),.INTERNAL_PACKET_BOUNDARY_ENABLE(INTERNAL_PACKET_BOUNDARY_ENABLE))u_adapter(
   .i_clk(i_clk),.i_rstn(i_rstn&&!i_port_link_reset[p]),.i_enable(i_enable),.i_active(effective_active_mask[p]), // 当前已提交模式资格。
   .i_rate_valid(i_rate_valid[p]),.o_rate_ready(o_rate_ready[p]),.i_rate_code(i_rate_code[p*16+:16]),.o_rate_accept(o_rate_accept[p]),.o_rate_error(o_rate_error[p]), // 独立rate配置。
   .o_rate_configured(o_rate_configured[p]),.o_active_rate_code(o_active_rate_code[p*16+:16]),.i_budget_available(i_tx_budget_available[p]), // 外部预算只作资格。
   .i_native_valid(native_valid[p]),.o_native_ready(native_ready[p]),.i_native_flit(native_flit[p*512+:512]),.i_native_msg(native_msg[p*2+:2]),.i_native_sop(i_native_sop[p]),.i_native_eop(i_native_eop[p]),.i_internal_sop(native_packet_sop[p]),.i_internal_eop(native_packet_eop[p]), // 唯一owner输出。
   .o_builder_valid(paced_valid[p]),.i_builder_ready(paced_ready[p]),.o_builder_flit(paced_flit[p*512+:512]),.o_builder_msg(paced_msg[p*2+:2]), // scheduled输入。
   .o_builder_sop(paced_sop[p]),.o_builder_eop(paced_eop[p]),.o_builder_flush(paced_flush[p]),.o_error(adapter_error[p])); // 完整word立即flush。
 end endgenerate

 endpoint_station_transaction_composer #(.WIDTH(WIDTH),.HEADER_DEPTH(HEADER_DEPTH),.BANK_DEPTH(BANK_DEPTH),.RX_DEPTH(RX_DEPTH),.HEADER_COUNT_WIDTH(HEADER_COUNT_WIDTH),.DATA_COUNT_WIDTH(DATA_COUNT_WIDTH),.RX_COUNT_WIDTH(RX_COUNT_WIDTH),.ORIGINATOR_CAPACITY(ORIGINATOR_CAPACITY),.COMPLETER_CAPACITY(COMPLETER_CAPACITY),.RUNTIME_ACTIVE_ENABLE(DYNAMIC_MODE_ENABLE),.MESSAGE_ENABLE(MESSAGE_ENABLE),.MESSAGE_TOKEN_WIDTH(MESSAGE_TOKEN_WIDTH),.NORMAL_WRITE_ENABLE(NORMAL_WRITE_ENABLE),.FULL_READ_ENABLE(FULL_READ_ENABLE),.ATOMIC_ENABLE(ATOMIC_ENABLE),.ATOMIC_TX_CLOSE_ENABLE(ATOMIC_TX_CLOSE_ENABLE),.ATOMIC_TOKEN_WIDTH(ATOMIC_TOKEN_WIDTH),.ORDINARY_ORDERING_ENABLE(ORDINARY_ORDERING_ENABLE),.PACKET_BOUNDARY_ENABLE(INTERNAL_PACKET_BOUNDARY_ENABLE),.ACTIVE_PORT_MASK(ACTIVE_PORT_MASK)) u_transaction(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_remote_request_admission_enable(i_remote_request_admission_enable),.i_active_mask(effective_active_mask),.i_port_link_reset(i_port_link_reset),.i_start(i_start),.i_shared(i_shared),.i_capacities(i_capacities), // 唯一owner配置。
  .i_rx_valid(rx_tl_valid),.i_rx_flit(rx_tl_data),.i_rx_msg(rx_tl_msg),.o_rx_ready(rx_tl_ready),.o_rx_taken(), // scheduled RX直接进入同一tl_port。
  .o_tx_tl_valid(native_valid),.o_tx_tl_flit(native_flit),.o_tx_tl_msg(native_msg),.o_tx_tl_packet_sop(native_packet_sop),.o_tx_tl_packet_eop(native_packet_eop),.i_tx_tl_ready(native_ready), // native TX经pacing返回真实ready。
  .o_retired_valid(),.o_retired_ready(),.o_retired_flit(),.o_retired_msg(),.o_retired_classes(),.o_retired_releases(),.o_retired_port(), // 退休观察留在下层。
  .i_local_id(i_local_id),.i_request_valid(i_request_valid),.o_request_ready(o_request_ready),.i_request_port(i_request_port),.i_request_tag(i_request_tag),.i_request_address(i_request_address),.i_request_dst(i_request_dst),.i_request_length(i_request_length),.i_request_attr(i_request_attr), // 请求接口。
  .i_request_is_write(i_request_is_write),.i_request_full(i_request_full),.i_request_asi(i_request_asi),.i_request_metadata(i_request_metadata),.i_request_data(i_request_data),.i_request_be(i_request_be),
  .i_order_profile_valid(i_order_profile_valid),.i_order_mode(i_order_mode),.i_order_epoch(i_order_epoch),.i_order_affinity_valid(i_order_affinity_valid),.i_order_actual_vc(i_order_actual_vc),.o_order_busy(o_order_busy),.o_order_quiescent(o_order_quiescent),.o_order_error(o_order_error),
  .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag),.o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid), // 完成接口。
  .o_complete_is_write(o_complete_is_write),.o_complete_data_full(o_complete_data_full),.o_complete_mask(o_complete_mask),
  .o_mem_valid(o_mem_valid),.i_mem_ready(i_mem_ready),.o_mem_slot(o_mem_slot),.o_mem_address(o_mem_address),.o_mem_length(o_mem_length),.o_mem_attr(o_mem_attr),.o_mem_asi(o_mem_asi),.o_mem_metadata(o_mem_metadata), // Read命令。
  .i_mem_result_valid(i_mem_result_valid),.o_mem_result_ready(o_mem_result_ready),.i_mem_result_slot(i_mem_result_slot),.i_mem_result_data(i_mem_result_data),.i_mem_result_status(i_mem_result_status), // Read结果。
  .i_mem_result_data_full(i_mem_result_data_full),.o_mem_be(o_mem_be),.o_write_mem_valid(o_write_mem_valid),.i_write_mem_ready(i_write_mem_ready),.o_write_mem_slot(o_write_mem_slot),.o_write_mem_address(o_write_mem_address),.o_write_mem_length(o_write_mem_length),.o_write_mem_attr(o_write_mem_attr),.o_write_mem_asi(o_write_mem_asi),.o_write_mem_metadata(o_write_mem_metadata),.o_write_mem_data(o_write_mem_data),.o_write_mem_be(o_write_mem_be),.i_write_mem_result_valid(i_write_mem_result_valid),.o_write_mem_result_ready(o_write_mem_result_ready),.i_write_mem_result_slot(i_write_mem_result_slot),.i_write_mem_result_status(i_write_mem_result_status),.o_write_completer_count(o_write_completer_count),
  .i_atomic_profile_valid(i_atomic_profile_valid),.i_atomic_two_operand(i_atomic_two_operand),.i_atomic_order_profile_valid(i_atomic_order_profile_valid),.i_atomic_order_mode(i_atomic_order_mode),.i_atomic_order_epoch(i_atomic_order_epoch),.o_atomic_backend_valid(o_atomic_backend_valid),.i_atomic_backend_ready(i_atomic_backend_ready),.o_atomic_backend_token(o_atomic_backend_token),.o_atomic_backend_header(o_atomic_backend_header),.o_atomic_backend_port(o_atomic_backend_port),.o_atomic_backend_operands(o_atomic_backend_operands),.o_atomic_backend_byte_enable(o_atomic_backend_byte_enable),.o_atomic_backend_atomic_return(o_atomic_backend_atomic_return),.o_atomic_backend_op_type(o_atomic_backend_op_type),.o_atomic_backend_op_size(o_atomic_backend_op_size),.i_atomic_backend_result_valid(i_atomic_backend_result_valid),.o_atomic_backend_result_ready(o_atomic_backend_result_ready),.i_atomic_backend_result_token(i_atomic_backend_result_token),.i_atomic_backend_result_status(i_atomic_backend_result_status),.i_atomic_backend_result_data(i_atomic_backend_result_data),.o_atomic_response_valid(o_atomic_response_valid),.i_atomic_response_ready(i_atomic_response_ready),.o_atomic_response_token(o_atomic_response_token),.o_atomic_response_atomic_return(o_atomic_response_atomic_return),.o_atomic_response_port(o_atomic_response_port),.o_atomic_response_tag(o_atomic_response_tag),.o_atomic_response_src(o_atomic_response_src),.o_atomic_response_dst(o_atomic_response_dst),.o_atomic_response_status(o_atomic_response_status),.o_atomic_response_data(o_atomic_response_data),.o_atomic_response_data_valid(o_atomic_response_data_valid),
  .o_message_backend_valid(o_message_backend_valid),.i_message_backend_ready(i_message_backend_ready),.o_message_backend_token(o_message_backend_token),.o_message_backend_header(o_message_backend_header),.o_message_backend_port(o_message_backend_port),.o_message_backend_data(o_message_backend_data),.o_message_backend_be(o_message_backend_be),
  .i_message_result_valid(i_message_result_valid),.o_message_result_ready(o_message_result_ready),.i_message_result_token(i_message_result_token),.i_message_result_is_read(i_message_result_is_read),.i_message_result_num_beats(i_message_result_num_beats),.i_message_result_status(i_message_result_status),.i_message_result_data(i_message_result_data),.i_message_result_poison(i_message_result_poison),.o_message_busy(o_message_busy),.o_message_reason(o_message_reason),
  .o_source_valid(),.o_source_control(),.o_source_port(),.o_data_valid(),.o_data0(),.o_data1(),.o_outstanding_count(outstanding_count),.o_completer_count(completer_count),.o_core_error(unused_core), // core观察。
  .o_start_ready(o_start_ready),.o_start_taken(o_start_taken),.o_local_done(o_local_done),.o_peer_done(o_peer_done),.o_peer_shared(unused_peer_shared), // 初始化状态。
  .o_capacity(capacity),.o_available(available),.o_pending(pending),.o_tx_validation_state(tx_validation),.o_port_idle(port_idle),.o_port_error(o_port_error),.o_dispatch_error(unused_dispatch),.o_remote_request_reject_pulse(o_remote_request_reject_pulse),.o_error(o_transaction_error)); // 账本、非致命拒绝及错误。

 endpoint_station_dl_scheduled_path #(.C_REPLAY_DEPTH(REPLAY_DEPTH),.C_ADDR_WIDTH(REPLAY_ADDR_WIDTH)) u_scheduled(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable),.i_ras_rx_cleanup({4{i_ras_rx_cleanup}}&effective_active_mask),.i_requested_mode(effective_requested_mode),.i_mode_commit(i_mode_commit),.i_lane_up(i_lane_up),.i_port_link_reset(i_port_link_reset), // managed路径提交CSR模式及已排空RX清理。
  .o_port_slot_enable(o_port_slot_enable),.o_slot_port(o_slot_port),.o_slot_error(o_slot_error),.o_active_mode(o_active_mode),.o_active_mask(o_active_mask),.o_mode_commit_accept(o_mode_commit_accept),.o_mode_error(o_mode_error), // 日历和模式状态。
  .i_tx_tl_valid(paced_valid),.o_tx_tl_ready(paced_ready),.i_tx_tl_data(paced_flit),.i_tx_tl_msg(paced_msg),.i_tx_tl_sop(paced_sop),.i_tx_tl_eop(paced_eop),.i_tx_flush(paced_flush), // 完整native word进入builder。
  .i_rx_frame_valid(i_rx_frame_valid),.o_rx_frame_ready(o_rx_frame_ready),.i_rx_frame_data(i_rx_frame_data),.i_rx_frame_sop(i_rx_frame_sop),.i_rx_frame_eop(i_rx_frame_eop),.i_rx_fec_complete(i_rx_fec_complete),.i_rx_crc_ok(i_rx_crc_ok), // 已验证frame输入。
  .o_rx_tl_valid(rx_tl_valid),.i_rx_tl_ready(rx_tl_ready),.o_rx_tl_data(rx_tl_data),.o_rx_tl_msg(rx_tl_msg), // 解包TL回唯一owner。
  .o_tx_control_valid(o_tx_control_valid),.i_tx_control_ready(i_tx_control_ready),.o_tx_control_replay_request(o_tx_control_replay_request),.o_tx_control_target(o_tx_control_target), // ACK/replay控制。
  .o_crc_input_valid(o_crc_input_valid),.i_crc_input_ready(i_crc_input_ready),.o_crc_input_data(o_crc_input_data),.o_crc_input_sop(o_crc_input_sop),.o_crc_input_eop(o_crc_input_eop),.o_crc_input_sequence(o_crc_input_sequence),.o_crc_input_replay(o_crc_input_replay), // CRC候选。
  .o_crc_required(o_crc_required),.o_physical_valid(o_physical_valid),.o_tx_resident_count(o_tx_resident_count),.o_tx_unacked_count(tx_unacked),.o_rx_last_sequence(dl_rx_last),.o_rx_bad_crc_count(dl_rx_bad_crc),.o_rx_unexpected_count(dl_rx_unexpected),.o_rx_ambiguous(dl_rx_ambiguous),.o_rx_in_replay(dl_rx_replay),.o_rx_port_quiescent(dl_rx_quiescent),.o_builder_busy(unused_builder_busy),.o_builder_quiescent(unused_builder_quiescent),.o_builder_protocol_error(unused_builder_error), // A19及builder、DL owner状态。
  .o_busy(scheduled_busy),.o_quiescent(scheduled_quiescent),.o_error(o_scheduled_error)); // scheduled聚合状态。

 endpoint_station_epoch_owner_qualification #(.WIDTH(WIDTH))u_epoch_owner_qualification(
  .i_enable(i_rstn&&i_enable),.i_active_mask(effective_active_mask),.i_local_done(o_local_done),.i_peer_done(o_peer_done),.i_port_idle(port_idle),
  .i_capacity(capacity),.i_available(available),.i_pending(pending),.i_tx_validation(tx_validation),
  .i_outstanding_count(outstanding_count),.i_completer_count(completer_count),.i_native_valid(native_valid),.i_paced_valid(paced_valid),.i_transaction_error(o_transaction_error),
  .i_scheduled_quiescent(scheduled_quiescent),.i_scheduled_error(o_scheduled_error),.i_tx_resident_count(o_tx_resident_count),.i_tx_unacked_count(tx_unacked),
  .i_dl_rx_last_sequence(dl_rx_last),.i_dl_rx_bad_crc_count(dl_rx_bad_crc),.i_dl_rx_unexpected_count(dl_rx_unexpected),.i_dl_rx_ambiguous(dl_rx_ambiguous),.i_dl_rx_replay(dl_rx_replay),.i_dl_rx_quiescent(dl_rx_quiescent),
  .o_owner_ready(o_ras_owner_ready),.o_missing_owners(o_ras_missing_owners));
endmodule // 结束单Station transaction到DL模板组合器。

// Managed Station只在这里公开真实owner的组合资格；epoch窗口和证书租约由上层时序owner消费。
module endpoint_station_epoch_owner_qualification #(
 parameter integer WIDTH=8
)(
 input wire i_enable,input wire[3:0] i_active_mask,input wire[3:0] i_local_done,input wire[3:0] i_peer_done,input wire[3:0] i_port_idle,
 input wire[80*(WIDTH+1)-1:0] i_capacity,input wire[80*(WIDTH+1)-1:0] i_available,input wire[80*(WIDTH+1)-1:0] i_pending,input wire[359:0] i_tx_validation,
 input wire[7:0] i_outstanding_count,input wire[7:0] i_completer_count,input wire[3:0] i_native_valid,input wire[3:0] i_paced_valid,input wire i_transaction_error,
 input wire i_scheduled_quiescent,input wire i_scheduled_error,input wire[31:0] i_tx_resident_count,input wire[31:0] i_tx_unacked_count,
 input wire[35:0] i_dl_rx_last_sequence,input wire[11:0] i_dl_rx_bad_crc_count,input wire[31:0] i_dl_rx_unexpected_count,input wire[3:0] i_dl_rx_ambiguous,input wire[3:0] i_dl_rx_replay,input wire[3:0] i_dl_rx_quiescent,
 output wire[2:0] o_owner_ready,output wire[2:0] o_missing_owners
);
 wire[3:0] credit_rebuilt,tx_context_empty,rx_context_empty,dl_tx_empty,dl_rx_rebuilt;wire active_present=|i_active_mask;
 genvar owner_port;generate for(owner_port=0;owner_port<4;owner_port=owner_port+1)begin:gen_owner_port
  wire validation_budget_observed=|i_tx_validation[owner_port*90+3+:7];
  assign credit_rebuilt[owner_port]=!i_active_mask[owner_port]||
   ((i_available[owner_port*20*(WIDTH+1)+:20*(WIDTH+1)]==i_capacity[owner_port*20*(WIDTH+1)+:20*(WIDTH+1)])&&
    !(|i_pending[owner_port*20*(WIDTH+1)+:20*(WIDTH+1)]));
  assign tx_context_empty[owner_port]=!i_active_mask[owner_port]||
   (i_port_idle[owner_port]&&!(|i_tx_validation[owner_port*90+89:owner_port*90+10])&&!(|i_tx_validation[owner_port*90+:3])&&
    (validation_budget_observed||!validation_budget_observed));
  assign rx_context_empty[owner_port]=!i_active_mask[owner_port]||i_port_idle[owner_port];
  assign dl_tx_empty[owner_port]=!i_active_mask[owner_port]||
   ((i_tx_resident_count[owner_port*8+:8]==0)&&(i_tx_unacked_count[owner_port*8+:8]==0));
  assign dl_rx_rebuilt[owner_port]=!i_active_mask[owner_port]||
   ((i_dl_rx_last_sequence[owner_port*9+:9]==9'd511)&&(i_dl_rx_bad_crc_count[owner_port*3+:3]==0)&&
    (i_dl_rx_unexpected_count[owner_port*8+:8]==0)&&!i_dl_rx_ambiguous[owner_port]&&!i_dl_rx_replay[owner_port]);
 end endgenerate
 wire initialization_complete=&((~i_active_mask)|(i_local_done&i_peer_done));
 wire transaction_empty=(i_outstanding_count==0)&&(i_completer_count==0)&&!(|(i_native_valid&i_active_mask))&&!(|(i_paced_valid&i_active_mask));
 wire common_healthy=i_enable&&active_present&&!i_transaction_error&&!i_scheduled_error;
 assign o_owner_ready[2]=common_healthy&&initialization_complete&&transaction_empty&&(&credit_rebuilt)&&(&tx_context_empty);
 assign o_owner_ready[1]=common_healthy&&i_scheduled_quiescent&&(&dl_tx_empty);
 assign o_owner_ready[0]=common_healthy&&initialization_complete&&transaction_empty&&(&((~i_active_mask)|i_dl_rx_quiescent))&&(&rx_context_empty)&&(&dl_rx_rebuilt);
 assign o_missing_owners=~o_owner_ready;
endmodule
`default_nettype wire
