module tl_credit_admission #(parameter WIDTH=16)( // tl_credit_admission模块：当前确认字段的整段信用准入
 input wire i_rstn,i_control,i_done,i_shared, // 同步复位电平及真实发送序列边界
 input wire [255:0] i_half, // 待发送Control半Flit，数据阶段不解码
 input wire [20*(WIDTH+1)-1:0] i_available,i_capacity, // 唯一发送账本的当前物理槽计数
 output reg [119:0] o_requirements, // 每物理槽六位，容纳八个四Beat响应
 output wire o_allow,o_wait,o_shortfall // 可准入、暂缺信用、总容量不足诊断
); // 原子头部准入，不改变线上逐Data对扣费时刻
generate if(WIDTH<8||WIDTH>16)begin:gen_invalid_width // 实际端口信用宽度契约
 tl_credit_admission_invalid_WIDTH invalid_parameter(); // 非法参数明确拒绝展开
end endgenerate // 参数合法性检查结束
wire [1:0] status;wire [3:0] unused_fields;wire [31:0] w_counts;wire [7:0] unused_be; // 规范字段附带数量
wire [7:0] unused_count_lsb; // 每字段半Flit计数的最低位不参与完整Beat信用计算
assign unused_count_lsb={w_counts[28],w_counts[24],w_counts[20],w_counts[16],w_counts[12],w_counts[8],w_counts[4],w_counts[0]}; // 明确收集独立解码器接口中有意未使用的奇偶位
wire valid;wire [2:0] unused_requests;wire [3:0] unused_responses;wire [7:0] unused_starts,w_req,w_rsp;wire [15:0] field_vc;wire [7:0] field_pool; // 各字段保留原VC与Pool，直接匹配固定账户
wire eligible_format; // 未决及无效tenure均不得准入
assign eligible_format=valid&&(status==2'd0); // 未决及无效tenure均不得准入
wire [19:0] available_fit,capacity_fit; // 所有物理槽共同满足才准入
wire [119:0] raw_requirements; // 二十个逻辑槽的固定并行累计，尚未合并共享池
 tl_control_tenure u_tenure(i_half,status,unused_fields,w_counts,unused_be); // 复用已核对tenure解码
 tl_control_decode u_decode(i_half,valid,unused_requests,unused_responses,unused_starts,w_req,w_rsp); // 只解释真正字段起点
wire [1:0] w_vc0; // sector0字段VC
assign w_vc0=(i_half[127:124]==4'd1)?i_half[117:116]:((i_half[63:60]==4'd2)?i_half[59:58]:(i_half[63:60]==4'd3)?i_half[56:55]:i_half[27:26]); // sector0字段VC
wire w_pool0; // sector0字段Pool
assign w_pool0=(i_half[127:124]==4'd1)?i_half[102]:((i_half[63:60]==4'd2)?i_half[46]:(i_half[63:60]==4'd3)?i_half[41]:i_half[14]); // sector0字段Pool
assign field_vc[0+:2]=w_vc0;assign field_pool[0]=w_pool0; // 第0字段按原始VC和Pool属性匹配固定槽
wire [1:0] w_vc1; // sector1字段VC
assign w_vc1=i_half[59:58]; // sector1字段VC
wire w_pool1; // sector1字段Pool
assign w_pool1=i_half[46]; // sector1字段Pool
assign field_vc[2+:2]=w_vc1;assign field_pool[1]=w_pool1; // 第1字段按原始VC和Pool属性匹配固定槽
wire [1:0] w_vc2; // sector2字段VC
assign w_vc2=(i_half[127:124]==4'd2)?i_half[123:122]:(i_half[127:124]==4'd3)?i_half[120:119]:i_half[91:90]; // sector2字段VC
wire w_pool2; // sector2字段Pool
assign w_pool2=(i_half[127:124]==4'd2)?i_half[110]:(i_half[127:124]==4'd3)?i_half[105]:i_half[78]; // sector2字段Pool
assign field_vc[4+:2]=w_vc2;assign field_pool[2]=w_pool2; // 第2字段按原始VC和Pool属性匹配固定槽
wire [1:0] w_vc3; // sector3字段VC
assign w_vc3=i_half[123:122]; // sector3字段VC
wire w_pool3; // sector3字段Pool
assign w_pool3=i_half[110]; // sector3字段Pool
assign field_vc[6+:2]=w_vc3;assign field_pool[3]=w_pool3; // 第3字段按原始VC和Pool属性匹配固定槽
wire [1:0] w_vc4; // sector4字段VC
assign w_vc4=(i_half[255:252]==4'd1)?i_half[245:244]:((i_half[191:188]==4'd2)?i_half[187:186]:(i_half[191:188]==4'd3)?i_half[184:183]:i_half[155:154]); // sector4字段VC
wire w_pool4; // sector4字段Pool
assign w_pool4=(i_half[255:252]==4'd1)?i_half[230]:((i_half[191:188]==4'd2)?i_half[174]:(i_half[191:188]==4'd3)?i_half[169]:i_half[142]); // sector4字段Pool
assign field_vc[8+:2]=w_vc4;assign field_pool[4]=w_pool4; // 第4字段按原始VC和Pool属性匹配固定槽
wire [1:0] w_vc5; // sector5字段VC
assign w_vc5=i_half[187:186]; // sector5字段VC
wire w_pool5; // sector5字段Pool
assign w_pool5=i_half[174]; // sector5字段Pool
assign field_vc[10+:2]=w_vc5;assign field_pool[5]=w_pool5; // 第5字段按原始VC和Pool属性匹配固定槽
wire [1:0] w_vc6; // sector6字段VC
assign w_vc6=(i_half[255:252]==4'd2)?i_half[251:250]:(i_half[255:252]==4'd3)?i_half[248:247]:i_half[219:218]; // sector6字段VC
wire w_pool6; // sector6字段Pool
assign w_pool6=(i_half[255:252]==4'd2)?i_half[238]:(i_half[255:252]==4'd3)?i_half[233]:i_half[206]; // sector6字段Pool
assign field_vc[12+:2]=w_vc6;assign field_pool[6]=w_pool6; // 第6字段按原始VC和Pool属性匹配固定槽
wire [1:0] w_vc7; // sector7字段VC
assign w_vc7=i_half[251:250]; // sector7字段VC
wire w_pool7; // sector7字段Pool
assign w_pool7=i_half[238]; // sector7字段Pool
assign field_vc[14+:2]=w_vc7;assign field_pool[7]=w_pool7; // 第7字段按原始VC和Pool属性匹配固定槽
genvar account,field;generate for(account=0;account<20;account=account+1)begin:gen_requirements // 固定逻辑槽避免动态读写宽向量
 localparam integer SLOT_LANE=account%5; // 每类零号为Pool，其余四槽对应专用VC
 localparam integer SLOT_VC_VALUE=SLOT_LANE-1; // 专用槽减一得到原始两位VC编号
 localparam [1:0] SLOT_VC=SLOT_VC_VALUE[1:0]; // Pool分支不使用此值，专用VC显式限制为两位
 wire [5:0] contribution[0:7];wire [5:0] pair[0:3];wire [5:0] quad[0:1]; // 六位完整表示最多八命令或三十二Data信用
 for(field=0;field<8;field=field+1)begin:gen_field // 每个自然对齐字段只向所属槽提供贡献
  wire slot_match; // 不构造中间槽号，直接判断字段类别和Pool或VC
  assign slot_match=(((account%10)<5)?w_req[field]:(w_rsp[field]&&!w_req[field]))&&((SLOT_LANE==0)?field_pool[field]:(!field_pool[field]&&(field_vc[field*2+:2]==SLOT_VC))); // 保留原请求优先归属及五个物理lane的精确选择
  if(account<10)begin:gen_command // CMD每字段扣一份，与Data长度独立
   assign contribution[field]=slot_match?6'd1:6'd0; // 仅该逻辑CMD槽接收此字段计数
  end else begin:gen_data // Data贡献使用已确认的完整Beat数量
   assign contribution[field]=slot_match?{3'd0,w_counts[field*4+1+:3]}:6'd0; // BE半Flit不增加Data信用
  end // 结束CMD与Data静态分支
 end // 结束八字段独立贡献
 assign pair[0]=contribution[0]+contribution[1];assign pair[1]=contribution[2]+contribution[3]; // 第一级并行归约低四字段
 assign pair[2]=contribution[4]+contribution[5];assign pair[3]=contribution[6]+contribution[7]; // 第一级并行归约高四字段
 assign quad[0]=pair[0]+pair[1];assign quad[1]=pair[2]+pair[3]; // 第二级分别合计前后四字段
 assign raw_requirements[account*6+:6]=quad[0]+quad[1]; // 第三级得到固定槽总需求，无字段间动态选择链
end endgenerate // 结束二十逻辑槽的平衡累计
always @* begin // 合法Control门控与共享池归一化保持原接口时序
 o_requirements=120'd0; // 非Control、复位或未确认格式无需求
 if(i_rstn&&i_control&&eligible_format)begin // 所有字段解码语义保持原实现
  o_requirements=raw_requirements; // 一次写入完整逻辑需求而不逐字段改写动态槽
  if(i_shared)begin // 仅两个Data Pool合并，CMD及专用VC保持独立
   o_requirements[60+:6]=o_requirements[60+:6]+o_requirements[90+:6]; // 共享池总需求最多三十二
   o_requirements[90+:6]=6'd0; // 第二逻辑池在物理账本中已并入槽十
  end // 共享归一化结束
 end // 合法Control判断结束
end // 无寄存器的准入需求结束
genvar j;generate for(j=0;j<20;j=j+1)begin:credit_fit // 每槽独立等宽比较
 wire [WIDTH:0] need; // 六位需求无损扩宽
assign need={{(WIDTH-5){1'b0}},o_requirements[j*6+:6]}; // 六位需求无损扩宽
 assign available_fit[j]=need<=i_available[j*(WIDTH+1)+:WIDTH+1]; // 不借用尚未接收的返还
 assign capacity_fit[j]=need<=i_capacity[j*(WIDTH+1)+:WIDTH+1]; // 区分等待与无法容纳
end endgenerate // 比较器结束
assign o_allow=i_rstn&&(!i_control||(eligible_format&&((o_requirements==120'd0)||(i_done&&(&available_fit))))); // FC启动无信用依赖
assign o_shortfall=i_rstn&&i_control&&eligible_format&&i_done&&!( &capacity_fit); // 本地策略诊断，不生成新的线消息
assign o_wait=i_rstn&&i_control&&eligible_format&&!o_allow&&!o_shortfall; // 初始化或已用信用等待
endmodule // 结束tl_credit_admission模块
