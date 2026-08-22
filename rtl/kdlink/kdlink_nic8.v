module kdlink_nic8 ( // 定义八 plane 十六 slice Tensor stream NIC 数据边界
    input wire clk_i, // 接收 slice 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire start_i, // 接收 operation 启动脉冲
    output wire start_ready_o, // 返回 operation 启动许可
    input wire [511:0] descriptor_i, // 接收 KDLink descriptor
    input wire phase_i, // 接收 collective RS/AG phase
    input wire [7:0] link_epoch_i, // 接收当前 link epoch
    input wire finish_i, // 接收 operation 完成脉冲
    output reg active_o, // 指示 NIC operation active
    output reg descriptor_error_o, // 指示启动 descriptor 非法
    input wire [15:0] source_valid_i, // 接收十六 Tensor source bank valid
    output wire [15:0] source_ready_o, // 返回十六 Tensor source bank ready
    input wire [8191:0] source_data_i, // 接收十六 Tensor source payload
    input wire [111:0] source_bytes_i, // 接收十六 Tensor source 有效字节数
    input wire [15:0] source_eop_i, // 指示各 bank 当前 flit 提前结束 packet
    input wire [79:0] source_dst_i, // 接收 direct operation 每 bank destination
    output wire [15:0] link_tx_valid_o, // 输出八 plane 十六 slice TX valid
    input wire [15:0] link_tx_ready_i, // 接收八 plane 十六 slice TX 本地 ready
    output wire [1535:0] link_tx_header_o, // 输出十六 slice 96-bit header
    output wire [8191:0] link_tx_data_o, // 输出十六 slice payload
    output wire [111:0] link_tx_bytes_o, // 输出十六 slice 有效字节数
    input wire [15:0] link_rx_valid_i, // 接收八 plane 十六 slice RX valid
    output wire [15:0] link_rx_ready_o, // 返回八 plane 十六 slice RX ready
    input wire [1535:0] link_rx_header_i, // 接收十六 slice RX header
    input wire [8191:0] link_rx_data_i, // 接收十六 slice RX payload
    input wire [111:0] link_rx_bytes_i, // 接收十六 slice RX 有效字节数
    output wire [15:0] result_valid_o, // 输出十六 Tensor result bank valid
    input wire [15:0] result_ready_i, // 接收十六 Tensor result bank ready
    output wire [1535:0] result_header_o, // 输出十六 Tensor result header
    output wire [8191:0] result_data_o, // 输出十六 Tensor result payload
    output wire [111:0] result_bytes_o, // 输出十六 Tensor result 有效字节数
    output wire [15:0] source_stall_o, // 输出各 source bank stall
    output wire [15:0] result_stall_o // 输出各 result bank stall
); // 结束端口声明
    reg [2:0] opcode_q; // 保存 active operation opcode
    reg [1:0] dtype_q; // 保存 active operation dtype
    reg [4:0] local_node_q; // 保存本地 node identity
    reg [11:0] collective_id_q; // 保存 active collective identity
    reg [7:0] plane_mask_q; // 保存 active plane mask
    reg [1:0] slice_mask_q; // 保存 active slice mask
    reg [11:0] packet_seq_q [0:15]; // 保存每 slice packet sequence
    reg [5:0] flit_seq_q [0:15]; // 保存每 slice packet 内 flit sequence
    reg [1535:0] source_header_d; // 保存十六 bank 组合 header
    wire [15:0] bank_enable; // 标记 descriptor 允许的十六 bank
    wire [15:0] array_source_valid; // 保存 mask 后 source valid
    wire [15:0] array_source_ready; // 保存 Tensor bank array source ready
    wire [15:0] source_fire; // 保存各 bank source 传输事件
    wire [15:0] array_source_stall; // 保存 Tensor bank array source stall
    integer bank_index; // 提供十六 bank header 和计数索引
    reg [4:0] ring_destination; // 保存 collective ring 下一 node
    assign start_ready_o = !active_o; // 仅无 active operation 时接受新 descriptor
    assign array_source_valid = source_valid_i & bank_enable; // 屏蔽 descriptor 未启用的 bank
    assign source_ready_o = array_source_ready & bank_enable; // 仅向启用 bank返回本地 ready
    assign source_fire = array_source_valid & array_source_ready; // 形成各 bank source 传输事件
    assign source_stall_o = array_source_stall | (source_valid_i & ~bank_enable); // 汇总内部和资源 mask 停顿
    genvar enable_index; // 提供十六 bank enable 生成索引
    generate // 按八 plane 和双 slice mask 生成 bank enable
        for (enable_index = 0; enable_index < 16; enable_index = enable_index + 1) begin : g_bank_enable // 生成单 bank 资源许可
            assign bank_enable[enable_index] = active_o && plane_mask_q[enable_index/2] && slice_mask_q[enable_index%2]; // 静态映射 bank 到 plane 和 slice
        end // 结束 bank enable 生成
    endgenerate // 结束资源 mask 连接
    always @(*) begin // 构造十六个协议 header
        source_header_d = 1536'd0; // 默认全部 header 为零
        ring_destination = (local_node_q == 5'd31) ? 5'd0 : local_node_q + 5'd1; // 计算三十二 node ring 下一跳
        for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 构造每个 plane/slice header
            source_header_d[bank_index*96 + 0 +: 4] = 4'd2; // 写入协议版本
            source_header_d[bank_index*96 + 4 +: 4] = 4'd0; // 写入 DATA message type
            source_header_d[bank_index*96 + 8 +: 3] = opcode_q; // 写入 operation opcode
            source_header_d[bank_index*96 + 11 +: 2] = dtype_q; // 写入 reduction dtype
            if (opcode_q <= 3'd2) source_header_d[bank_index*96 + 13 +: 3] = 3'd2; // collective data 使用 bulk VC2
            else if (opcode_q <= 3'd4) source_header_d[bank_index*96 + 13 +: 3] = 3'd3; // AllToAll traffic 使用 VC3
            else source_header_d[bank_index*96 + 13 +: 3] = 3'd4; // point-to-point 使用 VC4
            source_header_d[bank_index*96 + 16] = phase_i; // 写入 RS/AG phase
            source_header_d[bank_index*96 + 17] = flit_seq_q[bank_index] == 6'd0; // packet 首 flit 写入 SOP
            source_header_d[bank_index*96 + 18] = source_eop_i[bank_index] || (flit_seq_q[bank_index] == 6'd15); // packet 尾 flit 写入 EOP
            source_header_d[bank_index*96 + 20 +: 5] = local_node_q; // 写入 source node
            source_header_d[bank_index*96 + 25 +: 5] = (opcode_q <= 3'd2) ? ring_destination[4:0] : source_dst_i[bank_index*5 +: 5]; // collective 走 ring 而 direct 使用 bank destination
            source_header_d[bank_index*96 + 30 +: 3] = bank_index[3:1]; // 写入静态 plane identity
            source_header_d[bank_index*96 + 33 +: 5] = 5'd31; // 初始化 hop limit
            source_header_d[bank_index*96 + 38 +: 8] = link_epoch_i; // 写入 link epoch
            source_header_d[bank_index*96 + 46 +: 12] = collective_id_q; // 写入 collective identity
            source_header_d[bank_index*96 + 58 +: 12] = {bank_index[3:0], packet_seq_q[bank_index][7:0]}; // 写入 bank stripe chunk identity
            source_header_d[bank_index*96 + 70 +: 12] = packet_seq_q[bank_index]; // 写入全局 packet sequence
            source_header_d[bank_index*96 + 82 +: 6] = flit_seq_q[bank_index]; // 写入 packet 内 flit sequence
            source_header_d[bank_index*96 + 88 +: 7] = source_bytes_i[bank_index*7 +: 7]; // 写入 payload 有效字节数
        end // 结束十六 header 构造
    end // 结束 header 组合逻辑
    kdlink_tensor_bank_array u_banks ( // 实例化十六 bank 双向弹性边界
        .clk_i(clk_i), .rst_n_i(rst_n_i), .source_valid_i(array_source_valid), .source_ready_o(array_source_ready), .source_header_i(source_header_d), .source_data_i(source_data_i), .source_bytes_i(source_bytes_i), // 连接 descriptor mask 后 source banks
        .link_tx_valid_o(link_tx_valid_o), .link_tx_ready_i(link_tx_ready_i), .link_tx_header_o(link_tx_header_o), .link_tx_data_o(link_tx_data_o), .link_tx_bytes_o(link_tx_bytes_o), // 连接十六 slice TX
        .link_rx_valid_i(link_rx_valid_i), .link_rx_ready_o(link_rx_ready_o), .link_rx_header_i(link_rx_header_i), .link_rx_data_i(link_rx_data_i), .link_rx_bytes_i(link_rx_bytes_i), // 连接十六 slice RX
        .result_valid_o(result_valid_o), .result_ready_i(result_ready_i), .result_header_o(result_header_o), .result_data_o(result_data_o), .result_bytes_o(result_bytes_o), // 连接十六 result banks
        .source_stall_o(array_source_stall), .result_stall_o(result_stall_o) // 连接 bank stall 状态
    ); // 结束 Tensor bank array 实例
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 active descriptor 和每 bank packet identity
        if (!rst_n_i) begin // 检测复位有效
            active_o <= 1'b0; // 清除 active operation
            descriptor_error_o <= 1'b0; // 清除 descriptor error
            opcode_q <= 3'd0; // 清零 opcode
            dtype_q <= 2'd0; // 清零 dtype
            local_node_q <= 5'd0; // 清零 local node
            collective_id_q <= 12'd0; // 清零 collective identity
            plane_mask_q <= 8'd0; // 清零 plane mask
            slice_mask_q <= 2'd0; // 清零 slice mask
            for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 清零每 bank packet 状态
                packet_seq_q[bank_index] <= bank_index[0] ? 12'd1 : 12'd0; // 偶奇 bank 初始化为相邻 packet sequence
                flit_seq_q[bank_index] <= 6'd0; // 清零 packet 内 flit sequence
            end // 结束 bank packet 状态清零
        end else begin // 处理正常 NIC operation
            descriptor_error_o <= 1'b0; // 默认本周期无 descriptor error
            if (start_i && start_ready_o) begin // 接受一个新 operation descriptor
                if (descriptor_i[2:0] > 3'd5 || descriptor_i[15:10] != 6'd32 || descriptor_i[24:21] != 4'd2 || descriptor_i[56:49] == 8'd0 || descriptor_i[58:57] == 2'd0 || descriptor_i[63:62] != 2'd0 || descriptor_i[511:416] != 96'd0) begin // 检查必要 descriptor 和 reserved 字段
                    descriptor_error_o <= 1'b1; // 报告非法 descriptor
                end else begin // 锁存合法 operation 配置
                    active_o <= 1'b1; // 标记 operation active
                    opcode_q <= descriptor_i[2:0]; // 锁存 opcode
                    dtype_q <= descriptor_i[4:3]; // 锁存 dtype
                    local_node_q <= descriptor_i[9:5]; // 锁存 local node
                    collective_id_q <= descriptor_i[36:25]; // 锁存 collective identity
                    plane_mask_q <= descriptor_i[56:49]; // 锁存 plane mask
                    slice_mask_q <= descriptor_i[58:57]; // 锁存 slice mask
                    for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 初始化 operation packet 状态
                        packet_seq_q[bank_index] <= bank_index[0] ? 12'd1 : 12'd0; // 每 bonded port 以偶奇相邻 sequence 开始
                        flit_seq_q[bank_index] <= 6'd0; // 每 bank 从 packet flit 零开始
                    end // 结束 packet 状态初始化
                end // 结束合法 descriptor 锁存
            end // 结束 operation 启动
            if (finish_i) active_o <= 1'b0; // operation 完成时释放 NIC 数据边界
            for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 推进各 bank packet identity
                if (source_fire[bank_index]) begin // 检查本 bank source flit 被接受
                    if (source_eop_i[bank_index] || (flit_seq_q[bank_index] == 6'd15)) begin // 检查 packet 边界
                        flit_seq_q[bank_index] <= 6'd0; // 下一 flit 从新 packet sequence 零开始
                        packet_seq_q[bank_index] <= packet_seq_q[bank_index] + 12'd2; // 保持 bonded port 偶奇 packet 条带
                    end else begin // 处理 packet 内普通 flit
                        flit_seq_q[bank_index] <= flit_seq_q[bank_index] + 6'd1; // 推进 packet 内 sequence
                    end // 结束 packet sequence 更新
                end // 结束 source flit 接受处理
            end // 结束十六 bank packet 状态更新
        end // 结束正常 NIC operation
    end // 结束 active descriptor 更新
endmodule // 结束八 plane NIC 数据边界
