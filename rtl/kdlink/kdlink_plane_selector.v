module kdlink_plane_selector ( // 定义八平面故障感知注入选择器
    input wire [63:0] global_transaction_id_i, // 接收用于稳定散列的全局事务标识
    input wire [7:0] active_plane_mask_i, // 接收当前拓扑代次活动平面掩码
    input wire [7:0] failed_plane_mask_i, // 接收实时故障平面掩码
    input wire adaptive_enable_i, // 接收允许使用 plane1 至 plane7 指示
    input wire force_escape_i, // 接收强制确定性 escape 路径指示
    output reg selection_valid_o, // 输出存在安全可用平面状态
    output reg [2:0] selected_plane_o, // 输出选中的逻辑平面
    output reg escape_selected_o, // 输出本次选择使用 plane0 状态
    output reg adaptive_fallback_o // 输出自适应平面不可用而回退 escape 状态
); // 结束八平面选择器端口声明
    wire [7:0] available_mask; // 汇总已配置且未故障的平面
    reg adaptive_found_d; // 标记旋转扫描找到 plane1 至 plane7
    reg [2:0] candidate_plane_d; // 保存当前旋转扫描候选平面
    integer scan_i; // 声明最多七平面组合扫描变量
    assign available_mask = active_plane_mask_i & ~failed_plane_mask_i; // 排除当前拓扑未启用或已故障平面
    always @(*) begin // 优先稳定散列自适应平面并保留 plane0 escape 回退
        selection_valid_o = 1'b0; // 默认没有安全可用平面
        selected_plane_o = 3'd0; // 默认选择确定性 escape 平面
        escape_selected_o = 1'b0; // 默认尚未选中 escape
        adaptive_fallback_o = 1'b0; // 默认未发生自适应回退
        adaptive_found_d = 1'b0; // 默认未找到自适应平面
        candidate_plane_d = 3'd1; // 默认候选从一号平面开始
        if (adaptive_enable_i && !force_escape_i) begin // 普通注入优先使用 plane1 至 plane7
            for (scan_i = 0; scan_i < 7; scan_i = scan_i + 1) begin // 从事务散列起点旋转扫描七个自适应平面
                /* verilator lint_off WIDTHEXPAND */ // 扫描变量范围零至六且模七结果已证明适合三位平面编号
                /* verilator lint_off WIDTHTRUNC */ // 扫描变量范围零至六且模七结果已证明适合三位平面编号
                candidate_plane_d = ((global_transaction_id_i[2:0] + scan_i) % 7) + 1; // 将散列候选严格限制到一至七号平面
                /* verilator lint_on WIDTHTRUNC */ // 恢复后续组合逻辑截断检查
                /* verilator lint_on WIDTHEXPAND */ // 恢复后续组合逻辑扩展检查
                if (!adaptive_found_d && available_mask[candidate_plane_d]) begin // 捕获第一个未故障自适应平面
                    adaptive_found_d = 1'b1; // 停止后续候选覆盖
                    selection_valid_o = 1'b1; // 报告找到安全平面
                    selected_plane_o = candidate_plane_d; // 输出稳定旋转扫描结果
                end // 结束自适应平面捕获
            end // 结束七平面旋转扫描
            if (!adaptive_found_d && available_mask[0]) begin // 所有自适应平面失效时回退确定性 escape
                selection_valid_o = 1'b1; selected_plane_o = 3'd0; escape_selected_o = 1'b1; adaptive_fallback_o = 1'b1; // 报告安全回退 plane0
            end // 结束 escape 回退
        end else if (available_mask[0]) begin // 强制 escape 或禁用自适应时仅允许 plane0
            selection_valid_o = 1'b1; selected_plane_o = 3'd0; escape_selected_o = 1'b1; // 选择确定性 escape 平面
        end // 结束强制 escape 选择
    end // 结束故障感知平面组合选择
endmodule // 结束 kdlink_plane_selector
