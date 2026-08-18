module coll_credit_counter #( // 定义逐 VC credit 计数模块
    parameter DEPTH = 64, // 配置最大 credit 数量
    parameter COUNT_W = 7 // 配置 credit 计数位宽
) ( // 开始端口声明
    input  wire                 clk_i, // 接收工作时钟
    input  wire                 rst_n_i, // 接收低有效异步复位
    input  wire                 init_i, // 接收 epoch 初始化脉冲
    input  wire [COUNT_W-1:0]   init_count_i, // 接收初始化 credit 数量
    input  wire                 send_i, // 接收发送一个 flit 的扣减请求
    input  wire [COUNT_W-1:0]   return_count_i, // 接收本拍归还 credit 数量
    output wire [COUNT_W-1:0]   credit_o, // 输出当前可用 credit
    output wire                 available_o, // 指示至少有一个 credit
    output reg                  underflow_o, // 指示 credit 下溢事件
    output reg                  overflow_o // 指示 credit 上溢事件
); // 结束端口声明
    reg [COUNT_W-1:0] credit_q; // 保存当前 credit 数量
    reg [COUNT_W:0] next_ext; // 保存扩展位宽的候选 credit 数量
    assign credit_o = credit_q; // 输出当前 credit 数量
    assign available_o = (credit_q != 0); // 指示当前允许发送
    always @(*) begin // 组合计算下一 credit 数量
        next_ext = {1'b0, credit_q} + {1'b0, return_count_i}; // 累计本拍归还但不提前授权发送
        if (send_i && (credit_q != 0)) begin // 仅允许消耗拍前已经可用的 credit
            next_ext = next_ext - 1'b1; // 扣减一个发送 credit
        end // 结束发送扣减条件
    end // 结束下一状态组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 credit 状态和错误脉冲
        if (!rst_n_i) begin // 检测复位有效
            credit_q <= {COUNT_W{1'b0}}; // 清零 credit 数量
            underflow_o <= 1'b0; // 清除下溢事件
            overflow_o <= 1'b0; // 清除上溢事件
        end else if (init_i) begin // 检测 epoch 初始化
            credit_q <= (init_count_i <= DEPTH) ? init_count_i : DEPTH; // 限制初始化值不超过深度
            underflow_o <= 1'b0; // 初始化时清除下溢事件
            overflow_o <= (init_count_i > DEPTH); // 报告非法初始化值
        end else begin // 处理正常 credit 更新
            underflow_o <= send_i && (credit_q == 0); // 报告任何零余额发送且不消耗同拍归还
            overflow_o <= (next_ext > DEPTH); // 报告更新结果超过最大深度
            if (next_ext > DEPTH) begin // 检测候选值超过深度
                credit_q <= DEPTH; // 将计数饱和到最大深度
            end else begin // 处理合法候选值
                credit_q <= next_ext[COUNT_W-1:0]; // 保存更新后的 credit 数量
            end // 结束范围选择
        end // 结束复位与初始化选择
    end // 结束 credit 时序逻辑
endmodule // 结束 credit 计数模块
