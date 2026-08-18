module kdlink_v2_fabric32 ( // 定义三十二节点八 plane 双 slice 逻辑交换 fabric
    input wire clk_i, // 接收 fabric 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [511:0] endpoint_tx_valid_i, // 接收三十二 endpoint 各十六 slice TX valid
    output wire [511:0] endpoint_tx_ready_o, // 返回三十二 endpoint 各十六 slice 本地许可
    input wire [327679:0] endpoint_tx_flit_i, // 接收五百一十二路 640-bit logical flit
    output wire [511:0] endpoint_rx_valid_o, // 输出三十二 endpoint 各十六 slice RX valid
    input wire [511:0] endpoint_rx_ready_i, // 接收三十二 endpoint 各十六 slice RX 许可
    output wire [327679:0] endpoint_rx_flit_o, // 输出五百一十二路 640-bit logical flit
    output wire [15:0] protocol_error_o // 输出八 plane 双 slice 协议错误位
); // 结束端口声明
    wire [511:0] plane_ingress_valid; // 保存八 plane 各六十四 ingress valid
    wire [511:0] plane_ingress_ready; // 保存八 plane 各六十四 ingress ready
    wire [327679:0] plane_ingress_flit; // 保存八 plane ingress flit
    wire [511:0] plane_egress_valid; // 保存八 plane 各六十四 egress valid
    wire [511:0] plane_egress_ready; // 保存八 plane 各六十四 egress ready
    wire [327679:0] plane_egress_flit; // 保存八 plane egress flit
    wire [511:0] escape_pending_unused; // 保存未导出的 escape pending 状态
    genvar map_node; // 提供 endpoint node 静态映射索引
    genvar map_plane; // 提供 fabric plane 静态映射索引
    genvar map_slice; // 提供 bonded slice 静态映射索引
    generate // 在 endpoint-major 与 plane-major packed bus 之间建立静态映射
        for (map_node = 0; map_node < 32; map_node = map_node + 1) begin : g_map_node // 生成一个 endpoint node 映射
            for (map_plane = 0; map_plane < 8; map_plane = map_plane + 1) begin : g_map_plane // 生成该 node 的八个 plane 映射
                for (map_slice = 0; map_slice < 2; map_slice = map_slice + 1) begin : g_map_slice // 生成该 plane 的双 slice 映射
                    localparam integer ENDPOINT_INDEX = map_node*16 + map_plane*2 + map_slice; // 计算 endpoint-major slice 索引
                    localparam integer PLANE_INDEX = map_plane*64 + map_slice*32 + map_node; // 计算 plane-major switch port 索引
                    assign plane_ingress_valid[PLANE_INDEX] = endpoint_tx_valid_i[ENDPOINT_INDEX]; // 映射 endpoint TX valid 到对应 plane ingress
                    assign endpoint_tx_ready_o[ENDPOINT_INDEX] = plane_ingress_ready[PLANE_INDEX]; // 映射对应 plane ingress ready 回 endpoint
                    assign plane_ingress_flit[PLANE_INDEX*640 +: 640] = endpoint_tx_flit_i[ENDPOINT_INDEX*640 +: 640]; // 映射 endpoint TX flit 到对应 plane ingress
                    assign endpoint_rx_valid_o[ENDPOINT_INDEX] = plane_egress_valid[PLANE_INDEX]; // 映射对应 plane egress valid 到 endpoint RX
                    assign plane_egress_ready[PLANE_INDEX] = endpoint_rx_ready_i[ENDPOINT_INDEX]; // 映射 endpoint RX ready 到对应 plane egress
                    assign endpoint_rx_flit_o[ENDPOINT_INDEX*640 +: 640] = plane_egress_flit[PLANE_INDEX*640 +: 640]; // 映射对应 plane egress flit 到 endpoint RX
                end // 结束双 slice 映射
            end // 结束八 plane 映射
        end // 结束三十二 node 映射
    endgenerate // 结束 endpoint 与 plane packed bus 映射
    genvar plane_index; // 提供八个 KDSwitch plane 生成索引
    generate // 生成八个完全独立的双 slice KDSwitch32 plane
        for (plane_index = 0; plane_index < 8; plane_index = plane_index + 1) begin : g_plane // 生成当前 plane switch
            kdlink_v2_switch32 u_switch ( // 实例化当前三十二端口双 slice switch
                .clk_i(clk_i), .rst_n_i(rst_n_i), // 连接 fabric 时钟和复位
                .ingress_valid_i(plane_ingress_valid[plane_index*64 +: 64]), .ingress_ready_o(plane_ingress_ready[plane_index*64 +: 64]), .ingress_flit_i(plane_ingress_flit[plane_index*40960 +: 40960]), // 连接当前 plane ingress
                .egress_valid_o(plane_egress_valid[plane_index*64 +: 64]), .egress_ready_i(plane_egress_ready[plane_index*64 +: 64]), .egress_flit_o(plane_egress_flit[plane_index*40960 +: 40960]), // 连接当前 plane egress
                .escape_pending_o(escape_pending_unused[plane_index*64 +: 64]), .protocol_error_o(protocol_error_o[plane_index*2 +: 2]) // 连接当前 plane 状态
            ); // 结束当前 plane switch 实例
        end // 结束当前 plane 生成
    endgenerate // 结束八 plane switch 生成
endmodule // 结束三十二节点八 plane fabric
