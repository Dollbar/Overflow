`timescale 1ns/1ps // 定义带FIFO Tile顶层的仿真时间单位和精度
`default_nettype none // 禁止隐式网络掩盖跨层端口连接错误

module TILE_FP8_16_FIFO #( // 集成双输入FIFO、FP8计算核心和十六路输出FIFO的Tile顶层
    parameter bit DAZ = 1'b0, // 选择是否把输入FP8非规格数视为零
    parameter bit FTZ = 1'b0, // 选择是否把输出下溢结果冲刷为零
    parameter bit STATIC_WEIGHT_MODE = 1'b0, // 允许先独立装载十六列B并由后续A重复使用
    parameter bit EXACT_OUTPUT_MODE = 1'b0 // 选择Tile内SRAM FIFO保存精确Q32而非提前舍入FP32
) ( // 开始缓冲Tile顶层端口列表
    input  logic                         clk_i, // 提供全部FIFO和计算核心共用的上升沿时钟
    input  logic                         rst_i, // 提供同步高有效复位并丢弃全部缓冲和在途事务
    input  logic                         clear_i, // 同步清空全部FIFO和计算流水线控制状态
    input  logic                         input_issue_enable_i, // 允许非空A/B输入对进入计算核心，供路由批次预填充使用
    input  logic                         a_valid_i, // 表示A激活行输入当前有效
    output logic                         a_ready_o, // 表示A输入FIFO能够接受当前激活行
    input  logic                 [127:0] a_data_i, // 提供十六个FP8激活元素
    input  fp8_pkg::fp8_format_e         a_format_i, // 指定当前A激活行的FP8格式
    input  fp8_pkg::fp8_rounding_e       rounding_i, // 指定当前A/B配对事务的FP32舍入模式
    input  logic                         b_valid_i, // 表示B权重列输入当前有效
    output logic                         b_ready_o, // 表示B输入FIFO能够接受当前权重列
    input  logic                 [127:0] b_data_i, // 提供十六个FP8权重元素
    input  fp8_pkg::fp8_format_e         b_format_i, // 指定当前B权重列的FP8格式
    input  logic                         a_east_ready_i, // 表示东侧相邻Tile能够接收直通A激活行
    output logic                         a_east_valid_o, // 表示东向直通A激活行当前有效
    output logic                 [127:0] a_east_data_o, // 输出与本Tile实际发射严格对齐的东向A激活行
    output fp8_pkg::fp8_format_e         a_east_format_o, // 输出东向A激活行的FP8格式
    output fp8_pkg::fp8_rounding_e       a_east_rounding_o, // 输出东向A激活行对应的舍入模式
    input  logic                         b_south_ready_i, // 表示南侧相邻Tile能够接收直通B权重列
    output logic                         b_south_valid_o, // 表示南向直通B权重列当前有效
    output logic                 [127:0] b_south_data_o, // 输出与本Tile实际发射严格对齐的南向B权重列
    output fp8_pkg::fp8_format_e         b_south_format_o, // 输出南向B权重列的FP8格式
    output logic                   [3:0] b_south_column_o, // 输出南向B权重列在当前Tile中的循环列号
    input  logic                         result_ready_i, // 表示下游能够同拍接收完整十六列结果行
    output logic                         result_valid_o, // 表示十六个输出FIFO队首已经组成完整结果行
    output logic                 [511:0] result_data_o, // 输出按列拼接的十六个FP32结果
    output logic                  [15:0] result_invalid_o, // 输出完整结果行逐列对应的无效运算标志
    input  logic                         exact_result_ready_i, // 表示下游能够接收一行精确定点结果
    output logic                         exact_result_valid_o, // 表示精确结果SRAM FIFO队首有效
    output logic                [1103:0] exact_result_sum_o, // 输出十六列69位Q32精确块和
    output logic                  [31:0] exact_result_special_o, // 输出十六列特殊值状态
    output logic                  [31:0] exact_result_zero_sign_o, // 输出十六列零符号状态
    output logic                  [15:0] exact_result_invalid_o, // 输出十六列无效运算状态
    output logic                  [31:0] exact_result_rounding_o, // 输出十六列舍入模式
    output logic                   [5:0] exact_result_level_o, // 输出精确结果FIFO当前占用数量
    output logic                         input_pair_valid_o, // 表示A和B两个输入FIFO队首均非空
    output logic                         input_pair_issue_o, // 动态模式表示A/B对发射，静态模式表示A计算发射
    output logic                         input_a_issue_o, // 表示本拍独立消费一个A队首并发起计算
    output logic                         input_b_issue_o, // 表示本拍独立消费一个B队首并装载权重
    output logic                         weights_loaded_o, // 表示计算核心已经至少装载全部十六个权重列
    output logic                         weight_block_loaded_o, // 每完成一组十六列B装载时产生单拍脉冲
    output logic                         input_a_full_o, // 表示A输入FIFO已经占用全部三十二项
    output logic                         input_a_empty_o, // 表示A输入FIFO当前为空
    output logic                   [5:0] input_a_level_o, // 输出A输入FIFO当前占用数量
    output logic                         input_b_full_o, // 表示B输入FIFO已经占用全部三十二项
    output logic                         input_b_empty_o, // 表示B输入FIFO当前为空
    output logic                   [5:0] input_b_level_o, // 输出B输入FIFO当前占用数量
    output logic                  [15:0] result_lane_full_o, // 输出十六个结果FIFO各自的满状态
    output logic                  [15:0] result_lane_empty_o, // 输出十六个结果FIFO各自的空状态
    output logic                  [95:0] result_lane_level_o, // 输出十六个结果FIFO各自的六位占用数量
    output logic                         output_overflow_o, // 粘滞标识计算结果到达时对应输出FIFO没有空间
    output logic                  [15:0] act_right_valid_o, // 输出计算核心右边界逐行激活有效状态
    output logic                 [127:0] act_right_data_o, // 输出计算核心右边界逐行FP8激活数据
    output logic                  [15:0] act_right_format_o // 输出计算核心右边界逐行FP8格式
); // 结束缓冲Tile顶层端口列表

    localparam integer TILE_SIZE = 16; // 固定Tile包含十六行和十六列
    localparam integer FIFO_DEPTH = 32; // 固定输入输出FIFO逻辑深度为三十二
    localparam integer OUTPUT_FLUSH_GROUPS = 8; // 每组局部清空只驱动两列输出旁带指针

    logic [127:0] input_a_head_data; // 接收A输入FIFO保持式队首数据
    logic [127:0] input_b_head_data; // 接收B输入FIFO保持式队首数据
    logic input_a_head_valid; // 接收A输入FIFO独立队首有效状态
    logic input_b_head_valid; // 接收B输入FIFO独立队首有效状态
    logic core_act_ready; // 接收计算核心激活输入就绪状态
    logic core_weight_ready; // 接收计算核心权重输入就绪状态
    logic core_input_ready; // 汇总计算核心对完整A/B输入对的接收许可
    logic core_pair_valid; // 仅在两个直通出口均可容纳新事务时向计算核心声明输入对有效
    logic core_act_valid; // 选择动态成对或静态独立协议后的核心A有效
    logic core_weight_valid; // 选择动态成对或静态独立协议后的核心B有效
    logic input_a_pop_ready; // 向输入FIFO提供静态模式A独立出队许可
    logic input_b_pop_ready; // 向输入FIFO提供静态模式B独立出队许可
    logic a_path_ready; // 表示东向A弹性寄存器能够接受新数据
    logic b_path_ready; // 表示南向B弹性寄存器能够接受新数据
    logic direct_path_ready; // 汇总东向A和南向B两个弹性出口的替换许可
    logic [2:0] a_east_meta_q; // 保存东向A格式和舍入旁带的局部切片输出
    logic [4:0] b_south_meta_q; // 保存南向B格式和循环列号旁带的局部切片输出
    logic [3:0] weight_column_q; // 自动记录下一对B权重写入的计算核心列号
    logic input_a_write_fire; // 标识A输入FIFO本拍接受了一项数据和旁带信息
    logic input_b_write_fire; // 标识B输入FIFO本拍接受了一项数据和旁带信息
    logic input_a_meta_store; // 允许A旁带写空闲槽且刻意不让同步清空进入存储写使能
    logic input_b_meta_store; // 允许B旁带写空闲槽且刻意不让同步清空进入存储写使能
    logic [4:0] input_a_meta_wr_ptr_q; // 保存A格式和舍入旁带的下一个写地址
    logic [4:0] input_a_meta_rd_ptr_q; // 保存A格式和舍入旁带的当前队首地址
    logic [4:0] input_b_meta_wr_ptr_q; // 保存B格式旁带的下一个写地址
    logic [4:0] input_b_meta_rd_ptr_q; // 保存B格式旁带的当前队首地址
    logic [2:0] input_a_meta_mem [0:FIFO_DEPTH-1]; // 保存每项A输入的两位舍入模式和一位FP8格式
    logic input_b_format_mem [0:FIFO_DEPTH-1]; // 保存每项B输入的一位FP8格式
    fp8_pkg::fp8_format_e core_act_format; // 恢复与A队首严格对齐的FP8格式
    fp8_pkg::fp8_format_e core_weight_format; // 恢复与B队首严格对齐的FP8格式
    fp8_pkg::fp8_rounding_e core_rounding; // 恢复与A/B队首严格对齐的舍入模式
    logic [15:0] core_result_valid; // 接收计算核心逐列错峰结果有效状态
    logic [511:0] core_result_data; // 接收计算核心逐列FP32结果数据
    logic [15:0] core_result_invalid; // 接收计算核心逐列无效运算标志
    logic [15:0] core_exact_valid; // 接收十六列同步到达的精确Q32结果有效状态
    logic [1103:0] core_exact_sum; // 接收十六列69位精确Q32块和
    logic [31:0] core_exact_special; // 接收十六列特殊值旁带
    logic [31:0] core_exact_zero_sign; // 接收十六列零符号旁带
    logic [15:0] core_exact_invalid; // 接收十六列精确结果无效旁带
    logic [31:0] core_exact_rounding; // 接收十六列舍入模式旁带
    logic [15:0] exact_lane_write_ready; // 接收十六个精确列FIFO各自的写入credit
    logic [15:0] exact_lane_read_valid; // 标识十六个精确列FIFO各自存在有效队首
    logic [2047:0] exact_lane_read_data; // 接收十六个128位精确列FIFO队首
    logic [95:0] exact_lane_level; // 接收十六个精确列FIFO各自的六位占用数量
    logic exact_row_pop; // 十六个精确列队首同时被下游原子消费
    logic [15:0] result_lane_write_ready; // 接收十六个输出FIFO各自的写入许可
    logic [511:0] result_lane_read_data; // 接收十六个输出FIFO各自的FP32队首数据
    logic [15:0] result_lane_write_fire; // 标识逐列结果实际写入对应输出FIFO
    logic [15:0] result_lane_meta_store; // 允许结果旁带写空闲槽且不让同步清空进入存储写使能
    logic result_row_pop; // 标识下游同拍消费十六个输出FIFO队首
    logic complete_row_arrival_q; // 将最后一列入队事件延迟到对应SRAM队首可用周期
    logic [5:0] complete_rows_q; // 记录十六列均已到达且能够被下游消费的完整结果行数
    logic result_available_q; // 独立保存完整结果行非空状态以避免六位零检测进入握手关键路径
    logic input_control_flush; // 为输入旁带指针和权重列号提供局部组合清空
    logic result_control_flush; // 为完整行计数和溢出状态提供局部组合清空
    logic [OUTPUT_FLUSH_GROUPS-1:0] output_meta_flush_group; // 为每两列输出旁带指针提供一组局部组合清空
    logic [4:0] output_meta_wr_ptr_q [0:TILE_SIZE-1]; // 保存每列异常旁带的下一个写地址
    logic [4:0] output_meta_rd_ptr_q [0:TILE_SIZE-1]; // 保存每列异常旁带的当前队首地址
    logic output_invalid_mem [0:TILE_SIZE-1][0:FIFO_DEPTH-1]; // 保存与各列FP32结果严格对齐的异常旁带
    integer metadata_store_column_index; // 遍历无需复位的十六列异常旁带存储阵列

    generate // 构造不增加周期的分层组合清空树以限制单个综合网的控制扇出
        (* keep = "true", dont_touch = "true" *)
        tile_flush_buffer #(
            .BUFFER_ID (0)
        ) u_input_control_flush_buffer (
            .rst_i   (rst_i),
            .clear_i (clear_i),
            .flush_o (input_control_flush)
        );

        (* keep = "true", dont_touch = "true" *)
        tile_flush_buffer #(
            .BUFFER_ID (1)
        ) u_result_control_flush_buffer (
            .rst_i   (rst_i),
            .clear_i (clear_i),
            .flush_o (result_control_flush)
        );

        for (genvar output_flush_group_index = 0;
             output_flush_group_index < OUTPUT_FLUSH_GROUPS;
             output_flush_group_index = output_flush_group_index + 1) begin : gen_output_flush_buffers
            (* keep = "true", dont_touch = "true" *)
            tile_flush_buffer #(
                .BUFFER_ID (output_flush_group_index + 2)
            ) u_output_meta_flush_buffer (
                .rst_i   (rst_i),
                .clear_i (clear_i),
                .flush_o (output_meta_flush_group[output_flush_group_index])
            );
        end
    endgenerate

    assign input_a_write_fire = a_valid_i && a_ready_o; // A输入valid和ready同时有效时记录对应旁带
    assign input_b_write_fire = b_valid_i && b_ready_o; // B输入valid和ready同时有效时记录对应旁带
    assign a_path_ready = !a_east_valid_o || a_east_ready_i; // 东向寄存器为空或同拍被消费时允许替换
    assign b_path_ready = !b_south_valid_o || b_south_ready_i; // 南向寄存器为空或同拍被消费时允许替换
    assign direct_path_ready = a_path_ready && b_path_ready; // 动态模式仍要求两个直通方向同时可接受
    assign core_pair_valid = input_pair_valid_o && direct_path_ready &&
                             input_issue_enable_i; // 路由批次未收齐或直通出口反压时抑制核心A/B有效
    assign core_input_ready = core_act_ready && core_weight_ready; // 动态核心的ready只有在已门控的A/B valid同时有效时才会成立
    assign core_act_valid = STATIC_WEIGHT_MODE ?
                            (input_a_head_valid && a_path_ready &&
                             input_issue_enable_i) : core_pair_valid; // 静态模式只需A路径可替换即可向核心发射激活
    assign core_weight_valid = STATIC_WEIGHT_MODE ?
                               (input_b_head_valid && b_path_ready &&
                                input_issue_enable_i) : core_pair_valid; // 静态模式允许B不依赖A独立装载
    assign input_a_pop_ready = STATIC_WEIGHT_MODE && core_act_ready &&
                               a_path_ready && input_issue_enable_i; // 核心和东向直通同时接收时弹出A
    assign input_b_pop_ready = STATIC_WEIGHT_MODE && core_weight_ready &&
                               b_path_ready && input_issue_enable_i; // 核心和南向直通同时接收时弹出B
    assign input_a_issue_o = STATIC_WEIGHT_MODE ?
                             (core_act_valid && core_act_ready) :
                             (input_pair_valid_o && core_input_ready); // 输出实际A消费事件
    assign input_b_issue_o = STATIC_WEIGHT_MODE ?
                             (core_weight_valid && core_weight_ready) :
                             (input_pair_valid_o && core_input_ready); // 输出实际B消费事件
    assign input_pair_issue_o = input_a_issue_o; // 保持系统级计算发射计数语义，静态装权重不计为计算
    assign weight_block_loaded_o = input_b_issue_o &&
                                   (weight_column_q == 4'd15); // 第十五列被核心接受即完成当前权重块
    assign core_act_format = fp8_pkg::fp8_format_e'(input_a_meta_mem[input_a_meta_rd_ptr_q][0]); // 从A旁带队首恢复激活格式
    assign core_rounding = fp8_pkg::fp8_rounding_e'(input_a_meta_mem[input_a_meta_rd_ptr_q][2:1]); // 从A旁带队首恢复舍入模式
    assign core_weight_format = fp8_pkg::fp8_format_e'(input_b_format_mem[input_b_meta_rd_ptr_q]); // 从B旁带队首恢复权重格式
    assign result_lane_write_fire = core_result_valid & result_lane_write_ready; // 逐列标识已经被输出FIFO接受的结果
    assign input_a_meta_store = input_a_write_fire; // 只在A数据FIFO真正接收时写入对齐旁带
    assign input_b_meta_store = input_b_write_fire; // 只在B数据FIFO真正接收时写入对齐旁带
    assign result_lane_meta_store = core_result_valid &
                                    (~result_lane_full_o |
                                     {TILE_SIZE{result_row_pop}}); // 正常周期与逐列写握手等价且清空时无需保护无效存储内容
    assign exact_result_valid_o = &exact_lane_read_valid; // 所有错峰列都到达队首后才声明完整精确结果行
    assign exact_row_pop = exact_result_valid_o && exact_result_ready_i; // 下游握手时十六列同步弹出以保持行对齐
    assign result_valid_o = result_available_q; // 独立状态位直接声明至少存在一个完整可消费结果行
    assign result_row_pop = result_valid_o && result_ready_i; // 下游握手时原子弹出十六个列FIFO队首
    assign result_data_o = result_lane_read_data; // 将十六个列FIFO队首拼接为完整512位结果行
    assign a_east_format_o = fp8_pkg::fp8_format_e'(a_east_meta_q[0]); // 从局部旁带切片恢复东向A格式
    assign a_east_rounding_o = fp8_pkg::fp8_rounding_e'(a_east_meta_q[2:1]); // 从局部旁带切片恢复东向A舍入模式
    assign b_south_format_o = fp8_pkg::fp8_format_e'(b_south_meta_q[0]); // 从局部旁带切片恢复南向B格式
    assign b_south_column_o = b_south_meta_q[4:1]; // 从局部旁带切片恢复南向B循环列号

    generate // 把宽直通负载划分为局部寄存切片，避免单个发射使能直接驱动全部数据位
        for (genvar direct_slice_index = 0;
             direct_slice_index < 8;
             direct_slice_index = direct_slice_index + 1) begin : gen_direct_data_slices
            (* keep = "true", dont_touch = "true" *)
            tile_router_output_slice #(
                .WIDTH (16)
            ) u_a_east_data_slice (
                .clk_i  (clk_i),
                .load_i (input_a_issue_o),
                .data_i (input_a_head_data[direct_slice_index*16 +: 16]),
                .data_o (a_east_data_o[direct_slice_index*16 +: 16])
            );

            (* keep = "true", dont_touch = "true" *)
            tile_router_output_slice #(
                .WIDTH (16)
            ) u_b_south_data_slice (
                .clk_i  (clk_i),
                .load_i (input_b_issue_o),
                .data_i (input_b_head_data[direct_slice_index*16 +: 16]),
                .data_o (b_south_data_o[direct_slice_index*16 +: 16])
            );
        end

        (* keep = "true", dont_touch = "true" *)
        tile_router_output_slice #(
            .WIDTH (3)
        ) u_a_east_meta_slice (
            .clk_i  (clk_i),
            .load_i (input_a_issue_o),
            .data_i ({core_rounding, core_act_format}),
            .data_o (a_east_meta_q)
        );

        (* keep = "true", dont_touch = "true" *)
        tile_router_output_slice #(
            .WIDTH (5)
        ) u_b_south_meta_slice (
            .clk_i  (clk_i),
            .load_i (input_b_issue_o),
            .data_i ({weight_column_q, core_weight_format}),
            .data_o (b_south_meta_q)
        );
    endgenerate

    always_ff @(posedge clk_i) begin // 维护A向东和B向南两个独立ready/valid弹性直通寄存器
        if (input_control_flush) begin // 同步复位或清空时丢弃尚未被相邻Tile接收的直通事务
            a_east_valid_o <= 1'b0; // 清除东向A有效状态
            b_south_valid_o <= 1'b0; // 清除南向B有效状态
        end else begin // 未发射新输入对时允许两个出口各自独立完成旧事务
            if (input_a_issue_o) begin // 核心实际接受A时生成东向直通副本
                a_east_valid_o <= 1'b1;
            end else if (a_east_valid_o && a_east_ready_i) begin // 东侧完成A直通握手时释放对应弹性寄存器
                a_east_valid_o <= 1'b0; // 清除已被东侧接收的A有效状态
            end // 结束东向A握手处理
            if (input_b_issue_o) begin // 核心实际接受B时生成南向直通副本
                b_south_valid_o <= 1'b1;
            end else if (b_south_valid_o && b_south_ready_i) begin // 南侧完成B直通握手时释放对应弹性寄存器
                b_south_valid_o <= 1'b0; // 清除已被南侧接收的B有效状态
            end // 结束南向B握手处理
        end // 结束直通寄存器正常工作分支
    end // 结束双方向弹性直通寄存器时序过程

    always_ff @(posedge clk_i) begin // 在统一时钟上推进输入旁带指针和自动权重列号
        if (input_control_flush) begin // 局部同步复位或清空时丢弃全部输入旁带队列状态
            input_a_meta_wr_ptr_q <= 5'd0; // A旁带写指针回到地址零
            input_a_meta_rd_ptr_q <= 5'd0; // A旁带读指针回到地址零
            input_b_meta_wr_ptr_q <= 5'd0; // B旁带写指针回到地址零
            input_b_meta_rd_ptr_q <= 5'd0; // B旁带读指针回到地址零
            weight_column_q <= 4'd0; // 下一项B权重重新从第零列开始装载
        end else begin // 正常周期独立处理输入写入和成对自动取用
            if (input_a_write_fire) begin // A输入FIFO接受数据时同步保存格式和舍入旁带
                input_a_meta_wr_ptr_q <= input_a_meta_wr_ptr_q + 5'd1; // 推进A旁带写指针并自然回绕
            end // 结束A输入旁带写入处理
            if (input_b_write_fire) begin // B输入FIFO接受数据时同步保存格式旁带
                input_b_meta_wr_ptr_q <= input_b_meta_wr_ptr_q + 5'd1; // 推进B旁带写指针并自然回绕
            end // 结束B输入旁带写入处理
            if (input_a_issue_o) begin // 核心接受A队首时推进A旁带读指针
                input_a_meta_rd_ptr_q <= input_a_meta_rd_ptr_q + 5'd1; // 推进A旁带读指针并自然回绕
            end
            if (input_b_issue_o) begin // 核心接受B队首时推进B旁带读指针和循环列号
                input_b_meta_rd_ptr_q <= input_b_meta_rd_ptr_q + 5'd1; // 推进B旁带读指针并自然回绕
                weight_column_q <= weight_column_q + 4'd1; // 自动生成循环的零到十五权重列号
            end // 结束输入对自动取用处理
        end // 结束输入旁带正常工作分支
    end // 结束输入旁带和权重列号时序过程

    always_ff @(posedge clk_i) begin // 旁带存储内容无需复位且仅由有效写槽许可更新
        if (input_a_meta_store) begin // A FIFO非满或满状态同拍出队时当前写槽可以安全覆盖
            input_a_meta_mem[input_a_meta_wr_ptr_q] <= {rounding_i, a_format_i}; // 保存与A数据写地址一致的三位旁带
        end // 结束A旁带存储写入
        if (input_b_meta_store) begin // B FIFO非满或满状态同拍出队时当前写槽可以安全覆盖
            input_b_format_mem[input_b_meta_wr_ptr_q] <= b_format_i; // 保存与B数据写地址一致的一位格式
        end // 结束B旁带存储写入
    end // 结束不需要同步清空的数据阵列写入过程

    always_ff @(posedge clk_i) begin // 在统一时钟上维护完整结果行计数和溢出状态
        if (result_control_flush) begin // 局部同步复位或清空时丢弃全部结果行控制状态
            output_overflow_o <= 1'b0; // 清除历史输出FIFO溢出标志
            complete_row_arrival_q <= 1'b0; // 丢弃尚未对齐到SRAM队首的最后一列到达事件
            complete_rows_q <= 6'd0; // 清除全部已完成结果行的可见状态
            result_available_q <= 1'b0; // 清除完整结果行可用状态
        end else begin // 正常周期处理完整行到达、消费和溢出检测
            complete_row_arrival_q <= result_lane_write_fire[TILE_SIZE-1]; // 最后一列写入后等待一拍匹配FIFO同步预取延迟
            unique case ({complete_row_arrival_q, result_row_pop}) // 合并完整行到达和下游消费对计数的影响
                2'b10: complete_rows_q <= complete_rows_q + 6'd1; // 仅新完整行可见时增加可消费数量
                2'b01: complete_rows_q <= complete_rows_q - 6'd1; // 仅下游消费时减少可消费数量
                default: complete_rows_q <= complete_rows_q; // 同拍到达和消费或均无事件时保持数量
            endcase // 结束完整结果行计数更新
            unique case ({complete_row_arrival_q, result_row_pop}) // 单独维护零延迟的完整行可用状态
                2'b10: result_available_q <= 1'b1; // 任意新完整行到达后至少存在一个可消费队首
                2'b01: result_available_q <= (complete_rows_q > 6'd1); // 只消费时根据消费前数量判断是否仍有完整行
                2'b11: result_available_q <= 1'b1; // 同拍消费并补入完整行时保持连续有效
                default: result_available_q <= result_available_q; // 无完整行数量变化时保持当前有效状态
            endcase // 结束完整行可用状态更新
            if (|(core_result_valid & ~result_lane_write_ready) ||
                (|(core_exact_valid & ~exact_lane_write_ready))) begin // 任一结果没有真实FIFO credit时记录容量违约
                output_overflow_o <= 1'b1; // 粘滞保持输出FIFO容量违约状态
            end // 结束输出溢出检测
        end // 结束结果行控制正常工作分支
    end // 结束完整行计数和溢出状态时序过程

    generate // 按每两列一个清空分组独立维护十六列输出异常旁带指针
        for (genvar metadata_pointer_column = 0;
             metadata_pointer_column < TILE_SIZE;
             metadata_pointer_column = metadata_pointer_column + 1) begin : gen_output_meta_pointers
            localparam integer OUTPUT_FLUSH_GROUP = metadata_pointer_column / 2;
            always_ff @(posedge clk_i) begin // 在统一时钟上维护当前列异常旁带读写指针
                if (output_meta_flush_group[OUTPUT_FLUSH_GROUP]) begin // 局部同步清空只驱动当前两列的二十个指针位
                    output_meta_wr_ptr_q[metadata_pointer_column] <= 5'd0; // 当前列异常旁带写指针回到地址零
                    output_meta_rd_ptr_q[metadata_pointer_column] <= 5'd0; // 当前列异常旁带读指针回到地址零
                end else begin // 正常周期独立推进当前列旁带写指针并统一推进读指针
                    if (result_lane_write_fire[metadata_pointer_column]) begin // 当前列FP32结果实际入队时推进旁带写地址
                        output_meta_wr_ptr_q[metadata_pointer_column] <= output_meta_wr_ptr_q[metadata_pointer_column] + 5'd1; // 五位自然回绕匹配三十二深度
                    end // 结束当前列异常旁带写指针更新
                    if (result_row_pop) begin // 完整结果行被下游接受时推进当前列旁带队首
                        output_meta_rd_ptr_q[metadata_pointer_column] <= output_meta_rd_ptr_q[metadata_pointer_column] + 5'd1; // 五位自然回绕匹配三十二深度
                    end // 结束当前列异常旁带读指针更新
                end // 结束当前列旁带指针正常工作分支
            end // 结束当前列异常旁带指针时序过程
        end // 结束十六列异常旁带指针生成循环
    endgenerate // 结束输出异常旁带指针分组结构

    always_ff @(posedge clk_i) begin // 输出异常旁带内容无需复位且与结果FIFO写槽同步更新
        for (metadata_store_column_index = 0; metadata_store_column_index < TILE_SIZE; metadata_store_column_index = metadata_store_column_index + 1) begin // 逐列检查当前写槽是否允许覆盖
            if (result_lane_meta_store[metadata_store_column_index]) begin // 非满或完整行同拍出队时当前列写槽可安全覆盖
                output_invalid_mem[metadata_store_column_index][output_meta_wr_ptr_q[metadata_store_column_index]] <= core_result_invalid[metadata_store_column_index]; // 写入与当前列FP32数据相同地址的异常旁带
            end // 结束当前列异常旁带存储写入
        end // 结束十六列异常旁带存储遍历
    end // 结束无需同步清空的输出旁带阵列写入过程

    TILE_INPUT_FIFO u_input_fifo ( // 例化两个可独立写入且成对读取的128位输入FIFO
        .clk_i        (clk_i), // 连接Tile统一时钟
        .rst_i        (rst_i), // 连接同步高有效复位
        .clear_i      (clear_i), // 连接同步清空控制
        .a_valid_i    (a_valid_i), // 接收A激活行有效状态
        .a_ready_o    (a_ready_o), // 返回A输入FIFO写入许可
        .a_data_i     (a_data_i), // 接收A激活行数据
        .b_valid_i    (b_valid_i), // 接收B权重列有效状态
        .b_ready_o    (b_ready_o), // 返回B输入FIFO写入许可
        .b_data_i     (b_data_i), // 接收B权重列数据
        .independent_mode_i (STATIC_WEIGHT_MODE), // 静态模式允许A/B队首独立消费
        .pair_ready_i (core_input_ready), // 计算核心就绪时立即取用非空输入对
        .pair_valid_o (input_pair_valid_o), // 输出两个FIFO队首同时有效状态
        .a_ready_i    (input_a_pop_ready), // 静态模式A独立出队许可
        .a_valid_o    (input_a_head_valid), // 接收A独立队首有效状态
        .b_ready_i    (input_b_pop_ready), // 静态模式B独立出队许可
        .b_valid_o    (input_b_head_valid), // 接收B独立队首有效状态
        .a_data_o     (input_a_head_data), // 输出A输入FIFO队首激活行
        .b_data_o     (input_b_head_data), // 输出B输入FIFO队首权重列
        .a_full_o     (input_a_full_o), // 输出A输入FIFO满状态
        .a_empty_o    (input_a_empty_o), // 输出A输入FIFO空状态
        .a_level_o    (input_a_level_o), // 输出A输入FIFO占用数量
        .b_full_o     (input_b_full_o), // 输出B输入FIFO满状态
        .b_empty_o    (input_b_empty_o), // 输出B输入FIFO空状态
        .b_level_o    (input_b_level_o) // 输出B输入FIFO占用数量
    ); // 结束Tile双输入FIFO例化

    TILE_FP8_16 #( // 配置保持独立验证和STA边界的16乘16 FP8计算核心
        .DAZ                (DAZ), // 向计算核心传递输入非规格数处理策略
        .FTZ                (FTZ), // 向计算核心传递输出下溢处理策略
        .STATIC_WEIGHT_MODE (STATIC_WEIGHT_MODE), // 由顶层选择动态流式或静态权重复用协议
        .FUSED16_REDUCTION  (EXACT_OUTPUT_MODE), // 精确输出始终采用完整十六项融合归约
        .EXACT_OUTPUT_MODE  (EXACT_OUTPUT_MODE) // 精确模式跳过Tile内FP32规格化和舍入
    ) u_compute_core ( // 例化保持独立验证和STA边界的16乘16 FP8计算核心
        .clk_i                    (clk_i), // 连接Tile统一时钟
        .rst_i                    (rst_i), // 连接同步高有效复位
        .clear_i                  (clear_i), // 连接同步流水线清空
        .weight_load_valid_i      (core_weight_valid), // 按所选协议向核心声明B权重有效
        .weight_load_ready_o      (core_weight_ready), // 接收计算核心权重通道就绪状态
        .weight_load_column_i     (weight_column_q), // 连接自动循环的权重列号
        .weight_load_data_i       (input_b_head_data), // 连接B权重FIFO队首数据
        .weight_load_format_i     (core_weight_format), // 连接与B队首对齐的FP8格式
        .weights_loaded_o         (weights_loaded_o), // 输出全部十六列至少装载一次的状态
        .act_valid_i              (core_act_valid), // 按所选协议向核心声明A激活有效
        .act_ready_o              (core_act_ready), // 接收计算核心激活通道就绪状态
        .act_data_i               (input_a_head_data), // 连接A激活FIFO队首数据
        .act_format_i             (core_act_format), // 连接与A队首对齐的FP8格式
        .rounding_i               (core_rounding), // 连接与当前输入对对齐的舍入模式
        .column_result_valid_o    (core_result_valid), // 接收计算核心逐列结果有效状态
        .column_result_data_o     (core_result_data), // 接收计算核心逐列FP32结果
        .column_result_invalid_o  (core_result_invalid), // 接收计算核心逐列无效运算标志
        .column_exact_valid_o     (core_exact_valid), // 接收精确Q32结果有效状态
        .column_exact_sum_o       (core_exact_sum), // 接收十六列69位精确块和
        .column_exact_special_o   (core_exact_special), // 接收特殊值旁带
        .column_exact_zero_sign_o (core_exact_zero_sign), // 接收零符号旁带
        .column_exact_invalid_o   (core_exact_invalid), // 接收无效运算旁带
        .column_exact_rounding_o  (core_exact_rounding), // 接收最终舍入模式旁带
        .act_right_valid_o        (act_right_valid_o), // 输出计算核心右边界激活有效状态
        .act_right_data_o         (act_right_data_o), // 输出计算核心右边界激活数据
        .act_right_format_o       (act_right_format_o) // 输出计算核心右边界激活格式
    ); // 结束FP8计算核心例化

    always_comb begin // 用最浅列FIFO的占用量表示已经完整到齐的精确结果行数
        exact_result_level_o = exact_lane_level[0 +: 6]; // 以第零列占用量初始化最小值
        for (integer exact_level_column = 1; exact_level_column < TILE_SIZE;
             exact_level_column = exact_level_column + 1) begin
            if (exact_lane_level[exact_level_column*6 +: 6] <
                exact_result_level_o) begin
                exact_result_level_o =
                    exact_lane_level[exact_level_column*6 +: 6];
            end
        end
    end

    generate // 每列使用独立双端口SRAM FIFO吸收A向右传播造成的固定列间错峰
        for (genvar exact_column = 0; exact_column < TILE_SIZE;
             exact_column = exact_column + 1) begin : gen_exact_result_fifos
            logic [127:0] exact_write_data;
            logic exact_fifo_full;
            logic exact_fifo_empty;

            assign exact_write_data = {
                52'd0,
                core_exact_rounding[exact_column*2 +: 2],
                core_exact_invalid[exact_column],
                core_exact_zero_sign[exact_column*2 +: 2],
                core_exact_special[exact_column*2 +: 2],
                core_exact_sum[exact_column*69 +: 69]
            }; // 单项保存69位Q32及七位最终IEEE处理旁带
            assign exact_result_sum_o[exact_column*69 +: 69] =
                exact_lane_read_data[exact_column*128 +: 69];
            assign exact_result_special_o[exact_column*2 +: 2] =
                exact_lane_read_data[exact_column*128 + 69 +: 2];
            assign exact_result_zero_sign_o[exact_column*2 +: 2] =
                exact_lane_read_data[exact_column*128 + 71 +: 2];
            assign exact_result_invalid_o[exact_column] =
                exact_lane_read_data[exact_column*128 + 73];
            assign exact_result_rounding_o[exact_column*2 +: 2] =
                exact_lane_read_data[exact_column*128 + 74 +: 2];

            FIFO_SYNC_32_128 u_exact_result_fifo (
                .clk_i      (clk_i),
                .rst_i      (rst_i),
                .clear_i    (clear_i),
                .wr_valid_i (core_exact_valid[exact_column]),
                .wr_ready_o (exact_lane_write_ready[exact_column]),
                .wr_data_i  (exact_write_data),
                .rd_ready_i (exact_row_pop),
                .rd_valid_o (exact_lane_read_valid[exact_column]),
                .rd_data_o  (exact_lane_read_data[exact_column*128 +: 128]),
                .full_o     (exact_fifo_full),
                .empty_o    (exact_fifo_empty),
                .level_o    (exact_lane_level[exact_column*6 +: 6])
            );

            wire _unused_exact_fifo_status = &{
                1'b0, exact_fifo_full, exact_fifo_empty,
                exact_lane_read_data[exact_column*128 + 76 +: 52]
            }; // 明确消费为匹配128位SRAM宏而补齐的未使用高位
        end
    endgenerate

    genvar result_column; // 声明十六个输出FIFO的静态列生成索引
    generate // 为每个计算结果列生成一组独立32位同步FIFO
        for (result_column = 0; result_column < TILE_SIZE; result_column = result_column + 1) begin : gen_result_fifos // 展开十六个列结果FIFO
            FIFO_SYNC_32_32 u_result_fifo ( // 例化当前列使用的32深度FP32结果FIFO
                .clk_i      (clk_i), // 连接Tile统一时钟
                .rst_i      (rst_i), // 连接同步高有效复位
                .clear_i    (clear_i), // 连接同步清空控制
                .wr_valid_i (core_result_valid[result_column]), // 当前列结果有效时发起独立写入
                .wr_ready_o (result_lane_write_ready[result_column]), // 接收当前列FIFO写入许可
                .wr_data_i  (core_result_data[result_column*32 +: 32]), // 写入当前列FP32结果
                .rd_ready_i (result_row_pop), // 完整行握手时统一消费当前列队首
                /* verilator lint_off PINCONNECTEMPTY */
                .rd_valid_o (), // 完整行计数已经按照最后一列写入和同步预取延迟维护可见有效状态
                /* verilator lint_on PINCONNECTEMPTY */
                .rd_data_o  (result_lane_read_data[result_column*32 +: 32]), // 输出当前列FP32队首数据
                .full_o     (result_lane_full_o[result_column]), // 输出当前列FIFO满状态
                .empty_o    (result_lane_empty_o[result_column]), // 输出当前列FIFO空状态
                .level_o    (result_lane_level_o[result_column*6 +: 6]) // 输出当前列FIFO占用数量
            ); // 结束当前列结果FIFO例化

            assign result_invalid_o[result_column] = result_valid_o ? output_invalid_mem[result_column][output_meta_rd_ptr_q[result_column]] : 1'b0; // 输出与当前列队首对齐的异常标志
        end // 结束单个列结果FIFO生成块
    endgenerate // 结束十六列结果FIFO生成结构

endmodule // 结束TILE_FP8_16_FIFO缓冲Tile顶层

`default_nettype wire // 恢复默认网络类型避免影响后续编译单元
