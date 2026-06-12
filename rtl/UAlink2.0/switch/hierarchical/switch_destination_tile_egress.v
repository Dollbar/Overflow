`timescale 1ns/1ps // 统一Destination Tile切片的仿真时间单位。
`default_nettype none // 禁止隐式网络掩盖逐Port队列接线错误。
// Destination Tile逐Port出口：每个Port/Class/VC拥有独立逻辑FIFO，每个Port拥有独立输出调度器。
// 队列到Egress protocol adapter采用标准ready/valid；TL/UPLI信用由adapter在实际协议发送处拥有。
module switch_destination_tile_egress #( // 可综合的单入口、多Port并行出口切片。
 parameter integer C_NUM_PORTS=4, // 本Tile实现的Logical Port数，目标配置最多三十二。
 parameter integer C_NUM_CLASSES=2, // Request/Response等内部traffic class数量。
 parameter integer C_NUM_VC=4, // 保存并恢复的原始UALink VC数量。
 parameter integer C_DATA_WIDTH=32, // Internal flit payload位宽。
 parameter integer C_META_WIDTH=16, // 除显式路由字段外的opaque metadata位宽。
 parameter integer C_PORT_WIDTH=3, // 输入目的Port编码位宽，允许reduced测试注入非法编号。
 parameter integer C_CLASS_WIDTH=1, // traffic class编码位宽。
 parameter integer C_VC_WIDTH=2, // original VC编码位宽。
 parameter integer C_QUEUE_DEPTH=4, // 每个Port/Class/VC逻辑队列的真实深度。
 parameter integer C_COUNT_WIDTH=3, // 队列occupancy计数位宽。
 parameter integer C_PER_PORT_QUEUES=C_NUM_CLASSES*C_NUM_VC, // 每Port逻辑队列数。
 parameter integer C_TOTAL_QUEUES=C_NUM_PORTS*C_PER_PORT_QUEUES, // Tile全部逻辑队列数。
 parameter integer C_QUEUE_WIDTH=(C_TOTAL_QUEUES<=2)?1:(C_TOTAL_QUEUES<=4)?2:(C_TOTAL_QUEUES<=8)?3:(C_TOTAL_QUEUES<=16)?4:(C_TOTAL_QUEUES<=32)?5:(C_TOTAL_QUEUES<=64)?6:(C_TOTAL_QUEUES<=128)?7:(C_TOTAL_QUEUES<=256)?8:(C_TOTAL_QUEUES<=512)?9:10, // 展平队列索引位宽。
 parameter integer C_SELECT_WIDTH=(C_PER_PORT_QUEUES<=2)?1:(C_PER_PORT_QUEUES<=4)?2:(C_PER_PORT_QUEUES<=8)?3:(C_PER_PORT_QUEUES<=16)?4:5, // 单Port调度索引位宽。
 parameter integer C_PORT_INDEX_WIDTH=(C_NUM_PORTS<=2)?1:(C_NUM_PORTS<=4)?2:(C_NUM_PORTS<=8)?3:(C_NUM_PORTS<=16)?4:5, // 合法Port数组索引位宽。
 parameter integer C_SLOT_WIDTH=(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=2)?1:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=4)?2:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=8)?3:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=16)?4:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=32)?5:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=64)?6:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=128)?7:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=256)?8:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=512)?9:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=1024)?10:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=2048)?11:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=4096)?12:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=8192)?13:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=16384)?14:(C_TOTAL_QUEUES*C_QUEUE_DEPTH<=32768)?15:16 // 展平存储槽地址位宽，覆盖三十二Port/四Class/八VC参数上界。
)( // 结束参数并声明internal-flit与逐Port输出端口。
 input wire i_clk,input wire i_rstn, // 唯一同步时钟与低有效同步复位。
 input wire i_valid,output reg o_ready, // 单路internal-flit输入握手。
 input wire [C_DATA_WIDTH-1:0] i_data,input wire [C_META_WIDTH-1:0] i_meta, // 输入payload与opaque metadata。
 input wire [C_PORT_WIDTH-1:0] i_dst_port,input wire [C_CLASS_WIDTH-1:0] i_class, // 最终Port与内部class。
 input wire [C_VC_WIDTH-1:0] i_original_vc,input wire i_pool,input wire i_sop,input wire i_eop, // Egress恢复所需字段与包边界。
 input wire [C_NUM_PORTS-1:0] i_port_active,input wire [C_NUM_PORTS-1:0] i_upli_credit, // Port配置有效及UPLI发送许可。
 input wire [C_NUM_PORTS-1:0] i_tl_credit,input wire [C_NUM_PORTS-1:0] i_link_up, // TL发送许可及独立Link状态。
 output reg [C_NUM_PORTS-1:0] o_head_valid, // 队首预览独立于credit；供相邻协议context计算精确demand。
 output reg [C_NUM_PORTS-1:0] o_valid,input wire [C_NUM_PORTS-1:0] i_ready, // 每Port独立输出握手。
 output reg [C_NUM_PORTS*C_DATA_WIDTH-1:0] o_data,output reg [C_NUM_PORTS*C_META_WIDTH-1:0] o_meta, // 每Port输出payload与metadata。
 output reg [C_NUM_PORTS*C_PORT_WIDTH-1:0] o_dst_port, // 输出PortID用于接入对应UPLI context审计。
 output reg [C_NUM_PORTS*C_CLASS_WIDTH-1:0] o_class, // 每Port当前输出traffic class。
 output reg [C_NUM_PORTS*C_VC_WIDTH-1:0] o_original_vc, // 每Port恢复的原始VC。
 output reg [C_NUM_PORTS-1:0] o_pool,output reg [C_NUM_PORTS-1:0] o_sop,output reg [C_NUM_PORTS-1:0] o_eop, // Pool及包边界保持到真实握手。
 output reg [C_TOTAL_QUEUES*C_COUNT_WIDTH-1:0] o_queue_occupancy,output wire o_empty, // CSR与守恒验证观察。
 output reg o_illegal_dst_error,output reg o_inactive_dst_error, // 非法编号及inactive目的sticky错误。
 output reg o_protocol_error,output wire o_error // 包边界/归属错误及总错误。
); // 结束模块端口声明。
 function egress_width_encodes; // 参数化编码必须有正位宽，并避免大于整数移位范围。
  input integer width_value;input integer count_value;
  begin if((width_value<1)||(width_value>30)||(count_value<1))egress_width_encodes=0;else egress_width_encodes=((32'd1<<width_value)>=count_value);end
 endfunction
 localparam integer C_TOTAL_SLOTS=C_TOTAL_QUEUES*C_QUEUE_DEPTH; // 全部逻辑FIFO映射的存储槽数。
 localparam [C_COUNT_WIDTH-1:0] C_DEPTH_COUNT=C_QUEUE_DEPTH[C_COUNT_WIDTH-1:0]; // 等宽深度比较常量。
 localparam [C_PORT_WIDTH:0] C_PORT_LIMIT=C_NUM_PORTS[C_PORT_WIDTH:0]; // 防别名的Port上界。
 localparam [C_CLASS_WIDTH:0] C_CLASS_LIMIT=C_NUM_CLASSES[C_CLASS_WIDTH:0]; // class上界。
 localparam [C_VC_WIDTH:0] C_VC_LIMIT=C_NUM_VC[C_VC_WIDTH:0]; // VC上界。
 localparam [C_SELECT_WIDTH:0] C_SELECT_LIMIT=C_PER_PORT_QUEUES[C_SELECT_WIDTH:0]; // RR扫描的等宽队列数上界。
 localparam CONFIG_LEGAL=(C_NUM_PORTS>=1)&&(C_NUM_PORTS<=32)&&(C_NUM_CLASSES>=1)&&(C_NUM_CLASSES<=4)&&(C_NUM_VC>=1)&&(C_NUM_VC<=8)&&
  (C_QUEUE_DEPTH>=2)&&(C_TOTAL_SLOTS<=65536)&&(C_DATA_WIDTH>=1)&&(C_META_WIDTH>=1)&&
  (C_PER_PORT_QUEUES==C_NUM_CLASSES*C_NUM_VC)&&(C_TOTAL_QUEUES==C_NUM_PORTS*C_PER_PORT_QUEUES)&&
  egress_width_encodes(C_PORT_WIDTH,C_NUM_PORTS)&&egress_width_encodes(C_CLASS_WIDTH,C_NUM_CLASSES)&&
  egress_width_encodes(C_VC_WIDTH,C_NUM_VC)&&egress_width_encodes(C_COUNT_WIDTH,C_QUEUE_DEPTH+1)&&
  egress_width_encodes(C_QUEUE_WIDTH,C_TOTAL_QUEUES)&&egress_width_encodes(C_SELECT_WIDTH,C_PER_PORT_QUEUES)&&
  egress_width_encodes(C_PORT_INDEX_WIDTH,C_NUM_PORTS)&&egress_width_encodes(C_SLOT_WIDTH,C_TOTAL_SLOTS); // 派生关系和全部索引位宽均必须无别名。
 reg [C_DATA_WIDTH-1:0] data_mem[0:C_TOTAL_SLOTS-1]; // 每槽真实payload存储。
 reg [C_META_WIDTH-1:0] meta_mem[0:C_TOTAL_SLOTS-1]; // 每槽opaque metadata存储。
 reg [C_PORT_WIDTH-1:0] port_mem[0:C_TOTAL_SLOTS-1]; // 每槽目的Port审计字段。
 reg [C_CLASS_WIDTH-1:0] class_mem[0:C_TOTAL_SLOTS-1]; // 每槽traffic class。
 reg [C_VC_WIDTH-1:0] vc_mem[0:C_TOTAL_SLOTS-1]; // 每槽original VC。
 reg pool_mem[0:C_TOTAL_SLOTS-1];reg sop_mem[0:C_TOTAL_SLOTS-1];reg eop_mem[0:C_TOTAL_SLOTS-1]; // 每槽Pool及边界。
 integer head_q[0:C_TOTAL_QUEUES-1];integer tail_q[0:C_TOTAL_QUEUES-1]; // 各逻辑队列环形指针。
 reg [C_COUNT_WIDTH-1:0] occupancy_q[0:C_TOTAL_QUEUES-1]; // 各逻辑队列真实占用。
 reg input_owner_q;reg [C_QUEUE_WIDTH-1:0] input_queue_q; // 单入口多拍包固定队列归属。
 reg [C_PORT_WIDTH-1:0] input_port_q;reg [C_CLASS_WIDTH-1:0] input_class_q; // 多拍输入固定目的与class。
 reg [C_VC_WIDTH-1:0] input_vc_q;reg input_pool_q; // 多拍输入固定VC与Pool。
 reg [C_NUM_PORTS-1:0] output_owner_q; // 每Port从首拍stall/接纳起锁定输出队列。
 reg [C_QUEUE_WIDTH-1:0] output_queue_q[0:C_NUM_PORTS-1]; // 每Port当前packet owner队列。
 reg [C_SELECT_WIDTH-1:0] rr_q[0:C_NUM_PORTS-1]; // 每Port下一次class/VC扫描起点。
 reg [C_NUM_PORTS-1:0] selected_valid;reg [C_QUEUE_WIDTH-1:0] selected_queue[0:C_NUM_PORTS-1];reg [C_SELECT_WIDTH-1:0] selected_local[0:C_NUM_PORTS-1]; // 组合候选。
 reg [C_SELECT_WIDTH-1:0] output_local_q[0:C_NUM_PORTS-1]; // owner保存本Port局部队列号以无除法更新RR。
 reg [C_TOTAL_QUEUES-1:0] dequeue_queue; // 同拍最多每Port一个真实出队事件。
 reg input_legal,input_phase_legal;reg [C_QUEUE_WIDTH-1:0] input_queue;reg [C_PORT_INDEX_WIDTH-1:0] decoded_port; // 输入查表与协议资格。
 reg enqueue_fire;reg [C_NUM_PORTS-1:0] output_fire; // 所有状态只由真实握手推进。
 reg [C_QUEUE_WIDTH-1:0] input_queue_value;reg [C_SLOT_WIDTH-1:0] input_write_slot;reg [C_SLOT_WIDTH-1:0] output_slot; // 队列号与存储地址均保持参数化的精确位宽。
 integer port_index;integer scan_index;reg [C_SELECT_WIDTH:0] select_value;reg [C_SELECT_WIDTH-1:0] select_local;reg [C_QUEUE_WIDTH-1:0] candidate_queue; // 分布式RR扫描临时值。
 integer queue_index;integer reset_port;integer update_queue;integer read_port; // 组合导出及状态更新索引。
 reg any_occupancy; // 全队列empty归约结果。
 function [C_QUEUE_WIDTH-1:0] make_input_queue; // 将合法Port/Class/VC精确展平为逻辑队列号。
  input [C_PORT_INDEX_WIDTH-1:0] port_value;input [C_CLASS_WIDTH-1:0] class_value;input [C_VC_WIDTH-1:0] vc_value;reg [31:0] arithmetic_value; // 显式零扩展使Verilog-2001各项算术宽度一致。
  begin arithmetic_value={{(32-C_PORT_INDEX_WIDTH){1'b0}},port_value}*C_PER_PORT_QUEUES+{{(32-C_CLASS_WIDTH){1'b0}},class_value}*C_NUM_VC+{{(32-C_VC_WIDTH){1'b0}},vc_value};if(|arithmetic_value[31:C_QUEUE_WIDTH])make_input_queue={C_QUEUE_WIDTH{1'bx}};else make_input_queue=arithmetic_value[C_QUEUE_WIDTH-1:0];end
 endfunction // 结束输入队列索引函数。
 function [C_QUEUE_WIDTH-1:0] make_candidate_queue; // 将Port与Port内RR编号转换为全局队列号。
  input [C_PORT_INDEX_WIDTH-1:0] port_value;input [C_SELECT_WIDTH-1:0] local_value;reg [31:0] arithmetic_value; // 中间值完整覆盖三十二Port配置。
  begin arithmetic_value={{(32-C_PORT_INDEX_WIDTH){1'b0}},port_value}*C_PER_PORT_QUEUES+{{(32-C_SELECT_WIDTH){1'b0}},local_value};if(|arithmetic_value[31:C_QUEUE_WIDTH])make_candidate_queue={C_QUEUE_WIDTH{1'bx}};else make_candidate_queue=arithmetic_value[C_QUEUE_WIDTH-1:0];end
 endfunction // 结束候选队列索引函数。
 function [C_SLOT_WIDTH-1:0] make_slot; // 形成某逻辑队列当前head或tail的真实存储槽地址。
  input [C_QUEUE_WIDTH-1:0] queue_value;input integer pointer_value;reg [31:0] arithmetic_value; // 指针只在零至深度减一范围内使用。
  begin arithmetic_value={{(32-C_QUEUE_WIDTH){1'b0}},queue_value}*C_QUEUE_DEPTH+pointer_value;if(|arithmetic_value[31:C_SLOT_WIDTH])make_slot={C_SLOT_WIDTH{1'bx}};else make_slot=arithmetic_value[C_SLOT_WIDTH-1:0];end
 endfunction // 结束存储槽地址函数。
 assign o_empty=!any_occupancy; // 仅occupancy决定有效数据，SRAM内容无需清零。
 wire eligibility_observation=^(i_upli_credit^i_tl_credit^i_link_up); // 旧ABI仅保留观察，不能再预门控队首。
 assign o_error=o_illegal_dst_error||o_inactive_dst_error||o_protocol_error||!CONFIG_LEGAL||(eligibility_observation&1'b0); // 严重错误不得静默忽略。
 always @(*) begin // 输入目的解码先做范围检查，再形成合法数组索引。
  input_queue_value={C_QUEUE_WIDTH{1'b0}};input_queue={C_QUEUE_WIDTH{1'b0}};decoded_port={C_PORT_INDEX_WIDTH{1'b0}};input_write_slot=0;input_legal=1'b0;input_phase_legal=1'b0;o_ready=1'b0; // 缺省fail-closed。
  if(({1'b0,i_dst_port}<C_PORT_LIMIT)&&({1'b0,i_class}<C_CLASS_LIMIT)&&({1'b0,i_original_vc}<C_VC_LIMIT)) begin // 三个显式编号均合法。
   decoded_port=i_dst_port[C_PORT_INDEX_WIDTH-1:0]; // 范围检查后截取恰好满足数组的索引宽度。
   input_queue_value=make_input_queue(decoded_port,i_class,i_original_vc); // Port/Class/VC展平队列号。
   input_queue=input_queue_value;input_write_slot=make_slot(input_queue_value,tail_q[input_queue_value]);input_legal=1'b1; // 合法索引才允许访问occupancy。
   if(!input_owner_q)input_phase_legal=i_sop; // 新包必须以SOP开始。
   else input_phase_legal=!i_sop&&(i_dst_port==input_port_q)&&(i_class==input_class_q)&&(i_original_vc==input_vc_q)&&(i_pool==input_pool_q)&&(input_queue==input_queue_q); // 包体不得换队列或属性。
   if(i_rstn&&CONFIG_LEGAL&&i_port_active[decoded_port]&&input_phase_legal&&(occupancy_q[input_queue]<C_DEPTH_COUNT))o_ready=1'b1; // 仅真实空槽可接纳。
  end // 结束合法目的解码。
  enqueue_fire=i_valid&&o_ready; // 输入所有权仅在valid-ready同时为真时转移。
 end // 结束输入准入组合逻辑。
 always @(*) begin // 每Port独立从自己的Class/VC集合做RR选择。
  selected_valid={C_NUM_PORTS{1'b0}};select_value={(C_SELECT_WIDTH+1){1'b0}};select_local={C_SELECT_WIDTH{1'b0}};candidate_queue={C_QUEUE_WIDTH{1'b0}};port_index=0;scan_index=0; // 缺省无输出候选且循环变量确定赋值。
  for(port_index=0;port_index<C_NUM_PORTS;port_index=port_index+1) begin // 每个Port拥有独立scheduler。
   selected_queue[port_index]={C_QUEUE_WIDTH{1'b0}};selected_local[port_index]={C_SELECT_WIDTH{1'b0}}; // 无候选时输出索引清零。
   if(output_owner_q[port_index]) begin // packet owner优先于新仲裁。
    selected_queue[port_index]=output_queue_q[port_index];selected_local[port_index]=output_local_q[port_index]; // 保持原逻辑队列和局部编号。
    selected_valid[port_index]=(occupancy_q[output_queue_q[port_index]]!=0); // 包体尚未到达时允许bubble。
   end else begin // 空闲Port扫描自己的Class/VC逻辑队列。
    for(scan_index=0;scan_index<C_PER_PORT_QUEUES;scan_index=scan_index+1) begin // 最多扫描全部本Port队列。
     select_value={1'b0,rr_q[port_index]}+scan_index[C_SELECT_WIDTH:0];if(select_value>=C_SELECT_LIMIT)select_value=select_value-C_SELECT_LIMIT;select_local=select_value[C_SELECT_WIDTH-1:0]; // 非二次幂配置单次回绕。
     candidate_queue=make_candidate_queue(port_index[C_PORT_INDEX_WIDTH-1:0],select_local); // 本Port局部编号转换为全局队列号。
     if(!selected_valid[port_index]&&(occupancy_q[candidate_queue]!=0)) begin selected_valid[port_index]=1'b1;selected_queue[port_index]=candidate_queue;selected_local[port_index]=select_local;end // 首个非空队列获胜。
    end // 完成本Port扫描。
   end // 结束owner或新仲裁分支。
  end // 完成全部Port调度。
 end // 结束scheduler组合逻辑。
 always @(*) begin // 从各队列head展示稳定预览；发送valid仍要求全部资格。
  o_head_valid={C_NUM_PORTS{1'b0}};o_valid={C_NUM_PORTS{1'b0}};o_data={(C_NUM_PORTS*C_DATA_WIDTH){1'b0}};o_meta={(C_NUM_PORTS*C_META_WIDTH){1'b0}}; // 无效输出明确清零。
  o_dst_port={(C_NUM_PORTS*C_PORT_WIDTH){1'b0}};o_class={(C_NUM_PORTS*C_CLASS_WIDTH){1'b0}};o_original_vc={(C_NUM_PORTS*C_VC_WIDTH){1'b0}}; // 无效路由字段清零。
  o_pool={C_NUM_PORTS{1'b0}};o_sop={C_NUM_PORTS{1'b0}};o_eop={C_NUM_PORTS{1'b0}};output_fire={C_NUM_PORTS{1'b0}};dequeue_queue={C_TOTAL_QUEUES{1'b0}}; // 边界及出队缺省清零。
  output_slot=0; // 动态存储地址缺省指向合法零号槽。
  for(read_port=0;read_port<C_NUM_PORTS;read_port=read_port+1) begin // 每Port独立并行读一个head。
   if(selected_valid[read_port]) begin // 只有非空队列允许读取SRAM模型。
    output_slot=make_slot(selected_queue[read_port],head_q[selected_queue[read_port]]); // 展平真实槽地址。
    o_data[read_port*C_DATA_WIDTH+:C_DATA_WIDTH]=data_mem[output_slot];o_meta[read_port*C_META_WIDTH+:C_META_WIDTH]=meta_mem[output_slot]; // 展示payload与opaque metadata。
    o_dst_port[read_port*C_PORT_WIDTH+:C_PORT_WIDTH]=port_mem[output_slot];o_class[read_port*C_CLASS_WIDTH+:C_CLASS_WIDTH]=class_mem[output_slot]; // 展示Port与class。
    o_original_vc[read_port*C_VC_WIDTH+:C_VC_WIDTH]=vc_mem[output_slot];o_pool[read_port]=pool_mem[output_slot];o_sop[read_port]=sop_mem[output_slot];o_eop[read_port]=eop_mem[output_slot]; // 展示VC、Pool及边界。
    // head preview不读取credit，打破“无valid→无demand→无credit”的组合死锁。
    o_head_valid[read_port]=i_rstn&&CONFIG_LEGAL;
    // 向协议adapter公开队首不依赖credit；adapter容量通过i_ready反压，真实Link发送再扣TL/UPLI账本。
    o_valid[read_port]=o_head_valid[read_port];
    output_fire[read_port]=o_valid[read_port]&&i_ready[read_port]; // 真实Port握手。
    if(output_fire[read_port])dequeue_queue[selected_queue[read_port]]=1'b1; // 同一队列只属于一个Port，故不会重复置位。
   end // 结束有效候选读取。
  end // 完成全部Port输出。
 end // 结束输出组合逻辑。
 always @(*) begin // 展平occupancy并计算全Tile empty。
  o_queue_occupancy={(C_TOTAL_QUEUES*C_COUNT_WIDTH){1'b0}};any_occupancy=1'b0; // 缺省全部空。
  for(queue_index=0;queue_index<C_TOTAL_QUEUES;queue_index=queue_index+1) begin o_queue_occupancy[queue_index*C_COUNT_WIDTH+:C_COUNT_WIDTH]=occupancy_q[queue_index];if(occupancy_q[queue_index]!=0)any_occupancy=1'b1;end // 每队列状态无遗漏导出。
 end // 结束occupancy观察逻辑。
 always @(posedge i_clk) begin // 输入包归属和sticky错误状态。
  if(!i_rstn) begin input_owner_q<=1'b0;input_queue_q<={C_QUEUE_WIDTH{1'b0}};input_port_q<={C_PORT_WIDTH{1'b0}};input_class_q<={C_CLASS_WIDTH{1'b0}};input_vc_q<={C_VC_WIDTH{1'b0}};input_pool_q<=1'b0;o_illegal_dst_error<=1'b0;o_inactive_dst_error<=1'b0;o_protocol_error<=1'b0;end // 复位清除所有瞬态所有权。
  else begin // 正常周期只接受明确事件。
   if(!CONFIG_LEGAL)o_protocol_error<=1'b1; // 非法参数配置永久fail-closed。
   if(i_valid&&!input_legal)o_illegal_dst_error<=1'b1; // 非法Port/Class/VC编码不握手。
   if(i_valid&&input_legal&&!i_port_active[decoded_port])o_inactive_dst_error<=1'b1; // inactive目的不进入任何队列。
   if(i_valid&&input_legal&&i_port_active[decoded_port]&&!input_phase_legal)o_protocol_error<=1'b1; // 包边界或中途换队列为协议错误。
   if(enqueue_fire) begin // 只有真实接纳才改变输入包owner。
    if(!input_owner_q) begin input_queue_q<=input_queue;input_port_q<=i_dst_port;input_class_q<=i_class;input_vc_q<=i_original_vc;input_pool_q<=i_pool;input_owner_q<=!i_eop;end // SOP建立快照，单拍包同沿结束。
    else if(i_eop)input_owner_q<=1'b0; // EOP真实接纳后释放输入owner。
   end // 结束输入握手处理。
  end // 结束正常状态更新。
 end // 结束输入及错误时序逻辑。
 always @(posedge i_clk) begin // 每Port输出packet owner与RR状态。
  if(!i_rstn) begin output_owner_q<={C_NUM_PORTS{1'b0}};for(reset_port=0;reset_port<C_NUM_PORTS;reset_port=reset_port+1)begin output_queue_q[reset_port]<={C_QUEUE_WIDTH{1'b0}};output_local_q[reset_port]<={C_SELECT_WIDTH{1'b0}};rr_q[reset_port]<={C_SELECT_WIDTH{1'b0}};end end // 复位取消所有输出候选。
  else for(reset_port=0;reset_port<C_NUM_PORTS;reset_port=reset_port+1) begin // 每Port独立推进owner。
   if(!output_owner_q[reset_port]&&o_head_valid[reset_port]&&!output_fire[reset_port])begin output_owner_q[reset_port]<=1'b1;output_queue_q[reset_port]<=selected_queue[reset_port];output_local_q[reset_port]<=selected_local[reset_port];end // 队首预览即锁定候选，credit查询期间字段稳定。
   if(output_fire[reset_port]) begin output_queue_q[reset_port]<=selected_queue[reset_port];output_local_q[reset_port]<=selected_local[reset_port];output_owner_q[reset_port]<=!o_eop[reset_port];if(o_eop[reset_port])begin if({1'b0,selected_local[reset_port]}==(C_SELECT_LIMIT-1'b1))rr_q[reset_port]<={C_SELECT_WIDTH{1'b0}};else rr_q[reset_port]<=selected_local[reset_port]+1'b1;end end // EOP握手后释放并轮转。
  end // 完成全部Port owner更新。
 end // 结束输出调度状态。
 always @(posedge i_clk) begin // FIFO存储、指针与occupancy守恒更新。
  if(!i_rstn) begin for(update_queue=0;update_queue<C_TOTAL_QUEUES;update_queue=update_queue+1)begin head_q[update_queue]<=0;tail_q[update_queue]<=0;occupancy_q[update_queue]<={C_COUNT_WIDTH{1'b0}};end end // 数据位不清零，valid由occupancy定义。
  else begin // 正常周期允许一个入队与多个不同Port出队并行。
   if(enqueue_fire) begin data_mem[input_write_slot]<=i_data;meta_mem[input_write_slot]<=i_meta;port_mem[input_write_slot]<=i_dst_port;class_mem[input_write_slot]<=i_class;vc_mem[input_write_slot]<=i_original_vc;pool_mem[input_write_slot]<=i_pool;sop_mem[input_write_slot]<=i_sop;eop_mem[input_write_slot]<=i_eop;end // 原子保存全部可见字段。
   for(update_queue=0;update_queue<C_TOTAL_QUEUES;update_queue=update_queue+1) begin // 各队列独立守恒更新。
    if(enqueue_fire&&(input_queue==update_queue[C_QUEUE_WIDTH-1:0]))begin if(tail_q[update_queue]==C_QUEUE_DEPTH-1)tail_q[update_queue]<=0;else tail_q[update_queue]<=tail_q[update_queue]+1;end // tail按深度回绕。
    if(dequeue_queue[update_queue])begin if(head_q[update_queue]==C_QUEUE_DEPTH-1)head_q[update_queue]<=0;else head_q[update_queue]<=head_q[update_queue]+1;end // head只在真实发送时推进。
    case({enqueue_fire&&(input_queue==update_queue[C_QUEUE_WIDTH-1:0]),dequeue_queue[update_queue]})2'b10:occupancy_q[update_queue]<=occupancy_q[update_queue]+1'b1;2'b01:occupancy_q[update_queue]<=occupancy_q[update_queue]-1'b1;default:occupancy_q[update_queue]<=occupancy_q[update_queue];endcase // 同时入出保持数量不变。
   end // 完成全部队列更新。
  end // 结束正常FIFO状态更新。
 end // 结束FIFO时序逻辑。
endmodule // 结束Destination Tile逐Port出口切片。
`default_nettype wire // 恢复后续编译单元默认网络规则。
