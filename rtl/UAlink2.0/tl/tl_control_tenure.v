module tl_control_tenure #(parameter ZERO_ON_ERROR=1'b1)(input wire [255:0] i_half,output reg [1:0] o_status,output reg [3:0] o_fields,output reg [31:0] o_data_counts,output reg [7:0] o_byte_enable); // tl_control_tenure模块：按自然字段派生tenure，默认错误时清零描述符
wire [255:0] unused_payload; // 保留未消费字段位信号声明
assign unused_payload=i_half; // 保留未消费字段位组合驱动
reg [1:0] s0;reg [3:0] f0;reg [31:0] d0;reg [7:0] b0; // 每个sector末端独立语义
reg [1:0] s1;reg [3:0] f1;reg [31:0] d1;reg [7:0] b1; // 每个sector末端独立语义
reg [1:0] s2;reg [3:0] f2;reg [31:0] d2;reg [7:0] b2; // 每个sector末端独立语义
reg [1:0] s3;reg [3:0] f3;reg [31:0] d3;reg [7:0] b3; // 每个sector末端独立语义
reg [1:0] s4;reg [3:0] f4;reg [31:0] d4;reg [7:0] b4; // 每个sector末端独立语义
reg [1:0] s5;reg [3:0] f5;reg [31:0] d5;reg [7:0] b5; // 每个sector末端独立语义
reg [1:0] s6;reg [3:0] f6;reg [31:0] d6;reg [7:0] b6; // 每个sector末端独立语义
reg [1:0] s7;reg [3:0] f7;reg [31:0] d7;reg [7:0] b7; // 每个sector末端独立语义
always @* begin // 并行字段派生逻辑
s7=2'd0;f7=4'd0;d7=32'd0;b7=8'd0; // 并行字段派生逻辑
case(i_half[255:252]) // 并行字段派生逻辑
4'd0: begin end // FC无tenure
4'd1: begin // 并行字段派生逻辑
f7=f7+4'd1; // 计入请求或响应字段
case(i_half[251:246]) // 未压缩CMD
6'd3,6'd4,6'd5,6'd8,6'd9,6'd10,6'd11,6'd12,6'd13,6'd14,6'd15: begin end // 读请求不附带数据
6'd32,6'd33,6'd34,6'd42: s7=2'd2; // 特殊命令BE尚待专节确认
6'd48,6'd50,6'd51: begin // 标准原子固定一Beat
if(i_half[129:128]!=2'd0) s7=2'd1; // 并行字段派生逻辑
else begin d7[16 +: 4]=4'd2;b7[4]=1'b1;end // 并行字段派生逻辑
end // 并行字段派生逻辑
6'd35,6'd39,6'd41: begin // 并行字段派生逻辑
d7[16 +: 4]={1'b0,i_half[129:128],1'b0}+4'd2;b7[4]=1'b0; // NUMBEATS加一再乘二
end // 并行字段派生逻辑
6'd38,6'd40,6'd44,6'd45,6'd46,6'd47,6'd60,6'd61,6'd62,6'd63: begin // 并行字段派生逻辑
d7[16 +: 4]={1'b0,i_half[129:128],1'b0}+4'd2;b7[4]=1'b1; // NUMBEATS加一再乘二
end // 并行字段派生逻辑
default:s7=2'd1; // 保留CMD
endcase // 并行字段派生逻辑
end // 并行字段派生逻辑
4'd2: begin // 并行字段派生逻辑
f7=f7+4'd1; // 计入请求或响应字段
if(i_half[229]) d7[24 +: 4]={1'b0,i_half[237:236],1'b0}+4'd2; // 未压缩读响应LEN
end // 并行字段派生逻辑
4'd3: begin // 并行字段派生逻辑
f7=f7+4'd1; // 计入请求或响应字段
if(i_half[251:249]>=3'd3) begin // 压缩写类CMD
d7[24 +: 4]={1'b0,i_half[232:231],1'b0}+4'd2; // 压缩LEN
b7[6]=(i_half[251:249]==3'd3)||(i_half[251:249]==3'd4); // 非Full写附加BE
end // 并行字段派生逻辑
end // 并行字段派生逻辑
4'd4: begin // 并行字段派生逻辑
f7=f7+4'd1; // 计入请求或响应字段
d7[28 +: 4]=4'd2; // 单Beat读响应
end // 并行字段派生逻辑
4'd5: begin // 并行字段派生逻辑
f7=f7+4'd1; // 计入请求或响应字段
if(i_half[225]) d7[28 +: 4]={1'b0,i_half[227:226],1'b0}+4'd2; // 压缩读响应
end // 并行字段派生逻辑
4'd6,4'd7:s7=2'd2; // 冲突规范编码明确未决
default:s7=2'd1; // 其余保留类型
endcase // 并行字段派生逻辑
end // 并行字段派生逻辑
always @* begin // 并行字段派生逻辑
s6=2'd0;f6=4'd0;d6=32'd0;b6=8'd0; // 并行字段派生逻辑
case(i_half[223:220]) // 并行字段派生逻辑
4'd0: begin end // FC无tenure
4'd1: begin // 并行字段派生逻辑
s6=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd2: begin // 并行字段派生逻辑
s6=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd3: begin // 并行字段派生逻辑
s6=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd4: begin // 并行字段派生逻辑
f6=f6+4'd1; // 计入请求或响应字段
d6[24 +: 4]=4'd2; // 单Beat读响应
end // 并行字段派生逻辑
4'd5: begin // 并行字段派生逻辑
f6=f6+4'd1; // 计入请求或响应字段
if(i_half[193]) d6[24 +: 4]={1'b0,i_half[195:194],1'b0}+4'd2; // 压缩读响应
end // 并行字段派生逻辑
4'd6,4'd7:s6=2'd2; // 冲突规范编码明确未决
default:s6=2'd1; // 其余保留类型
endcase // 并行字段派生逻辑
end // 并行字段派生逻辑
always @* begin // 并行字段派生逻辑
s5=2'd0;f5=4'd0;d5=32'd0;b5=8'd0; // 并行字段派生逻辑
case(i_half[191:188]) // 并行字段派生逻辑
4'd0: begin end // FC无tenure
4'd1: begin // 并行字段派生逻辑
s5=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd2: begin // 并行字段派生逻辑
f5=f5+4'd1; // 计入请求或响应字段
if(i_half[165]) d5[16 +: 4]={1'b0,i_half[173:172],1'b0}+4'd2; // 未压缩读响应LEN
end // 并行字段派生逻辑
4'd3: begin // 并行字段派生逻辑
f5=f5+4'd1; // 计入请求或响应字段
if(i_half[187:185]>=3'd3) begin // 压缩写类CMD
d5[16 +: 4]={1'b0,i_half[168:167],1'b0}+4'd2; // 压缩LEN
b5[4]=(i_half[187:185]==3'd3)||(i_half[187:185]==3'd4); // 非Full写附加BE
end // 并行字段派生逻辑
end // 并行字段派生逻辑
4'd4: begin // 并行字段派生逻辑
f5=f5+4'd1; // 计入请求或响应字段
d5[20 +: 4]=4'd2; // 单Beat读响应
end // 并行字段派生逻辑
4'd5: begin // 并行字段派生逻辑
f5=f5+4'd1; // 计入请求或响应字段
if(i_half[161]) d5[20 +: 4]={1'b0,i_half[163:162],1'b0}+4'd2; // 压缩读响应
end // 并行字段派生逻辑
4'd6,4'd7:s5=2'd2; // 冲突规范编码明确未决
default:s5=2'd1; // 其余保留类型
endcase // 并行字段派生逻辑
end // 并行字段派生逻辑
always @* begin // 并行字段派生逻辑
s4=2'd0;f4=4'd0;d4=32'd0;b4=8'd0; // 并行字段派生逻辑
case(i_half[159:156]) // 并行字段派生逻辑
4'd0: begin end // FC无tenure
4'd1: begin // 并行字段派生逻辑
s4=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd2: begin // 并行字段派生逻辑
s4=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd3: begin // 并行字段派生逻辑
s4=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd4: begin // 并行字段派生逻辑
f4=f4+4'd1; // 计入请求或响应字段
d4[16 +: 4]=4'd2; // 单Beat读响应
end // 并行字段派生逻辑
4'd5: begin // 并行字段派生逻辑
f4=f4+4'd1; // 计入请求或响应字段
if(i_half[129]) d4[16 +: 4]={1'b0,i_half[131:130],1'b0}+4'd2; // 压缩读响应
end // 并行字段派生逻辑
4'd6,4'd7:s4=2'd2; // 冲突规范编码明确未决
default:s4=2'd1; // 其余保留类型
endcase // 并行字段派生逻辑
end // 并行字段派生逻辑
always @* begin // 并行字段派生逻辑
s3=2'd0;f3=4'd0;d3=32'd0;b3=8'd0; // 并行字段派生逻辑
case(i_half[127:124]) // 并行字段派生逻辑
4'd0: begin end // FC无tenure
4'd1: begin // 并行字段派生逻辑
f3=f3+4'd1; // 计入请求或响应字段
case(i_half[123:118]) // 未压缩CMD
6'd3,6'd4,6'd5,6'd8,6'd9,6'd10,6'd11,6'd12,6'd13,6'd14,6'd15: begin end // 读请求不附带数据
6'd32,6'd33,6'd34,6'd42: s3=2'd2; // 特殊命令BE尚待专节确认
6'd48,6'd50,6'd51: begin // 标准原子固定一Beat
if(i_half[1:0]!=2'd0) s3=2'd1; // 并行字段派生逻辑
else begin d3[0 +: 4]=4'd2;b3[0]=1'b1;end // 并行字段派生逻辑
end // 并行字段派生逻辑
6'd35,6'd39,6'd41: begin // 并行字段派生逻辑
d3[0 +: 4]={1'b0,i_half[1:0],1'b0}+4'd2;b3[0]=1'b0; // NUMBEATS加一再乘二
end // 并行字段派生逻辑
6'd38,6'd40,6'd44,6'd45,6'd46,6'd47,6'd60,6'd61,6'd62,6'd63: begin // 并行字段派生逻辑
d3[0 +: 4]={1'b0,i_half[1:0],1'b0}+4'd2;b3[0]=1'b1; // NUMBEATS加一再乘二
end // 并行字段派生逻辑
default:s3=2'd1; // 保留CMD
endcase // 并行字段派生逻辑
end // 并行字段派生逻辑
4'd2: begin // 并行字段派生逻辑
f3=f3+4'd1; // 计入请求或响应字段
if(i_half[101]) d3[8 +: 4]={1'b0,i_half[109:108],1'b0}+4'd2; // 未压缩读响应LEN
end // 并行字段派生逻辑
4'd3: begin // 并行字段派生逻辑
f3=f3+4'd1; // 计入请求或响应字段
if(i_half[123:121]>=3'd3) begin // 压缩写类CMD
d3[8 +: 4]={1'b0,i_half[104:103],1'b0}+4'd2; // 压缩LEN
b3[2]=(i_half[123:121]==3'd3)||(i_half[123:121]==3'd4); // 非Full写附加BE
end // 并行字段派生逻辑
end // 并行字段派生逻辑
4'd4: begin // 并行字段派生逻辑
f3=f3+4'd1; // 计入请求或响应字段
d3[12 +: 4]=4'd2; // 单Beat读响应
end // 并行字段派生逻辑
4'd5: begin // 并行字段派生逻辑
f3=f3+4'd1; // 计入请求或响应字段
if(i_half[97]) d3[12 +: 4]={1'b0,i_half[99:98],1'b0}+4'd2; // 压缩读响应
end // 并行字段派生逻辑
4'd6,4'd7:s3=2'd2; // 冲突规范编码明确未决
default:s3=2'd1; // 其余保留类型
endcase // 并行字段派生逻辑
end // 并行字段派生逻辑
always @* begin // 并行字段派生逻辑
s2=2'd0;f2=4'd0;d2=32'd0;b2=8'd0; // 并行字段派生逻辑
case(i_half[95:92]) // 并行字段派生逻辑
4'd0: begin end // FC无tenure
4'd1: begin // 并行字段派生逻辑
s2=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd2: begin // 并行字段派生逻辑
s2=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd3: begin // 并行字段派生逻辑
s2=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd4: begin // 并行字段派生逻辑
f2=f2+4'd1; // 计入请求或响应字段
d2[8 +: 4]=4'd2; // 单Beat读响应
end // 并行字段派生逻辑
4'd5: begin // 并行字段派生逻辑
f2=f2+4'd1; // 计入请求或响应字段
if(i_half[65]) d2[8 +: 4]={1'b0,i_half[67:66],1'b0}+4'd2; // 压缩读响应
end // 并行字段派生逻辑
4'd6,4'd7:s2=2'd2; // 冲突规范编码明确未决
default:s2=2'd1; // 其余保留类型
endcase // 并行字段派生逻辑
end // 并行字段派生逻辑
always @* begin // 并行字段派生逻辑
s1=2'd0;f1=4'd0;d1=32'd0;b1=8'd0; // 并行字段派生逻辑
case(i_half[63:60]) // 并行字段派生逻辑
4'd0: begin end // FC无tenure
4'd1: begin // 并行字段派生逻辑
s1=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd2: begin // 并行字段派生逻辑
f1=f1+4'd1; // 计入请求或响应字段
if(i_half[37]) d1[0 +: 4]={1'b0,i_half[45:44],1'b0}+4'd2; // 未压缩读响应LEN
end // 并行字段派生逻辑
4'd3: begin // 并行字段派生逻辑
f1=f1+4'd1; // 计入请求或响应字段
if(i_half[59:57]>=3'd3) begin // 压缩写类CMD
d1[0 +: 4]={1'b0,i_half[40:39],1'b0}+4'd2; // 压缩LEN
b1[0]=(i_half[59:57]==3'd3)||(i_half[59:57]==3'd4); // 非Full写附加BE
end // 并行字段派生逻辑
end // 并行字段派生逻辑
4'd4: begin // 并行字段派生逻辑
f1=f1+4'd1; // 计入请求或响应字段
d1[4 +: 4]=4'd2; // 单Beat读响应
end // 并行字段派生逻辑
4'd5: begin // 并行字段派生逻辑
f1=f1+4'd1; // 计入请求或响应字段
if(i_half[33]) d1[4 +: 4]={1'b0,i_half[35:34],1'b0}+4'd2; // 压缩读响应
end // 并行字段派生逻辑
4'd6,4'd7:s1=2'd2; // 冲突规范编码明确未决
default:s1=2'd1; // 其余保留类型
endcase // 并行字段派生逻辑
end // 并行字段派生逻辑
always @* begin // 并行字段派生逻辑
s0=2'd0;f0=4'd0;d0=32'd0;b0=8'd0; // 并行字段派生逻辑
case(i_half[31:28]) // 并行字段派生逻辑
4'd0: begin end // FC无tenure
4'd1: begin // 并行字段派生逻辑
s0=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd2: begin // 并行字段派生逻辑
s0=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd3: begin // 并行字段派生逻辑
s0=2'd1; // 字段自然对齐错误
end // 并行字段派生逻辑
4'd4: begin // 并行字段派生逻辑
f0=f0+4'd1; // 计入请求或响应字段
d0[0 +: 4]=4'd2; // 单Beat读响应
end // 并行字段派生逻辑
4'd5: begin // 并行字段派生逻辑
f0=f0+4'd1; // 计入请求或响应字段
if(i_half[1]) d0[0 +: 4]={1'b0,i_half[3:2],1'b0}+4'd2; // 压缩读响应
end // 并行字段派生逻辑
4'd6,4'd7:s0=2'd2; // 冲突规范编码明确未决
default:s0=2'd1; // 其余保留类型
endcase // 并行字段派生逻辑
end // 并行字段派生逻辑
wire four3; // 自然对齐四sector字段信号声明
assign four3=(i_half[127:124]==4'd1); // 自然对齐四sector字段组合驱动
wire four7; // 自然对齐四sector字段信号声明
assign four7=(i_half[255:252]==4'd1); // 自然对齐四sector字段组合驱动
wire two1; // 自然对齐双sector字段信号声明
assign two1=(i_half[63:60]==4'd2)||(i_half[63:60]==4'd3); // 自然对齐双sector字段组合驱动
wire two3; // 自然对齐双sector字段信号声明
assign two3=(i_half[127:124]==4'd2)||(i_half[127:124]==4'd3); // 自然对齐双sector字段组合驱动
wire two5; // 自然对齐双sector字段信号声明
assign two5=(i_half[191:188]==4'd2)||(i_half[191:188]==4'd3); // 自然对齐双sector字段组合驱动
wire two7; // 自然对齐双sector字段信号声明
assign two7=(i_half[255:252]==4'd2)||(i_half[255:252]==4'd3); // 自然对齐双sector字段组合驱动
wire use3; // 并行字段派生逻辑信号声明
assign use3=1'b1; // 并行字段派生逻辑组合驱动
wire use2; // 并行字段派生逻辑信号声明
assign use2=!four3&&!two3; // 并行字段派生逻辑组合驱动
wire use1; // 并行字段派生逻辑信号声明
assign use1=!four3; // 并行字段派生逻辑组合驱动
wire use0; // 并行字段派生逻辑信号声明
assign use0=!four3&&!two1; // 并行字段派生逻辑组合驱动
wire use7; // 并行字段派生逻辑信号声明
assign use7=1'b1; // 并行字段派生逻辑组合驱动
wire use6; // 并行字段派生逻辑信号声明
assign use6=!four7&&!two7; // 并行字段派生逻辑组合驱动
wire use5; // 并行字段派生逻辑信号声明
assign use5=!four7; // 并行字段派生逻辑组合驱动
wire use4; // 并行字段派生逻辑信号声明
assign use4=!four7&&!two5; // 并行字段派生逻辑组合驱动
always @* begin // 并行字段派生逻辑
o_status=2'd0; // 并行字段派生逻辑
if(use7 && s7!=2'd0) o_status=s7; // 最高有效字段错误优先
else if(use6 && s6!=2'd0) o_status=s6; // 最高有效字段错误优先
else if(use5 && s5!=2'd0) o_status=s5; // 最高有效字段错误优先
else if(use4 && s4!=2'd0) o_status=s4; // 最高有效字段错误优先
else if(use3 && s3!=2'd0) o_status=s3; // 最高有效字段错误优先
else if(use2 && s2!=2'd0) o_status=s2; // 最高有效字段错误优先
else if(use1 && s1!=2'd0) o_status=s1; // 最高有效字段错误优先
else if(use0 && s0!=2'd0) o_status=s0; // 最高有效字段错误优先
o_fields=4'd0;o_data_counts=32'd0;o_byte_enable=8'd0; // 并行字段派生逻辑
if(!ZERO_ON_ERROR||(o_status==2'd0)) begin // 默认错误时清零；内部费用并行路径由调用方单独拒绝错误状态
o_fields=((((use0?f0:4'd0)+(use1?f1:4'd0))+((use2?f2:4'd0)+(use3?f3:4'd0)))+(((use4?f4:4'd0)+(use5?f5:4'd0))+((use6?f6:4'd0)+(use7?f7:4'd0)))); // 平衡字段数累计
o_data_counts=(use0?d0:32'd0)|(use1?d1:32'd0)|(use2?d2:32'd0)|(use3?d3:32'd0)|(use4?d4:32'd0)|(use5?d5:32'd0)|(use6?d6:32'd0)|(use7?d7:32'd0); // 并行字段派生逻辑
o_byte_enable=(use0?b0:8'd0)|(use1?b1:8'd0)|(use2?b2:8'd0)|(use3?b3:8'd0)|(use4?b4:8'd0)|(use5?b5:8'd0)|(use6?b6:8'd0)|(use7?b7:8'd0); // 并行字段派生逻辑
end // 并行字段派生逻辑
end // 并行字段派生逻辑
endmodule // 结束tl_control_tenure组合字段派生模块
