`timescale 1ns/1ps
`default_nettype none
// Single retired-record parser and mutually exclusive normal/message dispatch.
module endpoint_message_receive_path #(parameter PORTS=1,parameter TOKEN_WIDTH=16,parameter MESSAGE_ENABLE=0,parameter MESSAGE_RESPONSE_ENABLE=0,parameter MESSAGE_RUNTIME_ACTIVE_ENABLE=0)(
 input wire i_clk,i_rstn,input wire i_request_admission_enable,input wire[PORTS-1:0] i_message_active_mask,input wire[PORTS-1:0] i_message_link_reset,input wire [9:0] i_local_id,
 input wire [1:0] i_port,input wire i_read_valid,output wire o_read_ready,
 input wire [511:0] i_read_flit,input wire [1:0] i_read_msg,input wire [5:0] i_read_classes,input wire [79:0] i_read_releases,
 output wire o_normal_valid,input wire i_normal_ready,output wire [127:0] o_normal_header,
 output wire [1:0] o_normal_port,output wire [2047:0] o_normal_data,output wire [255:0] o_normal_be,
 output wire o_response_valid,input wire i_response_ready,output wire [63:0] o_response_header,
 output wire [511:0] o_response_data,output wire [1:0] o_response_port,output wire o_response_data_error,
 output wire o_backend_valid,input wire i_backend_ready,output wire [TOKEN_WIDTH-1:0] o_backend_token,
 output wire [127:0] o_backend_header,output wire [1:0] o_backend_port,output wire [2047:0] o_backend_data,output wire [255:0] o_backend_be,
 input wire i_result_valid,output wire o_result_ready,input wire [TOKEN_WIDTH-1:0] i_result_token,
 input wire i_result_is_read,input wire [1:0] i_result_num_beats,input wire [3:0] i_result_status,
 input wire [2047:0] i_result_data,input wire [3:0] i_result_poison,input wire i_response_pool,
 output wire o_source_valid,output wire [255:0] o_source_control,output wire [1:0] o_source_port,input wire i_source_captured,
 output wire [1:0] o_data_valid,output wire [511:0] o_data,output wire [1:0] o_data_poison,input wire [1:0] i_data_accepted,
 output wire o_busy,output wire o_error,output wire [7:0] o_reason,
 output wire [1:0] o_response_offset,output wire o_response_last,output wire o_request_reject_pulse,output wire[1:0] o_request_reject_port
);
wire request_valid,request_ready,receive_ready,receive_error,receive_idle,handler_error,handler_busy,handler_ready;
wire [127:0] request_header;wire [1:0] request_port;wire [2047:0] request_data;wire [255:0] request_be;
wire message_request=(MESSAGE_ENABLE!=0)&&request_header[123:118]==6'h2a;
assign request_ready=!handler_error&&(message_request?handler_ready:i_normal_ready);
assign o_normal_valid=request_valid&&!message_request&&!handler_error;
assign o_normal_header=o_normal_valid?request_header:128'd0;assign o_normal_port=o_normal_valid?request_port:2'd0;
assign o_normal_data=o_normal_valid?request_data:2048'd0;assign o_normal_be=o_normal_valid?request_be:256'd0;
assign o_read_ready=receive_ready&&!handler_error;
assign o_error=receive_error||handler_error;assign o_busy=i_rstn&&(!receive_idle||handler_busy);
wire [116:0] unused_request_fields;
wire [43:0] unused_response_fields;
assign o_response_offset=unused_response_fields[26:25];assign o_response_last=unused_response_fields[27];
endpoint_receive_transactions #(.WRITE_ENABLE(1),.FULL_READ_ENABLE(1),.NATIVE_FIELDS_ENABLE(1),.MESSAGE_ENABLE(MESSAGE_ENABLE),.MESSAGE_RESPONSE_ENABLE(MESSAGE_RESPONSE_ENABLE)) u_receiver(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_request_admission_enable(i_request_admission_enable),.i_port(i_port),.i_read_valid(i_read_valid&&!handler_error),.o_read_ready(receive_ready),
 .i_read_flit(i_read_flit),.i_read_msg(i_read_msg),.i_read_classes(i_read_classes),.i_read_releases(i_read_releases),
 .o_request_valid(request_valid),.i_request_ready(request_ready),.o_request_header(request_header),.o_request_port(request_port),.o_request_data(request_data),.o_request_be(request_be),
 .o_request_reject_pulse(o_request_reject_pulse),.o_request_reject_port(o_request_reject_port),
 .o_request_tag(unused_request_fields[10:0]),.o_request_src(unused_request_fields[20:11]),.o_request_dst(unused_request_fields[30:21]),
 .o_request_address(unused_request_fields[87:31]),.o_request_length(unused_request_fields[93:88]),.o_request_attr(unused_request_fields[101:94]),
 .o_request_vc(unused_request_fields[103:102]),.o_request_pool(unused_request_fields[104]),.o_request_asi(unused_request_fields[106:105]),
 .o_request_metadata(unused_request_fields[114:107]),.o_request_is_write(unused_request_fields[115]),.o_request_full(unused_request_fields[116]),
 .o_response_valid(o_response_valid),.i_response_ready(i_response_ready),.o_response_header(o_response_header),.o_response_port(o_response_port),.o_response_data(o_response_data),.o_response_data_error(o_response_data_error),
 .o_response_tag(unused_response_fields[10:0]),.o_response_dst(unused_response_fields[20:11]),.o_response_status(unused_response_fields[24:21]),
 .o_response_offset(unused_response_fields[26:25]),.o_response_last(unused_response_fields[27]),.o_response_num_beats(unused_response_fields[29:28]),
 .o_response_is_write(unused_response_fields[30]),.o_response_src(unused_response_fields[40:31]),.o_response_vc(unused_response_fields[42:41]),.o_response_pool(unused_response_fields[43]),
 .o_error(receive_error),.o_idle(receive_idle));
endpoint_message_multiport_owner #(.C_PORTS(PORTS),.C_TOKEN_WIDTH(TOKEN_WIDTH),.C_ACTIVE_PORT_MASK((PORTS==1)?4'b0001:(PORTS==2)?4'b0011:4'b1111),.C_RUNTIME_ACTIVE_ENABLE(MESSAGE_RUNTIME_ACTIVE_ENABLE)) u_handler(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_active_port_mask({{(4-PORTS){1'b0}},i_message_active_mask}),.i_link_reset((MESSAGE_RUNTIME_ACTIVE_ENABLE!=0)?i_message_link_reset:{PORTS{1'b0}}),.i_local_id(i_local_id),.i_request_valid(request_valid&&message_request&&!receive_error),.o_request_ready(handler_ready),
 .i_request_header(request_header),.i_request_port(request_port),.i_request_data(request_data),.i_request_be(request_be),
 .o_backend_valid(o_backend_valid),
 .i_backend_ready(i_backend_ready),
 .o_backend_token(o_backend_token),
 .o_backend_header(o_backend_header),
 .o_backend_port(o_backend_port),
 .o_backend_data(o_backend_data),
 .o_backend_be(o_backend_be),
 .i_result_valid(i_result_valid),
 .o_result_ready(o_result_ready),
 .i_result_token(i_result_token),
 .i_result_is_read(i_result_is_read),
 .i_result_num_beats(i_result_num_beats),
 .i_result_status(i_result_status),
 .i_result_data(i_result_data),
 .i_result_poison(i_result_poison),
 .i_response_pool(i_response_pool),
 .o_source_valid(o_source_valid),
 .o_source_control(o_source_control),
 .o_source_port(o_source_port),
 .i_source_captured(i_source_captured),
 .o_data_valid(o_data_valid),
 .o_data(o_data),
 .o_data_poison(o_data_poison),
 .i_data_accepted(i_data_accepted),
 .o_busy(handler_busy),
 .o_error(handler_error),
 .o_reason(o_reason));
endmodule
`default_nettype wire
