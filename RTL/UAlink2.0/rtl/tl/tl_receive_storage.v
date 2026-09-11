module tl_receive_storage #( // tl_receive_storage模块：实际TL Flit与消费信用元数据存储
parameter integer DEPTH=17, // 本地FIFO字容量，初始线上信用配置另需资源证明
parameter integer COUNT_WIDTH=(DEPTH<2)?1:(DEPTH<4)?2:(DEPTH<8)?3:(DEPTH<16)?4:(DEPTH<32)?5:(DEPTH<64)?6:(DEPTH<128)?7:(DEPTH<256)?8:(DEPTH<512)?9:(DEPTH<1024)?10:(DEPTH<2048)?11:(DEPTH<4096)?12:(DEPTH<8192)?13:(DEPTH<16384)?14:(DEPTH<32768)?15:16 // 深度派生位宽由原FIFO校验
)( // 本地可停顿事务接口，不新增物理链路ready
input wire i_clk,i_rstn,i_valid,i_auth,input wire [511:0] i_flit,input wire [1:0] i_msg, // 实际入站Flit
output wire o_allowed,o_taken,o_rejected,o_fatal, // 不合法接收锁存fatal，空间等待不锁存
output wire [2:0] o_lower,o_upper,output wire [79:0] o_demands,o_proposed_releases,output wire o_store, // 真实接纳分类与提议
input wire i_read_ready,output wire o_read_valid,output wire [511:0] o_read_flit,output wire [1:0] o_read_msg, // 消费完整保存字
output wire [5:0] o_read_classes,output wire [79:0] o_read_releases,output wire o_retired, // 消费者同拍接纳返回量，后续交给FC发布器
output wire [COUNT_WIDTH-1:0] o_count,output wire [663:0] o_context_state,output wire [89:0] o_validation_state // 完整控制状态观察
); // 端口结束
wire ctx_allowed,full_allowed,full_fatal,space,write_ready,read_valid; // 原子准入与存储空间
wire [599:0] read_word,write_word;wire [6:0] ctx_pending,full_pending; // 完整字及两个同拍推进上下文
wire [72:0] ctx_be,full_be;wire [583:0] metadata;wire [2:0] unused_ctx_lower,unused_ctx_upper,rq;wire [3:0] rs;wire opened,poison; // 状态观察
wire unused_ct,unused_cr,unused_ft,unused_fr;reg r_fatal; // 独立接纳错误锁存
wire proposal; // 显式组合网络声明
assign proposal=ctx_allowed&&full_allowed&&!r_fatal; // 完整合法性联合
assign o_fatal=r_fatal||full_fatal; // 任一错误禁止后续收发消费
assign space=!o_store||write_ready; // 纯控制FC/消息无需事务存储空间
assign o_allowed=proposal&&space;assign o_taken=i_valid&&o_allowed; // 唯一原子接纳
assign o_rejected=i_rstn&&i_valid&&!proposal; // 空间等待不是协议内容错误
assign o_context_state={ctx_pending,ctx_be,metadata}; // 新释放上下文全部寄存器
assign o_validation_state={full_pending,full_be,rq,rs,full_fatal,opened,poison}; // 完整内容与预算状态
 tl_receive_context u_context(.i_clk(i_clk),.i_rstn(i_rstn),.i_commit(o_taken),.i_auth(i_auth),.i_lower(i_flit[255:0]),.i_msg(i_msg),.i_type0(i_flit[7:0]),.i_type1(i_flit[263:256]),.o_allowed(ctx_allowed),.o_taken(unused_ct),.o_rejected(unused_cr),.o_lower(unused_ctx_lower),.o_upper(unused_ctx_upper),.o_demands(o_demands),.o_releases(o_proposed_releases),.o_store(o_store),.o_pending(ctx_pending),.o_be(ctx_be),.o_metadata(metadata)); // 仅实际接纳推进释放所有权
 tl_full_flit u_full(.i_clk(i_clk),.i_rstn(i_rstn),.i_commit(i_valid&&space&&ctx_allowed&&!r_fatal),.i_auth(i_auth),.i_flit(i_flit),.i_msg(i_msg),.o_allowed(full_allowed),.o_taken(unused_ft),.o_rejected(unused_fr),.o_lower(o_lower),.o_upper(o_upper),.o_pending(full_pending),.o_be(full_be),.o_requests_available(rq),.o_responses_available(rs),.o_fatal(full_fatal),.o_pair_open(opened),.o_pair_poison(poison)); // 原样内容分类和预算校验
assign write_word={o_proposed_releases,o_upper,o_lower,i_msg,i_flit}; // 600bit整字节，释放元数据和payload同存
 upli_receive_storage #(.C_DEPTH(DEPTH),.C_DATA_WIDTH(600),.C_COUNT_WIDTH(COUNT_WIDTH)) u_storage(.i_clk(i_clk),.i_rstn(i_rstn),.i_write_valid(o_taken&&o_store),.i_write_data(write_word),.o_write_ready(write_ready),.i_read_ready(i_read_ready&&!o_fatal),.o_read_valid(read_valid),.o_read_data(read_word),.o_count(o_count)); // 获授权实际SDP存储映射
assign o_read_valid=i_rstn&&!o_fatal&&read_valid;assign o_retired=o_read_valid&&i_read_ready; // 一次完整消费同时交接信用元数据
assign {o_read_releases,o_read_classes,o_read_msg,o_read_flit}=read_word; // 输出只由保存的实际字驱动
always @(posedge i_clk)begin // 单输入时钟同步控制复位
 if(!i_rstn)r_fatal<=1'b0; // 清除旧接纳错误
 else if(o_rejected)r_fatal<=1'b1; // 非法提议停止且不进入SRAM
end // 错误状态更新
endmodule // 结束tl_receive_storage接收事务存储模块
