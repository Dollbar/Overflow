module coll_depacketizer ( // 定义 logical flit CRC 检查和字段输出模块
    input  wire clk_i, // 接收 link core 时钟
    input  wire rst_n_i, // 接收低有效异步复位
    input  wire valid_i, // 接收 RX logical flit 有效
    input  wire [639:0] flit_i, // 接收带 CRC logical flit
    output wire valid_o, // 指示检查流水输出有效
    output wire crc_good_o, // 指示接收 flit CRC 正确
    output wire [95:0] header_o, // 输出不含 CRC 的 header
    output wire [511:0] payload_o, // 输出 Tensor payload
    output wire [6:0] payload_bytes_o // 输出 payload 有效字节数
); // 结束端口声明
    wire crc_valid; // 指示 CRC 重算结果有效
    wire [31:0] crc_value; // 保存重算 CRC 结果
    wire [95:0] aligned_header; // 保存对齐后的接收 header
    wire [511:0] aligned_payload; // 保存对齐后的接收 payload
    wire [6:0] aligned_payload_bytes; // 保存对齐后的 payload 字节数
    reg [31:0] received_crc_q [0:304]; // 保存与三百零四级 CRC 流水对齐的接收 CRC
    reg received_valid_q [0:304]; // 保存接收 CRC 对齐有效标志
    always @(posedge clk_i or negedge rst_n_i) begin // 更新接收 CRC 对齐输入级
        if (!rst_n_i) begin // 检测复位有效
            received_crc_q[0] <= 32'd0; // 清零接收 CRC 输入级
            received_valid_q[0] <= 1'b0; // 清除接收 CRC 输入级有效
        end else begin // 处理接收 CRC 输入级正常运行
            received_crc_q[0] <= flit_i[639:608]; // 锁存接收 header CRC 字段
            received_valid_q[0] <= valid_i; // 锁存接收 flit 有效标志
        end // 结束接收 CRC 输入级复位选择
    end // 结束接收 CRC 输入级时序逻辑
    genvar align_stage; // 提供静态接收 CRC 对齐流水级索引
    generate // 静态展开三百零四个接收 CRC 对齐级
        for (align_stage = 1; align_stage <= 304; align_stage = align_stage + 1) begin : g_crc_align // 生成单个对齐寄存级
            always @(posedge clk_i or negedge rst_n_i) begin // 更新当前接收 CRC 对齐级
                if (!rst_n_i) begin // 检测复位有效
                    received_crc_q[align_stage] <= 32'd0; // 清零当前接收 CRC 对齐级
                    received_valid_q[align_stage] <= 1'b0; // 清除当前接收 CRC 对齐有效
                end else begin // 处理当前对齐级正常运行
                    received_crc_q[align_stage] <= received_crc_q[align_stage-1]; // 传递接收 CRC 字段
                    received_valid_q[align_stage] <= received_valid_q[align_stage-1]; // 传递接收 CRC 有效标志
                end // 结束当前对齐级复位选择
            end // 结束当前接收 CRC 对齐时序逻辑
        end // 结束当前静态对齐级
    endgenerate // 结束接收 CRC 对齐流水生成
    coll_crc32_flit_pipeline u_crc_check ( // 实例化接收 flit CRC 重算流水
        .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(valid_i), .header_i(flit_i[607:512]), // 连接接收 header 和控制
        .payload_i(flit_i[511:0]), .payload_bytes_i(flit_i[592:586]), .valid_o(crc_valid), .crc_o(crc_value), // 连接接收 payload 长度和 CRC 结果
        .header_o(aligned_header), .payload_o(aligned_payload), .payload_bytes_o(aligned_payload_bytes) // 连接对齐后的接收字段
    ); // 结束接收 CRC 重算实例
    assign valid_o = crc_valid && received_valid_q[304]; // 仅在重算和接收对齐均有效时输出
    assign crc_good_o = (crc_value == received_crc_q[304]); // 比较重算 CRC 与接收 CRC
    assign header_o = aligned_header; // 输出 CRC 对齐后的 header
    assign payload_o = aligned_payload; // 输出 CRC 对齐后的 payload
    assign payload_bytes_o = aligned_payload_bytes; // 输出 CRC 对齐后的 payload 字节数
endmodule // 结束 logical flit depacketizer
