module tl_prepared_partition #(parameter WIDTH=16)( // tl_prepared_partition模块：寄存完整源字段元数据并按容量分组
 input wire i_clk,i_rstn,i_source_valid,i_ready,i_done,i_response,i_auth,i_shared, // 唯一时钟、同步复位及本次捕获的初始化属性
 input wire [255:0] i_source_control,input wire [511:0] i_source_tags, // 捕获后由本模块持有的完整字段与八个认证标签
 input wire [20*(WIDTH+1)-1:0] i_capacity, // 当前初始化时期的二十个物理总容量
 output wire o_source_ready,o_captured,o_valid,o_taken,o_group_done,o_error,o_shortfall, // 捕获、分组接纳和整组完成分别握手
 output wire [255:0] o_control,o_tags,output wire [3:0] o_fields,o_end,o_cursor // 完整字段输出及本地分组进度
); // 结束注册化准备端口
 generate if(WIDTH<8||WIDTH>16)begin:gen_invalid_width // 合法信用位宽与下游端口保持一致
  tl_prepared_partition_invalid_WIDTH invalid_parameter(); // 非法参数在展开时拒绝
 end endgenerate // 结束位宽检查
reg r_owned,r_error,r_auth,r_shared;reg [3:0] r_cursor; // 所有权、已捕获属性与完整字段游标
reg [255:0] r_control;reg [511:0] r_tags;reg [20*(WIDTH+1)-1:0] r_capacity; // 源在捕获后可以立即改变输入
reg [7:1] r_starts;reg [7:0] r_application;reg [31:0] r_counts;reg [39:0] r_slots; // 发射端只消费寄存描述符，零扇区之前不需要结束边界
wire decoded;wire [2:0] requests;wire [3:0] responses,total_fields; // 输入预解码的字段数量及类别
wire [7:0] starts,request_starts,response_starts,application_starts,bad_fc; // 原始完整字段边界和非零FC检查
wire [1:0] tenure_status;wire [31:0] source_counts;wire [7:0] unused_be;wire [39:0] source_slots; // 预解码Data量与逻辑账户
wire [7:0] selected_sectors;wire [3:0] selected_tags; // 最长合格边界的扇区和标签资格并行归约
wire format_error;wire [7:0] fit;wire [3:0] prefix_fields[0:7];wire [959:0] prefix_cost; // 八个合法边界候选及其二十槽费用
reg [3:0] selected_end,selected_fields,before_fields;wire [255:0] selected_control;integer pick; // 最长完整前缀与认证标签位置
 tl_control_decode Decode_Inst(i_source_control,decoded,requests,responses,starts,request_starts,response_starts); // 捕获端只解析一次真实自然对齐字段树
 tl_control_tenure Tenure_Inst(i_source_control,tenure_status,total_fields,source_counts,unused_be); // 捕获前验证全部事务tenure
assign application_starts=request_starts|response_starts; // 事务起点不包含NOP或FC
assign format_error=!decoded||(tenure_status!=2'd0)||(total_fields==4'd0)||(i_response?(requests!=3'd0):(responses!=4'd0))||(|bad_fc); // 保存全组格式拒绝条件
assign o_error=i_rstn&&r_owned&&r_error; // 已接纳错误组保持所有权直至复位
assign o_valid=i_rstn&&r_owned&&!r_error&&(|fit); // 输出不再依赖已捕获之后的实时源或done
assign o_taken=o_valid&&i_ready;assign o_group_done=o_taken&&(selected_end==4'd8); // 只在最后完整分组被接纳时退休整组
assign o_source_ready=i_rstn&&i_done&&(!r_owned||o_group_done); // 空槽或最后分组同拍退休允许接纳下一个源
assign o_captured=o_source_ready&&i_source_valid; // 输入接纳不是整组成功发射确认
assign o_shortfall=i_rstn&&r_owned&&!r_error&&!(|fit); // 捕获容量无法容纳最早字段时保持等待直到复位
assign o_control=o_valid?selected_control:256'd0;assign o_fields=o_valid?selected_fields:4'd0;assign o_end=o_valid?selected_end:4'd0; // 无效时明确清零可见负载
assign o_cursor=i_rstn?r_cursor:4'd0; // 同步复位取消旧游标并屏蔽复位周期输出
wire [7:0] unused_count_lsb; // Data信用使用完整64B的计数，最低Flit位不消费
assign unused_count_lsb={r_counts[28],r_counts[24],r_counts[20],r_counts[16],r_counts[12],r_counts[8],r_counts[4],r_counts[0]}; // 显式保留未消费位的审计说明
wire [1:0] w_vc0; // sector0字段VC
assign w_vc0=(i_source_control[127:124]==4'd1)?i_source_control[117:116]:((i_source_control[63:60]==4'd2)?i_source_control[59:58]:(i_source_control[63:60]==4'd3)?i_source_control[56:55]:i_source_control[27:26]); // sector0字段VC
wire w_pool0; // sector0字段Pool
assign w_pool0=(i_source_control[127:124]==4'd1)?i_source_control[102]:((i_source_control[63:60]==4'd2)?i_source_control[46]:(i_source_control[63:60]==4'd3)?i_source_control[41]:i_source_control[14]); // sector0字段Pool
wire [2:0] w_lane0; // Pool或专用VC
assign w_lane0=w_pool0?3'd0:({1'b0,w_vc0}+3'd1); // Pool或专用VC
assign source_slots[0+:5]=(request_starts[0]?5'd10:5'd15)+{2'd0,w_lane0}; // 请求与响应Data类
wire [1:0] w_vc1; // sector1字段VC
assign w_vc1=i_source_control[59:58]; // sector1字段VC
wire w_pool1; // sector1字段Pool
assign w_pool1=i_source_control[46]; // sector1字段Pool
wire [2:0] w_lane1; // Pool或专用VC
assign w_lane1=w_pool1?3'd0:({1'b0,w_vc1}+3'd1); // Pool或专用VC
assign source_slots[5+:5]=(request_starts[1]?5'd10:5'd15)+{2'd0,w_lane1}; // 请求与响应Data类
wire [1:0] w_vc2; // sector2字段VC
assign w_vc2=(i_source_control[127:124]==4'd2)?i_source_control[123:122]:(i_source_control[127:124]==4'd3)?i_source_control[120:119]:i_source_control[91:90]; // sector2字段VC
wire w_pool2; // sector2字段Pool
assign w_pool2=(i_source_control[127:124]==4'd2)?i_source_control[110]:(i_source_control[127:124]==4'd3)?i_source_control[105]:i_source_control[78]; // sector2字段Pool
wire [2:0] w_lane2; // Pool或专用VC
assign w_lane2=w_pool2?3'd0:({1'b0,w_vc2}+3'd1); // Pool或专用VC
assign source_slots[10+:5]=(request_starts[2]?5'd10:5'd15)+{2'd0,w_lane2}; // 请求与响应Data类
wire [1:0] w_vc3; // sector3字段VC
assign w_vc3=i_source_control[123:122]; // sector3字段VC
wire w_pool3; // sector3字段Pool
assign w_pool3=i_source_control[110]; // sector3字段Pool
wire [2:0] w_lane3; // Pool或专用VC
assign w_lane3=w_pool3?3'd0:({1'b0,w_vc3}+3'd1); // Pool或专用VC
assign source_slots[15+:5]=(request_starts[3]?5'd10:5'd15)+{2'd0,w_lane3}; // 请求与响应Data类
wire [1:0] w_vc4; // sector4字段VC
assign w_vc4=(i_source_control[255:252]==4'd1)?i_source_control[245:244]:((i_source_control[191:188]==4'd2)?i_source_control[187:186]:(i_source_control[191:188]==4'd3)?i_source_control[184:183]:i_source_control[155:154]); // sector4字段VC
wire w_pool4; // sector4字段Pool
assign w_pool4=(i_source_control[255:252]==4'd1)?i_source_control[230]:((i_source_control[191:188]==4'd2)?i_source_control[174]:(i_source_control[191:188]==4'd3)?i_source_control[169]:i_source_control[142]); // sector4字段Pool
wire [2:0] w_lane4; // Pool或专用VC
assign w_lane4=w_pool4?3'd0:({1'b0,w_vc4}+3'd1); // Pool或专用VC
assign source_slots[20+:5]=(request_starts[4]?5'd10:5'd15)+{2'd0,w_lane4}; // 请求与响应Data类
wire [1:0] w_vc5; // sector5字段VC
assign w_vc5=i_source_control[187:186]; // sector5字段VC
wire w_pool5; // sector5字段Pool
assign w_pool5=i_source_control[174]; // sector5字段Pool
wire [2:0] w_lane5; // Pool或专用VC
assign w_lane5=w_pool5?3'd0:({1'b0,w_vc5}+3'd1); // Pool或专用VC
assign source_slots[25+:5]=(request_starts[5]?5'd10:5'd15)+{2'd0,w_lane5}; // 请求与响应Data类
wire [1:0] w_vc6; // sector6字段VC
assign w_vc6=(i_source_control[255:252]==4'd2)?i_source_control[251:250]:(i_source_control[255:252]==4'd3)?i_source_control[248:247]:i_source_control[219:218]; // sector6字段VC
wire w_pool6; // sector6字段Pool
assign w_pool6=(i_source_control[255:252]==4'd2)?i_source_control[238]:(i_source_control[255:252]==4'd3)?i_source_control[233]:i_source_control[206]; // sector6字段Pool
wire [2:0] w_lane6; // Pool或专用VC
assign w_lane6=w_pool6?3'd0:({1'b0,w_vc6}+3'd1); // Pool或专用VC
assign source_slots[30+:5]=(request_starts[6]?5'd10:5'd15)+{2'd0,w_lane6}; // 请求与响应Data类
wire [1:0] w_vc7; // sector7字段VC
assign w_vc7=i_source_control[251:250]; // sector7字段VC
wire w_pool7; // sector7字段Pool
assign w_pool7=i_source_control[238]; // sector7字段Pool
wire [2:0] w_lane7; // Pool或专用VC
assign w_lane7=w_pool7?3'd0:({1'b0,w_vc7}+3'd1); // Pool或专用VC
assign source_slots[35+:5]=(request_starts[7]?5'd10:5'd15)+{2'd0,w_lane7}; // 请求与响应Data类
genvar account,field;generate for(account=0;account<20;account=account+1)begin:gen_shared_cost // 每个物理账户的字段费用只计算一次
 localparam [4:0] ACCOUNT=account[4:0];localparam [4:0] COMMAND_DATA_SLOT=account+10; // CMD账户按原逻辑Data编号关联
 wire [5:0] contribution[0:7]; // 六位完整容纳八命令或三十二Data信用
 for(field=0;field<8;field=field+1)begin:gen_field_cost // 八个自然位置在所有完整候选中复用
  localparam [3:0] FIELD_POSITION=field[3:0]; // 后缀掩码仅作用于已捕获的完整字段起点
  if(account<10)begin:gen_cmd // 每实际CMD字段计一个信用
   assign contribution[field]=((r_application[field]&&(r_cursor<=FIELD_POSITION))&&(r_slots[field*5+:5]==COMMAND_DATA_SLOT))?6'd1:6'd0; // 保持原CMD账户编号
  end else begin:gen_data // 完整Data Beat信用在物理账户累加
  wire physical_match; // 静态账户直接判断共享映射，避免先选择五位编号再比较
  if(account==10)begin:gen_pool_destination // 请求Data Pool接收共享响应Pool
   assign physical_match=(r_slots[field*5+:5]==5'd10)||(r_shared&&(r_slots[field*5+:5]==5'd15)); // 两个原始Pool直接归约到共享目标
  end else if(account==15)begin:gen_pool_source // 独立响应Data Pool只在非共享模式使用
   assign physical_match=!r_shared&&(r_slots[field*5+:5]==5'd15); // 共享模式不重复计入被合并账户
  end else begin:gen_dedicated_data // 专用VC账户不依赖共享Pool选择
   assign physical_match=(r_slots[field*5+:5]==ACCOUNT); // 固定账户与原始编号直接比较
  end // 结束静态物理Data账户匹配
   assign contribution[field]=((r_application[field]&&(r_cursor<=FIELD_POSITION))&&physical_match)?{3'd0,r_counts[field*4+1+:3]}:6'd0; // BE不增加Data信用
  end // 结束CMD与Data静态选择
 end // 结束八字段费用
// BEGIN_COST_COMPRESSION
 wire [5:0] cost_sum_0,cost_carry_0; // 三操作数六位进位保存结果
 assign cost_sum_0=contribution[0]^contribution[1]^contribution[2]; // 同位异或不沿位传播进位
 assign cost_carry_0=((contribution[0]&contribution[1])|(contribution[0]&contribution[2])|(contribution[1]&contribution[2]))<<1; // 多数位左移，六位模加法保持原截断语义
 wire [5:0] cost_sum_1,cost_carry_1; // 三操作数六位进位保存结果
 assign cost_sum_1=cost_sum_0^cost_carry_0^contribution[3]; // 同位异或不沿位传播进位
 assign cost_carry_1=((cost_sum_0&cost_carry_0)|(cost_sum_0&contribution[3])|(cost_carry_0&contribution[3]))<<1; // 多数位左移，六位模加法保持原截断语义
 wire [5:0] cost_sum_2,cost_carry_2; // 三操作数六位进位保存结果
 assign cost_sum_2=cost_sum_1^cost_carry_1^contribution[4]; // 同位异或不沿位传播进位
 assign cost_carry_2=((cost_sum_1&cost_carry_1)|(cost_sum_1&contribution[4])|(cost_carry_1&contribution[4]))<<1; // 多数位左移，六位模加法保持原截断语义
 wire [5:0] cost_sum_3,cost_carry_3; // 三操作数六位进位保存结果
 assign cost_sum_3=contribution[3]^contribution[4]^contribution[5]; // 同位异或不沿位传播进位
 assign cost_carry_3=((contribution[3]&contribution[4])|(contribution[3]&contribution[5])|(contribution[4]&contribution[5]))<<1; // 多数位左移，六位模加法保持原截断语义
 wire [5:0] cost_sum_4,cost_carry_4; // 三操作数六位进位保存结果
 assign cost_sum_4=cost_sum_0^cost_carry_0^cost_sum_3; // 同位异或不沿位传播进位
 assign cost_carry_4=((cost_sum_0&cost_carry_0)|(cost_sum_0&cost_sum_3)|(cost_carry_0&cost_sum_3))<<1; // 多数位左移，六位模加法保持原截断语义
 wire [5:0] cost_sum_5,cost_carry_5; // 三操作数六位进位保存结果
 assign cost_sum_5=cost_sum_4^cost_carry_4^cost_carry_3; // 同位异或不沿位传播进位
 assign cost_carry_5=((cost_sum_4&cost_carry_4)|(cost_sum_4&cost_carry_3)|(cost_carry_4&cost_carry_3))<<1; // 多数位左移，六位模加法保持原截断语义
 wire [5:0] cost_sum_6,cost_carry_6; // 三操作数六位进位保存结果
 assign cost_sum_6=cost_sum_5^cost_carry_5^contribution[6]; // 同位异或不沿位传播进位
 assign cost_carry_6=((cost_sum_5&cost_carry_5)|(cost_sum_5&contribution[6])|(cost_carry_5&contribution[6]))<<1; // 多数位左移，六位模加法保持原截断语义
 wire [5:0] cost_sum_7,cost_carry_7; // 三操作数六位进位保存结果
 assign cost_sum_7=cost_carry_3^contribution[6]^contribution[7]; // 同位异或不沿位传播进位
 assign cost_carry_7=((cost_carry_3&contribution[6])|(cost_carry_3&contribution[7])|(contribution[6]&contribution[7]))<<1; // 多数位左移，六位模加法保持原截断语义
 wire [5:0] cost_sum_8,cost_carry_8; // 三操作数六位进位保存结果
 assign cost_sum_8=cost_sum_4^cost_carry_4^cost_sum_7; // 同位异或不沿位传播进位
 assign cost_carry_8=((cost_sum_4&cost_carry_4)|(cost_sum_4&cost_sum_7)|(cost_carry_4&cost_sum_7))<<1; // 多数位左移，六位模加法保持原截断语义
 wire [5:0] cost_sum_9,cost_carry_9; // 三操作数六位进位保存结果
 assign cost_sum_9=cost_sum_8^cost_carry_8^cost_carry_7; // 同位异或不沿位传播进位
 assign cost_carry_9=((cost_sum_8&cost_carry_8)|(cost_sum_8&cost_carry_7)|(cost_carry_8&cost_carry_7))<<1; // 多数位左移，六位模加法保持原截断语义
 assign prefix_cost[(account*8+0)*6+:6]=contribution[0]; // 完整前缀只在末级传播一次进位
 assign prefix_cost[(account*8+1)*6+:6]=contribution[0]+contribution[1]; // 完整前缀只在末级传播一次进位
 assign prefix_cost[(account*8+2)*6+:6]=cost_sum_0+cost_carry_0; // 完整前缀只在末级传播一次进位
 assign prefix_cost[(account*8+3)*6+:6]=cost_sum_1+cost_carry_1; // 完整前缀只在末级传播一次进位
 assign prefix_cost[(account*8+4)*6+:6]=cost_sum_2+cost_carry_2; // 完整前缀只在末级传播一次进位
 assign prefix_cost[(account*8+5)*6+:6]=cost_sum_5+cost_carry_5; // 完整前缀只在末级传播一次进位
 assign prefix_cost[(account*8+6)*6+:6]=cost_sum_6+cost_carry_6; // 完整前缀只在末级传播一次进位
 assign prefix_cost[(account*8+7)*6+:6]=cost_sum_9+cost_carry_9; // 完整前缀只在末级传播一次进位
// END_COST_COMPRESSION
end endgenerate // 结束复用费用与八种前缀累计
wire [511:0] tags_offset_one,tags_offset_two;wire [255:0] tags_shifted; // 四个输出槽共用已完成字段数的标签移位
assign tags_offset_one=before_fields[0]?{64'd0,r_tags[511:64]}:r_tags; // 第一层选择零或一个64位标签偏移
assign tags_offset_two=before_fields[1]?{128'd0,tags_offset_one[511:128]}:tags_offset_one; // 第二层选择零或两个标签偏移
assign tags_shifted=before_fields[3]?256'd0:(before_fields[2]?tags_offset_two[511:256]:tags_offset_two[255:0]); // 第三层选择低四或高四标签，源外偏移全部清零
genvar boundary,sector,tag,slot;generate // 固定八个边界和四个输出认证槽
for(sector=0;sector<8;sector=sector+1)begin:gen_selected_sector // 任意更高合格边界都包含当前自然扇区
 localparam [3:0] POSITION=sector[3:0]; // 游标比较保留全部四位意义
 assign selected_sectors[sector]=(r_cursor<=POSITION)&&(|fit[7:sector]); // 直接归约合格边界，避免宽载荷优先选择链
 assign selected_control[sector*32+:32]=selected_sectors[sector]?r_control[sector*32+:32]:32'd0; // 每扇区只有一次有效数据掩码
end // 结束最长合格前缀的直接扇区选择
for(sector=0;sector<8;sector=sector+1)begin:gen_fc_check // 捕获前的非事务单扇区只允许全零NOP
 assign bad_fc[sector]=starts[sector]&&!application_starts[sector]&&(i_source_control[sector*32+:32]!=32'd0); // FC事件由独立发布器处理
end // 结束源NOP检查
for(boundary=0;boundary<8;boundary=boundary+1)begin:gen_prefix // 每个候选只在完整字段边界结束
 localparam integer END_VALUE=boundary+1;localparam [3:0] END_SECTOR=END_VALUE[3:0]; // 四位表示结束扇区一至八
 wire complete_boundary,allowed;wire [19:0] capacity_fit;wire [7:0] selected_starts; // 每组容量检查与字段计数
 if(boundary==7)begin:gen_last // 第八扇区之后必为完整源结尾
  assign complete_boundary=1'b1; // 不访问边界以外的起点位
 end else begin:gen_inner // 中间边界必须是下一个已解码字段起点
  assign complete_boundary=r_starts[boundary+1]; // 禁止在双扇区或四扇区字段内部切断
 end // 结束字段边界选择
 for(sector=0;sector<8;sector=sector+1)begin:gen_sector // 保留自然对齐位置，省略字段用NOP清零
  localparam [3:0] POSITION=sector[3:0]; // 将生成索引限制到本地游标比较宽度
  assign selected_starts[sector]=r_application[sector]&&(r_cursor<=POSITION)&&(sector<=boundary); // 只计入仍属当前前缀的事务字段
 end // 结束候选扇区掩码
 assign prefix_fields[boundary]={3'd0,selected_starts[0]}+{3'd0,selected_starts[1]}+{3'd0,selected_starts[2]}+{3'd0,selected_starts[3]}+{3'd0,selected_starts[4]}+{3'd0,selected_starts[5]}+{3'd0,selected_starts[6]}+{3'd0,selected_starts[7]}; // 四位完整表示零至八个字段
 for(slot=0;slot<20;slot=slot+1)begin:gen_capacity_fit // 每候选只比较已共享计算的实际费用
  wire [WIDTH:0] need; // 六位需求无损扩展到原信用计数宽度
  assign need={{(WIDTH-5){1'b0}},prefix_cost[(slot*8+boundary)*6+:6]}; // 只取对应完整边界的六位前缀
  assign capacity_fit[slot]=need<=r_capacity[slot*(WIDTH+1)+:WIDTH+1]; // 保持所有物理账户的原比较意义
 end // 结束二十槽容量判断
 assign allowed=(&capacity_fit); // 费用只依赖已捕获描述符与容量，格式由r_error统一门控
 assign fit[boundary]=(r_cursor<END_SECTOR)&&complete_boundary&&(prefix_fields[boundary]!=4'd0)&&(!r_auth||(prefix_fields[boundary]<=4'd4))&&allowed; // 完整非空字段组同时满足容量与Auth槽限制
end // 结束八种完整前缀候选
for(tag=0;tag<4;tag=tag+1)begin:gen_tag // 标签跟随未修改的事务字段顺序重新从低槽开始
 localparam [3:0] TAG_POSITION=tag[3:0]; // 输出槽编号与字段数量匹配
 wire [7:0] tag_eligible; // 每个合格前缀是否包含本输出标签槽
 for(boundary=0;boundary<8;boundary=boundary+1)begin:gen_eligible // 字段数随边界单调增加，不需要再次选择最长字段数
  assign tag_eligible[boundary]=fit[boundary]&&(TAG_POSITION<prefix_fields[boundary]); // 合格前缀含此标签即可证明最长合格前缀也包含
 end // 结束八个边界的标签资格
 assign selected_tags[tag]=|tag_eligible; // 并行资格归约代替字段计数的优先选择后再比较
 assign o_tags[tag*64+:64]=(i_rstn&&r_owned&&!r_error&&r_auth&&selected_tags[tag])?tags_shifted[tag*64+:64]:64'd0; // 所有未使用槽必须清零
end // 结束认证标签槽映射
endgenerate // 结束完整字段、容量与标签生成结构
always @* begin // 选择最长合格完整前缀，并数出已入队标签
 selected_end=4'd0;selected_fields=4'd0;before_fields=4'd0; // 完整组合默认值
 for(pick=0;pick<8;pick=pick+1)begin // 顺序覆盖实现最高完整边界优先
  if(fit[pick])begin selected_end=pick[3:0]+4'd1;selected_fields=prefix_fields[pick];end // 合格边界永不切割原始字段
  if(r_application[pick]&&(pick[3:0]<r_cursor))before_fields=before_fields+4'd1; // NOP不占认证槽
 end // 结束最长前缀与标签前缀计数
end // 结束组合分组提议
always @(posedge i_clk)begin // 同步复位只清有效所有权与游标，未定义负载由有效门完全屏蔽
 if(!i_rstn)begin r_owned<=1'b0;r_cursor<=4'd0;end // 复位取消错误组、部分完成组及旧初始化时期
 else begin // 正常周期按显式捕获与实际下游接纳更新状态
  if(o_source_ready)r_owned<=i_source_valid;else if(o_group_done)r_owned<=1'b0; // done为低仍可退休，禁止空槽遗留所有权
  if(o_taken)r_cursor<=o_group_done?4'd0:selected_end; // 反压、错误及容量不足不推进游标
  if(o_captured)begin // 捕获完整数据和解释结果，支持最后分组退休同拍替换
   r_control<=i_source_control;r_tags<=i_source_tags;r_capacity<=i_capacity; // 输入从下一拍起无需再保持
   r_starts<=starts[7:1];r_application<=application_starts;r_counts<=source_counts;r_slots<=source_slots; // 发射费用来自真实寄存元数据
   r_error<=format_error;r_auth<=i_auth;r_shared<=i_shared; // 初始化及认证属性形成不可变快照
  end // 结束输入接纳
 end // 结束正常状态更新
end // 结束唯一时钟寄存器
endmodule // 结束tl_prepared_partition模块
