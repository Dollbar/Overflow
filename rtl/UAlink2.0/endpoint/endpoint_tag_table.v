// Common 2.0完整(port,Tag)身份与完整响应结果预约；四槽为本地实现容量，不限制规范Tag取值。
`default_nettype none // 禁止未声明网络隐藏匹配或握手错误
module endpoint_tag_table #(parameter integer CAPACITY=4, NUM_PORTS=1)( // Tag表模块：预约、实际发送、完整响应和应用退休四阶段所有权
 input wire i_clk,i_rstn, // 单时钟与同步低有效复位；不表示Link Down恢复
 input wire [9:0] i_local_id, // 当前复位时期稳定的本地响应目的标识
 input wire i_allocate_valid, // 调用方已检查Read字段profile的预约请求
 input wire [1:0] i_allocate_port, // 本地物理端口身份域
 input wire [10:0] i_allocate_tag, // 完整十一位Tag，不使用低位直接索引
 output wire o_allocate_ready, // 空闲槽与未占用身份同时满足才可预约
 input wire i_sent_valid, // 对应请求Header已经被真实发送器消费
 input wire [1:0] i_sent_port, // 发送事件对应端口
 input wire [10:0] i_sent_tag, // 发送事件对应完整Tag
 input wire i_response_valid, // 上游必须已保存完整两个Data半Flit
 output wire o_response_ready, // 已预约结果容量使响应消费独立于应用背压
 input wire [1:0] i_response_port, // 响应进入的本地端口
 input wire [10:0] i_response_tag, // 线上响应完整Tag
 input wire [9:0] i_response_dst, // 验证响应路由到当前Originator
 input wire [3:0] i_response_status, // 当前仅实现OKAY零和DECODE ERROR三
 input wire [1:0] i_response_offset, // 单Beat响应要求偏移零
 input wire i_response_last, // 单Beat响应必须完整结束
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
 output wire [7:0] o_count // 全部预约数，含未发送、等待响应和完成背压
); // 表项生命周期接口完全局限于当前同步复位时期
localparam CONFIG_LEGAL=(CAPACITY>0)&&(CAPACITY<=255)&&((NUM_PORTS==1)||(NUM_PORTS==2)||(NUM_PORTS==4)); // 计数宽度及端口域的局部参数范围
localparam TABLE_DEPTH=CAPACITY; // 静态槽数用于有界展开和独立lint核对
localparam SLOT_WIDTH=(CAPACITY<=2)?1:(CAPACITY<=4)?2:(CAPACITY<=8)?3:(CAPACITY<=16)?4:(CAPACITY<=32)?5:(CAPACITY<=64)?6:(CAPACITY<=128)?7:8; // 精确槽索引宽度防止隐式截断
reg r_active[0:CAPACITY-1],r_sent[0:CAPACITY-1],r_done[0:CAPACITY-1]; // 每槽预约、真实发送和完整响应状态
reg [1:0] r_port[0:CAPACITY-1]; // 槽内保留本地端口身份
reg [10:0] r_tag[0:CAPACITY-1]; // 槽内完整Tag支持任意稀疏分配
reg [3:0] r_status[0:CAPACITY-1]; // 已保存响应状态
reg [511:0] r_data[0:CAPACITY-1]; // 预约时即拥有的完整结果空间
reg [7:0] r_count; // 活跃预约累计，包括等待应用退休的完成
reg r_complete_valid; // 已锁定的完成不能被后来较低槽完成替换
reg [SLOT_WIDTH-1:0] r_complete_slot; // 背压期间稳定的完成槽选择
reg free_found,allocate_duplicate,sent_found,response_found,done_found; // 各独立事件以沿前状态并行搜索
reg [SLOT_WIDTH-1:0] free_slot,sent_slot,response_slot,done_slot; // 槽编号只用于本地存储寻址
integer scan_slot; // 静态有界遍历变量不承担协议身份
wire response_legal,sent_legal,allocate_bad,allocate_fire,retire_fire; // 事件合法性与实际所有权转移
always @* begin // 独立搜索完整身份和空闲结果容量
 free_found=1'b0;allocate_duplicate=1'b0;sent_found=1'b0;response_found=1'b0;done_found=1'b0; // 每次组合求值从空结果开始
 free_slot={SLOT_WIDTH{1'b0}};sent_slot={SLOT_WIDTH{1'b0}};response_slot={SLOT_WIDTH{1'b0}};done_slot={SLOT_WIDTH{1'b0}}; // 未找到时的安全地址不用于有效写入
 for(scan_slot=32'd0;scan_slot<TABLE_DEPTH;scan_slot=scan_slot+32'd1) begin // 全部槽精确比较端口和完整Tag
  if(!r_active[scan_slot]&&!free_found)begin free_found=1'b1;free_slot=scan_slot[SLOT_WIDTH-1:0];end // 保守选择沿前第一个空槽
  if(r_active[scan_slot]&&(r_port[scan_slot]==i_allocate_port)&&(r_tag[scan_slot]==i_allocate_tag)) allocate_duplicate=1'b1; // 完成但未退休的Tag仍不可复用
  if(r_active[scan_slot]&&(r_port[scan_slot]==i_sent_port)&&(r_tag[scan_slot]==i_sent_tag))begin sent_found=1'b1;sent_slot=scan_slot[SLOT_WIDTH-1:0];end // 发送事件不缩短身份宽度
  if(r_active[scan_slot]&&(r_port[scan_slot]==i_response_port)&&(r_tag[scan_slot]==i_response_tag))begin response_found=1'b1;response_slot=scan_slot[SLOT_WIDTH-1:0];end // 响应关联不包含debug-only源ID
  if(r_active[scan_slot]&&r_done[scan_slot]&&!done_found)begin done_found=1'b1;done_slot=scan_slot[SLOT_WIDTH-1:0];end // 只有无锁定完成时才使用此候选
 end // 结束固定容量搜索
end // 所有组合输出在每条路径均赋值
assign allocate_bad=!CONFIG_LEGAL||({30'd0,i_allocate_port}>=NUM_PORTS)||allocate_duplicate; // 满容量属于背压，不属于非法事件
assign o_allocate_ready=i_rstn&&!allocate_bad&&free_found; // 不借用同拍退休槽，允许保守一拍气泡
assign allocate_fire=i_allocate_valid&&o_allocate_ready; // 仅此握手创建新预约和结果所有权
assign sent_legal=CONFIG_LEGAL&&sent_found&&!r_sent[sent_slot]&&!r_done[sent_slot]; // 不允许未知或重复发送事件修改表项
assign response_legal=CONFIG_LEGAL&&response_found&&r_sent[response_slot]&&!r_done[response_slot]&& // 响应必须属于沿前已真实发送且尚未完成的预约
 (i_response_dst==i_local_id)&&((i_response_status==4'd0)||(i_response_status==4'd3))&& // 目的验证与明确支持的普通响应状态
 (i_response_offset==2'd0)&&(i_response_num_beats==2'd0)&&i_response_last&&!i_response_data_error; // 收齐单Beat、无DataError才允许完成
assign o_response_ready=i_rstn&&CONFIG_LEGAL; // 非法响应也可被消费诊断，绝不占用新槽
assign o_complete_valid=i_rstn&&r_complete_valid; // 同步状态复位前亦抑制输出有效
assign o_complete_port=o_complete_valid?r_port[r_complete_slot]:2'd0; // 空闲完成输出清零
assign o_complete_tag=o_complete_valid?r_tag[r_complete_slot]:11'd0; // 只从锁定槽输出身份
assign o_complete_status=o_complete_valid?r_status[r_complete_slot]:4'd0; // 背压期间槽状态不可更改
assign o_complete_data_valid=o_complete_valid&&(r_status[r_complete_slot]==4'd0); // 错误完成不提交成功数据
assign o_complete_data=o_complete_data_valid?r_data[r_complete_slot]:512'd0; // 非成功或无完成时数据全零
assign retire_fire=o_complete_valid&&i_complete_ready; // 应用接纳是保守Tag复用边界
assign o_count=i_rstn?r_count:8'd0; // 复位期间不暴露此前预约
assign o_error=i_rstn&&((i_allocate_valid&&allocate_bad)||(i_sent_valid&&!sent_legal)||(i_response_valid&&!response_legal)); // 诊断不自动清理任何其他事务
always @(posedge i_clk) begin // 单一同步域持有计数和完成仲裁
 if(!i_rstn) begin // 本地复位取消当前所有权，完整恢复协议另行实现
  r_count<=8'd0;r_complete_valid<=1'b0;r_complete_slot<={SLOT_WIDTH{1'b0}}; // 清空容量和稳定完成选择
 end else begin // 所有事件合法性从该沿前状态判断
  case({allocate_fire,retire_fire}) // 独立预约与退休同拍时容量净变化为零
   2'b10:r_count<=r_count+8'd1; // 一笔新预约获得完整结果存储
   2'b01:r_count<=r_count-8'd1; // 一笔应用完成归还完整结果存储
   default:r_count<=r_count; // 同拍或无事件维持容量
  endcase // 结束容量守恒更新
  if(retire_fire)r_complete_valid<=1'b0; // 保守仲裁允许退休后气泡
  else if(!r_complete_valid&&done_found)begin // 有背压时禁止替换已经锁定的完成
   r_complete_valid<=1'b1;r_complete_slot<=done_slot; // 锁定沿前已经完整保存的结果
  end // 结束稳定完成选择
 end // 结束计数与仲裁正常更新
end // 结束共享控制寄存器
 genvar slot;generate for(slot=32'd0;slot<TABLE_DEPTH;slot=slot+32'd1)begin:gen_slot // 每个结果槽由独立时序块唯一驱动
 localparam [SLOT_WIDTH-1:0] SLOT_INDEX=slot[SLOT_WIDTH-1:0]; // 综合展开时固定的精确宽度槽编号
 always @(posedge i_clk)begin // 本地槽状态和结果数据采用相同时钟
  if(!i_rstn)begin // 同步取消该槽预约和残留结果
   r_active[slot]<=1'b0;r_sent[slot]<=1'b0;r_done[slot]<=1'b0; // 无预约、未发送、无完成
   r_port[slot]<=2'd0;r_tag[slot]<=11'd0;r_status[slot]<=4'd0;r_data[slot]<=512'd0; // 清除旧时期身份和结果
  end else begin // 本槽依据共享搜索的沿前结果独立更新
   if(allocate_fire&&(free_slot==SLOT_INDEX))begin // 预约只写入沿前空闲槽
    r_active[slot]<=1'b1;r_sent[slot]<=1'b0;r_done[slot]<=1'b0; // 新预约必须经历实际发送后才可完成
    r_port[slot]<=i_allocate_port;r_tag[slot]<=i_allocate_tag; // 完整身份在预约沿捕获
    r_status[slot]<=4'd0;r_data[slot]<=512'd0; // 新预约不暴露上一使用者数据
   end // 结束本槽预约写入
   if(i_sent_valid&&sent_legal&&(sent_slot==SLOT_INDEX))r_sent[slot]<=1'b1; // 只有实际Header消费推进sent
   if(i_response_valid&&o_response_ready&&response_legal&&(response_slot==SLOT_INDEX))begin // 非法响应永不触发结果写入
    r_done[slot]<=1'b1;r_status[slot]<=i_response_status; // 保存完整单Beat响应的结束状态
    r_data[slot]<=(i_response_status==4'd0)?i_response_data:512'd0; // 错误响应虽完整接收但成功数据存储置零
   end // 结束完整响应捕获
   if(retire_fire&&(r_complete_slot==SLOT_INDEX))begin // 锁定完成只有应用接纳时释放
    r_active[slot]<=1'b0;r_sent[slot]<=1'b0;r_done[slot]<=1'b0; // 槽再次可被后续周期预约
   end // 结束本槽应用退休
  end // 结束本槽正常更新
 end // 结束本槽同步寄存器
end endgenerate // 结束全部固定容量槽展开
endmodule // 结束完整Tag与结果容量表模块
`default_nettype wire // 恢复外围默认网络设置
