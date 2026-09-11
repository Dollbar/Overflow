`timescale 1ns/1ps // 本地同钟原子路由配置服务的数字时间单位。
`default_nettype none // 禁止隐式网络隐藏管理接口连接错误。
module switch_route_table #( // 独立候选：不是标准CSR地址图，也不自行判断fabric是否排空。
 parameter integer PORTS=4, // 对称目的端口数，当前验证一至五端口。
 parameter integer INDEX_WIDTH=(PORTS<=2)?1:(PORTS<=4)?2:(PORTS<=8)?3:(PORTS<=16)?4:(PORTS<=32)?5:(PORTS<=64)?6:(PORTS<=128)?7:(PORTS<=256)?8:(PORTS<=512)?9:10 // 默认避免单端口零宽度，允许显式加宽索引。
)( // 开始明确的本地shadow写入与提交接口。
 input wire i_clk, // 所有管理状态共用上升沿时钟。
 input wire i_rstn, // 同步低有效复位在时钟沿清空两份表。
 input wire i_write_valid, // 本沿请求更新一个shadow entry。
 input wire [INDEX_WIDTH-1:0] i_write_index, // 自然端口编号，未使用编码必须拒绝。
 input wire [9:0] i_write_route_id, // 完整十位逻辑目标ID。
 input wire i_write_enable, // 该shadow entry是否参与目标匹配。
 input wire i_commit, // 显式请求原子发布当前完整shadow表。
 input wire i_quiescent, // 外部保证停止接纳并排空在途所有权，本模块信任该保证。
 output wire o_write_accepted, // 本沿实际接纳shadow写入的组合确认。
 output wire o_commit_accepted, // 本沿实际提交整个active表的组合确认。
 output wire [PORTS*10-1:0] o_route_ids, // port*10低位起点的active十位目标表。
 output wire [PORTS-1:0] o_port_enable, // 与现有lookup直接兼容的active使能位。
 output wire o_pending, // shadow与active任何保存bit不同，包含disabled entry的ID。
 output wire o_error // 有效非法事件组合诊断，不粘滞，不是线上错误码。
); // 结束候选管理接口。
 localparam TABLE_ENTRIES=PORTS; // 共用编译期固定条目总数作为组合扫描与存储生成界限。
 localparam CONFIG_LEGAL=(PORTS>=1)&&(PORTS<=1024)&&(INDEX_WIDTH>=1)&&(INDEX_WIDTH<=10)&&((1<<INDEX_WIDTH)>=PORTS); // 不允许截断端口编号或超出配置表示范围。
 localparam [INDEX_WIDTH:0] PORT_LIMIT=PORTS[INDEX_WIDTH:0]; // 多一位比较精确表示二次幂端口总数。
 reg [PORTS*10-1:0] shadow_ids_q,active_ids_q; // 保存候选配置及当前已发布配置，写入不穿透到active。
 reg [PORTS-1:0] shadow_enable_q,active_enable_q; // 两份表的使能与ID同时原子维护。
 reg shadow_duplicate; // 当前shadow表存在重复enabled目标时禁止提交。
 wire active,index_legal; // 分离有效本地配置和候选索引检查。
 integer left_port,right_port; // 有界组合扫描全部真实端口对。
 assign active=i_rstn&&CONFIG_LEGAL; // 复位或非法参数封锁所有接纳事件。
 assign index_legal={1'b0,i_write_index}<PORT_LIMIT; // 未用高编码不会别名写入已有端口。
 always @(*) begin // duplicate只描述当前shadow内容，不对正常分步编辑报错。
  shadow_duplicate=1'b0; // 默认候选enabled目的唯一。
  for(left_port=32'd0;left_port<TABLE_ENTRIES;left_port=left_port+32'd1)begin // 固定端口范围可静态展开。
   for(right_port=32'd0;right_port<TABLE_ENTRIES;right_port=right_port+32'd1)begin // 使用固定界限避免依赖动态循环起点。
    if((left_port<right_port)&&shadow_enable_q[left_port]&&shadow_enable_q[right_port]&&(shadow_ids_q[left_port*10+:10]==shadow_ids_q[right_port*10+:10]))begin // 仅两个enabled entry的完整ID相等才冲突。
     shadow_duplicate=1'b1; // disabled重复项仍可合法提交。
    end // 结束当前端口对唯一性检查。
   end // 结束全部右侧候选比较。
  end // 结束全部真实端口对检查。
 end // 完整组合默认覆盖，无锁存器。
 assign o_write_accepted=active&&i_write_valid&&!i_commit&&index_legal; // 同拍write和commit双拒绝，不推断先后顺序。
 assign o_commit_accepted=active&&i_commit&&!i_write_valid&&i_quiescent&&!shadow_duplicate; // 必须由外部明确保证quiescent且整个候选表合法。
 assign o_route_ids=active_ids_q; // 外部只能看到上次原子提交的完整ID表。
 assign o_port_enable=active_enable_q; // 使能与ID在同一提交沿切换。
 assign o_pending=(shadow_ids_q!=active_ids_q)||(shadow_enable_q!=active_enable_q); // 相同值写入不制造虚假pending，写回原值可清除pending。
 assign o_error=i_rstn&&(!CONFIG_LEGAL||(i_write_valid&&i_commit)||(i_write_valid&&!index_legal)||(i_commit&&(!i_quiescent||shadow_duplicate))); // busy、重复、非法索引和并发命令只诊断，不修改被拒绝状态。
 always @(posedge i_clk)begin // 所有可见变化仅在真实管理事件的时钟沿发生。
  if(!active)begin // 同步复位清空shadow与active，所有目的关闭。
   active_ids_q<={(PORTS*10){1'b0}}; // 清除已发布ID。
   active_enable_q<={PORTS{1'b0}}; // 已发布表全disabled。
  end else begin // 正常管理周期仅响应已明确接纳的命令。
   if(o_commit_accepted)begin // 将全部端口表在同一沿原子发布。
    active_ids_q<=shadow_ids_q; // shadow内容保留供后续增量编辑。
    active_enable_q<=shadow_enable_q; // disabled重复值也按原样保存。
   end // 被拒绝提交保持active及shadow不变。
  end // 结束同步复位与正常管理分支。
 end // 结束两份配置表的真实存储过程。
 genvar entry; // 固定真实端口索引支持外部索引加宽而不截断非法值。
 generate for(entry=32'd0;entry<TABLE_ENTRIES;entry=entry+32'd1)begin:shadow_entry // 每个entry使用独立固定索引寄存器。
  localparam [INDEX_WIDTH-1:0] ENTRY_INDEX=entry[INDEX_WIDTH-1:0]; // 保留完整候选索引宽度进行相等比较。
  always @(posedge i_clk)begin // 与active表共用同一同步域。
   if(!active)begin // 同步清除每个shadow entry。
    shadow_ids_q[entry*10+:10]<=10'd0; // 复位未发布ID。
    shadow_enable_q[entry]<=1'b0; // 复位未发布使能。
   end else if(o_write_accepted&&i_write_index==ENTRY_INDEX)begin // 仅完整索引匹配的真实entry接纳写入。
    shadow_ids_q[entry*10+:10]<=i_write_route_id; // 保留完整十位ID，不使用截断索引选择。
    shadow_enable_q[entry]<=i_write_enable; // ID和使能原子保存。
   end // 被拒绝写入以及其他entry写入均保持本entry。
  end // 结束当前真实entry同步更新。
 end endgenerate // 结束全部固定entry生成。
endmodule // 结束本地原子配置候选，主线负责安全quiescence判定。
`default_nettype wire // 恢复外围编译默认规则。
