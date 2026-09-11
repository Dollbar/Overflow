`timescale 1ns/1ps // 上下文与已冻结Request bridge共享同一采样时钟。
`default_nettype none // 防止网络身份或本地token位宽漏接。
module upli_endpoint_request_context #( // 模块保存完整请求上下文，网络Tag不重新分配。
parameter integer CAPACITY=4, // 本地容量或索引宽度，不增加原生线字段。
parameter integer C_NUM_PORTS=1, // 本地容量或索引宽度，不增加原生线字段。
parameter integer C_STATION_WIDTH=8, // 本地容量或索引宽度，不增加原生线字段。
parameter integer C_GENERATION_WIDTH=8, // 本地容量或索引宽度，不增加原生线字段。
parameter integer C_SLOT_WIDTH=(CAPACITY<=2)?1:(CAPACITY<=4)?2:(CAPACITY<=8)?3:4, // 本地容量或索引宽度，不增加原生线字段。
parameter integer C_COUNT_WIDTH=(CAPACITY<=1)?1:(CAPACITY<=3)?2:(CAPACITY<=7)?3:(CAPACITY<=15)?4:5 // 本地容量或索引宽度，不增加原生线字段。
)( // 接纳、交付和最终释放是三个不同的所有权事件。
input wire  i_clk, // 共同reset、本地容量或显式所有权完成资格。
input wire  i_rstn, // 共同reset、本地容量或显式所有权完成资格。
input wire  i_request_valid, // 完整原始descriptor字段保持到外部最终释放。
input wire  i_issue_ready, // 完整原始descriptor字段保持到外部最终释放。
input wire  i_release_valid, // 共同reset、本地容量或显式所有权完成资格。
input wire [C_STATION_WIDTH-1:0] i_request_station, // 完整原始descriptor字段保持到外部最终释放。
input wire [2-1:0] i_request_port, // 完整原始descriptor字段保持到外部最终释放。
input wire [2-1:0] i_request_vc, // 完整原始descriptor字段保持到外部最终释放。
input wire  i_request_pool, // 完整原始descriptor字段保持到外部最终释放。
input wire [184-1:0] i_request_payload, // 完整原始descriptor字段保持到外部最终释放。
input wire [2048-1:0] i_request_data, // 完整原始descriptor字段保持到外部最终释放。
input wire [256-1:0] i_request_be, // 完整原始descriptor字段保持到外部最终释放。
input wire [4-1:0] i_request_poison, // 完整原始descriptor字段保持到外部最终释放。
input wire [4-1:0] i_request_data_pools, // 完整原始descriptor字段保持到外部最终释放。
input wire [C_SLOT_WIDTH+C_GENERATION_WIDTH-1:0] i_release_token, // 共同reset、本地容量或显式所有权完成资格。
output wire  o_request_ready, // 完整原始descriptor字段保持到外部最终释放。
output wire  o_issue_valid, // 完整原始descriptor字段保持到外部最终释放。
output wire  o_release_ready, // 共同reset、本地容量或显式所有权完成资格。
output wire  o_error, // 共同reset、本地容量或显式所有权完成资格。
output wire [C_SLOT_WIDTH+C_GENERATION_WIDTH-1:0] o_request_token, // 完整原始descriptor字段保持到外部最终释放。
output wire [C_SLOT_WIDTH+C_GENERATION_WIDTH-1:0] o_issue_token, // 完整原始descriptor字段保持到外部最终释放。
output wire [C_STATION_WIDTH-1:0] o_issue_station, // 完整原始descriptor字段保持到外部最终释放。
output wire [2-1:0] o_issue_port, // 完整原始descriptor字段保持到外部最终释放。
output wire [2-1:0] o_issue_vc, // 完整原始descriptor字段保持到外部最终释放。
output wire  o_issue_pool, // 完整原始descriptor字段保持到外部最终释放。
output wire [184-1:0] o_issue_payload, // 完整原始descriptor字段保持到外部最终释放。
output wire [2048-1:0] o_issue_data, // 完整原始descriptor字段保持到外部最终释放。
output wire [256-1:0] o_issue_be, // 完整原始descriptor字段保持到外部最终释放。
output wire [4-1:0] o_issue_poison, // 完整原始descriptor字段保持到外部最终释放。
output wire [4-1:0] o_issue_data_pools, // 完整原始descriptor字段保持到外部最终释放。
output wire [C_COUNT_WIDTH-1:0] o_count // 共同reset、本地容量或显式所有权完成资格。
); // 结束单一请求上下文表接口。
localparam [31:0] C_CAPACITY_LIMIT=CAPACITY; // 固定容量界限用于组合搜索。
localparam [31:0] C_PORT_LIMIT=C_NUM_PORTS; // 完整两位端口与实际配置比较。
localparam [31:0] C_LAST_INTEGER=CAPACITY-1; // 显式裁剪本地循环指针的合法末项。
localparam [C_SLOT_WIDTH-1:0] C_LAST=C_LAST_INTEGER[C_SLOT_WIDTH-1:0]; // 非二次幂容量也在真实末项环回。
reg [CAPACITY-1:0] r_active,r_issued; // 已预约与已交付状态分别保存，不用issue释放Tag。
reg [C_GENERATION_WIDTH-1:0] r_generation[0:CAPACITY-1]; // 有限本地代次，不能作为无限epoch保证。
reg [C_SLOT_WIDTH-1:0] pending_slots[0:CAPACITY-1]; // FIFO只保存表项索引，不复制全部payload。
reg [C_SLOT_WIDTH-1:0] read_ptr,write_ptr; // 实际接纳顺序的头尾指针。
reg [C_COUNT_WIDTH-1:0] r_count,r_pending_count; // 活跃总数包括已issue，队列只计待issue。
reg [C_STATION_WIDTH-1:0] r_station[0:CAPACITY-1]; // 完整保存station，不借用后来输入。
reg [2-1:0] r_port[0:CAPACITY-1]; // 完整保存port，不借用后来输入。
reg [2-1:0] r_vc[0:CAPACITY-1]; // 完整保存vc，不借用后来输入。
reg r_pool[0:CAPACITY-1]; // 完整保存pool，不借用后来输入。
reg [184-1:0] r_payload[0:CAPACITY-1]; // 完整保存payload，不借用后来输入。
reg [2048-1:0] r_data[0:CAPACITY-1]; // 完整保存data，不借用后来输入。
reg [256-1:0] r_be[0:CAPACITY-1]; // 完整保存be，不借用后来输入。
reg [4-1:0] r_poison[0:CAPACITY-1]; // 完整保存poison，不借用后来输入。
reg [4-1:0] r_data_pools[0:CAPACITY-1]; // 完整保存data_pools，不借用后来输入。
reg free_found,duplicate; // 满表背压和真实重复身份错误分离。
reg [C_SLOT_WIDTH-1:0] free_slot; // 仅指向沿前已经空闲的槽，不能借同拍release。
wire [C_SLOT_WIDTH-1:0] issue_slot,release_slot; // 两个事件各自定位其实际所有者。
wire [C_GENERATION_WIDTH-1:0] next_generation,release_generation; // 本地代次不写入网络Request字段。
wire [183:0] issue_payload; // 完整网络字段透明输出，用于独立字段对照。
wire request_bad,release_legal,allocate_fire,issue_fire,release_fire; // 三种握手只更新各自责任。
integer scan,reset_index; // 常量有界组合搜索及共同reset遍历。
always @* begin // 对当前活跃表项检查完整本地Source Accelerator身份域。
 free_found=1'b0;duplicate=1'b0;free_slot={C_SLOT_WIDTH{1'b0}}; // 所有组合路径有确定默认。
 for(scan=32'd0;scan<C_CAPACITY_LIMIT;scan=scan+32'd1)begin // 原Tag全部十一位参与查重。
  if(!r_active[scan] && !free_found)begin free_found=1'b1;free_slot=scan[C_SLOT_WIDTH-1:0];end // 保守选择最小空闲槽。
  if(r_active[scan] && (r_station[scan]==i_request_station) && (r_port[scan]==i_request_port) && (r_payload[scan][97:87]==i_request_payload[97:87]))duplicate=1'b1; // VC/pool/命令/Src不能扩大本地共享Tag域。
 end // 结束唯一上下文表搜索。
end // 结束完整组合默认与固定边界扫描。
assign request_bad=duplicate || ({30'd0,i_request_port}>=C_PORT_LIMIT); // 满容量不属于非法有效事件。
assign o_request_ready=i_rstn && free_found && !request_bad; // 只有实际空表项才能接纳完整descriptor。
assign next_generation=r_generation[free_slot]+{{(C_GENERATION_WIDTH-1){1'b0}},1'b1}; // 模运算代次只辅助拒绝旧token。
assign o_request_token=(i_request_valid && o_request_ready)?{next_generation,free_slot}:{(C_SLOT_WIDTH+C_GENERATION_WIDTH){1'b0}}; // 接纳沿公开对应本地token。
assign allocate_fire=i_request_valid && o_request_ready; // 此沿才取得完整请求上下文所有权。
assign issue_slot=pending_slots[read_ptr]; // 输出次序来自实际接纳FIFO，不由空槽优先级重新仲裁。
assign o_issue_valid=i_rstn && (r_pending_count!={C_COUNT_WIDTH{1'b0}}); // 待交付队列非空才公开有效上下文。
assign o_issue_token=o_issue_valid?{r_generation[issue_slot],issue_slot}:{(C_SLOT_WIDTH+C_GENERATION_WIDTH){1'b0}}; // token独立于原Tag，不覆盖任何线上身份。
assign issue_payload=o_issue_valid?r_payload[issue_slot]:184'd0; // 不按几何、状态或授权修改保存的原始请求。
assign o_issue_payload = issue_payload; // 独立保持原Tag、Src/Dst、Auth、地址及几何字段。
assign o_issue_station=o_issue_valid?r_station[issue_slot]:{C_STATION_WIDTH{1'b0}}; // 完整字段随同一有效上下文保持，idle确定归零。
assign o_issue_port=o_issue_valid?r_port[issue_slot]:{2{1'b0}}; // 完整字段随同一有效上下文保持，idle确定归零。
assign o_issue_vc=o_issue_valid?r_vc[issue_slot]:{2{1'b0}}; // 完整字段随同一有效上下文保持，idle确定归零。
assign o_issue_pool=o_issue_valid?r_pool[issue_slot]:{1{1'b0}}; // 完整字段随同一有效上下文保持，idle确定归零。
assign o_issue_data=o_issue_valid?r_data[issue_slot]:{2048{1'b0}}; // 完整字段随同一有效上下文保持，idle确定归零。
assign o_issue_be=o_issue_valid?r_be[issue_slot]:{256{1'b0}}; // 完整字段随同一有效上下文保持，idle确定归零。
assign o_issue_poison=o_issue_valid?r_poison[issue_slot]:{4{1'b0}}; // 完整字段随同一有效上下文保持，idle确定归零。
assign o_issue_data_pools=o_issue_valid?r_data_pools[issue_slot]:{4{1'b0}}; // 完整字段随同一有效上下文保持，idle确定归零。
assign issue_fire=o_issue_valid && i_issue_ready; // 下游真正接纳只标issued，不释放活动容量。
assign release_slot=i_release_token[C_SLOT_WIDTH-1:0]; // 只按本地槽索引寻址，不从网络Tag暗取槽号。
assign release_generation=i_release_token[C_SLOT_WIDTH+C_GENERATION_WIDTH-1:C_SLOT_WIDTH]; // 独立核对当前槽代次。
assign release_legal=({{(32-C_SLOT_WIDTH){1'b0}},release_slot}<C_CAPACITY_LIMIT) && r_active[release_slot] && r_issued[release_slot] && (r_generation[release_slot]==release_generation); // 未交付、未知槽和旧代次都不得释放。
assign o_release_ready=i_rstn && release_legal; // 不借同拍issue预判该槽已经交付。
assign release_fire=i_release_valid && o_release_ready; // 仅外部合法最终所有权完成才释放容量。
assign o_error=i_rstn && ((i_request_valid && request_bad) || (i_release_valid && !release_legal)); // 正常满表与下游背压不报错。
assign o_count=i_rstn?r_count:{C_COUNT_WIDTH{1'b0}}; // 包括待issue与已issue但尚未release的全部上下文。
always @(posedge i_clk)begin // 唯一上下文状态只在真实所有权沿改变。
 if(!i_rstn)begin // 共同同步reset取消全部旧epoch上下文。
  r_active<={CAPACITY{1'b0}};r_issued<={CAPACITY{1'b0}}; // 新epoch不含旧预约或交付承诺。
  read_ptr<={C_SLOT_WIDTH{1'b0}};write_ptr<={C_SLOT_WIDTH{1'b0}}; // 重新从空索引队列开始。
  r_count<={C_COUNT_WIDTH{1'b0}};r_pending_count<={C_COUNT_WIDTH{1'b0}}; // 总容量与未交付数独立归零。
  for(reset_index=32'd0;reset_index<C_CAPACITY_LIMIT;reset_index=reset_index+32'd1)begin // 固定容量全部初始化，无残留身份可见。
   r_generation[reset_index]<={C_GENERATION_WIDTH{1'b0}};pending_slots[reset_index]<={C_SLOT_WIDTH{1'b0}}; // reset不是可独立于对端完成的新epoch协议。
   r_station[reset_index]<= {C_STATION_WIDTH{1'b0}}; // 取消旧station及未提交信息。
   r_port[reset_index]<= {2{1'b0}}; // 取消旧port及未提交信息。
   r_vc[reset_index]<= {2{1'b0}}; // 取消旧vc及未提交信息。
   r_pool[reset_index]<= {1{1'b0}}; // 取消旧pool及未提交信息。
   r_payload[reset_index]<= {184{1'b0}}; // 取消旧payload及未提交信息。
   r_data[reset_index]<= {2048{1'b0}}; // 取消旧data及未提交信息。
   r_be[reset_index]<= {256{1'b0}}; // 取消旧be及未提交信息。
   r_poison[reset_index]<= {4{1'b0}}; // 取消旧poison及未提交信息。
   r_data_pools[reset_index]<= {4{1'b0}}; // 取消旧data_pools及未提交信息。
  end // 结束共同reset的全部槽处理。
 end else begin // 没有对应事件的状态保持不变。
  case({allocate_fire,release_fire}) // 总占用只取接纳与最终释放的净变化。
   2'b10:r_count<=r_count+{{(C_COUNT_WIDTH-1){1'b0}},1'b1}; // 新上下文占用一个槽。
   2'b01:r_count<=r_count-{{(C_COUNT_WIDTH-1){1'b0}},1'b1}; // 最终release归还一个槽。
   default:r_count<=r_count; // 同时发生时总占用不变。
  endcase // 结束活动表项计数。
  case({allocate_fire,issue_fire}) // 只把未交付索引保存在pending队列。
   2'b10:r_pending_count<=r_pending_count+{{(C_COUNT_WIDTH-1){1'b0}},1'b1}; // 接纳追加待交付项。
   2'b01:r_pending_count<=r_pending_count-{{(C_COUNT_WIDTH-1){1'b0}},1'b1}; // issue移除队头索引。
   default:r_pending_count<=r_pending_count; // 同沿出入不破坏队列数量。
  endcase // 结束待交付计数。
  if(allocate_fire)begin // 原子保存完整最大descriptor，之后不依赖输入保持。
   r_active[free_slot]<=1'b1;r_issued[free_slot]<=1'b0;r_generation[free_slot]<=next_generation; // 本地token与保存数据在同一沿建立。
   pending_slots[write_ptr]<=free_slot; // 追加真实接纳顺序，而不是之后按槽号选择。
   if(write_ptr==C_LAST)write_ptr<={C_SLOT_WIDTH{1'b0}};else write_ptr<=write_ptr+{{(C_SLOT_WIDTH-1){1'b0}},1'b1}; // 任意合法容量循环索引。
   r_station[free_slot]<=i_request_station; // 完整station由此实际接纳沿拥有。
   r_port[free_slot]<=i_request_port; // 完整port由此实际接纳沿拥有。
   r_vc[free_slot]<=i_request_vc; // 完整vc由此实际接纳沿拥有。
   r_pool[free_slot]<=i_request_pool; // 完整pool由此实际接纳沿拥有。
   r_payload[free_slot]<=i_request_payload; // 完整payload由此实际接纳沿拥有。
   r_data[free_slot]<=i_request_data; // 完整data由此实际接纳沿拥有。
   r_be[free_slot]<=i_request_be; // 完整be由此实际接纳沿拥有。
   r_poison[free_slot]<=i_request_poison; // 完整poison由此实际接纳沿拥有。
   r_data_pools[free_slot]<=i_request_data_pools; // 完整data_pools由此实际接纳沿拥有。
  end // 结束完整表项保存。
  if(issue_fire)r_issued[issue_slot]<=1'b1; // issue不会清除active、原Tag或结果关联容量。
  if(issue_fire)begin // 只有下游真正接受才推进索引队头。
   if(read_ptr==C_LAST)read_ptr<={C_SLOT_WIDTH{1'b0}};else read_ptr<=read_ptr+{{(C_SLOT_WIDTH-1){1'b0}},1'b1}; // 背压期间指针和全部输出稳定。
  end // 结束有序交付索引推进。
  if(release_fire)begin r_active[release_slot]<=1'b0;r_issued[release_slot]<=1'b0;end // 保留代次供下次分配递增，其它槽不受影响。
 end // 结束共同reset和正常所有权更新分支。
end // 结束唯一上下文表时序过程。
generate if((CAPACITY<1)||(CAPACITY>16)||((C_NUM_PORTS!=1)&&(C_NUM_PORTS!=2)&&(C_NUM_PORTS!=4))||(C_STATION_WIDTH<1)||(C_STATION_WIDTH>32)||(C_GENERATION_WIDTH<1)||(C_GENERATION_WIDTH>16)|| // 有界本地资源，不扩展原生字段。
 (C_SLOT_WIDTH!=((CAPACITY<=2)?1:(CAPACITY<=4)?2:(CAPACITY<=8)?3:4))|| // 不允许覆盖派生索引宽度造成静默别名。
 (C_COUNT_WIDTH!=((CAPACITY<=1)?1:(CAPACITY<=3)?2:(CAPACITY<=7)?3:(CAPACITY<=15)?4:5)))begin:gen_invalid // 总数必须能表示实际容量。
 upli_endpoint_request_context_parameters_invalid u_invalid(); // 不合法参数在elaboration明确拒绝。
end endgenerate // 结束配置保护。
endmodule // 结束只保存上下文和交付所有权的模块，未实现backend或网络Tag再分配。
`default_nettype wire // 恢复外部编译单元默认网络。
