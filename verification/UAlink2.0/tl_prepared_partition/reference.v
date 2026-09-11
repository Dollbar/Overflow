module tl_prepared_reference #(parameter WIDTH=16)( // 验证参考模块：独立持有原始字段并使用固定基线分组器
 input wire i_clk,i_rstn,i_source_valid,i_ready,i_done,i_response,i_auth,i_shared, // 与候选完全相同的实时输入
 input wire [255:0] i_source_control,input wire [511:0] i_source_tags, // 原始字段和按字段排序的认证标签
 input wire [20*(WIDTH+1)-1:0] i_capacity, // 本次初始化时期的物理总容量
 output wire o_source_ready,o_captured,o_valid,o_taken,o_group_done,o_error,o_shortfall, // 独立参考所有权与下游握手
 output wire [255:0] o_control,o_tags,output wire [3:0] o_fields,o_end,o_cursor // 十二个输出完整参与比较
); // 结束参考接口
reg held_valid,held_response,held_auth,held_shared; // 参考自行捕获类别和初始化属性
reg [255:0] held_control;reg [511:0] held_tags;reg [20*(WIDTH+1)-1:0] held_capacity; // 保存原始字段，不保存或复用候选元数据
assign o_source_ready=i_rstn&&i_done&&(!held_valid||o_group_done); // 参考只依据自己的整组退休释放槽位
assign o_captured=i_source_valid&&o_source_ready; // 捕获事件独立于候选所有权
tl_control_partition #(.WIDTH(WIDTH)) Raw_Reference_Inst( // 基线RTL每拍重新解释原始字段，拥有独立游标
 .i_clk(i_clk),.i_rstn(i_rstn),.i_source_valid(held_valid),.i_ready(i_ready),.i_done(1'b1), // 已捕获组不再依赖实时done
 .i_response(held_response),.i_auth(held_auth),.i_shared(held_shared), // 初始化快照持续到整个源组退休
 .i_source_control(held_control),.i_source_tags(held_tags),.i_capacity(held_capacity), // 同一输入握手保存的原始内容
 .o_valid(o_valid),.o_taken(o_taken),.o_source_taken(o_group_done),.o_error(o_error),.o_shortfall(o_shortfall), // 参考实际分组及最后入队确认
 .o_control(o_control),.o_tags(o_tags),.o_fields(o_fields),.o_end(o_end),.o_cursor(o_cursor) // 完整负载及进度观察
); // 结束原始字段参考实例
always @(posedge i_clk)begin // 参考与候选使用同一上升沿，但没有共享状态控制
 if(!i_rstn)held_valid<=1'b0; // 同步复位只取消所有权，基线实例同步取消游标
 else begin // 捕获后输入可立即改变
  if(o_source_ready)held_valid<=i_source_valid;else if(o_group_done)held_valid<=1'b0; // 支持最后分组与下一组捕获同拍发生
  if(o_captured)begin // 原始字段和属性按同一接纳事件形成快照
   held_control<=i_source_control;held_tags<=i_source_tags;held_capacity<=i_capacity; // 不从候选提取字段或费用
   held_response<=i_response;held_auth<=i_auth;held_shared<=i_shared; // 错误判定由基线在持有数据上重新计算
  end // 结束原始输入捕获
 end // 结束非复位更新
end // 结束独立参考寄存器
endmodule // 结束tl_prepared_reference验证模块
