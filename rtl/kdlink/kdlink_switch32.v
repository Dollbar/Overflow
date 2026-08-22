module kdlink_switch32 ( // 定义双 slice 独立数据面的三十二端口 KDSwitch
    input wire clk_i, // 接收 switch 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [63:0] ingress_valid_i, // 接收两 slice 各三十二 ingress valid
    output wire [63:0] ingress_ready_o, // 返回两 slice 各三十二 ingress ready
    input wire [40959:0] ingress_flit_i, // 接收两 slice 各三十二个 640-bit flit
    output wire [63:0] egress_valid_o, // 输出两 slice 各三十二 egress valid
    input wire [63:0] egress_ready_i, // 接收两 slice 各三十二 egress ready
    output wire [40959:0] egress_flit_o, // 输出两 slice 各三十二个 640-bit flit
    output wire [63:0] escape_pending_o, // 输出两 slice 各 ingress escape pending
    output wire [1:0] protocol_error_o // 输出两 slice 协议不变量错误
); // 结束端口声明
    kdlink_switch_slice32 u_slice0 ( // 实例化物理 slice 零独立 switch 数据面
        .clk_i(clk_i), .rst_n_i(rst_n_i), .ingress_valid_i(ingress_valid_i[31:0]), .ingress_ready_o(ingress_ready_o[31:0]), .ingress_flit_i(ingress_flit_i[20479:0]), // 连接 slice 零 ingress
        .egress_valid_o(egress_valid_o[31:0]), .egress_ready_i(egress_ready_i[31:0]), .egress_flit_o(egress_flit_o[20479:0]), .escape_pending_o(escape_pending_o[31:0]), .protocol_error_o(protocol_error_o[0]) // 连接 slice 零 egress 和状态
    ); // 结束 slice 零实例
    kdlink_switch_slice32 u_slice1 ( // 实例化物理 slice 一独立 switch 数据面
        .clk_i(clk_i), .rst_n_i(rst_n_i), .ingress_valid_i(ingress_valid_i[63:32]), .ingress_ready_o(ingress_ready_o[63:32]), .ingress_flit_i(ingress_flit_i[40959:20480]), // 连接 slice 一 ingress
        .egress_valid_o(egress_valid_o[63:32]), .egress_ready_i(egress_ready_i[63:32]), .egress_flit_o(egress_flit_o[40959:20480]), .escape_pending_o(escape_pending_o[63:32]), .protocol_error_o(protocol_error_o[1]) // 连接 slice 一 egress 和状态
    ); // 结束 slice 一实例
endmodule // 结束双 slice KDSwitch
