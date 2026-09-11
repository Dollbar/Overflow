module tl_content( // 已分类完整Flit的内容与Beat配对检查
 input wire i_clk,i_rstn,i_commit, // 唯一时钟、同步低复位、实际接收事件
 input wire [255:0] i_lower,i_upper, // 完整两半线上内容
 input wire [2:0] i_class0,i_class1, // 上游已验证分类，编码同tl_sequence
 input wire [3:0] i_tags, // 本Control请求响应总数
 output wire o_allowed,o_taken,o_rejected, // 内容级握手，尚未组合预算
 output reg o_fatal,o_open,o_poison // 锁存接收错误与当前Beat状态
); // 不执行认证算法或完整Message解析
reg bad,n_open,n_poison; // 整拍提议
reg [2:0] kind; // 当前逻辑类别
reg [255:0] word; // 当前半内容
integer half; // 静态展开两半
assign o_allowed=i_rstn&&!o_fatal&&!bad; // 错误后停止允许转发
assign o_taken=i_commit&&o_allowed; // 唯一内容通过事件
assign o_rejected=i_rstn&&i_commit&&!o_allowed; // 拒绝观察
always @* begin // 原子检查两半
 bad=1'b0;n_open=o_open;n_poison=o_poison;kind=3'd7;word=256'd0; // 完整初值
 for(half=0;half<2;half=half+1) begin // 按消费顺序检查配对
  kind=(half==0)?i_class0:i_class1;word=(half==0)?i_lower:i_upper; // 当前物理半
  if((kind==3'd3)&&(word!=256'd0)) bad=1'b1; // Mandatory NOP必须全零
  if(kind==3'd6) begin // 未使用认证槽清零
   case(i_tags) // 使用槽从低64位开始
    4'd1:if(word[255:64]!=192'd0)bad=1'b1; // 一槽
    4'd2:if(word[255:128]!=128'd0)bad=1'b1; // 两槽
    4'd3:if(word[255:192]!=64'd0)bad=1'b1; // 三槽
    4'd4:begin end // 四槽均使用
    default:bad=1'b1; // AuthTags仅允许一至四槽
   endcase // 认证填充检查结束
  end // AuthTags结束
  if((kind==3'd1)||(kind==3'd5)) begin // 仅Data或Poison消费数据半Beat
   if(n_open) begin // 第二半必须与第一半Poison状态一致
    if(n_poison!=(kind==3'd5))bad=1'b1; // 配对不一致
    n_open=1'b0;n_poison=1'b0; // 完成Beat并清除历史标志
   end else begin n_open=1'b1;n_poison=(kind==3'd5);end // 第一半
  end else if((kind==3'd2)&&n_open)bad=1'b1; // BE不得打断64字节Beat
 end // 两半结束，Message及Control不消费配对状态
end // 组合检查结束
always @(posedge i_clk) begin // 唯一状态更新
 if(!i_rstn)begin o_fatal<=1'b0;o_open<=1'b0;o_poison<=1'b0;end // 复位清除错误
 else begin // 拒绝整拍不更新配对状态
  if(i_commit&&bad)o_fatal<=1'b1; // 接收错误锁存至复位
  if(o_taken)begin o_open<=n_open;o_poison<=n_poison;end // 合法完整Flit提交
 end // 非复位结束
end // 时序检查结束
endmodule // 内容监视器结束
