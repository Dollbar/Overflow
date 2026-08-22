module kdlink_switch_crossbar4 ( // 定义四路 640-bit 注册 crossbar leaf
    input wire clk_i, // 接收 switch 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire valid_i, // 接收 crossbar 选择有效位
    input wire [1:0] select_i, // 接收四路选择索引
    input wire [2559:0] flit_i, // 接收四个 640-bit flit
    output reg valid_o, // 输出注册化 crossbar 有效位
    output reg [639:0] flit_o // 输出注册化 crossbar flit
); // 结束端口声明
    reg [639:0] selected_flit_d; // 保存组合选择结果
    always @(*) begin // 选择四路 crossbar 输入
        selected_flit_d = 640'd0; // 默认输出安全零值
        case (select_i) // 译码四路选择索引
            2'd0: selected_flit_d = flit_i[639:0]; // 选择输入零
            2'd1: selected_flit_d = flit_i[1279:640]; // 选择输入一
            2'd2: selected_flit_d = flit_i[1919:1280]; // 选择输入二
            2'd3: selected_flit_d = flit_i[2559:1920]; // 选择输入三
            default: selected_flit_d = 640'd0; // 非法选择时输出零值
        endcase // 结束四路选择
    end // 结束组合选择
    always @(posedge clk_i or negedge rst_n_i) begin // 注册 crossbar 输出
        if (!rst_n_i) begin // 检测复位有效
            valid_o <= 1'b0; // 清除输出有效位
            flit_o <= 640'd0; // 清零输出 flit
        end else begin // 处理正常 crossbar 传输
            valid_o <= valid_i; // 注册选择有效位
            if (valid_i) flit_o <= selected_flit_d; // 仅在有效时注册选择 flit
        end // 结束正常传输
    end // 结束 crossbar 输出注册
endmodule // 结束四路 crossbar leaf
