module coll_toggle_handshake ( // 定义跨时钟域单请求握手模块
    input  wire src_clk_i, // 接收源时钟
    input  wire src_rst_n_i, // 接收源域低有效异步复位
    input  wire src_pulse_i, // 接收源域请求脉冲
    output wire src_busy_o, // 指示源域存在未确认请求
    input  wire dst_clk_i, // 接收目标时钟
    input  wire dst_rst_n_i, // 接收目标域低有效异步复位
    output wire dst_pulse_o // 输出目标域单周期请求脉冲
); // 结束端口声明
    reg src_toggle_q; // 保存源域请求翻转位
    reg ack_sync1_q; // 保存源域第一级确认同步位
    reg ack_sync2_q; // 保存源域第二级确认同步位
    reg req_sync1_q; // 保存目标域第一级请求同步位
    reg req_sync2_q; // 保存目标域第二级请求同步位
    reg req_seen_q; // 保存目标域已处理请求翻转位
    reg ack_toggle_q; // 保存目标域确认翻转位
    assign src_busy_o = (src_toggle_q != ack_sync2_q); // 比较请求与确认翻转位形成忙状态
    assign dst_pulse_o = (req_sync2_q != req_seen_q); // 检测目标域新请求翻转
    always @(posedge src_clk_i or negedge src_rst_n_i) begin // 更新源域请求和确认同步链
        if (!src_rst_n_i) begin // 检测源域复位有效
            src_toggle_q <= 1'b0; // 清零源域请求翻转位
            ack_sync1_q <= 1'b0; // 清零确认第一级同步位
            ack_sync2_q <= 1'b0; // 清零确认第二级同步位
        end else begin // 处理源域正常运行
            ack_sync1_q <= ack_toggle_q; // 同步目标域确认翻转位
            ack_sync2_q <= ack_sync1_q; // 完成第二级确认同步
            if (src_pulse_i && !src_busy_o) begin // 检测可接受的新源域请求
                src_toggle_q <= !src_toggle_q; // 翻转请求位发起一次跨域事件
            end // 结束新请求条件
        end // 结束源域复位选择
    end // 结束源域时序逻辑
    always @(posedge dst_clk_i or negedge dst_rst_n_i) begin // 更新目标域请求同步和确认状态
        if (!dst_rst_n_i) begin // 检测目标域复位有效
            req_sync1_q <= 1'b0; // 清零请求第一级同步位
            req_sync2_q <= 1'b0; // 清零请求第二级同步位
            req_seen_q <= 1'b0; // 清零已处理请求状态
            ack_toggle_q <= 1'b0; // 清零目标域确认翻转位
        end else begin // 处理目标域正常运行
            req_sync1_q <= src_toggle_q; // 同步源域请求翻转位
            req_sync2_q <= req_sync1_q; // 完成第二级请求同步
            if (req_sync2_q != req_seen_q) begin // 检测新到达请求
                req_seen_q <= req_sync2_q; // 记录已处理请求翻转位
                ack_toggle_q <= req_sync2_q; // 返回相同翻转位作为确认
            end // 结束目标域请求处理
        end // 结束目标域复位选择
    end // 结束目标域时序逻辑
endmodule // 结束跨域握手模块
