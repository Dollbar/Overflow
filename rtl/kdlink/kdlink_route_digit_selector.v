module kdlink_route_digit_selector #( // 定义一至五级 radix-8 目的域数位选择器
    parameter integer DOMAIN_COUNT = 32768, // 指定活动 leaf 域数量
    parameter integer STAGE_INDEX = 0 // 指定从根向 leaf 的零起始路由级
) ( // 开始路由数位选择器端口声明
    input wire [14:0] destination_domain_i, // 接收十五位目的 leaf 域
    input wire [7:0] active_egress_mask_i, // 接收当前级八出口可用掩码
    output reg [2:0] selected_egress_o, // 输出当前级确定性 radix-8 数位
    output wire profile_valid_o, // 输出参数化 profile 合法状态
    output wire destination_valid_o, // 输出目的域属于活动范围状态
    output wire selected_egress_active_o, // 输出确定性出口可用状态
    output wire final_stage_o, // 输出当前级紧邻目的 leaf 状态
    output wire [2:0] remaining_stages_o, // 输出含当前级在内的剩余级数
    output wire [2:0] escape_rank_o // 输出单调递增 escape 依赖等级
); // 结束路由数位选择器端口声明
    localparam integer STAGE_COUNT = (DOMAIN_COUNT <= 8) ? 1 : ((DOMAIN_COUNT <= 64) ? 2 : ((DOMAIN_COUNT <= 512) ? 3 : ((DOMAIN_COUNT <= 4096) ? 4 : 5))); // 计算活动 radix-8 路由深度
    localparam [15:0] DOMAIN_LIMIT = DOMAIN_COUNT[15:0]; // 将域数量冻结为无符号十六位比较界限
    localparam [2:0] STAGE_COUNT_VALUE = (STAGE_COUNT == 5) ? 3'd5 : ((STAGE_COUNT == 4) ? 3'd4 : ((STAGE_COUNT == 3) ? 3'd3 : ((STAGE_COUNT == 2) ? 3'd2 : 3'd1))); // 将整数级数安全转换为三位常量
    localparam [2:0] STAGE_INDEX_VALUE = (STAGE_INDEX == 4) ? 3'd4 : ((STAGE_INDEX == 3) ? 3'd3 : ((STAGE_INDEX == 2) ? 3'd2 : ((STAGE_INDEX == 1) ? 3'd1 : 3'd0))); // 将整数级编号安全转换为三位常量
    localparam [2:0] REMAINING_STAGES = STAGE_COUNT_VALUE - STAGE_INDEX_VALUE; // 冻结含当前级在内的剩余级数
    localparam [2:0] ESCAPE_RANK = STAGE_INDEX_VALUE + 3'd1; // 冻结当前级单调 escape 等级
    assign profile_valid_o = (DOMAIN_COUNT >= 2) && (DOMAIN_COUNT <= 32768) && (STAGE_INDEX >= 0) && (STAGE_INDEX < STAGE_COUNT); // 检查域数量和当前级参数范围
    assign destination_valid_o = {1'b0, destination_domain_i} < DOMAIN_LIMIT; // 检查目的域属于活动 profile
    assign selected_egress_active_o = active_egress_mask_i[selected_egress_o]; // 检查确定性数位对应出口可用
    assign final_stage_o = STAGE_INDEX == (STAGE_COUNT - 1); // 指示当前级是否为最后 radix-8 级
    assign remaining_stages_o = REMAINING_STAGES; // 输出剩余级数常量
    assign escape_rank_o = ESCAPE_RANK; // 输出当前级 escape 等级常量
    always @(*) begin // 按活动深度和当前级选择目的域三位数位
        selected_egress_o = 3'd0; // 默认选择零号出口以覆盖非法参数
        case (STAGE_COUNT) // 按一至五级 profile 选择位段
            1: selected_egress_o = destination_domain_i[2:0]; // 单级 profile 消费最低三位
            2: begin // 两级 profile 消费六位目的域
                if (STAGE_INDEX == 0) selected_egress_o = destination_domain_i[5:3]; // 第零级消费高三位
                else selected_egress_o = destination_domain_i[2:0]; // 第一层消费低三位
            end // 结束两级 profile 数位选择
            3: begin // 三级 profile 消费九位目的域
                if (STAGE_INDEX == 0) selected_egress_o = destination_domain_i[8:6]; // 第零级消费最高三位
                else if (STAGE_INDEX == 1) selected_egress_o = destination_domain_i[5:3]; // 第一层消费中间三位
                else selected_egress_o = destination_domain_i[2:0]; // 第二层消费最低三位
            end // 结束三级 profile 数位选择
            4: begin // 四级 profile 消费十二位目的域
                if (STAGE_INDEX == 0) selected_egress_o = destination_domain_i[11:9]; // 第零级消费最高三位
                else if (STAGE_INDEX == 1) selected_egress_o = destination_domain_i[8:6]; // 第一层消费次高三位
                else if (STAGE_INDEX == 2) selected_egress_o = destination_domain_i[5:3]; // 第二层消费次低三位
                else selected_egress_o = destination_domain_i[2:0]; // 第三层消费最低三位
            end // 结束四级 profile 数位选择
            5: begin // 五级 profile 消费完整十五位目的域
                if (STAGE_INDEX == 0) selected_egress_o = destination_domain_i[14:12]; // 第零级消费位十四至十二
                else if (STAGE_INDEX == 1) selected_egress_o = destination_domain_i[11:9]; // 第一层消费位十一至九
                else if (STAGE_INDEX == 2) selected_egress_o = destination_domain_i[8:6]; // 第二层消费位八至六
                else if (STAGE_INDEX == 3) selected_egress_o = destination_domain_i[5:3]; // 第三层消费位五至三
                else selected_egress_o = destination_domain_i[2:0]; // 第四层消费最低三位
            end // 结束五级 profile 数位选择
            /* verilator coverage_off */ // STRUCTURAL: STAGE_COUNT is a compile-time ternary constrained to one through five.
            default: selected_egress_o = 3'd0; // 非法深度保持安全零出口
            /* verilator coverage_on */
        endcase // 结束活动深度选择
    end // 结束 radix-8 数位组合逻辑
endmodule // 结束 kdlink_route_digit_selector
