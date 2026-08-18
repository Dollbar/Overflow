module kdlink_v2_depacketizer ( // 定义 KDLink-v2 RX CRC 检查流水
    input wire clk_i, // 接收一 GHz slice 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire valid_i, // 接收连续 RX flit 有效标志
    input wire [639:0] flit_i, // 接收带 CRC 的 KDLink-v2 flit
    output wire valid_o, // 输出检查完成有效标志
    output wire crc_good_o, // 输出 CRC 比较结果
    output wire [95:0] header_o, // 输出不含 CRC 的对齐 header
    output wire [511:0] payload_o, // 输出对齐 payload
    output wire [6:0] payload_bytes_o // 输出对齐有效字节数
); // 结束端口声明
    wire crc_valid; // 保存重算 CRC 流水有效标志
    wire [31:0] crc_value; // 保存重算 CRC 结果
    wire [95:0] aligned_header; // 保存重算流水对齐 header
    wire [511:0] aligned_payload; // 保存重算流水对齐 payload
    wire [6:0] aligned_payload_bytes; // 保存重算流水对齐字节数
    reg [31:0] received_crc_q [0:304]; // 保存接收 CRC 对齐流水
    reg received_valid_q [0:304]; // 保存接收有效对齐流水
    always @(posedge clk_i or negedge rst_n_i) begin // 锁存接收 CRC 输入级
        if (!rst_n_i) begin // 检测复位有效
            received_crc_q[0] <= 32'd0; // 清零接收 CRC 输入级
            received_valid_q[0] <= 1'b0; // 清除接收有效输入级
        end else begin // 处理正常接收
            received_crc_q[0] <= flit_i[639:608]; // 锁存当前接收 CRC
            received_valid_q[0] <= valid_i; // 锁存当前接收有效标志
        end // 结束接收 CRC 输入级更新
    end // 结束接收 CRC 输入级时序逻辑
    genvar align_stage; // 提供 CRC 对齐流水静态索引
    generate // 展开三百零四级 CRC 对齐流水
        for (align_stage = 1; align_stage <= 304; align_stage = align_stage + 1) begin : g_crc_align // 生成当前对齐级
            always @(posedge clk_i or negedge rst_n_i) begin // 更新当前 CRC 对齐级
                if (!rst_n_i) begin // 检测复位有效
                    received_crc_q[align_stage] <= 32'd0; // 清零当前 CRC 对齐级
                    received_valid_q[align_stage] <= 1'b0; // 清除当前有效对齐级
                end else begin // 处理正常对齐传递
                    received_crc_q[align_stage] <= received_crc_q[align_stage-1]; // 传递接收 CRC
                    received_valid_q[align_stage] <= received_valid_q[align_stage-1]; // 传递接收有效标志
                end // 结束当前对齐级更新
            end // 结束当前 CRC 对齐时序逻辑
        end // 结束当前静态对齐级
    endgenerate // 结束 CRC 对齐流水生成
    coll_crc32_flit_pipeline u_crc_check ( // 复用已收敛的 CRC-32 重算流水
        .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(valid_i), .header_i(flit_i[607:512]), // 连接接收 header
        .payload_i(flit_i[511:0]), .payload_bytes_i(flit_i[606:600]), .valid_o(crc_valid), .crc_o(crc_value), // 连接 v2 payload 长度和 CRC
        .header_o(aligned_header), .payload_o(aligned_payload), .payload_bytes_o(aligned_payload_bytes) // 连接流水对齐数据
    ); // 结束 CRC 重算实例
    assign valid_o = crc_valid && received_valid_q[304]; // 输出对齐后的检查有效标志
    assign crc_good_o = (crc_value == received_crc_q[304]); // 比较重算 CRC 与接收 CRC
    assign header_o = aligned_header; // 输出对齐 header
    assign payload_o = aligned_payload; // 输出对齐 payload
    assign payload_bytes_o = aligned_payload_bytes; // 输出对齐 payload 字节数
endmodule // 结束 KDLink-v2 depacketizer
