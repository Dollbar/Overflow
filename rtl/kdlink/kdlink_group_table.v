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
    output reg query_found_o, // 输出组标识和代次精确命中的状态
    output reg query_local_member_o, // 输出当前域属于通信组的状态
    output reg [255:0] query_member_mask_o, // 输出命中通信组成员位图
    output reg [8:0] query_member_count_o, // 输出命中通信组成员数量
    output reg [7:0] query_root_domain_o, // 输出命中通信组根域
    output reg config_error_o // 输出非法配置或重复精确键 sticky 错误
); // 结束全局通信组表端口声明
    reg valid_q [0:3]; // 保存四个通信组表槽有效位
    reg [31:0] group_id_q [0:3]; // 保存四个全局通信组标识
    reg [7:0] topology_epoch_q [0:3]; // 保存四个通信组拓扑代次
    reg [255:0] member_mask_q [0:3]; // 保存四个通信组二百五十六域成员位图
    reg [8:0] member_count_q [0:3]; // 保存四个通信组成员数量
    reg [7:0] root_domain_q [0:3]; // 保存四个通信组根域
    reg duplicate_key_d; // 标记配置键与另一有效槽重复
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
    reg pending_invalidate_q; // 保存待处理通信组槽失效请求
    reg config_decision_valid_q; // 标记配置合同判定已经流水完成
    reg config_decision_accept_q; // 保存流水后的配置合同接受判定
    wire config_contract_valid; // 标记通信组配置字段和精确键均合法
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
    assign config_ready_o = !config_pending_q && !config_decision_valid_q; // 仅在三级配置校验流水空闲时接受新写入
    assign config_contract_valid = !pending_index_q[2] && (config_computed_member_count != 9'd0) && (pending_member_count_q == config_computed_member_count) && pending_member_mask_q[pending_root_domain_q] && !duplicate_key_d; // 汇总流水后的物理槽范围、精确成员数、根成员和唯一精确键合同
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
    always @(*) begin // 组合完成精确组查询和重复配置键检查
        query_found_o = 1'b0; // 默认通信组查询未命中
        query_local_member_o = 1'b0; // 默认当前域不是通信组成员
        query_member_mask_o = 256'd0; // 默认查询成员位图为空
        query_member_count_o = 9'd0; // 默认查询成员数量为零
        query_root_domain_o = 8'd0; // 默认查询根域为零
        duplicate_key_d = 1'b0; // 默认配置键不与其他槽重复
        for (scan_i = 32'd0; scan_i < 32'd4; scan_i = scan_i + 32'd1) begin // 扫描固定四个通信组表槽
            if (query_valid_i && valid_q[scan_i] && (group_id_q[scan_i] == query_group_id_i) && (topology_epoch_q[scan_i] == query_topology_epoch_i) && !query_found_o) begin // 捕获最低编号精确键命中
                query_found_o = 1'b1; // 标记通信组查询命中
                query_local_member_o = member_mask_q[scan_i][query_local_domain_i]; // 查询当前域成员位
                query_member_mask_o = member_mask_q[scan_i]; // 输出完整通信组成员位图
                query_member_count_o = member_count_q[scan_i]; // 输出通信组成员数量
                query_root_domain_o = root_domain_q[scan_i]; // 输出通信组根域
            end // 结束通信组精确查询命中
            if (valid_q[scan_i] && (scan_i[2:0] != pending_index_q) && (group_id_q[scan_i] == pending_group_id_q) && (topology_epoch_q[scan_i] == pending_topology_epoch_q)) duplicate_key_d = 1'b1; // 检查另一物理槽存在与流水配置重复的精确键
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
            pending_invalidate_q <= 1'b0; // 清除待处理失效请求
            config_decision_valid_q <= 1'b0; // 清除配置合同判定流水有效位
            config_decision_accept_q <= 1'b0; // 清除配置合同接受判定
            for (partial_i = 0; partial_i < 16; partial_i = partial_i + 1) config_partial_count_q[partial_i] <= 5'd0; // 清零成员计数流水边界
        end else if (config_decision_valid_q) begin // 提交第三级配置写入或拒绝结果
            config_decision_valid_q <= 1'b0; // 释放配置合同判定流水
            if (!config_decision_accept_q) config_error_o <= 1'b1; // sticky 记录已经流水判定的非法配置
        end else if (config_pending_q) begin // 在第二级寄存配置合同判定
            config_pending_q <= 1'b0; // 释放成员计数第二级流水
            config_decision_valid_q <= 1'b1; // 标记下周期提交配置判定
            config_decision_accept_q <= pending_invalidate_q ? !pending_index_q[2] : config_contract_valid; // 寄存失效或普通配置的完整合同判定
        end else if (config_valid_i && config_ready_o) begin // 捕获一次通信组配置到第一级流水
            config_pending_q <= 1'b1; // 标记第二级校验将在下一周期提交
            pending_index_q <= config_index_i; // 流水保存物理槽编号
            pending_group_id_q <= config_group_id_i; // 流水保存通信组标识
            pending_topology_epoch_q <= config_topology_epoch_i; // 流水保存拓扑代次
            pending_member_mask_q <= config_member_mask_i; // 流水保存完整成员位图
            pending_member_count_q <= config_member_count_i; // 流水保存声明成员数量
            pending_root_domain_q <= config_root_domain_i; // 流水保存根域
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
                end else if (config_decision_valid_q && config_decision_accept_q && (pending_index_q == GROUP_INDEX)) begin // 第三级配置判定选中当前通信组表槽
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
