module coll_elastic_slice #( // 定义单级弹性流水模块
    parameter WIDTH = 32 // 配置数据位宽
) ( // 开始端口声明
    input  wire                 clk_i, // 接收工作时钟
    input  wire                 rst_n_i, // 接收低有效异步复位
    input  wire [WIDTH-1:0]     data_i, // 接收上游数据
    input  wire                 valid_i, // 接收上游有效指示
    output wire                 ready_o, // 返回上游接收能力
    output wire [WIDTH-1:0]     data_o, // 输出已寄存数据
    output wire                 valid_o, // 输出已寄存有效指示
    input  wire                 ready_i // 接收下游接收能力
); // 结束端口声明
    localparam BYTE_LANES = WIDTH / 8; // 按字节复制窄控制树以限制高扇出
    wire [BYTE_LANES-1:0] lane_ready; // 汇集各字节 lane 的写就绪状态
    wire [BYTE_LANES-1:0] lane_valid; // 汇集各字节 lane 的读有效状态
    assign ready_o = lane_ready[0]; // 使用 lane 零返回一致的上游就绪状态
    assign valid_o = lane_valid[0]; // 使用 lane 零返回一致的下游有效状态
    genvar lane_index; // 提供静态字节 lane 生成索引
    generate // 为每八位数据复制小扇出弹性控制状态
        for (lane_index = 0; lane_index < BYTE_LANES; lane_index = lane_index + 1) begin : g_lane // 生成一个字节弹性 lane
            reg [7:0] bank0_q; // 保存本 lane 的存储体零数据
            reg [7:0] bank1_q; // 保存本 lane 的存储体一数据
            (* keep *) reg write_ptr_q; // 保存本 lane 独立写指针以限制扇出
            (* keep *) reg read_ptr_q; // 保存本 lane 独立读指针以限制扇出
            (* keep *) reg [1:0] count_q; // 保存本 lane 独立占用状态以限制扇出
            wire push_fire; // 指示本 lane 接受上游字节
            wire pop_fire; // 指示本 lane 向下游交付字节
            assign lane_ready[lane_index] = (count_q != 2'd2); // 根据本 lane 寄存占用产生就绪
            assign lane_valid[lane_index] = (count_q != 2'd0); // 根据本 lane 寄存占用产生有效
            assign data_o[lane_index*8 +: 8] = read_ptr_q ? bank1_q : bank0_q; // 选择本 lane 当前队首字节
            assign push_fire = valid_i && lane_ready[lane_index]; // 形成本 lane 写入握手
            assign pop_fire = lane_valid[lane_index] && ready_i; // 形成本 lane 读取握手
            always @(posedge clk_i or negedge rst_n_i) begin // 更新本字节 lane 弹性状态
                if (!rst_n_i) begin // 检测复位有效
                    bank0_q <= 8'd0; // 清零本 lane 存储体零
                    bank1_q <= 8'd0; // 清零本 lane 存储体一
                    write_ptr_q <= 1'b0; // 清零本 lane 写指针
                    read_ptr_q <= 1'b0; // 清零本 lane 读指针
                    count_q <= 2'd0; // 清零本 lane 占用数量
                end else begin // 处理本 lane 正常操作
                    if (push_fire) begin // 检测本 lane 合法写入
                        if (write_ptr_q) begin // 选择本 lane 存储体一
                            bank1_q <= data_i[lane_index*8 +: 8]; // 写入本 lane 存储体一
                        end else begin // 选择本 lane 存储体零
                            bank0_q <= data_i[lane_index*8 +: 8]; // 写入本 lane 存储体零
                        end // 结束本 lane 写存储体选择
                        write_ptr_q <= !write_ptr_q; // 推进本 lane 环形写指针
                    end // 结束本 lane 写入处理
                    if (pop_fire) begin // 检测本 lane 合法读取
                        read_ptr_q <= !read_ptr_q; // 推进本 lane 环形读指针
                    end // 结束本 lane 读取处理
                    case ({push_fire, pop_fire}) // 按本 lane 握手组合更新占用
                        2'b10: count_q <= count_q + 1'b1; // 仅写入时增加本 lane 占用
                        2'b01: count_q <= count_q - 1'b1; // 仅读取时减少本 lane 占用
                        2'b11: count_q <= count_q; // 同拍写读时保持本 lane 占用
                        default: count_q <= count_q; // 空闲时保持本 lane 占用
                    endcase // 结束本 lane 占用选择
                end // 结束本 lane 复位选择
            end // 结束本 lane 时序逻辑
        end // 结束字节 lane 生成
    endgenerate // 结束字节切片弹性结构
endmodule // 结束弹性流水模块
