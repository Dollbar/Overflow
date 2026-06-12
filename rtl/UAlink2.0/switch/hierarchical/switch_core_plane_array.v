`timescale 1ns/1ps // 定义多Plane阵列数字仿真的统一时间单位。
`default_nettype none // 禁止隐式网络掩盖Plane与Group展平索引错误。
module switch_core_plane_array #( // 静态复制独立8x8 Core Plane，避免形成跨Plane中央仲裁器。
    parameter integer C_NUM_PLANES = 2, // reduced为2，完整参考profile为32。
    parameter integer C_DATA_WIDTH = 32, // 每个内部flit的数据位宽。
    parameter integer C_META_WIDTH = 32 // 每个内部flit的路由及事务元数据位宽。
) (
    input wire i_clk, // 全部Plane状态使用同一已同步fabric时钟更新。
    input wire i_rstn, // 同步低有效复位清除各Plane逐包owner。
    input wire [C_NUM_PLANES*8-1:0] i_valid, // 按plane*8+source_group排列的输入有效位。
    input wire [C_NUM_PLANES*8-1:0] i_route_valid, // 每个Plane输入的路由合法资格。
    output wire [C_NUM_PLANES*8-1:0] o_ready, // 各Plane独立返回逐Group接纳状态。
    input wire [C_NUM_PLANES*8*C_DATA_WIDTH-1:0] i_data, // 按Plane后Group顺序展平的payload。
    input wire [C_NUM_PLANES*8*C_META_WIDTH-1:0] i_meta, // 与payload同索引的内部元数据。
    input wire [C_NUM_PLANES*24-1:0] i_dst_group, // 每Plane包含八个三位目的Group。
    input wire [C_NUM_PLANES*8-1:0] i_sop, // 每路packet首拍标志。
    input wire [C_NUM_PLANES*8-1:0] i_eop, // 每路packet尾拍标志。
    output wire [C_NUM_PLANES*8-1:0] o_valid, // 按plane*8+destination_group排列的输出有效位。
    input wire [C_NUM_PLANES*8-1:0] i_ready, // Destination Group逐Plane的registered admission能力。
    output wire [C_NUM_PLANES*8*C_DATA_WIDTH-1:0] o_data, // Core交换后的payload。
    output wire [C_NUM_PLANES*8*C_META_WIDTH-1:0] o_meta, // Core透明转发的内部元数据。
    output wire [C_NUM_PLANES*8-1:0] o_sop, // Core交换后的首拍标志。
    output wire [C_NUM_PLANES*8-1:0] o_eop, // Core交换后的尾拍标志。
    output wire [C_NUM_PLANES*8-1:0] o_route_error, // 逐Plane输入路由错误。
    output wire [C_NUM_PLANES*8-1:0] o_protocol_error, // 逐Plane输入packet边界错误。
    output wire [C_NUM_PLANES*8-1:0] o_owner_valid, // 每Plane每目的Group的packet owner状态。
    output wire o_quiescent
);
    localparam CONFIG_LEGAL = (C_NUM_PLANES >= 1) && (C_NUM_PLANES <= 32) && // 限制实现为冻结架构允许的Plane规模。
                              (C_DATA_WIDTH >= 1) && (C_META_WIDTH >= 1); // 零位宽配置必须失败关闭。
    wire [C_NUM_PLANES*8-1:0] plane_ready; // 收集叶Plane产生的ready。
    wire [C_NUM_PLANES*8-1:0] plane_valid; // 收集叶Plane产生的valid。
    wire [C_NUM_PLANES*8*C_DATA_WIDTH-1:0] plane_data; // 收集叶Plane payload。
    wire [C_NUM_PLANES*8*C_META_WIDTH-1:0] plane_meta; // 收集叶Plane metadata。
    wire [C_NUM_PLANES*8*C_META_WIDTH-1:0] zero_meta = 0; // 非法配置输出的定宽零，避免超宽复制网络。
    wire [C_NUM_PLANES*8-1:0] plane_sop; // 收集叶Plane SOP。
    wire [C_NUM_PLANES*8-1:0] plane_eop; // 收集叶Plane EOP。
    wire [C_NUM_PLANES*8-1:0] plane_route_error; // 收集叶Plane route error。
    wire [C_NUM_PLANES*8-1:0] plane_protocol_error; // 收集叶Plane protocol error。
    wire [C_NUM_PLANES*8-1:0] plane_owner_valid; // 收集叶Plane owner状态。
    wire [C_NUM_PLANES-1:0] plane_quiescent;
    assign o_ready = CONFIG_LEGAL ? plane_ready : {(C_NUM_PLANES*8){1'b0}}; // 非法参数禁止接受数据。
    assign o_valid = CONFIG_LEGAL ? plane_valid : {(C_NUM_PLANES*8){1'b0}}; // 非法参数禁止发送数据。
    assign o_data = CONFIG_LEGAL ? plane_data : {(C_NUM_PLANES*8*C_DATA_WIDTH){1'b0}}; // 非法参数输出确定零。
    assign o_meta = CONFIG_LEGAL ? plane_meta : zero_meta; // 非法参数输出确定零。
    assign o_sop = CONFIG_LEGAL ? plane_sop : {(C_NUM_PLANES*8){1'b0}}; // 非法参数不产生SOP。
    assign o_eop = CONFIG_LEGAL ? plane_eop : {(C_NUM_PLANES*8){1'b0}}; // 非法参数不产生EOP。
    assign o_route_error = CONFIG_LEGAL ? plane_route_error : {(C_NUM_PLANES*8){1'b1}}; // 非法参数显式报告错误。
    assign o_protocol_error = CONFIG_LEGAL ? plane_protocol_error : {(C_NUM_PLANES*8){1'b1}}; // 非法参数显式报告错误。
    assign o_owner_valid = CONFIG_LEGAL ? plane_owner_valid : {(C_NUM_PLANES*8){1'b0}}; // 非法参数不保留owner。
    assign o_quiescent = CONFIG_LEGAL && (&plane_quiescent);
    genvar plane_index; // 每个生成索引对应一个物理独立Core Plane。
    generate
        for (plane_index = 0; plane_index < C_NUM_PLANES; plane_index = plane_index + 1) begin : g_core_plane
            switch_core_plane_8x8 #(
                .DATA_WIDTH(C_DATA_WIDTH), .META_WIDTH(C_META_WIDTH)
            ) u_plane (
                .clk(i_clk), .i_rstn(i_rstn && CONFIG_LEGAL),
                .i_valid(i_valid[plane_index*8 +: 8]),
                .i_route_valid(i_route_valid[plane_index*8 +: 8]),
                .o_ready(plane_ready[plane_index*8 +: 8]),
                .i_data(i_data[plane_index*8*C_DATA_WIDTH +: 8*C_DATA_WIDTH]),
                .i_meta(i_meta[plane_index*8*C_META_WIDTH +: 8*C_META_WIDTH]),
                .i_dst_group(i_dst_group[plane_index*24 +: 24]),
                .i_sop(i_sop[plane_index*8 +: 8]), .i_eop(i_eop[plane_index*8 +: 8]),
                .o_valid(plane_valid[plane_index*8 +: 8]),
                .i_ready(i_ready[plane_index*8 +: 8]),
                .o_data(plane_data[plane_index*8*C_DATA_WIDTH +: 8*C_DATA_WIDTH]),
                .o_meta(plane_meta[plane_index*8*C_META_WIDTH +: 8*C_META_WIDTH]),
                .o_sop(plane_sop[plane_index*8 +: 8]), .o_eop(plane_eop[plane_index*8 +: 8]),
                .o_route_error(plane_route_error[plane_index*8 +: 8]),
                .o_protocol_error(plane_protocol_error[plane_index*8 +: 8]),
                .o_owner_valid(plane_owner_valid[plane_index*8 +: 8]),.o_quiescent(plane_quiescent[plane_index])
            );
        end
    endgenerate
endmodule
`default_nettype wire // 恢复后续编译单元的默认网络规则。
