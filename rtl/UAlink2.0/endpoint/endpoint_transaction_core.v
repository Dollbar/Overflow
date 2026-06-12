// 真实Read与可选普通Write事务总装；共享Tag身份和后端执行顺序。
`default_nettype none
module endpoint_transaction_core #(
 parameter integer ORIGINATOR_CAPACITY=4, // 应用Tag预约槽数，保持既有八位占用计数范围
 parameter integer COMPLETER_CAPACITY=4, // 两位公开内存slot接口可寻址一至四个执行槽
 parameter integer WRITE_ENABLE=0, // 默认保留原Read接口语义
 parameter integer FULL_READ_ENABLE=0, // 完整普通Read长度及逐Tag多Beat完成
 parameter integer RAS_ENABLE=0,EPOCH_WIDTH=8,GENERATION_WIDTH=8,NATIVE_ENABLE=0,
 parameter integer MESSAGE_ENABLE=0,MESSAGE_TOKEN_WIDTH=16 // 默认保持原容量与接口。
,parameter integer NATIVE_MESSAGE_ENABLE=0 // 原Tag保存显式Message响应义务，默认关闭。
,parameter integer NUM_LOGICAL_PORTS=1,parameter integer MESSAGE_RUNTIME_ACTIVE_ENABLE=0 // Station分叉后可见的一、二或四个独立逻辑端口。
,parameter integer ORDINARY_ORDERING_ENABLE=0,parameter integer ORDER_TOKEN_WIDTH=16,parameter integer ORDER_EPOCH_WIDTH=8
)(
 input wire i_clk,i_rstn,input wire i_remote_request_admission_enable, // drain只关闭新远端事务；Response和已绑定Data继续。
 input wire[3:0] i_message_active_mask,input wire[3:0] i_message_link_reset, // managed Station逐端口Message资格和局部reset。
 input wire [1:0] i_port, // 当前接收事务所属的一、二或四端口逻辑身份。
 input wire [9:0] i_local_id, // 复位时期配置并在运行期间稳定
 input wire i_request_valid,output wire o_request_ready, // 应用请求预约握手
 input wire [1:0] i_request_port,input wire [10:0] i_request_tag,
 input wire [56:0] i_request_address,input wire [9:0] i_request_dst,
 input wire [5:0] i_request_length,input wire [7:0] i_request_attr,
 output wire o_complete_valid,input wire i_complete_ready, // 完成只在完整结果到达后公开
 output wire [1:0] o_complete_port,output wire [10:0] o_complete_tag,
 output wire [3:0] o_complete_status,output wire [511:0] o_complete_data,
 output wire o_complete_data_valid, // 错误完成不得提交成功数据
 output wire o_mem_valid,input wire i_mem_ready,output wire [1:0] o_mem_slot,
 output wire [56:0] o_mem_address,output wire [5:0] o_mem_length,
 output wire [7:0] o_mem_attr,output wire [1:0] o_mem_asi,output wire [7:0] o_mem_metadata,
 input wire i_mem_result_valid,output wire o_mem_result_ready,input wire [1:0] i_mem_result_slot,
 input wire [511:0] i_mem_result_data,input wire [3:0] i_mem_result_status,
 output wire [1:0] o_source_valid,output wire [511:0] o_source_control,output wire [3:0] o_source_port,
 input wire [1:0] i_source_captured,input wire i_request_header_taken, // capture与实际发送确认严格分离
 output wire [3:0] o_data_valid,output wire [511:0] o_data0,o_data1,
 input wire [3:0] i_data_accepted, // 每类别实际入队半Flit数量，允许只接纳一个
 input wire i_read_valid,output wire o_read_ready,input wire [511:0] i_read_flit,
 input wire [1:0] i_read_msg,input wire [5:0] i_read_classes,input wire [79:0] i_read_releases,
 output wire [7:0] o_outstanding_count,o_completer_count,output wire o_error,
 input wire i_request_is_write,i_request_full,
 input wire [1:0] i_request_asi,input wire [7:0] i_request_metadata,
 input wire [2047:0] i_request_data,input wire [255:0] i_request_be,
 output wire o_complete_is_write,
 output wire o_write_mem_valid,input wire i_write_mem_ready,output wire [1:0] o_write_mem_slot,
 output wire [56:0] o_write_mem_address,output wire [5:0] o_write_mem_length,
 output wire [7:0] o_write_mem_attr,output wire [1:0] o_write_mem_asi,output wire [7:0] o_write_mem_metadata,
 output wire [2047:0] o_write_mem_data,output wire [255:0] o_write_mem_be,
 input wire i_write_mem_result_valid,output wire o_write_mem_result_ready,input wire [1:0] i_write_mem_result_slot,
 input wire [3:0] i_write_mem_result_status,output wire [7:0] o_write_completer_count,
 input wire [2047:0] i_mem_result_data_full,output wire [255:0] o_mem_be,
 output wire [2047:0] o_complete_data_full,output wire [255:0] o_complete_mask,
 input wire i_ras_isolate,i_ras_link_down,i_ras_link_up,i_ras_init_done,i_ras_drop, // 单物理端口真实管理事件。
 input wire i_ras_recover_valid,input wire [EPOCH_WIDTH-1:0] i_ras_recover_epoch, // 新epoch只能由实际所有者推进。
 input wire i_rx_epoch_drained,i_tx_epoch_drained,i_owner_events_drained,input wire [EPOCH_WIDTH-1:0] i_tx_drain_epoch, // 明确外部责任资格。
 output wire o_tx_stop,output wire [1:0] o_tx_port,output wire o_tx_local_drained, // 原formatter保存的真实发送所有权。
 output wire [EPOCH_WIDTH-1:0] o_ras_epoch,output wire o_ras_isolated,o_ras_recovered,o_ras_recover_ready,o_ras_blocked, // 原账本状态。
 output wire [7:0] o_ras_ledger_count,output wire o_ras_dummy_done_fire,output wire [1:0] o_ras_dummy_done_slot, // 联合done观察。
 output wire o_complete_cancel,o_complete_is_dummy,output wire [1:0] o_complete_slot, // 应用cancel与ready同沿时cancel优先。
 output wire [EPOCH_WIDTH-1:0] o_complete_epoch,output wire [GENERATION_WIDTH-1:0] o_complete_generation,output wire [2:0] o_complete_beats, // 全部原始身份。
 output wire o_ras_receiver_idle,o_ras_other_role_idle, // 实际接收与Completer责任观察，不是全链恢复证明。
 input wire [183:0] i_native_payload,
 input wire [1:0] i_native_vc,input wire i_native_pool,i_native_tl_pool,
 input wire [3:0] i_native_poison,i_native_data_pools,
 input wire i_response_tl_pool,
 output wire [183:0] o_native_complete_payload,
 output wire [1:0] o_native_complete_vc,output wire o_native_complete_pool,
 output wire [2047:0] o_native_complete_raw_data,
 output wire [255:0] o_native_complete_raw_headers,
 // Explicit vendor service boundary; disabled-mode outputs are deterministic zero.
 output wire o_message_backend_valid,input wire i_message_backend_ready,
 output wire [MESSAGE_TOKEN_WIDTH-1:0] o_message_backend_token,
 output wire [127:0] o_message_backend_header,output wire [1:0] o_message_backend_port,
 output wire [2047:0] o_message_backend_data,output wire [255:0] o_message_backend_be,
 input wire i_message_result_valid,output wire o_message_result_ready,
 input wire [MESSAGE_TOKEN_WIDTH-1:0] i_message_result_token,
 input wire i_message_result_is_read,input wire [1:0] i_message_result_num_beats,
 input wire [3:0] i_message_result_status,input wire [2047:0] i_message_result_data,
 input wire [3:0] i_message_result_poison,
 output wire o_message_busy,output wire [7:0] o_message_reason,
 output wire o_remote_request_reject_pulse,output wire [1:0] o_remote_request_reject_port, // drain期完整丢弃一笔新远端请求时的非致命RAS事件。
 output wire [3:0] o_data_poison

,input wire i_native_message_response_is_read,input wire [1:0] i_native_message_response_num_beats
,output wire o_native_complete_is_message,output wire [2:0] o_native_complete_response_beats,output wire [3:0] o_native_complete_raw_poison
,input wire[ORDER_EPOCH_WIDTH-1:0] i_request_order_epoch,input wire[ORDER_TOKEN_WIDTH-1:0] i_request_order_token,output wire[ORDER_EPOCH_WIDTH-1:0] o_complete_order_epoch,output wire[ORDER_TOKEN_WIDTH-1:0] o_complete_order_token
);
localparam PORT_CONFIG_LEGAL=(NUM_LOGICAL_PORTS==1)||(NUM_LOGICAL_PORTS==2)||(NUM_LOGICAL_PORTS==4); // 冻结profile只允许x4、2x2和4x1对应的端口数。
localparam CONFIG_LEGAL=PORT_CONFIG_LEGAL&&(ORIGINATOR_CAPACITY>=1)&&(ORIGINATOR_CAPACITY<=255)&&(COMPLETER_CAPACITY>=1)&&(COMPLETER_CAPACITY<=4)&&((RAS_ENABLE==0)||((RAS_ENABLE==1)&&(ORIGINATOR_CAPACITY<=4)&&(NUM_LOGICAL_PORTS==1))); // Message由per-Port typed owner保存回源身份；RAS仍保持既有单Port限制。
localparam ORIGINATOR_CAPACITY_SAFE=CONFIG_LEGAL?ORIGINATOR_CAPACITY:1; // 非法参数也保持可展开的非空数组
localparam COMPLETER_CAPACITY_SAFE=CONFIG_LEGAL?COMPLETER_CAPACITY:1; // 非法组合由统一复位封锁安全实例
wire message_source_valid,message_source_captured,message_path_busy;
wire [255:0] message_control;wire [511:0] message_data;wire [1:0] message_source_port;
wire [1:0] message_mask,message_accept,message_poison;
wire [511:0] read_data;wire [1:0] read_count,read_accept;
wire response_arbiter_error;
wire [1:0] response_vc;wire [63:0] response_header;
wire transaction_rstn=i_rstn&&CONFIG_LEGAL; // 局部配置错误持续清空事务所有权
wire request_valid,request_ready,response_valid,response_ready; // 接收器向两种事务所有者分别交付
wire [10:0] request_tag,response_tag;
wire [9:0] request_src,request_dst,response_dst;
wire [56:0] request_address;
wire [5:0] request_length;wire [7:0] request_attr,request_metadata;
wire [1:0] request_vc,request_asi,response_port,response_offset,response_num_beats;
wire request_pool,response_last,response_data_error;wire [1:0] request_ingress_port;
wire request_is_write,request_full,response_is_write;
wire [2047:0] request_data;wire [255:0] request_be;
wire [511:0] originator_data;wire [1:0] originator_data_valid;
wire read_request_ready,write_request_ready,dispatch_allowed,dispatch_idle;
wire read_source_valid,write_source_valid,read_source_captured,write_source_captured;wire [1:0] read_source_port,write_source_port;
wire [255:0] read_source_control,write_source_control;
wire unused_response_class_busy,response_class_quiescent;wire[1:0] unused_response_class_owner;
wire write_completer_error;
wire receiver_request_reject_pulse;wire[1:0] receiver_request_reject_port;
wire [3:0] response_status;wire [511:0] response_data,completer_data;
wire [1:0] completer_data_valid;wire originator_error,receiver_error,completer_error;
// 源类别零保存请求Data/BE；类别一保存Read响应Data。
assign o_data_valid={completer_data_valid,originator_data_valid};
assign o_data0={completer_data[255:0],originator_data[255:0]};
assign o_data1={completer_data[511:256],originator_data[511:256]};
assign o_error=i_rstn&&(!CONFIG_LEGAL||originator_error||receiver_error||completer_error||write_completer_error||response_arbiter_error||(((FULL_READ_ENABLE!=0)||(RAS_ENABLE!=0))&&(WRITE_ENABLE==0)&&i_request_valid&&i_request_is_write)); // 配置诊断不伪装正常满槽背压
generate if(WRITE_ENABLE!=0||FULL_READ_ENABLE!=0||RAS_ENABLE!=0) begin:mixed_originator
 wire candidate_allowed=(WRITE_ENABLE!=0)||!i_request_is_write;wire formatter_ready;
 wire ras_port_in_range=({30'd0,i_port}<NUM_LOGICAL_PORTS); // 单次管理事件必须绑定当前合法逻辑端口。
 wire [NUM_LOGICAL_PORTS-1:0] ras_port_onehot=ras_port_in_range?({{(NUM_LOGICAL_PORTS-1){1'b0}},1'b1}<<i_port):{NUM_LOGICAL_PORTS{1'b0}}; // 非法端口不触碰任何账本。
 wire [NUM_LOGICAL_PORTS-1:0] ras_isolate_by_port={NUM_LOGICAL_PORTS{i_ras_isolate}}&ras_port_onehot; // 标量管理ABI转换为参数化端口事件。
 wire [NUM_LOGICAL_PORTS-1:0] ras_link_down_by_port={NUM_LOGICAL_PORTS{i_ras_link_down}}&ras_port_onehot;
 wire [NUM_LOGICAL_PORTS-1:0] ras_link_up_by_port={NUM_LOGICAL_PORTS{i_ras_link_up}}&ras_port_onehot;
 wire [NUM_LOGICAL_PORTS-1:0] ras_init_done_by_port={NUM_LOGICAL_PORTS{i_ras_init_done}}&ras_port_onehot;
 wire [NUM_LOGICAL_PORTS-1:0] ras_drop_by_port={NUM_LOGICAL_PORTS{i_ras_drop}}&ras_port_onehot;
 wire [NUM_LOGICAL_PORTS-1:0] tx_stop_by_port,ras_isolated_by_port; // 旧标量输出保守归并全部端口状态。
 assign o_request_ready=candidate_allowed&&formatter_ready;
 assign o_tx_stop=|tx_stop_by_port;assign o_ras_isolated=|ras_isolated_by_port;
endpoint_request_formatter #(.MESSAGE_ENABLE(NATIVE_MESSAGE_ENABLE),.CAPACITY(ORIGINATOR_CAPACITY_SAFE),.NUM_PORTS(NUM_LOGICAL_PORTS),.FULL_READ_ENABLE(FULL_READ_ENABLE),.RAS_ENABLE(RAS_ENABLE),.EPOCH_WIDTH(EPOCH_WIDTH),.GENERATION_WIDTH(GENERATION_WIDTH),.NATIVE_REQUEST_ENABLE(NATIVE_ENABLE),.NATIVE_RAW_ENABLE(NATIVE_ENABLE),.ORDERING_ENABLE(ORDINARY_ORDERING_ENABLE),.ORDER_TOKEN_WIDTH(ORDER_TOKEN_WIDTH),.ORDER_EPOCH_WIDTH(ORDER_EPOCH_WIDTH)) u_originator(
 .i_native_message_response_is_read(i_native_message_response_is_read),.i_native_message_response_num_beats(i_native_message_response_num_beats),.o_native_complete_is_message(o_native_complete_is_message),.o_native_complete_response_beats(o_native_complete_response_beats),.o_native_complete_raw_poison(o_native_complete_raw_poison),
 .i_native_payload(i_native_payload),.i_native_vc(i_native_vc),.i_native_pool(i_native_pool),.i_native_tl_pool(i_native_tl_pool),.i_native_poison(i_native_poison),.i_native_data_pools(i_native_data_pools),
 .o_native_complete_payload(o_native_complete_payload),.o_native_complete_vc(o_native_complete_vc),.o_native_complete_pool(o_native_complete_pool),.i_response_vc(response_vc),.i_response_header(response_header),.o_native_complete_raw_data(o_native_complete_raw_data),.o_native_complete_raw_headers(o_native_complete_raw_headers),
 .i_clk(i_clk),.i_rstn(transaction_rstn),.i_local_id(i_local_id),
 .i_request_is_write(i_request_is_write),.i_request_full(i_request_full),.i_request_asi(i_request_asi),.i_request_metadata(i_request_metadata),
 .i_request_order_epoch(i_request_order_epoch),.i_request_order_token(i_request_order_token),.o_complete_order_epoch(o_complete_order_epoch),.o_complete_order_token(o_complete_order_token),.i_order_port_reset(i_message_link_reset),
 .i_request_data(i_request_data),.i_request_be(i_request_be),
 .o_data_valid(originator_data_valid),.o_data(originator_data),.i_data_accepted(i_data_accepted[1:0]),
 .i_response_is_write(response_is_write),.o_complete_is_write(o_complete_is_write),.o_complete_data_full(o_complete_data_full),.o_complete_mask(o_complete_mask),
 .i_request_valid(i_request_valid&&candidate_allowed),.o_request_ready(formatter_ready),.i_request_port(i_request_port),
 .i_request_tag(i_request_tag),.i_request_address(i_request_address),.i_request_dst(i_request_dst),.i_request_length(i_request_length),.i_request_attr(i_request_attr),
 .o_source_valid(o_source_valid[0]),.o_source_control(o_source_control[255:0]),.i_source_captured(i_source_captured[0]),.i_header_taken(i_request_header_taken),
 .i_response_valid(response_valid),.o_response_ready(response_ready),.i_response_port(response_port),.i_response_tag(response_tag),.i_response_dst(response_dst),
 .i_response_status(response_status),.i_response_offset(response_offset),.i_response_last(response_last),.i_response_num_beats(response_num_beats),.i_response_data(response_data),.i_response_data_error(response_data_error),
 .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag),.o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid),
 .i_ras_isolate(ras_isolate_by_port),.i_ras_link_down(ras_link_down_by_port),.i_ras_link_up(ras_link_up_by_port),.i_ras_init_done(ras_init_done_by_port),.i_ras_drop(ras_drop_by_port), // 管理事件按当前逻辑端口独热转换。
 .i_ras_recover_valid(i_ras_recover_valid),.i_ras_recover_epoch(i_ras_recover_epoch),.i_rx_epoch_drained(i_rx_epoch_drained&&o_ras_receiver_idle),.i_tx_epoch_drained(i_tx_epoch_drained),.i_tx_drain_epoch(i_tx_drain_epoch),.i_owner_events_drained(i_owner_events_drained), // 不以ready代替接收排空。
 .o_tx_stop(tx_stop_by_port),.o_tx_port(o_tx_port),.o_tx_local_drained(o_tx_local_drained),.o_ras_epoch(o_ras_epoch),.o_ras_isolated(ras_isolated_by_port),.o_ras_recovered(o_ras_recovered),.o_ras_recover_ready(o_ras_recover_ready),.o_ras_blocked(o_ras_blocked), // 端口化状态再保守归并至旧ABI。
 .o_ras_ledger_count(o_ras_ledger_count),.o_ras_dummy_done_fire(o_ras_dummy_done_fire),.o_ras_dummy_done_slot(o_ras_dummy_done_slot), // 不构造镜像计数。
 .o_complete_cancel(o_complete_cancel),.o_complete_is_dummy(o_complete_is_dummy),.o_complete_slot(o_complete_slot),.o_complete_epoch(o_complete_epoch),.o_complete_generation(o_complete_generation),.o_complete_beats(o_complete_beats), // 明确保留取消ABI。
 .o_count(o_outstanding_count),.o_error(originator_error));
 assign o_source_port[1:0]=o_tx_port; // formatter保持应用请求端口至全部Control/Data所有权转移。
end else begin:read_originator
 assign o_complete_order_epoch={ORDER_EPOCH_WIDTH{1'b0}};assign o_complete_order_token={ORDER_TOKEN_WIDTH{1'b0}};
 assign o_native_complete_is_message=1'b0;assign o_native_complete_response_beats=3'd0;assign o_native_complete_raw_poison=4'd0;
 assign o_native_complete_payload=184'd0;assign o_native_complete_vc=2'd0;assign o_native_complete_pool=1'b0;assign o_native_complete_raw_data=2048'd0;assign o_native_complete_raw_headers=256'd0;

 assign o_tx_stop=1'b0;assign o_tx_local_drained=1'b0; // 旧无RAS发起器不提供该排空观察，不能用source_valid冒充。
 assign o_ras_epoch={EPOCH_WIDTH{1'b0}};assign o_ras_isolated=1'b0;assign o_ras_recovered=1'b0;assign o_ras_recover_ready=1'b0;assign o_ras_blocked=1'b0; // 默认无管理owner。
 assign o_ras_ledger_count=8'd0;assign o_ras_dummy_done_fire=1'b0;assign o_ras_dummy_done_slot=2'd0; // 不创建额外账本。
 assign o_complete_cancel=1'b0;assign o_complete_is_dummy=1'b0;assign o_complete_slot=2'd0;assign o_complete_epoch={EPOCH_WIDTH{1'b0}};assign o_complete_generation={GENERATION_WIDTH{1'b0}};assign o_complete_beats=3'd0; // 默认消费者保持旧语义。
 assign o_complete_data_full={1536'd0,o_complete_data};assign o_complete_mask=o_complete_data_valid?{192'd0,64'hffffffffffffffff}:256'd0;
 assign originator_data=512'd0;assign originator_data_valid=2'd0;assign o_complete_is_write=1'b0;
endpoint_read_originator #(.CAPACITY(ORIGINATOR_CAPACITY_SAFE),.NUM_PORTS(NUM_LOGICAL_PORTS)) u_originator(
 .i_clk(i_clk),.i_rstn(transaction_rstn),.i_local_id(i_local_id),
 .i_request_valid(i_request_valid),.o_request_ready(o_request_ready),.i_request_port(i_request_port),
 .i_request_tag(i_request_tag),.i_request_address(i_request_address),.i_request_dst(i_request_dst),.i_request_length(i_request_length),.i_request_attr(i_request_attr),
 .o_source_valid(o_source_valid[0]),.o_source_control(o_source_control[255:0]),.o_source_port(o_tx_port),.i_source_captured(i_source_captured[0]),.i_header_taken(i_request_header_taken),
 .i_response_valid(response_valid),.o_response_ready(response_ready),.i_response_port(response_port),.i_response_tag(response_tag),.i_response_dst(response_dst),
 .i_response_status(response_status),.i_response_offset(response_offset),.i_response_last(response_last),.i_response_num_beats(response_num_beats),.i_response_data(response_data),.i_response_data_error(response_data_error),
 .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag),.o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid),
 .o_count(o_outstanding_count),.o_error(originator_error));
 assign o_source_port[1:0]=o_tx_port; // legacy Read也保持实际应用端口至Header发送。
end endgenerate
generate if(MESSAGE_ENABLE==0)begin:legacy_receive
assign o_message_backend_valid=1'b0;assign o_message_backend_token={MESSAGE_TOKEN_WIDTH{1'b0}};
assign o_message_backend_header=128'd0;assign o_message_backend_port=2'd0;assign o_message_backend_data=2048'd0;assign o_message_backend_be=256'd0;
assign o_message_result_ready=1'b0;assign o_message_busy=1'b0;assign o_message_reason=8'd0;
assign message_source_valid=1'b0;assign message_control=256'd0;assign message_data=512'd0;assign message_mask=2'd0;assign message_poison=2'd0;assign message_source_port=2'd0;assign message_path_busy=1'b0;
endpoint_receive_transactions #(.WRITE_ENABLE(WRITE_ENABLE),.FULL_READ_ENABLE(FULL_READ_ENABLE),.NATIVE_FIELDS_ENABLE(NATIVE_ENABLE)) u_receiver(
 .o_response_vc(response_vc),.o_response_header(response_header),
 .i_clk(i_clk),.i_rstn(transaction_rstn),.i_request_admission_enable(i_remote_request_admission_enable),.i_port(i_port),.i_read_valid(i_read_valid),.o_read_ready(o_read_ready),
 .i_read_flit(i_read_flit),.i_read_msg(i_read_msg),.i_read_classes(i_read_classes),.i_read_releases(i_read_releases),
 .o_request_valid(request_valid),.i_request_ready(request_ready),.o_request_tag(request_tag),.o_request_src(request_src),.o_request_dst(request_dst),
 .o_request_port(request_ingress_port),
 .o_request_address(request_address),.o_request_length(request_length),.o_request_attr(request_attr),.o_request_vc(request_vc),.o_request_pool(request_pool),.o_request_asi(request_asi),.o_request_metadata(request_metadata),
 .o_response_valid(response_valid),.i_response_ready(response_ready),.o_response_port(response_port),.o_response_tag(response_tag),.o_response_dst(response_dst),
 .o_response_status(response_status),.o_response_offset(response_offset),.o_response_last(response_last),.o_response_num_beats(response_num_beats),.o_response_data(response_data),.o_response_data_error(response_data_error),.o_error(receiver_error),.o_idle(o_ras_receiver_idle),
 .o_request_is_write(request_is_write),.o_request_full(request_full),.o_request_data(request_data),.o_request_be(request_be),.o_response_is_write(response_is_write),.o_request_reject_pulse(receiver_request_reject_pulse),.o_request_reject_port(receiver_request_reject_port));
end else begin:message_receive
wire [127:0] normal_header;wire [1:0] normal_port;
wire unused_normal_port=^{normal_port,normal_header[127:124],normal_header[4:0]};
assign request_tag=normal_header[113:103];assign request_src=normal_header[24:15];assign request_dst=normal_header[14:5];
assign request_ingress_port=normal_port;
assign request_address={normal_header[79:25],2'b00};assign request_length=normal_header[93:88];assign request_attr=normal_header[101:94];
assign request_vc=normal_header[117:116];assign request_pool=normal_header[102];assign request_asi=normal_header[115:114];assign request_metadata=normal_header[87:80];
assign request_is_write=normal_header[123:118]==6'h28||normal_header[123:118]==6'h29;assign request_full=normal_header[123:118]==6'h29;
assign response_tag=response_header[57:47];assign response_dst=response_header[25:16];assign response_status=response_header[41:38];
assign response_vc=response_header[59:58];assign response_num_beats=response_header[45:44];assign response_is_write=!response_header[37];
assign o_ras_receiver_idle=transaction_rstn&&!message_path_busy;assign o_message_busy=message_path_busy;
endpoint_message_receive_path #(.MESSAGE_RESPONSE_ENABLE(NATIVE_MESSAGE_ENABLE),.PORTS(NUM_LOGICAL_PORTS),.TOKEN_WIDTH(MESSAGE_TOKEN_WIDTH),.MESSAGE_ENABLE(1),.MESSAGE_RUNTIME_ACTIVE_ENABLE(MESSAGE_RUNTIME_ACTIVE_ENABLE)) u_receiver(
 .i_clk(i_clk),.i_rstn(transaction_rstn),.i_request_admission_enable(i_remote_request_admission_enable),.i_message_active_mask(i_message_active_mask[NUM_LOGICAL_PORTS-1:0]),.i_message_link_reset(i_message_link_reset[NUM_LOGICAL_PORTS-1:0]),.i_local_id(i_local_id),.i_port(i_port),.i_read_valid(i_read_valid),.o_read_ready(o_read_ready),
 .i_read_flit(i_read_flit),.i_read_msg(i_read_msg),.i_read_classes(i_read_classes),.i_read_releases(i_read_releases),
 .o_normal_valid(request_valid),.i_normal_ready(request_ready),.o_normal_header(normal_header),.o_normal_port(normal_port),.o_normal_data(request_data),.o_normal_be(request_be),
 .o_response_valid(response_valid),.i_response_ready(response_ready),.o_response_header(response_header),.o_response_port(response_port),.o_response_data(response_data),.o_response_data_error(response_data_error),
 .o_response_offset(response_offset),.o_response_last(response_last),
 .o_backend_valid(o_message_backend_valid),.i_backend_ready(i_message_backend_ready),.o_backend_token(o_message_backend_token),
 .o_backend_header(o_message_backend_header),.o_backend_port(o_message_backend_port),.o_backend_data(o_message_backend_data),.o_backend_be(o_message_backend_be),
 .i_result_valid(i_message_result_valid),.o_result_ready(o_message_result_ready),.i_result_token(i_message_result_token),
 .i_result_is_read(i_message_result_is_read),.i_result_num_beats(i_message_result_num_beats),.i_result_status(i_message_result_status),.i_result_data(i_message_result_data),.i_result_poison(i_message_result_poison),
 .i_response_pool(i_response_tl_pool),.o_source_valid(message_source_valid),.o_source_control(message_control),.o_source_port(message_source_port),.i_source_captured(message_source_captured),
 .o_data_valid(message_mask),.o_data(message_data),.o_data_poison(message_poison),.i_data_accepted(message_accept),
 .o_busy(message_path_busy),.o_error(receiver_error),.o_reason(o_message_reason),.o_request_reject_pulse(receiver_request_reject_pulse),.o_request_reject_port(receiver_request_reject_port));
end endgenerate
assign o_remote_request_reject_pulse=receiver_request_reject_pulse;
assign o_remote_request_reject_port=receiver_request_reject_pulse?receiver_request_reject_port:2'd0;
endpoint_read_completer #(.CAPACITY(COMPLETER_CAPACITY_SAFE),.SLOT_WIDTH(2),.FULL_READ_ENABLE(FULL_READ_ENABLE),.NATIVE_FIELDS_ENABLE(NATIVE_ENABLE)) u_completer(
 .i_response_tl_pool(i_response_tl_pool),
 .i_clk(i_clk),.i_rstn(transaction_rstn),.i_local_id(i_local_id),.i_request_valid(request_valid&&!request_is_write&&dispatch_allowed),.o_request_ready(read_request_ready),.i_request_port(request_ingress_port),
 .i_request_tag(request_tag),.i_request_src(request_src),.i_request_dst(request_dst),.i_request_address(request_address),.i_request_length(request_length),.i_request_attr(request_attr),
 .i_request_vc(request_vc),.i_request_pool(request_pool),.i_request_asi(request_asi),.i_request_metadata(request_metadata),
 .o_mem_valid(o_mem_valid),.i_mem_ready(i_mem_ready),.o_mem_slot(o_mem_slot),.o_mem_address(o_mem_address),.o_mem_length(o_mem_length),.o_mem_attr(o_mem_attr),.o_mem_asi(o_mem_asi),.o_mem_metadata(o_mem_metadata),
 .i_mem_result_valid(i_mem_result_valid),.o_mem_result_ready(o_mem_result_ready),.i_mem_result_slot(i_mem_result_slot),.i_mem_result_data(i_mem_result_data),.i_mem_result_status(i_mem_result_status),.i_mem_result_data_full(i_mem_result_data_full),.o_mem_be(o_mem_be),
 .o_source_valid(read_source_valid),.o_source_control(read_source_control),.o_source_port(read_source_port),.i_source_captured(read_source_captured),
 .o_data_valid(read_count),.o_data(read_data),.i_data_accepted(read_accept),.o_count(o_completer_count),.o_error(completer_error));
assign o_ras_other_role_idle=transaction_rstn&&dispatch_idle&&!message_path_busy&&response_class_quiescent&&(o_completer_count==0)&&(o_write_completer_count==0)&&!request_valid&&!o_source_valid[1]&&(completer_data_valid==0); // 真实后端及响应holding均已转交，仍须检查下游。
assign request_ready=dispatch_allowed&&(request_is_write?write_request_ready:read_request_ready);
generate if(WRITE_ENABLE!=0||FULL_READ_ENABLE!=0) begin:mixed_completer
 // 共享调度只等待真实后端结果；应用反压不阻止下一笔内存操作。
 reg dispatch_busy,dispatch_write,dispatch_issued;
 reg [1:0] dispatch_slot;
 wire dispatch_result=dispatch_issued&&(dispatch_write?
  (i_write_mem_result_valid&&o_write_mem_result_ready&&(i_write_mem_result_slot==dispatch_slot)&&
   ((i_write_mem_result_status==4'd0)||(i_write_mem_result_status==4'd2)||(i_write_mem_result_status==4'd3)||(i_write_mem_result_status==4'd6)||(i_write_mem_result_status==4'd8))):
  (i_mem_result_valid&&o_mem_result_ready&&(i_mem_result_slot==dispatch_slot)&&((i_mem_result_status==4'd0)||(i_mem_result_status==4'd3)||((FULL_READ_ENABLE!=0)&&((i_mem_result_status==4'd2)||(i_mem_result_status==4'd6)||(i_mem_result_status==4'd8))))));
 assign dispatch_allowed=!dispatch_busy;
 assign dispatch_idle=!dispatch_busy; // issued只在busy内有效，实际后端责任由busy寄存器保持。
 always @(posedge i_clk) begin
  if(!transaction_rstn) begin dispatch_busy<=1'b0;dispatch_write<=1'b0;dispatch_issued<=1'b0;dispatch_slot<=2'd0;end
  else begin
   if(request_valid&&request_ready) begin dispatch_busy<=1'b1;dispatch_write<=request_is_write;dispatch_issued<=1'b0;end
   if(dispatch_busy&&!dispatch_issued) begin
    if(dispatch_write&&o_write_mem_valid&&i_write_mem_ready) begin dispatch_issued<=1'b1;dispatch_slot<=o_write_mem_slot;end
    if(!dispatch_write&&o_mem_valid&&i_mem_ready) begin dispatch_issued<=1'b1;dispatch_slot<=o_mem_slot;end
   end
   if(dispatch_busy&&dispatch_result) begin dispatch_busy<=1'b0;dispatch_issued<=1'b0;end
  end
 end
 if(MESSAGE_ENABLE==0)begin:legacy_response
 // 捕获前锁定响应Header所有者，避免另一种完成在反压期间替换字段。
 reg response_locked,response_write,prefer_write,response_header_q;
 wire choose_write=response_locked?response_write:(write_source_valid&&(!read_source_valid||prefer_write));
 assign o_source_valid[1]=choose_write?write_source_valid:read_source_valid;
 assign o_source_control[511:256]=choose_write?write_source_control:read_source_control;
 assign read_source_captured=i_source_captured[1]&&!choose_write;
 assign write_source_captured=i_source_captured[1]&&choose_write;
 assign o_source_port[3:2]=choose_write?write_source_port:read_source_port;
 wire response_capture=o_source_valid[1]&&i_source_captured[1];
 wire response_done=choose_write?response_capture:((response_header_q||response_capture)&&((read_count==0)||(i_data_accepted[3:2]==read_count)));
 always @(posedge i_clk) begin
  if(!transaction_rstn) begin response_locked<=1'b0;response_write<=1'b0;prefer_write<=1'b0;response_header_q<=1'b0;end
  else begin
   if(o_source_valid[1]&&!response_locked) begin response_locked<=1'b1;response_write<=choose_write;end
   if(response_capture)response_header_q<=1'b1;
   if(response_done) begin response_locked<=1'b0;response_header_q<=1'b0;prefer_write<=!choose_write;end
  end
 end
 end
 endpoint_write_completer #(.CAPACITY(COMPLETER_CAPACITY_SAFE),.SLOT_WIDTH(2),.NATIVE_FIELDS_ENABLE(NATIVE_ENABLE)) u_write_completer(
 .i_response_tl_pool(i_response_tl_pool),
 .i_clk(i_clk),.i_rstn(transaction_rstn&&(WRITE_ENABLE!=0)),.i_local_id(i_local_id),.i_request_port(request_ingress_port),
 .i_request_valid(request_valid&&request_is_write&&dispatch_allowed),.o_request_ready(write_request_ready),
 .i_request_tag(request_tag),.i_request_src(request_src),.i_request_dst(request_dst),.i_request_full(request_full),
 .i_request_address(request_address),.i_request_length(request_length),.i_request_attr(request_attr),.i_request_vc(request_vc),.i_request_pool(request_pool),
 .i_request_asi(request_asi),.i_request_metadata(request_metadata),.i_request_data(request_data),.i_request_be(request_be),
 .o_mem_valid(o_write_mem_valid),.i_mem_ready(i_write_mem_ready),.o_mem_slot(o_write_mem_slot),.o_mem_address(o_write_mem_address),
 .o_mem_length(o_write_mem_length),.o_mem_attr(o_write_mem_attr),.o_mem_asi(o_write_mem_asi),.o_mem_metadata(o_write_mem_metadata),
 .o_mem_data(o_write_mem_data),.o_mem_be(o_write_mem_be),
 .i_mem_result_valid(i_write_mem_result_valid),.o_mem_result_ready(o_write_mem_result_ready),.i_mem_result_slot(i_write_mem_result_slot),.i_mem_result_status(i_write_mem_result_status),
 .o_source_valid(write_source_valid),.o_source_control(write_source_control),.o_source_port(write_source_port),.i_source_captured(write_source_captured),.o_error(write_completer_error),.o_count(o_write_completer_count));
end else begin:read_completer
 assign dispatch_idle=1'b1; // 旧Read路径没有共享dispatch寄存器，执行责任由实际completer计数保持。
 assign dispatch_allowed=1'b1;assign write_request_ready=1'b0;assign write_completer_error=1'b0;
 assign o_source_valid[1]=read_source_valid;assign o_source_control[511:256]=read_source_control;
 assign o_source_port[3:2]=read_source_port;
 assign read_source_captured=i_source_captured[1];assign write_source_captured=1'b0;
 assign write_source_valid=1'b0;assign write_source_control=256'd0;
 assign o_write_mem_valid=1'b0;assign o_write_mem_slot=2'd0;assign o_write_mem_address=57'd0;
 assign o_write_mem_length=6'd0;assign o_write_mem_attr=8'd0;assign o_write_mem_asi=2'd0;assign o_write_mem_metadata=8'd0;
 assign o_write_mem_data=2048'd0;assign o_write_mem_be=256'd0;assign o_write_mem_result_ready=1'b0;assign o_write_completer_count=8'd0;
end endgenerate
generate if(MESSAGE_ENABLE==0)begin:legacy_data
 assign completer_data_valid=read_count;assign completer_data=read_data;assign read_accept=i_data_accepted[3:2];
 assign message_accept=2'd0;assign message_source_captured=1'b0;assign o_data_poison=4'd0;assign response_arbiter_error=1'b0;
 assign unused_response_class_busy=1'b0;assign response_class_quiescent=1'b1;assign unused_response_class_owner=2'd0;
end else begin:message_response
 wire [1:0] message_count={1'b0,message_mask[0]}+{1'b0,message_mask[1]};
 wire [511:0] shifted_message=message_mask==2'b10 ?{256'd0,message_data[511:256]}:message_data;
 wire[2:0] class_source_captured;wire[5:0] class_data_accepted;wire[1:0] class_data_count,class_data_poison;wire[511:0] class_data;
 endpoint_tl_response_class_arbiter u_response_class_arbiter(
  .i_clk(i_clk),.i_rstn(transaction_rstn),.i_enable(1'b1),.i_valid({message_source_valid,write_source_valid,read_source_valid}),
  .i_control({message_control,write_source_control,read_source_control}),.i_port({message_source_port,write_source_port,read_source_port}),
  .i_data_count({message_count,2'd0,read_count}),.i_data({shifted_message,512'd0,read_data}),.i_data_poison({(message_mask==2'b10 ? {1'b0,message_poison[1]} : message_poison),4'd0}),
  .o_source_captured(class_source_captured),.o_data_accepted(class_data_accepted),.o_valid(o_source_valid[1]),.o_control(o_source_control[511:256]),.o_port(o_source_port[3:2]),
  .o_data_count(class_data_count),.o_data(class_data),.o_data_poison(class_data_poison),.i_source_captured(i_source_captured[1]),.i_data_accepted(i_data_accepted[3:2]),
  .o_owner_class(unused_response_class_owner),.o_busy(unused_response_class_busy),.o_quiescent(response_class_quiescent),.o_error(response_arbiter_error));
 assign completer_data_valid=class_data_count;assign completer_data=class_data;assign o_data_poison={class_data_poison,2'd0};
 assign read_source_captured=class_source_captured[0];assign write_source_captured=class_source_captured[1];assign message_source_captured=class_source_captured[2];
 assign read_accept=class_data_accepted[1:0];
 assign message_accept=(class_data_accepted[5:4]==2)?message_mask:(class_data_accepted[5:4]==1)?(message_mask[0]?2'b01:2'b10):2'd0;
end endgenerate
generate if((MESSAGE_ENABLE!=0)&&((MESSAGE_ENABLE!=1)||(NATIVE_ENABLE!=1)||(WRITE_ENABLE!=1)||(FULL_READ_ENABLE!=1)||(RAS_ENABLE!=0)||(MESSAGE_TOKEN_WIDTH<3)||(MESSAGE_TOKEN_WIDTH>32)))begin:invalid_message_config
 message_core_requires_native_mixed_without_ras Invalid_Config();
end endgenerate
generate if((NATIVE_ENABLE!=0)&&((NATIVE_ENABLE!=1)||(WRITE_ENABLE!=1)||(FULL_READ_ENABLE!=1)||(RAS_ENABLE!=0)))begin:invalid_native_config
 native_core_requires_mixed_full_read_without_ras Invalid_Config();
end endgenerate
generate if(NATIVE_MESSAGE_ENABLE!=0&&((NATIVE_MESSAGE_ENABLE!=1)||(MESSAGE_ENABLE!=1)||(NATIVE_ENABLE!=1)||(WRITE_ENABLE!=1)||(FULL_READ_ENABLE!=1)||(RAS_ENABLE!=0)))begin:invalid_native_message_config
 endpoint_native_message_requires_complete_owners u_bad();
end endgenerate
endmodule
`default_nettype wire
