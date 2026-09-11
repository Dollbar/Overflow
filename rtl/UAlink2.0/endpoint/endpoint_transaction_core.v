// 真实single64B Read事务总装；请求、内存执行、响应与Tag完成由独立模块持有所有权。
`default_nettype none
module endpoint_transaction_core(
 input wire i_clk,i_rstn, // 全部局部状态使用同一同步低有效复位
 input wire [1:0] i_port, // 当前集成固定物理端口零
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
 output wire [1:0] o_source_valid,output wire [511:0] o_source_control,
 input wire [1:0] i_source_captured,input wire i_request_header_taken, // capture与实际发送确认严格分离
 output wire [3:0] o_data_valid,output wire [511:0] o_data0,o_data1,
 input wire [3:0] i_data_accepted, // 每类别实际入队半Flit数量，允许只接纳一个
 input wire i_read_valid,output wire o_read_ready,input wire [511:0] i_read_flit,
 input wire [1:0] i_read_msg,input wire [5:0] i_read_classes,input wire [79:0] i_read_releases,
 output wire [7:0] o_outstanding_count,o_completer_count,output wire o_error
);
wire request_valid,request_ready,response_valid,response_ready; // 接收器向两种事务所有者分别交付
wire [10:0] request_tag,response_tag;
wire [9:0] request_src,request_dst,response_dst;
wire [56:0] request_address;
wire [5:0] request_length;wire [7:0] request_attr,request_metadata;
wire [1:0] request_vc,request_asi,response_port,response_offset,response_num_beats;
wire request_pool,response_last,response_data_error;
wire [3:0] response_status;wire [511:0] response_data,completer_data;
wire [1:0] completer_data_valid;wire originator_error,receiver_error,completer_error;
// 源类别零只发送无OrigData的Read；类别一保存完整有序响应数据。
assign o_data_valid={completer_data_valid,2'd0};
assign o_data0={completer_data[255:0],256'd0};
assign o_data1={completer_data[511:256],256'd0};
assign o_error=originator_error||receiver_error||completer_error;
endpoint_read_originator #(.CAPACITY(4),.NUM_PORTS(1)) u_originator(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_local_id(i_local_id),
 .i_request_valid(i_request_valid),.o_request_ready(o_request_ready),.i_request_port(i_request_port),
 .i_request_tag(i_request_tag),.i_request_address(i_request_address),.i_request_dst(i_request_dst),.i_request_length(i_request_length),.i_request_attr(i_request_attr),
 .o_source_valid(o_source_valid[0]),.o_source_control(o_source_control[255:0]),.i_source_captured(i_source_captured[0]),.i_header_taken(i_request_header_taken),
 .i_response_valid(response_valid),.o_response_ready(response_ready),.i_response_port(response_port),.i_response_tag(response_tag),.i_response_dst(response_dst),
 .i_response_status(response_status),.i_response_offset(response_offset),.i_response_last(response_last),.i_response_num_beats(response_num_beats),.i_response_data(response_data),.i_response_data_error(response_data_error),
 .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag),.o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid),
 .o_count(o_outstanding_count),.o_error(originator_error));
endpoint_receive_transactions u_receiver(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_port(i_port),.i_read_valid(i_read_valid),.o_read_ready(o_read_ready),
 .i_read_flit(i_read_flit),.i_read_msg(i_read_msg),.i_read_classes(i_read_classes),.i_read_releases(i_read_releases),
 .o_request_valid(request_valid),.i_request_ready(request_ready),.o_request_tag(request_tag),.o_request_src(request_src),.o_request_dst(request_dst),
 .o_request_address(request_address),.o_request_length(request_length),.o_request_attr(request_attr),.o_request_vc(request_vc),.o_request_pool(request_pool),.o_request_asi(request_asi),.o_request_metadata(request_metadata),
 .o_response_valid(response_valid),.i_response_ready(response_ready),.o_response_port(response_port),.o_response_tag(response_tag),.o_response_dst(response_dst),
 .o_response_status(response_status),.o_response_offset(response_offset),.o_response_last(response_last),.o_response_num_beats(response_num_beats),.o_response_data(response_data),.o_response_data_error(response_data_error),.o_error(receiver_error));
endpoint_read_completer #(.CAPACITY(4),.SLOT_WIDTH(2)) u_completer(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_local_id(i_local_id),.i_request_valid(request_valid),.o_request_ready(request_ready),
 .i_request_tag(request_tag),.i_request_src(request_src),.i_request_dst(request_dst),.i_request_address(request_address),.i_request_length(request_length),.i_request_attr(request_attr),
 .i_request_vc(request_vc),.i_request_pool(request_pool),.i_request_asi(request_asi),.i_request_metadata(request_metadata),
 .o_mem_valid(o_mem_valid),.i_mem_ready(i_mem_ready),.o_mem_slot(o_mem_slot),.o_mem_address(o_mem_address),.o_mem_length(o_mem_length),.o_mem_attr(o_mem_attr),.o_mem_asi(o_mem_asi),.o_mem_metadata(o_mem_metadata),
 .i_mem_result_valid(i_mem_result_valid),.o_mem_result_ready(o_mem_result_ready),.i_mem_result_slot(i_mem_result_slot),.i_mem_result_data(i_mem_result_data),.i_mem_result_status(i_mem_result_status),
 .o_source_valid(o_source_valid[1]),.o_source_control(o_source_control[511:256]),.i_source_captured(i_source_captured[1]),
 .o_data_valid(completer_data_valid),.o_data(completer_data),.i_data_accepted(i_data_accepted[3:2]),.o_count(o_completer_count),.o_error(completer_error));
endmodule
`default_nettype wire
