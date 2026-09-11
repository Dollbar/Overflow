module tl_tx_packer #(parameter WIDTH=16)( // tl_tx_packer模块：准备好的Control、Data及FC按半Flit打包
 input wire i_clk,i_rstn,i_taken, // 唯一输入时钟、同步低有效复位及实际发送提交
 input wire [6:0] i_pending, // 真实发送端口尚待发送的Data或BE半Flit数
 input wire i_auth,i_done,i_shared, // 复位间认证模式及对端初始信用状态
 input wire [20*(WIDTH+1)-1:0] i_available,i_capacity, // 唯一发送账本的实际物理信用
 input wire [2:0] i_request_budget,input wire [3:0] i_response_budget, // 实际Tx验证状态的catch预算
 input wire i_header_valid,input wire [255:0] i_header, // 已准备Control队首，直至实际header_taken保持
 input wire i_tags_valid,input wire [255:0] i_tags, // 与头部对应的AuthTags，密码计算在外部
 input wire [1:0] i_data_valid,input wire [255:0] i_data0,i_data1, // 有序Data或BE队首可见数量及两个半Flit
 input wire i_fc_valid,input wire [511:0] i_fc_flit,input wire [1:0] i_fc_msg, // 真实发布器的FC或初始化完成候选
 output wire o_valid,output wire [511:0] o_flit,output wire [1:0] o_msg, // 稳定至实际发送的完整候选
 output wire o_header_taken,o_tags_taken,output wire [1:0] o_data_taken,output wire o_fc_taken, // 分别确认实际消耗的输入队首
 output wire o_header_wait,o_capacity_shortfall // 本地等待及仍需上层处理的总容量不足
); // 模块端口声明结束
wire credit_allow,unused_credit_wait,credit_shortfall;wire [119:0] unused_requirements; // 独立整段信用提议
wire decode_valid;wire [2:0] request_count;wire [3:0] response_count,fields; // 实际字段个数
wire [7:0] unused_starts,unused_request_starts,unused_response_starts,be; // 字段起点及额外BE
wire [1:0] tenure_status;wire [31:0] data_counts; // 每个字段的已确认Data数量
wire header_format,credit_ready,budget_ready,has_data,payload_ready,header_ready; // 独立就绪条件
 tl_credit_admission #(.WIDTH(WIDTH)) Credit_Inst( // 头部包含全部后续Data信用需求
 .i_rstn(i_rstn),.i_control(1'b1),.i_done(i_done),.i_shared(i_shared), // 只解码准备好的Control队首
 .i_half(i_header),.i_available(i_available),.i_capacity(i_capacity), // 实际账本信用
 .o_requirements(unused_requirements),.o_allow(credit_allow),.o_wait(unused_credit_wait),.o_shortfall(credit_shortfall) // 信用准入及容量诊断
 ); // 结束整段信用实例端口连接
 tl_control_decode Decode_Inst(i_header,decode_valid,request_count,response_count,unused_starts,unused_request_starts,unused_response_starts); // 真实Control结构及catch需求
 tl_control_tenure Tenure_Inst(i_header,tenure_status,fields,data_counts,be); // 真实Control的Data与BE附带数量
assign header_format=decode_valid&&(tenure_status==2'd0)&&(fields!=4'd0)&&(!i_auth||(fields<=4'd4)); // 保留未决类型与Auth字段数量限制
assign credit_ready=header_format&&credit_allow; // 非法头部不能仅凭零需求放行
assign budget_ready=(request_count<=i_request_budget)&&(response_count<=i_response_budget); // 不超过实际Tx catch预算
assign has_data=(|data_counts)||(|be); // 任何后续Data或BE需要有序数据源
assign payload_ready=(i_pending==7'd1)?(i_data_valid>=2'd1):(i_auth?i_tags_valid:(!has_data||(i_data_valid>=2'd1))); // 尾部优先于新头部附带数据或认证标签
assign header_ready=i_header_valid&&credit_ready&&budget_ready&&payload_ready&&(i_pending<=7'd1)&&!(i_auth&&(i_pending==7'd1))&&!((i_pending==7'd1)&&i_fc_valid&&(i_fc_msg!=2'd0)); // Auth尾部和等待中的完成消息均先排空旧尾
 tl_tx_packer_core Core_Inst( // 独立接口保留原资格计算，再进入不含解码的来源选择核心
 .i_clk(i_clk),.i_rstn(i_rstn),.i_taken(i_taken),.i_pending(i_pending),.i_auth(i_auth), // 保持原时钟、复位与序列
 .i_header_ready(header_ready),.i_nop_ready(i_header_valid&&credit_ready&&!budget_ready),.i_has_data(has_data), // NOP的位置限制仍由核心检查
 .i_header(i_header),.i_tags(i_tags),.i_data_valid(i_data_valid),.i_data0(i_data0),.i_data1(i_data1), // 原始负载直接传递
 .i_fc_valid(i_fc_valid),.i_fc_flit(i_fc_flit),.i_fc_msg(i_fc_msg), // FC仲裁与旧尾部规则不变
 .o_valid(o_valid),.o_flit(o_flit),.o_msg(o_msg),.o_header_taken(o_header_taken),.o_tags_taken(o_tags_taken),.o_data_taken(o_data_taken),.o_fc_taken(o_fc_taken) // 完整公开输出
 ); // 结束独立packer核心实例
assign o_header_wait=i_rstn&&i_header_valid&&!header_ready; // 数据供应、序列位置、预算或信用均可能引起本地等待
assign o_capacity_shortfall=i_rstn&&i_header_valid&&header_format&&credit_shortfall; // 保留超容量事务诊断，不自动丢弃或改写
endmodule // 结束tl_tx_packer模块
