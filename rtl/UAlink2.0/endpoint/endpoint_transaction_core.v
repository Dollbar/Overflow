// 真实Read与可选普通Write事务总装；共享Tag身份和后端执行顺序。
`default_nettype none
module endpoint_transaction_core #(
 parameter integer ORIGINATOR_CAPACITY=4, // 应用Tag预约槽数，保持既有八位占用计数范围
 parameter integer COMPLETER_CAPACITY=4, // 两位公开内存slot接口可寻址一至四个执行槽
 parameter integer WRITE_ENABLE=0, // 默认保留原Read接口语义
 parameter integer FULL_READ_ENABLE=0 // 完整普通Read长度及逐Tag多Beat完成
)(
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
 output wire [2047:0] o_complete_data_full,output wire [255:0] o_complete_mask
);
localparam CONFIG_LEGAL=(ORIGINATOR_CAPACITY>=1)&&(ORIGINATOR_CAPACITY<=255)&&(COMPLETER_CAPACITY>=1)&&(COMPLETER_CAPACITY<=4); // 非法本地容量不允许接纳事务
localparam ORIGINATOR_CAPACITY_SAFE=CONFIG_LEGAL?ORIGINATOR_CAPACITY:1; // 非法参数也保持可展开的非空数组
localparam COMPLETER_CAPACITY_SAFE=CONFIG_LEGAL?COMPLETER_CAPACITY:1; // 非法组合由统一复位封锁安全实例
wire transaction_rstn=i_rstn&&CONFIG_LEGAL; // 局部配置错误持续清空事务所有权
wire request_valid,request_ready,response_valid,response_ready; // 接收器向两种事务所有者分别交付
wire [10:0] request_tag,response_tag;
wire [9:0] request_src,request_dst,response_dst;
wire [56:0] request_address;
wire [5:0] request_length;wire [7:0] request_attr,request_metadata;
wire [1:0] request_vc,request_asi,response_port,response_offset,response_num_beats;
wire request_pool,response_last,response_data_error;
wire request_is_write,request_full,response_is_write;
wire [2047:0] request_data;wire [255:0] request_be;
wire [511:0] originator_data;wire [1:0] originator_data_valid;
wire read_request_ready,write_request_ready,dispatch_allowed;
wire read_source_valid,write_source_valid,read_source_captured,write_source_captured;
wire [255:0] read_source_control,write_source_control;
wire write_completer_error;
wire [3:0] response_status;wire [511:0] response_data,completer_data;
wire [1:0] completer_data_valid;wire originator_error,receiver_error,completer_error;
// 源类别零保存请求Data/BE；类别一保存Read响应Data。
assign o_data_valid={completer_data_valid,originator_data_valid};
assign o_data0={completer_data[255:0],originator_data[255:0]};
assign o_data1={completer_data[511:256],originator_data[511:256]};
assign o_error=i_rstn&&(!CONFIG_LEGAL||originator_error||receiver_error||completer_error||write_completer_error||((FULL_READ_ENABLE!=0)&&(WRITE_ENABLE==0)&&i_request_valid&&i_request_is_write)); // 配置诊断不伪装正常满槽背压
generate if(WRITE_ENABLE!=0||FULL_READ_ENABLE!=0) begin:mixed_originator
 wire candidate_allowed=(WRITE_ENABLE!=0)||!i_request_is_write;wire formatter_ready;
 assign o_request_ready=candidate_allowed&&formatter_ready;
endpoint_request_formatter #(.CAPACITY(ORIGINATOR_CAPACITY_SAFE),.NUM_PORTS(1),.FULL_READ_ENABLE(FULL_READ_ENABLE)) u_originator(
 .i_clk(i_clk),.i_rstn(transaction_rstn),.i_local_id(i_local_id),
 .i_request_is_write(i_request_is_write),.i_request_full(i_request_full),.i_request_asi(i_request_asi),.i_request_metadata(i_request_metadata),
 .i_request_data(i_request_data),.i_request_be(i_request_be),
 .o_data_valid(originator_data_valid),.o_data(originator_data),.i_data_accepted(i_data_accepted[1:0]),
 .i_response_is_write(response_is_write),.o_complete_is_write(o_complete_is_write),.o_complete_data_full(o_complete_data_full),.o_complete_mask(o_complete_mask),
 .i_request_valid(i_request_valid&&candidate_allowed),.o_request_ready(formatter_ready),.i_request_port(i_request_port),
 .i_request_tag(i_request_tag),.i_request_address(i_request_address),.i_request_dst(i_request_dst),.i_request_length(i_request_length),.i_request_attr(i_request_attr),
 .o_source_valid(o_source_valid[0]),.o_source_control(o_source_control[255:0]),.i_source_captured(i_source_captured[0]),.i_header_taken(i_request_header_taken),
 .i_response_valid(response_valid),.o_response_ready(response_ready),.i_response_port(response_port),.i_response_tag(response_tag),.i_response_dst(response_dst),
 .i_response_status(response_status),.i_response_offset(response_offset),.i_response_last(response_last),.i_response_num_beats(response_num_beats),.i_response_data(response_data),.i_response_data_error(response_data_error),
 .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag),.o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid),
 .o_count(o_outstanding_count),.o_error(originator_error));
end else begin:read_originator
 assign o_complete_data_full={1536'd0,o_complete_data};assign o_complete_mask=o_complete_data_valid?{192'd0,64'hffffffffffffffff}:256'd0;
 assign originator_data=512'd0;assign originator_data_valid=2'd0;assign o_complete_is_write=1'b0;
endpoint_read_originator #(.CAPACITY(ORIGINATOR_CAPACITY_SAFE),.NUM_PORTS(1)) u_originator(
 .i_clk(i_clk),.i_rstn(transaction_rstn),.i_local_id(i_local_id),
 .i_request_valid(i_request_valid),.o_request_ready(o_request_ready),.i_request_port(i_request_port),
 .i_request_tag(i_request_tag),.i_request_address(i_request_address),.i_request_dst(i_request_dst),.i_request_length(i_request_length),.i_request_attr(i_request_attr),
 .o_source_valid(o_source_valid[0]),.o_source_control(o_source_control[255:0]),.i_source_captured(i_source_captured[0]),.i_header_taken(i_request_header_taken),
 .i_response_valid(response_valid),.o_response_ready(response_ready),.i_response_port(response_port),.i_response_tag(response_tag),.i_response_dst(response_dst),
 .i_response_status(response_status),.i_response_offset(response_offset),.i_response_last(response_last),.i_response_num_beats(response_num_beats),.i_response_data(response_data),.i_response_data_error(response_data_error),
 .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag),.o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid),
 .o_count(o_outstanding_count),.o_error(originator_error));
end endgenerate
endpoint_receive_transactions #(.WRITE_ENABLE(WRITE_ENABLE),.FULL_READ_ENABLE(FULL_READ_ENABLE)) u_receiver(
 .i_clk(i_clk),.i_rstn(transaction_rstn),.i_port(i_port),.i_read_valid(i_read_valid),.o_read_ready(o_read_ready),
 .i_read_flit(i_read_flit),.i_read_msg(i_read_msg),.i_read_classes(i_read_classes),.i_read_releases(i_read_releases),
 .o_request_valid(request_valid),.i_request_ready(request_ready),.o_request_tag(request_tag),.o_request_src(request_src),.o_request_dst(request_dst),
 .o_request_address(request_address),.o_request_length(request_length),.o_request_attr(request_attr),.o_request_vc(request_vc),.o_request_pool(request_pool),.o_request_asi(request_asi),.o_request_metadata(request_metadata),
 .o_response_valid(response_valid),.i_response_ready(response_ready),.o_response_port(response_port),.o_response_tag(response_tag),.o_response_dst(response_dst),
 .o_response_status(response_status),.o_response_offset(response_offset),.o_response_last(response_last),.o_response_num_beats(response_num_beats),.o_response_data(response_data),.o_response_data_error(response_data_error),.o_error(receiver_error),
 .o_request_is_write(request_is_write),.o_request_full(request_full),.o_request_data(request_data),.o_request_be(request_be),.o_response_is_write(response_is_write));
endpoint_read_completer #(.CAPACITY(COMPLETER_CAPACITY_SAFE),.SLOT_WIDTH(2),.FULL_READ_ENABLE(FULL_READ_ENABLE)) u_completer(
 .i_clk(i_clk),.i_rstn(transaction_rstn),.i_local_id(i_local_id),.i_request_valid(request_valid&&!request_is_write&&dispatch_allowed),.o_request_ready(read_request_ready),
 .i_request_tag(request_tag),.i_request_src(request_src),.i_request_dst(request_dst),.i_request_address(request_address),.i_request_length(request_length),.i_request_attr(request_attr),
 .i_request_vc(request_vc),.i_request_pool(request_pool),.i_request_asi(request_asi),.i_request_metadata(request_metadata),
 .o_mem_valid(o_mem_valid),.i_mem_ready(i_mem_ready),.o_mem_slot(o_mem_slot),.o_mem_address(o_mem_address),.o_mem_length(o_mem_length),.o_mem_attr(o_mem_attr),.o_mem_asi(o_mem_asi),.o_mem_metadata(o_mem_metadata),
 .i_mem_result_valid(i_mem_result_valid),.o_mem_result_ready(o_mem_result_ready),.i_mem_result_slot(i_mem_result_slot),.i_mem_result_data(i_mem_result_data),.i_mem_result_status(i_mem_result_status),.i_mem_result_data_full(i_mem_result_data_full),.o_mem_be(o_mem_be),
 .o_source_valid(read_source_valid),.o_source_control(read_source_control),.i_source_captured(read_source_captured),
 .o_data_valid(completer_data_valid),.o_data(completer_data),.i_data_accepted(i_data_accepted[3:2]),.o_count(o_completer_count),.o_error(completer_error));
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
 // 捕获前锁定响应Header所有者，避免另一种完成在反压期间替换字段。
 reg response_locked,response_write,prefer_write;
 wire choose_write=response_locked?response_write:(write_source_valid&&(!read_source_valid||prefer_write));
 assign o_source_valid[1]=choose_write?write_source_valid:read_source_valid;
 assign o_source_control[511:256]=choose_write?write_source_control:read_source_control;
 assign read_source_captured=i_source_captured[1]&&!choose_write;
 assign write_source_captured=i_source_captured[1]&&choose_write;
 always @(posedge i_clk) begin
  if(!transaction_rstn) begin response_locked<=1'b0;response_write<=1'b0;prefer_write<=1'b0;end
  else begin
   if(o_source_valid[1]&&!response_locked) begin response_locked<=1'b1;response_write<=choose_write;end
   if(o_source_valid[1]&&i_source_captured[1]) begin response_locked<=1'b0;prefer_write<=!choose_write;end
  end
 end
 endpoint_write_completer #(.CAPACITY(COMPLETER_CAPACITY_SAFE),.SLOT_WIDTH(2)) u_write_completer(
 .i_clk(i_clk),.i_rstn(transaction_rstn&&(WRITE_ENABLE!=0)),.i_local_id(i_local_id),
 .i_request_valid(request_valid&&request_is_write&&dispatch_allowed),.o_request_ready(write_request_ready),
 .i_request_tag(request_tag),.i_request_src(request_src),.i_request_dst(request_dst),.i_request_full(request_full),
 .i_request_address(request_address),.i_request_length(request_length),.i_request_attr(request_attr),.i_request_vc(request_vc),.i_request_pool(request_pool),
 .i_request_asi(request_asi),.i_request_metadata(request_metadata),.i_request_data(request_data),.i_request_be(request_be),
 .o_mem_valid(o_write_mem_valid),.i_mem_ready(i_write_mem_ready),.o_mem_slot(o_write_mem_slot),.o_mem_address(o_write_mem_address),
 .o_mem_length(o_write_mem_length),.o_mem_attr(o_write_mem_attr),.o_mem_asi(o_write_mem_asi),.o_mem_metadata(o_write_mem_metadata),
 .o_mem_data(o_write_mem_data),.o_mem_be(o_write_mem_be),
 .i_mem_result_valid(i_write_mem_result_valid),.o_mem_result_ready(o_write_mem_result_ready),.i_mem_result_slot(i_write_mem_result_slot),.i_mem_result_status(i_write_mem_result_status),
 .o_source_valid(write_source_valid),.o_source_control(write_source_control),.i_source_captured(write_source_captured),.o_error(write_completer_error),.o_count(o_write_completer_count));
end else begin:read_completer
 assign dispatch_allowed=1'b1;assign write_request_ready=1'b0;assign write_completer_error=1'b0;
 assign o_source_valid[1]=read_source_valid;assign o_source_control[511:256]=read_source_control;
 assign read_source_captured=i_source_captured[1];assign write_source_captured=1'b0;
 assign write_source_valid=1'b0;assign write_source_control=256'd0;
 assign o_write_mem_valid=1'b0;assign o_write_mem_slot=2'd0;assign o_write_mem_address=57'd0;
 assign o_write_mem_length=6'd0;assign o_write_mem_attr=8'd0;assign o_write_mem_asi=2'd0;assign o_write_mem_metadata=8'd0;
 assign o_write_mem_data=2048'd0;assign o_write_mem_be=256'd0;assign o_write_mem_result_ready=1'b0;assign o_write_completer_count=8'd0;
end endgenerate
endmodule
`default_nettype wire
