module coll_crc32_flit_pipeline ( // 定义三百零四级 logical flit CRC-32 流水线
    input  wire clk_i, // 接收 link core 工作时钟
    input  wire rst_n_i, // 接收低有效异步复位
    input  wire valid_i, // 接收 header 和 payload 有效指示
    input  wire [95:0] header_i, // 接收不含 CRC 字段的十二字节 header
    input  wire [511:0] payload_i, // 接收最多六十四字节 payload
    input  wire [6:0] payload_bytes_i, // 接收实际参与 CRC 的 payload 字节数
    output wire valid_o, // 指示流水 CRC 结果有效
    output wire [31:0] crc_o, // 输出完成 xorout 的 CRC-32
    output wire [95:0] header_o, // 输出与 CRC 结果对齐的 header 字段
    output wire [511:0] payload_o, // 输出与 CRC 结果对齐的 payload
    output wire [6:0] payload_bytes_o // 输出与 CRC 结果对齐的 payload 字节数
); // 结束端口声明
    localparam STAGES = 304; // 定义每个半字节先复制使能再更新 CRC 的总流水级数
    wire [607:0] stream_input; // 按低位优先组合 header 和 payload 字节流
    reg [607:0] stream_q [0:STAGES]; // 保存各级字节流对齐副本
    reg [6:0] payload_bytes_q [0:STAGES]; // 保存各级 payload 字节数
    reg [31:0] crc_q [0:STAGES]; // 保存各级 CRC 中间状态
    reg [7:0] enable_q [0:STAGES]; // 保存八路复制的 CRC 段使能
    reg valid_q [0:STAGES]; // 保存各级有效流水标志
    assign stream_input = {payload_i, header_i}; // 将 header 放在 CRC 字节流低十二字节
    assign valid_o = valid_q[STAGES]; // 输出末级有效标志
    assign crc_o = crc_q[STAGES] ^ 32'hFFFFFFFF; // 对末级 CRC 状态执行协议 xorout
    assign header_o = stream_q[STAGES][95:0]; // 输出末级对齐 header
    assign payload_o = stream_q[STAGES][607:96]; // 输出末级对齐 payload
    assign payload_bytes_o = payload_bytes_q[STAGES]; // 输出末级对齐 payload 字节数
    always @(posedge clk_i or negedge rst_n_i) begin // 锁存流水输入级数据
        if (!rst_n_i) begin // 检测复位有效
            stream_q[0] <= 608'd0; // 清零输入级字节流
            payload_bytes_q[0] <= 7'd0; // 清零输入级 payload 字节数
            crc_q[0] <= 32'hFFFFFFFF; // 初始化 CRC 协议初值
            enable_q[0] <= 8'd0; // 清零输入级 CRC 段使能
            valid_q[0] <= 1'b0; // 清除输入级有效标志
        end else begin // 处理流水输入级正常运行
            stream_q[0] <= stream_input; // 锁存当前 header 和 payload
            payload_bytes_q[0] <= payload_bytes_i; // 锁存当前 payload 字节数
            crc_q[0] <= 32'hFFFFFFFF; // 为每条新 flit 重新装载 CRC 初值
            enable_q[0] <= 8'd0; // 输入级无需 CRC 段使能
            valid_q[0] <= valid_i; // 锁存当前 flit 有效标志
        end // 结束输入级复位选择
    end // 结束流水输入级时序逻辑
    genvar stage_index; // 提供静态 CRC 流水级生成索引
    generate // 为每个半字节生成使能复制级和 CRC 更新级
        for (stage_index = 0; stage_index < STAGES; stage_index = stage_index + 1) begin : g_stage // 生成当前 CRC 流水级
            if ((stage_index % 2) == 0) begin : g_enable_stage // 处理半字节使能复制级
                localparam integer NIBBLE_INDEX = stage_index/2; // 固化当前半字节索引
                localparam integer PAYLOAD_BYTE_INDEX = (NIBBLE_INDEX-24)/2; // 固化 payload 字节索引
                wire enable_source; // 保存当前半字节原始覆盖使能
                if (NIBBLE_INDEX < 24) begin : g_header_enable // 处理固定 header 半字节
                    assign enable_source = 1'b1; // 固定启用 header 半字节
                end else begin : g_payload_enable // 处理可变 payload 半字节
                    assign enable_source = {25'd0, payload_bytes_q[stage_index]} > PAYLOAD_BYTE_INDEX; // 按 payload 长度启用对应半字节
                end // 结束半字节覆盖使能选择
                always @(posedge clk_i or negedge rst_n_i) begin // 更新半字节使能复制级
                    if (!rst_n_i) begin // 检测复位有效
                        stream_q[stage_index+1] <= 608'd0; // 清零下一级字节流副本
                        payload_bytes_q[stage_index+1] <= 7'd0; // 清零下一级 payload 字节数
                        crc_q[stage_index+1] <= 32'hFFFFFFFF; // 清零下一级 CRC 为协议初值
                        enable_q[stage_index+1] <= 8'd0; // 清零下一级 CRC 段使能
                        valid_q[stage_index+1] <= 1'b0; // 清除下一级有效标志
                    end else begin // 处理使能复制级正常流水
                        stream_q[stage_index+1] <= stream_q[stage_index]; // 传递字节流对齐副本
                        payload_bytes_q[stage_index+1] <= payload_bytes_q[stage_index]; // 传递 payload 字节数
                        crc_q[stage_index+1] <= crc_q[stage_index]; // 保持 CRC 状态等待半字节更新
                        enable_q[stage_index+1] <= {8{enable_source}}; // 复制覆盖使能限制单网扇出
                        valid_q[stage_index+1] <= valid_q[stage_index]; // 传递 flit 有效标志
                    end // 结束使能复制级复位选择
                end // 结束使能复制级时序逻辑
            end else begin : g_update_stage // 处理半字节 CRC 更新级
                localparam integer NIBBLE_INDEX = (stage_index-1)/2; // 固化当前更新半字节索引
                wire [31:0] crc_next; // 保存半字节 CRC 更新结果
                coll_crc32_nibble u_n0 ( // 实例化分段使能半字节 CRC 更新
                    .crc_i(crc_q[stage_index]), .data_i(stream_q[stage_index][NIBBLE_INDEX*4 +: 4]), .enable_i(enable_q[stage_index]), .crc_o(crc_next) // 连接当前半字节状态数据和复制使能
                ); // 结束半字节 CRC 实例
                always @(posedge clk_i or negedge rst_n_i) begin // 更新半字节 CRC 状态级
                    if (!rst_n_i) begin // 检测复位有效
                        stream_q[stage_index+1] <= 608'd0; // 清零下一级字节流副本
                        payload_bytes_q[stage_index+1] <= 7'd0; // 清零下一级 payload 字节数
                        crc_q[stage_index+1] <= 32'hFFFFFFFF; // 清零下一级 CRC 为协议初值
                        enable_q[stage_index+1] <= 8'd0; // 清零下一级 CRC 段使能
                        valid_q[stage_index+1] <= 1'b0; // 清除下一级有效标志
                    end else begin // 处理 CRC 更新级正常流水
                        stream_q[stage_index+1] <= stream_q[stage_index]; // 传递字节流对齐副本
                        payload_bytes_q[stage_index+1] <= payload_bytes_q[stage_index]; // 传递 payload 字节数
                        crc_q[stage_index+1] <= crc_next; // 锁存半字节 CRC 更新结果
                        enable_q[stage_index+1] <= 8'd0; // 更新级后清除临时使能
                        valid_q[stage_index+1] <= valid_q[stage_index]; // 传递 flit 有效标志
                    end // 结束 CRC 更新级复位选择
                end // 结束 CRC 更新级时序逻辑
            end // 结束 CRC 流水级类型选择
        end // 结束 CRC 流水级生成
    endgenerate // 结束 CRC 流水生成
endmodule // 结束 logical flit CRC-32 流水模块
