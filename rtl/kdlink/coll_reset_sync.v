module coll_reset_sync ( // 定义异步置位同步释放复位模块
    input  wire clk_i, // 接收目标时钟
    input  wire async_rst_n_i, // 接收低有效异步复位
    output wire sync_rst_n_o // 输出低有效同步释放复位
); // 结束端口声明
    reg [1:0] sync_ff; // 保存两级复位同步状态
    always @(posedge clk_i or negedge async_rst_n_i) begin // 在时钟上升沿或异步复位下降沿更新
        if (!async_rst_n_i) begin // 检测异步复位有效
            sync_ff <= 2'b00; // 立即置位两级同步寄存器
        end else begin // 处理复位释放过程
            sync_ff <= {sync_ff[0], 1'b1}; // 用两拍将释放状态同步到目标域
        end // 结束复位条件
    end // 结束同步时序逻辑
    assign sync_rst_n_o = sync_ff[1]; // 输出第二级同步复位状态
endmodule // 结束复位同步模块
