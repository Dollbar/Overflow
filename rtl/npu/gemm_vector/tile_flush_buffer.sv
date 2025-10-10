`timescale 1ns/1ps // 定义Tile清空缓冲单元的仿真时间单位和精度
`default_nettype none // 禁止隐式网络掩盖控制端口拼写错误

(* keep_hierarchy = "yes" *) // 保留组合缓冲层次以阻止综合重新合并高扇出清空网络
module tile_flush_buffer #( // 定义一组无额外时钟周期的局部同步清空缓冲
    parameter integer BUFFER_ID = 0 // 为每个物理控制分组生成独立的参数化层次
) ( // 开始局部清空缓冲端口列表
    input  logic rst_i, // 接收顶层同步高有效复位
    input  logic clear_i, // 接收顶层同步高有效清空
    output logic flush_o // 输出当前物理分组使用的组合高有效清空条件
); // 结束局部清空缓冲端口列表

    generate // 使用参数化生成块维持各个局部缓冲实例的独立层次
        if (BUFFER_ID >= 0) begin : gen_valid_buffer // 对所有非负编号生成相同的复位和清空合并逻辑
            assign flush_o = rst_i || clear_i; // 组合合并控制且不增加任何接口或状态更新周期
        end // 结束有效局部缓冲生成分支
    endgenerate // 结束局部清空缓冲生成结构

endmodule // 结束tile_flush_buffer模块

`default_nettype wire // 恢复默认网络类型避免影响后续编译单元
