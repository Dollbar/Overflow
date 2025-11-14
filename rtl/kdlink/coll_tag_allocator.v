module coll_tag_allocator #( // 定义位图标签分配器
    parameter TAGS = 16, // 配置标签总数
    parameter TAG_W = 4 // 配置标签索引位宽
) ( // 开始端口声明
    input  wire                 clk_i, // 接收工作时钟
    input  wire                 rst_n_i, // 接收低有效异步复位
    input  wire                 alloc_i, // 接收分配请求
    output wire                 alloc_ready_o, // 指示存在可分配标签
    output wire [TAG_W-1:0]     alloc_tag_o, // 输出最低可用标签
    input  wire                 free_i, // 接收释放请求
    input  wire [TAG_W-1:0]     free_tag_i, // 接收待释放标签
    output reg                  double_free_o, // 指示重复释放事件
    output wire [TAGS-1:0]      allocated_o // 输出当前标签位图
); // 结束端口声明
    reg [TAGS-1:0] allocated_q; // 保存已分配标签位图
    wire [TAGS-1:0] free_mask; // 表示全部空闲标签位置
    wire [TAGS-1:0] lowest_free; // 表示最低编号空闲标签 one-hot
    wire [TAG_W-1:0] selected_d; // 表示组合编码后的空闲标签
    wire selected_valid_d; // 指示组合选择结果有效
    assign free_mask = ~allocated_q; // 反相占用位图得到空闲位图
    assign lowest_free = free_mask & (~free_mask + 1'b1); // 用二进制隔离最低空闲位
    generate // 按冻结的标签规模建立平衡 one-hot 编码树
        if ((TAGS == 4) && (TAG_W == 2)) begin : g_encode4 // 支持公共单元四标签配置
            assign selected_d[0] = |(lowest_free & 4'hA); // 编码标签编号最低位
            assign selected_d[1] = |(lowest_free & 4'hC); // 编码标签编号最高位
        end else begin : g_encode16 // 默认支持产品十六标签配置
            assign selected_d[0] = |(lowest_free & 16'hAAAA); // 编码十六标签编号位零
            assign selected_d[1] = |(lowest_free & 16'hCCCC); // 编码十六标签编号位一
            assign selected_d[2] = |(lowest_free & 16'hF0F0); // 编码十六标签编号位二
            assign selected_d[3] = |(lowest_free & 16'hFF00); // 编码十六标签编号位三
        end // 结束标签规模选择
    endgenerate // 结束 one-hot 编码树生成
    assign selected_valid_d = |free_mask; // 任一空闲位存在时允许分配
    assign alloc_ready_o = selected_valid_d; // 输出分配可用状态
    assign alloc_tag_o = selected_d; // 输出候选标签编号
    assign allocated_o = allocated_q; // 输出当前分配位图
    always @(posedge clk_i or negedge rst_n_i) begin // 更新标签位图和错误状态
        if (!rst_n_i) begin // 检测复位有效
            allocated_q <= {TAGS{1'b0}}; // 清除全部标签占用
            double_free_o <= 1'b0; // 清除重复释放事件
        end else begin // 处理正常分配释放
            double_free_o <= free_i && !allocated_q[free_tag_i]; // 检测当前重复释放
            if (alloc_i && selected_valid_d) begin // 检测合法分配请求
                allocated_q[selected_d] <= 1'b1; // 标记候选标签已分配
            end // 结束分配条件
            if (free_i && allocated_q[free_tag_i]) begin // 检测合法释放请求
                allocated_q[free_tag_i] <= 1'b0; // 清除已释放标签占用
            end // 结束释放条件
        end // 结束复位选择
    end // 结束标签分配时序逻辑
endmodule // 结束标签分配器
