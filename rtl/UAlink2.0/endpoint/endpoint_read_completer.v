`timescale 1ns/1ps // 定义同钟普通Read执行器的数字时间单位。
`default_nettype none // 禁止隐式网络掩盖事务接口错误。
module endpoint_read_completer #( // 真实请求经内存完成后生成单Beat响应。
 parameter CAPACITY=4, // 每个槽同时预留描述符和完整512位结果，本轮冻结并验证1至4槽。
 parameter SLOT_WIDTH=(CAPACITY<=2)?1:(CAPACITY<=4)?2:(CAPACITY<=8)?3:(CAPACITY<=16)?4:(CAPACITY<=32)?5:(CAPACITY<=64)?6:(CAPACITY<=128)?7:8, // 单槽避免零宽度，非二次幂保留尾索引检查。
 parameter FULL_READ_ENABLE=0 // 默认保持既有单64B行为，开启后处理完整普通Read。
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
 output wire o_error,output wire [7:0] o_count, // 非法事件组合诊断和完整生命周期槽占用。
 input wire [2047:0] i_mem_result_data_full, // 完整模式一次接收相对首Beat起的四个自然64B数据块。
 output wire [255:0] o_mem_be // 内存字节使能始终按整个256B区域定位。
); // 结束Completer外部接口。
generate if(FULL_READ_ENABLE==0) begin:legacy_read

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
 assign o_mem_be=256'hffffffffffffffff << issue_address[7:0]; // 旧64B完整使能按区域位置导出。
end else begin:full_read
 localparam integer SLOTS=(CAPACITY>=1&&CAPACITY<=4)?CAPACITY:1; // 非法容量仍安全展开有限非空数组。
 localparam CONFIG_LEGAL=(CAPACITY>=1)&&(CAPACITY<=4)&&(SLOT_WIDTH>=1)&&(SLOT_WIDTH<=2)&&((1<<SLOT_WIDTH)>=CAPACITY); // 拒绝不可表示的真实槽索引。
 localparam integer LAST_VALUE=SLOTS-1; // 真实环形回绕点不包含补齐行。
 localparam [SLOT_WIDTH-1:0] LAST_SLOT=LAST_VALUE[SLOT_WIDTH-1:0]; // 明确索引位宽。
 localparam [7:0] COUNT_LIMIT=SLOTS[7:0]; // 精确容量保持八位公开ABI。
 wire active,request_legal,request_fire,memory_fire,result_fire,status_legal; // 各接口实际事件独立控制生命周期。
 wire head_result,head_final,header_fire,data_legal,beat_done,retire,encode_error; // 一个Beat完整交付后才进入下个Beat。
 wire [8:0] request_bytes,request_end;wire [6:0] request_last_dw;wire [5:0] unused_rounding_bits; // 九位计算涵盖完整256B和非法跨区末端。
 wire [2:0] request_beats; // 真实Beat数一至四，不能用两位表示四。
 reg [255:0] request_be; // 首尾DWORD稀疏使能和中间完整DWORD。
 reg [SLOT_WIDTH-1:0] allocate_q,issue_q,head_q; // 接纳、执行和响应退休独立顺序指针。
 reg [7:0] count_q; // 直到最后Beat完整交付才减少占用。
 reg [SLOTS-1:0] busy_q,issued_q,complete_q,header_q; // 每槽独立生命周期和当前Beat Header所有权。
 reg [10:0] tag_q[0:SLOTS-1];reg [9:0] src_q[0:SLOTS-1],dst_q[0:SLOTS-1]; // 保存完整响应身份。
 reg [56:0] address_q[0:SLOTS-1];reg [5:0] length_q[0:SLOTS-1]; // 不截断地址，也不限制4KiB测试映射。
 reg [7:0] attr_q[0:SLOTS-1],metadata_q[0:SLOTS-1];reg [1:0] asi_q[0:SLOTS-1]; // 执行属性原样保留。
 reg [255:0] be_q[0:SLOTS-1];reg [2:0] beats_q[0:SLOTS-1]; // 预留完整区域BE与返回Beat数。
 reg [2047:0] full_result_q[0:SLOTS-1];reg [3:0] status_q[0:SLOTS-1]; // 所有N Beat发送完之前保留同一次后端完整结果。
 reg [1:0] beat_q[0:SLOTS-1],sent_q[0:SLOTS-1]; // 相对Beat编号与当前Beat已交付半字数。
 reg [56:0] issue_address;reg [5:0] issue_length;reg [7:0] issue_attr,issue_meta;reg [1:0] issue_asi;reg [255:0] issue_be; // 内存反压时选择同一保存描述符。
 reg issue_busy,issue_issued,head_busy,head_complete,head_header,result_legal; // 所有动态选择均展开为真实固定索引。
 reg [10:0] head_tag;reg [9:0] head_src,head_dst;reg [3:0] head_status; // 当前响应的完整身份和事务统一状态。
 reg [2047:0] head_full;reg [511:0] head_data;reg [1:0] head_beat,head_sent;reg [2:0] head_beats; // 只公开当前拥有的Beat数据。
 integer byte_index,read_slot; // 组合有界循环与固定索引选择。
 wire unused_legacy_result=&{1'b0,i_mem_result_data}; // 完整模式保留旧ABI输入但只使用完整结果接口。
 assign active=i_rstn&&CONFIG_LEGAL; // 非法配置不接纳或公开任何有效事务。
 assign request_bytes={1'b0,i_request_length,2'b00}+9'd4; // LEN零是四字节，LEN六十三是256字节。
 assign request_end={1'b0,i_request_address[7:0]}+request_bytes; // 即使BE全零也按结构范围拒绝越界。
 assign request_last_dw=request_end[8:2]-7'd1; // 末DWORD的区域起始位置。
 assign {request_beats,unused_rounding_bits}={3'd0,i_request_address[5:0]}+request_bytes+9'd63; // 首Beat内偏移参与向上取整。
 always @(*) begin // 独立重建内存侧区域BE，不改变响应自然lane位置。
  request_be=256'd0; // 请求区间以外的字节不参与内存读取。
  for(byte_index=0;byte_index<256;byte_index=byte_index+1)begin // 固定遍历整个区域。
   if(byte_index[8:0]>={1'b0,i_request_address[7:0]}&&byte_index[8:0]<request_end)begin // 仅考虑DWORD包围区间。
    if(byte_index[7:2]==i_request_address[7:2])request_be[byte_index]=i_request_attr[{1'b0,byte_index[1:0]}]; // 首DWORD优先，LEN零完全忽略高nibble。
    else if(byte_index[8:2]==request_last_dw)request_be[byte_index]=i_request_attr[{1'b1,byte_index[1:0]}]; // 多DWORD请求的末DWORD使用高nibble。
    else request_be[byte_index]=1'b1; // 中间DWORD所有字节有效。
   end // 结束当前自然byte位置判定。
  end // 结束完整区域使能重建。
 end // 全组合默认覆盖，不推断锁存器。
 assign request_legal=(i_request_dst==i_local_id)&&(i_request_address[1:0]==2'd0)&&(request_end<=9'd256)&&(i_request_vc==2'd0)&&!i_request_pool; // 当前集成VC零pool零；ASI与metadata全值透传。
 assign o_request_ready=active&&request_legal&&(count_q<COUNT_LIMIT); // 接纳时同时预留全部结果空间。
 assign request_fire=i_request_valid&&o_request_ready; // 有效非法请求只诊断不分配。
 assign status_legal=(i_mem_result_status==4'd0)||(i_mem_result_status==4'd2)||(i_mem_result_status==4'd3)||(i_mem_result_status==4'd6)||(i_mem_result_status==4'd8); // 普通单播Read五种真实完成状态。
 always @(*) begin // 固定索引读取消除非二次幂未使用RAM映射行。
  issue_address=57'd0;issue_length=6'd0;issue_attr=8'd0;issue_meta=8'd0;issue_asi=2'd0;issue_be=256'd0; // 无真实选择时无有效命令内容。
  issue_busy=1'b0;issue_issued=1'b0;head_busy=1'b0;head_complete=1'b0;head_header=1'b0;result_legal=1'b0; // 未使用slot不能别名到有效槽。
  head_tag=11'd0;head_src=10'd0;head_dst=10'd0;head_status=4'd0;head_full=2048'd0;head_beat=2'd0;head_sent=2'd0;head_beats=3'd0; // 当前响应字段默认无效。
  for(read_slot=0;read_slot<SLOTS;read_slot=read_slot+1)begin // 仅展开真实一至四槽。
   if(issue_q==read_slot[SLOT_WIDTH-1:0])begin // 最早未发内存命令保持请求顺序。
    issue_busy=busy_q[read_slot];issue_issued=issued_q[read_slot];issue_address=address_q[read_slot];issue_length=length_q[read_slot]; // 选择已保存地址与长度。
    issue_attr=attr_q[read_slot];issue_meta=metadata_q[read_slot];issue_asi=asi_q[read_slot];issue_be=be_q[read_slot]; // 保留属性和整个区域掩码。
   end // 结束执行描述符选择。
   if(head_q==read_slot[SLOT_WIDTH-1:0])begin // 响应保守按请求顺序串行化。
    head_busy=busy_q[read_slot];head_complete=complete_q[read_slot];head_header=header_q[read_slot];head_tag=tag_q[read_slot];head_src=src_q[read_slot];head_dst=dst_q[read_slot]; // 保存所有权与完整身份。
    head_status=status_q[read_slot];head_full=full_result_q[read_slot];head_beat=beat_q[read_slot];head_sent=sent_q[read_slot];head_beats=beats_q[read_slot]; // 一次完成的所有Beat共享同一状态。
   end // 结束当前响应选择。
   if(i_mem_result_slot==read_slot[SLOT_WIDTH-1:0])result_legal=busy_q[read_slot]&&issued_q[read_slot]&&!complete_q[read_slot]&&status_legal; // 未发、重复、未知与保留状态结果均不能覆盖有效槽。
  end // 结束有界固定索引读取。
  case(head_beat) // 每个Beat保持全部512位，自然lane不压缩。
   2'd0:head_data=head_full[511:0]; // 相对首Beat是向下对齐64B地址的数据。
   2'd1:head_data=head_full[1023:512]; // 第二Beat。
   2'd2:head_data=head_full[1535:1024]; // 第三Beat。
   default:head_data=head_full[2047:1536]; // 第四Beat。
  endcase // 完整覆盖两位Beat编号。
 end // 全组合选择无补齐读行或锁存器。
 assign o_mem_valid=active&&issue_busy&&!issue_issued; // 请求接纳与内存接纳是不同事件。
 assign o_mem_slot=issue_q;assign o_mem_address=issue_address;assign o_mem_length=issue_length; // 保持完整执行身份与几何。
 assign o_mem_attr=issue_attr;assign o_mem_asi=issue_asi;assign o_mem_metadata=issue_meta; // 执行属性全值透传。
 assign o_mem_be=issue_be; // 区域bit零对应256B对齐区域首字节。
 assign memory_fire=o_mem_valid&&i_mem_ready; // 仅真实命令接纳允许未来结果关联。
 assign o_mem_result_ready=active; // 全部槽预留结果空间，非法事件消费并诊断。
 assign result_fire=i_mem_result_valid&&o_mem_result_ready&&result_legal; // 真实完成只允许更新一次。
 assign head_result=active&&head_busy&&head_complete; // 未完成的执行绝不产生Header或Data。
 assign head_final=({1'b0,head_beat}+3'd1)==head_beats; // 本实现按OFFSET递增发送，最终发送Beat才LAST。
 endpoint_response_encode #(.FULL_READ_ENABLE(1)) u_response_encode( // 明确选择规范Single-Beat response模式。
  .i_valid(head_result&&!head_header),.i_tag(head_tag),.i_src(head_dst),.i_dst(head_src),.i_status(head_status), // 反向路由完整请求身份。
  .i_num_beats(2'd0),.i_offset(head_beat),.i_last(head_final),.i_vc(2'd0),.i_pool(1'b0), // 每Header恰好对应两Data半字。
  .o_valid(o_source_valid),.o_error(encode_error),.o_control(o_source_control)); // 真实低64位字段，其余NOP。
 assign header_fire=o_source_valid&&i_source_captured; // Header只捕获一次，但不提前释放当前Beat。
 assign o_data_valid=head_result?(2'd2-head_sent):2'd0; // 错误也保留全部N Beat的完整Data tenure。
 assign o_data=!head_result?512'd0:(head_sent==2'd0)?head_data:(head_sent==2'd1)?{256'd0,head_data[511:256]}:512'd0; // 部分接纳后未接纳高半字前移。
 assign data_legal=i_data_accepted<=o_data_valid; // 零至二项实际接纳不能超额。
 assign beat_done=head_result&&(head_header||header_fire)&&data_legal&&({1'b0,head_sent}+{1'b0,i_data_accepted}==3'd2); // Header与Data所有权独立闭合。
 assign retire=beat_done&&head_final; // 仅最后Beat完整交付才回收整事务槽。
 assign o_count=active?count_q:8'd0; // 非法配置和复位不公开旧占用。
 assign o_error=i_rstn&&(!CONFIG_LEGAL||(i_request_valid&&!request_legal)||(i_mem_result_valid&&!result_legal)||(i_source_captured&&!o_source_valid)||!data_legal||encode_error); // 普通满槽和等待不属于错误。
 always @(posedge i_clk)begin // 环形索引只随真实握手推进。
  if(!active)begin allocate_q<={SLOT_WIDTH{1'b0}};issue_q<={SLOT_WIDTH{1'b0}};head_q<={SLOT_WIDTH{1'b0}};count_q<=8'd0;end // 同步清空整个局部epoch。
  else begin // 接纳与退休可来自不同槽并行发生。
   if(request_fire)begin if(allocate_q==LAST_SLOT)allocate_q<={SLOT_WIDTH{1'b0}};else allocate_q<=allocate_q+1'b1;end // 不进入非二次幂未用尾索引。
   if(memory_fire)begin if(issue_q==LAST_SLOT)issue_q<={SLOT_WIDTH{1'b0}};else issue_q<=issue_q+1'b1;end // 后端命令按接纳顺序发出。
   if(retire)begin if(head_q==LAST_SLOT)head_q<={SLOT_WIDTH{1'b0}};else head_q<=head_q+1'b1;end // 整个事务发完才切换响应槽。
   case({request_fire,retire}) // 保持精确资源守恒。
    2'b10:count_q<=count_q+1'b1; // 预留新描述符与完整结果存储。
    2'b01:count_q<=count_q-1'b1; // 回收完整事务。
    default:count_q<=count_q; // 同时一进一出或空闲保持。
   endcase // 结束占用更新。
  end // 结束正常指针更新。
 end // 结束共享环状态。
 genvar slot; // 每个实际槽独立生成固定索引寄存器更新。
 for(slot=0;slot<SLOTS;slot=slot+1)begin:storage_slot // 不生成任何虚构RAM行。
  localparam [SLOT_WIDTH-1:0] THIS_SLOT=slot[SLOT_WIDTH-1:0]; // 固定真实槽索引。
  always @(posedge i_clk)begin // 只更新属于本槽的完整事务。
   if(!active)begin busy_q[slot]<=1'b0;issued_q[slot]<=1'b0;complete_q[slot]<=1'b0;header_q[slot]<=1'b0;beat_q[slot]<=2'd0;sent_q[slot]<=2'd0;end // 大数据无需复位，所有有效所有权清除。
   else begin // 同一槽从接纳至最后响应保持唯一所有者。
    if(request_fire&&allocate_q==THIS_SLOT)begin // 原子保存完整请求与预留资源。
     busy_q[slot]<=1'b1;issued_q[slot]<=1'b0;complete_q[slot]<=1'b0;header_q[slot]<=1'b0;beat_q[slot]<=2'd0;sent_q[slot]<=2'd0; // 新事务从相对Beat零开始。
     tag_q[slot]<=i_request_tag;src_q[slot]<=i_request_src;dst_q[slot]<=i_request_dst;address_q[slot]<=i_request_address;length_q[slot]<=i_request_length; // 保留57位地址和完整身份。
     attr_q[slot]<=i_request_attr;asi_q[slot]<=i_request_asi;metadata_q[slot]<=i_request_metadata;be_q[slot]<=request_be;beats_q[slot]<=request_beats; // BE全零也保留结构Beat数。
    end // 结束请求捕获。
    if(memory_fire&&issue_q==THIS_SLOT)issued_q[slot]<=1'b1; // 下一周期起允许真实结果关联。
    if(result_fire&&i_mem_result_slot==THIS_SLOT)begin // 按slot接收真实乱序后端结果。
     full_result_q[slot]<=i_mem_result_data_full; // 完整成功数据逐位保存，无压缩或截断。
     if(i_mem_result_status!=4'd0)full_result_q[slot]<=2048'd0; // 合法错误制造全零Data，但发送所有原定Beat。
     status_q[slot]<=i_mem_result_status;complete_q[slot]<=1'b1; // 整事务所有响应Beat共享同一完成状态。
    end // 非法结果没有任何状态写入。
    if(head_q==THIS_SLOT)begin // 当前响应所有权按Beat保持到两类捕获都完成。
     if(header_fire)header_q[slot]<=1'b1; // Header已移交后不再重复提供。
     if(head_result&&data_legal&&i_data_accepted!=2'd0)sent_q[slot]<=head_sent+i_data_accepted; // 精确记录部分Data接纳。
     if(beat_done)begin header_q[slot]<=1'b0;sent_q[slot]<=2'd0;if(!head_final)beat_q[slot]<=head_beat+1'b1;end // 当前Beat完整交付后才进入下一OFFSET。
     if(retire)begin busy_q[slot]<=1'b0;issued_q[slot]<=1'b0;complete_q[slot]<=1'b0;end // 最后Beat交付才回收数据与描述符所有权。
    end // 结束当前响应槽推进。
   end // 结束真实槽正常生命周期。
  end // 结束固定索引同步更新。
 end // 结束全部真实槽生成。
end endgenerate
endmodule // 结束兼容旧子集与完整普通Read执行器。
`default_nettype wire // 恢复外围编译单元默认网络规则。
