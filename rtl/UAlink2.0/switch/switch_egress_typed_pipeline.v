`timescale 1ps/1ps // 原队列预约与物理出口调度直接连接，不新增资源所有者。
module switch_egress_typed_pipeline #( // switch_egress_pipeline模块：出口、请求响应及VC独立资源缓存。
 parameter integer PORTS=4,VCS=4,TOKEN_WIDTH=8,UNIT_WIDTH=4, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 parameter [UNIT_WIDTH-1:0] DEFAULT_CAPACITY=4, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 parameter [2*VCS*PORTS*UNIT_WIDTH-1:0] CAPACITIES={2*VCS*PORTS{DEFAULT_CAPACITY}}, // 逐类别、VC、出口容量保持原有slot顺序。
 parameter integer RSP_BURST_MAX=2 // 调度响应连续包上限直接传给唯一物理出口scheduler。
)( // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire i_clk,i_rstn, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS-1:0] i_header_valid, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS*PORTS-1:0] i_route_match, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS*UNIT_WIDTH-1:0] i_header_units, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS*TOKEN_WIDTH-1:0] i_header_token, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS*2-1:0] i_header_vc, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS-1:0] i_header_response, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [PORTS-1:0] o_header_ready, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS-1:0] i_body_valid, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS*544-1:0] i_body_data, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS-1:0] i_body_last, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS*TOKEN_WIDTH-1:0] i_body_token, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [PORTS-1:0] o_body_ready, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS-1:0] i_ready, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [PORTS-1:0] o_valid,o_last, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [PORTS*544-1:0] o_data, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [PORTS*TOKEN_WIDTH-1:0] o_token, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [2*VCS*PORTS-1:0] o_release_valid, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [2*VCS*PORTS*UNIT_WIDTH-1:0] o_release_units, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [2*VCS*PORTS*UNIT_WIDTH-1:0] o_available,o_reserved,o_queue_reserved,o_stored,o_completed, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [PORTS-1:0] o_source_busy,o_source_error_sticky, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [PORTS-1:0] o_header_error,o_body_error, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [2*VCS*PORTS-1:0] o_queue_error_now,o_queue_error_sticky, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [2*VCS-1:0] o_reservation_error, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [PORTS*2-1:0] o_vc, // 实际物理输出包所属VC。
 output wire [PORTS-1:0] o_response,o_owned, // 实际类别与独立物理出口包锁。
 output wire [2*VCS*PORTS-1:0] o_selected, // 保留原slot排列的唯一选择观察。
 output wire [PORTS*24-1:0] o_local_dl_header, // 保存的原始本地header，不重建DL包。
 output wire [PORTS*6-1:0] o_record_aux, // 原始六位辅助字段完整保存。
 output wire [PORTS*2-1:0] o_tl_msg, // 原始TL flit两位消息标签。
 output wire [PORTS*512-1:0] o_tl_flit, // 完整已打包flit，不伪造prepared源字段。
 output wire [PORTS-1:0] o_repack_input_error, // 已有repack非法VC输入诊断。
 output wire o_error // 原队列预约与物理出口调度直接连接，不新增资源所有者。
); // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 wire [PORTS-1:0] pipeline_valid,pipeline_last,pipeline_response,pipeline_ready; // 真正的queue到repack交接事件。
 wire [PORTS*544-1:0] pipeline_data; // 保留全部544位，不重排位序。
 wire [PORTS*TOKEN_WIDTH-1:0] pipeline_token; // 已预约包身份随同数据进入repack。
 wire [PORTS*2-1:0] pipeline_vc; // 唯一scheduler保存的实际VC。
 wire pipeline_error; // 原队列资源诊断独立保留。
 assign o_error=pipeline_error || (|o_repack_input_error); // 聚合现有真实诊断，不产生新的Drop状态。
 switch_egress_pipeline #(.PORTS(PORTS),.VCS(VCS),.DATA_WIDTH(544),.TOKEN_WIDTH(TOKEN_WIDTH),.UNIT_WIDTH(UNIT_WIDTH),.DEFAULT_CAPACITY(DEFAULT_CAPACITY),.CAPACITIES(CAPACITIES),.RSP_BURST_MAX(RSP_BURST_MAX)) u_pipeline( // 唯一容量预约及释放owner。
 .i_clk(i_clk), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_rstn(i_rstn), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_header_valid(i_header_valid), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_route_match(i_route_match), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_header_units(i_header_units), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_header_token(i_header_token), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_header_vc(i_header_vc), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_header_response(i_header_response), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_header_ready(o_header_ready), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_body_valid(i_body_valid), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_body_data(i_body_data), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_body_last(i_body_last), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_body_token(i_body_token), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_body_ready(o_body_ready), // 原pipeline接口直接连接；容量事件不在新层生成。
 .i_ready(pipeline_ready), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_valid(pipeline_valid), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_last(pipeline_last), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_data(pipeline_data), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_token(pipeline_token), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_release_valid(o_release_valid), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_release_units(o_release_units), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_available(o_available), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_reserved(o_reserved), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_queue_reserved(o_queue_reserved), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_stored(o_stored), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_completed(o_completed), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_source_busy(o_source_busy), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_source_error_sticky(o_source_error_sticky), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_header_error(o_header_error), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_body_error(o_body_error), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_queue_error_now(o_queue_error_now), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_queue_error_sticky(o_queue_error_sticky), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_reservation_error(o_reservation_error), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_vc(pipeline_vc), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_response(pipeline_response), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_owned(o_owned), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_selected(o_selected), // 原pipeline接口直接连接；容量事件不在新层生成。
 .o_error(pipeline_error) // 原pipeline接口直接连接；容量事件不在新层生成。
 ); // 结束实际队列和scheduler组合实例。
 switch_egress_repack #(.PORTS(PORTS),.VCS(VCS),.TOKEN_WIDTH(TOKEN_WIDTH)) u_repack( // 每物理出口唯一一项typed存储。
 .i_clk(i_clk),.i_rstn(i_rstn), // 同一个reset取消两级所有权。
 .i_valid(pipeline_valid),.i_data(pipeline_data),.i_last(pipeline_last),.i_token(pipeline_token),.i_vc(pipeline_vc),.i_response(pipeline_response), // 只接实际scheduler输出。
 .o_ready(pipeline_ready),.i_ready(i_ready), // 下游消费与queue到repack捕获是不同事件。
 .o_valid(o_valid),.o_last(o_last),.o_token(o_token),.o_vc(o_vc),.o_response(o_response), // typed元数据与完整记录原子交接。
 .o_local_dl_header(o_local_dl_header),.o_record_aux(o_record_aux),.o_tl_msg(o_tl_msg),.o_tl_flit(o_tl_flit), // 全部544位保存为明确的本地字段。
 .o_input_error(o_repack_input_error)); // 非法输入VC仅沿用既有repack诊断。
 genvar p; // 每端口独立重构既有本地record形状。
 generate for(p=0;p<PORTS;p=p+1)begin:gen_record // 不添加任何字段推断或第二条握手路径。
  assign o_data[p*544+:544]={o_local_dl_header[p*24+:24],o_record_aux[p*6+:6],o_tl_msg[p*2+:2],o_tl_flit[p*512+:512]}; // 精确还原全部544位供现有record消费者使用。
 end endgenerate // 结束静态端口拼接。
endmodule // 结束真实queue、scheduler和typed交接模块。
