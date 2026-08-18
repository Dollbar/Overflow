module coll_sat_counter #( // 定义可清零饱和计数器
    parameter WIDTH = 64 // 配置计数器位宽
) ( // 开始端口声明
    input  wire                 clk_i, // 接收工作时钟
    input  wire                 rst_n_i, // 接收低有效异步复位
    input  wire                 clear_i, // 接收同步清零脉冲
    input  wire                 increment_i, // 接收加一脉冲
    output wire [WIDTH-1:0]     count_o, // 输出当前计数值
    output wire                 saturated_o // 指示计数器已经饱和
); // 结束端口声明
    reg [WIDTH-1:0] count_q; // 保存当前计数值
    reg saturated_q; // 保存计数器饱和状态以隔离宽归约路径
    wire [WIDTH-1:0] prefix1; // 保存距离一的前缀与结果
    wire [WIDTH-1:0] prefix2; // 保存距离二的前缀与结果
    wire [WIDTH-1:0] prefix4; // 保存距离四的前缀与结果
    wire [WIDTH-1:0] prefix8; // 保存距离八的前缀与结果
    wire [WIDTH-1:0] prefix16; // 保存距离十六的前缀与结果
    /* verilator lint_off UNUSEDSIGNAL */ // 最高前缀位仅服务结构完整性且不进入加一结果
    wire [WIDTH-1:0] prefix32; // 保存距离三十二的前缀与结果
    /* verilator lint_on UNUSEDSIGNAL */ // 恢复未使用信号检查
    wire [WIDTH-1:0] incremented; // 保存对当前值加一的前缀网络结果
    genvar bit_index; // 提供静态前缀网络生成索引
    generate // 建立对数深度的加一进位前缀网络
        for (bit_index = 0; bit_index < WIDTH; bit_index = bit_index + 1) begin : g_prefix // 为每一计数位生成前缀节点
            if (bit_index >= 1) begin : g_p1 // 连接距离一的前缀节点
                assign prefix1[bit_index] = count_q[bit_index] & count_q[bit_index-1]; // 合并相邻一位进位条件
            end else begin : g_p1_pass // 直通最低位前缀
                assign prefix1[bit_index] = count_q[bit_index]; // 保留最低位进位条件
            end // 结束距离一选择
            if (bit_index >= 2) begin : g_p2 // 连接距离二的前缀节点
                assign prefix2[bit_index] = prefix1[bit_index] & prefix1[bit_index-2]; // 合并距离二进位条件
            end else begin : g_p2_pass // 直通不足距离二的前缀
                assign prefix2[bit_index] = prefix1[bit_index]; // 保留较低位前缀条件
            end // 结束距离二选择
            if (bit_index >= 4) begin : g_p4 // 连接距离四的前缀节点
                assign prefix4[bit_index] = prefix2[bit_index] & prefix2[bit_index-4]; // 合并距离四进位条件
            end else begin : g_p4_pass // 直通不足距离四的前缀
                assign prefix4[bit_index] = prefix2[bit_index]; // 保留较低位前缀条件
            end // 结束距离四选择
            if (bit_index >= 8) begin : g_p8 // 连接距离八的前缀节点
                assign prefix8[bit_index] = prefix4[bit_index] & prefix4[bit_index-8]; // 合并距离八进位条件
            end else begin : g_p8_pass // 直通不足距离八的前缀
                assign prefix8[bit_index] = prefix4[bit_index]; // 保留较低位前缀条件
            end // 结束距离八选择
            if (bit_index >= 16) begin : g_p16 // 连接距离十六的前缀节点
                assign prefix16[bit_index] = prefix8[bit_index] & prefix8[bit_index-16]; // 合并距离十六进位条件
            end else begin : g_p16_pass // 直通不足距离十六的前缀
                assign prefix16[bit_index] = prefix8[bit_index]; // 保留较低位前缀条件
            end // 结束距离十六选择
            if (bit_index >= 32) begin : g_p32 // 连接距离三十二的前缀节点
                assign prefix32[bit_index] = prefix16[bit_index] & prefix16[bit_index-32]; // 合并距离三十二进位条件
            end else begin : g_p32_pass // 直通不足距离三十二的前缀
                assign prefix32[bit_index] = prefix16[bit_index]; // 保留较低位前缀条件
            end // 结束距离三十二选择
        end // 结束逐位前缀节点生成
    endgenerate // 结束加一前缀网络
    assign incremented = count_q ^ {prefix32[WIDTH-2:0], 1'b1}; // 用前缀进位并行形成加一结果
    assign count_o = count_q; // 输出当前计数值
    assign saturated_o = saturated_q; // 输出隔离后的寄存饱和状态
    always @(posedge clk_i or negedge rst_n_i) begin // 更新计数器状态
        if (!rst_n_i) begin // 检测复位有效
            count_q <= {WIDTH{1'b0}}; // 异步清零计数值
            saturated_q <= 1'b0; // 异步清除饱和状态
        end else if (clear_i) begin // 检测同步清零请求
            count_q <= {WIDTH{1'b0}}; // 清零计数值
            saturated_q <= 1'b0; // 同步清除饱和状态
        end else if (increment_i && !saturated_q) begin // 检测未饱和的加一请求
            count_q <= incremented; // 保存对数深度前缀网络的加一结果
            saturated_q <= (!count_q[0]) && (&count_q[WIDTH-1:1]); // 在当前值为最大值减一时锁存饱和
        end // 结束计数更新条件
    end // 结束计数器时序逻辑
endmodule // 结束饱和计数器
