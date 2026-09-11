`timescale 1ps/1ps // 原队列预约与物理出口调度直接连接，不新增资源所有者。
module switch_egress_pipeline #( // switch_egress_pipeline模块：出口、请求响应及VC独立资源缓存。
 parameter integer PORTS=4,VCS=4,DATA_WIDTH=544,TOKEN_WIDTH=8,UNIT_WIDTH=4, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
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
 input wire [PORTS*DATA_WIDTH-1:0] i_body_data, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS-1:0] i_body_last, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS*TOKEN_WIDTH-1:0] i_body_token, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [PORTS-1:0] o_body_ready, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 input wire [PORTS-1:0] i_ready, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [PORTS-1:0] o_valid,o_last, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 output wire [PORTS*DATA_WIDTH-1:0] o_data, // 原队列预约与物理出口调度直接连接，不新增资源所有者。
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
 output wire o_error // 原队列预约与物理出口调度直接连接，不新增资源所有者。
); // 原队列预约与物理出口调度直接连接，不新增资源所有者。
 wire [2*VCS*PORTS-1:0] queue_valid,queue_last,queue_ready; // 真实队列头与唯一返回ready路径。
 wire [2*VCS*PORTS*DATA_WIDTH-1:0] queue_data; // 所有域的完整实际数据头。
 wire [2*VCS*PORTS*TOKEN_WIDTH-1:0] queue_token; // 与实际数据头同行的原始包身份。
 switch_egress_vc_queues #(.PORTS(PORTS),.VCS(VCS),.DATA_WIDTH(DATA_WIDTH),.TOKEN_WIDTH(TOKEN_WIDTH),.UNIT_WIDTH(UNIT_WIDTH),.DEFAULT_CAPACITY(DEFAULT_CAPACITY),.CAPACITIES(CAPACITIES)) Queues_Inst( // 唯一分域预约、真实存储与最后一拍释放所有者。
 .i_clk(i_clk), // 原队列接口原样传递，完整slot顺序不变。
 .i_rstn(i_rstn), // 原队列接口原样传递，完整slot顺序不变。
 .i_header_valid(i_header_valid), // 原队列接口原样传递，完整slot顺序不变。
 .i_route_match(i_route_match), // 原队列接口原样传递，完整slot顺序不变。
 .i_header_units(i_header_units), // 原队列接口原样传递，完整slot顺序不变。
 .i_header_token(i_header_token), // 原队列接口原样传递，完整slot顺序不变。
 .i_header_vc(i_header_vc), // 原队列接口原样传递，完整slot顺序不变。
 .i_header_response(i_header_response), // 原队列接口原样传递，完整slot顺序不变。
 .o_header_ready(o_header_ready), // 原队列接口原样传递，完整slot顺序不变。
 .i_body_valid(i_body_valid), // 原队列接口原样传递，完整slot顺序不变。
 .i_body_data(i_body_data), // 原队列接口原样传递，完整slot顺序不变。
 .i_body_last(i_body_last), // 原队列接口原样传递，完整slot顺序不变。
 .i_body_token(i_body_token), // 原队列接口原样传递，完整slot顺序不变。
 .o_body_ready(o_body_ready), // 原队列接口原样传递，完整slot顺序不变。
 .i_ready(queue_ready), // 原队列接口原样传递，完整slot顺序不变。
 .o_valid(queue_valid), // 原队列接口原样传递，完整slot顺序不变。
 .o_last(queue_last), // 原队列接口原样传递，完整slot顺序不变。
 .o_data(queue_data), // 原队列接口原样传递，完整slot顺序不变。
 .o_token(queue_token), // 原队列接口原样传递，完整slot顺序不变。
 .o_release_valid(o_release_valid), // 原队列接口原样传递，完整slot顺序不变。
 .o_release_units(o_release_units), // 原队列接口原样传递，完整slot顺序不变。
 .o_available(o_available), // 原队列接口原样传递，完整slot顺序不变。
 .o_reserved(o_reserved), // 原队列接口原样传递，完整slot顺序不变。
 .o_queue_reserved(o_queue_reserved), // 原队列接口原样传递，完整slot顺序不变。
 .o_stored(o_stored), // 原队列接口原样传递，完整slot顺序不变。
 .o_completed(o_completed), // 原队列接口原样传递，完整slot顺序不变。
 .o_source_busy(o_source_busy), // 原队列接口原样传递，完整slot顺序不变。
 .o_source_error_sticky(o_source_error_sticky), // 原队列接口原样传递，完整slot顺序不变。
 .o_header_error(o_header_error), // 原队列接口原样传递，完整slot顺序不变。
 .o_body_error(o_body_error), // 原队列接口原样传递，完整slot顺序不变。
 .o_queue_error_now(o_queue_error_now), // 原队列接口原样传递，完整slot顺序不变。
 .o_queue_error_sticky(o_queue_error_sticky), // 原队列接口原样传递，完整slot顺序不变。
 .o_reservation_error(o_reservation_error), // 原队列接口原样传递，完整slot顺序不变。
 .o_error(o_error) // 原队列接口原样传递，完整slot顺序不变。
 ); // 结束唯一队列资源所有者实例。
 switch_egress_scheduler #(.PORTS(PORTS),.VCS(VCS),.DATA_WIDTH(DATA_WIDTH),.TOKEN_WIDTH(TOKEN_WIDTH),.RSP_BURST_MAX(RSP_BURST_MAX)) Scheduler_Inst( // 每物理出口一条流，不再次预约或释放。
 .i_clk(i_clk),.i_rstn(i_rstn), // 队列和scheduler必须使用同一复位epoch。
 .i_valid(queue_valid),.i_data(queue_data),.i_last(queue_last),.i_token(queue_token), // 调度输入只来自真实完整包队列。
 .i_ready(i_ready),.o_ready(queue_ready), // 物理接受资格只送回唯一所选slot。
 .o_valid(o_valid),.o_data(o_data),.o_last(o_last),.o_token(o_token), // 整包payload、边界和身份完整透传。
 .o_vc(o_vc),.o_response(o_response),.o_selected(o_selected),.o_owned(o_owned) // 类别与VC来自实际包锁，不能从新header重推断。
 ); // 结束物理egress调度实例。
endmodule // 结束本地包资源与物理出口流水组合模块。
