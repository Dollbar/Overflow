`timescale 1ns/1ps // 定义FP32内部加减结果规格化模块的仿真时间单位与时间精度

module fp32_normalize ( // 定义二十八位加减结果的前导零检测和规格化组合模块
    input  logic        [27:0] magnitude_i, // 输入保留最高进位的二十八位加减结果幅值
    input  logic signed [10:0] exponent_i, // 输入对阶后的共同无偏指数
    output logic        [26:0] significand_o, // 输出带Guard、Round和Sticky位的规格化有效数
    output logic signed [10:0] exponent_o, // 输出根据右移或前导零数量修正后的无偏指数
    output logic               zero_o // 输出加减结果精确为零的分类标志
); // 结束fp32_normalize端口声明

logic [27:0] normalize_padded_comb; // 保存低位补零后便于按七个半字节并行处理的二十八位幅值
logic [5:0] normalize_group_nonzero_comb; // 标识最高六个四位分块中是否至少包含一个有效一
logic [27:0] normalize_candidate_comb [0:6]; // 保存七个四位分块各自完成局部规格化后的候选结果
logic [1:0] normalize_local_shift_comb [0:6]; // 保存七个四位分块各自计算的零到三位局部移位量
logic [4:0] normalize_shift_candidate_comb [0:6]; // 保存七个分块的完整前导零数量候选
logic [27:0] normalize_candidate01_comb; // 保存最高两个分块之间的候选选择结果
logic [27:0] normalize_candidate23_comb; // 保存第三和第四分块之间的候选选择结果
logic [27:0] normalize_candidate45_comb; // 保存第五和第六分块之间的候选选择结果
logic [27:0] normalize_candidate03_comb; // 保存最高四个分块之间的候选选择结果
logic [27:0] normalize_candidate46_comb; // 保存最低三个分块之间的候选选择结果
logic [27:0] normalize_selected_comb; // 保存三层分块选择后的最终二十八位规格化结果
logic [4:0] normalize_shift01_comb; // 保存最高两个分块之间的移位量选择结果
logic [4:0] normalize_shift23_comb; // 保存第三和第四分块之间的移位量选择结果
logic [4:0] normalize_shift45_comb; // 保存第五和第六分块之间的移位量选择结果
logic [4:0] normalize_shift03_comb; // 保存最高四个分块之间的移位量选择结果
logic [4:0] normalize_shift46_comb; // 保存最低三个分块之间的移位量选择结果
logic [4:0] normalize_shift_selected_comb; // 保存三层分块选择后的总前导零数量

assign normalize_padded_comb = {magnitude_i[26:0], 1'b0}; // 将二十七位幅值最高位对齐到七个完整四位分块

generate // 为七个四位分块并行建立两层局部LZC和两层固定左移网络
    for (genvar group_index = 0; group_index < 7; group_index++) begin : g_normalize_group // 逐个展开互不串联的四位候选规格化路径
        localparam int COARSE_SHIFT = group_index * 4; // 定义当前分块成为最高非零块时需要的四位粗移位量
        localparam logic [2:0] COARSE_CODE = group_index; // 将四位粗移位倍数编码为总移位量高三位
        logic [3:0] local_group_comb; // 保存当前候选路径负责检查的完整四位分块
        /* verilator lint_off UNUSEDSIGNAL */ // 保留两位组低位以维持平衡多输出综合结构
        logic [1:0] local_pair_comb; // 保存当前分块LZC选择出的完整两位组
        /* verilator lint_on UNUSEDSIGNAL */ // 恢复未使用信号检查
        logic [27:0] local_base_comb; // 保存当前分块固定粗移位后的二十八位数据
        logic [27:0] local_stage2_comb; // 保存当前候选执行可选两位左移后的结果

        always_comb begin // 在当前四位分块内使用两层平衡树计算局部前导零数量
            local_group_comb = normalize_padded_comb[27-(group_index*4) -: 4]; // 提取当前候选对应的完整四位分块
            normalize_local_shift_comb[group_index] = 2'd0; // 默认当前分块最高位即为一
            local_pair_comb = local_group_comb[3:2]; // 默认在当前分块高两位继续定位
            if (!(|local_group_comb[3:2])) begin // 当前分块高两位全零时选择低两位
                normalize_local_shift_comb[group_index][1] = 1'b1; // 记录局部规格化需要左移两位
                local_pair_comb = local_group_comb[1:0]; // 将完整低两位送入最后一级定位
            end // 结束当前分块两位级LZC选择
            normalize_local_shift_comb[group_index][0] = !local_pair_comb[1]; // 最后两位的高位为零时再左移一位
            normalize_shift_candidate_comb[group_index] = {COARSE_CODE, normalize_local_shift_comb[group_index]}; // 拼接当前分块粗移位和局部移位量
        end // 结束当前四位分块局部LZC逻辑

        always_comb begin // 使用局部LZC结果并行形成当前分块对应的完整规格化候选
            local_base_comb = normalize_padded_comb << COARSE_SHIFT; // 使用常量移位先把当前分块提升到最高半字节
            local_stage2_comb = local_base_comb; // 默认旁路两位局部移位级
            if (normalize_local_shift_comb[group_index][1]) begin // 局部移位量包含两位时执行固定左移
                local_stage2_comb = {local_base_comb[25:0], 2'b00}; // 用固定拼接完成两位左移
            end // 结束当前候选两位移位级
            normalize_candidate_comb[group_index] = local_stage2_comb; // 默认旁路一位局部移位级
            if (normalize_local_shift_comb[group_index][0]) begin // 局部移位量包含一位时执行固定左移
                normalize_candidate_comb[group_index] = {local_stage2_comb[26:0], 1'b0}; // 用固定拼接完成一位左移
            end // 结束当前候选一位移位级
        end // 结束当前四位分块候选移位逻辑
    end // 结束单个四位分块候选生成
endgenerate // 结束七路并行候选规格化网络

always_comb begin // 使用平衡三层七选一网络选择最高非零分块对应的候选和总移位量
    normalize_group_nonzero_comb[5] = |normalize_padded_comb[7:4]; // 判定第六个四位分块是否非零
    normalize_group_nonzero_comb[4] = |normalize_padded_comb[11:8]; // 判定第五个四位分块是否非零
    normalize_group_nonzero_comb[3] = |normalize_padded_comb[15:12]; // 判定第四个四位分块是否非零
    normalize_group_nonzero_comb[2] = |normalize_padded_comb[19:16]; // 判定第三个四位分块是否非零
    normalize_group_nonzero_comb[1] = |normalize_padded_comb[23:20]; // 判定第二个四位分块是否非零
    normalize_group_nonzero_comb[0] = |normalize_padded_comb[27:24]; // 判定最高四位分块是否非零
    normalize_candidate01_comb = normalize_group_nonzero_comb[0] ? normalize_candidate_comb[0] : normalize_candidate_comb[1]; // 在最高两个分块候选中选择优先者
    normalize_candidate23_comb = normalize_group_nonzero_comb[2] ? normalize_candidate_comb[2] : normalize_candidate_comb[3]; // 在第三和第四分块候选中选择优先者
    normalize_candidate45_comb = normalize_group_nonzero_comb[4] ? normalize_candidate_comb[4] : normalize_candidate_comb[5]; // 在第五和第六分块候选中选择优先者
    normalize_shift01_comb = normalize_group_nonzero_comb[0] ? normalize_shift_candidate_comb[0] : normalize_shift_candidate_comb[1]; // 同步选择最高两个分块的移位量
    normalize_shift23_comb = normalize_group_nonzero_comb[2] ? normalize_shift_candidate_comb[2] : normalize_shift_candidate_comb[3]; // 同步选择第三和第四分块的移位量
    normalize_shift45_comb = normalize_group_nonzero_comb[4] ? normalize_shift_candidate_comb[4] : normalize_shift_candidate_comb[5]; // 同步选择第五和第六分块的移位量
    normalize_candidate03_comb = (normalize_group_nonzero_comb[0] || normalize_group_nonzero_comb[1]) ? normalize_candidate01_comb : normalize_candidate23_comb; // 在最高四个分块候选中选择优先半区
    normalize_candidate46_comb = (normalize_group_nonzero_comb[4] || normalize_group_nonzero_comb[5]) ? normalize_candidate45_comb : normalize_candidate_comb[6]; // 在最低三个分块候选中选择优先半区
    normalize_shift03_comb = (normalize_group_nonzero_comb[0] || normalize_group_nonzero_comb[1]) ? normalize_shift01_comb : normalize_shift23_comb; // 同步选择最高四个分块的移位量
    normalize_shift46_comb = (normalize_group_nonzero_comb[4] || normalize_group_nonzero_comb[5]) ? normalize_shift45_comb : normalize_shift_candidate_comb[6]; // 同步选择最低三个分块的移位量
    if (|normalize_group_nonzero_comb[3:0]) begin // 最高四个分块任一非零时选择高半区结果
        normalize_selected_comb = normalize_candidate03_comb; // 选择最高四个分块已经局部规格化的候选
        normalize_shift_selected_comb = normalize_shift03_comb; // 选择最高四个分块对应的总移位量
    end else begin // 最高四个分块全零时选择最低三个分块结果
        normalize_selected_comb = normalize_candidate46_comb; // 选择最低三个分块已经局部规格化的候选
        normalize_shift_selected_comb = normalize_shift46_comb; // 选择最低三个分块对应的总移位量
    end // 结束高低分块候选选择
end // 结束七路并行候选选择逻辑

always_comb begin // 根据最高进位或LZC结果完成有效数规格化和指数修正
    significand_o = 27'd0; // 默认清零规格化扩展有效数
    exponent_o = exponent_i; // 默认保持对阶后的共同无偏指数
    zero_o = (magnitude_i == 28'd0); // 判定有限加减结果是否精确抵消为零
    if (magnitude_i[27]) begin // 同号加法产生最高进位时右规格化一位
        significand_o = magnitude_i[27:1]; // 将最高进位移动到统一隐藏位位置
        significand_o[0] = magnitude_i[1] | magnitude_i[0]; // 合并右移丢弃位以保持正确Sticky信息
        exponent_o = exponent_i + 11'sd1; // 将最高进位规格化对应指数增加一
    end else if (!zero_o) begin // 非零且无最高进位结果通过并行候选网络左移规格化
        significand_o = {normalize_selected_comb[27:2], normalize_selected_comb[1] | normalize_selected_comb[0]}; // 去除补齐低位并输出二十七位规格化候选
        exponent_o = exponent_i - $signed({6'b000000, normalize_shift_selected_comb}); // 按选中分块的完整前导零数量降低无偏指数
    end // 结束最高进位、左规格化与精确零结果选择
end // 结束有效数规格化组合逻辑

endmodule // 结束fp32_normalize组合模块
