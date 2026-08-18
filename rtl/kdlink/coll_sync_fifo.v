module coll_sync_fifo #( // 定义带寄存头的同步 FIFO
    parameter WIDTH = 32, // 配置数据位宽
    parameter DEPTH = 8, // 配置 FIFO 深度
    parameter ADDR_W = 3, // 配置存储地址位宽
    parameter COUNT_W = 4 // 配置占用计数位宽
) ( // 开始端口声明
    input  wire                 clk_i, // 接收工作时钟
    input  wire                 rst_n_i, // 接收低有效异步复位
    input  wire [WIDTH-1:0]     push_data_i, // 接收写入数据
    input  wire                 push_valid_i, // 接收写入有效指示
    output wire                 push_ready_o, // 返回写入接收能力
    output wire [WIDTH-1:0]     pop_data_o, // 输出队首寄存数据
    output wire                 pop_valid_o, // 输出队首有效指示
    input  wire                 pop_ready_i, // 接收队首消费指示
    output wire [COUNT_W-1:0]   occupancy_o, // 输出当前占用数量
    output reg                  overflow_o, // 指示内部写指针不变量错误且正常 ready valid 握手下恒为零
    output reg                  underflow_o // 指示内部读指针不变量错误且正常 ready valid 握手下恒为零
); // 结束端口声明
    reg [WIDTH-1:0] mem [0:DEPTH-1]; // 保存环形 FIFO 全部数据
    reg [ADDR_W-1:0] read_ptr_q; // 保存当前队首存储读取指针
    reg [ADDR_W-1:0] write_ptr_q; // 保存下一尾部存储写入指针
    reg [COUNT_W-1:0] count_q; // 保存 FIFO 总占用数量
    wire push_fire; // 指示本拍接受写入
    wire pop_fire; // 指示本拍接受读取
    assign pop_valid_o = (count_q != {COUNT_W{1'b0}}); // 占用非零时声明队首有效
    /* verilator lint_off WIDTHEXPAND */ // 允许参数化 FIFO 深度与 occupancy 位宽比较
    assign push_ready_o = (count_q < DEPTH); // 仅由寄存占用状态产生写就绪以切断满队列旁路
    /* verilator lint_on WIDTHEXPAND */ // 恢复宽度检查
    assign push_fire = push_valid_i && push_ready_o; // 形成写入握手
    assign pop_fire = pop_ready_i && pop_valid_o; // 形成读取握手
    assign pop_data_o = mem[read_ptr_q]; // 从环形存储当前读地址输出队首数据
    assign occupancy_o = count_q; // 输出占用计数
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 FIFO 状态和数据
        if (!rst_n_i) begin // 检测复位有效
            read_ptr_q <= {ADDR_W{1'b0}}; // 清零读指针
            write_ptr_q <= {ADDR_W{1'b0}}; // 清零写指针
            count_q <= {COUNT_W{1'b0}}; // 清零占用计数
            overflow_o <= 1'b0; // 清除写满错误脉冲
            underflow_o <= 1'b0; // 清除读空错误脉冲
        end else begin // 处理正常 FIFO 操作
            overflow_o <= 1'b0; // producer 等待 push_ready 属于合法 backpressure
            underflow_o <= 1'b0; // consumer 提前声明 pop_ready 属于合法 ready valid 行为
            case ({push_fire, pop_fire}) // 按同拍写读组合更新状态
                2'b10: begin // 处理仅写入操作
                    mem[write_ptr_q] <= push_data_i; // 将新数据写入当前环形尾部
                    write_ptr_q <= write_ptr_q + 1'b1; // 推进尾部写指针
                    count_q <= count_q + 1'b1; // 增加占用计数
                end // 结束仅写入操作
                2'b01: begin // 处理仅读取操作
                    read_ptr_q <= read_ptr_q + 1'b1; // 推进环形读指针
                    count_q <= count_q - 1'b1; // 减少占用计数
                end // 结束仅读取操作
                2'b11: begin // 处理同拍写入和读取
                    mem[write_ptr_q] <= push_data_i; // 同拍将新数据写入环形尾部
                    write_ptr_q <= write_ptr_q + 1'b1; // 推进环形写指针
                    read_ptr_q <= read_ptr_q + 1'b1; // 推进环形读指针
                end // 结束同拍写读操作
                default: begin // 处理空闲周期
                    count_q <= count_q; // 保持占用计数不变
                end // 结束默认操作
            endcase // 结束写读组合选择
        end // 结束复位选择
    end // 结束 FIFO 时序逻辑
endmodule // 结束同步 FIFO 模块
