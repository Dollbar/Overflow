module formal_scale_route_control; // 定义五级数位与 escape 转换组合形式属性
    (* anyconst *) reg [14:0] destination_domain; // 任取完整十五位目的 leaf 域
    (* anyconst *) reg [7:0] active_egress_mask; // 任取当前级出口可用掩码
    (* anyconst *) reg [2:0] current_plane; // 任取当前平面
    (* anyconst *) reg [2:0] next_plane; // 任取下一跳平面
    (* anyconst *) reg [2:0] current_rank; // 任取当前 escape 等级
    (* anyconst *) reg [2:0] next_rank; // 任取下一 escape 等级
    wire [2:0] digit0; wire [2:0] digit1; wire [2:0] digit2; wire [2:0] digit3; wire [2:0] digit4; // 观察五级 radix-8 数位
    wire final0; wire final4; wire [2:0] remaining0; wire [2:0] remaining4; wire [2:0] rank0; wire [2:0] rank4; // 观察边界层次元数据
    wire transition_allowed; wire escape_monotonic; // 观察无死锁转换判定
    kdlink_route_digit_selector #(.DOMAIN_COUNT(32768), .STAGE_INDEX(0)) u0 ( // 实例化满规模根级数位选择器
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit0), // 连接目的域和根级数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(), .final_stage_o(final0), .remaining_stages_o(remaining0), .escape_rank_o(rank0) // 观察根级元数据
    ); // 结束根级实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(32768), .STAGE_INDEX(1)) u1 ( // 实例化第二级数位选择器
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit1), // 连接第二级数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 忽略已在边界级证明的元数据
    ); // 结束第二级实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(32768), .STAGE_INDEX(2)) u2 ( // 实例化第三级数位选择器
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit2), // 连接第三级数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 忽略中间级元数据
    ); // 结束第三级实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(32768), .STAGE_INDEX(3)) u3 ( // 实例化第四级数位选择器
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit3), // 连接第四级数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(), .final_stage_o(), .remaining_stages_o(), .escape_rank_o() // 忽略中间级元数据
    ); // 结束第四级实例
    kdlink_route_digit_selector #(.DOMAIN_COUNT(32768), .STAGE_INDEX(4)) u4 ( // 实例化第五级数位选择器
        .destination_domain_i(destination_domain), .active_egress_mask_i(active_egress_mask), .selected_egress_o(digit4), // 连接末级数位
        .profile_valid_o(), .destination_valid_o(), .selected_egress_active_o(), .final_stage_o(final4), .remaining_stages_o(remaining4), .escape_rank_o(rank4) // 观察末级元数据
    ); // 结束第五级实例
    kdlink_deadlock_guard u_guard ( // 实例化 adaptive 至 escape 单向转换检查器
        .current_plane_i(current_plane), .next_plane_i(next_plane), .current_escape_rank_i(current_rank), .next_escape_rank_i(next_rank), // 连接任意平面和等级
        .transition_allowed_o(transition_allowed), .escape_monotonic_o(escape_monotonic) // 观察转换合同
    ); // 结束无死锁检查器实例
    always @(*) begin // 对全部任意输入证明位级和依赖不变量
        assert ({digit0, digit1, digit2, digit3, digit4} == destination_domain); // 五级 radix-8 数位必须无损重构十五位目的域
        assert (!final0 && final4 && (remaining0 == 3'd5) && (remaining4 == 3'd1)); // 根末级边界和剩余深度必须冻结
        assert ((rank0 == 3'd1) && (rank4 == 3'd5)); // escape 等级必须随级号严格增长
        if (transition_allowed && (current_plane == 3'd0)) assert ((next_plane == 3'd0) && escape_monotonic); // escape 内不得返回 adaptive 且等级必须递增
        if (transition_allowed && (current_plane != 3'd0) && (next_plane != current_plane)) assert ((next_plane == 3'd0) && escape_monotonic); // adaptive 跨平面只能单向进入 escape
    end // 结束组合形式断言
endmodule // 结束 formal_scale_route_control
