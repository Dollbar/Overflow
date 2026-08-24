`timescale 1ns/1ps // 定义权重格式局部通道的仿真时间单位和精度

(* keep_hierarchy = "yes" *) // 保留列级格式通道层次以便综合和布局阶段维持扇出分区
module tile_weight_format_slice ( // 定义单个权重列的格式选择通道
    input  logic                      select_i, // 指示当前周期是否正在装载本列权重
    input  logic                [1:0] global_format_i, // 输入当前装载事务的全局格式编码
    input  logic                [1:0] saved_format_i, // 输入本列最近一次已保存的格式编码
    output logic                [1:0] format_o // 输出送往本列全部PE的局部格式编码
); // 结束单列权重格式通道端口列表

    assign format_o = select_i ? global_format_i : saved_format_i; // 装载时选择当前事务格式，其余时间保持列格式

endmodule // 结束单列权重格式通道
