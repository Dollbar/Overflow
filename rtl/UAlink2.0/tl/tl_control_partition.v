module tl_control_partition #(parameter WIDTH=16)( // tl_control_partition模块：按总信用容量分组完整字段，保持单笔事务不变
 input wire i_clk,i_rstn,i_source_valid,i_ready,i_done,i_response,i_auth,i_shared, // 唯一时钟及同一初始化时期的类别、认证、共享状态
 input wire [255:0] i_source_control,input wire [511:0] i_source_tags, // 最多八个已准备字段及按字段排序的八个64位标签
 input wire [20*(WIDTH+1)-1:0] i_capacity, // 实际端口初始化后固定的物理容量，不是可变余额
 output wire o_valid,o_taken,o_source_taken,o_error,o_shortfall, // 分组入队确认与整个输入字段组完成确认分别返回
 output wire [255:0] o_control,o_tags,output wire [3:0] o_fields,o_end,o_cursor // 输出合法分组和本地扇区进度观察
); // 结束完整字段容量分组端口
generate if(WIDTH<8||WIDTH>16)begin:gen_invalid_width // 保持实际信用宽度范围的展开拒绝
 tl_control_partition_invalid_WIDTH invalid_parameter(); // 非法参数不能隐式截断费用
end endgenerate // 结束参数检查
reg [3:0] r_cursor; // 当前源中尚未入队的第一个扇区，原始字段自然对齐位置保持不变
wire decoded;wire [2:0] requests;wire [3:0] responses,total_fields; // 原始组的类别与合法字段数量
wire [7:0] starts,request_starts,response_starts,application_starts; // 实际解码树提供完整字段边界而非猜测payload位
wire [1:0] tenure_status;wire [31:0] unused_counts;wire [7:0] unused_be; // 已确认tenure合法性，不修改事务数据长度
wire [7:0] bad_fc,fit;wire [255:0] prefix[0:7];wire [3:0] prefix_fields[0:7]; // 八个可能边界及其完整字段提议
reg [3:0] selected_end,selected_fields,before_fields;reg [255:0] selected_control; // 当前最长可容纳前缀与此前已完成标签数
wire format_error;integer pick; // 静态展开边界优先级，无派生时钟或隐藏队列
 tl_control_decode Decode_Inst(i_source_control,decoded,requests,responses,starts,request_starts,response_starts); // 使用真实自然对齐树识别字段
 tl_control_tenure Tenure_Inst(i_source_control,tenure_status,total_fields,unused_counts,unused_be); // 未决编码不能绕过到容量逻辑
assign application_starts=request_starts|response_starts; // NOP/FC不拥有事务数据或认证标签
assign format_error=!decoded||(tenure_status!=2'd0)||(total_fields==4'd0)||(i_response?(requests!=3'd0):(responses!=4'd0))||(|bad_fc); // 不混类且拒绝把独立FC事件当作可重分组事务
assign o_error=i_rstn&&i_source_valid&&format_error; // 格式错误保留整组输入，禁止部分丢弃
assign o_valid=i_rstn&&i_done&&i_source_valid&&!format_error&&(selected_end!=4'd0); // 初始化容量稳定后才提出可入队分组
assign o_taken=o_valid&&i_ready;assign o_source_taken=o_taken&&(selected_end==4'd8); // 只有最后一组实际入队才释放源字段组
assign o_shortfall=i_rstn&&i_done&&i_source_valid&&!format_error&&(selected_end==4'd0); // 最早单字段也超容量时明确等待，不拆写事务
assign o_control=o_valid?selected_control:256'd0;assign o_fields=o_valid?selected_fields:4'd0;assign o_end=o_valid?selected_end:4'd0; // 无效提议不暴露旧字段或标签数量
assign o_cursor=i_rstn?r_cursor:4'd0; // 本地游标只由实际入队推进
wire [255:0] masked_source;wire masked_valid;wire [1:0] masked_status; // 所有候选复用游标之前清零的真实字段解释
wire [7:0] masked_requests,masked_responses,unused_masked_starts,unused_masked_be; // 仍包含游标落在字段内部时的实际掩码语义
wire [2:0] unused_masked_request_count;wire [3:0] unused_masked_response_count,unused_masked_fields; // 完整后缀的解码观察
wire [31:0] masked_counts;wire [39:0] w_slots;wire [959:0] prefix_cost; // 每槽八个六位前缀累计覆盖一至八个扇区
wire [7:0] unused_masked_count_lsb; // Data信用只消费完整Beat计数
assign unused_masked_count_lsb={masked_counts[28],masked_counts[24],masked_counts[20],masked_counts[16],masked_counts[12],masked_counts[8],masked_counts[4],masked_counts[0]}; // 显式标明未消费的半Flit奇偶位
 tl_control_decode Masked_Decode_Inst(masked_source,masked_valid,unused_masked_request_count,unused_masked_response_count,unused_masked_starts,masked_requests,masked_responses); // 一份掩码字段树服务全部候选
 tl_control_tenure #(.ZERO_ON_ERROR(1'b0)) Masked_Tenure_Inst(masked_source,masked_status,unused_masked_fields,masked_counts,unused_masked_be); // 内部Data量与错误并行派生，masked_status仍单独阻止非法分组
wire [1:0] w_vc0; // sector0字段VC
assign w_vc0=(masked_source[127:124]==4'd1)?masked_source[117:116]:((masked_source[63:60]==4'd2)?masked_source[59:58]:(masked_source[63:60]==4'd3)?masked_source[56:55]:masked_source[27:26]); // sector0字段VC
wire w_pool0; // sector0字段Pool
assign w_pool0=(masked_source[127:124]==4'd1)?masked_source[102]:((masked_source[63:60]==4'd2)?masked_source[46]:(masked_source[63:60]==4'd3)?masked_source[41]:masked_source[14]); // sector0字段Pool
wire [2:0] w_lane0; // Pool或专用VC
assign w_lane0=w_pool0?3'd0:({1'b0,w_vc0}+3'd1); // Pool或专用VC
assign w_slots[0+:5]=(masked_requests[0]?5'd10:5'd15)+{2'd0,w_lane0}; // 请求与响应Data类
wire [1:0] w_vc1; // sector1字段VC
assign w_vc1=masked_source[59:58]; // sector1字段VC
wire w_pool1; // sector1字段Pool
assign w_pool1=masked_source[46]; // sector1字段Pool
wire [2:0] w_lane1; // Pool或专用VC
assign w_lane1=w_pool1?3'd0:({1'b0,w_vc1}+3'd1); // Pool或专用VC
assign w_slots[5+:5]=(masked_requests[1]?5'd10:5'd15)+{2'd0,w_lane1}; // 请求与响应Data类
wire [1:0] w_vc2; // sector2字段VC
assign w_vc2=(masked_source[127:124]==4'd2)?masked_source[123:122]:(masked_source[127:124]==4'd3)?masked_source[120:119]:masked_source[91:90]; // sector2字段VC
wire w_pool2; // sector2字段Pool
assign w_pool2=(masked_source[127:124]==4'd2)?masked_source[110]:(masked_source[127:124]==4'd3)?masked_source[105]:masked_source[78]; // sector2字段Pool
wire [2:0] w_lane2; // Pool或专用VC
assign w_lane2=w_pool2?3'd0:({1'b0,w_vc2}+3'd1); // Pool或专用VC
assign w_slots[10+:5]=(masked_requests[2]?5'd10:5'd15)+{2'd0,w_lane2}; // 请求与响应Data类
wire [1:0] w_vc3; // sector3字段VC
assign w_vc3=masked_source[123:122]; // sector3字段VC
wire w_pool3; // sector3字段Pool
assign w_pool3=masked_source[110]; // sector3字段Pool
wire [2:0] w_lane3; // Pool或专用VC
assign w_lane3=w_pool3?3'd0:({1'b0,w_vc3}+3'd1); // Pool或专用VC
assign w_slots[15+:5]=(masked_requests[3]?5'd10:5'd15)+{2'd0,w_lane3}; // 请求与响应Data类
wire [1:0] w_vc4; // sector4字段VC
assign w_vc4=(masked_source[255:252]==4'd1)?masked_source[245:244]:((masked_source[191:188]==4'd2)?masked_source[187:186]:(masked_source[191:188]==4'd3)?masked_source[184:183]:masked_source[155:154]); // sector4字段VC
wire w_pool4; // sector4字段Pool
assign w_pool4=(masked_source[255:252]==4'd1)?masked_source[230]:((masked_source[191:188]==4'd2)?masked_source[174]:(masked_source[191:188]==4'd3)?masked_source[169]:masked_source[142]); // sector4字段Pool
wire [2:0] w_lane4; // Pool或专用VC
assign w_lane4=w_pool4?3'd0:({1'b0,w_vc4}+3'd1); // Pool或专用VC
assign w_slots[20+:5]=(masked_requests[4]?5'd10:5'd15)+{2'd0,w_lane4}; // 请求与响应Data类
wire [1:0] w_vc5; // sector5字段VC
assign w_vc5=masked_source[187:186]; // sector5字段VC
wire w_pool5; // sector5字段Pool
assign w_pool5=masked_source[174]; // sector5字段Pool
wire [2:0] w_lane5; // Pool或专用VC
assign w_lane5=w_pool5?3'd0:({1'b0,w_vc5}+3'd1); // Pool或专用VC
assign w_slots[25+:5]=(masked_requests[5]?5'd10:5'd15)+{2'd0,w_lane5}; // 请求与响应Data类
wire [1:0] w_vc6; // sector6字段VC
assign w_vc6=(masked_source[255:252]==4'd2)?masked_source[251:250]:(masked_source[255:252]==4'd3)?masked_source[248:247]:masked_source[219:218]; // sector6字段VC
wire w_pool6; // sector6字段Pool
assign w_pool6=(masked_source[255:252]==4'd2)?masked_source[238]:(masked_source[255:252]==4'd3)?masked_source[233]:masked_source[206]; // sector6字段Pool
wire [2:0] w_lane6; // Pool或专用VC
assign w_lane6=w_pool6?3'd0:({1'b0,w_vc6}+3'd1); // Pool或专用VC
assign w_slots[30+:5]=(masked_requests[6]?5'd10:5'd15)+{2'd0,w_lane6}; // 请求与响应Data类
wire [1:0] w_vc7; // sector7字段VC
assign w_vc7=masked_source[251:250]; // sector7字段VC
wire w_pool7; // sector7字段Pool
assign w_pool7=masked_source[238]; // sector7字段Pool
wire [2:0] w_lane7; // Pool或专用VC
assign w_lane7=w_pool7?3'd0:({1'b0,w_vc7}+3'd1); // Pool或专用VC
assign w_slots[35+:5]=(masked_requests[7]?5'd10:5'd15)+{2'd0,w_lane7}; // 请求与响应Data类
genvar account,field;generate for(account=0;account<20;account=account+1)begin:gen_shared_cost // 每个物理账户的字段费用只计算一次
 localparam [4:0] ACCOUNT=account[4:0];localparam [4:0] COMMAND_DATA_SLOT=account+10; // CMD账户按原逻辑Data编号关联
 wire [5:0] contribution[0:7];wire [5:0] pair[0:3];wire [5:0] quad[0:1]; // 六位完整容纳八命令或三十二Data信用
 for(field=0;field<8;field=field+1)begin:gen_field_cost // 八个自然位置在所有完整候选中复用
  if(account<10)begin:gen_cmd // 每实际CMD字段计一个信用
   assign contribution[field]=((masked_requests[field]||masked_responses[field])&&(w_slots[field*5+:5]==COMMAND_DATA_SLOT))?6'd1:6'd0; // 保持原CMD账户编号
  end else begin:gen_data // 完整Data Beat信用在物理账户累加
  wire [4:0] physical_data_slot; // 两个Data Pool在初始化共享模式下归一化
  assign physical_data_slot=(i_shared&&(w_slots[field*5+:5]==5'd15))?5'd10:w_slots[field*5+:5]; // CMD及专用VC不合并
   assign contribution[field]=((masked_requests[field]||masked_responses[field])&&(physical_data_slot==ACCOUNT))?{3'd0,masked_counts[field*4+1+:3]}:6'd0; // BE不增加Data信用
  end // 结束CMD与Data静态选择
 end // 结束八字段费用
 assign pair[0]=contribution[0]+contribution[1];assign pair[1]=contribution[2]+contribution[3]; // 低半字的二字段并行归约
 assign pair[2]=contribution[4]+contribution[5];assign pair[3]=contribution[6]+contribution[7]; // 高半字的二字段并行归约
 assign quad[0]=pair[0]+pair[1];assign quad[1]=pair[2]+pair[3]; // 两个四字段完整费用
assign prefix_cost[(account*8+0)*6+:6]=contribution[0]; // 首字段前缀
 assign prefix_cost[(account*8+1)*6+:6]=pair[0];assign prefix_cost[(account*8+2)*6+:6]=pair[0]+contribution[2]; // 两字段及三字段前缀
 assign prefix_cost[(account*8+3)*6+:6]=quad[0];assign prefix_cost[(account*8+4)*6+:6]=quad[0]+contribution[4]; // 四字段及五字段前缀
 assign prefix_cost[(account*8+5)*6+:6]=quad[0]+pair[2];assign prefix_cost[(account*8+6)*6+:6]=quad[0]+(pair[2]+contribution[6]); // 六字段及七字段前缀
 assign prefix_cost[(account*8+7)*6+:6]=quad[0]+quad[1]; // 八字段平衡总和
end endgenerate // 结束复用费用与八种前缀累计
wire [511:0] tags_offset_one,tags_offset_two;wire [255:0] tags_shifted; // 四个输出槽共用已完成字段数的标签移位
assign tags_offset_one=before_fields[0]?{64'd0,i_source_tags[511:64]}:i_source_tags; // 第一层选择零或一个64位标签偏移
assign tags_offset_two=before_fields[1]?{128'd0,tags_offset_one[511:128]}:tags_offset_one; // 第二层选择零或两个标签偏移
assign tags_shifted=before_fields[3]?256'd0:(before_fields[2]?tags_offset_two[511:256]:tags_offset_two[255:0]); // 第三层选择低四或高四标签，源外偏移全部清零
genvar boundary,sector,tag,slot;generate // 固定八个边界和四个输出认证槽
for(sector=0;sector<8;sector=sector+1)begin:gen_fc_check // 解码标为非事务起点的单扇区只允许全零NOP
 localparam [3:0] MASK_POSITION=sector[3:0]; // 显式四位游标比较
 assign masked_source[sector*32+:32]=(r_cursor<=MASK_POSITION)?i_source_control[sector*32+:32]:32'd0; // 所有候选共同的游标清零后缀
 assign bad_fc[sector]=starts[sector]&&!application_starts[sector]&&(i_source_control[sector*32+:32]!=32'd0); // 非零FC需走独立发布器而非此接口
end // 结束源NOP字段检查
for(boundary=0;boundary<8;boundary=boundary+1)begin:gen_prefix // 每个候选只在完整字段边界结束
 localparam integer END_VALUE=boundary+1;localparam [3:0] END_SECTOR=END_VALUE[3:0]; // 四位表示结束扇区一至八
 wire complete_boundary,allowed;wire [19:0] capacity_fit;wire [7:0] selected_starts; // 每组容量检查与字段计数
 if(boundary==7)begin:gen_last // 第八扇区之后必为完整源结尾
  assign complete_boundary=1'b1; // 不访问边界以外的起点位
 end else begin:gen_inner // 中间边界必须是下一个已解码字段起点
  assign complete_boundary=starts[boundary+1]; // 禁止在双扇区或四扇区字段内部切断
 end // 结束字段边界选择
 for(sector=0;sector<8;sector=sector+1)begin:gen_sector // 保留自然对齐位置，省略字段用NOP清零
  localparam [3:0] POSITION=sector[3:0]; // 将生成索引限制到本地游标比较宽度
  assign prefix[boundary][sector*32+:32]=((r_cursor<=POSITION)&&(sector<=boundary))?i_source_control[sector*32+:32]:32'd0; // 所有原字段位完整保留或整体由边界排除
  assign selected_starts[sector]=application_starts[sector]&&(r_cursor<=POSITION)&&(sector<=boundary); // 只计入仍属当前前缀的事务字段
 end // 结束候选扇区掩码
 assign prefix_fields[boundary]={3'd0,selected_starts[0]}+{3'd0,selected_starts[1]}+{3'd0,selected_starts[2]}+{3'd0,selected_starts[3]}+{3'd0,selected_starts[4]}+{3'd0,selected_starts[5]}+{3'd0,selected_starts[6]}+{3'd0,selected_starts[7]}; // 四位完整表示零至八个字段
 for(slot=0;slot<20;slot=slot+1)begin:gen_capacity_fit // 每候选只比较已共享计算的实际费用
  wire [WIDTH:0] need; // 六位需求无损扩展到原信用计数宽度
  assign need={{(WIDTH-5){1'b0}},prefix_cost[(slot*8+boundary)*6+:6]}; // 只取对应完整边界的六位前缀
  assign capacity_fit[slot]=need<=i_capacity[slot*(WIDTH+1)+:WIDTH+1]; // 保持所有物理账户的原比较意义
 end // 结束二十槽容量判断
 assign allowed=i_rstn&&i_done&&masked_valid&&(masked_status==2'd0)&&(&capacity_fit); // 原格式及初始化门控仍通过实际字段解析
 assign fit[boundary]=(r_cursor<END_SECTOR)&&complete_boundary&&(prefix_fields[boundary]!=4'd0)&&(!i_auth||(prefix_fields[boundary]<=4'd4))&&allowed; // 完整非空字段组同时满足容量与Auth槽限制
end // 结束八种完整前缀候选
for(tag=0;tag<4;tag=tag+1)begin:gen_tag // 标签跟随未修改的事务字段顺序重新从低槽开始
 localparam [3:0] TAG_POSITION=tag[3:0]; // 输出槽编号与字段数量匹配
 assign o_tags[tag*64+:64]=(o_valid&&i_auth&&(TAG_POSITION<selected_fields))?tags_shifted[tag*64+:64]:64'd0; // 所有未使用槽必须清零
end // 结束认证标签槽映射
endgenerate // 结束完整字段、容量与标签生成结构
always @* begin // 选择最长合格完整前缀，并数出已入队标签
 selected_end=4'd0;selected_fields=4'd0;selected_control=256'd0;before_fields=4'd0; // 完整组合默认值
 for(pick=0;pick<8;pick=pick+1)begin // 顺序覆盖实现最高完整边界优先
  if(fit[pick])begin selected_end=pick[3:0]+4'd1;selected_fields=prefix_fields[pick];selected_control=prefix[pick];end // 合格边界永不切割原始字段
  if(application_starts[pick]&&(pick[3:0]<r_cursor))before_fields=before_fields+4'd1; // NOP不占认证槽
 end // 结束最长前缀与标签前缀计数
end // 结束组合分组提议
always @(posedge i_clk)begin // 唯一状态记录实际下游头部队列的接纳进度
 if(!i_rstn)r_cursor<=4'd0; // 同步复位取消旧批次所有权
 else if(o_taken)r_cursor<=o_source_taken?4'd0:selected_end; // 停顿或超容量时完整保持源游标
end // 结束分组游标寄存器
endmodule // 结束tl_control_partition模块
