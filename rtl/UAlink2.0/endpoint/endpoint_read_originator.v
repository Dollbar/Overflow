// single64B Read Originator：真实字段编码、四槽结果预约以及捕获/发送分阶段所有权。
`default_nettype none // 禁止隐式连接破坏完整Tag和握手语义
module endpoint_read_originator #(parameter integer CAPACITY=4, NUM_PORTS=1)( // Read发起模块：一个待发描述符与可并存的完整Tag结果表
 input wire i_clk,i_rstn, // 单时钟与同步低有效复位
 input wire [9:0] i_local_id, // 当前时期稳定的本地源ID和响应目的ID
 input wire i_request_valid, // 应用提供局部single64B Read请求
 output wire o_request_ready, // 仅同时获得待发位置和结果槽才接受请求
 input wire [1:0] i_request_port, // 本地身份端口，不编码进Control字段
 input wire [10:0] i_request_tag, // 应用完整十一位Tag
 input wire [56:0] i_request_address, // 保留完整五十七位字节地址
 input wire [9:0] i_request_dst, // 请求目标加速器ID
 input wire [5:0] i_request_length, // 当前必须为十五个DWORD增量
 input wire [7:0] i_request_attr, // 当前首末DWORD全部字节使能
 output wire o_source_valid, // 仅尚未被TL捕获的待发字段有效
 output wire [255:0] o_source_control, // 真实Read编码器生成的低位字段加NOP
 input wire i_source_captured, // TL源组捕获，不等于实际Header发送
 input wire i_header_taken, // 对应Request Header已在实际发送边界被消费
 input wire i_response_valid, // 完整两个Data半Flit已经由上游组装保存
 output wire o_response_ready, // 预约结果槽使响应不依赖应用完成接纳
 input wire [1:0] i_response_port, // 实际响应所在本地端口
 input wire [10:0] i_response_tag, // 实际响应完整Tag
 input wire [9:0] i_response_dst, // 验证响应目的为本地ID
 input wire [3:0] i_response_status, // 当前支持OKAY零与DECODE ERROR三
 input wire [1:0] i_response_offset, // 当前完整单Beat响应偏移零
 input wire i_response_last, // 单Beat响应必须有LAST
 input wire [1:0] i_response_num_beats, // 当前响应LEN为零
 input wire [511:0] i_response_data, // 完整响应数据，不存在半数据完成入口
 input wire i_response_data_error, // 首阶段拒绝DataError完成
 output wire o_complete_valid, // 稳定的已关联应用完成
 input wire i_complete_ready, // 应用握手释放Tag和完整结果容量
 output wire [1:0] o_complete_port, // 完成对应的本地端口
 output wire [10:0] o_complete_tag, // 完成对应的完整应用Tag
 output wire [3:0] o_complete_status, // 完整响应状态
 output wire [511:0] o_complete_data, // 错误完成输出零
 output wire o_complete_data_valid, // 仅成功完成允许提交数据
 output wire o_error, // 有效非法事件的当周期局部诊断
 output wire [7:0] o_count // 包括等待应用接纳的全部活跃预约
); // 内部ready/valid接口不冒充原生UPLI信用接口
reg r_pending,r_captured; // 待发送所有权与已转移给TL的捕获阶段
reg [1:0] r_port;reg [10:0] r_tag; // 待发身份保留到真实Header消费
reg [255:0] r_control; // 完整编码结果在应用握手沿保存
wire encoded_valid,encoded_error;wire [255:0] encoded_control; // 实际生产字段编码器结果
wire table_ready,table_error,port_legal,allocate_valid,request_fire,sent_event; // 分离预约、源捕获和真实发送
assign port_legal=({30'd0,i_request_port}<NUM_PORTS); // 当前配置只允许既定端口身份域
endpoint_read_encode Encode_Inst( // 复用真实Table5-29编码器与局部profile检查
 .i_valid(1'b1),.i_tag(i_request_tag),.i_src(i_local_id),.i_dst(i_request_dst), // 编码候选不直接转移所有权
 .i_address(i_request_address),.i_length(i_request_length),.i_attr(i_request_attr), // 高位地址完整进入编码器
 .i_vc(2'd0),.i_pool(1'b0),.i_asi(2'd0),.i_metadata(8'd0), // 冻结子集的本地选择
 .o_valid(encoded_valid),.o_error(encoded_error),.o_control(encoded_control) // 拒绝的字段不能获得请求ready
); // 结束真实请求编码器连接
assign allocate_valid=i_request_valid&&encoded_valid&&port_legal&&!r_pending; // 等待发送期间不重复预约保持中的应用输入
assign o_request_ready=i_rstn&&encoded_valid&&port_legal&&!r_pending&&table_ready; // 不借用同拍Header退休位置，允许保守吞吐
assign request_fire=i_request_valid&&o_request_ready; // 一次应用握手原子预约表项和待发描述符
assign o_source_valid=i_rstn&&r_pending&&!r_captured; // 源组捕获后禁止重复提交同一Header
assign o_source_control=o_source_valid?r_control:256'd0; // 背压前保持整个Control，捕获后撤下输出
assign sent_event=i_header_taken&&r_pending&&(r_captured||i_source_captured); // 实际Header消费才将Tag标记为已发送
assign o_error=i_rstn&&(table_error||(i_request_valid&&(encoded_error||!port_legal))|| // 非法profile和Tag事件由各所有者报告
 (i_source_captured&&(!r_pending||r_captured))||(i_header_taken&&(!r_pending||(!r_captured&&!i_source_captured)))); // 非法捕获/发送反馈不释放未发送描述符
endpoint_tag_table #(.CAPACITY(CAPACITY),.NUM_PORTS(NUM_PORTS)) Tags_Inst( // 实际实例化完整Tag和结果预约表
 .i_clk(i_clk),.i_rstn(i_rstn),.i_local_id(i_local_id), // 同一同步复位时期与本地ID
 .i_allocate_valid(allocate_valid),.i_allocate_port(i_request_port),.i_allocate_tag(i_request_tag),.o_allocate_ready(table_ready), // 只有有界空闲槽支持请求预约
 .i_sent_valid(sent_event),.i_sent_port(r_port),.i_sent_tag(r_tag), // 真实Header消费携带此前保存的身份
 .i_response_valid(i_response_valid),.o_response_ready(o_response_ready),.i_response_port(i_response_port),.i_response_tag(i_response_tag), // 响应直接进入预留结果表
 .i_response_dst(i_response_dst),.i_response_status(i_response_status),.i_response_offset(i_response_offset), // 严格验证目的与单Beat状态
 .i_response_last(i_response_last),.i_response_num_beats(i_response_num_beats),.i_response_data(i_response_data),.i_response_data_error(i_response_data_error), // 完整Data是响应valid的前提
 .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag), // 应用完成保持至握手
 .o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid), // 错误完成与成功数据明确区分
 .o_error(table_error),.o_count(o_count) // 槽容量和非法事件独立可见
); // 结束实际Tag表连接
always @(posedge i_clk)begin // 保守单待发位置限制吞吐，不限制已发送请求总容量
 if(!i_rstn)begin // 同步清空当前待发所有权
  r_pending<=1'b0;r_captured<=1'b0;r_port<=2'd0;r_tag<=11'd0;r_control<=256'd0; // 重置全部待发字段和身份
 end else begin // 所有后续反馈只作用于已经预约的描述符
  if(request_fire)begin // 原子保存编码字段与表中相同的完整身份
   r_pending<=1'b1;r_captured<=1'b0;r_port<=i_request_port;r_tag<=i_request_tag;r_control<=encoded_control; // 应用随后可改变输入
  end // 结束应用请求捕获
  if(i_source_captured&&o_source_valid)r_captured<=1'b1; // 源组所有权转移但仍保留待真实发送的Tag
  if(sent_event)begin r_pending<=1'b0;r_captured<=1'b0;end // 实际Header消费后才开放下一个待发位置
 end // 结束正常单待发状态更新
end // 结束Originator同步控制
endmodule // 结束真实Read发起模块
`default_nettype wire // 恢复外围默认网络设置
