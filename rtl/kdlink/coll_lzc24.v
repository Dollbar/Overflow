module coll_lzc24 ( // 定义分层二十四位前导零计数器
    input  wire [23:0] value_i, // 接收待归一化尾数
    output reg [4:0] count_o, // 输出零至二十四前导零数量
    output reg [7:0] selected_byte_o, // 输出选中的八位非零分组
    output reg [4:0] base_count_o // 输出分组前导零基数
); // 结束端口声明
    reg [7:0] selected_byte_d; // 保存最高非零八位分组
    reg [4:0] base_count_d; // 保存最高非零分组前导零基数
    reg [3:0] byte_count_d; // 保存八位分组内部前导零数
    always @(*) begin // 组合选择最高非零八位分组
        selected_byte_d = 8'd0; // 默认选择全零分组
        base_count_d = 5'd24; // 默认完整输入全零
        if (|value_i[23:16]) begin // 检查最高八位分组
            selected_byte_d = value_i[23:16]; // 选择最高八位分组
            base_count_d = 5'd0; // 最高分组前无前导零
        end else if (|value_i[15:8]) begin // 检查中间八位分组
            selected_byte_d = value_i[15:8]; // 选择中间八位分组
            base_count_d = 5'd8; // 跳过最高八个零
        end else if (|value_i[7:0]) begin // 检查最低八位分组
            selected_byte_d = value_i[7:0]; // 选择最低八位分组
            base_count_d = 5'd16; // 跳过最高十六个零
        end // 结束最高非零分组选择
        selected_byte_o = selected_byte_d; // 输出选中的八位分组供后级流水寄存
        base_count_o = base_count_d; // 输出分组基数供后级流水寄存
    end // 结束八位分组选择逻辑
    always @(*) begin // 组合并行编码八位分组内部前导零数
        byte_count_d = 4'd0; // 默认全零分组编码
        byte_count_d[2] = ~(|selected_byte_d[7:4]); // 前导零达到四位时置最高计数位
        byte_count_d[1] = ((~(|selected_byte_d[7:6])) && (selected_byte_d[5] || selected_byte_d[4])) || ((~(|selected_byte_d[7:2])) && (selected_byte_d[1] || selected_byte_d[0])); // 并行形成计数中间位
        byte_count_d[0] = ((!selected_byte_d[7]) && selected_byte_d[6]) || ((~(|selected_byte_d[7:5])) && selected_byte_d[4]) || ((~(|selected_byte_d[7:3])) && selected_byte_d[2]) || ((~(|selected_byte_d[7:1])) && selected_byte_d[0]); // 并行形成计数最低位
    end // 结束八位分组内部编码
    always @(*) begin // 组合形成最终前导零数量
        if (base_count_d == 5'd24) count_o = 5'd24; // 全零输入返回二十四
        else count_o = base_count_d + {1'b0, byte_count_d}; // 合并分组基数和内部计数
    end // 结束最终前导零计数形成
endmodule // 结束分层二十四位前导零计数器
