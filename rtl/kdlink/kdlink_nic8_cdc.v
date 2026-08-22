module kdlink_nic8_cdc ( // 定义异步 Tensor 域到一 GHz slice 域的八 plane NIC wrapper
    input wire tensor_clk_i, // 接收 Tensor stream 工作时钟
    input wire tensor_rst_n_i, // 接收 Tensor 域低有效异步复位
    input wire slice_clk_i, // 接收 KDLink slice 工作时钟
    input wire slice_rst_n_i, // 接收 slice 域低有效异步复位
    input wire start_i, // 接收 slice 域 operation 启动脉冲
    output wire start_ready_o, // 返回 slice 域 operation 启动许可
    input wire [511:0] descriptor_i, // 接收 slice 域 KDLink descriptor
    input wire phase_i, // 接收 slice 域 collective phase
    input wire [7:0] link_epoch_i, // 接收 slice 域 link epoch
    input wire finish_i, // 接收 slice 域 operation 完成脉冲
    output wire active_o, // 输出 slice 域 NIC active 状态
    output wire descriptor_error_o, // 输出 slice 域 descriptor error
    input wire [15:0] source_valid_i, // 接收 Tensor 域十六 bank source valid
    output wire [15:0] source_ready_o, // 返回 Tensor 域十六 bank source ready
    input wire [8191:0] source_data_i, // 接收 Tensor 域十六 bank payload
    input wire [111:0] source_bytes_i, // 接收 Tensor 域十六 bank 有效字节数
    input wire [15:0] source_eop_i, // 接收 Tensor 域十六 bank EOP
    input wire [79:0] source_dst_i, // 接收 Tensor 域十六 bank direct destination
    output wire [15:0] link_tx_valid_o, // 输出 slice 域十六路 link TX valid
    input wire [15:0] link_tx_ready_i, // 接收 slice 域十六路 link TX ready
    output wire [1535:0] link_tx_header_o, // 输出 slice 域十六路 link TX header
    output wire [8191:0] link_tx_data_o, // 输出 slice 域十六路 link TX payload
    output wire [111:0] link_tx_bytes_o, // 输出 slice 域十六路 link TX 有效字节数
    input wire [15:0] link_rx_valid_i, // 接收 slice 域十六路 link RX valid
    output wire [15:0] link_rx_ready_o, // 返回 slice 域十六路 link RX ready
    input wire [1535:0] link_rx_header_i, // 接收 slice 域十六路 link RX header
    input wire [8191:0] link_rx_data_i, // 接收 slice 域十六路 link RX payload
    input wire [111:0] link_rx_bytes_i, // 接收 slice 域十六路 link RX 有效字节数
    output wire [15:0] result_valid_o, // 输出 Tensor 域十六 bank result valid
    input wire [15:0] result_ready_i, // 接收 Tensor 域十六 bank result ready
    output wire [1535:0] result_header_o, // 输出 Tensor 域十六 bank result header
    output wire [8191:0] result_data_o, // 输出 Tensor 域十六 bank result payload
    output wire [111:0] result_bytes_o, // 输出 Tensor 域十六 bank result 有效字节数
    output wire [31:0] cdc_error_o // 输出三十二个 async FIFO overflow/underflow 汇总位
); // 结束端口声明
    wire [15:0] slice_source_valid; // 保存 source FIFO slice 域 read valid
    wire [15:0] slice_source_ready; // 保存 source FIFO slice 域 read ready
    wire [8399:0] slice_source_word; // 保存十六路 525-bit source FIFO read data
    wire [8191:0] slice_source_data; // 保存 slice 域 source payload
    wire [111:0] slice_source_bytes; // 保存 slice 域 source 有效字节数
    wire [15:0] slice_source_eop; // 保存 slice 域 source EOP
    wire [79:0] slice_source_dst; // 保存 slice 域 source direct destination
    wire [15:0] slice_result_valid; // 保存 NIC slice 域 result valid
    wire [15:0] slice_result_ready; // 保存 result FIFO slice 域 write ready
    wire [1535:0] slice_result_header; // 保存 NIC slice 域 result header
    wire [8191:0] slice_result_data; // 保存 NIC slice 域 result payload
    wire [111:0] slice_result_bytes; // 保存 NIC slice 域 result 有效字节数
    wire [9839:0] tensor_result_word; // 保存十六路 615-bit result FIFO read data
    wire [15:0] source_overflow; // 保存十六 source FIFO overflow 状态
    wire [15:0] source_underflow; // 保存十六 source FIFO underflow 状态
    wire [15:0] result_overflow; // 保存十六 result FIFO overflow 状态
    wire [15:0] result_underflow; // 保存十六 result FIFO underflow 状态
    wire [15:0] source_stall_unused; // 保存未导出的 slice source stall
    wire [15:0] result_stall_unused; // 保存未导出的 slice result stall
    assign cdc_error_o = {result_overflow | result_underflow, source_overflow | source_underflow}; // 汇总每方向 async FIFO 协议错误
    genvar cdc_bank; // 提供十六 bank CDC FIFO 生成索引
    generate // 为每个 Tensor bank 生成独立 source/result 双向 async FIFO
        for (cdc_bank = 0; cdc_bank < 16; cdc_bank = cdc_bank + 1) begin : g_cdc_bank // 生成当前 bank CDC bridge
            wire [524:0] source_write_word; // 打包当前 bank Tensor source metadata 和 payload
            wire [614:0] result_write_word; // 打包当前 bank slice result metadata 和 payload
            wire [614:0] result_read_word; // 保存当前 bank Tensor 域 result FIFO 输出
            assign source_write_word = {source_dst_i[cdc_bank*5 +: 5], source_eop_i[cdc_bank], source_bytes_i[cdc_bank*7 +: 7], source_data_i[cdc_bank*512 +: 512]}; // 原子打包 source crossing 数据
            coll_async_fifo #(.WIDTH(525), .ADDR_W(3)) u_source_fifo ( // 实例化 Tensor 到 slice 的八深度 async FIFO
                .write_clk_i(tensor_clk_i), .write_rst_n_i(tensor_rst_n_i), .write_data_i(source_write_word), .write_valid_i(source_valid_i[cdc_bank]), .write_ready_o(source_ready_o[cdc_bank]), // 连接 Tensor 域 source 写口
                .read_clk_i(slice_clk_i), .read_rst_n_i(slice_rst_n_i), .read_data_o(slice_source_word[cdc_bank*525 +: 525]), .read_valid_o(slice_source_valid[cdc_bank]), .read_ready_i(slice_source_ready[cdc_bank]), // 连接 slice 域 source 读口
                .overflow_o(source_overflow[cdc_bank]), .underflow_o(source_underflow[cdc_bank]) // 连接 source FIFO 错误状态
            ); // 结束 source async FIFO 实例
            assign slice_source_data[cdc_bank*512 +: 512] = slice_source_word[cdc_bank*525 +: 512]; // 解包 slice 域 source payload
            assign slice_source_bytes[cdc_bank*7 +: 7] = slice_source_word[cdc_bank*525 + 512 +: 7]; // 解包 slice 域 source 字节数
            assign slice_source_eop[cdc_bank] = slice_source_word[cdc_bank*525 + 519]; // 解包 slice 域 source EOP
            assign slice_source_dst[cdc_bank*5 +: 5] = slice_source_word[cdc_bank*525 + 520 +: 5]; // 解包 slice 域 source destination
            assign result_write_word = {slice_result_bytes[cdc_bank*7 +: 7], slice_result_header[cdc_bank*96 +: 96], slice_result_data[cdc_bank*512 +: 512]}; // 原子打包 result crossing 数据
            coll_async_fifo #(.WIDTH(615), .ADDR_W(3)) u_result_fifo ( // 实例化 slice 到 Tensor 的八深度 async FIFO
                .write_clk_i(slice_clk_i), .write_rst_n_i(slice_rst_n_i), .write_data_i(result_write_word), .write_valid_i(slice_result_valid[cdc_bank]), .write_ready_o(slice_result_ready[cdc_bank]), // 连接 slice 域 result 写口
                .read_clk_i(tensor_clk_i), .read_rst_n_i(tensor_rst_n_i), .read_data_o(result_read_word), .read_valid_o(result_valid_o[cdc_bank]), .read_ready_i(result_ready_i[cdc_bank]), // 连接 Tensor 域 result 读口
                .overflow_o(result_overflow[cdc_bank]), .underflow_o(result_underflow[cdc_bank]) // 连接 result FIFO 错误状态
            ); // 结束 result async FIFO 实例
            assign tensor_result_word[cdc_bank*615 +: 615] = result_read_word; // 保存当前 bank result crossing word
            assign result_data_o[cdc_bank*512 +: 512] = result_read_word[511:0]; // 解包 Tensor 域 result payload
            assign result_header_o[cdc_bank*96 +: 96] = result_read_word[512 +: 96]; // 解包 Tensor 域 result header
            assign result_bytes_o[cdc_bank*7 +: 7] = result_read_word[608 +: 7]; // 解包 Tensor 域 result 字节数
        end // 结束当前 bank CDC bridge
    endgenerate // 结束十六 bank 双向 async FIFO 生成
    kdlink_nic8 u_nic ( // 实例化 slice 域八 plane NIC
        .clk_i(slice_clk_i), .rst_n_i(slice_rst_n_i), // 连接 slice 域时钟复位
        .start_i(start_i), .start_ready_o(start_ready_o), .descriptor_i(descriptor_i), .phase_i(phase_i), .link_epoch_i(link_epoch_i), .finish_i(finish_i), .active_o(active_o), .descriptor_error_o(descriptor_error_o), // 连接 slice 域 operation 控制
        .source_valid_i(slice_source_valid), .source_ready_o(slice_source_ready), .source_data_i(slice_source_data), .source_bytes_i(slice_source_bytes), .source_eop_i(slice_source_eop), .source_dst_i(slice_source_dst), // 连接 source FIFO slice 域读口
        .link_tx_valid_o(link_tx_valid_o), .link_tx_ready_i(link_tx_ready_i), .link_tx_header_o(link_tx_header_o), .link_tx_data_o(link_tx_data_o), .link_tx_bytes_o(link_tx_bytes_o), // 连接 slice 域 link TX
        .link_rx_valid_i(link_rx_valid_i), .link_rx_ready_o(link_rx_ready_o), .link_rx_header_i(link_rx_header_i), .link_rx_data_i(link_rx_data_i), .link_rx_bytes_i(link_rx_bytes_i), // 连接 slice 域 link RX
        .result_valid_o(slice_result_valid), .result_ready_i(slice_result_ready), .result_header_o(slice_result_header), .result_data_o(slice_result_data), .result_bytes_o(slice_result_bytes), // 连接 result FIFO slice 域写口
        .source_stall_o(source_stall_unused), .result_stall_o(result_stall_unused) // 连接未导出的本地 stall 状态
    ); // 结束 slice 域 NIC 实例
endmodule // 结束异步 Tensor NIC wrapper
