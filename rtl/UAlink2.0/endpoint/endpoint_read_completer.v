`timescale 1ns/1ps // 定义同钟普通Read执行器的数字时间单位。
`default_nettype none // 禁止隐式网络掩盖事务接口错误。
module endpoint_read_completer #( // 真实请求经内存完成后生成单Beat响应。
 parameter CAPACITY=4, // 每个槽同时预留描述符和完整512位结果，本轮冻结并验证1至4槽。
 parameter SLOT_WIDTH=(CAPACITY<=2)?1:(CAPACITY<=4)?2:(CAPACITY<=8)?3:(CAPACITY<=16)?4:(CAPACITY<=32)?5:(CAPACITY<=64)?6:(CAPACITY<=128)?7:8 // 单槽避免零宽度，非二次幂保留尾索引检查。
)( // 开始冻结的本地执行接口。
 input wire i_clk,i_rstn, // 共用时钟上升沿和同步低有效复位。
 input wire [9:0] i_local_id, // 运行期间稳定的完整本地ID。
 input wire i_request_valid,output wire o_request_ready, // 接纳真实收到的完整请求。
 input wire [10:0] i_request_tag, // 完整Tag而非低位槽索引。
 input wire [9:0] i_request_src,i_request_dst, // 保留完整双方身份供响应反向路由。
 input wire [56:0] i_request_address, // 不截断57位请求地址。
 input wire [5:0] i_request_length, // 本阶段要求长度15。
 input wire [7:0] i_request_attr, // 本阶段要求完整首末DWORD字节使能。
 input wire [1:0] i_request_vc,input wire i_request_pool, // 本阶段限定VC0和VC信用。
 input wire [1:0] i_request_asi,input wire [7:0] i_request_metadata, // 本阶段测试执行域选择零属性。
 output wire o_mem_valid,input wire i_mem_ready, // 实际内存命令接纳接口。
 output wire [SLOT_WIDTH-1:0] o_mem_slot, // 仅用于本地结果关联的执行槽。
 output wire [56:0] o_mem_address, // 转发完整已保存地址，不增加4KiB生产限制。
 output wire [5:0] o_mem_length,output wire [7:0] o_mem_attr, // 转发原请求长度和字节属性。
 output wire [1:0] o_mem_asi,output wire [7:0] o_mem_metadata, // 转发原请求执行属性。
 input wire i_mem_result_valid,output wire o_mem_result_ready, // 已预留空间接收真实执行结果，非法返回消费诊断。
 input wire [SLOT_WIDTH-1:0] i_mem_result_slot, // 允许已发slot乱序返回。
 input wire [511:0] i_mem_result_data,input wire [3:0] i_mem_result_status, // 完整数据和同一完成状态。
 output wire o_source_valid,output wire [255:0] o_source_control,input wire i_source_captured, // 真实Control组所有权转移。
 output wire [1:0] o_data_valid,output wire [511:0] o_data,input wire [1:0] i_data_accepted, // 零至两个半Flit提议和实际接纳数。
 output wire o_error,output wire [7:0] o_count // 非法事件组合诊断和完整生命周期槽占用。
); // 结束Completer外部接口。
 reg [CAPACITY-1:0] busy_q,issued_q,complete_q,header_q; // 保存每个槽真实生命周期。
 reg [SLOT_WIDTH-1:0] allocate_q,issue_q,head_q; // 分别推进请求接纳、内存发出和响应退休顺序。
 reg [7:0] count_q; // 对应完整描述符和结果资源占用。
 reg [10:0] tag_q[0:CAPACITY-1]; // 独立保存每槽完整Tag。
 reg [9:0] src_q[0:CAPACITY-1],dst_q[0:CAPACITY-1]; // 独立保存请求来源和本地目的。
 reg [56:0] address_q[0:CAPACITY-1]; // 保存全部57位地址直到内存真实接纳。
 reg [5:0] length_q[0:CAPACITY-1]; // 保存请求长度。
 reg [7:0] attr_q[0:CAPACITY-1],metadata_q[0:CAPACITY-1]; // 保存请求访问属性。
 reg [1:0] asi_q[0:CAPACITY-1],data_sent_q[0:CAPACITY-1]; // 保存执行属性与已接纳Data数量。
 reg [511:0] result_q[0:CAPACITY-1]; // 实际预留并保存每槽完整64字节结果。
 reg [3:0] status_q[0:CAPACITY-1]; // 保存结果对应的真实执行状态。
 wire request_legal,request_fire,memory_fire,result_fire,head_result,header_fire,data_feedback_legal,retire,encode_error; // 分离每个接口的实际推进条件。
 reg result_legal; // 先检查slot范围再读取对应生命周期。
 integer reset_slot; // 同步清理槽进度的有界循环变量。
 integer read_slot; // 静态有界读取只选择实际分配的槽，不推断不存在的RAM补齐行。
 reg [56:0] issue_address; // 内存命令组合选择保留完整57位地址。
 reg [5:0] issue_length; reg [7:0] issue_attr,issue_metadata; reg [1:0] issue_asi; // 保存当前内存命令的组合字段。
 reg [10:0] head_tag; reg [9:0] head_src,head_dst; // 保存真实队首描述符的组合字段。
 reg [511:0] head_data; reg [3:0] head_status; reg [1:0] head_data_sent; // 选择队首完整结果、状态和实际接纳进度。
 always @(*) begin // 有界多路器为非二次幂容量的未用地址定义无效输出，不分配虚构槽。
  issue_address=57'd0;issue_length=6'd0;issue_attr=8'd0;issue_metadata=8'd0;issue_asi=2'd0; // 无匹配时不提供有效内存字段。
  head_tag=11'd0;head_src=10'd0;head_dst=10'd0;head_data=512'd0;head_status=4'd0;head_data_sent=2'd0; // 无匹配时默认无有效队首内容。
  for(read_slot=0;read_slot<CAPACITY;read_slot=read_slot+1) begin // 综合展开为每个实际槽的固定索引读取。
   if(issue_q==read_slot) begin // 只选择当前内存命令所属的真实槽。
    issue_address=address_q[read_slot];issue_length=length_q[read_slot];issue_attr=attr_q[read_slot];issue_metadata=metadata_q[read_slot];issue_asi=asi_q[read_slot]; // 固定索引读取不会生成不存在的RAM读行。
   end // 结束内存命令字段选择。
   if(head_q==read_slot) begin // 只选择按请求顺序提交的真实队首。
    head_tag=tag_q[read_slot];head_src=src_q[read_slot];head_dst=dst_q[read_slot];head_data=result_q[read_slot];head_status=status_q[read_slot];head_data_sent=data_sent_q[read_slot]; // 保留完整Tag、ID、512位结果与接纳进度。
   end // 结束队首响应字段选择。
  end // 结束对真实CAPACITY的有界选择。
 end // 组合默认值覆盖全部输出，无锁存器或未驱动补齐行。
 assign request_legal=(i_request_dst==i_local_id)&&(i_request_address[5:0]==0)&&(i_request_length==15)&&(i_request_attr==8'hff)&&(i_request_vc==0)&&!i_request_pool&&(i_request_asi==0)&&(i_request_metadata==0); // 仅限制已冻结子集而不限制地址映射范围。
 assign o_request_ready=i_rstn&&request_legal&&(count_q<CAPACITY); // 满槽背压，不借用当拍尚未退休的容量。
 assign request_fire=i_request_valid&&o_request_ready; // 实际请求握手同时预留结果槽。
 assign o_mem_valid=i_rstn&&busy_q[issue_q]&&!issued_q[issue_q]; // 最早尚未实际执行的请求成为内存队首。
 assign o_mem_slot=issue_q; // slot与命令一起保持至内存接纳。
 assign o_mem_address = issue_address; // 全部57位原样传递。
 assign o_mem_length=issue_length; // 原样传递保存的请求长度。
 assign o_mem_attr=issue_attr; // 原样传递保存的字节属性。
 assign o_mem_asi=issue_asi; // 原样传递保存的执行空间。
 assign o_mem_metadata=issue_metadata; // 原样传递保存的执行元数据。
 assign memory_fire=o_mem_valid&&i_mem_ready; // 只有真实内存命令握手才允许结果返回。
 assign o_mem_result_ready=i_rstn; // 结果空间已预留，非法返回也明确消费。
 always @(*) begin // 完整组合校验结果slot与状态。
  result_legal=1'b0; // 默认拒绝未发、空闲或重复完成。
  if(i_mem_result_slot<CAPACITY) begin // 未用尾索引不能别名到合法槽。
   result_legal=busy_q[i_mem_result_slot]&&issued_q[i_mem_result_slot]&&!complete_q[i_mem_result_slot]&&((i_mem_result_status==0)||(i_mem_result_status==3)); // 只允许已发请求接受一次合法状态结果。
  end // 结束slot范围检查。
 end // 结束无锁存结果合法性译码。
 assign result_fire=i_mem_result_valid&&o_mem_result_ready&&result_legal; // 被消费的非法返回不写入有效结果槽。
 assign head_result=i_rstn && busy_q[head_q] && complete_q[head_q]; // 队首已保存真实完成才有响应资格。
 endpoint_response_encode u_response_encode( // 复用实际字段编码器，不在状态机重定义线上字段。
  .i_valid(head_result&&!header_q[head_q]),.i_tag(head_tag), // 仅提供尚未被捕获的Header。
  .i_src(head_dst),.i_dst(head_src),.i_status(head_status), // 原请求源成为响应目的，Tag和状态保持完整。
  .i_num_beats(2'd0),.i_offset(2'd0),.i_last(1'b1),.i_vc(2'd0),.i_pool(1'b0), // 明确普通单Beat未认证子集。
  .o_valid(o_source_valid),.o_error(encode_error),.o_control(o_source_control) // 输出真实Control和编码诊断。
 ); // 结束Response字段编码实例。
 assign header_fire=i_source_captured&&o_source_valid; // 捕获Header不表示Data已全部入队。
 assign o_data_valid=head_result?(2'd2-head_data_sent):2'd0; // 只提议尚未被实际接纳的半字。
 assign o_data=!head_result?512'd0:(head_data_sent==0)?{head_data[511:256],head_data[255:0]}:(head_data_sent==1)?{256'd0,head_data[511:256]}:512'd0; // 部分接纳后把未接纳高半前移。
 assign data_feedback_legal=(i_data_accepted<=o_data_valid); // 超额或三项反馈不能推进Data所有权。
 assign retire=head_result&&(header_q[head_q]||header_fire)&&data_feedback_legal&&((head_data_sent+i_data_accepted)==2); // Header和两Data全部真实转移才回收槽。
 assign o_error=i_rstn&&((i_request_valid&&!request_legal)||(i_mem_result_valid&&!result_legal)||(i_source_captured&&!o_source_valid)||!data_feedback_legal||encode_error); // 满槽与普通等待不是错误。
 assign o_count=count_q; // 公布包含待执行、等待结果和待完整发送的占用。
 always @(posedge i_clk) begin // 仅实际接口事件更新事务状态。
  if(!i_rstn) begin // 同步复位取消本地epoch，不伪装Link Down恢复。
   busy_q<={CAPACITY{1'b0}};issued_q<={CAPACITY{1'b0}};complete_q<={CAPACITY{1'b0}};header_q<={CAPACITY{1'b0}}; // 清除槽有效生命周期。
   allocate_q<=0;issue_q<=0;head_q<=0;count_q<=0; // 清空本地环和精确容量。
   for(reset_slot=0;reset_slot<CAPACITY;reset_slot=reset_slot+1) data_sent_q[reset_slot]<=0; // 清除进度即可阻止旧结果重新有效，无需复位大数据阵列。
  end else begin // 不同槽可以并行接受请求、返回结果与发送响应。
   if(request_fire) begin // 捕获完整描述符并预留其结果空间。
    busy_q[allocate_q]<=1'b1;issued_q[allocate_q]<=1'b0;complete_q[allocate_q]<=1'b0;header_q[allocate_q]<=1'b0;data_sent_q[allocate_q]<=0; // 开始新事务的唯一生命周期。
    tag_q[allocate_q]<=i_request_tag;src_q[allocate_q]<=i_request_src;dst_q[allocate_q]<=i_request_dst; // 保存完整Tag和双方ID。
    address_q[allocate_q]<=i_request_address;length_q[allocate_q]<=i_request_length;attr_q[allocate_q]<=i_request_attr;asi_q[allocate_q]<=i_request_asi;metadata_q[allocate_q]<=i_request_metadata; // 之后不依赖上游实时描述符。
    if(allocate_q==CAPACITY-1) allocate_q<=0; else allocate_q<=allocate_q+1'b1; // 对非二次幂容量也正确循环。
   end // 结束真实请求接纳。
   if(memory_fire) begin // 仅在实际执行接口接纳后标记issued。
    issued_q[issue_q]<=1'b1; // 从下一周期起此slot才允许结果到达。
    if(issue_q==CAPACITY-1) issue_q<=0; else issue_q<=issue_q+1'b1; // 内存请求保持请求接收顺序。
   end // 结束内存命令推进。
   if(result_fire) begin // 按slot接受乱序真实内存完成。
    result_q[i_mem_result_slot]<=i_mem_result_data;status_q[i_mem_result_slot]<=i_mem_result_status;complete_q[i_mem_result_slot]<=1'b1; // 原子保存全部512位与执行状态。
   end // 非法或重复结果只诊断，不破坏已保存数据。
   if(header_fire) header_q[head_q]<=1'b1; // Header只转移一次，继续保留未入队Data。
   if(head_result&&data_feedback_legal&&i_data_accepted!=0) data_sent_q[head_q]<=head_data_sent+i_data_accepted; // 精确按零至两项实际反馈推进。
   if(retire) begin // 所有响应字段全部转移后才释放描述符及结果。
    busy_q[head_q]<=1'b0;issued_q[head_q]<=1'b0;complete_q[head_q]<=1'b0;header_q[head_q]<=1'b0; // 防止旧结果再次成为响应来源。
    if(head_q==CAPACITY-1) head_q<=0; else head_q<=head_q+1'b1; // 下个响应按请求顺序提交。
   end // 结束完整响应退休。
   case({request_fire,retire}) // 处理同拍一进一出与独立容量变化。
    2'b10:count_q<=count_q+1'b1; // 只有新接纳请求时增加占用。
    2'b01:count_q<=count_q-1'b1; // 只有完整响应退休时减少占用。
    default:count_q<=count_q; // 空闲或一进一出保持占用。
   endcase // 结束完整生命周期计数。
  end // 结束正常执行与同步复位分支。
 end // 结束Completer事务状态过程。
endmodule // 结束endpoint_read_completer真实单Beat子集。
`default_nettype wire // 恢复外围编译单元默认网络规则。
