module coll_fp32_add_lane ( // 定义十六级 IEEE FP32 RNE 加法流水 lane
    input  wire clk_i, // 接收 reduction 时钟
    input  wire rst_n_i, // 接收低有效异步复位
    input  wire valid_i, // 接收 operand 有效
    input  wire [31:0] a_i, // 接收本地 FP32 operand
    input  wire [31:0] b_i, // 接收远端 FP32 operand
    output wire valid_o, // 指示加法结果有效
    output wire [31:0] result_o // 输出 IEEE FP32 RNE 加法结果
); // 结束端口声明
    reg input_valid_q; // 保存 lane 输入寄存级有效
    reg [31:0] input_a_q; // 保存 lane 输入寄存级 operand A
    reg [31:0] input_b_q; // 保存 lane 输入寄存级 operand B
    reg valid_s0_q; // 保存分类排序级有效
    reg special_s0_q; // 保存分类排序级特殊标志
    reg [31:0] special_result_s0_q; // 保存分类排序级特殊结果
    reg sign_big_s0_q; // 保存较大 magnitude operand 符号
    reg sign_small_s0_q; // 保存较小 magnitude operand 符号
    reg [7:0] exp_big_s0_q; // 保存较大 operand 有效 exponent
    reg [7:0] exp_small_s0_q; // 保存较小 operand 有效 exponent
    reg [23:0] mant_big_s0_q; // 保存较大 operand 尾数
    reg [23:0] mant_small_s0_q; // 保存较小 operand 尾数
    reg valid_align_q; // 保存右移对齐低半级有效
    reg special_align_q; // 传递右移对齐低半级特殊标志
    reg [31:0] special_result_align_q; // 传递右移对齐低半级特殊结果
    reg sign_align_q; // 保存右移对齐低半级结果符号
    reg [7:0] exp_align_q; // 保存右移对齐低半级 exponent
    reg subtract_align_q; // 指示右移对齐低半级执行相减
    reg [26:0] big_align_q; // 保存右移对齐低半级大尾数
    reg [26:0] small_partial_align_q; // 保存低两位移位后的较小尾数
    reg [2:0] shift_high_align_q; // 保存剩余四位倍数右移量
    reg sticky_low_align_q; // 保存低两位移位丢失的 sticky
    reg valid_align4_q; // 保存可选四位右移级有效
    reg special_align4_q; // 传递可选四位右移级特殊标志
    reg [31:0] special_result_align4_q; // 传递可选四位右移级特殊结果
    reg sign_align4_q; // 传递可选四位右移级符号
    reg [7:0] exp_align4_q; // 传递可选四位右移级 exponent
    reg subtract_align4_q; // 传递可选四位右移级相减标志
    reg [26:0] big_align4_q; // 传递较大尾数
    reg [26:0] small_align4_q; // 保存可选四位右移后的较小尾数
    reg [1:0] shift_high_align4_q; // 保存剩余八位倍数右移量
    reg sticky_align4_q; // 保存经过可选四位右移后的 sticky
    reg valid_s1_q; // 保存尾数对齐级有效
    reg special_s1_q; // 传递尾数对齐级特殊标志
    reg [31:0] special_result_s1_q; // 传递尾数对齐级特殊结果
    reg sign_s1_q; // 保存算术结果符号
    reg [7:0] exp_s1_q; // 保存算术结果初始 exponent
    reg subtract_s1_q; // 指示执行 magnitude 相减
    reg [26:0] big_aligned_s1_q; // 保存附加 GRS 的较大尾数
    reg [26:0] small_aligned_s1_q; // 保存右移对齐且合并 sticky 的较小尾数
    reg valid_arith_q; // 保存分段尾数加减候选级有效
    reg special_arith_q; // 传递分段尾数加减候选级特殊标志
    reg [31:0] special_result_arith_q; // 传递分段尾数加减候选级特殊结果
    reg sign_arith_q; // 传递分段尾数加减候选级符号
    reg [7:0] exp_arith_q; // 传递分段尾数加减候选级 exponent
    reg subtract_arith_q; // 保存分段尾数加减类型
    reg [13:0] arithmetic_low_q; // 保存尾数加减低十四位结果
    reg arithmetic_carry_q; // 保存尾数加减低十四位进位或无借位标志
    reg [13:0] arithmetic_high0_q; // 保存尾数加减高十四位无低半进位或借位候选
    reg [13:0] arithmetic_high1_q; // 保存尾数加减高十四位有低半进位或借位候选
    reg [7:0] arithmetic_high_low0_d; // 保存高十四位候选零的低七位结果和进位
    reg [7:0] arithmetic_high_low1_d; // 保存高十四位候选一的低七位结果和进位
    reg [6:0] arithmetic_high_top0_d; // 保存高十四位顶七位无进位候选
    reg [6:0] arithmetic_high_top1_d; // 保存高十四位顶七位有进位候选
    reg [13:0] arithmetic_high0_d; // 保存分段拼接后的高十四位候选零
    reg [13:0] arithmetic_high1_d; // 保存分段拼接后的高十四位候选一
    reg valid_s2_q; // 保存尾数加减级有效
    reg special_s2_q; // 传递尾数加减级特殊标志
    reg [31:0] special_result_s2_q; // 传递尾数加减级特殊结果
    reg sign_s2_q; // 传递尾数加减级符号
    reg [7:0] exp_s2_q; // 传递尾数加减级 exponent
    reg subtract_s2_q; // 传递尾数加减级相减标志
    reg [27:0] arithmetic_s2_q; // 保存对齐尾数加减结果
    reg valid_s3_q; // 保存 LZC 准备级有效
    reg special_s3_q; // 传递 LZC 准备级特殊标志
    reg [31:0] special_result_s3_q; // 传递 LZC 准备级特殊结果
    reg sign_s3_q; // 传递 LZC 准备级符号
    reg [7:0] exp_s3_q; // 传递 LZC 准备级 exponent
    reg subtract_s3_q; // 传递 LZC 准备级相减标志
    reg [27:0] arithmetic_s3_q; // 传递 LZC 准备级算术结果
    reg [7:0] lzc_selected_q; reg [4:0] lzc_base_q; reg [4:0] lzc_s4_q; // 保存 LZC 分组选择和后级编码结果
    reg valid_lzc_q; reg special_lzc_q; reg [31:0] special_result_lzc_q; reg sign_lzc_q; reg [7:0] exp_lzc_q; reg subtract_lzc_q; reg [27:0] arithmetic_lzc_q; // 保存 LZC 后 metadata 对齐级
    reg valid_norm_q; // 保存分段归一化低半级有效
    reg special_norm_q; // 传递分段归一化低半级特殊标志
    reg [31:0] special_result_norm_q; // 传递分段归一化低半级特殊结果
    reg sign_norm_q; // 保存分段归一化低半级符号
    reg [8:0] exp_norm_q; // 保存分段归一化完成后的 exponent
    reg [26:0] mant_partial_norm_q; // 保存归一化低两位移位后的尾数
    reg [2:0] shift_high_norm_q; // 保存归一化剩余四位倍数移位量
    reg subtract_norm_q; // 指示分段归一化处理相减路径
    reg zero_norm_q; // 指示分段归一化输入精确为零
    reg valid_norm_pre_q; reg special_norm_pre_q; reg [31:0] special_result_norm_pre_q; reg sign_norm_pre_q; reg [8:0] exp_norm_pre_q; reg [26:0] norm_base_q; reg [1:0] norm_shift_low_q; reg [2:0] norm_shift_high_q; reg subtract_norm_pre_q; reg zero_norm_pre_q; // 保存归一化移位前级并切断变量移位路径
    reg valid_norm4_q; // 保存可选四位左移级有效
    reg special_norm4_q; // 传递可选四位左移级特殊标志
    reg [31:0] special_result_norm4_q; // 传递可选四位左移级特殊结果
    reg sign_norm4_q; // 传递可选四位左移级符号
    reg [8:0] exp_norm4_q; // 传递可选四位左移级 exponent
    reg [26:0] mant_norm4_q; // 保存可选四位左移后的尾数
    reg [1:0] shift_high_norm4_q; // 保存剩余八位倍数左移量
    reg subtract_norm4_q; // 传递归一化相减路径标志
    reg zero_norm4_q; // 传递精确零标志
    reg valid_s4_q; // 保存归一化级有效
    reg special_s4_q; // 传递归一化级特殊标志
    reg [31:0] special_result_s4_q; // 传递归一化级特殊结果
    reg sign_s4_q; // 保存归一化结果符号
    reg [8:0] exp_s4_q; // 保存归一化 exponent 并允许 overflow
    reg [26:0] mant_grs_s4_q; // 保存含 GRS 的归一化尾数
    reg zero_s4_q; // 指示 magnitude 相减精确为零
    reg valid_round_low_q; // 保存 RNE 低十二位和高位候选级有效
    reg special_round_low_q; // 传递 RNE 分段加法级特殊标志
    reg [31:0] special_result_round_low_q; // 传递 RNE 分段加法级特殊结果
    reg sign_round_low_q; // 保存 RNE 分段加法级结果符号
    reg [8:0] exp_round_low_q; // 保存 RNE 分段加法级 exponent
    reg [11:0] mant_low_round_low_q; // 保存 RNE 尾数低十二位结果
    reg carry_round_low_q; // 保存 RNE 低十二位进位
    reg [12:0] mant_high0_round_low_q; // 保存高十二位无进位候选和顶端扩展位
    reg [12:0] mant_high1_round_low_q; // 保存高十二位有进位候选和顶端扩展位
    reg zero_round_low_q; // 保存 RNE 分段加法级精确零标志
    reg valid_round_q; // 保存舍入加法级有效
    reg special_round_q; // 传递舍入加法级特殊标志
    reg [31:0] special_result_round_q; // 传递舍入加法级特殊结果
    reg sign_round_q; // 保存舍入加法级结果符号
    reg [8:0] exp_round_q; // 保存舍入加法级原始 exponent
    reg [24:0] mant_round_q; // 保存已经执行 RNE 增量的尾数
    reg zero_round_q; // 保存舍入加法级精确零标志
    reg valid_s5_q; // 保存最终打包级有效
    reg [31:0] result_s5_q; // 保存最终 FP32 结果
    reg [31:0] special_result_d; // 保存输入特殊分类组合结果
    reg special_d; // 指示输入可直接产生特殊结果
    reg a_is_nan_d; // 指示 operand A 为 NaN
    reg b_is_nan_d; // 指示 operand B 为 NaN
    reg a_is_inf_d; // 指示 operand A 为 infinity
    reg b_is_inf_d; // 指示 operand B 为 infinity
    reg a_is_zero_d; // 指示 operand A 为 zero
    reg b_is_zero_d; // 指示 operand B 为 zero
    reg a_larger_d; // 指示 operand A magnitude 不小于 B
    reg [7:0] a_exp_eff_d; // 保存 A 对齐用有效 exponent
    reg [7:0] b_exp_eff_d; // 保存 B 对齐用有效 exponent
    reg [7:0] exp_delta_d; // 保存大小 operand exponent 差
    reg [26:0] small_shifted_d; // 保存右移对齐后小尾数
    reg [26:0] small_ext_d; // 保存带 GRS 的小尾数
    reg sticky_d; // 保存对齐 sticky bit
    reg [26:0] small_partial_d; // 保存右移对齐低两位移位结果
    reg [2:0] shift_high_d; // 保存右移对齐剩余高三位
    reg sticky_low_d; // 保存右移对齐低两位丢失 sticky
    reg [26:0] small_align4_d; // 保存可选四位右移组合结果
    reg sticky_align4_d; // 保存可选四位右移后的 sticky
    wire [7:0] lzc_selected_wire; wire [4:0] lzc_base_wire; // 连接二十四位 LZC 分组结果
    reg [4:0] lzc_byte_count_d; // 保存后级八位分组编码结果
    reg [4:0] shift_left_d; // 保存相减归一化实际左移量
    reg [26:0] normalized_add_d; // 保存加法 carry 归一化结果
    reg [26:0] normalized_sub_d; // 保存减法左移归一化结果
    reg [26:0] normalized_shift_d; // 保存归一化后级低位移位结果
    reg [26:0] mant_norm4_d; // 保存可选四位左移组合结果
    reg [12:0] rounded_low_d; // 保存 RNE 低十二位加法和进位
    reg [12:0] rounded_high0_d; // 保存 RNE 高半无低位进位候选
    reg [12:0] rounded_high1_d; // 保存 RNE 高半有低位进位候选
    reg round_up_d; // 指示最终 GRS 满足 RNE 增一
    coll_lzc24 u_lzc (.value_i(arithmetic_s2_q[26:3]), .count_o(), .selected_byte_o(lzc_selected_wire), .base_count_o(lzc_base_wire)); // 并行计算相减尾数分组选择
    assign valid_o = valid_s5_q; // 输出末级有效
    assign result_o = result_s5_q; // 输出末级 FP32 结果
    always @(*) begin // 组合执行输入 FP 分类和 magnitude 比较
        a_is_nan_d = (input_a_q[30:23] == 8'hFF) && (input_a_q[22:0] != 23'd0); // 分类 A NaN
        b_is_nan_d = (input_b_q[30:23] == 8'hFF) && (input_b_q[22:0] != 23'd0); // 分类 B NaN
        a_is_inf_d = (input_a_q[30:23] == 8'hFF) && (input_a_q[22:0] == 23'd0); // 分类 A infinity
        b_is_inf_d = (input_b_q[30:23] == 8'hFF) && (input_b_q[22:0] == 23'd0); // 分类 B infinity
        a_is_zero_d = (input_a_q[30:0] == 31'd0); // 分类 A signed zero
        b_is_zero_d = (input_b_q[30:0] == 31'd0); // 分类 B signed zero
        special_d = a_is_nan_d || b_is_nan_d || a_is_inf_d || b_is_inf_d || a_is_zero_d || b_is_zero_d; // 汇总特殊快速路径
        special_result_d = 32'd0; // 默认特殊结果正零
        if (a_is_nan_d || b_is_nan_d || (a_is_inf_d && b_is_inf_d && input_a_q[31] != input_b_q[31])) special_result_d = 32'h7FC00000; // canonicalize NaN 和相反 infinity
        else if (a_is_inf_d) special_result_d = {input_a_q[31], 8'hFF, 23'd0}; // 传播 A infinity
        else if (b_is_inf_d) special_result_d = {input_b_q[31], 8'hFF, 23'd0}; // 传播 B infinity
        else if (a_is_zero_d && b_is_zero_d) special_result_d = {input_a_q[31] & input_b_q[31], 31'd0}; // RNE 下异号 zero 产生正零
        else if (a_is_zero_d) special_result_d = input_b_q; // 零加 B 精确返回 B
        else if (b_is_zero_d) special_result_d = input_a_q; // A 加零精确返回 A
        a_exp_eff_d = (input_a_q[30:23] == 8'd0) ? 8'd1 : input_a_q[30:23]; // subnormal 对齐 exponent 视为一
        b_exp_eff_d = (input_b_q[30:23] == 8'd0) ? 8'd1 : input_b_q[30:23]; // subnormal 对齐 exponent 视为一
        a_larger_d = (a_exp_eff_d > b_exp_eff_d) || ((a_exp_eff_d == b_exp_eff_d) && ({input_a_q[30:23] != 8'd0, input_a_q[22:0]} >= {input_b_q[30:23] != 8'd0, input_b_q[22:0]})); // 比较 operand magnitude
    end // 结束输入分类组合逻辑
    always @(*) begin // 组合执行 exponent 对齐低两位移位和 sticky 计算
        exp_delta_d = exp_big_s0_q - exp_small_s0_q; // 计算非负 exponent 差
        small_ext_d = {mant_small_s0_q, 3'd0}; // 为较小尾数附加 GRS 位
        small_partial_d = 27'd0; shift_high_d = 3'd0; sticky_low_d = 1'b0; // 默认超大差值时全部移出
        if (exp_delta_d >= 8'd27) begin small_partial_d = 27'd0; shift_high_d = 3'd0; sticky_low_d = |small_ext_d; end else begin // 处理有效二十七位内移位
            shift_high_d = exp_delta_d[4:2]; // 保存四位倍数的剩余移位量
            case (exp_delta_d[1:0]) // 仅执行低两位零至三位右移
                2'd0: begin small_partial_d = small_ext_d; sticky_low_d = 1'b0; end // 不执行低位移位
                2'd1: begin small_partial_d = small_ext_d >> 1; sticky_low_d = small_ext_d[0]; end // 右移一位并收集 sticky
                2'd2: begin small_partial_d = small_ext_d >> 2; sticky_low_d = |small_ext_d[1:0]; end // 右移两位并收集 sticky
                default: begin small_partial_d = small_ext_d >> 3; sticky_low_d = |small_ext_d[2:0]; end // 右移三位并收集 sticky
            endcase // 结束低两位移位选择
        end // 结束有效移位范围选择
    end // 结束 exponent 对齐低半组合逻辑
    always @(*) begin // 组合执行 exponent 对齐可选四位右移
        small_align4_d = small_partial_align_q; sticky_align4_d = sticky_low_align_q; // 默认保持低两位移位结果
        if (shift_high_align_q[0]) begin small_align4_d = small_partial_align_q >> 4; sticky_align4_d = sticky_low_align_q || |small_partial_align_q[3:0]; end // 可选右移四位并累计 sticky
    end // 结束可选四位右移组合逻辑
    always @(*) begin // 组合执行 exponent 对齐剩余八位倍数右移
        case (shift_high_align4_q) // 按八 bit 倍数选择剩余右移
            2'd0: begin small_shifted_d = small_align4_q; sticky_d = sticky_align4_q; end // 不执行剩余右移
            2'd1: begin small_shifted_d = small_align4_q >> 8; sticky_d = sticky_align4_q || |small_align4_q[7:0]; end // 再右移八位
            2'd2: begin small_shifted_d = small_align4_q >> 16; sticky_d = sticky_align4_q || |small_align4_q[15:0]; end // 再右移十六位
            default: begin small_shifted_d = small_align4_q >> 24; sticky_d = sticky_align4_q || |small_align4_q[23:0]; end // 最大再右移二十四位
        endcase // 结束对齐剩余移位选择
        small_shifted_d[0] = small_shifted_d[0] | sticky_d; // 合并全部丢失位到最低 GRS bit
    end // 结束 exponent 对齐剩余组合逻辑
    always @(*) begin // 组合执行已寄存 LZC 后的归一化
        normalized_add_d = arithmetic_lzc_q[26:0]; // 默认保持加法结果低二十七位
        normalized_sub_d = arithmetic_lzc_q[26:0]; // 默认保持减法结果
        shift_left_d = ({3'd0, lzc_s4_q} > (exp_lzc_q - 1'b1)) ? (exp_lzc_q[4:0] - 1'b1) : lzc_s4_q; // 限制左移避免越过最小 normal exponent
        if (subtract_lzc_q && arithmetic_lzc_q[26:0] != 27'd0) normalized_sub_d = arithmetic_lzc_q[26:0]; // 保持相减归一化尾数并将移位延后一拍
        if (!subtract_lzc_q && arithmetic_lzc_q[27]) begin // 检查同号加法 carry
            normalized_add_d = arithmetic_lzc_q[27:1]; // 右移一位归一化 carry
            normalized_add_d[0] = arithmetic_lzc_q[1] | arithmetic_lzc_q[0]; // 保留右移丢失 sticky
        end // 结束加法 carry 归一化
    end // 结束归一化组合逻辑
    always @(*) begin // 组合执行寄存归一化尾数的低位移位
        case (norm_shift_low_q) // 选择零至三位左移
            2'd0: normalized_shift_d = norm_base_q; // 不执行低位移位
            2'd1: normalized_shift_d = norm_base_q << 1; // 左移一位
            2'd2: normalized_shift_d = norm_base_q << 2; // 左移两位
            default: normalized_shift_d = norm_base_q << 3; // 左移三位
        endcase // 结束寄存归一化低位移位选择
    end // 结束归一化后级移位组合逻辑
    always @(*) begin // 组合执行已寄存 LZC 分组的八位内部编码
        lzc_byte_count_d = 5'd0; // 默认全零分组编码
        lzc_byte_count_d[2] = ~(|lzc_selected_q[7:4]); // 前导零达到四位时置最高计数位
        lzc_byte_count_d[1] = ((~(|lzc_selected_q[7:6])) && (lzc_selected_q[5] || lzc_selected_q[4])) || ((~(|lzc_selected_q[7:2])) && (lzc_selected_q[1] || lzc_selected_q[0])); // 并行形成计数中间位
        lzc_byte_count_d[0] = ((!lzc_selected_q[7]) && lzc_selected_q[6]) || ((~(|lzc_selected_q[7:5])) && lzc_selected_q[4]) || ((~(|lzc_selected_q[7:3])) && lzc_selected_q[2]) || ((~(|lzc_selected_q[7:1])) && lzc_selected_q[0]); // 并行形成计数最低位
    end // 结束 LZC 八位内部编码组合逻辑
    always @(*) begin // 组合执行相减归一化可选四位左移
        mant_norm4_d = mant_partial_norm_q; // 默认保持低两位归一化结果
        if (subtract_norm_q && shift_high_norm_q[0]) mant_norm4_d = mant_partial_norm_q << 4; // 可选再左移四位
    end // 结束可选四位左移组合逻辑
    always @(*) begin // 组合执行分段 RNE 候选计算
        round_up_d = mant_grs_s4_q[2] && (mant_grs_s4_q[1] || mant_grs_s4_q[0] || mant_grs_s4_q[3]); // 根据 GRS 和偶数 LSB 判定增一
        rounded_low_d = {1'b0, mant_grs_s4_q[14:3]} + round_up_d; // 独立计算低十二位 RNE 增量和进位
        rounded_high0_d = {1'b0, mant_grs_s4_q[26:15]}; // 并行形成高十二位无进位候选
        rounded_high1_d = {1'b0, mant_grs_s4_q[26:15]} + 1'b1; // 并行形成高十二位有进位候选
    end // 结束分段 RNE 候选组合逻辑
    always @(*) begin // 组合执行高十四位七加七 carry-select 加减
        arithmetic_high_low0_d = 8'd0; arithmetic_high_low1_d = 8'd0; // 默认清零两个低七位候选
        arithmetic_high_top0_d = 7'd0; arithmetic_high_top1_d = 7'd0; // 默认清零两个顶七位候选
        if (!subtract_s1_q) begin // 形成同号加法的分段候选
            arithmetic_high_low0_d = {1'b0, big_aligned_s1_q[20:14]} + {1'b0, small_aligned_s1_q[20:14]}; // 计算高半低七位无进位候选
            arithmetic_high_low1_d = {1'b0, big_aligned_s1_q[20:14]} + {1'b0, small_aligned_s1_q[20:14]} + 8'd1; // 计算高半低七位有进位候选
            arithmetic_high_top0_d = {1'b0, big_aligned_s1_q[26:21]} + {1'b0, small_aligned_s1_q[26:21]}; // 并行计算顶七位无进位候选
            arithmetic_high_top1_d = {1'b0, big_aligned_s1_q[26:21]} + {1'b0, small_aligned_s1_q[26:21]} + 7'd1; // 并行计算顶七位有进位候选
        end else begin // 形成异号相减的二补码分段候选
            arithmetic_high_low0_d = {1'b0, big_aligned_s1_q[20:14]} + {1'b0, ~small_aligned_s1_q[20:14]} + 8'd1; // 计算 A 减 B 的低七位和无借位
            arithmetic_high_low1_d = {1'b0, big_aligned_s1_q[20:14]} + {1'b0, ~small_aligned_s1_q[20:14]}; // 计算 A 减 B 减一的低七位和无借位
            arithmetic_high_top0_d = {1'b0, big_aligned_s1_q[26:21]} + {1'b1, ~small_aligned_s1_q[26:21]}; // 并行计算二补码顶七位无进位候选
            arithmetic_high_top1_d = {1'b0, big_aligned_s1_q[26:21]} + {1'b1, ~small_aligned_s1_q[26:21]} + 7'd1; // 并行计算二补码顶七位有进位候选
        end // 结束加减类型选择
        arithmetic_high0_d = {arithmetic_high_low0_d[7] ? arithmetic_high_top1_d : arithmetic_high_top0_d, arithmetic_high_low0_d[6:0]}; // 用候选零低段进位拼接完整结果
        arithmetic_high1_d = {arithmetic_high_low1_d[7] ? arithmetic_high_top1_d : arithmetic_high_top0_d, arithmetic_high_low1_d[6:0]}; // 用候选一低段进位拼接完整结果
    end // 结束高十四位 carry-select 组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新十六级 FP32 加法流水
        if (!rst_n_i) begin // 检测复位有效
            input_valid_q <= 1'b0; input_a_q <= 32'd0; input_b_q <= 32'd0; // 清零 lane 输入寄存级
            valid_s0_q <= 1'b0; special_s0_q <= 1'b0; special_result_s0_q <= 32'd0; sign_big_s0_q <= 1'b0; sign_small_s0_q <= 1'b0; exp_big_s0_q <= 8'd0; exp_small_s0_q <= 8'd0; mant_big_s0_q <= 24'd0; mant_small_s0_q <= 24'd0; // 清零分类排序级
            valid_align_q <= 1'b0; special_align_q <= 1'b0; special_result_align_q <= 32'd0; sign_align_q <= 1'b0; exp_align_q <= 8'd0; subtract_align_q <= 1'b0; big_align_q <= 27'd0; small_partial_align_q <= 27'd0; shift_high_align_q <= 3'd0; sticky_low_align_q <= 1'b0; // 清零右移对齐低半级
            valid_align4_q <= 1'b0; special_align4_q <= 1'b0; special_result_align4_q <= 32'd0; sign_align4_q <= 1'b0; exp_align4_q <= 8'd0; subtract_align4_q <= 1'b0; big_align4_q <= 27'd0; small_align4_q <= 27'd0; shift_high_align4_q <= 2'd0; sticky_align4_q <= 1'b0; // 清零可选四位右移级
            valid_s1_q <= 1'b0; special_s1_q <= 1'b0; special_result_s1_q <= 32'd0; sign_s1_q <= 1'b0; exp_s1_q <= 8'd0; subtract_s1_q <= 1'b0; big_aligned_s1_q <= 27'd0; small_aligned_s1_q <= 27'd0; // 清零尾数对齐级
            valid_arith_q <= 1'b0; special_arith_q <= 1'b0; special_result_arith_q <= 32'd0; sign_arith_q <= 1'b0; exp_arith_q <= 8'd0; subtract_arith_q <= 1'b0; arithmetic_low_q <= 14'd0; arithmetic_carry_q <= 1'b0; arithmetic_high0_q <= 14'd0; arithmetic_high1_q <= 14'd0; // 清零分段尾数加减候选级
            valid_s2_q <= 1'b0; special_s2_q <= 1'b0; special_result_s2_q <= 32'd0; sign_s2_q <= 1'b0; exp_s2_q <= 8'd0; subtract_s2_q <= 1'b0; arithmetic_s2_q <= 28'd0; // 清零尾数加减级
            valid_s3_q <= 1'b0; special_s3_q <= 1'b0; special_result_s3_q <= 32'd0; sign_s3_q <= 1'b0; exp_s3_q <= 8'd0; subtract_s3_q <= 1'b0; arithmetic_s3_q <= 28'd0; lzc_selected_q <= 8'd0; lzc_base_q <= 5'd24; lzc_s4_q <= 5'd24; // 清零 LZC 分组级
            valid_lzc_q <= 1'b0; special_lzc_q <= 1'b0; special_result_lzc_q <= 32'd0; sign_lzc_q <= 1'b0; exp_lzc_q <= 8'd0; subtract_lzc_q <= 1'b0; arithmetic_lzc_q <= 28'd0; // 清零 LZC 后 metadata 对齐级
            valid_norm_pre_q <= 1'b0; special_norm_pre_q <= 1'b0; special_result_norm_pre_q <= 32'd0; sign_norm_pre_q <= 1'b0; exp_norm_pre_q <= 9'd0; norm_base_q <= 27'd0; norm_shift_low_q <= 2'd0; norm_shift_high_q <= 3'd0; subtract_norm_pre_q <= 1'b0; zero_norm_pre_q <= 1'b0; // 清零归一化移位前级
            valid_norm_q <= 1'b0; special_norm_q <= 1'b0; special_result_norm_q <= 32'd0; sign_norm_q <= 1'b0; exp_norm_q <= 9'd0; mant_partial_norm_q <= 27'd0; shift_high_norm_q <= 3'd0; subtract_norm_q <= 1'b0; zero_norm_q <= 1'b0; // 清零分段归一化低半级
            valid_norm4_q <= 1'b0; special_norm4_q <= 1'b0; special_result_norm4_q <= 32'd0; sign_norm4_q <= 1'b0; exp_norm4_q <= 9'd0; mant_norm4_q <= 27'd0; shift_high_norm4_q <= 2'd0; subtract_norm4_q <= 1'b0; zero_norm4_q <= 1'b0; // 清零可选四位左移级
            valid_s4_q <= 1'b0; special_s4_q <= 1'b0; special_result_s4_q <= 32'd0; sign_s4_q <= 1'b0; exp_s4_q <= 9'd0; mant_grs_s4_q <= 27'd0; zero_s4_q <= 1'b0; // 清零归一化级
            valid_round_low_q <= 1'b0; special_round_low_q <= 1'b0; special_result_round_low_q <= 32'd0; sign_round_low_q <= 1'b0; exp_round_low_q <= 9'd0; mant_low_round_low_q <= 12'd0; carry_round_low_q <= 1'b0; mant_high0_round_low_q <= 13'd0; mant_high1_round_low_q <= 13'd0; zero_round_low_q <= 1'b0; // 清零 RNE 分段候选级
            valid_round_q <= 1'b0; special_round_q <= 1'b0; special_result_round_q <= 32'd0; sign_round_q <= 1'b0; exp_round_q <= 9'd0; mant_round_q <= 25'd0; zero_round_q <= 1'b0; // 清零独立舍入加法级
            valid_s5_q <= 1'b0; result_s5_q <= 32'd0; // 清零最终打包级
        end else begin // 处理 FP32 加法流水正常运行
            input_valid_q <= valid_i; input_a_q <= a_i; input_b_q <= b_i; // 锁存 lane 输入切断外部分类路径
            valid_s0_q <= input_valid_q; special_s0_q <= special_d; special_result_s0_q <= special_result_d; // 锁存输入分类结果
            sign_big_s0_q <= a_larger_d ? input_a_q[31] : input_b_q[31]; sign_small_s0_q <= a_larger_d ? input_b_q[31] : input_a_q[31]; // 锁存排序后符号
            exp_big_s0_q <= a_larger_d ? a_exp_eff_d : b_exp_eff_d; exp_small_s0_q <= a_larger_d ? b_exp_eff_d : a_exp_eff_d; // 锁存排序后 exponent
            mant_big_s0_q <= a_larger_d ? {input_a_q[30:23] != 8'd0, input_a_q[22:0]} : {input_b_q[30:23] != 8'd0, input_b_q[22:0]}; // 锁存较大尾数
            mant_small_s0_q <= a_larger_d ? {input_b_q[30:23] != 8'd0, input_b_q[22:0]} : {input_a_q[30:23] != 8'd0, input_a_q[22:0]}; // 锁存较小尾数
            valid_align_q <= valid_s0_q; special_align_q <= special_s0_q; special_result_align_q <= special_result_s0_q; // 传递右移对齐低半级控制
            sign_align_q <= sign_big_s0_q; exp_align_q <= exp_big_s0_q; subtract_align_q <= sign_big_s0_q != sign_small_s0_q; // 锁存右移对齐低半级算术 metadata
            big_align_q <= {mant_big_s0_q, 3'd0}; small_partial_align_q <= small_partial_d; shift_high_align_q <= shift_high_d; sticky_low_align_q <= sticky_low_d; // 锁存低两位移位结果和剩余移位量
            valid_align4_q <= valid_align_q; special_align4_q <= special_align_q; special_result_align4_q <= special_result_align_q; // 传递可选四位右移级控制
            sign_align4_q <= sign_align_q; exp_align4_q <= exp_align_q; subtract_align4_q <= subtract_align_q; big_align4_q <= big_align_q; // 传递可选四位右移级 metadata 和大尾数
            small_align4_q <= small_align4_d; shift_high_align4_q <= shift_high_align_q[2:1]; sticky_align4_q <= sticky_align4_d; // 锁存四位移位结果和剩余八位倍数
            valid_s1_q <= valid_align4_q; special_s1_q <= special_align4_q; special_result_s1_q <= special_result_align4_q; // 传递尾数对齐剩余级控制
            sign_s1_q <= sign_align4_q; exp_s1_q <= exp_align4_q; subtract_s1_q <= subtract_align4_q; // 锁存对齐剩余级算术 metadata
            big_aligned_s1_q <= big_align4_q; small_aligned_s1_q <= small_shifted_d; // 锁存完成分段对齐的两条尾数
            valid_arith_q <= valid_s1_q; special_arith_q <= special_s1_q; special_result_arith_q <= special_result_s1_q; sign_arith_q <= sign_s1_q; exp_arith_q <= exp_s1_q; subtract_arith_q <= subtract_s1_q; // 传递分段尾数加减候选级 metadata
            if (!subtract_s1_q) begin // 并行形成同号尾数加法候选
                {arithmetic_carry_q, arithmetic_low_q} <= {1'b0, big_aligned_s1_q[13:0]} + {1'b0, small_aligned_s1_q[13:0]}; // 计算低十四位和进位
                arithmetic_high0_q <= arithmetic_high0_d; // 锁存七加七 carry-select 高半无进位候选
                arithmetic_high1_q <= arithmetic_high1_d; // 锁存七加七 carry-select 高半有进位候选
            end else begin // 并行形成异号 magnitude 相减候选
                {arithmetic_carry_q, arithmetic_low_q} <= {1'b0, big_aligned_s1_q[13:0]} + {1'b0, ~small_aligned_s1_q[13:0]} + 15'd1; // 计算低十四位差和无借位标志
                arithmetic_high0_q <= arithmetic_high0_d; // 锁存七加七 carry-select 高半无借位候选
                arithmetic_high1_q <= arithmetic_high1_d; // 锁存七加七 carry-select 高半有借位候选
            end // 结束分段尾数加减候选形成
            valid_s2_q <= valid_arith_q; special_s2_q <= special_arith_q; special_result_s2_q <= special_result_arith_q; // 传递尾数加减结果级控制
            sign_s2_q <= sign_arith_q; exp_s2_q <= exp_arith_q; subtract_s2_q <= subtract_arith_q; // 传递尾数加减结果级 metadata
            if (!subtract_arith_q) arithmetic_s2_q <= {arithmetic_carry_q ? arithmetic_high1_q : arithmetic_high0_q, arithmetic_low_q}; else arithmetic_s2_q <= {arithmetic_carry_q ? arithmetic_high0_q : arithmetic_high1_q, arithmetic_low_q}; // 选择高半候选形成完整尾数加减结果
            valid_s3_q <= valid_s2_q; special_s3_q <= special_s2_q; special_result_s3_q <= special_result_s2_q; // 传递 LZC 准备级控制
            sign_s3_q <= sign_s2_q; exp_s3_q <= exp_s2_q; subtract_s3_q <= subtract_s2_q; arithmetic_s3_q <= arithmetic_s2_q; lzc_selected_q <= lzc_selected_wire; lzc_base_q <= lzc_base_wire; // 寄存 LZC 分组选择和算术结果
            lzc_s4_q <= (lzc_base_q == 5'd24) ? 5'd24 : lzc_base_q + lzc_byte_count_d; // 拼接完整前导零数量
            valid_lzc_q <= valid_s3_q; special_lzc_q <= special_s3_q; special_result_lzc_q <= special_result_s3_q; sign_lzc_q <= sign_s3_q; exp_lzc_q <= exp_s3_q; subtract_lzc_q <= subtract_s3_q; arithmetic_lzc_q <= arithmetic_s3_q; // 对齐 LZC 后 metadata
            valid_norm_pre_q <= valid_lzc_q; special_norm_pre_q <= special_lzc_q; special_result_norm_pre_q <= special_result_lzc_q; sign_norm_pre_q <= sign_lzc_q; subtract_norm_pre_q <= subtract_lzc_q; // 传递归一化移位前级控制
            zero_norm_pre_q <= subtract_lzc_q && arithmetic_lzc_q[26:0] == 27'd0; // 检查精确 cancellation
            if (!subtract_lzc_q) begin // 处理同号加法归一化
                norm_base_q <= normalized_add_d; norm_shift_low_q <= 2'd0; norm_shift_high_q <= 3'd0; // 锁存加法归一化尾数且无需剩余移位
                if (arithmetic_lzc_q[27]) exp_norm_pre_q <= {1'b0, exp_lzc_q} + 1'b1; else if (exp_lzc_q == 8'd1 && !normalized_add_d[26]) exp_norm_pre_q <= 9'd0; else exp_norm_pre_q <= {1'b0, exp_lzc_q}; // 计算加法归一化 exponent
            end else begin // 处理异号 magnitude 相减归一化
                norm_base_q <= normalized_sub_d; norm_shift_low_q <= shift_left_d[1:0]; norm_shift_high_q <= shift_left_d[4:2]; // 锁存相减归一化尾数和分段移位量
                if ({3'd0, lzc_s4_q} >= exp_lzc_q) exp_norm_pre_q <= 9'd0; else exp_norm_pre_q <= {1'b0, exp_lzc_q} - {4'd0, shift_left_d}; // 计算相减归一化 exponent
            end // 结束归一化类型选择
            valid_norm_q <= valid_norm_pre_q; special_norm_q <= special_norm_pre_q; special_result_norm_q <= special_result_norm_pre_q; sign_norm_q <= sign_norm_pre_q; exp_norm_q <= exp_norm_pre_q; subtract_norm_q <= subtract_norm_pre_q; zero_norm_q <= zero_norm_pre_q; // 传递归一化后级 metadata
            mant_partial_norm_q <= normalized_shift_d; shift_high_norm_q <= norm_shift_high_q; // 锁存已执行低位移位的归一化尾数和剩余移位量
            valid_norm4_q <= valid_norm_q; special_norm4_q <= special_norm_q; special_result_norm4_q <= special_result_norm_q; sign_norm4_q <= sign_norm_q; exp_norm4_q <= exp_norm_q; // 传递可选四位左移级控制和 exponent
            mant_norm4_q <= mant_norm4_d; shift_high_norm4_q <= shift_high_norm_q[2:1]; subtract_norm4_q <= subtract_norm_q; zero_norm4_q <= zero_norm_q; // 锁存可选四位左移结果和剩余八位倍数
            valid_s4_q <= valid_norm4_q; special_s4_q <= special_norm4_q; special_result_s4_q <= special_result_norm4_q; sign_s4_q <= sign_norm4_q; exp_s4_q <= exp_norm4_q; zero_s4_q <= zero_norm4_q; // 传递归一化剩余级控制和 exponent
            if (!subtract_norm4_q) mant_grs_s4_q <= mant_norm4_q; else begin // 完成相减归一化剩余八位倍数移位
                case (shift_high_norm4_q) // 按八 bit 倍数选择剩余归一化移位
                    2'd0: mant_grs_s4_q <= mant_norm4_q; // 不执行剩余移位
                    2'd1: mant_grs_s4_q <= mant_norm4_q << 8; // 再左移八位
                    2'd2: mant_grs_s4_q <= mant_norm4_q << 16; // 再左移十六位
                    default: mant_grs_s4_q <= mant_norm4_q << 24; // 最大再左移二十四位
                endcase // 结束归一化剩余移位选择
            end // 结束相减归一化高半处理
            valid_round_low_q <= valid_s4_q; special_round_low_q <= special_s4_q; special_result_round_low_q <= special_result_s4_q; // 将特殊路径传入 RNE 分段候选级
            sign_round_low_q <= sign_s4_q; exp_round_low_q <= exp_s4_q; mant_low_round_low_q <= rounded_low_d[11:0]; carry_round_low_q <= rounded_low_d[12]; // 锁存 RNE 低半结果和进位
            mant_high0_round_low_q <= rounded_high0_d; mant_high1_round_low_q <= rounded_high1_d; zero_round_low_q <= zero_s4_q || mant_grs_s4_q == 27'd0; // 锁存高半候选和精确零标志
            valid_round_q <= valid_round_low_q; special_round_q <= special_round_low_q; special_result_round_q <= special_result_round_low_q; // 将 RNE 候选传入高半选择级
            sign_round_q <= sign_round_low_q; exp_round_q <= exp_round_low_q; mant_round_q <= {carry_round_low_q ? mant_high1_round_low_q : mant_high0_round_low_q, mant_low_round_low_q}; zero_round_q <= zero_round_low_q; // 选择高半候选并形成二十五位舍入尾数
            valid_s5_q <= valid_round_q; // 将舍入结果传入最终打包级
            if (special_round_q) result_s5_q <= special_result_round_q; // 输出特殊快速路径结果
            else if (zero_round_q) result_s5_q <= 32'd0; // cancellation 输出正零
            else if ((exp_round_q + mant_round_q[24]) >= 9'd255) result_s5_q <= {sign_round_q, 8'hFF, 23'd0}; // overflow 输出 infinity
            else if (exp_round_q == 9'd0 && mant_round_q[23]) result_s5_q <= {sign_round_q, 8'd1, mant_round_q[22:0]}; // subnormal 舍入成为最小 normal
            else if (mant_round_q[24]) result_s5_q <= {sign_round_q, exp_round_q[7:0] + 1'b1, mant_round_q[23:1]}; // 尾数 carry 后右移一位
            else result_s5_q <= {sign_round_q, exp_round_q[7:0], mant_round_q[22:0]}; // 输出普通 normal 或 subnormal 结果
        end // 结束 FP32 加法流水复位选择
    end // 结束 FP32 加法流水时序逻辑
endmodule // 结束十六级 IEEE FP32 加法 lane
