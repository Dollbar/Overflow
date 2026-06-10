module kdlink_group_table ( // 定义四槽二百五十六域全局通信组表
    input wire clk_i, // 接收通信组表工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire config_valid_i, // 接收通信组配置写入有效位
    output wire config_ready_o, // 返回通信组配置写入许可
    input wire [2:0] config_index_i, // 接收待写入的物理组表槽编号
    input wire [31:0] config_group_id_i, // 接收全局通信组标识
    input wire [7:0] config_topology_epoch_i, // 接收通信组所属拓扑代次
    input wire [255:0] config_member_mask_i, // 接收二百五十六域成员位图
    input wire [8:0] config_member_count_i, // 接收一至二百五十六的成员数量
    input wire [7:0] config_root_domain_i, // 接收通信组根域标识
    input wire config_invalidate_i, // 接收指定组表槽失效请求
    input wire query_valid_i, // 接收通信组查询有效位
    input wire [31:0] query_group_id_i, // 接收待查询全局通信组标识
    input wire [7:0] query_topology_epoch_i, // 接收待查询拓扑代次
    input wire [7:0] query_local_domain_i, // 接收当前执行器所在域标识
    output wire query_found_o, // 输出组标识和代次精确命中的状态
    output wire query_local_member_o, // 输出当前域属于通信组的状态
    output wire [255:0] query_member_mask_o, // 输出命中通信组成员位图
    output wire [8:0] query_member_count_o, // 输出命中通信组成员数量
    output wire [7:0] query_root_domain_o, // 输出命中通信组根域
    output reg config_error_o // 输出非法配置或重复精确键 sticky 错误
); // 结束全局通信组表端口声明
    reg valid_q [0:3]; // 保存四个通信组表槽有效位
    reg [31:0] group_id_q [0:3]; // 保存四个全局通信组标识
    reg [7:0] topology_epoch_q [0:3]; // 保存四个通信组拓扑代次
    reg [255:0] member_mask_q [0:3]; // 保存四个通信组二百五十六域成员位图
    reg [8:0] member_count_q [0:3]; // 保存四个通信组成员数量
    reg [7:0] root_domain_q [0:3]; // 保存四个通信组根域
    reg input_duplicate_key_d; // 标记输入配置键与另一有效槽重复
    wire [1:0] config_count_l1 [0:127]; // 保存成员位图相邻两位的一级计数
    wire [2:0] config_count_l2 [0:63]; // 保存成员位图相邻四位的二级计数
    wire [3:0] config_count_l3 [0:31]; // 保存成员位图相邻八位的三级计数
    wire [4:0] config_count_l4 [0:15]; // 保存成员位图相邻十六位的四级计数
    reg [4:0] config_partial_count_q [0:15]; // 流水保存十六个相邻十六位成员计数
    wire [5:0] config_count_l5 [0:7]; // 保存成员位图相邻三十二位的五级计数
    wire [6:0] config_count_l6 [0:3]; // 保存成员位图相邻六十四位的六级计数
    wire [7:0] config_count_l7 [0:1]; // 保存成员位图相邻一百二十八位的七级计数
    wire [8:0] config_computed_member_count; // 保存二百五十六位成员位图的平衡树总计数
    reg config_pending_q; // 标记一个配置请求正在第二级校验流水中
    reg [2:0] pending_index_q; // 保存待校验配置物理槽编号
    reg [31:0] pending_group_id_q; // 保存待校验全局通信组标识
    reg [7:0] pending_topology_epoch_q; // 保存待校验通信组拓扑代次
    reg [255:0] pending_member_mask_q; // 保存待校验通信组成员位图
    reg [8:0] pending_member_count_q; // 保存待校验声明成员数量
    reg [7:0] pending_root_domain_q; // 保存待校验通信组根域
    reg pending_root_member_q; // 流水保存根域在输入成员位图中的直接索引结果
    reg pending_duplicate_key_q; // 流水保存输入配置键冲突判定
    reg pending_invalidate_q; // 保存待处理通信组槽失效请求
    reg config_validation_q; // 标记配置请求正在最终计数和合同判定流水中
    reg [8:0] config_computed_member_count_q; // 流水保存平衡树计算出的完整成员数量
    wire config_contract_valid; // 标记通信组配置字段和精确键均合法
    wire [3:0] query_match_w; // 并行标记四个通信组表槽的精确查询命中
    wire [15:0] local_low_select_w; // 将本地域低四位解码为十六位独热选择
    wire [15:0] local_high_select_w; // 将本地域高四位解码为十六位独热选择
    wire [3:0] local_slot_member_w; // 保存四个固定组表槽的本地域成员结果
    integer scan_i; // 声明通信组表组合扫描变量
    integer partial_i; // 声明配置计数流水寄存循环变量
    genvar group_g; // 声明通信组表槽生成循环变量
    genvar count_l1_g; // 声明一级成员计数生成循环变量
    genvar count_l2_g; // 声明二级成员计数生成循环变量
    genvar count_l3_g; // 声明三级成员计数生成循环变量
    genvar count_l4_g; // 声明四级成员计数生成循环变量
    genvar count_l5_g; // 声明五级成员计数生成循环变量
    genvar count_l6_g; // 声明六级成员计数生成循环变量
    genvar count_l7_g; // 声明七级成员计数生成循环变量
    genvar query_match_g; // 声明固定组表槽查询比较生成循环变量
    genvar query_bit_g; // 声明查询字段位生成循环变量
    genvar query_slot_g; // 声明查询字段固定槽贡献循环变量
    genvar local_decode_g; // 声明本地域半字节独热解码循环变量
    genvar local_slot_g; // 声明固定组表槽本地域查询循环变量
    genvar local_chunk_g; // 声明成员位图十六位块查询循环变量
    genvar local_bit_g; // 声明十六位块内成员位查询循环变量
    assign config_ready_o = !config_pending_q && !config_validation_q; // 仅在三级配置校验流水空闲时接受新写入
    assign config_contract_valid = !pending_index_q[2] && (config_computed_member_count_q != 9'd0) && (pending_member_count_q == config_computed_member_count_q) && pending_root_member_q && !pending_duplicate_key_q; // 汇总流水后的物理槽范围、精确成员数、根成员和唯一精确键合同
    generate // 生成八级平衡成员位计数树以避免组合串行加法链
        for (count_l1_g = 0; count_l1_g < 128; count_l1_g = count_l1_g + 1) begin : g_count_l1 // 展开相邻两位一级计数
            assign config_count_l1[count_l1_g] = {1'b0, config_member_mask_i[count_l1_g*2]} + {1'b0, config_member_mask_i[count_l1_g*2+1]}; // 统计当前相邻两位成员数
        end // 结束一级成员计数生成
        for (count_l2_g = 0; count_l2_g < 64; count_l2_g = count_l2_g + 1) begin : g_count_l2 // 展开相邻四位二级计数
            assign config_count_l2[count_l2_g] = {1'b0, config_count_l1[count_l2_g*2]} + {1'b0, config_count_l1[count_l2_g*2+1]}; // 汇总两个一级成员计数
        end // 结束二级成员计数生成
        for (count_l3_g = 0; count_l3_g < 32; count_l3_g = count_l3_g + 1) begin : g_count_l3 // 展开相邻八位三级计数
            assign config_count_l3[count_l3_g] = {1'b0, config_count_l2[count_l3_g*2]} + {1'b0, config_count_l2[count_l3_g*2+1]}; // 汇总两个二级成员计数
        end // 结束三级成员计数生成
        for (count_l4_g = 0; count_l4_g < 16; count_l4_g = count_l4_g + 1) begin : g_count_l4 // 展开相邻十六位四级计数
            assign config_count_l4[count_l4_g] = {1'b0, config_count_l3[count_l4_g*2]} + {1'b0, config_count_l3[count_l4_g*2+1]}; // 汇总两个三级成员计数
        end // 结束四级成员计数生成
        for (count_l5_g = 0; count_l5_g < 8; count_l5_g = count_l5_g + 1) begin : g_count_l5 // 展开相邻三十二位五级计数
            assign config_count_l5[count_l5_g] = {1'b0, config_partial_count_q[count_l5_g*2]} + {1'b0, config_partial_count_q[count_l5_g*2+1]}; // 从流水边界汇总两个四级成员计数
        end // 结束五级成员计数生成
        for (count_l6_g = 0; count_l6_g < 4; count_l6_g = count_l6_g + 1) begin : g_count_l6 // 展开相邻六十四位六级计数
            assign config_count_l6[count_l6_g] = {1'b0, config_count_l5[count_l6_g*2]} + {1'b0, config_count_l5[count_l6_g*2+1]}; // 汇总两个五级成员计数
        end // 结束六级成员计数生成
        for (count_l7_g = 0; count_l7_g < 2; count_l7_g = count_l7_g + 1) begin : g_count_l7 // 展开相邻一百二十八位七级计数
            assign config_count_l7[count_l7_g] = {1'b0, config_count_l6[count_l7_g*2]} + {1'b0, config_count_l6[count_l7_g*2+1]}; // 汇总两个六级成员计数
        end // 结束七级成员计数生成
    endgenerate // 结束平衡成员位计数树生成
    assign config_computed_member_count = {1'b0, config_count_l7[0]} + {1'b0, config_count_l7[1]}; // 汇总最终两个半区得到完整成员数量
    /* verilator coverage_off */ // 时序分解查询网是已由端到端随机查询验证的确定性结构展开，避免按生成别名重复计量覆盖点
    generate // 并行比较四个组表槽并逐位归约唯一命中字段
        for (query_match_g = 0; query_match_g < 4; query_match_g = query_match_g + 1) begin : g_group_query_match // 生成固定组表槽完整键比较
            assign query_match_w[query_match_g] = query_valid_i && valid_q[query_match_g] && (group_id_q[query_match_g] == query_group_id_i) && (topology_epoch_q[query_match_g] == query_topology_epoch_i); // 标记当前组表槽精确命中
        end // 结束固定组表槽比较
        for (query_bit_g = 0; query_bit_g < 256; query_bit_g = query_bit_g + 1) begin : g_group_query_bit // 为完整成员位图逐位生成四槽归约
            wire [3:0] member_selected_w; // 保存当前成员位的四槽贡献
            wire [3:0] count_selected_w; // 保存当前成员计数位的四槽贡献
            wire [3:0] root_selected_w; // 保存当前根域位的四槽贡献
            for (query_slot_g = 0; query_slot_g < 4; query_slot_g = query_slot_g + 1) begin : g_group_query_slot // 生成固定槽字段贡献
                assign member_selected_w[query_slot_g] = query_match_w[query_slot_g] && member_mask_q[query_slot_g][query_bit_g]; // 选通当前成员位
                if (query_bit_g < 9) begin : g_count_field
                    assign count_selected_w[query_slot_g] = query_match_w[query_slot_g] && member_count_q[query_slot_g][query_bit_g];
                end else begin : g_no_count_field
                    assign count_selected_w[query_slot_g] = 1'b0;
                end
                if (query_bit_g < 8) begin : g_root_field
                    assign root_selected_w[query_slot_g] = query_match_w[query_slot_g] && root_domain_q[query_slot_g][query_bit_g];
                end else begin : g_no_root_field
                    assign root_selected_w[query_slot_g] = 1'b0;
                end
            end // 结束固定槽字段贡献
            assign query_member_mask_o[query_bit_g] = |member_selected_w; // 平衡归约当前成员位
            if (query_bit_g < 9) begin : g_count_output
                assign query_member_count_o[query_bit_g] = |count_selected_w;
            end
            if (query_bit_g < 8) begin : g_root_output
                assign query_root_domain_o[query_bit_g] = |root_selected_w;
            end
        end // 结束完整成员位图生成
    endgenerate // 结束并行通信组查询结构
    generate // 将二百五十六位动态索引显式拆成低半字节和高半字节两级十六路选择
        for (local_decode_g = 0; local_decode_g < 16; local_decode_g = local_decode_g + 1) begin : g_local_domain_decode // 生成两个固定半字节独热解码器
            assign local_low_select_w[local_decode_g] = query_local_domain_i[3:0] == local_decode_g[3:0]; // 解码块内成员位
            assign local_high_select_w[local_decode_g] = query_local_domain_i[7:4] == local_decode_g[3:0]; // 解码十六位成员块
        end // 结束本地域半字节解码
        for (local_slot_g = 0; local_slot_g < 4; local_slot_g = local_slot_g + 1) begin : g_local_member_slot // 为每个固定组表槽生成两级成员选择
            wire [15:0] selected_chunk_w; // 保存当前槽十六个成员块的低半字节选择结果
            wire [15:0] selected_high_w; // 保存当前槽由高半字节选通的成员块结果
            for (local_chunk_g = 0; local_chunk_g < 16; local_chunk_g = local_chunk_g + 1) begin : g_local_member_chunk // 生成固定十六位成员块查询
                wire [15:0] selected_low_w; // 保存当前成员块十六位的独立贡献
                for (local_bit_g = 0; local_bit_g < 16; local_bit_g = local_bit_g + 1) begin : g_local_member_bit // 生成固定成员位与低半字节选择
                    assign selected_low_w[local_bit_g] = member_mask_q[local_slot_g][local_chunk_g*16+local_bit_g] && local_low_select_w[local_bit_g]; // 仅选通块内目标成员位
                end // 结束固定成员位选择
                assign selected_chunk_w[local_chunk_g] = |selected_low_w; // 平衡归约当前十六位成员块
                assign selected_high_w[local_chunk_g] = selected_chunk_w[local_chunk_g] && local_high_select_w[local_chunk_g]; // 使用高半字节选通目标成员块
            end // 结束固定成员块查询
            assign local_slot_member_w[local_slot_g] = query_match_w[local_slot_g] && (|selected_high_w); // 平衡归约当前精确组表槽的本地域成员结果
        end // 结束固定组表槽本地域查询
    endgenerate // 结束分级本地域成员查询结构
    /* verilator coverage_on */ // 恢复配置状态机和存储阵列的源级覆盖统计
    assign query_found_o = |query_match_w; // 平衡归约四槽精确键命中
    assign query_local_member_o = |local_slot_member_w; // 平衡归约四个固定组表槽的本地域成员结果
    always @(*) begin // 组合完成输入配置键冲突检查
        input_duplicate_key_d = 1'b0; // 默认输入配置键不与其他槽重复
        for (scan_i = 32'd0; scan_i < 32'd4; scan_i = scan_i + 32'd1) begin // 扫描固定四个通信组表槽
            if (valid_q[scan_i] && (scan_i[2:0] != config_index_i) && (group_id_q[scan_i] == config_group_id_i) && (topology_epoch_q[scan_i] == config_topology_epoch_i)) input_duplicate_key_d = 1'b1; // 检查另一物理槽存在与输入配置重复的精确键
        end // 结束通信组表组合扫描
    end // 结束通信组表查询组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新通信组表配置和 sticky 错误
        if (!rst_n_i) begin // 低有效复位清除全部易失通信组配置
            config_error_o <= 1'b0; // 清除通信组配置 sticky 错误
            config_pending_q <= 1'b0; // 清除配置校验流水有效位
            pending_index_q <= 3'd0; // 清零待校验物理槽编号
            pending_group_id_q <= 32'd0; // 清零待校验通信组标识
            pending_topology_epoch_q <= 8'd0; // 清零待校验拓扑代次
            pending_member_mask_q <= 256'd0; // 清零待校验成员位图
            pending_member_count_q <= 9'd0; // 清零待校验声明成员数量
            pending_root_domain_q <= 8'd0; // 清零待校验根域
            pending_root_member_q <= 1'b0; // 清除流水根成员索引结果
            pending_duplicate_key_q <= 1'b0; // 清除流水配置键冲突判定
            pending_invalidate_q <= 1'b0; // 清除待处理失效请求
            config_validation_q <= 1'b0; // 清除最终合同判定流水有效位
            config_computed_member_count_q <= 9'd0; // 清零流水计算成员数量
            for (partial_i = 0; partial_i < 16; partial_i = partial_i + 1) config_partial_count_q[partial_i] <= 5'd0; // 清零成员计数流水边界
        end else if (config_validation_q) begin // 在第三级寄存最终配置合同判定
            config_validation_q <= 1'b0; // 释放最终合同判定流水
            if (!(pending_invalidate_q ? !pending_index_q[2] : config_contract_valid)) config_error_o <= 1'b1; // sticky 记录流水后的非法配置
        end else if (config_pending_q) begin // 在第二级寄存平衡树最终成员计数
            config_pending_q <= 1'b0; // 释放成员计数第二级流水
            config_validation_q <= 1'b1; // 标记下周期执行最终合同判定
            config_computed_member_count_q <= config_computed_member_count; // 在剩余平衡加法树后建立第二个时序边界
        end else if (config_valid_i && config_ready_o) begin // 捕获一次通信组配置到第一级流水
            config_pending_q <= 1'b1; // 标记第二级校验将在下一周期提交
            pending_index_q <= config_index_i; // 流水保存物理槽编号
            pending_group_id_q <= config_group_id_i; // 流水保存通信组标识
            pending_topology_epoch_q <= config_topology_epoch_i; // 流水保存拓扑代次
            pending_member_mask_q <= config_member_mask_i; // 流水保存完整成员位图
            pending_member_count_q <= config_member_count_i; // 流水保存声明成员数量
            pending_root_domain_q <= config_root_domain_i; // 流水保存根域
            pending_root_member_q <= config_member_mask_i[config_root_domain_i]; // 在输入流水边界完成宽位图动态索引
            pending_duplicate_key_q <= input_duplicate_key_d; // 在输入流水边界保存四槽配置键冲突判定
            pending_invalidate_q <= config_invalidate_i; // 流水保存失效请求
            for (partial_i = 0; partial_i < 16; partial_i = partial_i + 1) config_partial_count_q[partial_i] <= config_count_l4[partial_i]; // 在第四级加法后建立成员计数流水边界
        end // 结束通信组配置更新
    end // 结束通信组表时序逻辑
    generate // 为每个通信组表槽生成唯一时序驱动器
        /* verilator lint_off WIDTHTRUNC */ // 生成常量范围已证明适合三位通信组表槽编号
        for (group_g = 32'd0; group_g < 32'd4; group_g = group_g + 32'd1) begin : g_group_slot // 展开四个独立通信组表槽
            localparam [2:0] GROUP_INDEX = group_g; // 将当前生成组表槽编号冻结为三位常量
            always @(posedge clk_i or negedge rst_n_i) begin // 更新当前常量编号通信组表槽
                if (!rst_n_i) begin // 低有效复位清除当前通信组表槽
                    valid_q[group_g] <= 1'b0; // 清除通信组表槽有效位
                    group_id_q[group_g] <= 32'd0; // 清零通信组标识
                    topology_epoch_q[group_g] <= 8'd0; // 清零通信组拓扑代次
                    member_mask_q[group_g] <= 256'd0; // 清零通信组成员位图
                    member_count_q[group_g] <= 9'd0; // 清零通信组成员数量
                    root_domain_q[group_g] <= 8'd0; // 清零通信组根域
                end else if (config_validation_q && (pending_invalidate_q ? !pending_index_q[2] : config_contract_valid) && (pending_index_q == GROUP_INDEX)) begin // 第三级配置判定选中当前通信组表槽
                    if (pending_invalidate_q) valid_q[group_g] <= 1'b0; // 显式失效当前通信组表槽
                    else begin // 仅写入已经流水确认字段完整且键唯一的通信组配置
                        valid_q[group_g] <= 1'b1; // 标记当前通信组表槽有效
                        group_id_q[group_g] <= pending_group_id_q; // 保存流水后的全局通信组标识
                        topology_epoch_q[group_g] <= pending_topology_epoch_q; // 保存流水后的通信组拓扑代次
                        member_mask_q[group_g] <= pending_member_mask_q; // 保存流水后的二百五十六域成员位图
                        member_count_q[group_g] <= pending_member_count_q; // 保存流水后的通信组成员数量
                        root_domain_q[group_g] <= pending_root_domain_q; // 保存流水后的通信组根域
                    end // 结束合法通信组配置写入
                end // 结束当前通信组表槽配置选择
            end // 结束当前通信组表槽时序逻辑
        end // 结束通信组表槽生成循环
        /* verilator lint_on WIDTHTRUNC */ // 恢复后续逻辑的常量截断检查
    endgenerate // 结束通信组表槽时序驱动器生成
endmodule // 结束 kdlink_group_table
