module tl_credit_context( // 请求关联元数据与20槽信用需求
input wire i_clk,i_rstn,i_commit,i_auth,input wire [255:0] i_lower,input wire [1:0] i_msg,input wire [7:0] i_type0,i_type1, // 单时钟发送提议
output wire o_allowed,o_taken,o_rejected,output wire [2:0] o_lower,o_upper,output reg [79:0] o_demands, // 每槽四位，首Data半拍预留
output wire [6:0] o_pending,output wire [72:0] o_be,output wire [437:0] o_metadata // 每项为预留位及五位Data槽
); // 接口结束
wire [1:0] unused_status;wire [3:0] unused_fields;wire [31:0] w_counts;wire [7:0] w_be; // 已认证字段tenure
wire unused_valid;wire [2:0] unused_requests;wire [3:0] unused_responses;wire [7:0] unused_starts,w_req,w_rsp; // 实际字段起点
wire [39:0] w_slots; // 各sector元数据槽
reg [437:0] r_metadata,n_metadata; // 同步提交的有序元数据
integer i,target; // 有界展开索引
 tl_sequence u_sequence(i_clk,i_rstn,i_commit,i_auth,i_lower,i_msg,i_type0,i_type1,o_allowed,o_taken,o_rejected,o_lower,o_upper,o_pending,o_be); // 唯一分类准入
 tl_control_tenure u_tenure(i_lower,unused_status,unused_fields,w_counts,w_be); // 字段附带Data及BE数
 tl_control_decode u_decode(i_lower,unused_valid,unused_requests,unused_responses,unused_starts,w_req,w_rsp); // 请求响应实际起点
assign o_metadata=r_metadata; // 全状态观察
wire [1:0] w_vc0=(i_lower[127:124]==4'd1)?i_lower[117:116]:((i_lower[63:60]==4'd2)?i_lower[59:58]:(i_lower[63:60]==4'd3)?i_lower[56:55]:i_lower[27:26]); // sector0字段VC
wire w_pool0=(i_lower[127:124]==4'd1)?i_lower[102]:((i_lower[63:60]==4'd2)?i_lower[46]:(i_lower[63:60]==4'd3)?i_lower[41]:i_lower[14]); // sector0字段Pool
wire [2:0] w_lane0=w_pool0?3'd0:({1'b0,w_vc0}+3'd1); // Pool或专用VC
assign w_slots[0+:5]=(w_req[0]?5'd10:5'd15)+{2'd0,w_lane0}; // 请求与响应Data类
wire [1:0] w_vc1=i_lower[59:58]; // sector1字段VC
wire w_pool1=i_lower[46]; // sector1字段Pool
wire [2:0] w_lane1=w_pool1?3'd0:({1'b0,w_vc1}+3'd1); // Pool或专用VC
assign w_slots[5+:5]=(w_req[1]?5'd10:5'd15)+{2'd0,w_lane1}; // 请求与响应Data类
wire [1:0] w_vc2=(i_lower[127:124]==4'd2)?i_lower[123:122]:(i_lower[127:124]==4'd3)?i_lower[120:119]:i_lower[91:90]; // sector2字段VC
wire w_pool2=(i_lower[127:124]==4'd2)?i_lower[110]:(i_lower[127:124]==4'd3)?i_lower[105]:i_lower[78]; // sector2字段Pool
wire [2:0] w_lane2=w_pool2?3'd0:({1'b0,w_vc2}+3'd1); // Pool或专用VC
assign w_slots[10+:5]=(w_req[2]?5'd10:5'd15)+{2'd0,w_lane2}; // 请求与响应Data类
wire [1:0] w_vc3=i_lower[123:122]; // sector3字段VC
wire w_pool3=i_lower[110]; // sector3字段Pool
wire [2:0] w_lane3=w_pool3?3'd0:({1'b0,w_vc3}+3'd1); // Pool或专用VC
assign w_slots[15+:5]=(w_req[3]?5'd10:5'd15)+{2'd0,w_lane3}; // 请求与响应Data类
wire [1:0] w_vc4=(i_lower[255:252]==4'd1)?i_lower[245:244]:((i_lower[191:188]==4'd2)?i_lower[187:186]:(i_lower[191:188]==4'd3)?i_lower[184:183]:i_lower[155:154]); // sector4字段VC
wire w_pool4=(i_lower[255:252]==4'd1)?i_lower[230]:((i_lower[191:188]==4'd2)?i_lower[174]:(i_lower[191:188]==4'd3)?i_lower[169]:i_lower[142]); // sector4字段Pool
wire [2:0] w_lane4=w_pool4?3'd0:({1'b0,w_vc4}+3'd1); // Pool或专用VC
assign w_slots[20+:5]=(w_req[4]?5'd10:5'd15)+{2'd0,w_lane4}; // 请求与响应Data类
wire [1:0] w_vc5=i_lower[187:186]; // sector5字段VC
wire w_pool5=i_lower[174]; // sector5字段Pool
wire [2:0] w_lane5=w_pool5?3'd0:({1'b0,w_vc5}+3'd1); // Pool或专用VC
assign w_slots[25+:5]=(w_req[5]?5'd10:5'd15)+{2'd0,w_lane5}; // 请求与响应Data类
wire [1:0] w_vc6=(i_lower[255:252]==4'd2)?i_lower[251:250]:(i_lower[255:252]==4'd3)?i_lower[248:247]:i_lower[219:218]; // sector6字段VC
wire w_pool6=(i_lower[255:252]==4'd2)?i_lower[238]:(i_lower[255:252]==4'd3)?i_lower[233]:i_lower[206]; // sector6字段Pool
wire [2:0] w_lane6=w_pool6?3'd0:({1'b0,w_vc6}+3'd1); // Pool或专用VC
assign w_slots[30+:5]=(w_req[6]?5'd10:5'd15)+{2'd0,w_lane6}; // 请求与响应Data类
wire [1:0] w_vc7=i_lower[251:250]; // sector7字段VC
wire w_pool7=i_lower[238]; // sector7字段Pool
wire [2:0] w_lane7=w_pool7?3'd0:({1'b0,w_vc7}+3'd1); // Pool或专用VC
assign w_slots[35+:5]=(w_req[7]?5'd10:5'd15)+{2'd0,w_lane7}; // 请求与响应Data类
wire [6:0] w_length0={3'd0,w_counts[0+:4]}+{6'd0,w_be[0]}; // 每字段token长度
wire [6:0] w_prefix0=7'd0; // 字段顺序前缀
wire [5:0] w_token_0_0=(7'd0<w_length0)?{(4'd0<w_counts[0+:4]),w_slots[0+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_0_1=(7'd1<w_length0)?{1'b0,w_slots[0+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_0_2=(7'd2<w_length0)?{(4'd2<w_counts[0+:4]),w_slots[0+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_0_3=(7'd3<w_length0)?{1'b0,w_slots[0+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_0_4=(7'd4<w_length0)?{(4'd4<w_counts[0+:4]),w_slots[0+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_0_5=(7'd5<w_length0)?{1'b0,w_slots[0+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_0_6=(7'd6<w_length0)?{(4'd6<w_counts[0+:4]),w_slots[0+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_0_7=(7'd7<w_length0)?{1'b0,w_slots[0+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_0_8=(7'd8<w_length0)?{(4'd8<w_counts[0+:4]),w_slots[0+:5]}:6'd0; // 固定位置元数据
wire [437:0] w_append0={384'd0,w_token_0_8,w_token_0_7,w_token_0_6,w_token_0_5,w_token_0_4,w_token_0_3,w_token_0_2,w_token_0_1,w_token_0_0}<<({3'd0,w_prefix0}*10'd6); // 并行移动字段片段
wire [6:0] w_length1={3'd0,w_counts[4+:4]}+{6'd0,w_be[1]}; // 每字段token长度
wire [6:0] w_prefix1=w_length0; // 字段顺序前缀
wire [5:0] w_token_1_0=(7'd0<w_length1)?{(4'd0<w_counts[4+:4]),w_slots[5+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_1_1=(7'd1<w_length1)?{1'b0,w_slots[5+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_1_2=(7'd2<w_length1)?{(4'd2<w_counts[4+:4]),w_slots[5+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_1_3=(7'd3<w_length1)?{1'b0,w_slots[5+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_1_4=(7'd4<w_length1)?{(4'd4<w_counts[4+:4]),w_slots[5+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_1_5=(7'd5<w_length1)?{1'b0,w_slots[5+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_1_6=(7'd6<w_length1)?{(4'd6<w_counts[4+:4]),w_slots[5+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_1_7=(7'd7<w_length1)?{1'b0,w_slots[5+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_1_8=(7'd8<w_length1)?{(4'd8<w_counts[4+:4]),w_slots[5+:5]}:6'd0; // 固定位置元数据
wire [437:0] w_append1={384'd0,w_token_1_8,w_token_1_7,w_token_1_6,w_token_1_5,w_token_1_4,w_token_1_3,w_token_1_2,w_token_1_1,w_token_1_0}<<({3'd0,w_prefix1}*10'd6); // 并行移动字段片段
wire [6:0] w_length2={3'd0,w_counts[8+:4]}+{6'd0,w_be[2]}; // 每字段token长度
wire [6:0] w_prefix2=(w_length0+w_length1); // 字段顺序前缀
wire [5:0] w_token_2_0=(7'd0<w_length2)?{(4'd0<w_counts[8+:4]),w_slots[10+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_2_1=(7'd1<w_length2)?{1'b0,w_slots[10+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_2_2=(7'd2<w_length2)?{(4'd2<w_counts[8+:4]),w_slots[10+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_2_3=(7'd3<w_length2)?{1'b0,w_slots[10+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_2_4=(7'd4<w_length2)?{(4'd4<w_counts[8+:4]),w_slots[10+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_2_5=(7'd5<w_length2)?{1'b0,w_slots[10+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_2_6=(7'd6<w_length2)?{(4'd6<w_counts[8+:4]),w_slots[10+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_2_7=(7'd7<w_length2)?{1'b0,w_slots[10+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_2_8=(7'd8<w_length2)?{(4'd8<w_counts[8+:4]),w_slots[10+:5]}:6'd0; // 固定位置元数据
wire [437:0] w_append2={384'd0,w_token_2_8,w_token_2_7,w_token_2_6,w_token_2_5,w_token_2_4,w_token_2_3,w_token_2_2,w_token_2_1,w_token_2_0}<<({3'd0,w_prefix2}*10'd6); // 并行移动字段片段
wire [6:0] w_length3={3'd0,w_counts[12+:4]}+{6'd0,w_be[3]}; // 每字段token长度
wire [6:0] w_prefix3=(w_length0+(w_length1+w_length2)); // 字段顺序前缀
wire [5:0] w_token_3_0=(7'd0<w_length3)?{(4'd0<w_counts[12+:4]),w_slots[15+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_3_1=(7'd1<w_length3)?{1'b0,w_slots[15+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_3_2=(7'd2<w_length3)?{(4'd2<w_counts[12+:4]),w_slots[15+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_3_3=(7'd3<w_length3)?{1'b0,w_slots[15+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_3_4=(7'd4<w_length3)?{(4'd4<w_counts[12+:4]),w_slots[15+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_3_5=(7'd5<w_length3)?{1'b0,w_slots[15+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_3_6=(7'd6<w_length3)?{(4'd6<w_counts[12+:4]),w_slots[15+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_3_7=(7'd7<w_length3)?{1'b0,w_slots[15+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_3_8=(7'd8<w_length3)?{(4'd8<w_counts[12+:4]),w_slots[15+:5]}:6'd0; // 固定位置元数据
wire [437:0] w_append3={384'd0,w_token_3_8,w_token_3_7,w_token_3_6,w_token_3_5,w_token_3_4,w_token_3_3,w_token_3_2,w_token_3_1,w_token_3_0}<<({3'd0,w_prefix3}*10'd6); // 并行移动字段片段
wire [6:0] w_length4={3'd0,w_counts[16+:4]}+{6'd0,w_be[4]}; // 每字段token长度
wire [6:0] w_prefix4=((w_length0+w_length1)+(w_length2+w_length3)); // 字段顺序前缀
wire [5:0] w_token_4_0=(7'd0<w_length4)?{(4'd0<w_counts[16+:4]),w_slots[20+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_4_1=(7'd1<w_length4)?{1'b0,w_slots[20+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_4_2=(7'd2<w_length4)?{(4'd2<w_counts[16+:4]),w_slots[20+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_4_3=(7'd3<w_length4)?{1'b0,w_slots[20+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_4_4=(7'd4<w_length4)?{(4'd4<w_counts[16+:4]),w_slots[20+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_4_5=(7'd5<w_length4)?{1'b0,w_slots[20+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_4_6=(7'd6<w_length4)?{(4'd6<w_counts[16+:4]),w_slots[20+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_4_7=(7'd7<w_length4)?{1'b0,w_slots[20+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_4_8=(7'd8<w_length4)?{(4'd8<w_counts[16+:4]),w_slots[20+:5]}:6'd0; // 固定位置元数据
wire [437:0] w_append4={384'd0,w_token_4_8,w_token_4_7,w_token_4_6,w_token_4_5,w_token_4_4,w_token_4_3,w_token_4_2,w_token_4_1,w_token_4_0}<<({3'd0,w_prefix4}*10'd6); // 并行移动字段片段
wire [6:0] w_length5={3'd0,w_counts[20+:4]}+{6'd0,w_be[5]}; // 每字段token长度
wire [6:0] w_prefix5=((w_length0+w_length1)+(w_length2+(w_length3+w_length4))); // 字段顺序前缀
wire [5:0] w_token_5_0=(7'd0<w_length5)?{(4'd0<w_counts[20+:4]),w_slots[25+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_5_1=(7'd1<w_length5)?{1'b0,w_slots[25+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_5_2=(7'd2<w_length5)?{(4'd2<w_counts[20+:4]),w_slots[25+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_5_3=(7'd3<w_length5)?{1'b0,w_slots[25+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_5_4=(7'd4<w_length5)?{(4'd4<w_counts[20+:4]),w_slots[25+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_5_5=(7'd5<w_length5)?{1'b0,w_slots[25+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_5_6=(7'd6<w_length5)?{(4'd6<w_counts[20+:4]),w_slots[25+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_5_7=(7'd7<w_length5)?{1'b0,w_slots[25+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_5_8=(7'd8<w_length5)?{(4'd8<w_counts[20+:4]),w_slots[25+:5]}:6'd0; // 固定位置元数据
wire [437:0] w_append5={384'd0,w_token_5_8,w_token_5_7,w_token_5_6,w_token_5_5,w_token_5_4,w_token_5_3,w_token_5_2,w_token_5_1,w_token_5_0}<<({3'd0,w_prefix5}*10'd6); // 并行移动字段片段
wire [6:0] w_length6={3'd0,w_counts[24+:4]}+{6'd0,w_be[6]}; // 每字段token长度
wire [6:0] w_prefix6=((w_length0+(w_length1+w_length2))+(w_length3+(w_length4+w_length5))); // 字段顺序前缀
wire [5:0] w_token_6_0=(7'd0<w_length6)?{(4'd0<w_counts[24+:4]),w_slots[30+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_6_1=(7'd1<w_length6)?{1'b0,w_slots[30+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_6_2=(7'd2<w_length6)?{(4'd2<w_counts[24+:4]),w_slots[30+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_6_3=(7'd3<w_length6)?{1'b0,w_slots[30+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_6_4=(7'd4<w_length6)?{(4'd4<w_counts[24+:4]),w_slots[30+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_6_5=(7'd5<w_length6)?{1'b0,w_slots[30+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_6_6=(7'd6<w_length6)?{(4'd6<w_counts[24+:4]),w_slots[30+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_6_7=(7'd7<w_length6)?{1'b0,w_slots[30+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_6_8=(7'd8<w_length6)?{(4'd8<w_counts[24+:4]),w_slots[30+:5]}:6'd0; // 固定位置元数据
wire [437:0] w_append6={384'd0,w_token_6_8,w_token_6_7,w_token_6_6,w_token_6_5,w_token_6_4,w_token_6_3,w_token_6_2,w_token_6_1,w_token_6_0}<<({3'd0,w_prefix6}*10'd6); // 并行移动字段片段
wire [6:0] w_length7={3'd0,w_counts[28+:4]}+{6'd0,w_be[7]}; // 每字段token长度
wire [6:0] w_prefix7=((w_length0+(w_length1+w_length2))+((w_length3+w_length4)+(w_length5+w_length6))); // 字段顺序前缀
wire [5:0] w_token_7_0=(7'd0<w_length7)?{(4'd0<w_counts[28+:4]),w_slots[35+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_7_1=(7'd1<w_length7)?{1'b0,w_slots[35+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_7_2=(7'd2<w_length7)?{(4'd2<w_counts[28+:4]),w_slots[35+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_7_3=(7'd3<w_length7)?{1'b0,w_slots[35+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_7_4=(7'd4<w_length7)?{(4'd4<w_counts[28+:4]),w_slots[35+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_7_5=(7'd5<w_length7)?{1'b0,w_slots[35+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_7_6=(7'd6<w_length7)?{(4'd6<w_counts[28+:4]),w_slots[35+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_7_7=(7'd7<w_length7)?{1'b0,w_slots[35+:5]}:6'd0; // 固定位置元数据
wire [5:0] w_token_7_8=(7'd8<w_length7)?{(4'd8<w_counts[28+:4]),w_slots[35+:5]}:6'd0; // 固定位置元数据
wire [437:0] w_append7={384'd0,w_token_7_8,w_token_7_7,w_token_7_6,w_token_7_5,w_token_7_4,w_token_7_3,w_token_7_2,w_token_7_1,w_token_7_0}<<({3'd0,w_prefix7}*10'd6); // 并行移动字段片段
wire [437:0] w_append_all=w_append0|w_append1|w_append2|w_append3|w_append4|w_append5|w_append6|w_append7; // 八字段合并
always @* begin // 元数据与需求原子提议
n_metadata=r_metadata;o_demands=80'd0;target=0; // 完整初值
if(o_allowed) begin // 非法及复位不输出部分需求
 if(o_lower==3'd0) begin // 真正Control才解释新字段
  n_metadata=r_metadata|(o_pending[0]?(w_append_all<<6):w_append_all); // 旧尾最多一项，统一偏移
  for(i=0;i<8;i=i+1)begin // 按低sector到高sector顺序
   if(w_req[i]||w_rsp[i])begin // FC不消耗命令信用
    target={27'd0,w_slots[i*5+:5]}-10; // Data槽映射至相应CMD槽
    o_demands[target*4+:4]=o_demands[target*4+:4]+4'd1; // 合并同类命令信用
   end // 命令结束
  end // 字段顺序结束
 end // Control结束
 if(o_lower==3'd1||o_lower==3'd2||o_lower==3'd5)begin // 下半实际消费
  target={27'd0,n_metadata[4:0]}; // 队首信用槽
  if(n_metadata[5])o_demands[target*4+:4]=o_demands[target*4+:4]+4'd1; // 一对只收一次
  n_metadata=n_metadata>>6; // 弹出元数据
 end // 下半结束
 if(o_upper==3'd1||o_upper==3'd2||o_upper==3'd5)begin // 上半消费含旧尾交换
  target={27'd0,n_metadata[4:0]}; // 更新后的队首
  if(n_metadata[5])o_demands[target*4+:4]=o_demands[target*4+:4]+4'd1; // Data首半信用
  n_metadata=n_metadata>>6; // 弹出元数据
 end // 上半结束
end // 提议结束
end // 组合结束
always @(posedge i_clk)begin // 唯一时钟域
 if(!i_rstn)r_metadata<=438'd0; // 同步复位
 else if(o_taken)r_metadata<=n_metadata; // 与序列完全相同提交
end // 状态更新结束
endmodule // 上下文结束
