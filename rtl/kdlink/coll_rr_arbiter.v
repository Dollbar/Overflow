module coll_rr_arbiter ( // 定义四请求包边界轮询仲裁器
    input  wire       clk_i, // 接收工作时钟
    input  wire       rst_n_i, // 接收低有效异步复位
    input  wire [3:0] request_i, // 接收四路已寄存请求
    input  wire       packet_done_i, // 指示当前包在本拍完成
    output wire [3:0] grant_o, // 输出 one-hot 已寄存授权
    output wire       grant_valid_o // 指示授权有效
); // 结束端口声明
    reg [1:0] last_q; // 保存上次完成服务的请求编号
    reg [3:0] grant_q; // 保存当前包锁定授权
    reg [3:0] select_d; // 保存下一授权组合结果
    reg [1:0] selected_index_d; // 保存下一授权编号
    always @(*) begin // 组合计算轮询优先授权
        select_d = 4'b0000; // 默认无请求获得授权
        selected_index_d = last_q; // 默认保持上次服务编号
        case (last_q) // 从上次服务编号之后开始轮询
            2'd0: begin // 上次服务请求零
                if (request_i[1]) begin select_d = 4'b0010; selected_index_d = 2'd1; end // 优先选择请求一
                else if (request_i[2]) begin select_d = 4'b0100; selected_index_d = 2'd2; end // 其次选择请求二
                else if (request_i[3]) begin select_d = 4'b1000; selected_index_d = 2'd3; end // 再选择请求三
                else if (request_i[0]) begin select_d = 4'b0001; selected_index_d = 2'd0; end // 最后回到请求零
            end // 结束上次请求零选择
            2'd1: begin // 上次服务请求一
                if (request_i[2]) begin select_d = 4'b0100; selected_index_d = 2'd2; end // 优先选择请求二
                else if (request_i[3]) begin select_d = 4'b1000; selected_index_d = 2'd3; end // 其次选择请求三
                else if (request_i[0]) begin select_d = 4'b0001; selected_index_d = 2'd0; end // 再选择请求零
                else if (request_i[1]) begin select_d = 4'b0010; selected_index_d = 2'd1; end // 最后回到请求一
            end // 结束上次请求一选择
            2'd2: begin // 上次服务请求二
                if (request_i[3]) begin select_d = 4'b1000; selected_index_d = 2'd3; end // 优先选择请求三
                else if (request_i[0]) begin select_d = 4'b0001; selected_index_d = 2'd0; end // 其次选择请求零
                else if (request_i[1]) begin select_d = 4'b0010; selected_index_d = 2'd1; end // 再选择请求一
                else if (request_i[2]) begin select_d = 4'b0100; selected_index_d = 2'd2; end // 最后回到请求二
            end // 结束上次请求二选择
            default: begin // 上次服务请求三或非法编码
                if (request_i[0]) begin select_d = 4'b0001; selected_index_d = 2'd0; end // 优先选择请求零
                else if (request_i[1]) begin select_d = 4'b0010; selected_index_d = 2'd1; end // 其次选择请求一
                else if (request_i[2]) begin select_d = 4'b0100; selected_index_d = 2'd2; end // 再选择请求二
                else if (request_i[3]) begin select_d = 4'b1000; selected_index_d = 2'd3; end // 最后回到请求三
            end // 结束默认选择
        endcase // 结束轮询起点选择
    end // 结束授权组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新包锁定授权状态
        if (!rst_n_i) begin // 检测复位有效
            last_q <= 2'd3; // 复位后从请求零开始轮询
            grant_q <= 4'b0000; // 清除当前授权
        end else if ((grant_q == 0) || packet_done_i) begin // 在空闲或包边界选择下一请求
            grant_q <= select_d; // 寄存下一包授权
            if (select_d != 0) begin // 检测存在获胜请求
                last_q <= selected_index_d; // 记录新服务编号作为下次起点
            end // 结束获胜请求条件
        end // 结束包边界更新条件
    end // 结束仲裁时序逻辑
    assign grant_o = grant_q; // 输出当前 one-hot 授权
    assign grant_valid_o = (grant_q != 0); // 指示当前存在有效授权
endmodule // 结束轮询仲裁器
