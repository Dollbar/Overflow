module kdlink_v2_pcs_tx ( // 定义单 slice 十 lane 64b/66b PCS 发送器
    input wire clk_i, // 接收 PCS 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire flit_valid_i, // 接收 640-bit logical flit 有效位
    input wire [639:0] flit_i, // 接收 640-bit logical flit
    input wire training_i, // 请求发送一组训练 control block
    input wire alignment_marker_i, // 请求发送一组 alignment marker
    input wire [15:0] marker_sequence_i, // 接收 alignment marker sequence
    output wire blocks_valid_o, // 输出十个 66-bit block 共同有效位
    output reg [659:0] blocks_o // 输出低 lane 优先的十个 66-bit block
); // 结束端口声明
    wire [9:0] scrambled_valid; // 保存十 lane 扰码输出有效位
    wire [639:0] scrambled_data; // 保存十 lane 扰码输出数据
    reg training_q; // 对齐扰码流水的训练 control 状态
    reg marker_q; // 对齐扰码流水的 marker control 状态
    reg [15:0] marker_sequence_q; // 对齐 control 流水的 marker sequence
    wire data_valid; // 标记当前输入为普通 data flit
    integer lane_index; // 提供十 lane block 构造索引
    assign data_valid = flit_valid_i && !training_i && !alignment_marker_i; // control block 优先于普通 data
    assign blocks_valid_o = training_q || marker_q || (&scrambled_valid); // 汇总 control 或十 lane data 有效位
    genvar scrambler_index; // 提供十 lane 扰码器生成索引
    generate // 为十个 64-bit word 生成独立扰码状态
        for (scrambler_index = 0; scrambler_index < 10; scrambler_index = scrambler_index + 1) begin : g_scrambler // 生成单 PCS lane 扰码器
            kdlink_v2_scrambler64 u_scrambler ( // 实例化 x^58+x^39+1 扰码器
                .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(data_valid), .data_i(flit_i[scrambler_index*64 +: 64]), // 连接 lane 原始 data
                .valid_o(scrambled_valid[scrambler_index]), .data_o(scrambled_data[scrambler_index*64 +: 64]) // 连接 lane 扰码结果
            ); // 结束单 lane 扰码器实例
        end // 结束十 lane 扰码器生成
    endgenerate // 结束扰码器生成
    always @(*) begin // 构造十个 data 或 control block
        blocks_o = 660'd0; // 默认全部 block 为零
        for (lane_index = 0; lane_index < 10; lane_index = lane_index + 1) begin // 构造每个 66-bit lane block
            if (training_q) begin // 构造训练 control block
                blocks_o[lane_index*66 +: 2] = 2'b10; // control block sync header 固定为 10
                blocks_o[lane_index*66 + 2 +: 64] = 64'h4B44_4C32_5452_0000 | {56'd0, lane_index[7:0]}; // 写入 KDL2TR training pattern 和 lane identity
            end else if (marker_q) begin // 构造 alignment marker control block
                blocks_o[lane_index*66 +: 2] = 2'b10; // control block sync header 固定为 10
                blocks_o[lane_index*66 + 2 +: 64] = 64'hA11E_0000_0000_0000 | {40'd0, marker_sequence_q, lane_index[7:0]}; // 写入 marker signature、sequence 和 lane identity
            end else begin // 构造普通 data block
                blocks_o[lane_index*66 +: 2] = 2'b01; // data block sync header 固定为 01
                blocks_o[lane_index*66 + 2 +: 64] = scrambled_data[lane_index*64 +: 64]; // 写入对应 lane 扰码 payload
            end // 结束 block 类型选择
        end // 结束十 lane block 构造
    end // 结束 block 构造
    always @(posedge clk_i or negedge rst_n_i) begin // 对齐 control 状态与扰码流水
        if (!rst_n_i) begin // 检测复位有效
            training_q <= 1'b0; // 清除训练 control 状态
            marker_q <= 1'b0; // 清除 marker control 状态
            marker_sequence_q <= 16'd0; // 清零 marker sequence
        end else begin // 处理正常 control 流水
            training_q <= training_i; // 注册训练请求
            marker_q <= !training_i && alignment_marker_i; // 训练优先时屏蔽 marker
            marker_sequence_q <= marker_sequence_i; // 注册 marker sequence
        end // 结束正常 control 流水
    end // 结束 control 状态注册
endmodule // 结束 PCS 发送器
