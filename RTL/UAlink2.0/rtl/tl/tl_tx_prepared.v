module tl_tx_prepared #(parameter WIDTH=16, // tl_tx_prepared模块：完整源组捕获、容量分组与实际SRAM发送组合
 parameter integer HEADER_DEPTH=2,BANK_DEPTH=3, // 每类头部容量与每Data bank容量独立配置
 parameter integer HEADER_COUNT_WIDTH=(HEADER_DEPTH<2)?1:(HEADER_DEPTH<4)?2:(HEADER_DEPTH<8)?3:(HEADER_DEPTH<16)?4:(HEADER_DEPTH<32)?5:(HEADER_DEPTH<64)?6:(HEADER_DEPTH<128)?7:(HEADER_DEPTH<256)?8:(HEADER_DEPTH<512)?9:(HEADER_DEPTH<1024)?10:(HEADER_DEPTH<2048)?11:(HEADER_DEPTH<4096)?12:(HEADER_DEPTH<8192)?13:(HEADER_DEPTH<16384)?14:(HEADER_DEPTH<32768)?15:16, // 头部FIFO严格验证派生宽度
 parameter integer DATA_COUNT_WIDTH=(BANK_DEPTH<2)?1:(BANK_DEPTH<4)?2:(BANK_DEPTH<8)?3:(BANK_DEPTH<16)?4:(BANK_DEPTH<32)?5:(BANK_DEPTH<64)?6:(BANK_DEPTH<128)?7:(BANK_DEPTH<256)?8:(BANK_DEPTH<512)?9:(BANK_DEPTH<1024)?10:(BANK_DEPTH<2048)?11:(BANK_DEPTH<4096)?12:(BANK_DEPTH<8192)?13:(BANK_DEPTH<16384)?14:(BANK_DEPTH<32768)?15:16 // 单Data bank计数宽度，总数增加一位

)( // 结束参数列表并声明完整源组与实际发送端口
 input wire i_clk,i_rstn,i_taken, // 唯一输入时钟、同步复位和真实线上发送确认
 input wire [6:0] i_pending,input wire i_auth,i_done,i_shared, // 当前初始化时期的唯一端口状态
 input wire [20*(WIDTH+1)-1:0] i_available,i_capacity, // 实际可用信用及固定物理总容量
 input wire [2:0] i_request_budget,input wire [3:0] i_response_budget, // 两类实际catch预算
 input wire [1:0] i_source_valid,input wire [511:0] i_source_control, // 两个独立类别各提供完整256位源组
 input wire [1:0] i_source_tags_valid,input wire [1023:0] i_source_tags, // 每类八个64位标签在认证模式下与源组原子捕获
 input wire [3:0] i_data_valid,input wire [511:0] i_data0,i_data1, // 两类实际Data或BE有序入队来源
 input wire i_fc_valid,input wire [511:0] i_fc_flit,input wire [1:0] i_fc_msg, // 独立真实信用发布器来源
 output wire [1:0] o_source_ready,o_source_captured,o_source_tags_taken, // 捕获即转移完整源组及有效认证标签的所有权
 output wire [1:0] o_group_queued,o_partition_taken, // 整组最终入队和单个分组入队分别报告
 output wire [1:0] o_prepare_error,o_prepare_shortfall, // 已捕获组的格式或总容量错误保留至复位
 output wire o_valid,output wire [511:0] o_flit,output wire [1:0] o_msg, // 唯一实际端口的完整发送候选
 output wire [1:0] o_header_taken,o_tags_taken,output wire [3:0] o_data_taken,output wire o_fc_taken, // 线上消费反馈独立于上游源组捕获
 output wire [1:0] o_header_error,o_capacity_shortfall, // 实际队首格式和容量诊断
 output wire [3:0] o_data_accepted,output wire [1:0] o_data_ready,o_input_error, // Data入队数量、反压及非法数量诊断
 output wire [2*HEADER_COUNT_WIDTH-1:0] o_header_count, // 实际尚未线上消费的分组数量
 output wire [2*(DATA_COUNT_WIDTH+1)-1:0] o_data_count // 实际Data缓存、在途读和SRAM总数量
); // 结束生产发送组合端口声明
wire [1:0] partition_valid,partition_ready;wire [511:0] partition_control,partition_tags; // 两个准备器只在实际头部FIFO接纳时推进
wire [7:0] partition_fields,partition_end,partition_cursor; // 完整字段分组位置用于内部审计观察
wire [23:0] unused_partition_observation; // 内部观察信号不影响实际消费或源释放
assign unused_partition_observation={partition_fields,partition_end,partition_cursor}; // 显式标记未用于功能决策的观察总线
genvar lane;generate for(lane=0;lane<2;lane=lane+1)begin:gen_prepare // Request和Response分别保存完整源组所有权
 localparam RESPONSE=(lane==1); // 固定类别在综合展开时决定，不依赖实时源内容
 wire capture_ready,tags_ready; // 认证模式要求源头与八个标签同时可用
 assign tags_ready=!i_auth||i_source_tags_valid[lane]; // 非认证模式不消费无意义的标签来源
 assign o_source_ready[lane]=capture_ready&&tags_ready; // 对外ready只表示此沿可以原子接纳源组
 assign o_source_tags_taken[lane]=i_auth&&o_source_captured[lane]; // 标签的释放与完整源组捕获在同一沿
 tl_prepared_partition #(.WIDTH(WIDTH)) Prepare_Inst( // 捕获后只消费本地保存的源数据与元数据
 .i_clk(i_clk),.i_rstn(i_rstn),.i_source_valid(i_source_valid[lane]&&tags_ready),.i_ready(partition_ready[lane]), // 输入捕获和分组入队拥有不同握手
 .i_done(i_done),.i_response(RESPONSE),.i_auth(i_auth),.i_shared(i_shared), // 属性在当前初始化时期稳定
 .i_source_control(i_source_control[lane*256+:256]),.i_source_tags(i_source_tags[lane*512+:512]),.i_capacity(i_capacity), // 每类捕获完整源组与对应八个标签
 .o_source_ready(capture_ready),.o_captured(o_source_captured[lane]),.o_valid(partition_valid[lane]),.o_taken(o_partition_taken[lane]), // 实际队列反压直接传到当前分组
 .o_group_done(o_group_queued[lane]),.o_error(o_prepare_error[lane]),.o_shortfall(o_prepare_shortfall[lane]), // 最后分组入队允许同拍捕获下一个源组
 .o_control(partition_control[lane*256+:256]),.o_tags(partition_tags[lane*256+:256]), // 输出最多四个标签，保持完整字段顺序
 .o_fields(partition_fields[lane*4+:4]),.o_end(partition_end[lane*4+:4]),.o_cursor(partition_cursor[lane*4+:4]) // 分组观察不参与源生产者索引
 ); // 结束每类完整源组准备器实例
end endgenerate // 结束两个独立源所有者
tl_tx_buffered #(.WIDTH(WIDTH),.HEADER_DEPTH(HEADER_DEPTH),.BANK_DEPTH(BANK_DEPTH),.HEADER_COUNT_WIDTH(HEADER_COUNT_WIDTH),.DATA_COUNT_WIDTH(DATA_COUNT_WIDTH)) Buffered_Inst( // 使用真实SRAM队列和原有双类原子打包
 .i_clk(i_clk),.i_rstn(i_rstn),.i_taken(i_taken),.i_pending(i_pending),.i_auth(i_auth),.i_done(i_done),.i_shared(i_shared), // 与准备器使用同一时钟和初始化时期
 .i_available(i_available),.i_capacity(i_capacity),.i_request_budget(i_request_budget),.i_response_budget(i_response_budget), // 可用信用仍在真实发送时检查
 .i_header_valid(partition_valid),.i_headers(partition_control),.i_tags_valid(partition_valid),.i_tags(partition_tags), // 准备器输出的分组和四个标签原子入队
 .i_data_valid(i_data_valid),.i_data0(i_data0),.i_data1(i_data1), // Data或BE按原有接口独立有序保存
 .i_fc_valid(i_fc_valid),.i_fc_flit(i_fc_flit),.i_fc_msg(i_fc_msg), // 信用返回不经过源组准备器
 .o_valid(o_valid),.o_flit(o_flit),.o_msg(o_msg),.o_header_taken(o_header_taken),.o_tags_taken(o_tags_taken),.o_data_taken(o_data_taken),.o_fc_taken(o_fc_taken), // 保留实际线上消费语义
 .o_header_error(o_header_error),.o_capacity_shortfall(o_capacity_shortfall),.o_data_accepted(o_data_accepted), // 实际队列错误及入队计数继续独立报告
 .o_header_ready(partition_ready),.o_data_ready(o_data_ready),.o_input_error(o_input_error),.o_header_count(o_header_count),.o_data_count(o_data_count) // 单个分组只有收到真实ready才能退休
); // 结束实际缓存及打包组合实例
endmodule // 结束tl_tx_prepared模块
