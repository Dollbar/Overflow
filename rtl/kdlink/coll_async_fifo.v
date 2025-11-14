module coll_async_fifo #( // 定义 Gray 指针异步 FIFO
    parameter WIDTH = 32, // 配置跨域数据位宽
    parameter ADDR_W = 3 // 配置存储地址位宽且要求至少为二
) ( // 开始端口声明
    input  wire                 write_clk_i, // 接收写时钟
    input  wire                 write_rst_n_i, // 接收写域低有效异步复位
    input  wire [WIDTH-1:0]     write_data_i, // 接收写域数据
    input  wire                 write_valid_i, // 接收写域有效指示
    output wire                 write_ready_o, // 返回写域接收能力
    input  wire                 read_clk_i, // 接收读时钟
    input  wire                 read_rst_n_i, // 接收读域低有效异步复位
    output wire [WIDTH-1:0]     read_data_o, // 输出读域头部数据
    output wire                 read_valid_o, // 输出读域有效指示
    input  wire                 read_ready_i, // 接收读域消费能力
    output reg                  overflow_o, // 指示内部写指针越界不变量错误且正常 ready valid 握手下恒为零
    output reg                  underflow_o // 指示内部读指针越界不变量错误且正常 ready valid 握手下恒为零
); // 结束端口声明
    localparam PTR_W = ADDR_W + 1; // 定义带环绕位的指针宽度
    localparam DEPTH = (1 << ADDR_W); // 定义 FIFO 存储深度
    reg [WIDTH-1:0] mem [0:DEPTH-1]; // 保存跨域数据
    reg [PTR_W-1:0] write_bin_q; // 保存写域二进制指针
    reg [PTR_W-1:0] write_gray_q; // 保存写域 Gray 指针
    reg [PTR_W-1:0] read_gray_wsync1_q; // 保存读指针到写域第一级同步值
    reg [PTR_W-1:0] read_gray_wsync2_q; // 保存读指针到写域第二级同步值
    reg write_full_q; // 保存写域满状态
    reg [PTR_W-1:0] read_bin_q; // 保存读域二进制预取指针
    reg [PTR_W-1:0] read_gray_q; // 保存读域 Gray 预取指针
    reg [PTR_W-1:0] write_gray_rsync1_q; // 保存写指针到读域第一级同步值
    reg [PTR_W-1:0] write_gray_rsync2_q; // 保存写指针到读域第二级同步值
    reg [WIDTH-1:0] read_data_q; // 保存读域弹性头部数据
    reg read_valid_q; // 保存读域弹性头部有效状态
    wire write_fire; // 指示写域完成一次写入
    wire [PTR_W-1:0] write_bin_next; // 表示写域下一二进制指针
    wire [PTR_W-1:0] write_gray_next; // 表示写域下一 Gray 指针
    wire write_full_next; // 表示写域下一满状态
    wire read_take; // 指示下游消费当前头部数据
    wire read_load; // 指示读域需要装载头部数据
    wire raw_empty; // 指示异步存储当前没有可预取数据
    wire [PTR_W-1:0] read_bin_next; // 表示读域下一二进制指针
    wire [PTR_W-1:0] read_gray_next; // 表示读域下一 Gray 指针
    assign write_ready_o = !write_full_q; // 满状态未置位时允许写入
    assign write_fire = write_valid_i && write_ready_o; // 形成写域握手
    assign write_bin_next = write_bin_q + write_fire; // 计算写域下一二进制指针
    assign write_gray_next = (write_bin_next >> 1) ^ write_bin_next; // 将下一写指针转换为 Gray 编码
    assign write_full_next = (write_gray_next == {~read_gray_wsync2_q[PTR_W-1:PTR_W-2], read_gray_wsync2_q[PTR_W-3:0]}); // 比较翻转高位后的同步读指针
    assign read_take = read_valid_q && read_ready_i; // 形成读域消费握手
    assign read_load = !read_valid_q || read_take; // 在头部空闲或被消费时允许预取
    assign raw_empty = (read_gray_q == write_gray_rsync2_q); // 比较本地读指针和同步写指针
    assign read_bin_next = read_bin_q + (read_load && !raw_empty); // 计算预取后的读指针
    assign read_gray_next = (read_bin_next >> 1) ^ read_bin_next; // 将下一读指针转换为 Gray 编码
    assign read_data_o = read_data_q; // 输出读域弹性头部数据
    assign read_valid_o = read_valid_q; // 输出读域弹性头部有效状态
    always @(posedge write_clk_i or negedge write_rst_n_i) begin // 更新写域指针和存储
        if (!write_rst_n_i) begin // 检测写域复位有效
            write_bin_q <= {PTR_W{1'b0}}; // 清零写域二进制指针
            write_gray_q <= {PTR_W{1'b0}}; // 清零写域 Gray 指针
            write_full_q <= 1'b0; // 清除写域满状态
            overflow_o <= 1'b0; // 清除写满错误脉冲
            read_gray_wsync1_q <= {PTR_W{1'b0}}; // 清零读指针第一级同步值
            read_gray_wsync2_q <= {PTR_W{1'b0}}; // 清零读指针第二级同步值
        end else begin // 处理写域正常运行
            overflow_o <= 1'b0; // ready 拉低属于合法 backpressure 且不构成 overflow
            read_gray_wsync1_q <= read_gray_q; // 同步读域 Gray 指针到写域
            read_gray_wsync2_q <= read_gray_wsync1_q; // 完成读指针第二级同步
            if (write_fire) begin // 检测合法写入握手
                mem[write_bin_q[ADDR_W-1:0]] <= write_data_i; // 将数据写入当前写地址
            end // 结束存储写入条件
            write_bin_q <= write_bin_next; // 保存下一写域二进制指针
            write_gray_q <= write_gray_next; // 保存下一写域 Gray 指针
            write_full_q <= write_full_next; // 保存下一写域满状态
        end // 结束写域复位选择
    end // 结束写域时序逻辑
    always @(posedge read_clk_i or negedge read_rst_n_i) begin // 更新读域指针和弹性头部
        if (!read_rst_n_i) begin // 检测读域复位有效
            read_bin_q <= {PTR_W{1'b0}}; // 清零读域二进制指针
            read_gray_q <= {PTR_W{1'b0}}; // 清零读域 Gray 指针
            write_gray_rsync1_q <= {PTR_W{1'b0}}; // 清零写指针第一级同步值
            write_gray_rsync2_q <= {PTR_W{1'b0}}; // 清零写指针第二级同步值
            read_data_q <= {WIDTH{1'b0}}; // 清零读域头部数据
            read_valid_q <= 1'b0; // 清除读域头部有效状态
            underflow_o <= 1'b0; // 清除读空错误脉冲
        end else begin // 处理读域正常运行
            underflow_o <= 1'b0; // consumer 可提前声明 ready 且空 FIFO 不构成 underflow
            write_gray_rsync1_q <= write_gray_q; // 同步写域 Gray 指针到读域
            write_gray_rsync2_q <= write_gray_rsync1_q; // 完成写指针第二级同步
            if (read_load) begin // 检测头部需要装载或清空
                if (!raw_empty) begin // 检测异步存储存在待预取数据
                    read_data_q <= mem[read_bin_q[ADDR_W-1:0]]; // 将当前读地址数据预取到头部
                    read_valid_q <= 1'b1; // 声明新头部数据有效
                end else begin // 处理没有可预取数据
                    read_valid_q <= 1'b0; // 清除头部有效状态
                end // 结束原始空状态选择
            end // 结束头部装载条件
            read_bin_q <= read_bin_next; // 保存下一读域二进制指针
            read_gray_q <= read_gray_next; // 保存下一读域 Gray 指针
        end // 结束读域复位选择
    end // 结束读域时序逻辑
endmodule // 结束异步 FIFO 模块
