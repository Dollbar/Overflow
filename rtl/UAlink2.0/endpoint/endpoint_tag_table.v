`timescale 1ns/1ps // 唯一owner与RAS组合使用相同时钟时间单位。
// Common 2.0完整(port,Tag)身份与完整响应结果预约；四槽为本地实现容量，不限制规范Tag取值。
`default_nettype none // 禁止未声明网络隐藏匹配或握手错误
module endpoint_tag_table #(parameter integer CAPACITY=4, NUM_PORTS=1, WRITE_ENABLE=0, FULL_READ_ENABLE=0,RAS_OWNER_ENABLE=0,EPOCH_WIDTH=8,GENERATION_WIDTH=8,NATIVE_ID_ENABLE=0,NATIVE_RAW_ENABLE=0,parameter integer MESSAGE_ENABLE=0,parameter integer ORDERING_ENABLE=0,parameter integer ORDER_TOKEN_WIDTH=16,parameter integer ORDER_EPOCH_WIDTH=8)( // Tag表模块：预约、实际发送、完整响应和应用退休四阶段所有权
 input wire i_clk,i_rstn, // 单时钟与同步低有效复位；不表示Link Down恢复
 input wire [9:0] i_local_id, // 当前复位时期稳定的本地响应目的标识
 input wire i_allocate_valid, // 调用方已检查对应Read或Write字段profile的预约请求
 input wire [1:0] i_allocate_port, // 本地物理端口身份域
 input wire [10:0] i_allocate_tag, // 完整十一位Tag，不使用低位直接索引
 output wire o_allocate_ready, // 空闲槽与未占用身份同时满足才可预约
 input wire i_sent_valid, // 对应请求Header已经被真实发送器消费
 input wire [1:0] i_sent_port, // 发送事件对应端口
 input wire [10:0] i_sent_tag, // 发送事件对应完整Tag
 input wire i_response_valid, // Read必须已保存完整两个Data半Flit，Write响应无Data
 output wire o_response_ready, // 已预约结果容量使响应消费独立于应用背压
 input wire [1:0] i_response_port, // 响应进入的本地端口
 input wire [10:0] i_response_tag, // 线上响应完整Tag
 input wire [9:0] i_response_dst, // 验证响应路由到当前Originator
 input wire [3:0] i_response_status, // Read支持零三，Write支持零二三六八
 input wire [1:0] i_response_offset, // Read单Beat偏移零；Write忽略此字段
 input wire i_response_last, // Read单Beat必须完整结束；Write忽略此字段
 input wire [1:0] i_response_num_beats, // 单个六十四字节响应LEN为零
 input wire [511:0] i_response_data, // 完整自然字节序响应结果
 input wire i_response_data_error, // 首阶段不把DataError接纳为完成
 output wire o_complete_valid, // 锁定一条已经完整接收的应用完成
 input wire i_complete_ready, // 应用接纳才释放Tag和结果槽
 output wire [1:0] o_complete_port, // 完成所属本地端口
 output wire [10:0] o_complete_tag, // 完整应用Tag
 output wire [3:0] o_complete_status, // 成功或地址译码错误状态
 output wire [511:0] o_complete_data, // 错误状态强制输出零，避免成功数据误提交
 output wire o_complete_data_valid, // 仅OKAY完成携带可提交数据
 output wire o_error, // 非法有效事件被消费或拒绝后的当周期本地诊断
 output wire [7:0] o_count, // 全部预约数，含未发送、等待响应和完成背压
 input wire i_allocate_is_write,i_response_is_write, // 尾部追加kind端口；WRITE_ENABLE零忽略以兼容原Read入口
 output wire o_complete_is_write, // 应用完成保留请求种类
 input wire [1:0] i_allocate_read_num_beats, // 完整Read预约的总Beat数减一；默认模式忽略
 input wire [255:0] i_allocate_read_mask, // 相对首个自然对齐Beat的字节有效图
 output wire [2047:0] o_complete_data_full, // 完整Read结果；默认模式仅低512位有效
 output wire [255:0] o_complete_mask, // 成功Read有效字节；错误和Write均清零
 input wire i_owner_allocate_permit, // RAS模式实际义务预约资格。
 input wire [EPOCH_WIDTH-1:0] i_owner_epoch, // 实际账本epoch在预约沿保存。
 output wire o_allocate_candidate_valid, // 独立于permit和valid的真实空槽候选。
 output wire [7:0] o_allocate_slot, // 完整零扩展槽号，不隐式截断。
 output wire [GENERATION_WIDTH-1:0] o_allocate_generation, // 下一次预约的实际世代。
 output wire [CAPACITY-1:0] o_owner_active,o_owner_read, // 唯一Tag所有者的完整条目状态。
 output wire [CAPACITY*2-1:0] o_owner_port, // 紧密排列完整物理port。
 output wire [CAPACITY*11-1:0] o_owner_tag, // 紧密排列完整Tag。
 output wire [CAPACITY*EPOCH_WIDTH-1:0] o_owner_epoch, // 原始预约epoch。
 output wire [CAPACITY*GENERATION_WIDTH-1:0] o_owner_generation, // 原始预约世代直到真实释放。
 output wire [CAPACITY*3-1:0] o_owner_beats, // 一至四Beat真实义务几何。
 output wire [7:0] o_complete_slot, // 当前完整结果的真实槽号。
 output wire [EPOCH_WIDTH-1:0] o_complete_epoch, // 当前完整结果原epoch。
 output wire [GENERATION_WIDTH-1:0] o_complete_generation, // 当前完整结果原世代。
 input wire [NUM_PORTS-1:0] i_owner_isolated, // 含当前触发沿的实际隔离状态。
 input wire i_complete_cancel, // 撤销当前payload但保留Tag与义务。
 input wire i_dummy_release_valid, // 实际生成器done与两个owner联合提交。
 output wire o_dummy_release_ready, // 沿前完整身份合法，不依赖valid。
 input wire [7:0] i_dummy_release_slot, // 完整槽号拒绝高位别名。
 input wire [EPOCH_WIDTH-1:0] i_dummy_release_epoch, // done捕获的原epoch。
 input wire [GENERATION_WIDTH-1:0] i_dummy_release_generation, // done捕获的原世代。
 input wire [1:0] i_dummy_release_port, // done原完整port。
 input wire [10:0] i_dummy_release_tag, // done原完整Tag。
 input wire i_owner_epoch_advance, // 经过排空资格的共同新epoch握手。
 input wire [63:0] i_response_header, // 来自真实响应接收器的完整单拍Header，与typed字段必须一致。
 output wire [2047:0] o_complete_raw_data, // 原始自然Data，只在同一Tag完整完成时公开；不是成功数据资格。
 output wire [255:0] o_complete_raw_headers // 每Tag真实响应到达顺序；不规定不同Tag调度顺序。

,input wire i_allocate_is_message // 原Tag预约保存的消息义务，不从后来的响应猜测。
,output wire o_complete_is_message,output wire [2:0] o_complete_response_beats,output wire [3:0] o_complete_raw_poison, // 与锁定完成使用相同真实slot。
 input wire[ORDER_EPOCH_WIDTH-1:0] i_allocate_order_epoch,input wire[ORDER_TOKEN_WIDTH-1:0] i_allocate_order_token,output wire[ORDER_EPOCH_WIDTH-1:0] o_complete_order_epoch,output wire[ORDER_TOKEN_WIDTH-1:0] o_complete_order_token, // 普通ordering身份与同一Tag槽共同预约和应用退休。
 input wire[NUM_PORTS-1:0] i_order_port_reset // ordering模式逐Port协调取消Tag槽；关闭模式完全忽略。
); // 表项生命周期接口完全局限于当前同步复位时期
localparam CONFIG_LEGAL=(CAPACITY>0)&&(CAPACITY<=255)&&((NUM_PORTS==1)||(NUM_PORTS==2)||(NUM_PORTS==4))&&((ORDERING_ENABLE==0)||((ORDERING_ENABLE==1)&&(ORDER_TOKEN_WIDTH>=2)&&(ORDER_TOKEN_WIDTH<=30)&&(ORDER_EPOCH_WIDTH>=1)&&(ORDER_EPOCH_WIDTH<=30))); // 计数宽度及端口域的局部参数范围
localparam TABLE_DEPTH=CAPACITY; // 静态槽数用于有界展开和独立lint核对
localparam SLOT_WIDTH=(CAPACITY<=2)?1:(CAPACITY<=4)?2:(CAPACITY<=8)?3:(CAPACITY<=16)?4:(CAPACITY<=32)?5:(CAPACITY<=64)?6:(CAPACITY<=128)?7:8; // 精确槽索引宽度防止隐式截断
reg r_active[0:CAPACITY-1],r_sent[0:CAPACITY-1],r_done[0:CAPACITY-1]; // 每槽预约、真实发送和完整响应状态
reg r_suppressed[0:CAPACITY-1]; // 取消payload后仍拥有事务义务。
reg [EPOCH_WIDTH-1:0] r_epoch[0:CAPACITY-1]; // 真实预约时期保持至释放。
reg [GENERATION_WIDTH-1:0] r_generation[0:CAPACITY-1]; // 释放不清世代，最大值不回绕。
reg [ORDER_EPOCH_WIDTH-1:0] r_order_epoch[0:CAPACITY-1];reg [ORDER_TOKEN_WIDTH-1:0] r_order_token[0:CAPACITY-1]; // ordering身份不由Tag推导。
wire [3:0] isolated_ports; // 静态最大四端口安全索引。
wire complete_cancel,release_fire; // 取消和真实done分离。
wire [3:0] order_reset_ports;wire order_complete_cancel;reg [7:0] order_cancel_count; // ordering逐Port取消与正常应用退休分离。
reg generation_exhausted; // 沿前空槽全部耗尽时诊断不能回绕。
reg release_eligible; // 完整扫描避免八位slot越界寻址。
integer release_index; // 常量槽数遍历。
assign isolated_ports=(RAS_OWNER_ENABLE!=0)?{{(4-NUM_PORTS){1'b0}},i_owner_isolated}:4'd0; // 关闭模式完全忽略新增输入。
assign order_reset_ports=(ORDERING_ENABLE!=0)?{{(4-NUM_PORTS){1'b0}},i_order_port_reset}:4'd0; // 固定四位域使保存port的动态索引始终安全。
assign order_complete_cancel=(ORDERING_ENABLE!=0)&&r_complete_valid&&order_reset_ports[r_port[r_complete_slot]]; // reset同拍不公开应用完成。
assign complete_cancel=(RAS_OWNER_ENABLE!=0)&&r_complete_valid&&(i_complete_cancel||isolated_ports[r_port[r_complete_slot]]||r_suppressed[r_complete_slot]); // 同沿隔离先于正常ready。
always @* begin // ready独立valid并完整比较身份。
 release_eligible=1'b0;generation_exhausted=1'b0; // 无匹配时拒绝释放。
 for(release_index=32'd0;release_index<TABLE_DEPTH;release_index=release_index+32'd1)begin // 仅遍历实际槽。
  if(!r_active[release_index]&&(r_generation[release_index]=={GENERATION_WIDTH{1'b1}}))generation_exhausted=1'b1; // 空槽世代已经到最大值。
  if((i_dummy_release_slot==release_index[7:0])&&r_active[release_index]&&r_suppressed[release_index]&&(r_epoch[release_index]==i_dummy_release_epoch)&&(r_generation[release_index]==i_dummy_release_generation)&&(r_port[release_index]==i_dummy_release_port)&&(r_tag[release_index]==i_dummy_release_tag))release_eligible=1'b1; // 完整原始身份不可别名。
 end // 结束释放资格搜索。
end // 结束独立组合资格。
assign o_dummy_release_ready=i_rstn&&(RAS_OWNER_ENABLE!=0)&&release_eligible; // 未知或重复done不接纳。
assign release_fire=i_dummy_release_valid&&o_dummy_release_ready; // 唯一dummy Tag释放事件。
assign o_allocate_candidate_valid=i_rstn&&!allocate_bad&&free_found; // 不依赖下游permit避免组合环。
assign o_allocate_slot={{(8-SLOT_WIDTH){1'b0}},free_slot}; // 原始槽完整零扩展。
assign o_allocate_generation=r_generation[free_slot]+{{(GENERATION_WIDTH-1){1'b0}},1'b1}; // 仅有效候选的下一世代可使用。
assign o_complete_slot={{(8-SLOT_WIDTH){1'b0}},r_complete_slot}; // 锁定的完整结果槽。
assign o_complete_epoch=r_epoch[r_complete_slot]; // 原始结果epoch不临时重贴。
assign o_complete_generation=r_generation[r_complete_slot]; // 原始结果generation不临时重贴。
reg r_is_write[0:CAPACITY-1];
reg r_is_message[0:CAPACITY-1];reg [3:0] r_response_poison[0:CAPACITY-1]; // Message能力和实际响应Poison随唯一(port,Tag)保存。
wire allocate_is_write; // 声明allocate_is_write，旧Read配置不采纳新增kind输入
assign allocate_is_write=(WRITE_ENABLE!=0)&&i_allocate_is_write; // 旧Read配置不采纳新增kind输入
wire response_is_write; // 声明response_is_write，混合配置才使用收到的响应种类
assign response_is_write=(WRITE_ENABLE!=0)&&i_response_is_write; // 混合配置才使用收到的响应种类
reg [1:0] r_port[0:CAPACITY-1]; // 槽内保留本地端口身份
reg [9:0] r_response_dst[0:CAPACITY-1]; // 原生模式按实际预约捕获Src，响应不能借后来全局ID。
reg [10:0] r_tag[0:CAPACITY-1]; // 槽内完整Tag支持任意稀疏分配
reg [3:0] r_status[0:CAPACITY-1]; // 已保存响应状态
localparam RESULT_WIDTH=(FULL_READ_ENABLE!=0)?2048:512; // 默认配置不额外保留完整Read存储
reg [RESULT_WIDTH-1:0] r_data[0:CAPACITY-1]; // 预约时即拥有的完整结果空间
reg [1:0] r_read_num_beats[0:CAPACITY-1]; // 预约时保存预期响应几何
reg [255:0] r_read_mask[0:CAPACITY-1]; // 预约时保存完整相对字节mask
reg [3:0] r_seen[0:CAPACITY-1]; // 各响应Beat只能写入一次
reg r_multi[0:CAPACITY-1]; // 首Beat固定本事务响应模式
wire [3:0] expected_seen,received_seen; // 全部预期Beat与当前沿后的候选覆盖
wire read_full_legal,status_ordinary; // 完整Read语义和普通五状态
assign expected_seen=4'hf>>(2'd3-r_read_num_beats[response_slot]); // 总数一至四个对应低位连续位图
assign received_seen=r_seen[response_slot]|(4'b0001<<i_response_offset); // 候选位图仅合法响应才提交
assign status_ordinary=(i_response_status==0)||(i_response_status==2)||(i_response_status==3)||(i_response_status==6)||(i_response_status==8); // 普通单播状态集合
wire response_status_legal=((MESSAGE_ENABLE!=0)&&r_is_message[response_slot])?(!response_is_write||(i_response_status!=4'hf)):status_ordinary; // Vendor Read状态保留全域，Write15不当普通完成。
assign read_full_legal=response_status_legal&&(i_response_offset<=r_read_num_beats[response_slot])&& // OFFSET相对整个Read请求
 !r_seen[response_slot][i_response_offset]&& // 已接收Beat不能重复覆盖
 ((i_response_num_beats==0)||(i_response_num_beats==r_read_num_beats[response_slot]))&& // Single或完整Multi，不能拆成局部burst
 ((r_seen[response_slot]==0)||((i_response_status==r_status[response_slot])&& // 所有Beat必须保留同一完成状态
 (r_multi[response_slot]==(i_response_num_beats!=0))))&& // 首Beat之后不能切换响应模式
 ((i_response_num_beats==0)||(r_seen[response_slot]==((4'b0001<<i_response_offset)-4'b0001)))&& // Multi从零开始按序，Single允许任意顺序
 (i_response_last==(received_seen==expected_seen)); // LAST必须与全部且仅全部Beat收齐同时发生
wire [255:0] response_mask_shifted; // 当前Beat的相对字节mask窗口
reg [511:0] response_masked_data; // 先组合清零无效lane，再一次写入完整Beat
integer response_byte; // 固定64字节组合循环
assign response_mask_shifted=r_read_mask[response_slot]>>({30'd0,i_response_offset}*32'd64); // OFFSET只选择所属Beat字节
always @* begin // 避免逐字节动态写入整2048位寄存器形成冗余中间总线
 response_masked_data=512'd0; // 错误和未选字节默认为零
 for(response_byte=32'd0;response_byte<32'd64;response_byte=response_byte+32'd1)begin // 固定lane独立参与mask
  if(response_mask_shifted[response_byte]&&(i_response_status==0)&&!i_response_data_error) // 本地API策略，线上未选lane不要求零
   response_masked_data[response_byte*8 +: 8]=i_response_data[response_byte*8 +: 8]; // 有效字节保留原始位置
 end // 结束字节mask
end // 结束单Beat数据组合
reg [7:0] r_count; // 活跃预约累计，包括等待应用退休的完成
reg r_complete_valid; // 已锁定的完成不能被后来较低槽完成替换
reg [SLOT_WIDTH-1:0] r_complete_slot; // 背压期间稳定的完成槽选择
reg free_found,allocate_duplicate,sent_found,response_found,done_found; // 各独立事件以沿前状态并行搜索
reg [SLOT_WIDTH-1:0] free_slot,sent_slot,response_slot,done_slot; // 槽编号只用于本地存储寻址
integer scan_slot; // 静态有界遍历变量不承担协议身份
integer cancel_slot; // 独立取消计数遍历变量，避免组合过程共享临时状态。
wire response_legal,sent_legal,allocate_bad,allocate_fire,retire_fire;
wire native_header_legal=(NATIVE_RAW_ENABLE==0)||((i_response_header[63:60]==4'd2)&&(i_response_header[57:47]==i_response_tag)&&(i_response_header[25:16]==i_response_dst)&&(i_response_header[41:38]==i_response_status)&&(i_response_header[37]==!response_is_write)&&(i_response_num_beats==2'd0)&&(i_response_header[45:44]==2'd0)&&(response_is_write||((i_response_header[43:42]==i_response_offset)&&(i_response_header[36]==i_response_last)))); // Raw保存绝不绕过原有sent/Tag/kind/status/offset/LAST检查。
 // 事件合法性与实际所有权转移
always @* begin // 独立搜索完整身份和空闲结果容量
 free_found=1'b0;allocate_duplicate=1'b0;sent_found=1'b0;response_found=1'b0;done_found=1'b0; // 每次组合求值从空结果开始
 free_slot={SLOT_WIDTH{1'b0}};sent_slot={SLOT_WIDTH{1'b0}};response_slot={SLOT_WIDTH{1'b0}};done_slot={SLOT_WIDTH{1'b0}}; // 未找到时的安全地址不用于有效写入
 for(scan_slot=32'd0;scan_slot<TABLE_DEPTH;scan_slot=scan_slot+32'd1) begin // 全部槽精确比较端口和完整Tag
  if(!r_active[scan_slot]&&!free_found&&((RAS_OWNER_ENABLE==0)||(r_generation[scan_slot]!={GENERATION_WIDTH{1'b1}})))begin free_found=1'b1;free_slot=scan_slot[SLOT_WIDTH-1:0];end // 保守选择沿前第一个空槽
  if(r_active[scan_slot]&&(r_port[scan_slot]==i_allocate_port)&&(r_tag[scan_slot]==i_allocate_tag)) allocate_duplicate=1'b1; // 完成但未退休的Tag仍不可复用
  if(r_active[scan_slot]&&(r_port[scan_slot]==i_sent_port)&&(r_tag[scan_slot]==i_sent_tag))begin sent_found=1'b1;sent_slot=scan_slot[SLOT_WIDTH-1:0];end // 发送事件不缩短身份宽度
  if(r_active[scan_slot]&&(r_port[scan_slot]==i_response_port)&&(r_tag[scan_slot]==i_response_tag))begin response_found=1'b1;response_slot=scan_slot[SLOT_WIDTH-1:0];end // 响应关联不包含debug-only源ID
  if(r_active[scan_slot]&&r_done[scan_slot]&&!done_found&&!r_suppressed[scan_slot]&&!isolated_ports[r_port[scan_slot]]&&!order_reset_ports[r_port[scan_slot]])begin done_found=1'b1;done_slot=scan_slot[SLOT_WIDTH-1:0];end // reset端口不再选择为应用完成。
 end // 结束固定容量搜索
end // 所有组合输出在每条路径均赋值
always @* begin // 全部被逐Port reset取消的真实Tag槽计数。
 order_cancel_count=8'd0;
 for(cancel_slot=32'd0;cancel_slot<TABLE_DEPTH;cancel_slot=cancel_slot+32'd1)begin
  if(r_active[cancel_slot]&&order_reset_ports[r_port[cancel_slot]])order_cancel_count=order_cancel_count+8'd1;
 end
end
assign allocate_bad=!CONFIG_LEGAL||({30'd0,i_allocate_port}>=NUM_PORTS)||order_reset_ports[i_allocate_port]||allocate_duplicate; // reset端口不得创建新owner。
assign o_allocate_ready=o_allocate_candidate_valid&&((RAS_OWNER_ENABLE==0)||i_owner_allocate_permit); // 不借用同拍退休槽，允许保守一拍气泡
assign allocate_fire=i_allocate_valid&&o_allocate_ready; // 仅此握手创建新预约和结果所有权
assign sent_legal=CONFIG_LEGAL&&sent_found&&!r_sent[sent_slot]&&!r_done[sent_slot]&&!r_suppressed[sent_slot]&&!isolated_ports[r_port[sent_slot]]; // 不允许未知或重复发送事件修改表项
assign response_legal=CONFIG_LEGAL&&response_found&&r_sent[response_slot]&&!r_done[response_slot]&&!r_suppressed[response_slot]&&!isolated_ports[r_port[response_slot]]&& // 响应必须属于沿前已真实发送且尚未完成的预约
 native_header_legal&&(i_response_dst==((NATIVE_ID_ENABLE!=0)?r_response_dst[response_slot]:i_local_id))&&(r_is_write[response_slot]==response_is_write)&& // 完整身份匹配后仍要求本地目的与请求种类一致
 (!i_response_data_error||((MESSAGE_ENABLE!=0)&&r_is_message[response_slot]&&!response_is_write))&& // 仅Message原预约允许带Poison返回；普通Read继续保持既有拒绝策略。
 (response_is_write?((i_response_num_beats==0)&&response_status_legal): // Write忽略无效OFFSET与LAST
 ((FULL_READ_ENABLE!=0)?read_full_legal: // 完整Read按预约几何、模式和逐Beat覆盖检查
 ((i_response_num_beats==0)&&((i_response_status==0)||(i_response_status==3))&&(i_response_offset==0)&&i_response_last))); // 默认行为保持单64B Read
assign o_response_ready=i_rstn&&CONFIG_LEGAL; // 非法响应也可被消费诊断，绝不占用新槽
assign o_complete_valid=i_rstn&&r_complete_valid&&!order_complete_cancel; // reset取消优先于最终应用可见完成。
assign o_complete_port=o_complete_valid?r_port[r_complete_slot]:2'd0; // 空闲完成输出清零
assign o_complete_tag=o_complete_valid?r_tag[r_complete_slot]:11'd0; // 只从锁定槽输出身份
assign o_complete_order_epoch=(o_complete_valid&&(ORDERING_ENABLE!=0))?r_order_epoch[r_complete_slot]:{ORDER_EPOCH_WIDTH{1'b0}};
assign o_complete_order_token=(o_complete_valid&&(ORDERING_ENABLE!=0))?r_order_token[r_complete_slot]:{ORDER_TOKEN_WIDTH{1'b0}};
assign o_complete_status=o_complete_valid?r_status[r_complete_slot]:4'd0; // 背压期间槽状态不可更改
assign o_complete_is_write=o_complete_valid&&r_is_write[r_complete_slot]; // 背压期间kind随锁定槽稳定
assign o_complete_is_message=o_complete_valid&&(MESSAGE_ENABLE!=0)&&r_is_message[r_complete_slot];
assign o_complete_response_beats=o_complete_valid?(r_is_write[r_complete_slot]?3'd1:({1'b0,r_read_num_beats[r_complete_slot]}+3'd1)):3'd0;
assign o_complete_raw_poison=o_complete_is_message?r_response_poison[r_complete_slot]:4'd0;
assign o_complete_data_valid=o_complete_valid&&(r_status[r_complete_slot]==4'd0)&&!r_is_write[r_complete_slot]&&!(|r_response_poison[r_complete_slot]); // 错误完成不提交成功数据
generate if (CAPACITY==4) begin: gen_parallel_complete // 四槽固定选择先计算各槽成功资格，减少晚到的状态选择控制整条宽总线。
 wire [3:0] data_select; // 每槽完整资格仍含实际complete valid、kind和全部状态位。
 wire [2047:0] selected_data;wire [255:0] selected_mask; // 连续逻辑也在首个reset沿前提供确定输出，不依赖always事件启动。
 wire [8191:0] data_terms;wire [1023:0] mask_terms; // 四个真实槽的完整并行数据项。
 genvar complete_index; // 四个真实结果槽独立并行选择。
 for(complete_index=0;complete_index<4;complete_index=complete_index+1)begin:gen_select
  assign data_select[complete_index]=o_complete_valid&&(r_complete_slot==complete_index[SLOT_WIDTH-1:0])&&(r_status[complete_index]==4'd0)&&!r_is_write[complete_index]&&!(|r_response_poison[complete_index]);
  assign data_terms[complete_index*2048+:2048]={2048{data_select[complete_index]}}&{{(2048-RESULT_WIDTH){1'b0}},r_data[complete_index]};
  assign mask_terms[complete_index*256+:256]={256{data_select[complete_index]}}&r_read_mask[complete_index];
 end
 assign selected_data=(data_terms[2047:0]|data_terms[4095:2048])|(data_terms[6143:4096]|data_terms[8191:6144]);
 assign selected_mask=(mask_terms[255:0]|mask_terms[511:256])|(mask_terms[767:512]|mask_terms[1023:768]);
 assign o_complete_data=selected_data[511:0];
 assign o_complete_data_full=selected_data;
 assign o_complete_mask=selected_mask;
end else begin:gen_legacy_complete // 其他容量保留原选择表达式和原始边界语义。
assign o_complete_data=o_complete_data_valid?r_data[r_complete_slot][511:0]:512'd0; // 非成功或无完成时数据全零
assign o_complete_data_full=o_complete_data_valid?{{(2048-RESULT_WIDTH){1'b0}},r_data[r_complete_slot]}:2048'd0; // 全部结果只从完成锁定槽产生
assign o_complete_mask=o_complete_data_valid?r_read_mask[r_complete_slot]:256'd0; // 错误与Write从不暴露成功字节
end endgenerate
assign retire_fire=o_complete_valid&&i_complete_ready&&!complete_cancel; // 应用接纳是保守Tag复用边界
assign o_count=i_rstn?r_count:8'd0; // 复位期间不暴露此前预约
assign o_error=i_rstn&&(((RAS_OWNER_ENABLE!=0)&&((i_dummy_release_valid&&!o_dummy_release_ready)||(i_owner_epoch_advance&&(r_count!=8'd0))||(i_allocate_valid&&!free_found&&generation_exhausted)))||(i_allocate_valid&&allocate_bad)||(i_sent_valid&&!sent_legal)||(i_response_valid&&!response_legal)); // 诊断不自动清理任何其他事务
always @(posedge i_clk) begin // 单一同步域持有计数和完成仲裁
 if(!i_rstn) begin // 本地复位取消当前所有权，完整恢复协议另行实现
  r_count<=8'd0;r_complete_valid<=1'b0;r_complete_slot<={SLOT_WIDTH{1'b0}}; // 清空容量和稳定完成选择
 end else begin // 所有事件合法性从该沿前状态判断
  r_count<=r_count+{7'd0,allocate_fire}-{7'd0,retire_fire}-{7'd0,release_fire}-order_cancel_count; // reset取消只减对应Port真实槽。
  if(retire_fire||complete_cancel||order_complete_cancel)r_complete_valid<=1'b0; // reset取消绝不冒充应用退休。
  else if(!r_complete_valid&&done_found)begin // 有背压时禁止替换已经锁定的完成
   r_complete_valid<=1'b1;r_complete_slot<=done_slot; // 锁定沿前已经完整保存的结果
  end // 结束稳定完成选择
 end // 结束计数与仲裁正常更新
end // 结束共享控制寄存器
 genvar slot;generate for(slot=32'd0;slot<TABLE_DEPTH;slot=slot+32'd1)begin:gen_slot // 每个结果槽由独立时序块唯一驱动
 assign o_owner_active[slot]=i_rstn&&r_active[slot]; // 真正唯一owner是否占用。
 assign o_owner_read[slot]=!r_is_write[slot]; // 保存的原请求种类。
 assign o_owner_port[slot*2+:2]=r_port[slot];assign o_owner_tag[slot*11+:11]=r_tag[slot]; // 保存完整身份。
 assign o_owner_epoch[slot*EPOCH_WIDTH+:EPOCH_WIDTH]=r_epoch[slot];assign o_owner_generation[slot*GENERATION_WIDTH+:GENERATION_WIDTH]=r_generation[slot]; // 原始时期与世代。
 assign o_owner_beats[slot*3+:3]=r_is_write[slot]?3'd1:({1'b0,r_read_num_beats[slot]}+3'd1); // 不从mask猜几何。
 localparam [SLOT_WIDTH-1:0] SLOT_INDEX=slot[SLOT_WIDTH-1:0]; // 综合展开时固定的精确宽度槽编号
 always @(posedge i_clk)begin // 本地槽状态和结果数据采用相同时钟
  if(!i_rstn)begin // 同步取消该槽预约和残留结果
   r_suppressed[slot]<=1'b0;r_epoch[slot]<={EPOCH_WIDTH{1'b0}};r_generation[slot]<={GENERATION_WIDTH{1'b0}}; // 清共同reset身份。
   r_active[slot]<=1'b0;r_sent[slot]<=1'b0;r_done[slot]<=1'b0; // 无预约、未发送、无完成
   r_is_message[slot]<=1'b0;r_response_poison[slot]<=4'd0;
   r_response_dst[slot]<=10'd0;r_is_write[slot]<=1'b0;r_port[slot]<=2'd0;r_tag[slot]<=11'd0;r_order_epoch[slot]<={ORDER_EPOCH_WIDTH{1'b0}};r_order_token[slot]<={ORDER_TOKEN_WIDTH{1'b0}};r_status[slot]<=4'd0;r_data[slot]<={RESULT_WIDTH{1'b0}}; // 清除旧时期身份和结果
  r_read_num_beats[slot]<=2'd0;r_read_mask[slot]<=256'd0;r_seen[slot]<=4'd0;r_multi[slot]<=1'b0; // 取消旧几何和部分收集
  end else begin // 本槽依据共享搜索的沿前结果独立更新
   if((RAS_OWNER_ENABLE!=0)&&i_owner_epoch_advance&&(r_count==8'd0))r_generation[slot]<={GENERATION_WIDTH{1'b0}}; // 仅全空安全epoch边界清世代。
   if(allocate_fire&&(free_slot==SLOT_INDEX))begin // 预约只写入沿前空闲槽
    r_active[slot]<=1'b1;r_sent[slot]<=1'b0;r_done[slot]<=1'b0; // 同次预约创建未发送且未完成的事务。
    r_suppressed[slot]<=1'b0;r_epoch[slot]<=(RAS_OWNER_ENABLE!=0)?i_owner_epoch:{EPOCH_WIDTH{1'b0}};if(RAS_OWNER_ENABLE!=0)r_generation[slot]<=r_generation[slot]+{{(GENERATION_WIDTH-1){1'b0}},1'b1}; // 原子创建唯一新世代； 新预约必须经历实际发送后才可完成
    r_is_message[slot]<=(MESSAGE_ENABLE!=0)&&i_allocate_is_message;r_response_poison[slot]<=4'd0;
    r_response_dst[slot]<=i_local_id;r_is_write[slot]<=allocate_is_write;r_port[slot]<=i_allocate_port;r_tag[slot]<=i_allocate_tag;r_order_epoch[slot]<=(ORDERING_ENABLE!=0)?i_allocate_order_epoch:{ORDER_EPOCH_WIDTH{1'b0}};r_order_token[slot]<=(ORDERING_ENABLE!=0)?i_allocate_order_token:{ORDER_TOKEN_WIDTH{1'b0}}; // 完整身份在预约沿捕获
    r_status[slot]<=4'd0;r_data[slot]<={RESULT_WIDTH{1'b0}}; // 新预约不暴露上一使用者数据
   r_read_num_beats[slot]<=((FULL_READ_ENABLE!=0)&&!allocate_is_write)?i_allocate_read_num_beats:2'd0; // 默认和Write不依赖新增输入
    r_read_mask[slot]<=allocate_is_write?256'd0:((FULL_READ_ENABLE!=0)?i_allocate_read_mask:{192'd0,64'hffffffffffffffff}); // 默认Read保持所有64字节有效
    r_seen[slot]<=4'd0;r_multi[slot]<=1'b0; // 新请求没有历史响应模式或Beat
   end // 结束本槽预约写入
   if(i_sent_valid&&sent_legal&&(sent_slot==SLOT_INDEX))r_sent[slot]<=1'b1; // 只有实际Header消费推进sent
   if(i_response_valid&&o_response_ready&&response_legal&&(response_slot==SLOT_INDEX))begin // 非法响应永不触发结果写入
    r_status[slot]<=i_response_status;
    if((MESSAGE_ENABLE!=0)&&r_is_message[slot]&&!response_is_write)r_response_poison[slot][i_response_offset]<=i_response_data_error; // 合法响应始终与本事务已有状态一致
    if((FULL_READ_ENABLE!=0)&&!response_is_write)begin // 完整Read逐Beat写入预约空间，未完成时不会公开
     r_done[slot]<=i_response_last; // LAST与覆盖检查共同控制完成
     r_seen[slot]<=received_seen;r_multi[slot]<=(i_response_num_beats!=0); // 保存已通过独立合法性检查的收集状态
     r_data[slot][i_response_offset*512 +: 512]<=response_masked_data; // 每Beat一次原子写入，其他已收Beat保持
    end else begin // 原单Beat Read与Write完成行为保持
     r_done[slot]<=1'b1; // 兼容模式响应或Write无额外Data可等待
     r_data[slot]<=(!response_is_write&&(i_response_status==4'd0))?{{(RESULT_WIDTH-512){1'b0}},i_response_data}:{RESULT_WIDTH{1'b0}}; // 错误响应虽完整接收但成功数据存储置零
    end // 结束按模式保存结果
   end // 结束完整响应捕获
   if((RAS_OWNER_ENABLE!=0)&&r_active[slot]&&(isolated_ports[r_port[slot]]||(i_complete_cancel&&r_complete_valid&&(r_complete_slot==SLOT_INDEX))))begin // 取消保留预约身份。
    r_suppressed[slot]<=1'b1;r_done[slot]<=1'b0;r_seen[slot]<=4'd0; // payload不再参与正常完成。
   end // 结束取消保留。
   if((retire_fire&&(r_complete_slot==SLOT_INDEX))||(release_fire&&(i_dummy_release_slot==slot[7:0]))||((ORDERING_ENABLE!=0)&&r_active[slot]&&order_reset_ports[r_port[slot]]))begin // reset协调取消或真实退休释放槽。
    r_active[slot]<=1'b0;r_sent[slot]<=1'b0;r_done[slot]<=1'b0; // 槽再次可被后续周期预约
   end // 结束本槽应用退休
  end // 结束本槽正常更新
 end // 结束本槽同步寄存器
end endgenerate // 结束全部固定容量槽展开
generate if((RAS_OWNER_ENABLE!=0)&&((CAPACITY<1)||(CAPACITY>4)||(EPOCH_WIDTH<2)||(EPOCH_WIDTH>16)||(GENERATION_WIDTH<2)||(GENERATION_WIDTH>16)))begin:gen_invalid_ras // 明确不支持大容量RAS。
 endpoint_tag_table_ras_parameters_invalid Invalid_Inst(); // 非法参数展开失败。
end endgenerate // 结束RAS配置保护。

generate if(NATIVE_RAW_ENABLE!=0)begin:gen_native_raw
 reg [2047:0] raw_data[0:CAPACITY-1];
 reg [255:0] raw_headers[0:CAPACITY-1];
 wire [2:0] already_seen={2'd0,r_seen[response_slot][0]}+{2'd0,r_seen[response_slot][1]}+{2'd0,r_seen[response_slot][2]}+{2'd0,r_seen[response_slot][3]};
 wire [1:0] header_index=response_is_write?2'd0:already_seen[1:0]; // 沿前bitmap来自唯一Tag表，不另维护接收计数。
 wire unused_seen_high=already_seen[2]; // 合法未完成响应的index至多三，完整/重复响应被原检查拒绝。
 assign o_complete_raw_data=o_complete_valid?raw_data[r_complete_slot]:2048'd0;
 assign o_complete_raw_headers=o_complete_valid?raw_headers[r_complete_slot]:256'd0;
 genvar raw_slot;
 for(raw_slot=0;raw_slot<CAPACITY;raw_slot=raw_slot+1)begin:slot_data
  always @(posedge i_clk)begin
   if(!i_rstn)begin raw_data[raw_slot]<=2048'd0;raw_headers[raw_slot]<=256'd0;end
   else if(allocate_fire&&(free_slot==raw_slot[SLOT_WIDTH-1:0]))begin raw_data[raw_slot]<=2048'd0;raw_headers[raw_slot]<=256'd0;end
   else if(i_response_valid&&o_response_ready&&response_legal&&(response_slot==raw_slot[SLOT_WIDTH-1:0]))begin
    raw_headers[raw_slot][header_index*64+:64]<=i_response_header;
    if(!response_is_write)raw_data[raw_slot][i_response_offset*512+:512]<=i_response_data;
   end
  end
 end
end else begin:gen_no_native_raw
 wire unused_raw_header=^i_response_header;
 assign o_complete_raw_data=2048'd0;assign o_complete_raw_headers=256'd0;
end endgenerate
// Native raw forwarding is deliberately limited to ordinary single-beat response headers.
generate if((NATIVE_RAW_ENABLE!=0)&&((NATIVE_RAW_ENABLE!=1)||(NATIVE_ID_ENABLE!=1)||(FULL_READ_ENABLE!=1)||(RAS_OWNER_ENABLE!=0)))begin:invalid_native_raw
 native_raw_requires_full_read_native_identity_without_ras Invalid_Config();
end endgenerate
generate if(MESSAGE_ENABLE!=0&&((MESSAGE_ENABLE!=1)||(WRITE_ENABLE!=1)||(FULL_READ_ENABLE!=1)||(NATIVE_ID_ENABLE!=1)||(NATIVE_RAW_ENABLE!=1)||(RAS_OWNER_ENABLE!=0)))begin:bad_message_parameters
 endpoint_tag_table_message_configuration_invalid u_bad(); // 不在其他owner模式静默放宽合法性。
end endgenerate
endmodule // 结束完整Tag与结果容量表模块
`default_nettype wire // 恢复外围默认网络设置
