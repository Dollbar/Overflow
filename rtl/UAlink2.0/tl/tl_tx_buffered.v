module tl_tx_buffered #(parameter WIDTH=16, // tl_tx_buffered模块：两个类别实际SRAM发送队列与原子打包
 parameter integer HEADER_DEPTH=2,BANK_DEPTH=3, // 每类头部容量与每Data bank容量独立配置
 parameter integer HEADER_COUNT_WIDTH=(HEADER_DEPTH<2)?1:(HEADER_DEPTH<4)?2:(HEADER_DEPTH<8)?3:(HEADER_DEPTH<16)?4:(HEADER_DEPTH<32)?5:(HEADER_DEPTH<64)?6:(HEADER_DEPTH<128)?7:(HEADER_DEPTH<256)?8:(HEADER_DEPTH<512)?9:(HEADER_DEPTH<1024)?10:(HEADER_DEPTH<2048)?11:(HEADER_DEPTH<4096)?12:(HEADER_DEPTH<8192)?13:(HEADER_DEPTH<16384)?14:(HEADER_DEPTH<32768)?15:16, // 头部FIFO严格验证派生宽度
 parameter integer DATA_COUNT_WIDTH=(BANK_DEPTH<2)?1:(BANK_DEPTH<4)?2:(BANK_DEPTH<8)?3:(BANK_DEPTH<16)?4:(BANK_DEPTH<32)?5:(BANK_DEPTH<64)?6:(BANK_DEPTH<128)?7:(BANK_DEPTH<256)?8:(BANK_DEPTH<512)?9:(BANK_DEPTH<1024)?10:(BANK_DEPTH<2048)?11:(BANK_DEPTH<4096)?12:(BANK_DEPTH<8192)?13:(BANK_DEPTH<16384)?14:(BANK_DEPTH<32768)?15:16 // 单Data bank计数宽度，总数增加一位
)( // 结束参数列表并声明实际缓存及发送接口
 input wire i_clk,i_rstn,i_taken, // 唯一输入时钟、同步低有效复位及真实端口发送事件
 input wire [6:0] i_pending,input wire i_auth,i_done,i_shared, // 同一真实端口的序列、认证及初始信用状态
 input wire [20*(WIDTH+1)-1:0] i_available,i_capacity, // 两类共同观察唯一物理信用账本
 input wire [2:0] i_request_budget,input wire [3:0] i_response_budget, // 实际Tx catch预算
 input wire [1:0] i_header_valid,input wire [511:0] i_headers, // 低lane为Request，高lane为Response准备好的Control
 input wire [1:0] i_tags_valid,input wire [511:0] i_tags, // 两条头部各自对应的AuthTags，Auth开启时必须与头部一起可用
 input wire [3:0] i_data_valid,input wire [511:0] i_data0,i_data1, // 每lane两位有序入队提议数量及各自有序Data或BE队首
 input wire i_fc_valid,input wire [511:0] i_fc_flit,input wire [1:0] i_fc_msg, // 真实FC发布器的独立来源
 output wire o_valid,output wire [511:0] o_flit,output wire [1:0] o_msg, // 发给同一真实信用端口的完整候选
 output wire [1:0] o_header_taken,o_tags_taken,output wire [3:0] o_data_taken,output wire o_fc_taken, // 分别确认被实际消费的类与来源
 output wire [1:0] o_header_error,o_capacity_shortfall, // 分类错误和各队首超容量的独立本地诊断
 output wire [3:0] o_data_accepted, // 反馈各类实际入队半Flit数，未接纳项由上游继续保持
 output wire [1:0] o_header_ready,o_data_ready,o_input_error, // 上游头部标签原子接纳与各类数据反压、非法数量
 output wire [2*HEADER_COUNT_WIDTH-1:0] o_header_count, // 每类尚未线上消费的实际头部数
 output wire [2*(DATA_COUNT_WIDTH+1)-1:0] o_data_count // 每类SRAM、在途读和缓存中的半Flit总数
); // 结束实际发送缓存端口声明
wire [511:0] headers,tags,data0,data1;wire [1:0] header_valid;wire [3:0] data_valid; // 来自真实SRAM的四条独立有序来源
wire [1:0] header_taken,tags_taken;wire [3:0] data_taken; // 唯一实际线上消费事件返回各存储所有者
assign o_header_taken=header_taken;assign o_tags_taken=tags_taken;assign o_data_taken=data_taken; // 保留观察接口，生产者释放由独立入队握手决定
genvar lane;generate for(lane=0;lane<2;lane=lane+1)begin:gen_queues // 每个类别各有头部与数据容量，禁止相互借用
 wire raw_header_ready;wire [511:0] header_word; // 原子保存Control和AuthTags，避免标签与事务错配
 wire tags_ready; // Auth关闭时不要求无意义的标签有效
 assign tags_ready=!i_auth||i_tags_valid[lane]; // 配置在复位时期确定且运行中稳定
 assign o_header_ready[lane]=raw_header_ready&&tags_ready; // 头部握手只有同时保存其标签时才对外成立
 upli_receive_storage #(.C_DEPTH(HEADER_DEPTH),.C_DATA_WIDTH(512),.C_COUNT_WIDTH(HEADER_COUNT_WIDTH),.C_ZERO_INVALID(0)) Header_Inst( // 每类头部和标签在同一SRAM字中
 .i_clk(i_clk),.i_rstn(i_rstn),.i_write_valid(i_header_valid[lane]&&tags_ready),.i_write_data({i_tags[lane*256+:256],i_headers[lane*256+:256]}),.o_write_ready(raw_header_ready), // 接纳端和输出端独立推进
 .i_read_ready(header_taken[lane]),.o_read_valid(header_valid[lane]),.o_read_data(header_word),.o_count(o_header_count[lane*HEADER_COUNT_WIDTH+:HEADER_COUNT_WIDTH]) // 线上实际发送后才释放头部容量
 ); // 结束每类头部SRAM实例
 assign headers[lane*256+:256]=header_word[255:0];assign tags[lane*256+:256]=header_word[511:256]; // 拆分原子读取的头部与其保存标签
 tl_tx_data_fifo #(.BANK_DEPTH(BANK_DEPTH),.COUNT_WIDTH(DATA_COUNT_WIDTH)) Data_Inst( // 两个真实SRAM bank允许每拍一或二半Flit
 .i_clk(i_clk),.i_rstn(i_rstn),.i_write_valid(i_data_valid[lane*2+:2]!=2'd0),.i_write_count(i_data_valid[lane*2+:2]), // 零数量表示空闲，三数量由FIFO拒绝并诊断
 .i_data0(i_data0[lane*256+:256]),.i_data1(i_data1[lane*256+:256]),.o_write_ready(o_data_ready[lane]),.o_write_taken(o_data_accepted[lane*2+:2]), // 数据入队与头部流保持同类有序关系
 .i_take(data_taken[lane*2+:2]),.o_valid_count(data_valid[lane*2+:2]),.o_data0(data0[lane*256+:256]),.o_data1(data1[lane*256+:256]), // 旧尾和新头可确认不同类别的实际存储
 .o_count(o_data_count[lane*(DATA_COUNT_WIDTH+1)+:(DATA_COUNT_WIDTH+1)]),.o_error(o_input_error[lane]) // 发布精确总容量及本地数量错误
 ); // 结束每类双bank数据缓存实例
end endgenerate // 结束两类相互独立的真实发送存储结构
tl_tx_channels #(.WIDTH(WIDTH),.RAW_HEADERS(1)) Channels_Inst( // 复用已验证独立准入、旧Data所有权和FC公平打包
 .i_clk(i_clk),.i_rstn(i_rstn),.i_taken(i_taken),.i_pending(i_pending),.i_auth(i_auth),.i_done(i_done),.i_shared(i_shared), // 所有状态来自唯一实际信用端口
 .i_available(i_available),.i_capacity(i_capacity),.i_request_budget(i_request_budget),.i_response_budget(i_response_budget), // 原有整段信用和catch预算约束
 .i_header_valid(header_valid),.i_headers(headers),.i_tags_valid(header_valid),.i_tags(tags), // 每个保存的头部拥有原子配对的标签
 .i_data_valid(data_valid),.i_data0(data0),.i_data1(data1), // 缺数据时等待真实SRAM返回，禁止用输入旁路替代
 .i_fc_valid(i_fc_valid),.i_fc_flit(i_fc_flit),.i_fc_msg(i_fc_msg), // 信用返回继续使用独立实际发布器
 .o_valid(o_valid),.o_flit(o_flit),.o_msg(o_msg),.o_header_taken(header_taken),.o_tags_taken(tags_taken),.o_data_taken(data_taken),.o_fc_taken(o_fc_taken), // 只有真实发送确认修改缓存消费状态
 .o_header_error(o_header_error),.o_capacity_shortfall(o_capacity_shortfall) // 超容量和格式诊断保留未发送队首
); // 结束实际类别选择与打包实例
endmodule // 结束tl_tx_buffered模块
