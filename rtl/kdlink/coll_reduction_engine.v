`include "collective_defs.vh" // 引入四种 reduction dtype 编码
module coll_reduction_engine ( // 定义五百一十二位四 dtype SUM reduction 流水
    input  wire clk_i, // 接收 collective core 时钟
    input  wire rst_n_i, // 接收低有效异步复位
    input  wire valid_i, // 接收本地和远端 payload 有效
    input  wire [1:0] dtype_i, // 接收 INT32 FP32 FP16 或 BF16 编码
    input  wire [63:0] byte_valid_i, // 接收 payload 有效字节 mask
    input  wire [511:0] local_i, // 接收本地 Tensor payload
    input  wire [511:0] remote_i, // 接收远端 Tensor payload
    output reg valid_o, // 指示 reduction 结果有效
    output reg [511:0] result_o, // 输出逐 lane SUM 结果
    output reg [63:0] byte_valid_o // 输出与结果对齐的有效字节 mask
); // 结束端口声明
    reg input_valid_q; // 保存输入隔离级有效
    reg [1:0] input_dtype_q; // 保存输入隔离级 dtype
    (* keep = "true" *) reg [1:0] input_dtype_lane_q [0:31]; // 为三十二个浮点 lane 物理保留输入 dtype 副本
    (* keep = "true" *) reg [1:0] input_dtype_segment_q [0:255]; // 为每个 lane 八个四位 operand 段物理保留 dtype 副本
    reg selected_input_valid_q; // 保存 operand 分段选择级有效
    reg [511:0] selected_input_local_q; // 保存与二级 dtype 副本对齐的本地 payload
    reg [511:0] selected_input_remote_q; // 保存与二级 dtype 副本对齐的远端 payload
    reg [63:0] input_byte_valid_q; // 保存输入隔离级 byte mask
    reg [511:0] input_local_q; // 保存输入隔离级本地 payload
    reg [511:0] input_remote_q; // 保存输入隔离级远端 payload
    wire int_valid; // 指示 INT32 一拍结果有效
    wire [511:0] int_result; // 保存 INT32 modulo 加法结果
    reg int_valid_q [0:24]; // 保存 INT32 至最终选择的二十五拍对齐有效
    reg [511:0] int_result_q [0:24]; // 保存 INT32 至最终选择的二十五拍对齐数据
    reg [1:0] dtype_q [0:24]; // 保存 FP lane metadata 二十五拍对齐 dtype
    reg [63:0] byte_valid_q [0:24]; // 保存 FP lane metadata 二十五拍对齐 byte mask
    reg [511:0] local_q [0:24]; // 保存 FP lane metadata 二十五拍对齐本地数据
    wire [31:0] fp_a [0:31]; // 保存三十二 lane 扩展 FP32 operand A
    wire [31:0] fp_b [0:31]; // 保存三十二 lane 扩展 FP32 operand B
    wire [31:0] fp_sum [0:31]; // 保存三十二 lane FP32 加法结果
    wire fp_valid [0:31]; // 保存三十二 lane FP32 结果有效
    wire [31:0] fp16_a_ext [0:31]; // 保存 FP16 operand A 扩展结果
    wire [31:0] fp16_b_ext [0:31]; // 保存 FP16 operand B 扩展结果
    wire [31:0] bf16_a_ext [0:31]; // 保存 BF16 operand A 扩展结果
    wire [31:0] bf16_b_ext [0:31]; // 保存 BF16 operand B 扩展结果
    wire [15:0] fp16_sum [0:31]; // 保存 FP16 每 hop RNE 结果
    wire [15:0] bf16_sum [0:31]; // 保存 BF16 每 hop RNE 结果
    wire fp16_convert_valid [0:31]; // 保存四级 FP16 converter 输出有效
    reg [31:0] fp32_delay_q [0:255]; // 保存三十二 lane 八拍 FP32 对齐结果
    reg [15:0] bf16_delay_q [0:255]; // 保存三十二 lane 八拍 BF16 对齐结果
    reg fp_format_valid_q; // 保存浮点格式化级有效
    reg [31:0] fp32_format_q [0:15]; // 保存十六 lane FP32 格式化结果
    reg [15:0] fp16_format_q [0:31]; // 保存三十二 lane FP16 格式化结果
    reg [15:0] bf16_format_q [0:31]; // 保存三十二 lane BF16 格式化结果
    reg [1:0] select_dtype_q [0:15]; // 为最终十六个三十二位段复制 dtype
    reg [63:0] select_byte_valid_q; // 保存最终选择级 byte mask
    reg [511:0] select_local_q; // 保存最终选择级本地 payload
    reg selected_valid_q; // 保存 dtype 选择后的统一有效
    reg [31:0] selected_segment_q [0:15]; // 保存 dtype 选择后的十六个三十二位段
    reg [63:0] selected_byte_valid_q; // 保存与 dtype 选择结果对齐的 byte mask
    reg [511:0] selected_local_q; // 保存与 dtype 选择结果对齐的本地 payload
    reg [31:0] segment_selected_d [0:15]; // 保存每段 dtype 选择组合结果
    reg [31:0] segment_result_d [0:15]; // 保存每个三十二位段最终选择结果
    integer lane_index; // 提供固定 lane 流水索引
    integer segment_index; // 提供固定三十二位段索引
    integer byte_index; // 提供固定 byte tail 索引
    coll_int32_reduction u_int32 ( // 实例化十六 lane 两级 carry-select INT32 modulo reduction
        .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(input_valid_q && input_dtype_q == `COLL_DTYPE_INT32), // 连接已隔离 INT32 有效
        .local_i(input_local_q), .remote_i(input_remote_q), .byte_valid_i(input_byte_valid_q), // 连接已隔离 INT32 operands 和 byte mask
        .valid_o(int_valid), .result_o(int_result), .byte_valid_o() // 连接 INT32 结果且最终 mask 使用统一 metadata
    ); // 结束 INT32 reduction 实例
    genvar lane; // 提供三十二个浮点 lane 静态生成索引
    genvar operand_segment; // 提供每 lane 八个四位 operand 分段索引
    generate // 生成 FP16 BF16 扩展、FP32 add 和舍入 lane
        for (lane = 0; lane < 32; lane = lane + 1) begin : g_fp_lane // 生成当前浮点 lane
            coll_fp16_to_fp32 u_fp16_a (.value_i(selected_input_local_q[lane*16 +: 16]), .value_o(fp16_a_ext[lane])); // 扩展与 dtype 对齐的本地 FP16 operand
            coll_fp16_to_fp32 u_fp16_b (.value_i(selected_input_remote_q[lane*16 +: 16]), .value_o(fp16_b_ext[lane])); // 扩展与 dtype 对齐的远端 FP16 operand
            assign bf16_a_ext[lane] = {selected_input_local_q[lane*16 +: 16], 16'd0}; // 将对齐后的本地 BF16 精确扩展为 FP32
            assign bf16_b_ext[lane] = {selected_input_remote_q[lane*16 +: 16], 16'd0}; // 将对齐后的远端 BF16 精确扩展为 FP32
            if (lane < 16) begin : g_fp32_select // 前十六 lane 可承载 FP32 或十六位 dtype
                for (operand_segment = 0; operand_segment < 8; operand_segment = operand_segment + 1) begin : g_operand_segment // 分段选择三十二位 operand
                    assign fp_a[lane][operand_segment*4 +: 4] = (input_dtype_segment_q[lane*8+operand_segment] == `COLL_DTYPE_FP32) ? selected_input_local_q[lane*32+operand_segment*4 +: 4] : ((input_dtype_segment_q[lane*8+operand_segment] == `COLL_DTYPE_FP16) ? fp16_a_ext[lane][operand_segment*4 +: 4] : bf16_a_ext[lane][operand_segment*4 +: 4]); // 按本地 dtype 副本选择对齐 operand A 当前段
                    assign fp_b[lane][operand_segment*4 +: 4] = (input_dtype_segment_q[lane*8+operand_segment] == `COLL_DTYPE_FP32) ? selected_input_remote_q[lane*32+operand_segment*4 +: 4] : ((input_dtype_segment_q[lane*8+operand_segment] == `COLL_DTYPE_FP16) ? fp16_b_ext[lane][operand_segment*4 +: 4] : bf16_b_ext[lane][operand_segment*4 +: 4]); // 按本地 dtype 副本选择对齐 operand B 当前段
                end // 结束三十二位 operand 分段选择
            end else begin : g_fp16_select // 后十六 lane 仅承载十六位 dtype
                for (operand_segment = 0; operand_segment < 8; operand_segment = operand_segment + 1) begin : g_operand_segment // 分段选择十六位 dtype operand
                    assign fp_a[lane][operand_segment*4 +: 4] = (input_dtype_segment_q[lane*8+operand_segment] == `COLL_DTYPE_FP16) ? fp16_a_ext[lane][operand_segment*4 +: 4] : bf16_a_ext[lane][operand_segment*4 +: 4]; // 选择 FP16 或 BF16 operand A 当前段
                    assign fp_b[lane][operand_segment*4 +: 4] = (input_dtype_segment_q[lane*8+operand_segment] == `COLL_DTYPE_FP16) ? fp16_b_ext[lane][operand_segment*4 +: 4] : bf16_b_ext[lane][operand_segment*4 +: 4]; // 选择 FP16 或 BF16 operand B 当前段
                end // 结束十六位 dtype operand 分段选择
            end // 结束 lane dtype 选择
            coll_fp32_add_lane u_fp_add ( // 实例化当前 lane 十六级 FP32 add
                .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(selected_input_valid_q && input_dtype_segment_q[lane*8] != `COLL_DTYPE_INT32), // 连接分段选择级浮点输入有效
                .a_i(fp_a[lane]), .b_i(fp_b[lane]), .valid_o(fp_valid[lane]), .result_o(fp_sum[lane]) // 连接 operands 和 FP32 sum
            ); // 结束当前 FP32 add 实例
            coll_fp32_to_fp16_pipeline u_fp16_round (.clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(fp_valid[lane]), .value_i(fp_sum[lane]), .valid_o(fp16_convert_valid[lane]), .value_o(fp16_sum[lane])); // 将 FP32 sum 通过八级流水按 RNE 舍入回 FP16
            coll_fp32_to_bf16 u_bf16_round (.value_i(fp_sum[lane]), .value_o(bf16_sum[lane])); // 将 FP32 sum 按 RNE 舍入回 BF16
        end // 结束当前浮点 lane
    endgenerate // 结束浮点 lane 生成
    always @(*) begin // 按分段复制 dtype 选择 reduction 格式结果
        for (segment_index = 0; segment_index < 16; segment_index = segment_index + 1) begin // 遍历十六个三十二位输出段
            case (select_dtype_q[segment_index]) // 使用当前段本地 dtype 副本选择结果
                `COLL_DTYPE_INT32: segment_selected_d[segment_index] = int_result_q[22][segment_index*32 +: 32]; // 选择已补偿三级 INT32 与浮点流水延迟的当前段
                `COLL_DTYPE_FP32: segment_selected_d[segment_index] = fp32_format_q[segment_index]; // 选择 FP32 当前段
                `COLL_DTYPE_FP16: segment_selected_d[segment_index] = {fp16_format_q[segment_index*2+1], fp16_format_q[segment_index*2]}; // 选择两个 FP16 lane
                default: segment_selected_d[segment_index] = {bf16_format_q[segment_index*2+1], bf16_format_q[segment_index*2]}; // 选择两个 BF16 lane
            endcase // 结束当前段 dtype 选择
        end // 结束十六输出段选择
    end // 结束最终结果选择组合逻辑
    always @(*) begin // 对已寄存 dtype 选择结果应用 tail byte 保持
        for (segment_index = 0; segment_index < 16; segment_index = segment_index + 1) begin // 遍历十六个已选择输出段
            segment_result_d[segment_index] = selected_segment_q[segment_index]; // 默认输出 reduction 结果
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin // 遍历当前段四个 byte
                if (!selected_byte_valid_q[segment_index*4+byte_index]) segment_result_d[segment_index][byte_index*8 +: 8] = selected_local_q[segment_index*32+byte_index*8 +: 8]; // 无效 byte 保持本地原值
            end // 结束当前段 tail byte 保持
        end // 结束十六输出段选择
    end // 结束 tail byte 保持组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新输入隔离、metadata 和结果格式化流水
        if (!rst_n_i) begin // 检测复位有效
            input_valid_q <= 1'b0; input_dtype_q <= 2'd0; input_byte_valid_q <= 64'd0; input_local_q <= 512'd0; input_remote_q <= 512'd0; // 清零输入隔离级
            fp_format_valid_q <= 1'b0; select_byte_valid_q <= 64'd0; select_local_q <= 512'd0; selected_valid_q <= 1'b0; selected_byte_valid_q <= 64'd0; selected_local_q <= 512'd0; // 清零最终格式化和选择 metadata
            valid_o <= 1'b0; result_o <= 512'd0; byte_valid_o <= 64'd0; // 清零最终输出级
            selected_input_valid_q <= 1'b0; selected_input_local_q <= 512'd0; selected_input_remote_q <= 512'd0; // 清除 operand 分段选择级数据和有效
            for (lane_index = 0; lane_index < 25; lane_index = lane_index + 1) begin int_valid_q[lane_index] <= 1'b0; int_result_q[lane_index] <= 512'd0; dtype_q[lane_index] <= 2'd0; byte_valid_q[lane_index] <= 64'd0; local_q[lane_index] <= 512'd0; end // 清零二十五拍 metadata 对齐流水
            for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin fp32_format_q[lane_index] <= 32'd0; select_dtype_q[lane_index] <= 2'd0; end // 清零 FP32 和 dtype 分段寄存器
            for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) selected_segment_q[lane_index] <= 32'd0; // 清零 dtype 选择结果寄存器
            for (lane_index = 0; lane_index < 32; lane_index = lane_index + 1) begin fp16_format_q[lane_index] <= 16'd0; bf16_format_q[lane_index] <= 16'd0; end // 清零十六位格式化寄存器
            for (lane_index = 0; lane_index < 256; lane_index = lane_index + 1) begin fp32_delay_q[lane_index] <= 32'd0; bf16_delay_q[lane_index] <= 16'd0; end // 清零八拍 FP32 BF16 对齐流水
            for (lane_index = 0; lane_index < 32; lane_index = lane_index + 1) input_dtype_lane_q[lane_index] <= 2'd0; // 清零全部浮点 lane dtype 副本
            for (lane_index = 0; lane_index < 256; lane_index = lane_index + 1) input_dtype_segment_q[lane_index] <= 2'd0; // 清零全部 operand 分段 dtype 副本
        end else begin // 处理 reduction pipeline 正常运行
            input_valid_q <= valid_i; input_dtype_q <= dtype_i; input_byte_valid_q <= byte_valid_i; input_local_q <= local_i; input_remote_q <= remote_i; // 锁存外部输入切断宽 dtype 选择路径
            for (lane_index = 0; lane_index < 32; lane_index = lane_index + 1) input_dtype_lane_q[lane_index] <= dtype_i; // 复制输入 dtype 限制三十二 lane 选择扇出
            selected_input_valid_q <= input_valid_q; // 将输入有效对齐至 operand 分段选择级
            selected_input_local_q <= input_local_q; selected_input_remote_q <= input_remote_q; // 将 operands 延迟至二级 dtype 副本同拍
            for (lane_index = 0; lane_index < 256; lane_index = lane_index + 1) input_dtype_segment_q[lane_index] <= input_dtype_lane_q[lane_index/8]; // 二级复制 dtype 限制每个四位选择器扇出
            int_valid_q[0] <= int_valid; int_result_q[0] <= int_result; // 锁存 INT32 结果对齐级零
            dtype_q[0] <= input_dtype_q; byte_valid_q[0] <= input_byte_valid_q; local_q[0] <= input_local_q; // 锁存浮点 metadata 对齐级零
            for (lane_index = 1; lane_index < 25; lane_index = lane_index + 1) begin int_valid_q[lane_index] <= int_valid_q[lane_index-1]; int_result_q[lane_index] <= int_result_q[lane_index-1]; dtype_q[lane_index] <= dtype_q[lane_index-1]; byte_valid_q[lane_index] <= byte_valid_q[lane_index-1]; local_q[lane_index] <= local_q[lane_index-1]; end // 传递二十五拍 INT 和浮点 metadata
            fp_format_valid_q <= fp16_convert_valid[0]; // 以 FP16 converter 有效统一标记浮点格式化结果
            for (lane_index = 0; lane_index < 32; lane_index = lane_index + 1) begin // 前推三十二 lane 八拍格式对齐流水
                fp32_delay_q[lane_index*8] <= fp_sum[lane_index]; fp32_delay_q[lane_index*8+1] <= fp32_delay_q[lane_index*8]; fp32_delay_q[lane_index*8+2] <= fp32_delay_q[lane_index*8+1]; fp32_delay_q[lane_index*8+3] <= fp32_delay_q[lane_index*8+2]; fp32_delay_q[lane_index*8+4] <= fp32_delay_q[lane_index*8+3]; fp32_delay_q[lane_index*8+5] <= fp32_delay_q[lane_index*8+4]; fp32_delay_q[lane_index*8+6] <= fp32_delay_q[lane_index*8+5]; fp32_delay_q[lane_index*8+7] <= fp32_delay_q[lane_index*8+6]; // 延迟 FP32 原始 sum
                bf16_delay_q[lane_index*8] <= bf16_sum[lane_index]; bf16_delay_q[lane_index*8+1] <= bf16_delay_q[lane_index*8]; bf16_delay_q[lane_index*8+2] <= bf16_delay_q[lane_index*8+1]; bf16_delay_q[lane_index*8+3] <= bf16_delay_q[lane_index*8+2]; bf16_delay_q[lane_index*8+4] <= bf16_delay_q[lane_index*8+3]; bf16_delay_q[lane_index*8+5] <= bf16_delay_q[lane_index*8+4]; bf16_delay_q[lane_index*8+6] <= bf16_delay_q[lane_index*8+5]; bf16_delay_q[lane_index*8+7] <= bf16_delay_q[lane_index*8+6]; // 延迟 BF16 RNE 结果
                fp16_format_q[lane_index] <= fp16_sum[lane_index]; bf16_format_q[lane_index] <= bf16_delay_q[lane_index*8+7]; // 锁存对齐后的十六位结果
            end // 结束格式对齐流水前推
            for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) fp32_format_q[lane_index] <= fp32_delay_q[lane_index*8+7]; // 锁存十六 lane 对齐 FP32 结果
            for (segment_index = 0; segment_index < 16; segment_index = segment_index + 1) select_dtype_q[segment_index] <= dtype_q[24]; // 复制最终 dtype 限制宽选择扇出
            select_byte_valid_q <= byte_valid_q[24]; select_local_q <= local_q[24]; // 锁存最终 tail 保持 metadata
            for (segment_index = 0; segment_index < 16; segment_index = segment_index + 1) selected_segment_q[segment_index] <= segment_selected_d[segment_index]; // 锁存 dtype 选择结果切断宽多路选择路径
            selected_byte_valid_q <= select_byte_valid_q; selected_local_q <= select_local_q; selected_valid_q <= (select_dtype_q[0] == `COLL_DTYPE_INT32) ? int_valid_q[22] : fp_format_valid_q; // 锁存 tail metadata 和已补偿三级 INT32 与浮点延迟的统一有效
            valid_o <= selected_valid_q; // 输出已完成 dtype 选择和 metadata 对齐的有效
            for (segment_index = 0; segment_index < 16; segment_index = segment_index + 1) result_o[segment_index*32 +: 32] <= segment_result_d[segment_index]; // 分段锁存最终 reduction 结果
            byte_valid_o <= select_byte_valid_q; // 锁存最终 byte mask
        end // 结束 reduction pipeline 复位选择
    end // 结束 reduction pipeline 时序逻辑
endmodule // 结束四 dtype 五百一十二位 reduction engine
