module tl_sequence ( // 真实Control派生与两半Flit分类推进
 input wire i_clk,i_rstn,i_commit,i_auth, // auth在两次复位间固定
 input wire [255:0] i_lower, // 实际lower半Flit
 input wire [1:0] i_msg, // 两半Message标志
 input wire [7:0] i_type0,i_type1, // 两半Message类型
 output wire o_allowed,o_taken,o_rejected, // 本地分类提交握手
 output reg [2:0] o_lower,o_upper, // 本地类别编码
 output wire [6:0] o_pending, // 有序待完成半Flit数
 output wire [72:0] o_be // 低位最早，1表示ByteEnable
); // 尚未检查payload及信用
wire [1:0] w_status; // 实际字段派生状态
wire [3:0] w_fields; // 请求响应字段数
wire [31:0] w_counts; // 每起点Data半Flit计数
wire [7:0] w_be; // 每字段BE尾标志
tl_control_tenure u_tenure(i_lower,w_status,w_fields,w_counts,w_be); // 已验证实际RTL实例
reg [6:0] r_count,n_count; // 当前和提议队列长度
reg [72:0] r_bits,n_bits; // 当前和提议队列类型
reg valid; // 整个Flit原子合法
reg [2:0] upper_expected,second_expected; // 上半直接上下文
reg pop0,pop1; // 两半独立消费事件
reg [1:0] pop_count; // 本拍消费总量
wire [6:0] w_length0={3'd0,w_counts[0 +: 4]}+{6'd0,w_be[0]}; // 字段总长度独立计算
wire [6:0] w_length1={3'd0,w_counts[4 +: 4]}+{6'd0,w_be[1]}; // 字段总长度独立计算
wire [6:0] w_length2={3'd0,w_counts[8 +: 4]}+{6'd0,w_be[2]}; // 字段总长度独立计算
wire [6:0] w_length3={3'd0,w_counts[12 +: 4]}+{6'd0,w_be[3]}; // 字段总长度独立计算
wire [6:0] w_length4={3'd0,w_counts[16 +: 4]}+{6'd0,w_be[4]}; // 字段总长度独立计算
wire [6:0] w_length5={3'd0,w_counts[20 +: 4]}+{6'd0,w_be[5]}; // 字段总长度独立计算
wire [6:0] w_length6={3'd0,w_counts[24 +: 4]}+{6'd0,w_be[6]}; // 字段总长度独立计算
wire [6:0] w_length7={3'd0,w_counts[28 +: 4]}+{6'd0,w_be[7]}; // 字段总长度独立计算
wire [6:0] w_prefix0=7'd0; // 平衡前缀累计
wire [6:0] w_prefix1=w_length0; // 平衡前缀累计
wire [6:0] w_prefix2=(w_length0+w_length1); // 平衡前缀累计
wire [6:0] w_prefix3=(w_length0+(w_length1+w_length2)); // 平衡前缀累计
wire [6:0] w_prefix4=((w_length0+w_length1)+(w_length2+w_length3)); // 平衡前缀累计
wire [6:0] w_prefix5=((w_length0+w_length1)+(w_length2+(w_length3+w_length4))); // 平衡前缀累计
wire [6:0] w_prefix6=((w_length0+(w_length1+w_length2))+(w_length3+(w_length4+w_length5))); // 平衡前缀累计
wire [6:0] w_prefix7=((w_length0+(w_length1+w_length2))+((w_length3+w_length4)+(w_length5+w_length6))); // 平衡前缀累计
wire [6:0] w_prefix8=(((w_length0+w_length1)+(w_length2+w_length3))+((w_length4+w_length5)+(w_length6+w_length7))); // 平衡前缀累计
wire [6:0] w_position0=w_prefix0+{3'd0,w_counts[0 +: 4]}; // 相对新序列的BE位置
wire [72:0] w_mark0=w_be[0] ? (73'd1<<w_position0) : 73'd0; // 独立BE掩码
wire [6:0] w_position1=w_prefix1+{3'd0,w_counts[4 +: 4]}; // 相对新序列的BE位置
wire [72:0] w_mark1=w_be[1] ? (73'd1<<w_position1) : 73'd0; // 独立BE掩码
wire [6:0] w_position2=w_prefix2+{3'd0,w_counts[8 +: 4]}; // 相对新序列的BE位置
wire [72:0] w_mark2=w_be[2] ? (73'd1<<w_position2) : 73'd0; // 独立BE掩码
wire [6:0] w_position3=w_prefix3+{3'd0,w_counts[12 +: 4]}; // 相对新序列的BE位置
wire [72:0] w_mark3=w_be[3] ? (73'd1<<w_position3) : 73'd0; // 独立BE掩码
wire [6:0] w_position4=w_prefix4+{3'd0,w_counts[16 +: 4]}; // 相对新序列的BE位置
wire [72:0] w_mark4=w_be[4] ? (73'd1<<w_position4) : 73'd0; // 独立BE掩码
wire [6:0] w_position5=w_prefix5+{3'd0,w_counts[20 +: 4]}; // 相对新序列的BE位置
wire [72:0] w_mark5=w_be[5] ? (73'd1<<w_position5) : 73'd0; // 独立BE掩码
wire [6:0] w_position6=w_prefix6+{3'd0,w_counts[24 +: 4]}; // 相对新序列的BE位置
wire [72:0] w_mark6=w_be[6] ? (73'd1<<w_position6) : 73'd0; // 独立BE掩码
wire [6:0] w_position7=w_prefix7+{3'd0,w_counts[28 +: 4]}; // 相对新序列的BE位置
wire [72:0] w_mark7=w_be[7] ? (73'd1<<w_position7) : 73'd0; // 独立BE掩码
wire [72:0] w_append_bits=w_mark0|w_mark1|w_mark2|w_mark3|w_mark4|w_mark5|w_mark6|w_mark7; // 并行合并字段尾标记
wire w_fresh_present=(|w_counts)||(|w_be); // 新序列非空直接归约，避开长度进位
wire w_first_be=(w_be[0] && !(|w_counts[3:0]))|(w_be[1] && !(|w_counts[7:0]) && !(|w_be[0:0]))|(w_be[2] && !(|w_counts[11:0]) && !(|w_be[1:0]))|(w_be[3] && !(|w_counts[15:0]) && !(|w_be[2:0]))|(w_be[4] && !(|w_counts[19:0]) && !(|w_be[3:0]))|(w_be[5] && !(|w_counts[23:0]) && !(|w_be[4:0]))|(w_be[6] && !(|w_counts[27:0]) && !(|w_be[5:0]))|(w_be[7] && !(|w_counts[31:0]) && !(|w_be[6:0])); // 首位BE只需检查前缀是否全空
assign o_pending=r_count; // 当前状态观察
assign o_be=r_bits; // 当前队列观察
assign o_allowed=i_rstn && valid; // 复位抑制准入
assign o_taken=i_commit && o_allowed; // 唯一状态提交
assign o_rejected=i_rstn && i_commit && !valid; // 拒绝不推进
always @* begin // 完整组合初值
 n_count=r_count;n_bits=r_bits;valid=1'b1; // 事务式提议副本
 o_lower=3'd7;o_upper=3'd7;upper_expected=3'd3;second_expected=3'd3;pop0=1'b0;pop1=1'b0;pop_count=2'd0; // 复位或非法静默类别
 if(i_msg[0] && i_type0!=8'd0 && i_type0!=8'd1 && i_type0!=8'd32) valid=1'b0; // 保留Message拒绝
 if(i_msg[1] && i_type1!=8'd0 && i_type1!=8'd1 && i_type1!=8'd32) valid=1'b0; // 上半同规则
 if(r_count<=7'd1) begin // lower是Control槽，末Data交换到upper
  if(i_msg[0]) begin // 普通Message替换lower Control槽
   if(i_type0==8'd32) valid=1'b0; // Control不能Poison
   upper_expected=(r_count==7'd1)?(r_bits[0]?3'd2:3'd1):3'd3; // 尾Data仍占upper
  end else begin // 实际Control必须可派生
   if(w_status!=2'd0) valid=1'b0; // 非法及未决均禁止提交
   if(i_auth && ((w_fields>4'd4)||((r_count==7'd1)&&(w_fields!=4'd0)))) valid=1'b0; // 标签数量和交换约束
   n_count=r_count+w_prefix8; // 一次合并总长度，避免八段串行进位
   n_bits=r_bits|(r_count[0]?(w_append_bits<<1):w_append_bits); // Control上下文旧尾最多一项，最后统一偏移
   if(r_count==7'd1) upper_expected=r_bits[0]?3'd2:3'd1; // 优先旧尾部
   else if(i_auth && w_fields!=4'd0) upper_expected=3'd6; // AuthTags必须同Flit
   else if(w_fresh_present) upper_expected=(r_bits[0]|w_first_be)?3'd2:3'd1; // 新Data立即占upper
  end // Control分支结束
 end // lower上下文准备结束
 pop0=(r_count>7'd1)&&(!i_msg[0]||((i_type0==8'd32)&&!r_bits[0])); // 非Control下半消费
 second_expected=(r_count<=7'd1)?upper_expected:((pop0?r_bits[1]:r_bits[0])?3'd2:3'd1); // 直接选择上半队首
 if(r_count<=7'd1) o_lower=i_msg[0]?3'd4:3'd0; // lower特殊槽
 else o_lower=i_msg[0]?((i_type0==8'd32)?3'd5:3'd4):(r_bits[0]?3'd2:3'd1); // lower普通分类
 if((r_count>7'd1)&&i_msg[0]&&(i_type0==8'd32)&&r_bits[0]) valid=1'b0; // lower BE禁止Poison
 o_upper=(second_expected==3'd6)?3'd6:(i_msg[1]?((i_type1==8'd32)?3'd5:3'd4):second_expected); // upper独立分类
 if(i_msg[1]&&((second_expected==3'd6)||((i_type1==8'd32)&&(second_expected!=3'd1)))) valid=1'b0; // 标签与Poison约束
 pop1=((second_expected==3'd1)||(second_expected==3'd2))&&(!i_msg[1]||((i_type1==8'd32)&&(second_expected==3'd1))); // 上半消费
 pop_count={1'b0,pop0}+{1'b0,pop1}; // 本拍零到两项
 n_bits=n_bits>>pop_count;n_count=n_count-{5'd0,pop_count}; // 一次移动及减量
 if(!i_rstn || !valid) begin o_lower=3'd7;o_upper=3'd7;end // 非法不暴露部分分类
end // 提议计算结束
always @(posedge i_clk) begin // 唯一输入时钟
 if(!i_rstn) begin r_count<=7'd0;r_bits<=73'd0;end // 同步复位优先
 else if(o_taken) begin r_count<=n_count;r_bits<=n_bits;end // 仅合法完整Flit推进
end // 状态更新结束
endmodule // 分类与推进结束
