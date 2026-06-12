module tl_receive_obligation_tracker #(parameter integer WIDTH=12)( // tl_receive_obligation_tracker模块：实际存储字释放责任聚合，单时钟、无新的消费资格。
 input wire i_clk,i_rstn,i_store,i_retire, // 只能接实际FIFO写入和实际旧字退休。
 input wire [79:0] i_stored_releases,i_retired_releases, // 完整原始账户描述符，不按payload拍数推测。
 output wire [20*WIDTH-1:0] o_pending,output wire o_error // 观察责任和故障，不生成恢复ACK。
); // 接口结束。
reg [20*WIDTH-1:0] pending_q;reg fault_q; // 新维护的聚合账本，非重新遍历SRAM证明。
wire [19:0] invalid_delta;wire [20*WIDTH-1:0] next_pending; // 每账户独立有界净变化。
assign o_pending=pending_q; // 公开当前沿前真实维护状态。
assign o_error=i_rstn&&(fault_q||(|invalid_delta)); // 同沿诊断并在后续保持到共同复位。
genvar slot;generate // 固定20个原始类和Pool/VC账户。
 if((WIDTH<1)||(WIDTH>24))begin:gen_invalid_width // 拒绝无法表示或无意义的计数宽度。
  tl_receive_obligation_width_invalid Invalid_Inst(); // 非法展开不可伪装成零责任。
 end // 参数检查结束。
 for(slot=0;slot<20;slot=slot+1)begin:gen_slot // 各槽并行计算，没有跨账户抵扣。
  wire [WIDTH+4:0] added,removed,next_total; // 同沿先组成全宽代数净变化，足够容纳四位原描述符。
  assign added={5'd0,pending_q[slot*WIDTH+:WIDTH]}+{{(WIDTH+1){1'b0}},(i_store?i_stored_releases[slot*4+:4]:4'd0)}; // 不在单独加法阶段错误拒绝满账户的同时退休。
  assign removed={{(WIDTH+1){1'b0}},(i_retire?i_retired_releases[slot*4+:4]:4'd0)}; // 未实际退休不能减少任何责任。
  assign next_total=added-removed; // 存入和退休分别恰好一次，允许零账户同沿相抵。
  assign invalid_delta[slot]=(added<removed)||(|next_total[WIDTH+4:WIDTH]); // 无下溢、无截断回绕，检查的是完整净结果。
  assign next_pending[slot*WIDTH+:WIDTH]=next_total[WIDTH-1:0]; // 仅完整资格通过后保存。
 end // 每槽展开结束。
endgenerate // 结束generate有界账户计算。
always @(posedge i_clk)begin // 只有共同真实时钟推进观察账本。
 if(!i_rstn)begin pending_q<={(20*WIDTH){1'b0}};fault_q<=1'b0;end // 同步复位，仅整体所有者生命周期可重建。
 else if(o_error)fault_q<=1'b1; // 错误后保留最后可信状态，不据此允许恢复。
 else pending_q<=next_pending; // 与两个实际FIFO事件同沿维护。
end // 计数与错误状态结束。
endmodule // 结束实际存储字释放责任聚合器。
