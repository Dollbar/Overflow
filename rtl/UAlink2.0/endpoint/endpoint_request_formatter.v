// 一个共享Tag表协调Read/Write，不允许后来的Header或Data绕过当前holding。
`default_nettype none // 禁止隐式网络掩盖共享所有权接口错误
module endpoint_request_formatter #(parameter integer CAPACITY=4,NUM_PORTS=1,FULL_READ_ENABLE=0)( // 共享Read与Write发起模块：参数决定统一Tag容量和端口域
 input wire i_clk,i_rstn, // 单时钟与同步低有效复位
 input wire [9:0] i_local_id, // 当前时期稳定的本地源ID和响应目的ID
 input wire i_request_is_write,i_request_full, // 请求种类共用一个有序待发通道
 input wire [1:0] i_request_asi,input wire [7:0] i_request_metadata, // Write属性完整透传，Read保持冻结的零ASI和元数据
 input wire [2047:0] i_request_data,input wire [255:0] i_request_be, // 一次应用握手提供最多四个Beat及区域BE
 input wire i_request_valid, // 应用原子提交Read或完整Write
 output wire o_request_ready, // 仅同时获得待发位置和结果槽才接受请求
 input wire [1:0] i_request_port, // 本地身份端口，不编码进Control字段
 input wire [10:0] i_request_tag, // 应用完整十一位Tag
 input wire [56:0] i_request_address, // 保留完整五十七位字节地址
 input wire [9:0] i_request_dst, // 请求目标加速器ID
 input wire [5:0] i_request_length, // 字节长度除四减一
 input wire [7:0] i_request_attr, // Read使用FF；Write属性完整透传
 output wire o_source_valid, // 仅尚未被TL捕获的待发字段有效
 output wire [255:0] o_source_control, // 真实Read编码器生成的低位字段加NOP
 input wire i_source_captured, // TL源组捕获，不等于实际Header发送
 output wire [1:0] o_data_valid,output wire [511:0] o_data,input wire [1:0] i_data_accepted, // 类别零的数据半字按低位优先计数接纳
 input wire i_header_taken, // 对应Request Header已在实际发送边界被消费
 input wire i_response_is_write, // 响应种类必须匹配共享表中保存的请求种类
 input wire i_response_valid, // Read已收齐Data，Write无Data
 output wire o_response_ready, // 预约结果槽使响应不依赖应用完成接纳
 input wire [1:0] i_response_port, // 实际响应所在本地端口
 input wire [10:0] i_response_tag, // 实际响应完整Tag
 input wire [9:0] i_response_dst, // 验证响应目的为本地ID
 input wire [3:0] i_response_status, // Read零三；Write零二三六八
 input wire [1:0] i_response_offset, // 当前完整单Beat响应偏移零
 input wire i_response_last, // 单Beat响应必须有LAST
 input wire [1:0] i_response_num_beats, // 当前响应LEN为零
 input wire [511:0] i_response_data, // 完整响应数据，不存在半数据完成入口
 input wire i_response_data_error, // 首阶段拒绝DataError完成
 output wire o_complete_is_write, // 完成种类与Tag及结果共同保持至应用接纳
 output wire o_complete_valid, // 稳定的已关联应用完成
 input wire i_complete_ready, // 应用握手释放Tag和完整结果容量
 output wire [1:0] o_complete_port, // 完成对应的本地端口
 output wire [10:0] o_complete_tag, // 完成对应的完整应用Tag
 output wire [3:0] o_complete_status, // 完整响应状态
 output wire [511:0] o_complete_data, // 错误完成输出零
 output wire o_complete_data_valid, // 仅成功Read完成允许提交数据
 output wire o_error, // 有效非法事件的当周期局部诊断
 output wire [7:0] o_count, // 包括等待应用接纳的全部活跃预约

 output wire [2047:0] o_complete_data_full,output wire [255:0] o_complete_mask // 完整Read结果及相对Beat字节有效位
); // 结束混合事务发起与完成接口
reg r_pending,r_is_write,r_captured; // 保存唯一有序待发请求的种类和Read捕获状态
reg [1:0] r_port;reg [10:0] r_tag;reg [255:0] r_control; // 身份保持至真实Header发送，Read字段保存至捕获
wire read_legal;wire [255:0] read_control,read_be;wire [1:0] read_num_beats; // 实际Read编码器给出完整字段及候选合法性
wire write_ready,write_legal,write_error,write_source_valid,write_sent,write_done; // Write子模块独立报告准备和三阶段交付状态
wire [255:0] write_control;wire [1:0] write_data_valid;wire [511:0] write_data; // Write路径保存Header及顺序Data半字
wire table_ready,table_error; // 唯一Tag表提供容量背压与身份诊断
wire port_legal; // 声明port_legal，物理端口仅进入配置允许的身份域
assign port_legal=({30'd0,i_request_port}<NUM_PORTS); // 物理端口仅进入配置允许的身份域
wire profile_legal; // 声明profile_legal，Write检查完整几何；Read继续采用单64字节局部profile
assign profile_legal=i_request_is_write?write_legal:(read_legal&&((FULL_READ_ENABLE!=0)||((i_request_asi==2'd0)&&(i_request_metadata==8'd0)))); // Write检查完整几何；Read继续采用单64字节局部profile
wire allocate_valid; // 声明allocate_valid，holding空闲且候选合法才向共享表请求预约
assign allocate_valid=i_request_valid&&!r_pending&&port_legal&&profile_legal; // holding空闲且候选合法才向共享表请求预约
wire request_fire; // 声明request_fire，应用握手同时获得共享结果槽及待发位置
assign request_fire=i_request_valid&&o_request_ready; // 应用握手同时获得共享结果槽及待发位置
wire read_capture; // 声明read_capture，Read源捕获仅属于当前未捕获的Read请求
assign read_capture=i_source_captured&&r_pending&&!r_is_write&&!r_captured; // Read源捕获仅属于当前未捕获的Read请求
wire read_sent; // 声明read_sent，Read Header实际发送必须晚于或同于捕获反馈
assign read_sent=i_header_taken&&r_pending&&!r_is_write&&(r_captured||read_capture); // Read Header实际发送必须晚于或同于捕获反馈
wire sent_event; // 声明sent_event，当前holding的种类唯一选择真实发送事件
assign sent_event=r_is_write?write_sent:read_sent; // 当前holding的种类唯一选择真实发送事件
assign o_request_ready=i_rstn&&!r_pending&&port_legal&&profile_legal&&table_ready&&(!i_request_is_write||write_ready); // 共享表与对应保持模块均就绪才原子接受新请求
assign o_source_valid=r_is_write?write_source_valid:(i_rstn&&r_pending&&!r_captured); // 按当前保存种类选择唯一prepared Header源
assign o_source_control=r_is_write?write_control:(o_source_valid?r_control:256'd0); // Read和Write字段共用一个类别零Control入口
assign o_data_valid=r_is_write?write_data_valid:2'd0; // 只有当前Write拥有类别零Data有效数量
assign o_data=r_is_write?write_data:512'd0; // Read不产生请求Data，Write输出保存的顺序半字
assign o_error=i_rstn&&(table_error||write_error||(i_request_valid&&(!port_legal||!profile_legal))|| // 合并共享表和Write诊断，合法满槽不报告错误
 (!r_is_write&&((i_source_captured&&(!r_pending||r_captured))||(i_header_taken&&(!r_pending||(!r_captured&&!read_capture)))||(i_data_accepted!=2'd0)))); // Read路径拒绝伪捕获、未拥有的发送及任何请求Data接纳
endpoint_read_encode #(.FULL_READ_ENABLE(FULL_READ_ENABLE)) Read_Encode_Inst( // 实例化实际Read字段编码器，保持既有profile语义
 .i_valid(1'b1),.i_tag(i_request_tag),.i_src(i_local_id),.i_dst(i_request_dst),.i_address(i_request_address), // 候选编码保留Tag、地址与双侧物理ID
 .i_length(i_request_length),.i_attr(i_request_attr),.i_vc(2'd0),.i_pool(1'b0),.i_asi((FULL_READ_ENABLE!=0)?i_request_asi:2'd0),.i_metadata((FULL_READ_ENABLE!=0)?i_request_metadata:8'd0), // Read固定VC信用域及当前支持的地址空间元数据
 .o_valid(read_legal),.o_error(),.o_control(read_control),.o_num_beats(read_num_beats),.o_be(read_be) // 合法性用于共享预约；编码错误等价于候选非法
); // 结束Read编码器连接
endpoint_write_originator Write_Inst( // 实例化完整Write保持模块，不创建第二张Tag表
 .i_clk(i_clk),.i_rstn(i_rstn),.i_local_id(i_local_id), // Write与共享预约表使用相同同步复位时期
 .i_request_valid(i_request_valid&&i_request_is_write&&!r_pending&&table_ready&&port_legal),.o_request_ready(write_ready), // 共享表有空位且有序holding为空才允许Write捕获
 .i_request_full(i_request_full),.i_request_tag(i_request_tag),.i_request_address(i_request_address),.i_request_dst(i_request_dst), // 普通Write或Full类型、完整Tag地址和目的原样连接
 .i_request_length(i_request_length),.i_request_attr(i_request_attr),.i_request_asi(i_request_asi),.i_request_metadata(i_request_metadata), // 长度属性与Accelerator元数据进入实际编码器
 .i_request_data(i_request_data),.i_request_be(i_request_be), // 完整四Beat数据与区域BE在同次应用握手保存
 .o_source_valid(write_source_valid),.o_source_control(write_control),.i_source_captured(i_source_captured&&r_is_write), // 只有Write当前拥有Header时才接收捕获反馈
 .i_header_taken(i_header_taken&&r_is_write),.o_data_valid(write_data_valid),.o_data(write_data),.i_data_accepted(r_is_write?i_data_accepted:2'd0), // 实际发送和Data接纳仅送至当前Write所有者
 .o_pending(),.o_sent(write_sent),.o_done(write_done),.o_error(write_error),.o_profile_legal(write_legal) // 共享表使用真实发送事件；holding使用全部交付结束事件
); // 结束Write事务保持模块连接
endpoint_tag_table #(.CAPACITY(CAPACITY),.NUM_PORTS(NUM_PORTS),.WRITE_ENABLE(1),.FULL_READ_ENABLE(FULL_READ_ENABLE)) Tags_Inst( // 唯一共享Tag表显式开启Read与Write种类比较
 .i_clk(i_clk),.i_rstn(i_rstn),.i_local_id(i_local_id), // 本地响应目的ID与全部子模块同复位域
 .i_allocate_valid(allocate_valid),.i_allocate_port(i_request_port),.i_allocate_tag(i_request_tag),.i_allocate_is_write(i_request_is_write),.o_allocate_ready(table_ready), // 预约时同时保存完整身份及请求种类
 .i_sent_valid(sent_event),.i_sent_port(r_port),.i_sent_tag(r_tag), // 发送事件使用holding中身份而不使用变化中的应用输入
 .i_response_valid(i_response_valid),.i_response_is_write(i_response_is_write),.o_response_ready(o_response_ready), // 接收器提交完整响应并给出Read或Write类型
 .i_response_port(i_response_port),.i_response_tag(i_response_tag),.i_response_dst(i_response_dst),.i_response_status(i_response_status), // 共享表检查完整端口Tag和本地目的ID与状态
 .i_response_offset(i_response_offset),.i_response_last(i_response_last),.i_response_num_beats(i_response_num_beats), // Read检查单Beat结束条件，Write忽略无效偏移和LAST
 .i_response_data(i_response_data),.i_response_data_error(i_response_data_error), // Read拥有完整结果数据，Write不提交数据
 .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_is_write(o_complete_is_write), // 应用握手同时退休完成与其保存的kind
 .o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag),.o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid), // 完成结果与完整身份由锁定表槽提供
 .i_allocate_read_num_beats(read_num_beats),.i_allocate_read_mask(read_be>>(64*i_request_address[7:6])),
 .o_complete_data_full(o_complete_data_full),.o_complete_mask(o_complete_mask),
 .o_error(table_error),.o_count(o_count) // 导出预约计数及非法有效事件诊断
); // 结束唯一共享Tag表连接
always @(posedge i_clk)begin // 单一同步域维护类别零Header和Data的先后所有权
 if(!i_rstn)begin // 同步复位取消当前holding身份和种类
  r_pending<=1'b0;r_is_write<=1'b0;r_captured<=1'b0;r_port<=2'd0;r_tag<=11'd0;r_control<=256'd0; // 复位后无旧请求Header或种类残留有效
 end else begin // 正常周期只根据实际请求或交付事件更新
  if(request_fire)begin // 接受一个新请求时锁定Read或Write种类
   r_pending<=1'b1;r_is_write<=i_request_is_write;r_captured<=1'b0; // 新holding的捕获阶段始终从未捕获开始
   r_port<=i_request_port;r_tag<=i_request_tag;r_control<=read_control; // 保存完整本地身份及Read候选字段
  end // 结束原子请求身份保存
  if(read_capture)r_captured<=1'b1; // Read捕获后撤下源valid但仍等待实际发送
  if((r_is_write&&write_done)||read_sent)begin r_pending<=1'b0;r_captured<=1'b0;end // Write全部交付或Read实际发送后开放下个有序请求
 end // 结束正常holding所有权更新
end // 结束混合发起同步寄存器
endmodule // 结束endpoint_request_formatter模块
`default_nettype wire // 恢复外围默认网络声明方式
