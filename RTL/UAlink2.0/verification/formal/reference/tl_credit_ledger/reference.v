module ledger_reference #(parameter WIDTH=16)( // 独立占用量账本参考
 input wire i_clk,i_rstn,i_receive,i_send,i_finish,i_shared, // 本地事件
 input wire [20*WIDTH-1:0] i_grants,i_demands, // 逻辑槽输入
 output wire o_allowed,o_taken,o_receive_error, // 组合观察
 output reg [20*(WIDTH+1)-1:0] o_capacity, // 已学习物理容量
 output reg [20*(WIDTH+1)-1:0] o_available, // 占用量推导余额
 output reg o_done,o_shared, // 初始化及模式
 output reg invariant // 已归纳的可达约束
); // 接口结束
localparam B=WIDTH+1; // 共享池保留一位进位
reg [20*B-1:0] used; // 在途信用数量
reg [20*B-1:0] added,wanted,next_cap,next_used; // 候选接收发送及状态
reg bad,fits; // 全槽原子判定
integer j; // 独立顺序扫描索引
always @* begin // 完整组合参考
 added=0;wanted=0;next_cap=o_capacity;next_used=used;o_available=0;bad=0;fits=1;invariant=o_done||!o_shared; // 默认保持及模式约束
 for(j=0;j<20;j=j+1)begin // 从逻辑信用展开至物理槽
  if(i_receive)added[j*B+:B]={1'b0,i_grants[j*WIDTH+:WIDTH]}; // 接收候选
  wanted[j*B+:B]={1'b0,i_demands[j*WIDTH+:WIDTH]}; // 发送候选
 end // 输入展开结束
 if(o_shared)begin // 仅共享两个数据Pool
  added[10*B+:B]=added[10*B+:B]+added[15*B+:B];added[15*B+:B]=0; // 跨类返回同一物理池
  wanted[10*B+:B]=wanted[10*B+:B]+wanted[15*B+:B];wanted[15*B+:B]=0; // 跨类联合需求
 end // 合并结束
 for(j=0;j<20;j=j+1)begin // 使用占用量检查每个池
  o_available[j*B+:B]=o_capacity[j*B+:B]-used[j*B+:B]; // 容量减占用
  if(used[j*B+:B]>o_capacity[j*B+:B])invariant=0; // 不能超借容量
  if(!o_done&&used[j*B+:B]!=0)invariant=0; // 初始化没有消费
  if(o_shared&&j==10)begin // 合并池最大两个逻辑容量
   if(o_capacity[j*B+:B]>{ {WIDTH{1'b1}},1'b0})invariant=0; // 上界为两倍最大值
  end else if(o_capacity[j*B+:B]>{1'b0,{WIDTH{1'b1}}})invariant=0; // 其余槽仍限原位宽
  if(o_shared&&j==15&&o_capacity[j*B+:B]!=0)invariant=0; // 别名槽不重复计数
  if(added[j*B+:B]>(o_done?used[j*B+:B]:({1'b0,{WIDTH{1'b1}}}-o_capacity[j*B+:B])))bad=1; // 回收不能超过在途，初始化不能超过余量
  if(wanted[j*B+:B]>o_available[j*B+:B])fits=0; // 全部旧信用充足才可发送
  if(!o_done)next_cap[j*B+:B]=o_capacity[j*B+:B]+added[j*B+:B]; // 初始发行学习
 end // 扫描结束
 if(i_receive&&i_finish&&!o_done&&!i_shared&&((next_cap[10*B+:5*B]==0)||(next_cap[15*B+:5*B]==0)))bad=1; // 非共享初始化两类数据需非零
 if(o_done)begin // 已完成阶段在途计数
  for(j=0;j<20;j=j+1)next_used[j*B+:B]=used[j*B+:B]-added[j*B+:B]+((i_send&&fits&&!bad)?wanted[j*B+:B]:{B{1'b0}}); // 减返回加消费
 end // 在途更新结束
 if(i_receive&&i_finish&&!o_done&&i_shared)begin // 首次完成合并容量
  next_cap[10*B+:B]=next_cap[10*B+:B]+next_cap[15*B+:B];next_cap[15*B+:B]=0; // 使用学习后的容量包含本拍发布
 end // 初始化合并结束
end // 组合参考结束
assign o_receive_error=i_rstn&&bad; // 复位屏蔽错误
assign o_allowed=i_rstn&&o_done&&fits&&!bad; // 整笔发送许可
assign o_taken=i_send&&o_allowed; // 实际消费
always @(posedge i_clk)begin // 唯一同步时钟
 if(!i_rstn)begin o_capacity<=0;used<=0;o_done<=0;o_shared<=0;end // 复位建立不变量
 else if(!bad)begin // 任一错误全状态保持
  o_capacity<=next_cap;used<=next_used; // 容量及占用更新
  if(i_receive&&i_finish&&!o_done)begin o_done<=1;o_shared<=i_shared;end // 模式仅首次完成采样
 end // 更新结束
end // 时序结束
endmodule // 参考结束
module proof #(parameter WIDTH=16)(input wire i_clk,i_rstn,i_receive,i_send,i_finish,i_shared,input wire [20*WIDTH-1:0] i_grants,i_demands,output wire same_state,outputs_equal); // 完整关系包装
localparam N=40*(WIDTH+1)+2; // 全部状态观察位数
wire [N+2:0] actual,reference;wire invariant; // 三个组合输出及状态
 tl_credit_ledger #(.WIDTH(WIDTH)) dut(i_clk,i_rstn,i_receive,i_send,i_finish,i_shared,i_grants,i_demands,actual[N+2],actual[N+1],actual[N],actual[N-1:20*(WIDTH+1)+2],actual[20*(WIDTH+1)+1:2],actual[1],actual[0]); // 实际实现
 ledger_reference #(.WIDTH(WIDTH)) ref_impl(i_clk,i_rstn,i_receive,i_send,i_finish,i_shared,i_grants,i_demands,reference[N+2],reference[N+1],reference[N],reference[N-1:20*(WIDTH+1)+2],reference[20*(WIDTH+1)+1:2],reference[1],reference[0],invariant); // 独立参考
assign same_state=(actual[N-1:0]==reference[N-1:0])&&invariant; // 对应关系包含归纳不变量
assign outputs_equal=actual==reference; // 全输出观察
endmodule // 包装结束
