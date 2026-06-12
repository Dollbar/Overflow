`timescale 1ns/1ps // 与实际所有者子链统一仿真时间单位。
// 一个共享Tag表协调Read/Write，不允许后来的Header或Data绕过当前holding。
`default_nettype none // 禁止隐式网络掩盖共享所有权接口错误
module endpoint_request_formatter #(parameter integer CAPACITY=4,NUM_PORTS=1,FULL_READ_ENABLE=0,RAS_ENABLE=0,IS_SWITCH=0,EPOCH_WIDTH=8,GENERATION_WIDTH=8,NATIVE_REQUEST_ENABLE=0,NATIVE_RAW_ENABLE=0,MESSAGE_ENABLE=0,parameter integer ORDERING_ENABLE=0,parameter integer ORDER_TOKEN_WIDTH=16,parameter integer ORDER_EPOCH_WIDTH=8)( // 共享Read与Write发起模块：参数决定统一Tag容量和端口域
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

 output wire [2047:0] o_complete_data_full,output wire [255:0] o_complete_mask, // 完整Read结果及相对Beat字节有效位
 input wire [NUM_PORTS-1:0] i_ras_isolate,i_ras_link_down,i_ras_link_up,i_ras_init_done,i_ras_drop, // 唯一外部管理输入不复制Drop状态。
 input wire i_ras_recover_valid,input wire [EPOCH_WIDTH-1:0] i_ras_recover_epoch, // 显式新时期恢复申请。
 input wire i_rx_epoch_drained,i_tx_epoch_drained,i_owner_events_drained,input wire [EPOCH_WIDTH-1:0] i_tx_drain_epoch, // 系统资格必须绑定实际旧时期。
 output wire [NUM_PORTS-1:0] o_tx_stop,o_ras_isolated,output wire [1:0] o_tx_port,output wire o_tx_local_drained, // 唯一holding与管理停止域。
 output wire [EPOCH_WIDTH-1:0] o_ras_epoch,output wire o_ras_recovered,o_ras_recover_ready,o_ras_blocked, // 实际账本时期与恢复状态。
 output wire [7:0] o_ras_ledger_count,output wire o_ras_dummy_done_fire,output wire [1:0] o_ras_dummy_done_slot, // 联合销账观察不是镜像账本。
 output wire o_complete_cancel,o_complete_is_dummy,output wire [1:0] o_complete_slot, // 应用必须遵循valid与ready且非cancel的整笔转移。
 output wire [EPOCH_WIDTH-1:0] o_complete_epoch,output wire [GENERATION_WIDTH-1:0] o_complete_generation,output wire [2:0] o_complete_beats, // 完整原始身份与响应几何。
 input wire [183:0] i_native_payload, // 完整原生opaque字段：ASI/Auth/Src/Dst/Tag/Num/Addr/Cmd/Len/Attr/Meta。
 input wire [1:0] i_native_vc,input wire i_native_pool,i_native_tl_pool, // 两套pool所有权完全分开。
 input wire [3:0] i_native_poison,i_native_data_pools, // 完整保留各拍原生数据身份；首阶段拒绝poison执行。
 input wire [1:0] i_response_vc, // 真实返回响应VC，不用当前请求VC替代。
 output wire [183:0] o_native_source_payload,o_native_complete_payload, // 原始请求上下文观察，不能当作新消费者。
 output wire [1:0] o_native_complete_vc,output wire o_native_complete_pool, // 原生返回关联元数据，非TL信用归还接口。
 output wire [3:0] o_native_complete_poison,o_native_complete_data_pools, // 原始逐拍上下文保持至最终应用接纳。
 input wire [63:0] i_response_header, // 原始TL单拍响应Header，完整保留Src/Pool/Spare与实际到达顺序。
 output wire [2047:0] o_native_complete_raw_data, // 独立于应用mask/error-zero的数据观察；仍绑定唯一Tag完成握手。
 output wire [255:0] o_native_complete_raw_headers // 每64位为一条真实响应Header。
,input wire i_native_message_response_is_read,input wire [1:0] i_native_message_response_num_beats // 应用声明的vendor响应义务在request_fire保存。
,output wire [2:0] o_native_complete_response_beats,output wire o_native_complete_is_message // 最终native发送使用同一Tag预约义务。
,output wire [3:0] o_native_complete_raw_poison // 对应实际收回Data的原始Poison，与请求OrigData标记分开。
,input wire[ORDER_EPOCH_WIDTH-1:0] i_request_order_epoch,input wire[ORDER_TOKEN_WIDTH-1:0] i_request_order_token,output wire[ORDER_EPOCH_WIDTH-1:0] o_complete_order_epoch,output wire[ORDER_TOKEN_WIDTH-1:0] o_complete_order_token,input wire[NUM_PORTS-1:0] i_order_port_reset
); // 结束混合事务发起与完成接口
wire selected_message=(MESSAGE_ENABLE!=0)&&(NATIVE_REQUEST_ENABLE!=0)&&(i_native_payload[27:22]==6'h2a); // 不把其他带Data命令猜成Message。
wire message_policy_legal=(i_native_payload[7:0]==0)?(!i_native_message_response_is_read&&i_native_message_response_num_beats==0&&i_native_payload[86:85]==0&&i_request_data[511:0]==0):(i_native_payload[7:4]==4'hf&& (i_native_message_response_is_read||i_native_message_response_num_beats==0)); // 标准NOP或明确vendor策略，KeyRoll仍拒绝。
wire selected_reply_write=selected_message?!i_native_message_response_is_read:selected_request_is_write; // 数据发送种类与响应kind是两个独立义务。
wire [1:0] selected_reply_num=selected_message?i_native_message_response_num_beats:read_num_beats; // Message响应拍数不由请求NUM/LEN推导。
wire [255:0] selected_reply_mask=selected_message?(256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff >> ((32'd3-{30'd0,i_native_message_response_num_beats})*32'd64)):(read_be>>(64*selected_request_address[7:6])); // Vendor完整自然Beat，不虚构内存字节mask。
wire [0:0] selected_request_is_write=(NATIVE_REQUEST_ENABLE!=0)?(i_native_payload[27:22]!=6'h03):i_request_is_write; // 默认应用模式完整保持原义。
wire [0:0] selected_request_full=(NATIVE_REQUEST_ENABLE!=0)?(i_native_payload[27:22]==6'h29):i_request_full; // 默认应用模式完整保持原义。
wire [1:0] selected_request_asi=(NATIVE_REQUEST_ENABLE!=0)?i_native_payload[183:182]:i_request_asi; // 默认应用模式完整保持原义。
wire [7:0] selected_request_metadata=(NATIVE_REQUEST_ENABLE!=0)?i_native_payload[7:0]:i_request_metadata; // 默认应用模式完整保持原义。
wire [10:0] selected_request_tag=(NATIVE_REQUEST_ENABLE!=0)?i_native_payload[97:87]:i_request_tag; // 默认应用模式完整保持原义。
wire [56:0] selected_request_address=(NATIVE_REQUEST_ENABLE!=0)?i_native_payload[84:28]:i_request_address; // 默认应用模式完整保持原义。
wire [9:0] selected_request_dst=(NATIVE_REQUEST_ENABLE!=0)?i_native_payload[107:98]:i_request_dst; // 默认应用模式完整保持原义。
wire [5:0] selected_request_length=(NATIVE_REQUEST_ENABLE!=0)?i_native_payload[21:16]:i_request_length; // 默认应用模式完整保持原义。
wire [7:0] selected_request_attr=(NATIVE_REQUEST_ENABLE!=0)?i_native_payload[15:8]:i_request_attr; // 默认应用模式完整保持原义。
wire [9:0] selected_local_id=(NATIVE_REQUEST_ENABLE!=0)?i_native_payload[117:108]:i_local_id; // 默认应用模式完整保持原义。
wire [255:0] selected_request_be=(NATIVE_REQUEST_ENABLE!=0)?(selected_message?i_request_be:(i_request_be << ({30'd0,i_native_payload[35:34]}*32'd64))):i_request_be; // 默认应用模式完整保持原义。
wire [1:0] selected_vc=(NATIVE_REQUEST_ENABLE!=0)?i_native_vc:2'd0;
wire selected_tl_pool=(NATIVE_REQUEST_ENABLE!=0)&&i_native_tl_pool;
wire native_response_vc_bad;
wire [8:0] native_extent={3'd0,i_native_payload[33:28]}+{1'b0,i_native_payload[21:16],2'd0}+9'd67;
wire native_profile=(NATIVE_REQUEST_ENABLE==0)||(((i_native_payload[27:22]==6'h03)||(i_native_payload[27:22]==6'h28)||(i_native_payload[27:22]==6'h29)||(selected_message&&message_policy_legal))&&(i_native_payload[181:118]==64'd0)&&(i_native_poison==4'd0)&&((i_native_payload[27:22]!=6'h28)||((i_request_be>>(32'd256-{24'd0,i_native_payload[35:34],6'd0}))==256'd0))&&(selected_message||((i_native_payload[27:22]==6'h03)?(i_native_payload[86:85]==2'd0):(i_native_payload[86:85]==(native_extent[7:6]-2'd1))))); // Auth/poison未实现时明确拒绝，不静默改写成功。
reg [183:0] r_native_source_payload;
assign o_native_source_payload=((NATIVE_REQUEST_ENABLE!=0)&&o_source_valid)?r_native_source_payload:184'd0;
always @(posedge i_clk)begin
 if(!i_rstn)r_native_source_payload<=184'd0;else if(request_fire)r_native_source_payload<=i_native_payload;
end
wire unused_native_extent=^{native_extent[8],native_extent[5:0]}; // 完整合法几何只使用低两位编码拍数。

reg r_pending,r_is_write,r_captured; // 保存唯一有序待发请求的种类和Read捕获状态
reg [1:0] r_port;reg [10:0] r_tag;reg [255:0] r_control; // 身份保持至真实Header发送，Read字段保存至捕获
wire unused_read_error; // 编码合法输出已包含同一错误信息。
wire read_legal;wire [255:0] read_control,read_be;wire [1:0] read_num_beats; // 实际Read编码器给出完整字段及候选合法性
wire write_ready,write_legal,write_error,write_source_valid,write_sent,write_done; // Write子模块独立报告准备和三阶段交付状态
wire [255:0] write_control;wire [1:0] write_data_valid;wire [511:0] write_data; // Write路径保存Header及顺序Data半字
wire write_pending,held_stopped,local_cancel,qualified_tx_ack,feedback_error; // 取消依赖同期真实TX清空，不依赖Tag计数。
wire ras_blocked;reg r_feedback_error;wire [3:0] stop_ports; // 反馈异常保持直到共同reset。
assign stop_ports={{(4-NUM_PORTS){1'b0}},o_tx_stop}; // 端口选择保留完整两位域。
assign held_stopped=(RAS_ENABLE!=0)&&r_pending&&stop_ports[r_port]; // 只停止实际holding所属端口。
assign qualified_tx_ack=(RAS_ENABLE!=0)&&i_tx_epoch_drained&&(i_tx_drain_epoch==o_ras_epoch); // 旧ACK不能跨时期授权。
assign local_cancel=held_stopped&&qualified_tx_ack; // 明确清空确认才撤销本地残留。
assign feedback_error=(RAS_ENABLE!=0)&&held_stopped&&(i_source_captured||i_header_taken||(i_data_accepted!=2'd0)); // 停止后的伪交付不能推进sent。
assign o_tx_stop=o_ras_isolated|{NUM_PORTS{o_ras_blocked}}; // 不产生第二套隔离状态。
assign o_tx_port=r_port;assign o_tx_local_drained=!r_pending&&!write_pending; // 实际本地holding清空独立于预约计数。
assign o_ras_blocked=ras_blocked||r_feedback_error; // 非法反馈不自动恢复。
wire table_ready,table_error; // 唯一Tag表提供容量背压与身份诊断
wire port_legal; // 声明port_legal，物理端口仅进入配置允许的身份域
assign port_legal=({30'd0,i_request_port}<NUM_PORTS); // 物理端口仅进入配置允许的身份域
wire profile_legal; // 声明profile_legal，Write检查完整几何；Read继续采用单64字节局部profile
assign profile_legal=native_profile&&(selected_request_is_write?write_legal:(read_legal&&((FULL_READ_ENABLE!=0)||((selected_request_asi==2'd0)&&(selected_request_metadata==8'd0))))); // Write检查完整几何；Read继续采用单64字节局部profile
wire allocate_valid; // 声明allocate_valid，holding空闲且候选合法才向共享表请求预约
assign allocate_valid=i_request_valid&&!r_pending&&port_legal&&profile_legal&&(!selected_request_is_write||write_ready)&&!o_ras_blocked; // holding空闲且候选合法才向共享表请求预约
wire request_fire; // 声明request_fire，应用握手同时获得共享结果槽及待发位置
assign request_fire=i_request_valid&&o_request_ready; // 应用握手同时获得共享结果槽及待发位置
wire read_capture; // 声明read_capture，Read源捕获仅属于当前未捕获的Read请求
assign read_capture=!held_stopped&&i_source_captured&&r_pending&&!r_is_write&&!r_captured; // Read源捕获仅属于当前未捕获的Read请求
wire read_sent; // 声明read_sent，Read Header实际发送必须晚于或同于捕获反馈
assign read_sent=!held_stopped&&i_header_taken&&r_pending&&!r_is_write&&(r_captured||read_capture); // Read Header实际发送必须晚于或同于捕获反馈
wire sent_event; // 声明sent_event，当前holding的种类唯一选择真实发送事件
assign sent_event=r_is_write?write_sent:read_sent; // 当前holding的种类唯一选择真实发送事件
assign o_request_ready=i_rstn&&!o_ras_blocked&&!r_pending&&port_legal&&profile_legal&&table_ready&&(!selected_request_is_write||write_ready); // 共享表与对应保持模块均就绪才原子接受新请求
assign o_source_valid=!held_stopped&&(r_is_write?write_source_valid:(i_rstn&&r_pending&&!r_captured)); // 按当前保存种类选择唯一prepared Header源
assign o_source_control=o_source_valid?(r_is_write?write_control:r_control):256'd0; // Read和Write字段共用一个类别零Control入口
assign o_data_valid=(r_is_write&&!held_stopped)?write_data_valid:2'd0; // 只有当前Write拥有类别零Data有效数量
assign o_data=(r_is_write&&!held_stopped)?write_data:512'd0; // Read不产生请求Data，Write输出保存的顺序半字
assign o_error=i_rstn&&((i_response_valid&&native_response_vc_bad)||feedback_error||r_feedback_error||table_error||write_error||(i_request_valid&&(!port_legal||!profile_legal))|| // 合并共享表和Write诊断，合法满槽不报告错误
 (!r_is_write&&((i_source_captured&&(!r_pending||r_captured))||(i_header_taken&&(!r_pending||(!r_captured&&!read_capture)))||(i_data_accepted!=2'd0)))); // Read路径拒绝伪捕获、未拥有的发送及任何请求Data接纳
endpoint_read_encode #(.FULL_READ_ENABLE(FULL_READ_ENABLE),.NATIVE_FIELDS_ENABLE(NATIVE_REQUEST_ENABLE)) Read_Encode_Inst( // 实例化实际Read字段编码器，保持既有profile语义
 .i_valid(1'b1),.i_tag(selected_request_tag),.i_src(selected_local_id),.i_dst(selected_request_dst),.i_address(selected_request_address), // 候选编码保留Tag、地址与双侧物理ID
 .i_length(selected_request_length),.i_attr(selected_request_attr),.i_vc(selected_vc),.i_pool(selected_tl_pool),.i_asi((FULL_READ_ENABLE!=0)?selected_request_asi:2'd0),.i_metadata((FULL_READ_ENABLE!=0)?selected_request_metadata:8'd0), // Read固定VC信用域及当前支持的地址空间元数据
 .o_valid(read_legal),.o_error(unused_read_error),.o_control(read_control),.o_num_beats(read_num_beats),.o_be(read_be) // 合法性用于共享预约；编码错误等价于候选非法
); // 结束Read编码器连接
endpoint_write_originator #(.MESSAGE_ENABLE(MESSAGE_ENABLE),.CANCEL_ENABLE(RAS_ENABLE),.NATIVE_FIELDS_ENABLE(NATIVE_REQUEST_ENABLE)) Write_Inst( // 实例化完整Write保持模块，不创建第二张Tag表
 .i_request_is_message(selected_message),.i_request_num_beats(i_native_payload[86:85]),
 .i_clk(i_clk),.i_rstn(i_rstn),.i_local_id(selected_local_id), // Write与共享预约表使用相同同步复位时期
 .i_request_valid(request_fire&&selected_request_is_write),.o_request_ready(write_ready), // 共享表有空位且有序holding为空才允许Write捕获
 .i_request_full(selected_request_full),.i_request_tag(selected_request_tag),.i_request_address(selected_request_address),.i_request_dst(selected_request_dst), // 普通Write或Full类型、完整Tag地址和目的原样连接
 .i_request_length(selected_request_length),.i_request_attr(selected_request_attr),.i_request_asi(selected_request_asi),.i_request_metadata(selected_request_metadata), // 长度属性与Accelerator元数据进入实际编码器
 .i_request_data(i_request_data),.i_request_be(selected_request_be), // 完整四Beat数据与区域BE在同次应用握手保存
 .o_source_valid(write_source_valid),.o_source_control(write_control),.i_source_captured(i_source_captured&&r_is_write&&!held_stopped), // 只有Write当前拥有Header时才接收捕获反馈
 .i_header_taken(i_header_taken&&r_is_write&&!held_stopped),.o_data_valid(write_data_valid),.o_data(write_data),.i_data_accepted((r_is_write&&!held_stopped)?i_data_accepted:2'd0), // 实际发送和Data接纳仅送至当前Write所有者
 .i_request_vc(selected_vc),.i_request_tl_pool(selected_tl_pool),.o_pending(write_pending),.i_cancel(local_cancel),.o_sent(write_sent),.o_done(write_done),.o_error(write_error),.o_profile_legal(write_legal) // 共享表使用真实发送事件；holding使用全部交付结束事件
); // 结束Write事务保持模块连接
 generate if(RAS_ENABLE==0)begin:gen_legacy // 默认保持唯一旧表与255容量能力。
 wire unused_candidate,unused_release_ready;wire [7:0] unused_as,unused_ag,unused_cs,unused_ce,unused_cg; // 未启用RAS的真实观察不参与旧协议。
 wire [CAPACITY-1:0] unused_oa,unused_or;wire [CAPACITY*2-1:0] unused_op;wire [CAPACITY*11-1:0] unused_ot; // 显式连接全部追加所有者端口。
 wire [CAPACITY*8-1:0] unused_oe,unused_og;wire [CAPACITY*3-1:0] unused_ob; // 默认Tag时期宽度仍为八位。
 wire unused_disabled_ras=^{IS_SWITCH,i_ras_isolate,i_ras_link_down,i_ras_link_up,i_ras_init_done,i_ras_drop,i_ras_recover_valid,i_ras_recover_epoch,i_rx_epoch_drained,i_owner_events_drained}; // 默认分支明确不解释RAS事件。
 localparam NATIVE_SLOT_WIDTH=(CAPACITY<=2)?1:(CAPACITY<=4)?2:(CAPACITY<=8)?3:(CAPACITY<=16)?4:(CAPACITY<=32)?5:(CAPACITY<=64)?6:(CAPACITY<=128)?7:8; // 与实际Tag表一致的槽索引宽度。
 wire [NATIVE_SLOT_WIDTH-1:0] native_complete_index=unused_cs[NATIVE_SLOT_WIDTH-1:0]; // 只截取由真实表产生的合法槽位。
 reg [183:0] native_payloads[0:CAPACITY-1];reg [1:0] native_vcs[0:CAPACITY-1],native_ports[0:CAPACITY-1];
 reg [CAPACITY-1:0] native_pools;reg [3:0] native_poisons[0:CAPACITY-1],native_data_pools[0:CAPACITY-1];
 integer ni;reg bad_vc;
 assign native_response_vc_bad=((NATIVE_REQUEST_ENABLE!=0)&&bad_vc)||((NATIVE_RAW_ENABLE!=0)&&(i_response_header[59:58]!=i_response_vc));
 always @* begin
 bad_vc=1'b0;
 for(ni=0;ni<CAPACITY;ni=ni+1)if(unused_oa[ni]&&(native_ports[ni]==i_response_port)&&(native_payloads[ni][97:87]==i_response_tag)&&(native_vcs[ni]!=i_response_vc))bad_vc=1'b1;
 end
 genvar ns;
 for(ns=0;ns<CAPACITY;ns=ns+1)begin:gen_native_context
 always @(posedge i_clk)begin
 if(!i_rstn)begin native_payloads[ns]<=184'd0;native_vcs[ns]<=2'd0;native_ports[ns]<=2'd0;native_pools[ns]<=1'b0;native_poisons[ns]<=4'd0;native_data_pools[ns]<=4'd0;end
 else if((NATIVE_REQUEST_ENABLE!=0)&&request_fire&&(unused_as==ns[7:0]))begin native_payloads[ns]<=i_native_payload;native_vcs[ns]<=i_native_vc;native_ports[ns]<=i_request_port;native_pools[ns]<=i_native_pool;native_poisons[ns]<=i_native_poison;native_data_pools[ns]<=i_native_data_pools;end
 end
 end
 assign o_native_complete_payload=((NATIVE_REQUEST_ENABLE!=0)&&o_complete_valid)?native_payloads[native_complete_index]:184'd0;
 assign o_native_complete_vc=((NATIVE_REQUEST_ENABLE!=0)&&o_complete_valid)?native_vcs[native_complete_index]:2'd0;
 assign o_native_complete_pool=(NATIVE_REQUEST_ENABLE!=0)&&o_complete_valid&&native_pools[native_complete_index];
 assign o_native_complete_poison=((NATIVE_REQUEST_ENABLE!=0)&&o_complete_valid)?native_poisons[native_complete_index]:4'd0;
 assign o_native_complete_data_pools=((NATIVE_REQUEST_ENABLE!=0)&&o_complete_valid)?native_data_pools[native_complete_index]:4'd0;
 assign o_complete_cancel=1'b0;assign o_complete_is_dummy=1'b0;assign o_complete_slot=2'd0; // 默认应用接口没有撤销语义。
 assign o_complete_epoch={EPOCH_WIDTH{1'b0}};assign o_complete_generation={GENERATION_WIDTH{1'b0}};assign o_complete_beats=3'd0; // 追加观察输出不伪造RAS身份。
 assign o_ras_isolated={NUM_PORTS{1'b0}};assign o_ras_epoch={EPOCH_WIDTH{1'b0}};assign o_ras_recovered=1'b0;assign o_ras_recover_ready=1'b0; // 默认模式不解释RAS管理输入。
 assign o_ras_ledger_count=8'd0;assign ras_blocked=1'b0;assign o_ras_dummy_done_fire=1'b0;assign o_ras_dummy_done_slot=2'd0; // 无未启用账本。
endpoint_tag_table #(.CAPACITY(CAPACITY),.NUM_PORTS(NUM_PORTS),.WRITE_ENABLE(1),.FULL_READ_ENABLE(FULL_READ_ENABLE),.NATIVE_ID_ENABLE(NATIVE_REQUEST_ENABLE),.NATIVE_RAW_ENABLE(NATIVE_RAW_ENABLE),.MESSAGE_ENABLE(MESSAGE_ENABLE),.ORDERING_ENABLE(ORDERING_ENABLE),.ORDER_TOKEN_WIDTH(ORDER_TOKEN_WIDTH),.ORDER_EPOCH_WIDTH(ORDER_EPOCH_WIDTH)) Tags_Inst( // 唯一共享Tag表显式开启Read与Write种类比较
 .i_clk(i_clk),.i_rstn(i_rstn),.i_local_id(selected_local_id), // 本地响应目的ID与全部子模块同复位域
 .i_allocate_is_message(selected_message),.o_complete_is_message(o_native_complete_is_message),.o_complete_response_beats(o_native_complete_response_beats),.o_complete_raw_poison(o_native_complete_raw_poison),
 .i_response_header(i_response_header),.o_complete_raw_data(o_native_complete_raw_data),.o_complete_raw_headers(o_native_complete_raw_headers),
 .i_allocate_valid(allocate_valid),.i_allocate_port(i_request_port),.i_allocate_tag(selected_request_tag),.i_allocate_is_write(selected_reply_write),.o_allocate_ready(table_ready), // 预约时同时保存完整身份及请求种类
 .i_allocate_order_epoch(i_request_order_epoch),.i_allocate_order_token(i_request_order_token),.o_complete_order_epoch(o_complete_order_epoch),.o_complete_order_token(o_complete_order_token),.i_order_port_reset(i_order_port_reset),
 .i_sent_valid(sent_event),.i_sent_port(r_port),.i_sent_tag(r_tag), // 发送事件使用holding中身份而不使用变化中的应用输入
 .i_response_valid(i_response_valid&&!native_response_vc_bad),.i_response_is_write(i_response_is_write),.o_response_ready(o_response_ready), // 接收器提交完整响应并给出Read或Write类型
 .i_response_port(i_response_port),.i_response_tag(i_response_tag),.i_response_dst(i_response_dst),.i_response_status(i_response_status), // 共享表检查完整端口Tag和本地目的ID与状态
 .i_response_offset(i_response_offset),.i_response_last(i_response_last),.i_response_num_beats(i_response_num_beats), // Read检查单Beat结束条件，Write忽略无效偏移和LAST
 .i_response_data(i_response_data),.i_response_data_error(i_response_data_error), // Read拥有完整结果数据，Write不提交数据
 .o_complete_valid(o_complete_valid),.i_complete_ready(i_complete_ready),.o_complete_is_write(o_complete_is_write), // 应用握手同时退休完成与其保存的kind
 .o_complete_port(o_complete_port),.o_complete_tag(o_complete_tag),.o_complete_status(o_complete_status),.o_complete_data(o_complete_data),.o_complete_data_valid(o_complete_data_valid), // 完成结果与完整身份由锁定表槽提供
 .i_allocate_read_num_beats(selected_reply_num),.i_allocate_read_mask(selected_reply_mask), // 实际原始Read几何供默认表保存。
 .o_complete_data_full(o_complete_data_full),.o_complete_mask(o_complete_mask), // 保留默认完整结果及相对字节mask。
 .i_owner_allocate_permit(1'b1),.i_owner_epoch(8'd0),.o_allocate_candidate_valid(unused_candidate),.o_allocate_slot(unused_as),.o_allocate_generation(unused_ag), // 默认模式禁用追加所有者控制。
 .o_owner_active(unused_oa),.o_owner_read(unused_or),.o_owner_port(unused_op),.o_owner_tag(unused_ot),.o_owner_epoch(unused_oe),.o_owner_generation(unused_og),.o_owner_beats(unused_ob), // 明确未使用的观察。
 .o_complete_slot(unused_cs),.o_complete_epoch(unused_ce),.o_complete_generation(unused_cg),.i_owner_isolated({NUM_PORTS{1'b0}}),.i_complete_cancel(1'b0), // 默认应用无撤销输入。
 .i_dummy_release_valid(1'b0),.o_dummy_release_ready(unused_release_ready),.i_dummy_release_slot(8'd0),.i_dummy_release_epoch(8'd0),.i_dummy_release_generation(8'd0),.i_dummy_release_port(2'd0),.i_dummy_release_tag(11'd0),.i_owner_epoch_advance(1'b0), // 默认无外部dummy释放。
 .o_error(table_error),.o_count(o_count) // 导出预约计数及非法有效事件诊断
); // 结束唯一共享Tag表连接
 end else begin:gen_ras
 assign o_complete_order_epoch={ORDER_EPOCH_WIDTH{1'b0}};assign o_complete_order_token={ORDER_TOKEN_WIDTH{1'b0}};
 assign o_native_complete_raw_data=2048'd0;assign o_native_complete_raw_headers=256'd0;
 assign o_native_complete_is_message=1'b0;assign o_native_complete_response_beats=3'd0;assign o_native_complete_raw_poison=4'd0;
 assign native_response_vc_bad=1'b0;assign o_native_complete_payload=184'd0;assign o_native_complete_vc=2'd0;assign o_native_complete_pool=1'b0;assign o_native_complete_poison=4'd0;assign o_native_complete_data_pools=4'd0; // 以实际组合替换原唯一Tag实例，没有第二张镜像表。
 wire unused_retire;wire [CAPACITY-1:0] unused_owner_active;wire [CAPACITY*GENERATION_WIDTH-1:0] unused_owner_generation; // 唯一所有者观察无复制。
 wire app_read; // 实际应用种类反相别名。
 assign o_complete_is_write=!app_read;assign o_complete_data=o_complete_data_full[511:0]; // 保留原512位别名。
 ras_tag_owner_integration #(.PORTS(NUM_PORTS),.CAPACITY(CAPACITY),.IS_SWITCH(IS_SWITCH),.EPOCH_WIDTH(EPOCH_WIDTH),.GENERATION_WIDTH(GENERATION_WIDTH)) Tags_Inst( // 原始slot和世代只由真实Tag表生成。
 .i_clk(i_clk),.i_rstn(i_rstn),.i_local_id(selected_local_id),.i_allocate_valid(allocate_valid),.o_allocate_ready(table_ready), // 同一个实际request_fire创建holding和两个owner义务。
 .i_allocate_port(i_request_port),.i_allocate_tag(selected_request_tag),.i_allocate_is_write(selected_request_is_write),.i_allocate_read_num_beats(read_num_beats),.i_allocate_read_mask(read_be>>(64*selected_request_address[7:6])), // 保存实际编码几何。
 .i_sent_valid(sent_event),.i_sent_port(r_port),.i_sent_tag(r_tag), // 实际发送反馈来自当前holding。
 .i_response_valid(i_response_valid&&!native_response_vc_bad),.o_response_ready(o_response_ready),.i_response_port(i_response_port),.i_response_tag(i_response_tag),.i_response_dst(i_response_dst), // 真正接收字段原样进入唯一Tag表。
 .i_response_status(i_response_status),.i_response_offset(i_response_offset),.i_response_last(i_response_last),.i_response_num_beats(i_response_num_beats),.i_response_data(i_response_data),.i_response_data_error(i_response_data_error),.i_response_is_write(i_response_is_write), // 全宽逐Beat接收事件。
 .i_isolate(i_ras_isolate),.i_link_down(i_ras_link_down),.i_link_up(i_ras_link_up),.i_init_done(i_ras_init_done),.i_drop(i_ras_drop), // 单一管理所有者。
 .i_rx_epoch_drained(i_rx_epoch_drained&&!i_response_valid),.i_tx_epoch_drained(qualified_tx_ack&&o_tx_local_drained),.i_owner_events_drained(i_owner_events_drained&&!sent_event&&!feedback_error&&!r_feedback_error), // 外部资格不能绕过真实本地残留。
 .i_recover_valid(i_ras_recover_valid),.i_recover_epoch(i_ras_recover_epoch),.o_recover_ready(o_ras_recover_ready),.o_recovered(o_ras_recovered),.o_epoch(o_ras_epoch),.o_isolated(o_ras_isolated), // 原账本拥有时期推进。
 .i_app_ready(i_complete_ready),.o_app_valid(o_complete_valid),.o_app_cancel(o_complete_cancel),.o_app_is_dummy(o_complete_is_dummy),.o_app_slot(o_complete_slot),.o_app_port(o_complete_port),.o_app_tag(o_complete_tag), // 可撤销整笔完成不是普通ready/valid接口。
 .o_app_epoch(o_complete_epoch),.o_app_generation(o_complete_generation),.o_app_read(app_read),.o_app_beats(o_complete_beats),.o_app_status(o_complete_status), // 原始身份与完整几何。
 .o_app_data(o_complete_data_full),.o_app_mask(o_complete_mask),.o_app_data_valid(o_complete_data_valid),.o_retire(unused_retire),.o_tag_count(o_count),.o_ledger_count(o_ras_ledger_count), // 完整2048位及256字节mask无截断。
 .o_owner_active(unused_owner_active),.o_owner_generation(unused_owner_generation),.o_dummy_done_fire(o_ras_dummy_done_fire),.o_dummy_done_slot(o_ras_dummy_done_slot),.o_error(table_error),.o_blocked(ras_blocked) // 联合done由实际双账本资格决定。
 ); // 结束真实所有者子链。
 end endgenerate // 默认与RAS模式互斥，始终只有一张Tag表。
 always @(posedge i_clk)begin // 非法停止反馈保持诊断，不提前推进Tag状态。
 if(!i_rstn)r_feedback_error<=1'b0;else if(feedback_error)r_feedback_error<=1'b1; // 只有共同reset可清非法反馈。
 end // 结束反馈故障保持。
always @(posedge i_clk)begin // 单一同步域维护类别零Header和Data的先后所有权
 if(!i_rstn)begin // 同步复位取消当前holding身份和种类
  r_pending<=1'b0;r_is_write<=1'b0;r_captured<=1'b0;r_port<=2'd0;r_tag<=11'd0;r_control<=256'd0; // 复位后无旧请求Header或种类残留有效
 end else begin // 正常周期只根据实际请求或交付事件更新
  if(request_fire)begin // 接受一个新请求时锁定Read或Write种类
   r_pending<=1'b1;r_is_write<=selected_request_is_write;r_captured<=1'b0; // 新holding的捕获阶段始终从未捕获开始
   r_port<=i_request_port;r_tag<=selected_request_tag;r_control<=read_control; // 保存完整本地身份及Read候选字段
  end // 结束原子请求身份保存
  if(read_capture)r_captured<=1'b1; // Read捕获后撤下源valid但仍等待实际发送
  if(local_cancel||(r_is_write&&write_done)||read_sent)begin r_pending<=1'b0;r_captured<=1'b0;end // Write全部交付或Read实际发送后开放下个有序请求
 end // 结束正常holding所有权更新
end // 结束混合发起同步寄存器
generate if(((RAS_ENABLE!=0)&&(RAS_ENABLE!=1))||((NATIVE_REQUEST_ENABLE!=0)&&((RAS_ENABLE!=0)||(FULL_READ_ENABLE==0))))begin:gen_invalid_ras // 明确禁止未知模式参数。
 endpoint_request_formatter_ras_parameter_invalid Invalid_Inst(); // 非法配置展开失败。
end endgenerate // 结束配置检查。
generate if((NATIVE_RAW_ENABLE!=0)&&((NATIVE_RAW_ENABLE!=1)||(NATIVE_REQUEST_ENABLE!=1)||(FULL_READ_ENABLE!=1)||(RAS_ENABLE!=0)))begin:invalid_native_raw
 native_formatter_raw_requires_native_full_read_without_ras Invalid_Config();
end endgenerate
generate if(MESSAGE_ENABLE!=0&&((MESSAGE_ENABLE!=1)||(NATIVE_REQUEST_ENABLE!=1)||(NATIVE_RAW_ENABLE!=1)||(FULL_READ_ENABLE!=1)||(RAS_ENABLE!=0)))begin:bad_message_profile
 endpoint_request_formatter_message_configuration_invalid u_bad(); // 明确拒绝缺少原始身份/响应所有者的组合。
end endgenerate
endmodule // 结束endpoint_request_formatter模块
`default_nettype wire // 恢复外围默认网络声明方式
