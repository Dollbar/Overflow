// 普通未压缩Write/WriteFull：保存完整事务并按相对Beat序列交付Data与区域BE。
`default_nettype none // 禁止隐式网络掩盖握手连接错误
module endpoint_write_originator( // Write发起保持模块：单事务有序交付而不分配独立Tag表
 input wire i_clk,i_rstn, // 单时钟域与同步低有效复位
 input wire [9:0] i_local_id, // 当前复位时期稳定的源加速器标识
 input wire i_request_valid,output wire o_request_ready, // 应用一次握手保存完整描述符及全部数据
 input wire i_request_full,input wire [10:0] i_request_tag, // 选择WriteFull并携带完整十一位Tag
 input wire [56:0] i_request_address,input wire [9:0] i_request_dst, // 完整五十七位地址和十位单播目的ID
 input wire [5:0] i_request_length,input wire [7:0] i_request_attr, // 长度为DWORD数减一，属性原样传给目标
 input wire [1:0] i_request_asi,input wire [7:0] i_request_metadata, // 保留Accelerator定义的地址空间与元数据
 input wire [2047:0] i_request_data,input wire [255:0] i_request_be, // 低位起相对Beat数据和整个256字节区域的BE
 output wire o_source_valid,output wire [255:0] o_source_control, // 尚未被TL捕获的Header及其完整Control半字
 input wire i_source_captured,i_header_taken, // 分别接收prepared捕获和实际Header发送反馈
 output wire [1:0] o_data_valid,output wire [511:0] o_data,input wire [1:0] i_data_accepted, // 低半字优先，valid与accepted均为零至二的数量
 output wire o_pending,o_sent,o_done,o_error,o_profile_legal // 导出待发所有权、发送与全部交付事件及候选诊断
); // 结束Write整事务与TL序列化接口
wire [8:0] size_bytes; // 声明size_bytes，256字节需要九位，避免长度回卷
assign size_bytes={1'b0,i_request_length,2'b00}+9'd4; // 256字节需要九位，避免长度回卷
wire [9:0] end_byte; // 声明end_byte，区域末端允许等于256
assign end_byte={2'b0,i_request_address[7:0]}+{1'b0,size_bytes}; // 区域末端允许等于256
wire [9:0] beat_sum; // 声明beat_sum，加上Beat内偏移和向上取整补偿后计算Data数量
assign beat_sum={4'd0,i_request_address[5:0]}+{1'b0,size_bytes}+10'd63; // 加上Beat内偏移和向上取整补偿后计算Data数量
wire [2:0] beats; // 声明beats，合法区域内只允许一至四个相对Beat
assign beats=beat_sum[8:6]; // 合法区域内只允许一至四个相对Beat
reg [255:0] allowed_be; // 组合重建完整256字节区域的允许使能掩码
integer byte_index; // 静态遍历每个自然字节位置
always @* begin // 组合产生范围掩码，不保留上一候选的BE状态
 allowed_be=256'd0; // 先清空所有范围外使能位
 for(byte_index=0;byte_index<256;byte_index=byte_index+1) // 有界展开区域内全部256个字节位
  if((byte_index>={24'd0,i_request_address[7:0]})&&(byte_index<{22'd0,end_byte}))allowed_be[byte_index]=1'b1; // 只允许请求起始地址至排他末端范围内的字节
end // 结束无锁存的区域使能重建
wire profile_legal; // 声明profile_legal，要求DWORD对齐且整个请求不跨256字节区域
assign profile_legal=(i_request_address[1:0]==2'd0)&&(end_byte<=10'd256)&& // 要求DWORD对齐且整个请求不跨256字节区域
 (i_request_full?((i_request_address[5:0]==6'd0)&&(size_bytes[5:0]==6'd0)):((i_request_be&~allowed_be)==256'd0)); // Full要求完整Beat；普通Write拒绝范围外BE
wire [1:0] num_beats; // 声明num_beats，四Beat编码三，保留规范NUMBEATS的减一表示
assign num_beats=beats[1:0]-2'd1; // 四Beat编码三，保留规范NUMBEATS的减一表示
wire [255:0] encoded; // 声明encoded，未压缩自然128位字段上方补NOP并固定VC零
assign encoded={128'd0,4'h1,(i_request_full?6'h29:6'h28),2'd0,i_request_asi, // 未压缩自然128位字段上方补NOP并固定VC零
 i_request_tag,1'b0,i_request_attr,i_request_length,i_request_metadata,i_request_address[56:2],i_local_id,i_request_dst,3'd0,num_beats}; // 保留属性地址和ID全位，CLOAD与CWAY共三位清零
reg r_pending,r_captured,r_sent; // 分别记录预约、源捕获和真实发送所有权
reg [255:0] r_control; // 捕获后的完整Control不受应用输入变化影响
reg [2303:0] r_payload; // 最多八个Data半字以及最后一个固定256位BE半字
reg [3:0] r_index,r_total; // 半字读指针与包括可选BE的总半字数量
wire request_fire; // 声明request_fire，只有实际应用握手才创建待发事务
assign request_fire=i_request_valid&&o_request_ready; // 只有实际应用握手才创建待发事务
wire capture_fire; // 声明capture_fire，源有效且捕获反馈到达才转移Header所有权
assign capture_fire=i_source_captured&&o_source_valid; // 源有效且捕获反馈到达才转移Header所有权
wire header_fire; // 声明header_fire，每个Header仅允许一次实际发送事件
assign header_fire=i_header_taken&&r_pending&&!r_sent&&(r_captured||capture_fire); // 每个Header仅允许一次实际发送事件
wire accepted_legal; // 声明accepted_legal，Data接纳数不得超过当前连续有效半字数
assign accepted_legal=(i_data_accepted<=o_data_valid); // Data接纳数不得超过当前连续有效半字数
wire [3:0] accepted_count; // 声明accepted_count，非法接纳数量只诊断而不推进半字指针
assign accepted_count=accepted_legal?{2'd0,i_data_accepted}:4'd0; // 非法接纳数量只诊断而不推进半字指针
wire [3:0] next_index; // 声明next_index，根据本周期实际接纳数量计算下个未交付半字
assign next_index=r_index+accepted_count; // 根据本周期实际接纳数量计算下个未交付半字
wire [2303:0] shifted; // 声明shifted，以保存的相对半字指针选择最低两份连续数据
assign shifted=r_payload >> ({28'd0,r_index} * 32'd256); // 以保存的相对半字指针选择最低两份连续数据
assign o_profile_legal=profile_legal; // 组合候选合法性供共享预约控制使用
assign o_request_ready=i_rstn&&!r_pending&&profile_legal; // 仅合法候选且holding空闲时接受新Write
assign o_pending=i_rstn&&r_pending; // 同步复位期间抑制此前事务有效
assign o_source_valid=i_rstn&&r_pending&&!r_captured; // Header被prepared捕获后不再重复提供
assign o_source_control=o_source_valid?r_control:256'd0; // 有效时输出保存Control，其他周期输出NOP
assign o_data_valid=(!i_rstn||!r_pending)?2'd0:((r_total-r_index)>=4'd2)?2'd2:(r_total>r_index)?2'd1:2'd0; // 按剩余数量提供最多两个半字，不凭Header已发送提前清空
assign o_data={((o_data_valid==2'd2)?shifted[511:256]:256'd0),((o_data_valid!=2'd0)?shifted[255:0]:256'd0)}; // 低半字先交付，最后单半字时高半字明确清零
assign o_sent=i_rstn&&header_fire; // 仅真实Header发送推进共享Tag表，而非capture或Data入队
assign o_done=i_rstn&&r_pending&&(r_captured||capture_fire)&&(r_sent||header_fire)&&(next_index==r_total); // Header捕获、真实发送及所有Data同时闭合才释放holding
assign o_error=i_rstn&&((i_request_valid&&!profile_legal)||(i_source_captured&&!o_source_valid)|| // 非法应用字段与不属于当前Header的捕获均报告诊断
 (i_header_taken&&!header_fire)||!accepted_legal); // 正常holding与Data背压不属于错误
always @(posedge i_clk)begin // 同一同步域原子更新事务与半字交付状态
 if(!i_rstn)begin // 统一同步复位取消该模块全部待发所有权
  r_pending<=1'b0;r_captured<=1'b0;r_sent<=1'b0;r_control<=256'd0; // 清空Header阶段与保存的Control字段
  r_payload<=2304'd0;r_index<=4'd0;r_total<=4'd0; // 清空数据保持和半字进度，防止旧时期泄漏
 end else begin // 正常周期仅依据合法握手推进所有权
  if(request_fire)begin // 新预约原子保存编码结果和完整有效载荷
   r_pending<=1'b1;r_captured<=1'b0;r_sent<=1'b0;r_control<=encoded;r_index<=4'd0; // 新事务从未捕获未发送且半字指针零开始
   r_total<={beats,1'b0}+(i_request_full?4'd0:4'd1); // 普通Write在两倍Beat数后追加一个BE半字
   // 先保存全部Data，再把BE放在声明的最后Data之后；未发送Beat不会进入序列。
   r_payload<=({256'd0,i_request_data}&((2304'd1 << ({29'd0,beats} * 32'd512))-2304'd1))|({2048'd0,(i_request_full?allowed_be:i_request_be)} << ({29'd0,beats} * 32'd512)); // 先屏蔽未传输Beat再放入尾BE，避免未使用Data污染掩码
  end // 结束整事务应用捕获
  if(capture_fire)r_captured<=1'b1; // prepared捕获只推进Header持有阶段
  if(header_fire)r_sent<=1'b1; // 实际Header消费独立记录为已发送
  if(r_pending&&accepted_legal)r_index<=next_index; // 仅合法Data接纳推进半字索引
  if(o_done)begin r_pending<=1'b0;r_captured<=1'b0;r_sent<=1'b0;end // 三项交付条件全部满足后回收有序holding
 end // 结束正常周期的交付状态更新
end // 结束Write同步寄存器控制
endmodule // 结束endpoint_write_originator模块
`default_nettype wire // 恢复外围默认网络声明方式
