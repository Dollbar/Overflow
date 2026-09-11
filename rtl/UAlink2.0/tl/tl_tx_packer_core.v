module tl_tx_packer_core( // tl_tx_packer_core模块：复用已计算资格，仅选择来源并打包
 input wire i_clk,i_rstn,i_taken, // 唯一上升沿时钟、同步低有效复位和真实发送确认
 input wire [6:0] i_pending,input wire i_auth, // 原始发送序列位置与认证状态
 input wire i_header_ready,i_nop_ready,i_has_data, // 已核对头部资格、catch NOP资格及真实tenure负载标记
 input wire [255:0] i_header,i_tags, // 原始被选Control与对应标签，不在此重复解码
 input wire [1:0] i_data_valid,input wire [255:0] i_data0,i_data1, // 原tenure的数据数量和两个有序半Flit
 input wire i_fc_valid,input wire [511:0] i_fc_flit,input wire [1:0] i_fc_msg, // 独立FC或完成消息候选
 output reg o_valid,output reg [511:0] o_flit,output reg [1:0] o_msg, // 保持原组合打包和来源锁定语义
 output wire o_header_taken,o_tags_taken,output wire [1:0] o_data_taken,output wire o_fc_taken // 只有真实发送才确认消费
); // 结束内部资格复用接口
localparam [2:0] SEL_NONE=3'd0,SEL_HEADER=3'd1,SEL_FC=3'd2,SEL_DATA=3'd3,SEL_TAIL=3'd4,SEL_NOP=3'd5; // 候选来源与不消费输入的NOP
reg r_prefer_fc; // 同时可发时在FC与头部之间交替
reg [2:0] r_hold,selection; // 下游停顿时锁定来源，输入源保持未确认的队首
reg [1:0] data_count;reg tags_selected; // 当前候选实际占用的数据半数及标签
wire fc_ready; // FC资格仍依赖真实序列及所选有序Data源
assign fc_ready=i_fc_valid&&((i_pending==7'd0)||((i_pending==7'd1)&&(i_data_valid>=2'd1)&&(i_fc_msg==2'd0))); // 只有普通FC可与旧尾部共享Flit
always @* begin // 根据真实序列与已锁定来源选择当前候选
 selection=SEL_NONE; // 默认没有可发送候选
 if(i_rstn)begin // 复位期间不对外提议或消费输入
  if(r_hold!=SEL_NONE)selection=r_hold; // 停顿保持已选来源，允许其他源到达而不改写输出
  else if(i_pending>7'd1)begin // Data序列内部禁止Control或FC插入
   if(i_data_valid>=2'd2)selection=SEL_DATA; // 两个有序半Flit同时有效才构造完整Data Flit
  end else if(fc_ready&&(!i_header_ready||r_prefer_fc))selection=SEL_FC; // 轮到FC或业务不可发时先发FC
  else if(i_header_ready)selection=SEL_HEADER; // 信用、catch和本拍负载均已满足的头部
  else if((i_pending==7'd1)&&(i_data_valid>=2'd1))selection=SEL_TAIL; // 新头部阻塞仍以NOP加旧尾部完成前一事务
  else if((i_pending==7'd0)&&i_nop_ready)selection=SEL_NOP; // 显式NOP前进真实Flit计数并释放catch预算
 end // 结束复位外的候选选择
end // 结束来源选择组合逻辑
always @* begin // 被选来源组合成完整Flit以及独立消费计数
 o_valid=1'b0;o_flit=512'd0;o_msg=2'd0;data_count=2'd0;tags_selected=1'b0; // 完整默认值避免残留负载
 case(selection) // 按已确定的候选来源打包
  SEL_HEADER:begin // 新Control固定放在下半Flit
   o_valid=1'b1;o_flit[255:0]=i_header; // 只有实际taken才弹出头部
   if(i_pending==7'd1)begin o_flit[511:256]=i_data0;data_count=2'd1;end // 旧尾部交换到上半，不提前消费新数据
   else if(i_auth)begin o_flit[511:256]=i_tags;tags_selected=1'b1;end // 对应AuthTags与头部在同一个Flit
   else if(i_has_data)begin o_flit[511:256]=i_data0;data_count=2'd1;end // 无认证且有Data时上半消费第一条数据
  end // 结束新Control打包分支
  SEL_FC:begin // FC或完成消息来自真实发布器
   o_valid=1'b1;o_flit=i_fc_flit;o_msg=i_fc_msg; // 保持发布器原编码
   if(i_pending==7'd1)begin o_flit[511:256]=i_data0;data_count=2'd1;end // 普通FC上半携带旧Data或BE尾部
  end // 结束FC打包分支
  SEL_DATA:begin o_valid=1'b1;o_flit={i_data1,i_data0};data_count=2'd2;end // 有序两个Data或BE半Flit
  SEL_TAIL:begin o_valid=1'b1;o_flit={i_data0,256'd0};data_count=2'd1;end // 下半NOP允许旧尾部独立退休
  SEL_NOP:begin o_valid=1'b1;end // 完整零NOP推进catch预算且不确认任何输入队首
  default:begin end // 没有合法候选时保留所有零默认输出
 endcase // 结束候选负载打包选择
end // 结束负载和消费计数组合逻辑
assign o_header_taken=o_valid&&i_taken&&(selection==SEL_HEADER); // 头部只在真实发送后消费
assign o_tags_taken=o_valid&&i_taken&&tags_selected; // 标签消费与实际头部AuthTags同行
assign o_data_taken=(o_valid&&i_taken)?data_count:2'd0; // 分别确认零、一或两个有序半Flit
assign o_fc_taken=o_valid&&i_taken&&(selection==SEL_FC); // 发布信用仅由实际线上FC发送确认
always @(posedge i_clk)begin // 单时钟记录输出停顿时选择
 if(!i_rstn)r_hold<=SEL_NONE; // 同步复位取消尚未确认的提议
 else if(i_taken||!o_valid)r_hold<=SEL_NONE; // 完成发送或无有效候选后释放来源锁定
 else r_hold<=selection; // 首次停顿即锁定当前未消费来源
end // 结束来源锁定寄存器
always @(posedge i_clk)begin // 单时钟记录公平仲裁偏好
 if(!i_rstn)r_prefer_fc<=1'b1; // 初始化优先允许FC交换信用
 else if(o_fc_taken)r_prefer_fc<=1'b0; // FC已实际发送后让可发送头部获得下一次机会
 else if(o_header_taken)r_prefer_fc<=1'b1; // 头部已实际发送后让FC获得下一个合法Control位置
end // 结束仲裁偏好寄存器
endmodule // 结束tl_tx_packer_core模块
