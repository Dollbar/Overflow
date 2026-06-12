`timescale 1ns/1ps
`default_nettype none
// 单Station事务RX组合边界；四个tl_port分别独占链路credit、存储、退休和FC发布。
module endpoint_station_transaction_rx_composer #( // 将四路退休记录原子仲裁至一个四逻辑端口transaction core。
 parameter integer WIDTH=8, // 每个tl_port的credit计数宽度。
 parameter integer HEADER_DEPTH=2, // 每个tl_port保留的发送header队列深度。
 parameter integer BANK_DEPTH=3, // 每个tl_port保留的发送data bank深度。
 parameter integer RX_DEPTH=40, // 每个tl_port唯一接收FIFO深度。
 parameter integer HEADER_COUNT_WIDTH=(HEADER_DEPTH<2)?1:(HEADER_DEPTH<4)?2:3, // header计数宽度覆盖配置深度。
 parameter integer DATA_COUNT_WIDTH=(BANK_DEPTH<2)?1:(BANK_DEPTH<4)?2:3, // data计数宽度覆盖配置深度。
 parameter integer RX_COUNT_WIDTH=(RX_DEPTH<2)?1:(RX_DEPTH<4)?2:(RX_DEPTH<8)?3:(RX_DEPTH<16)?4:(RX_DEPTH<32)?5:(RX_DEPTH<64)?6:7, // RX计数宽度覆盖配置深度。
 parameter integer ORIGINATOR_CAPACITY=4, // core应用请求Tag槽容量。
 parameter integer COMPLETER_CAPACITY=4, // core目的端Read执行槽容量。
 parameter integer TX_CLOSE_ENABLE=0,parameter integer RUNTIME_ACTIVE_ENABLE=0,parameter integer MESSAGE_ENABLE=0,parameter integer MESSAGE_TOKEN_WIDTH=16,parameter integer NORMAL_WRITE_ENABLE=0,parameter integer FULL_READ_ENABLE=0,parameter integer ATOMIC_ENABLE=0,parameter integer ATOMIC_TX_CLOSE_ENABLE=0,parameter integer ATOMIC_TOKEN_WIDTH=16,parameter integer ORDINARY_ORDERING_ENABLE=0,parameter integer PACKET_BOUNDARY_ENABLE=0, // 普通ordering默认关闭；启用时源Tag槽把token保持到最终应用完成握手。
 parameter [3:0] ACTIVE_PORT_MASK=4'b0101 // 默认2x2模式只激活稀疏本地端口零和二。
)(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire i_remote_request_admission_enable,input wire [3:0] i_active_mask, // drain仅关闭新远端事务，链路接收和既有owner继续。
 input wire [3:0] i_port_link_reset,input wire [3:0] i_start,input wire [3:0] i_shared, // 四个稳定本地端口的独立链路控制。
 input wire [80*WIDTH-1:0] i_capacities, // 四组二十类本地接收容量，低位组对应端口零。
 input wire [3:0] i_rx_valid,input wire [2047:0] i_rx_flit,input wire [7:0] i_rx_msg, // Station DL已提交且已验证的四路TL RX输入。
 output wire [3:0] o_rx_ready,output wire [3:0] o_rx_taken, // 四个唯一tl_port owner返回的接纳资格和事件。
 output wire [3:0] o_port_tx_valid,output wire [2047:0] o_port_tx_flit,output wire [7:0] o_port_tx_msg,output wire [3:0] o_port_tx_packet_sop,o_port_tx_packet_eop, // 每个tl_port独立产生的FC TL输出。
 input wire [3:0] i_port_tx_ready, // 外部Station TX路径逐端口返回的真实发送ready。
 output wire o_retired_valid,output wire o_retired_ready,output wire [511:0] o_retired_flit, // 送入core的锁定退休握手与flit观察。
 output wire [1:0] o_retired_msg,output wire [5:0] o_retired_classes,output wire [79:0] o_retired_releases,output wire [1:0] o_retired_port, // 同一winner的其余退休字段。
 input wire [9:0] i_local_id, // core本地组件身份配置。
 input wire i_request_valid,output wire o_request_ready,input wire [1:0] i_request_port, // 应用Read请求握手和稀疏本地端口身份。
 input wire [10:0] i_request_tag,input wire [56:0] i_request_address,input wire [9:0] i_request_dst, // 应用Read请求Tag、地址和目的端。
 input wire [5:0] i_request_length,input wire [7:0] i_request_attr, // 应用Read请求长度和属性。
 input wire i_request_is_write,input wire i_request_full,input wire [1:0] i_request_asi,input wire [7:0] i_request_metadata,input wire [2047:0] i_request_data,input wire [255:0] i_request_be, // 可选普通Write/full Read字段；禁用profile时由core忽略。
 input wire[3:0] i_order_profile_valid,input wire[7:0] i_order_mode,input wire[31:0] i_order_epoch,input wire[3:0] i_order_affinity_valid,input wire[7:0] i_order_actual_vc, // 每Logical Port显式plaintext ordering合同；profile_valid低包含Security/Auth拒绝。
 output wire[3:0] o_order_busy,output wire[3:0] o_order_quiescent,output wire[3:0] o_order_error, // 首阶段owner观察；尚未宣称completion退休。
 output wire o_complete_valid,input wire i_complete_ready,output wire [1:0] o_complete_port, // 应用Read完成握手与原始端口身份。
 output wire [10:0] o_complete_tag,output wire [3:0] o_complete_status,output wire [511:0] o_complete_data,output wire o_complete_data_valid, // 应用Read完成内容。
 output wire o_complete_is_write,output wire [2047:0] o_complete_data_full,output wire [255:0] o_complete_mask, // 完整普通事务完成身份、数据和有效字节。
 output wire o_mem_valid,input wire i_mem_ready,output wire [1:0] o_mem_slot, // 目的端Read后端命令握手与槽身份。
 output wire [56:0] o_mem_address,output wire [5:0] o_mem_length,output wire [7:0] o_mem_attr, // 目的端Read后端命令字段。
 output wire [1:0] o_mem_asi,output wire [7:0] o_mem_metadata, // 目的端Read后端ASI和metadata。
 input wire i_mem_result_valid,output wire o_mem_result_ready,input wire [1:0] i_mem_result_slot, // Read后端结果握手与槽身份。
 input wire [511:0] i_mem_result_data,input wire [3:0] i_mem_result_status, // Read后端结果数据和状态。
 input wire [2047:0] i_mem_result_data_full,output wire [255:0] o_mem_be, // Full Read后端完整结果及请求字节使能。
 output wire o_write_mem_valid,input wire i_write_mem_ready,output wire [1:0] o_write_mem_slot,output wire [56:0] o_write_mem_address,output wire [5:0] o_write_mem_length,output wire [7:0] o_write_mem_attr,output wire [1:0] o_write_mem_asi,output wire [7:0] o_write_mem_metadata,output wire [2047:0] o_write_mem_data,output wire [255:0] o_write_mem_be, // 现有Write completer的唯一后端命令。
 input wire i_write_mem_result_valid,output wire o_write_mem_result_ready,input wire [1:0] i_write_mem_result_slot,input wire [3:0] i_write_mem_result_status,output wire [7:0] o_write_completer_count, // Write执行结果按原slot exactly-once返回。
 input wire[31:0] i_atomic_profile_valid,input wire[31:0] i_atomic_two_operand,input wire i_atomic_order_profile_valid,input wire[1:0] i_atomic_order_mode,input wire[7:0] i_atomic_order_epoch, // Atomic操作和ordering均由平台显式给出typed合同。
 output wire[3:0] o_atomic_backend_valid,input wire[3:0] i_atomic_backend_ready,output wire[4*ATOMIC_TOKEN_WIDTH-1:0] o_atomic_backend_token,output wire[511:0] o_atomic_backend_header,output wire[7:0] o_atomic_backend_port,output wire[2047:0] o_atomic_backend_operands,output wire[1023:0] o_atomic_backend_byte_enable,output wire[3:0] o_atomic_backend_atomic_return,output wire[19:0] o_atomic_backend_op_type,output wire[7:0] o_atomic_backend_op_size, // 四个Logical Port独立Atomic后端owner。
 input wire[3:0] i_atomic_backend_result_valid,output wire[3:0] o_atomic_backend_result_ready,input wire[4*ATOMIC_TOKEN_WIDTH-1:0] i_atomic_backend_result_token,input wire[15:0] i_atomic_backend_result_status,input wire[2047:0] i_atomic_backend_result_data, // 结果按每端口唯一token返回。
 output wire[3:0] o_atomic_response_valid,input wire[3:0] i_atomic_response_ready,output wire[4*ATOMIC_TOKEN_WIDTH-1:0] o_atomic_response_token,output wire[3:0] o_atomic_response_atomic_return,output wire[7:0] o_atomic_response_port,output wire[43:0] o_atomic_response_tag,output wire[39:0] o_atomic_response_src,output wire[39:0] o_atomic_response_dst,output wire[15:0] o_atomic_response_status,output wire[2047:0] o_atomic_response_data,output wire[3:0] o_atomic_response_data_valid, // typed响应描述符；后续TL formatter消费后才算网络完成。
 output wire o_message_backend_valid,input wire i_message_backend_ready,output wire[MESSAGE_TOKEN_WIDTH-1:0] o_message_backend_token,output wire[127:0] o_message_backend_header,output wire[1:0] o_message_backend_port,output wire[2047:0] o_message_backend_data,output wire[255:0] o_message_backend_be,
 input wire i_message_result_valid,output wire o_message_result_ready,input wire[MESSAGE_TOKEN_WIDTH-1:0] i_message_result_token,input wire i_message_result_is_read,input wire[1:0] i_message_result_num_beats,input wire[3:0] i_message_result_status,input wire[2047:0] i_message_result_data,input wire[3:0] i_message_result_poison,output wire o_message_busy,output wire[7:0] o_message_reason,
 output wire [1:0] o_source_valid,output wire [511:0] o_source_control,output wire [3:0] o_source_port, // core全部TX source类别及稳定端口身份原样外露。
 input wire [1:0] i_source_captured,input wire i_request_header_taken, // 外部TX owner返回的source捕获及真实请求header退休事件。
 output wire [3:0] o_data_valid,output wire [511:0] o_data0,output wire [511:0] o_data1, // core全部TX data类别原样外露。
 input wire [3:0] i_data_accepted, // 外部TX owner返回的各类别实际data接纳数量。
 output wire [7:0] o_outstanding_count,output wire [7:0] o_completer_count,output wire o_core_error, // core所有权占用与错误观察。
 output wire [3:0] o_start_ready,output wire [3:0] o_start_taken,output wire [3:0] o_local_done, // 四个tl_port的本地credit初始化状态。
 output wire [3:0] o_peer_done,output wire [3:0] o_peer_shared, // 四个tl_port观察到的对端credit初始化状态。
 output wire [80*(WIDTH+1)-1:0] o_capacity,output wire [80*(WIDTH+1)-1:0] o_available,output wire [80*(WIDTH+1)-1:0] o_pending, // 四个独立credit账本观察。
 output wire [359:0] o_tx_validation_state,output wire [3:0] o_port_idle,output wire [3:0] o_port_error, // 四个独立tl_port状态与错误。
 output wire o_dispatch_error,output wire [7:0] o_port_header_taken,output wire o_tx_request_header_taken, // 闭环TX路由及真实header反馈观察。
 output wire [3:0] o_remote_request_reject_pulse, // 每端口新远端Request/Message/Atomic在drain中安全丢弃一次的非致命事件。
 output wire o_error // inactive输入、任一端口owner或core错误的聚合失败关闭诊断。
);
 wire [3:0] effective_active_mask; // 默认ABI保持静态mask；managed路径使用calendar已提交mask。
 wire [3:0] inactive_port_mask; // 运行时inactive端口集合用于失败关闭检查。
 wire composer_rstn; // Station禁用时同步清空全部局部owner状态。
 wire request_port_active; // 应用请求必须保留合法稀疏端口身份。
 wire core_request_ready; // core原始应用请求ready在active检查后外露。
 wire ordered_request_valid,ordered_request_ready;wire[10:0] ordered_request_tag;wire[56:0] ordered_request_address;wire[9:0] ordered_request_src,ordered_request_dst;wire[5:0] ordered_request_length;wire[7:0] ordered_request_attr,ordered_request_metadata;wire ordered_request_is_write,ordered_request_full;wire[1:0] ordered_request_asi,ordered_request_port,ordered_request_vc;wire[2047:0] ordered_request_data;wire[255:0] ordered_request_be;
 wire[7:0] ordered_request_epoch,core_complete_order_epoch;wire[15:0] ordered_request_token,core_complete_order_token;
 wire[3:0] order_stage_valid,order_stage_ready,order_stage_core_ready;wire[43:0] order_stage_tag;wire[227:0] order_stage_address;wire[39:0] order_stage_src,order_stage_dst;wire[23:0] order_stage_length;wire[31:0] order_stage_attr,order_stage_metadata;wire[3:0] order_stage_is_write,order_stage_full;wire[7:0] order_stage_asi,order_stage_port,order_stage_vc;wire[8191:0] order_stage_data;wire[1023:0] order_stage_be;wire[3:0] unused_order_issue_valid,unused_order_profile_error,unused_order_reset_error;wire[31:0] unused_order_issue_epoch;wire[63:0] unused_order_issue_token;
 wire [3:0] raw_port_read_valid,port_read_valid; // tl_port原始退休头与Atomic分流后的普通事务头。
 wire [2047:0] raw_port_read_flit,port_read_flit; // 四端口完整flit在分流前后均保持。
 wire [7:0] raw_port_read_msg,port_read_msg; // 四端口Message类型。
 wire [23:0] raw_port_read_classes,port_read_classes; // 四端口消费class。
 wire [319:0] raw_port_read_releases,port_read_releases; // 四端口credit释放身份。
 wire [3:0] atomic_input_ready,atomic_busy,atomic_quiescent,atomic_error,atomic_request_reject_pulse; // 每Logical Port独立Atomic typed owner状态。
 wire [3:0] arbiter_ready; // 锁定arbiter只向实际winner返回退休ready。
 wire arbiter_valid; // 锁定arbiter向core提供的有效退休记录。
 wire [511:0] arbiter_flit; // 锁定arbiter选择的退休flit。
 wire [1:0] arbiter_msg; // 锁定arbiter选择的退休消息。
 wire [1:0] arbiter_port; // 锁定arbiter保存的稀疏本地端口身份。
 reg [5:0] selected_classes; // 按同一arbiter winner选择的消费class。
 reg [79:0] selected_releases; // 按同一arbiter winner选择的credit释放向量。
 wire core_read_ready; // transaction core对完整600-bit退休记录的唯一ready。
 wire core_request_reject_pulse;wire[1:0] core_request_reject_port;wire[3:0] core_request_reject_onehot;
 wire inactive_rx_error; // inactive链路输入不得被任何owner接纳。
 wire inactive_start_error; // inactive链路不得启动伪credit上下文。
 wire inactive_request_error,unsupported_request_error; // 应用请求不得使用inactive端口或未启用类型。
 wire [1:0] core_source_valid; // core的Request和Response source有效。
 wire [511:0] core_source_control; // core两类source控制，各占低高256位。
 wire [3:0] core_source_port; // core两类source各自稳定的Station-local端口身份。
 wire [3:0] core_data_valid; // core两类source关联的四个data有效位。
 wire [511:0] core_data0,core_data1; // core四类data内容。
 wire [7:0] port_source_valid,port_source_ready,port_source_captured,dispatched_source_valid,dispatcher_source_captured; // 最终tl_port与普通core dispatcher握手分离。
 wire [2047:0] port_source_control,dispatched_source_control; // Atomic merge后和merge前控制。
 wire [15:0] port_data_valid,port_data_accepted,dispatched_data_valid,dispatcher_data_accepted; // Atomic merge后和普通core反馈。
 wire [2047:0] port_data0,port_data1,dispatched_data0,dispatched_data1; // data沿相同owner保存。
 wire[3:0] atomic_native_source_valid,atomic_native_source_captured,atomic_native_busy,atomic_native_quiescent,atomic_native_error,atomic_response_ready_internal;
 wire[1023:0] atomic_native_control;wire[7:0] atomic_native_data_valid,atomic_native_data_accepted;wire[1023:0] atomic_native_data0,atomic_native_data1;
 wire[7:0] atomic_response_vc;wire[3:0] atomic_response_pool,response_merge_busy,response_merge_quiescent,response_merge_error;
 wire [7:0] port_data_ready,port_header_taken; // 四个唯一tl_port的data ready和真实header退休事件。
 wire[3:0] tl_port_idle;
 wire [1:0] core_source_captured; // dispatcher从真实owner选择回core的source捕获反馈。
 wire [3:0] core_data_accepted; // dispatcher从真实owner选择回core的data接纳反馈。
 wire core_request_header_taken; // 按Request source端口选择回core的真实header退休事件。
 wire source0_active; // Request source当前端口必须属于active稀疏集合。
 wire dispatcher_error; // inactive source或data身份失败关闭诊断。
 wire [3:0] unused_feature_error; // Security和Compression固定关闭后的端口特性错误观察。
 wire [3:0] unused_implemented; // 四个现有tl_port的实现存在证书。
 wire [3:0] unused_legacy_ready,unused_legacy_valid; // 四个tl_port旧scaffold输出保持未实现状态。
 wire [2047:0] unused_legacy_data; // 四个tl_port旧scaffold数据输出观察。
 wire [511:0] unused_legacy_meta; // 四个tl_port旧scaffoldmetadata输出观察。
 wire unused_tx_stop,unused_tx_local_drained,unused_ras_isolated,unused_ras_recovered; // 禁用RAS profile的状态输出。
 wire unused_ras_recover_ready,unused_ras_blocked,unused_ras_dummy_done_fire; // 禁用RAS恢复和dummy完成输出。
 wire [1:0] unused_tx_port,unused_ras_dummy_done_slot,unused_complete_slot; // 禁用RAS相关端口和槽输出。
 wire [7:0] unused_ras_epoch,unused_complete_epoch,unused_complete_generation,unused_ras_ledger_count; // 禁用RAS epoch、generation和账本输出。
 wire [2:0] unused_complete_beats; // 默认Read完成beat数量观察。
 wire unused_complete_cancel,unused_complete_is_dummy,unused_ras_receiver_idle,unused_ras_other_role_idle; // 禁用RAS完成和排空输出。
 wire [183:0] unused_native_complete_payload; // 禁用native profile完成payload输出。
 wire [1:0] unused_native_complete_vc; // 禁用native profile完成VC输出。
 wire unused_native_complete_pool; // 禁用native profile完成pool输出。
 wire [2047:0] unused_native_complete_raw_data; // 禁用native大数据输出。
 wire [255:0] unused_native_complete_raw_headers; // 禁用native header输出。
 wire [3:0] unused_data_poison,unused_native_complete_raw_poison; // 禁用Message和native poison输出。
 wire unused_native_complete_is_message; // 禁用native Message类型输出。
 wire [2:0] unused_native_complete_response_beats; // 禁用native Message响应beat输出。
 wire unused_observation; // 汇总全部禁用profile观察以避免隐式悬空owner。

 assign effective_active_mask=(RUNTIME_ACTIVE_ENABLE!=0)?i_active_mask:ACTIVE_PORT_MASK;
 assign inactive_port_mask=~effective_active_mask;
 assign composer_rstn=i_rstn&&i_enable; // Station禁用时同步清空全部局部owner状态。
 wire request_capability_legal=(NORMAL_WRITE_ENABLE!=0)||!i_request_is_write; // 关闭普通Write时不得把Write重解释成Read。
 assign request_port_active=effective_active_mask[i_request_port]&&!i_port_link_reset[i_request_port]; // 应用请求必须保留当前模式且未复位的合法端口身份。
 assign inactive_rx_error=composer_rstn&&(|(i_rx_valid&inactive_port_mask)); // inactive链路输入不得被任何owner接纳。
 assign inactive_start_error=composer_rstn&&(|(i_start&inactive_port_mask)); // inactive链路不得启动伪credit上下文。
 assign inactive_request_error=composer_rstn&&i_request_valid&&!request_port_active; // 应用请求不得使用inactive稀疏端口身份。
 assign unsupported_request_error=composer_rstn&&i_request_valid&&!request_capability_legal; // 未启用的Write显式失败关闭。
 assign source0_active=effective_active_mask[core_source_port[1:0]]; // 四个稳定端口身份直接索引当前active集合。
 assign core_request_header_taken=(TX_CLOSE_ENABLE!=0)?((composer_rstn&&source0_active)?port_header_taken[{core_source_port[1:0],1'b0}]:1'b0):i_request_header_taken; // 闭合模式下Request只接收其所属唯一owner的真实header退休事件。
 assign o_source_valid=core_source_valid; // 保留core source观察边界用于集成诊断。
 assign o_source_control=core_source_control; // 保留core source控制观察边界。
 assign o_source_port=core_source_port; // 保留core稳定端口身份观察边界。
 assign o_data_valid=core_data_valid; // 保留core四类data有效观察边界。
 assign o_data0=core_data0; // 保留core低data内容观察边界。
 assign o_data1=core_data1; // 保留core高data内容观察边界。
 assign o_dispatch_error=(TX_CLOSE_ENABLE!=0)&&dispatcher_error; // RX-only兼容模式不声明内部TX路由错误。
 assign o_port_header_taken=port_header_taken; // 公开四个真实owner的两类header发送事件。
 assign o_tx_request_header_taken=core_request_header_taken; // 公开实际回送core的Request header事件。

 generate if(ORDINARY_ORDERING_ENABLE==1)begin:gen_ordinary_ordering
  genvar order_port;
  for(order_port=0;order_port<4;order_port=order_port+1)begin:gen_port
   endpoint_ordinary_ordering_admission #(.C_RETIRE_ENABLE(1),.C_CANCEL_ON_LINK_RESET(1))u_order_admission(
    .i_clk(i_clk),.i_rstn(composer_rstn),.i_enable(effective_active_mask[order_port]),.i_admission_enable(i_remote_request_admission_enable),.i_port_link_reset(i_port_link_reset[order_port]),
    .i_profile_valid(i_order_profile_valid[order_port]),.i_mode(i_order_mode[order_port*2+:2]),.i_epoch(i_order_epoch[order_port*8+:8]),.i_affinity_valid(i_order_affinity_valid[order_port]),.i_actual_vc(i_order_actual_vc[order_port*2+:2]),.i_port(order_port[1:0]),
    .i_request_valid(i_request_valid&&(i_request_port==order_port[1:0])&&request_port_active&&request_capability_legal),.o_request_ready(order_stage_ready[order_port]),.i_request_tag(i_request_tag),.i_request_address(i_request_address),.i_request_src(i_local_id),.i_request_dst(i_request_dst),.i_request_length(i_request_length),.i_request_attr(i_request_attr),.i_request_is_write(i_request_is_write),.i_request_full(i_request_full),.i_request_asi(i_request_asi),.i_request_metadata(i_request_metadata),.i_request_data(i_request_data),.i_request_be(i_request_be),
    .o_downstream_valid(order_stage_valid[order_port]),.i_downstream_ready(order_stage_core_ready[order_port]),.o_downstream_tag(order_stage_tag[order_port*11+:11]),.o_downstream_address(order_stage_address[order_port*57+:57]),.o_downstream_src(order_stage_src[order_port*10+:10]),.o_downstream_dst(order_stage_dst[order_port*10+:10]),.o_downstream_length(order_stage_length[order_port*6+:6]),.o_downstream_attr(order_stage_attr[order_port*8+:8]),.o_downstream_is_write(order_stage_is_write[order_port]),.o_downstream_full(order_stage_full[order_port]),.o_downstream_asi(order_stage_asi[order_port*2+:2]),.o_downstream_metadata(order_stage_metadata[order_port*8+:8]),.o_downstream_data(order_stage_data[order_port*2048+:2048]),.o_downstream_be(order_stage_be[order_port*256+:256]),.o_downstream_port(order_stage_port[order_port*2+:2]),.o_downstream_actual_vc(order_stage_vc[order_port*2+:2]),
    .o_order_issue_valid(unused_order_issue_valid[order_port]),.o_order_issue_epoch(unused_order_issue_epoch[order_port*8+:8]),.o_order_issue_token(unused_order_issue_token[order_port*16+:16]),.i_order_retire_valid(o_complete_valid&&i_complete_ready&&(o_complete_port==order_port[1:0])),.i_order_retire_epoch(core_complete_order_epoch),.i_order_retire_token(core_complete_order_token),.o_busy(o_order_busy[order_port]),.o_quiescent(o_order_quiescent[order_port]),.o_profile_error(unused_order_profile_error[order_port]),.o_reset_error(unused_order_reset_error[order_port]),.o_error(o_order_error[order_port]));
  end
  assign ordered_request_valid=|order_stage_valid;
  assign order_stage_core_ready[0]=core_request_ready;assign order_stage_core_ready[1]=core_request_ready&&!order_stage_valid[0];assign order_stage_core_ready[2]=core_request_ready&&!(|order_stage_valid[1:0]);assign order_stage_core_ready[3]=core_request_ready&&!(|order_stage_valid[2:0]);
  assign ordered_request_ready=order_stage_ready[i_request_port];
  assign ordered_request_tag=order_stage_valid[0]?order_stage_tag[10:0]:order_stage_valid[1]?order_stage_tag[21:11]:order_stage_valid[2]?order_stage_tag[32:22]:order_stage_tag[43:33];
  assign ordered_request_address=order_stage_valid[0]?order_stage_address[56:0]:order_stage_valid[1]?order_stage_address[113:57]:order_stage_valid[2]?order_stage_address[170:114]:order_stage_address[227:171];
  assign ordered_request_src=order_stage_valid[0]?order_stage_src[9:0]:order_stage_valid[1]?order_stage_src[19:10]:order_stage_valid[2]?order_stage_src[29:20]:order_stage_src[39:30];
  assign ordered_request_dst=order_stage_valid[0]?order_stage_dst[9:0]:order_stage_valid[1]?order_stage_dst[19:10]:order_stage_valid[2]?order_stage_dst[29:20]:order_stage_dst[39:30];
  assign ordered_request_length=order_stage_valid[0]?order_stage_length[5:0]:order_stage_valid[1]?order_stage_length[11:6]:order_stage_valid[2]?order_stage_length[17:12]:order_stage_length[23:18];
  assign ordered_request_attr=order_stage_valid[0]?order_stage_attr[7:0]:order_stage_valid[1]?order_stage_attr[15:8]:order_stage_valid[2]?order_stage_attr[23:16]:order_stage_attr[31:24];
  assign ordered_request_metadata=order_stage_valid[0]?order_stage_metadata[7:0]:order_stage_valid[1]?order_stage_metadata[15:8]:order_stage_valid[2]?order_stage_metadata[23:16]:order_stage_metadata[31:24];
  assign ordered_request_is_write=|(order_stage_valid&order_stage_is_write);assign ordered_request_full=|(order_stage_valid&order_stage_full);
  assign ordered_request_asi=order_stage_valid[0]?order_stage_asi[1:0]:order_stage_valid[1]?order_stage_asi[3:2]:order_stage_valid[2]?order_stage_asi[5:4]:order_stage_asi[7:6];
  assign ordered_request_port=order_stage_valid[0]?order_stage_port[1:0]:order_stage_valid[1]?order_stage_port[3:2]:order_stage_valid[2]?order_stage_port[5:4]:order_stage_port[7:6];
  assign ordered_request_vc=order_stage_valid[0]?order_stage_vc[1:0]:order_stage_valid[1]?order_stage_vc[3:2]:order_stage_valid[2]?order_stage_vc[5:4]:order_stage_vc[7:6];
  assign ordered_request_data=order_stage_valid[0]?order_stage_data[2047:0]:order_stage_valid[1]?order_stage_data[4095:2048]:order_stage_valid[2]?order_stage_data[6143:4096]:order_stage_data[8191:6144];
  assign ordered_request_be=order_stage_valid[0]?order_stage_be[255:0]:order_stage_valid[1]?order_stage_be[511:256]:order_stage_valid[2]?order_stage_be[767:512]:order_stage_be[1023:768];
  assign ordered_request_epoch=order_stage_valid[0]?unused_order_issue_epoch[7:0]:order_stage_valid[1]?unused_order_issue_epoch[15:8]:order_stage_valid[2]?unused_order_issue_epoch[23:16]:unused_order_issue_epoch[31:24];
  assign ordered_request_token=order_stage_valid[0]?unused_order_issue_token[15:0]:order_stage_valid[1]?unused_order_issue_token[31:16]:order_stage_valid[2]?unused_order_issue_token[47:32]:unused_order_issue_token[63:48];
 end else begin:gen_ordinary_ordering_disabled
  assign ordered_request_valid=i_request_valid&&request_port_active&&request_capability_legal&&composer_rstn;assign ordered_request_ready=core_request_ready;assign ordered_request_tag=i_request_tag;assign ordered_request_address=i_request_address;assign ordered_request_src=i_local_id;assign ordered_request_dst=i_request_dst;assign ordered_request_length=i_request_length;assign ordered_request_attr=i_request_attr;assign ordered_request_metadata=i_request_metadata;assign ordered_request_is_write=i_request_is_write;assign ordered_request_full=i_request_full;assign ordered_request_asi=i_request_asi;assign ordered_request_port=i_request_port;assign ordered_request_vc=2'd0;assign ordered_request_data=i_request_data;assign ordered_request_be=i_request_be;
  assign ordered_request_epoch=8'd0;assign ordered_request_token=16'd0;
  assign order_stage_valid=4'd0;assign order_stage_ready=4'd0;assign order_stage_core_ready=4'd0;assign order_stage_tag=44'd0;assign order_stage_address=228'd0;assign order_stage_src=40'd0;assign order_stage_dst=40'd0;assign order_stage_length=24'd0;assign order_stage_attr=32'd0;assign order_stage_metadata=32'd0;assign order_stage_is_write=4'd0;assign order_stage_full=4'd0;assign order_stage_asi=8'd0;assign order_stage_port=8'd0;assign order_stage_vc=8'd0;assign order_stage_data=8192'd0;assign order_stage_be=1024'd0;assign unused_order_issue_valid=4'd0;assign unused_order_profile_error=4'd0;assign unused_order_reset_error=4'd0;assign unused_order_issue_epoch=32'd0;assign unused_order_issue_token=64'd0;assign o_order_busy=4'd0;assign o_order_quiescent=4'hf;assign o_order_error=4'd0;
 end endgenerate
 assign o_request_ready=(ORDINARY_ORDERING_ENABLE==1)?ordered_request_ready:(composer_rstn&&request_port_active&&request_capability_legal&&core_request_ready);

 endpoint_tl_group_dispatcher #(.PORTS(4),.ACTIVE_PORT_MASK(ACTIVE_PORT_MASK),.RUNTIME_ACTIVE_ENABLE(RUNTIME_ACTIVE_ENABLE)) u_tx_dispatcher( // 将core两类source和四类data按稳定端口身份送入唯一owner。
  .i_rstn(composer_rstn&&(TX_CLOSE_ENABLE!=0)),.i_active_mask(effective_active_mask),.i_source_valid(core_source_valid),.i_source_control(core_source_control),.i_source_port(core_source_port), // 关闭模式组合清零全部路由输出。
  .i_data_valid(core_data_valid),.i_data0(core_data0),.i_data1(core_data1), // data端口身份继承对应source group。
  .o_port_source_valid(dispatched_source_valid),.o_port_source_control(dispatched_source_control), // 每个端口先获得普通core source。
  .o_port_data_valid(dispatched_data_valid),.o_port_data0(dispatched_data0),.o_port_data1(dispatched_data1), // data在Atomic merge前保持core归属。
  .i_port_source_captured(dispatcher_source_captured),.i_port_data_accepted(dispatcher_data_accepted), // merge仅在真实tl_port完整接纳后反馈。
  .o_source_captured(core_source_captured),.o_data_accepted(core_data_accepted),.o_error(dispatcher_error)); // 将实际owner反馈按原group归并回core。

 genvar p; // 生成四个固定Station-local端口owner的索引。
 generate for(p=0;p<32'd4;p=p+1)begin:gen_port_owner // 每个link严格只有一个tl_port拥有RX credit、存储、退休和FC。
  assign port_source_valid[p*2]=dispatched_source_valid[p*2];assign port_source_control[p*512+:256]=dispatched_source_control[p*512+:256];
  assign port_data_valid[p*4+:2]=dispatched_data_valid[p*4+:2];assign port_data0[p*512+:256]=dispatched_data0[p*512+:256];assign port_data1[p*512+:256]=dispatched_data1[p*512+:256];
  assign dispatcher_source_captured[p*2]=port_source_captured[p*2];assign dispatcher_data_accepted[p*4+:2]=port_data_accepted[p*4+:2];
  endpoint_atomic_native_response_owner #(.C_TOKEN_WIDTH(ATOMIC_TOKEN_WIDTH)) u_atomic_native_response(
   .i_clk(i_clk),.i_rstn(composer_rstn&&(ATOMIC_ENABLE!=0)&&(ATOMIC_TX_CLOSE_ENABLE!=0)&&!i_port_link_reset[p]),.i_enable(effective_active_mask[p]),
   .i_order_profile_valid(i_atomic_order_profile_valid),.i_order_mode(i_atomic_order_mode),.i_order_epoch(i_atomic_order_epoch),
   .i_response_valid(o_atomic_response_valid[p]),.o_response_ready(atomic_response_ready_internal[p]),.i_response_token(o_atomic_response_token[p*ATOMIC_TOKEN_WIDTH+:ATOMIC_TOKEN_WIDTH]),.i_atomic_return(o_atomic_response_atomic_return[p]),.i_port(o_atomic_response_port[p*2+:2]),.i_tag(o_atomic_response_tag[p*11+:11]),.i_src(o_atomic_response_src[p*10+:10]),.i_dst(o_atomic_response_dst[p*10+:10]),.i_vc(atomic_response_vc[p*2+:2]),.i_pool(atomic_response_pool[p]),.i_status(o_atomic_response_status[p*4+:4]),.i_data(o_atomic_response_data[p*512+:512]),.i_data_valid(o_atomic_response_data_valid[p]),
   .o_source_valid(atomic_native_source_valid[p]),.o_source_control(atomic_native_control[p*256+:256]),.i_source_captured(atomic_native_source_captured[p]),.o_data_valid(atomic_native_data_valid[p*2+:2]),.o_data0(atomic_native_data0[p*256+:256]),.o_data1(atomic_native_data1[p*256+:256]),.i_data_accepted(atomic_native_data_accepted[p*2+:2]),.o_busy(atomic_native_busy[p]),.o_quiescent(atomic_native_quiescent[p]),.o_error(atomic_native_error[p]));
  endpoint_tl_response_owner_merge u_response_merge(
   .i_clk(i_clk),.i_rstn(composer_rstn&&!i_port_link_reset[p]),.i_enable(effective_active_mask[p]&&(TX_CLOSE_ENABLE!=0)),
   .i_normal_valid(dispatched_source_valid[p*2+1]),.i_normal_control(dispatched_source_control[p*512+256+:256]),.i_normal_data_valid(dispatched_data_valid[p*4+2+:2]),.i_normal_data0(dispatched_data0[p*512+256+:256]),.i_normal_data1(dispatched_data1[p*512+256+:256]),.o_normal_source_captured(dispatcher_source_captured[p*2+1]),.o_normal_data_accepted(dispatcher_data_accepted[p*4+2+:2]),
   .i_atomic_valid(atomic_native_source_valid[p]),.i_atomic_control(atomic_native_control[p*256+:256]),.i_atomic_data_valid(atomic_native_data_valid[p*2+:2]),.i_atomic_data0(atomic_native_data0[p*256+:256]),.i_atomic_data1(atomic_native_data1[p*256+:256]),.o_atomic_source_captured(atomic_native_source_captured[p]),.o_atomic_data_accepted(atomic_native_data_accepted[p*2+:2]),
   .o_source_valid(port_source_valid[p*2+1]),.o_source_control(port_source_control[p*512+256+:256]),.i_source_captured(port_source_captured[p*2+1]),.o_data_valid(port_data_valid[p*4+2+:2]),.o_data0(port_data0[p*512+256+:256]),.o_data1(port_data1[p*512+256+:256]),.i_data_accepted(port_data_accepted[p*4+2+:2]),.o_busy(response_merge_busy[p]),.o_quiescent(response_merge_quiescent[p]),.o_error(response_merge_error[p]));
  tl_port #(.WIDTH(WIDTH),.HEADER_DEPTH(HEADER_DEPTH),.BANK_DEPTH(BANK_DEPTH),.RX_DEPTH(RX_DEPTH),.HEADER_COUNT_WIDTH(HEADER_COUNT_WIDTH),.DATA_COUNT_WIDTH(DATA_COUNT_WIDTH),.RX_COUNT_WIDTH(RX_COUNT_WIDTH),.PACKET_BOUNDARY_ENABLE(PACKET_BOUNDARY_ENABLE)) u_tl_port( // 实例化现有唯一TL端口owner。
   .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(i_enable&&effective_active_mask[p]),.i_link_reset(i_port_link_reset[p]), // inactive端口保持局部复位且无owner资格。
   .i_start(i_start[p]&&effective_active_mask[p]),.i_shared(i_shared[p]),.i_security_enable(1'b0),.i_compression_enable(1'b0), // 仅active端口允许明文credit初始化。
   .i_capacities(i_capacities[p*20*WIDTH+:20*WIDTH]), // 每个实例只读取自己的二十类容量。
   .i_source_valid(port_source_valid[p*2+:2]),.i_source_control(port_source_control[p*512+:512]),.i_source_tags_valid(2'd0),.i_source_tags(1024'd0), // 闭合模式按端口接入core source，RX兼容模式由dispatcher清零。
   .i_data_valid(port_data_valid[p*4+:4]),.i_data0(port_data0[p*512+:512]),.i_data1(port_data1[p*512+:512]), // data与source使用同一稳定端口归属。
   .o_source_ready(port_source_ready[p*2+:2]),.o_source_captured(port_source_captured[p*2+:2]),.o_header_taken(port_header_taken[p*2+:2]), // 捕获并保留每个唯一owner的真实source/header事件。
   .o_data_ready(port_data_ready[p*2+:2]),.o_data_accepted(port_data_accepted[p*4+:4]), // 捕获每个唯一owner的真实data接纳事件。
   .o_tx_valid(o_port_tx_valid[p]),.o_tx_flit(o_port_tx_flit[p*512+:512]),.o_tx_msg(o_port_tx_msg[p*2+:2]),.o_tx_packet_sop(o_port_tx_packet_sop[p]),.o_tx_packet_eop(o_port_tx_packet_eop[p]),.i_tx_ready(i_port_tx_ready[p]&&effective_active_mask[p]), // 每端口FC保持独立Station TX边界。
   .i_rx_valid(i_rx_valid[p]&&effective_active_mask[p]),.i_rx_flit(i_rx_flit[p*512+:512]),.i_rx_msg(i_rx_msg[p*2+:2]), // 仅active输入进入该link唯一接收owner。
   .o_rx_ready(o_rx_ready[p]),.o_rx_taken(o_rx_taken[p]), // 原样外露真实credit与storage联合接纳结果。
   .i_read_ready(atomic_input_ready[p]),.o_read_valid(raw_port_read_valid[p]),.o_read_flit(raw_port_read_flit[p*512+:512]), // 只有arbiter winner握手才能退休FIFO头。
   .o_read_msg(raw_port_read_msg[p*2+:2]),.o_read_classes(raw_port_read_classes[p*6+:6]),.o_read_releases(raw_port_read_releases[p*80+:80]), // 保持全部600-bit退休字段在同一端口。
   .o_start_ready(o_start_ready[p]),.o_start_taken(o_start_taken[p]),.o_local_done(o_local_done[p]),.o_peer_done(o_peer_done[p]),.o_peer_shared(o_peer_shared[p]), // 外露独立credit初始化状态。
   .o_capacity(o_capacity[p*20*(WIDTH+1)+:20*(WIDTH+1)]),.o_available(o_available[p*20*(WIDTH+1)+:20*(WIDTH+1)]),.o_pending(o_pending[p*20*(WIDTH+1)+:20*(WIDTH+1)]), // 外露独立账本而不聚合owner。
   .o_tx_validation_state(o_tx_validation_state[p*90+:90]),.o_idle(tl_port_idle[p]),.o_feature_error(unused_feature_error[p]),.o_error(o_port_error[p]),.o_implemented(unused_implemented[p]), // 外露每个owner的状态和错误。
   .i_valid(1'b0),.i_data(512'd0),.i_meta(128'd0),.o_ready(unused_legacy_ready[p]),.o_valid(unused_legacy_valid[p]),.o_data(unused_legacy_data[p*512+:512]),.o_meta(unused_legacy_meta[p*128+:128])); // 旧scaffold入口固定失败关闭且不参与事务路径。
  if(ATOMIC_ENABLE!=0)begin:gen_atomic_owner
   endpoint_atomic_tl_port_owner #(.C_TOKEN_WIDTH(ATOMIC_TOKEN_WIDTH),.C_PORT_ID(p)) u_atomic_owner(
    .i_clk(i_clk),.i_rstn(composer_rstn&&!i_port_link_reset[p]),.i_enable(effective_active_mask[p]),.i_request_admission_enable(i_remote_request_admission_enable),.i_profile_valid(i_atomic_profile_valid),.i_two_operand(i_atomic_two_operand),
    .i_tl_valid(raw_port_read_valid[p]),.o_tl_ready(atomic_input_ready[p]),.i_tl_flit(raw_port_read_flit[p*512+:512]),.i_tl_msg(raw_port_read_msg[p*2+:2]),.i_tl_classes(raw_port_read_classes[p*6+:6]),.i_tl_releases(raw_port_read_releases[p*80+:80]),
    .o_normal_valid(port_read_valid[p]),.i_normal_ready(arbiter_ready[p]),.o_normal_flit(port_read_flit[p*512+:512]),.o_normal_msg(port_read_msg[p*2+:2]),.o_normal_classes(port_read_classes[p*6+:6]),.o_normal_releases(port_read_releases[p*80+:80]),
    .o_backend_valid(o_atomic_backend_valid[p]),.i_backend_ready(i_atomic_backend_ready[p]),.o_backend_token(o_atomic_backend_token[p*ATOMIC_TOKEN_WIDTH+:ATOMIC_TOKEN_WIDTH]),.o_backend_header(o_atomic_backend_header[p*128+:128]),.o_backend_port(o_atomic_backend_port[p*2+:2]),.o_backend_operands(o_atomic_backend_operands[p*512+:512]),.o_backend_byte_enable(o_atomic_backend_byte_enable[p*256+:256]),.o_backend_atomic_return(o_atomic_backend_atomic_return[p]),.o_backend_op_type(o_atomic_backend_op_type[p*5+:5]),.o_backend_op_size(o_atomic_backend_op_size[p*2+:2]),
    .i_backend_result_valid(i_atomic_backend_result_valid[p]),.o_backend_result_ready(o_atomic_backend_result_ready[p]),.i_backend_result_token(i_atomic_backend_result_token[p*ATOMIC_TOKEN_WIDTH+:ATOMIC_TOKEN_WIDTH]),.i_backend_result_status(i_atomic_backend_result_status[p*4+:4]),.i_backend_result_data(i_atomic_backend_result_data[p*512+:512]),
    .o_response_valid(o_atomic_response_valid[p]),.i_response_ready((ATOMIC_TX_CLOSE_ENABLE!=0)?atomic_response_ready_internal[p]:i_atomic_response_ready[p]),.o_response_token(o_atomic_response_token[p*ATOMIC_TOKEN_WIDTH+:ATOMIC_TOKEN_WIDTH]),.o_response_atomic_return(o_atomic_response_atomic_return[p]),.o_response_port(o_atomic_response_port[p*2+:2]),.o_response_tag(o_atomic_response_tag[p*11+:11]),.o_response_src(o_atomic_response_src[p*10+:10]),.o_response_dst(o_atomic_response_dst[p*10+:10]),.o_response_vc(atomic_response_vc[p*2+:2]),.o_response_pool(atomic_response_pool[p]),.o_response_status(o_atomic_response_status[p*4+:4]),.o_response_data(o_atomic_response_data[p*512+:512]),.o_response_data_valid(o_atomic_response_data_valid[p]),.o_busy(atomic_busy[p]),.o_quiescent(atomic_quiescent[p]),.o_request_reject_pulse(atomic_request_reject_pulse[p]),.o_error(atomic_error[p]));
  end else begin:gen_no_atomic
   assign atomic_input_ready[p]=arbiter_ready[p];assign port_read_valid[p]=raw_port_read_valid[p];assign port_read_flit[p*512+:512]=raw_port_read_flit[p*512+:512];assign port_read_msg[p*2+:2]=raw_port_read_msg[p*2+:2];assign port_read_classes[p*6+:6]=raw_port_read_classes[p*6+:6];assign port_read_releases[p*80+:80]=raw_port_read_releases[p*80+:80];
   assign o_atomic_backend_valid[p]=1'b0;assign o_atomic_backend_token[p*ATOMIC_TOKEN_WIDTH+:ATOMIC_TOKEN_WIDTH]={ATOMIC_TOKEN_WIDTH{1'b0}};assign o_atomic_backend_header[p*128+:128]=128'd0;assign o_atomic_backend_port[p*2+:2]=2'd0;assign o_atomic_backend_operands[p*512+:512]=512'd0;assign o_atomic_backend_byte_enable[p*256+:256]=256'd0;assign o_atomic_backend_atomic_return[p]=1'b0;assign o_atomic_backend_op_type[p*5+:5]=5'd0;assign o_atomic_backend_op_size[p*2+:2]=2'd0;assign o_atomic_backend_result_ready[p]=1'b0;
   assign o_atomic_response_valid[p]=1'b0;assign o_atomic_response_token[p*ATOMIC_TOKEN_WIDTH+:ATOMIC_TOKEN_WIDTH]={ATOMIC_TOKEN_WIDTH{1'b0}};assign o_atomic_response_atomic_return[p]=1'b0;assign o_atomic_response_port[p*2+:2]=2'd0;assign o_atomic_response_tag[p*11+:11]=11'd0;assign o_atomic_response_src[p*10+:10]=10'd0;assign o_atomic_response_dst[p*10+:10]=10'd0;assign atomic_response_vc[p*2+:2]=2'd0;assign atomic_response_pool[p]=1'b0;assign o_atomic_response_status[p*4+:4]=4'd0;assign o_atomic_response_data[p*512+:512]=512'd0;assign o_atomic_response_data_valid[p]=1'b0;assign atomic_busy[p]=1'b0;assign atomic_quiescent[p]=1'b1;assign atomic_request_reject_pulse[p]=1'b0;assign atomic_error[p]=1'b0;
  end
  assign o_port_idle[p]=tl_port_idle[p]&&((ORDINARY_ORDERING_ENABLE==0)||o_order_quiescent[p])&&((ATOMIC_ENABLE==0)||atomic_quiescent[p])&&((ATOMIC_TX_CLOSE_ENABLE==0)||(atomic_native_quiescent[p]&&response_merge_quiescent[p]));
 end endgenerate // 结束四个固定本地端口owner生成。

 endpoint_station_tl_ingress_arbiter u_ingress_arbiter( // 复用现有锁定round-robin退休仲裁器。
  .i_clk(i_clk),.i_rstn(composer_rstn),.i_tl_valid(port_read_valid&effective_active_mask),.o_tl_ready(arbiter_ready), // inactive端口永远不能成为winner。
  .i_tl_flit(port_read_flit),.i_tl_msg(port_read_msg),.o_tl_valid(arbiter_valid),.i_tl_ready(core_read_ready), // flit和msg与core进行唯一握手。
  .o_tl_flit(arbiter_flit),.o_tl_msg(arbiter_msg),.o_tl_port(arbiter_port)); // winner端口与payload一同锁定。

 always @(*)begin // 使用arbiter锁定的同一winner同步选择classes和releases。
  selected_classes=6'd0; // 无有效winner时默认清零消费class。
  selected_releases=80'd0; // 无有效winner时默认清零credit释放向量。
  case(arbiter_port) // 端口选择与arbiter输出flit、msg使用同一身份。
   2'd0:begin selected_classes=port_read_classes[5:0];selected_releases=port_read_releases[79:0];end // 选择端口零完整metadata。
   2'd1:begin selected_classes=port_read_classes[11:6];selected_releases=port_read_releases[159:80];end // 选择端口一完整metadata。
   2'd2:begin selected_classes=port_read_classes[17:12];selected_releases=port_read_releases[239:160];end // 选择端口二完整metadata。
   default:begin selected_classes=port_read_classes[23:18];selected_releases=port_read_releases[319:240];end // 选择端口三完整metadata。
  endcase // 结束同winner metadata选择。
 end // 结束退休metadata组合mux。

 assign o_retired_valid=arbiter_valid; // 公开送入core的实际退休候选有效。
 assign o_retired_ready=core_read_ready; // 公开core返回的实际退休ready。
 assign o_retired_flit=arbiter_valid?arbiter_flit:512'd0; // 无候选时不泄露旧flit。
 assign o_retired_msg=arbiter_valid?arbiter_msg:2'd0; // 无候选时不泄露旧消息。
 assign o_retired_classes=arbiter_valid?selected_classes:6'd0; // classes只随有效完整记录公开。
 assign o_retired_releases=arbiter_valid?selected_releases:80'd0; // releases只随有效完整记录公开。
 assign o_retired_port=arbiter_valid?arbiter_port:2'd0; // port只随有效完整记录公开。
 endpoint_transaction_core #(.ORIGINATOR_CAPACITY(ORIGINATOR_CAPACITY),.COMPLETER_CAPACITY(COMPLETER_CAPACITY),.NUM_LOGICAL_PORTS(4),.WRITE_ENABLE((NORMAL_WRITE_ENABLE!=0)||(MESSAGE_ENABLE!=0)),.FULL_READ_ENABLE((FULL_READ_ENABLE!=0)||(MESSAGE_ENABLE!=0)),.NATIVE_ENABLE(MESSAGE_ENABLE),.MESSAGE_ENABLE(MESSAGE_ENABLE),.MESSAGE_TOKEN_WIDTH(MESSAGE_TOKEN_WIDTH),.MESSAGE_RUNTIME_ACTIVE_ENABLE(RUNTIME_ACTIVE_ENABLE),.ORDINARY_ORDERING_ENABLE(ORDINARY_ORDERING_ENABLE)) u_transaction_core( // 普通Read/Write和Message均复用同一退休记录与四端口owner。
  .i_clk(i_clk),.i_rstn(composer_rstn),.i_remote_request_admission_enable(i_remote_request_admission_enable),.i_message_active_mask(effective_active_mask),.i_message_link_reset(i_port_link_reset),.i_port(arbiter_port),.i_local_id(i_local_id), // 当前退休winner身份与完整记录同拍进入core。
  .i_request_valid(ordered_request_valid),.o_request_ready(core_request_ready),.i_request_port(ordered_request_port), // ordering启用时只允许取得唯一issue token的请求进入core。
  .i_request_order_epoch(ordered_request_epoch),.i_request_order_token(ordered_request_token),.o_complete_order_epoch(core_complete_order_epoch),.o_complete_order_token(core_complete_order_token),
  .i_request_tag(ordered_request_tag),.i_request_address(ordered_request_address),.i_request_dst(ordered_request_dst),.i_request_length(ordered_request_length),.i_request_attr(ordered_request_attr), // 保持captured完整请求字段。
  .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag), // 直通应用完成握手与身份。
  .o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid), // 直通应用完成结果。
  .o_mem_valid(o_mem_valid),.i_mem_ready(i_mem_ready),.o_mem_slot(o_mem_slot),.o_mem_address(o_mem_address),.o_mem_length(o_mem_length), // 直通目的端Read后端命令。
  .o_mem_attr(o_mem_attr),.o_mem_asi(o_mem_asi),.o_mem_metadata(o_mem_metadata), // 直通Read后端命令属性。
  .i_mem_result_valid(i_mem_result_valid),.o_mem_result_ready(o_mem_result_ready),.i_mem_result_slot(i_mem_result_slot), // 直通Read后端结果握手。
  .i_mem_result_data(i_mem_result_data),.i_mem_result_status(i_mem_result_status), // 直通Read后端结果内容。
  .o_source_valid(core_source_valid),.o_source_control(core_source_control),.o_source_port(core_source_port),.i_source_captured((TX_CLOSE_ENABLE!=0)?core_source_captured:i_source_captured), // 闭合模式使用同一组tl_port的真实source捕获，默认模式保留外部反馈。
  .i_request_header_taken(core_request_header_taken),.o_data_valid(core_data_valid),.o_data0(core_data0),.o_data1(core_data1),.i_data_accepted((TX_CLOSE_ENABLE!=0)?core_data_accepted:i_data_accepted), // Request退休和data接纳在闭合模式由实际所属owner返回。
  .i_read_valid(arbiter_valid),.o_read_ready(core_read_ready),.i_read_flit(arbiter_flit),.i_read_msg(arbiter_msg), // 锁定winner的payload原子送入core。
  .i_read_classes(selected_classes),.i_read_releases(selected_releases), // 与同一winner同步选择的credit metadata原子送入core。
  .o_outstanding_count(o_outstanding_count),.o_completer_count(o_completer_count),.o_error(o_core_error),.o_remote_request_reject_pulse(core_request_reject_pulse),.o_remote_request_reject_port(core_request_reject_port), // 外露core owner计数、拒绝事件和错误。
  .i_request_is_write((NORMAL_WRITE_ENABLE!=0)?ordered_request_is_write:1'b0),.i_request_full((NORMAL_WRITE_ENABLE!=0)?ordered_request_full:1'b0),.i_request_asi(((NORMAL_WRITE_ENABLE!=0)||(FULL_READ_ENABLE!=0))?ordered_request_asi:2'd0),.i_request_metadata(((NORMAL_WRITE_ENABLE!=0)||(FULL_READ_ENABLE!=0))?ordered_request_metadata:8'd0),.i_request_data((NORMAL_WRITE_ENABLE!=0)?ordered_request_data:2048'd0),.i_request_be((NORMAL_WRITE_ENABLE!=0)?ordered_request_be:256'd0), // 应用typed普通事务字段原样进入现有owner。
  .o_complete_is_write(o_complete_is_write),.o_write_mem_valid(o_write_mem_valid),.i_write_mem_ready(i_write_mem_ready),.o_write_mem_slot(o_write_mem_slot), // Write后端由原completer唯一拥有。
  .o_write_mem_address(o_write_mem_address),.o_write_mem_length(o_write_mem_length),.o_write_mem_attr(o_write_mem_attr),.o_write_mem_asi(o_write_mem_asi),.o_write_mem_metadata(o_write_mem_metadata), // Write命令字段保持至握手。
  .o_write_mem_data(o_write_mem_data),.o_write_mem_be(o_write_mem_be),.i_write_mem_result_valid(i_write_mem_result_valid),.o_write_mem_result_ready(o_write_mem_result_ready), // Write数据与结果只按真实握手推进。
  .i_write_mem_result_slot(i_write_mem_result_slot),.i_write_mem_result_status(i_write_mem_result_status),.o_write_completer_count(o_write_completer_count), // 结果slot沿用既有唯一owner。
  .i_mem_result_data_full(i_mem_result_data_full),.o_mem_be(o_mem_be),.o_complete_data_full(o_complete_data_full),.o_complete_mask(o_complete_mask), // Full Read结果与应用完成保持原mask。
  .i_ras_isolate(1'b0),.i_ras_link_down(1'b0),.i_ras_link_up(1'b0),.i_ras_init_done(1'b0),.i_ras_drop(1'b0), // 本里程碑不创建第二套RAS owner。
  .i_ras_recover_valid(1'b0),.i_ras_recover_epoch(8'd0),.i_rx_epoch_drained(1'b0),.i_tx_epoch_drained(1'b0),.i_owner_events_drained(1'b0),.i_tx_drain_epoch(8'd0), // 禁用可选epoch恢复输入。
  .o_tx_stop(unused_tx_stop),.o_tx_port(unused_tx_port),.o_tx_local_drained(unused_tx_local_drained),.o_ras_epoch(unused_ras_epoch),.o_ras_isolated(unused_ras_isolated), // 连接禁用RAS发送和epoch输出。
  .o_ras_recovered(unused_ras_recovered),.o_ras_recover_ready(unused_ras_recover_ready),.o_ras_blocked(unused_ras_blocked),.o_ras_ledger_count(unused_ras_ledger_count), // 连接禁用RAS恢复输出。
  .o_ras_dummy_done_fire(unused_ras_dummy_done_fire),.o_ras_dummy_done_slot(unused_ras_dummy_done_slot),.o_complete_cancel(unused_complete_cancel),.o_complete_is_dummy(unused_complete_is_dummy), // 连接禁用RAS dummy完成输出。
  .o_complete_slot(unused_complete_slot),.o_complete_epoch(unused_complete_epoch),.o_complete_generation(unused_complete_generation),.o_complete_beats(unused_complete_beats), // 连接默认完成的扩展身份输出。
  .o_ras_receiver_idle(unused_ras_receiver_idle),.o_ras_other_role_idle(unused_ras_other_role_idle), // 连接禁用RAS角色排空输出。
  .i_native_payload(184'd0),.i_native_vc(2'd0),.i_native_pool(1'b0),.i_native_tl_pool(1'b0),.i_native_poison(4'd0),.i_native_data_pools(4'd0), // 禁用可选native profile输入。
  .o_native_complete_payload(unused_native_complete_payload),.o_native_complete_vc(unused_native_complete_vc),.o_native_complete_pool(unused_native_complete_pool), // 连接禁用native完成基础输出。
  .o_native_complete_raw_data(unused_native_complete_raw_data),.o_native_complete_raw_headers(unused_native_complete_raw_headers), // 连接禁用native完成原始输出。
  .i_response_tl_pool(1'b0),.o_message_backend_valid(o_message_backend_valid),.i_message_backend_ready(i_message_backend_ready),.o_message_backend_token(o_message_backend_token), // 外露真实Message后端握手和typed token。
  .o_message_backend_header(o_message_backend_header),.o_message_backend_port(o_message_backend_port),.o_message_backend_data(o_message_backend_data),.o_message_backend_be(o_message_backend_be), // 保留已解码CMD42字段。
  .i_message_result_valid(i_message_result_valid),.o_message_result_ready(o_message_result_ready),.i_message_result_token(i_message_result_token), // backend result按token回到原端口owner。
  .i_message_result_is_read(i_message_result_is_read),.i_message_result_num_beats(i_message_result_num_beats),.i_message_result_status(i_message_result_status),.i_message_result_data(i_message_result_data),.i_message_result_poison(i_message_result_poison), // 不重新解释结果字段。
  .o_message_busy(o_message_busy),.o_message_reason(o_message_reason),.o_data_poison(unused_data_poison), // Message响应进入既有per-Port TX dispatcher。
  .i_native_message_response_is_read(1'b0),.i_native_message_response_num_beats(2'd0),.o_native_complete_is_message(unused_native_complete_is_message), // 禁用可选native Message响应。
  .o_native_complete_response_beats(unused_native_complete_response_beats),.o_native_complete_raw_poison(unused_native_complete_raw_poison)); // 连接禁用native Message响应扩展输出。

 assign core_request_reject_onehot=core_request_reject_pulse?(4'b0001<<core_request_reject_port):4'b0000;
 assign o_remote_request_reject_pulse=atomic_request_reject_pulse|core_request_reject_onehot; // Atomic在header处报告；普通/Message只在完整事务可安全丢弃时报告。
 assign unused_observation=(|port_source_ready)||(|port_data_ready)||(|unused_feature_error)||!(|unused_implemented)||(|unused_legacy_ready)||(|unused_legacy_valid)||(|unused_legacy_data)||(|unused_legacy_meta)||unused_tx_stop||unused_tx_local_drained||unused_ras_isolated||unused_ras_recovered||unused_ras_recover_ready||unused_ras_blocked||unused_ras_dummy_done_fire||(|unused_tx_port)||(|unused_ras_dummy_done_slot)||(|unused_complete_slot)||(|unused_ras_epoch)||(|unused_complete_epoch)||(|unused_complete_generation)||(|unused_ras_ledger_count)||(|unused_complete_beats)||unused_complete_cancel||unused_complete_is_dummy||unused_ras_receiver_idle||unused_ras_other_role_idle||(|unused_native_complete_payload)||(|unused_native_complete_vc)||unused_native_complete_pool||(|unused_native_complete_raw_data)||(|unused_native_complete_raw_headers)||(|unused_data_poison)||(|unused_native_complete_raw_poison)||unused_native_complete_is_message||(|unused_native_complete_response_beats); // 消费全部禁用profile观察以证明没有隐式第二owner。
 assign o_error=inactive_rx_error||inactive_start_error||inactive_request_error||unsupported_request_error||o_dispatch_error||(|o_port_error)||o_core_error||(|o_order_error)||(|atomic_error)||(|atomic_native_error)||(|response_merge_error)||(1'b0&&unused_observation)||(1'b0&&(|atomic_busy))||(1'b0&&!(|atomic_quiescent))||(1'b0&&(|atomic_native_busy))||(1'b0&&(|response_merge_busy))||(1'b0&&(|ordered_request_src))||(1'b0&&(|ordered_request_vc))||(1'b0&&(|unused_order_profile_error))||(1'b0&&(|unused_order_reset_error)); // 任一owner、路由或边界违规均失败关闭。
endmodule // 结束endpoint_station_transaction_rx_composer。
`default_nettype wire
