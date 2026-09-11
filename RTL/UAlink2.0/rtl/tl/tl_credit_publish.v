module tl_credit_publish #( // tl_credit_publish模块：退休信用累积与可停顿FC发布
parameter integer WIDTH=8 // 初始每逻辑槽容量位宽，合法范围1至16
)( // 接纳配置、消费释放和实际发布确认属于同一时钟域
input wire i_clk,i_rstn,i_start,i_shared, // 同步复位及一次性本地容量配置
input wire [20*WIDTH-1:0] i_capacities, // 四类各五个Pool/VC槽的初始可发布容量
output wire o_start_ready,o_start_taken,o_config_error, // 非共享模式须提供两类Data容量
input wire i_release_valid,input wire [79:0] i_releases, // 实际退休字保存的每槽四位归还量
output wire o_release_ready,o_release_taken, // 原子接纳全部归还量，不借同拍发送空间
input wire i_send,output wire o_valid,o_taken,o_complete,o_shared, // i_send仅对应实际端口接纳，完成类型区别于FC
output wire [31:0] o_word, // FC时是实际四类字段，完成类型由装配器形成MSG1
output wire o_active,o_done,output wire [19+20*WIDTH:0] o_pending, // pending仍包含有效输出中尚未发送的信用
output wire [48+20*(WIDTH+1):0] o_state // 完整寄存器观察用于独立验证
); // 结束发布器端口声明
localparam integer EXT=(WIDTH+2<5)?5:WIDTH+2; // 累积加法容纳四位归还与计数最高进位
reg r_active,r_done,r_shared,r_valid,r_complete; // 初始化与输出生命周期状态
reg [31:0] r_word;reg [11:0] r_pointer; // 固定输出快照及四类五槽轮转指针
reg [20*(WIDTH+1)-1:0] r_pending; // 每槽扩一位支持共享Data池跨类别归还
wire [19:0] overflow;wire [20*EXT-1:0] unused_totals,unused_next_totals; // 每槽扩展加法及实际发布后的结果
wire [31:0] selected_word;wire configuration_ok,has_pending; // 仅旧计数形成新的FC提议
assign configuration_ok=i_shared||((|i_capacities[10*WIDTH+:5*WIDTH])&&(|i_capacities[15*WIDTH+:5*WIDTH])); // 非共享两Data类非空
assign has_pending=|r_pending; // 初始化完成前必须全部初始信用实际发送
assign o_start_ready=i_rstn&&!r_active&&configuration_ok;assign o_start_taken=i_start&&o_start_ready; // 配置仅接纳一次
assign o_config_error=i_rstn&&i_start&&!r_active&&!configuration_ok; // 配置错误不建立部分状态
assign o_release_ready=i_rstn&&r_done&&!(|overflow);assign o_release_taken=i_release_valid&&o_release_ready; // 全向量原子接纳
assign o_valid=i_rstn&&r_valid;assign o_taken=o_valid&&i_send; // 输出停顿保持全部寄存器字段
assign o_complete=o_valid&&r_complete;assign o_shared=o_valid&&r_shared;assign o_word=o_valid?r_word:32'd0; // 无效输出不暴露陈旧提议
assign o_active=r_active;assign o_done=r_done;assign o_pending=r_pending; // 实际初始化与累积状态
assign o_state={r_active,r_done,r_shared,r_valid,r_complete,r_word,r_pointer,r_pending}; // 完整状态位串
 genvar group,index; // 常量展开四类FC与二十槽计数
 generate // 固定数量组合调度器与累积器
  if(WIDTH<1||WIDTH>16)begin : invalid_width // 非法参数在展开阶段拒绝
   tl_credit_publish_width_invalid Invalid_Inst(); // 不允许静默容量截断
  end // 结束发布位宽校验
  for(group=0;group<4;group=group+1)begin : groups // 每一类独立选择原始Pool或VC
   reg found;reg [2:0] chosen_lane;reg [4:0] chosen_amount; // 固定FC字段选择结果
   reg [31:0] amount;integer offset,lane; // 有界五槽优先搜索，临时量明确扩展
   wire [2:0] sent_lane;wire [4:0] sent_amount; // 从寄存输出字段还原实际已发送信用
   if(group<2)begin : command_field // CMD字段由类型、VC和三位数量组成
    assign selected_word[(22-6*group)+:6]=(chosen_amount!=5'd0)?{(chosen_lane!=3'd0),(chosen_lane==3'd0 ? 2'd0:(chosen_lane[1:0]-2'd1)),chosen_amount[2:0]}:6'd0; // 单字段最多七个CMD
    assign sent_lane=r_word[27-6*group]?({1'b0,r_word[(25-6*group)+:2]}+3'd1):3'd0; // 实际快照的信用槽
    assign sent_amount={2'd0,r_word[(22-6*group)+:3]}; // 实际快照的归还数量
   end else begin : data_field // Data字段由类型、VC和五位数量组成
    assign selected_word[(24-8*group)+:8]=(chosen_amount!=5'd0)?{(chosen_lane!=3'd0),(chosen_lane==3'd0 ? 2'd0:(chosen_lane[1:0]-2'd1)),chosen_amount}:8'd0; // 单字段最多三十一个Data
    assign sent_lane=r_word[31-8*group]?({1'b0,r_word[(29-8*group)+:2]}+3'd1):3'd0; // Data原始Pool或VC
    assign sent_amount=r_word[(24-8*group)+:5]; // 只有实际taken才用此值减计数
   end // 结束四类字段宽度分支
   always @* begin // 从当前轮转指针选择第一个非空槽
    found=1'b0;chosen_lane=3'd0;chosen_amount=5'd0;amount=32'd0;lane=0; // 完整组合初值
    for(offset=0;offset<5;offset=offset+1)begin // 固定五槽轮转扫描
     lane={29'd0,r_pointer[group*3+:3]}+offset;if(lane>=5)lane=lane-5; // 五进制回绕，不把VC与Pool混为一槽
     amount={{(31-WIDTH){1'b0}},r_pending[(group*5+lane)*(WIDTH+1)+:(WIDTH+1)]}; // 明确扩展当前逻辑槽数量
     if(!found&&amount!=32'd0)begin // 只保存扫描到的首个非空槽
      found=1'b1;chosen_lane=lane[2:0]; // 此快照在实际发送前不受新增归还影响
      if(group<2)chosen_amount=(amount>32'd7)?5'd7:amount[4:0]; // CMD分批上限
      else chosen_amount=(amount>32'd31)?5'd31:amount[4:0]; // Data分批上限
     end // 结束首个非空槽选择
    end // 结束五槽轮转扫描
   end // 结束FC组合字段选择
   always @(posedge i_clk)begin // 轮转仅由实际发送推进
    if(!i_rstn)r_pointer[group*3+:3]<=3'd0; // 四类独立从Pool开始
    else if(o_taken&&!r_complete&&sent_amount!=5'd0)r_pointer[group*3+:3]<=(sent_lane==3'd4)?3'd0:sent_lane+3'd1; // 空类别不改变公平指针
   end // 结束实际发送后的轮转状态
   for(index=0;index<5;index=index+1)begin : lanes // 每类五个独立逻辑累积槽
    localparam integer SLOT=group*5+index; // 保留原Request/Response及Pool/VC归属
    localparam [2:0] LANE=index; // 显式三位当前逻辑槽
    wire [EXT-1:0] pending_extended,release_extended,sent_extended; // 足够宽的无符号加减操作数
    assign pending_extended={{(EXT-WIDTH-1){1'b0}},r_pending[SLOT*(WIDTH+1)+:(WIDTH+1)]}; // 计数高位不截断
    assign release_extended={{(EXT-4){1'b0}},i_releases[SLOT*4+:4]}; // 每个实际退休字的四位量
    assign sent_extended=(o_taken&&!r_complete&&sent_lane==LANE)?{{(EXT-5){1'b0}},sent_amount}:{EXT{1'b0}}; // 只扣已被发送端接纳的快照
    assign unused_totals[SLOT*EXT+:EXT]=pending_extended+release_extended; // ready检查旧空间，独立于发送
    assign overflow[SLOT]=|unused_totals[SLOT*EXT+WIDTH+1+:(EXT-WIDTH-1)]; // 拒绝任何高位进位
    assign unused_next_totals[SLOT*EXT+:EXT]=pending_extended+(o_release_taken?release_extended:{EXT{1'b0}})-sent_extended; // 同拍发送和归还各记一次
    always @(posedge i_clk)begin // 所有累积计数使用同一输入时钟
     if(!i_rstn)r_pending[SLOT*(WIDTH+1)+:(WIDTH+1)]<={(WIDTH+1){1'b0}}; // 复位取消未发送信用
     else if(o_start_taken)r_pending[SLOT*(WIDTH+1)+:(WIDTH+1)]<={1'b0,i_capacities[SLOT*WIDTH+:WIDTH]}; // 一次性采样初始容量
     else r_pending[SLOT*(WIDTH+1)+:(WIDTH+1)]<=unused_next_totals[SLOT*EXT+:(WIDTH+1)]; // 同拍累积与发布统一提交
    end // 结束单槽累积状态
   end // 结束五槽独立累积器
  end // 结束四类FC字段和计数器
 endgenerate // 结束固定信用资源展开
assign selected_word[31:28]=4'd0; // FlowControl字段FTYPE为零
always @(posedge i_clk)begin // 发布生命周期及输出快照
 if(!i_rstn)begin // 同步复位整个发布器
  r_active<=1'b0;r_done<=1'b0;r_shared<=1'b0;r_valid<=1'b0;r_complete<=1'b0;r_word<=32'd0; // 无陈旧输出
 end else begin // 配置与发布独立接纳
  if(o_start_taken)begin r_active<=1'b1;r_shared<=i_shared;end // 保存本次链路初始化模式
  if(o_taken)begin // 已发送快照退休后才允许下一次装载
   if(r_complete)r_done<=1'b1; // 只有完成消息实际发送才接纳正常归还
   r_valid<=1'b0;r_complete<=1'b0;r_word<=32'd0; // 清除已发送提议，不重复发布
  end else if(!r_valid&&r_active)begin // 没有未发送快照时从旧计数生成提议
   if(has_pending)begin r_valid<=1'b1;r_complete<=1'b0;r_word<=selected_word;end // 四类FC快照
   else if(!r_done)begin r_valid<=1'b1;r_complete<=1'b1;r_word<=32'd0;end // 初始信用已全部发送才能发完成消息
  end // 结束新输出提议装载
 end // 结束非复位发布控制
end // 结束发布生命周期寄存器
endmodule // 结束tl_credit_publish信用发布模块
