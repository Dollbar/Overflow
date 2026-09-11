module tl_packing_budget ( // Common2.0第5.7节逻辑TL Flit打包预算
    input wire i_clk, // 唯一输入时钟
    input wire i_rstn, // 同步低有效复位
    input wire i_flit_commit, // 调用方申请提交完整逻辑TL Flit
    input wire [2:0] i_requests, // 本Flit请求数量，含非法超限编码
    input wire [3:0] i_responses, // 本Flit响应数量，含非法超限编码
    output wire [2:0] o_requests_available, // 当前可容纳请求数量
    output wire [3:0] o_responses_available, // 当前可容纳响应数量
    output wire o_allowed, // 当前提议满足两类预算
    output wire o_taken, // 本拍允许的实际提交事件
    output wire o_rejected // 超预算提交被拒绝，调用方不得发送
); // 本地控制接口，不定义新的线上字段
reg [1:0] r_requests; // 前序Flit尚未退役的请求
reg [2:0] r_responses; // 前序Flit尚未退役的响应
wire [3:0] w_requests_total; // 加宽防止非法计数算术回绕
wire [4:0] w_responses_total; // 加宽防止非法计数算术回绕
assign o_requests_available = 3'd4 - {1'b0,r_requests}; // 请求容量固定为四
assign o_responses_available = 4'd8 - {1'b0,r_responses}; // 响应容量固定为八
assign o_allowed = i_rstn && (i_requests <= o_requests_available) && (i_responses <= o_responses_available); // 两类预算共同判定
assign o_taken = i_flit_commit && o_allowed; // 仅实际允许提交时更新
assign o_rejected = i_rstn && i_flit_commit && !o_allowed; // 拒绝事件不消耗预算
assign w_requests_total = {2'b00,r_requests} + {1'b0,i_requests}; // 本Flit请求先计入队列
assign w_responses_total = {2'b00,r_responses} + {1'b0,i_responses}; // 本Flit响应先计入队列
always @(posedge i_clk) begin // 不生成派生时钟
    if (!i_rstn) begin // 复位优先于提交
        r_requests <= 2'd0; // 恢复全部请求容量
        r_responses <= 3'd0; // 恢复全部响应容量
    end else if (o_taken) begin // 等待周期不退役
        r_requests <= (w_requests_total == 4'd0) ? 2'd0 : (w_requests_total[1:0] - 2'd1); // 每逻辑TL Flit退役一个请求
        r_responses <= (w_responses_total == 5'd0) ? 3'd0 : (w_responses_total[2:0] - 3'd1); // 每逻辑TL Flit退役一个响应
    end // 未允许提交时保持两类状态
end // 同步状态更新结束
endmodule // 打包预算单元结束
