module tl_tx_channels #(parameter WIDTH=16,parameter integer RAW_HEADERS=0)( // tl_tx_channels模块：独立Request与Response候选及Data所有权选择
 input wire i_clk,i_rstn,i_taken, // 唯一输入时钟、同步低有效复位及真实端口发送事件
 input wire [6:0] i_pending,input wire i_auth,i_done,i_shared, // 同一真实端口的序列、认证及初始信用状态
 input wire [20*(WIDTH+1)-1:0] i_available,i_capacity, // 两类共同观察唯一物理信用账本
 input wire [2:0] i_request_budget,input wire [3:0] i_response_budget, // 实际Tx catch预算
 input wire [1:0] i_header_valid,input wire [511:0] i_headers, // 低lane为Request，高lane为Response准备好的Control
 input wire [1:0] i_tags_valid,input wire [511:0] i_tags, // 两条头部各自对应的AuthTags
 input wire [3:0] i_data_valid,input wire [511:0] i_data0,i_data1, // 每lane两位可见数量及各自有序Data或BE队首
 input wire i_fc_valid,input wire [511:0] i_fc_flit,input wire [1:0] i_fc_msg, // 真实FC发布器的独立来源
 output wire o_valid,output wire [511:0] o_flit,output wire [1:0] o_msg, // 发给同一真实信用端口的完整候选
 output wire [1:0] o_header_taken,o_tags_taken,output wire [3:0] o_data_taken,output wire o_fc_taken, // 分别确认被实际消费的类与来源
 output wire [1:0] o_header_error,o_capacity_shortfall // 分类错误和各队首超容量的独立本地诊断
); // 结束模块端口声明
generate if((RAW_HEADERS!=0)&&(RAW_HEADERS!=1))begin:gen_invalid_profile // 内部可见性模式只允许零或一
 tl_tx_channels_parameters_invalid Invalid_Inst(); // 非法覆盖在展开时失败
end endgenerate // 结束参数检查
reg r_preferred,r_owner,r_hold_class,r_hold_valid; // 下一头部偏好、旧Data所有者和停顿中的头部类
reg selected_class; // 本拍准备好的Control来源，不决定旧尾部的数据源
wire data_class;wire [1:0] format_ok,credit_ok,budget_ok,ready,nop_ready,candidate; // 两条独立候选资格
wire [1:0] credit_shortfall;wire [1:0] old_data_valid; // 两类超容量诊断及旧Data队首可用数量
wire header_taken,tags_taken;wire [1:0] data_taken; // 内层packer按真实发送确认
wire [1:0] has_data; // 两类原始tenure标记也在仲裁前计算
wire payload_visible;wire [255:0] selected_header,selected_tags; // 原始内部字只供资格解码，对外组包保持原无效零值
wire position_ready; // 当前Control位置是否允许新头部
assign old_data_valid=r_owner?i_data_valid[3:2]:i_data_valid[1:0]; // 旧tenure只观察已接纳头部的数据类
assign position_ready=(i_pending<=7'd1)&&!(i_auth&&(i_pending==7'd1))&&!((i_pending==7'd1)&&i_fc_valid&&(i_fc_msg!=2'd0)); // 保留Auth尾部及完成消息规则
genvar lane;generate for(lane=0;lane<2;lane=lane+1)begin:gen_class // Request和Response资格并行计算
 wire valid;wire [2:0] requests;wire [3:0] responses,fields; // 当前类实际字段计数
 wire [7:0] unused_starts,unused_requests,unused_responses,be;wire [31:0] counts;wire [1:0] status; // 解码位置及已确认tenure
 wire unused_wait;wire [119:0] unused_requirements;wire payload_ready; // 本拍负载及完整信用提议
 tl_control_decode Decode_Inst(i_headers[lane*256+:256],valid,requests,responses,unused_starts,unused_requests,unused_responses); // 实际字段类型决定归属
 tl_control_tenure Tenure_Inst(i_headers[lane*256+:256],status,fields,counts,be); // 未确认tenure不可成为发送候选
 tl_credit_admission #(.WIDTH(WIDTH)) Credit_Inst( // 每类独立比较整段Data与CMD信用
 .i_rstn(i_rstn),.i_control(1'b1),.i_done(i_done),.i_shared(i_shared), // 共享模式来自同一个实际端口
 .i_half(i_headers[lane*256+:256]),.i_available(i_available),.i_capacity(i_capacity), // 各头部看到同一物理余额
 .o_requirements(unused_requirements),.o_allow(credit_ok[lane]),.o_wait(unused_wait),.o_shortfall(credit_shortfall[lane]) // 保留独立的总容量不足判断
 ); // 结束每类信用准入实例端口连接
 assign format_ok[lane]=valid&&(status==2'd0)&&(fields!=4'd0)&&(!i_auth||(fields<=4'd4))&&((lane==0)?(responses==4'd0):(requests==3'd0)); // 只准许本队列对应的请求或响应字段
 assign candidate[lane]=i_header_valid[lane]&&format_ok[lane]; // 错类队首不能伪装成另一类发出
 assign budget_ok[lane]=(requests<=i_request_budget)&&(responses<=i_response_budget); // 两类catch条件分别核对
 assign has_data[lane]=((RAW_HEADERS==0)||i_header_valid[lane])&&((|counts)||(|be)); // Data或额外BE都来自本类有序负载源
 assign payload_ready=(i_pending!=7'd0)?(old_data_valid>=2'd1):(i_auth?i_tags_valid[lane]:(!has_data[lane]||(i_data_valid[lane*2+:2]>=2'd1))); // 有旧尾时保留旧类，新tenure才选择新类数据
 assign ready[lane]=candidate[lane]&&credit_ok[lane]&&budget_ok[lane]&&payload_ready&&position_ready; // 全部资格独立满足才参与优先仲裁
 assign nop_ready[lane]=candidate[lane]&&credit_ok[lane]&&!budget_ok[lane]; // 没有可发头部时选择需要catch NOP的候选
 assign o_header_error[lane]=i_rstn&&i_header_valid[lane]&&!format_ok[lane]; // 本地错类或格式错误不消费输入
 assign o_capacity_shortfall[lane]=i_rstn&&candidate[lane]&&credit_shortfall[lane]; // 一类超容量不阻止另一类独立检查
end endgenerate // 结束两类独立资格生成
always @* begin // 按就绪程度优先，再在同等级的两类间轮换
 selected_class=r_preferred; // 默认偏好仅在两类资格相同时使用
 if(r_hold_valid)selected_class=r_hold_class; // 输出停顿期间固定已提出的头部来源
 else if(|ready)selected_class=ready[r_preferred]?r_preferred:!r_preferred; // 可发另一类优先于任意阻塞队首
 else if(|nop_ready)selected_class=nop_ready[r_preferred]?r_preferred:!r_preferred; // catch恢复不能被缺信用队首挡住
 else if(|candidate)selected_class=candidate[r_preferred]?r_preferred:!r_preferred; // 保留可诊断的未获资格队首供内层等待或FC选择
end // 结束头部类别选择
assign data_class=(i_pending!=7'd0)?r_owner:selected_class; // 混合旧尾和新头时必须使用旧Data所有者
assign payload_visible=(RAW_HEADERS==0)||i_header_valid[selected_class]; // 兼容外部默认接口及内部空队首，包括任意停顿状态
assign selected_header=payload_visible?(selected_class?i_headers[511:256]:i_headers[255:0]):256'd0; // 仅在最终负载边界恢复原头部屏蔽
assign selected_tags=payload_visible?(selected_class?i_tags[511:256]:i_tags[255:0]):256'd0; // 标签与头部来自同一个原子存储字
 tl_tx_packer_core Packer_Inst( // 直接复用两类已完成的资格，避免选择头部后重复解码和信用比较
 .i_clk(i_clk),.i_rstn(i_rstn),.i_taken(i_taken),.i_pending(i_pending),.i_auth(i_auth), // 状态与真实端口同步
 .i_header_ready(ready[selected_class]),.i_nop_ready(nop_ready[selected_class]),.i_has_data(has_data[selected_class]), // 包括原位置、负载、信用及catch规则
 .i_header(selected_header),.i_tags(selected_tags), // 当前原始头部及标签保持至真实确认
 .i_data_valid(data_class?i_data_valid[3:2]:i_data_valid[1:0]),.i_data0(data_class?i_data0[511:256]:i_data0[255:0]),.i_data1(data_class?i_data1[511:256]:i_data1[255:0]), // Data仍跟随实际tenure所有者
 .i_fc_valid(i_fc_valid),.i_fc_flit(i_fc_flit),.i_fc_msg(i_fc_msg), // FC来源独立于头部资格
 .o_valid(o_valid),.o_flit(o_flit),.o_msg(o_msg),.o_header_taken(header_taken),.o_tags_taken(tags_taken),.o_data_taken(data_taken),.o_fc_taken(o_fc_taken) // 同一真实发送事件确认各输入
 ); // 结束复用资格的packer实例
assign o_header_taken=header_taken?(selected_class?2'b10:2'b01):2'b00; // 新头部只确认被选类别
assign o_tags_taken=tags_taken?(selected_class?2'b10:2'b01):2'b00; // AuthTags与新头部在同一类别确认
assign o_data_taken=data_class?{data_taken,2'd0}:{2'd0,data_taken}; // 旧Data尾部确认与新头部类选择严格分离
always @(posedge i_clk)begin // 记录下一次同等级头部的优先类
 if(!i_rstn)r_preferred<=1'b0; // 同步复位默认Request优先
 else if(header_taken)r_preferred<=!selected_class; // 只有实际发出头部才让另一类优先
end // 结束头部公平偏好寄存器
always @(posedge i_clk)begin // 记录新接纳头部带来的Data所有者
 if(!i_rstn)r_owner<=1'b0; // 同步复位后尚无旧tenure，默认类零
 else if(header_taken)r_owner<=selected_class; // 旧尾同拍仍用原所有者，下一拍切换新头部类
end // 结束Data所有权寄存器
always @(posedge i_clk)begin // 记录停顿时的候选类别
 if(!i_rstn)r_hold_class<=1'b0; // 同步复位清除历史头部类
 else if(o_valid&&!i_taken)r_hold_class<=selected_class; // 输入队首未确认期间保持来源
end // 结束停顿类别寄存器
always @(posedge i_clk)begin // 记录停顿来源锁定是否有效
 if(!i_rstn)r_hold_valid<=1'b0; // 同步复位取消未确认提议
 else r_hold_valid<=o_valid&&!i_taken; // 实际发送或没有候选时释放类别锁定
end // 结束停顿有效寄存器
endmodule // 结束tl_tx_channels模块
