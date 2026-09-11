// Initial-credit publisher: independent model comparison, not full UPLI VIP.
// 日期 2026-09-08；检查注册总线与同步复位，不将该测试等同协议认证。
`timescale 1ps/1ps // 同时精确表示正常和参考接口时钟周期。
module upli_credit_initialization_tb; // 初始信用发布模块的逐拍自检测试台。
    parameter integer C_NUM_PORTS = 1; // 本次仿真的实际端口数量。
    parameter integer C_CREDIT_WIDTH = 4; // 容量计数宽度与被测实例一致。
    parameter integer C_HALF_PERIOD_PS = 320; // 选择正常或参考频率的半周期。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = 20'hf4310; // 由入口覆盖的逐账户容量配置。
    reg i_clk; // 测试台唯一驱动的同步时钟。
    reg [1:0] stimulus; // 两位分别表示沿前复位和连接资格。
    reg [27:0] expected; // 模型的 valid、pool、VC、Num、done 打包期望。
    wire [27:0] observed; // 被测模块全部协议输出，包含无效期确定值。
    reg [27:0] before_edge; // 前一已验证状态，用于禁止沿间改变。
    reg [4095:0] vector_path; // 显式运行参数给出的只读向量路径。
    integer fd, fields, row; // 向量文件句柄、解析数量和已验证行数。
    upli_credit_initializer #( // 参数绑定与独立模型向量一致。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), // 选择实际端口及容量表示范围。
        .C_CAPACITIES(C_CAPACITIES), .C_DEFAULT_CAPACITY({C_CREDIT_WIDTH{1'b1}}) // 所有真实容量由打包参数提供。
    ) Initializer_Inst ( // 被测发布器不包含发送银行或物理存储。
        .i_clk(i_clk), .i_rstn(stimulus[1]), .i_credit_connected(stimulus[0]), // 沿前稳定的复位与返回方向资格。
        .o_credit_valid(observed[27:24]), .o_credit_pool(observed[23:20]), // 四端口批次有效和池选择。
        .o_credit_vc(observed[19:12]), .o_credit_num(observed[11:4]), // 每端口两个双位编码。
        .o_credit_init_done(observed[3:0]) // 独立完成后保持的四端口初始化电平。
    ); // 结束初始信用发布器实例。
    initial begin // 只使用独立模型的文件数据驱动并逐拍比较。
        i_clk = 1'b0; stimulus = 2'b00; row = 0; // 先施加同步复位初值。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin // 不允许缺少向量文件的空运行。
            $display("FAIL missing VECTORS"); $stop; // 输入缺失以失败退出。
        end // 结束路径参数检查。
        fd = $fopen(vector_path, "r"); // 只读取入口生成的两列向量。
        if (fd == 0) begin // 不将无法打开文件误判为测试完成。
            $display("FAIL vector open"); $stop; // 报告外部测试输入不可读。
        end // 结束文件句柄检查。
        before_edge = observed; // 复位前不要求未初始化寄存器的具体值。
        fields = $fscanf(fd, "%h %h", stimulus, expected); // 读取第一行明确的输入和沿后期望。
        while (fields == 2) begin // 只处理完整向量行，不忽略畸形尾部。
            #(C_HALF_PERIOD_PS-1); // 等待输入稳定但尚未到采样沿。
            if ((row > 0) && (observed !== before_edge)) begin // 所有输出必须由寄存器驱动。
                $display("FAIL asynchronous output row=%0d", row); $stop; // 捕获组合输出或异步复位变化。
            end // 结束沿前稳定性检查。
            #1 i_clk = 1'b1; // 在唯一时钟上升沿采样本行输入。
            #1; // 等待寄存器非阻塞赋值完成。
            if (observed !== expected) begin // 比较全部二十八位输出，不仅比较最终信用总量。
                $display("FAIL row=%0d actual=%h expected=%h", row, observed, expected); $stop; // 报告第一处独立模型差异。
            end // 结束沿后逐位检查。
            #(C_HALF_PERIOD_PS-1) i_clk = 1'b0; // 完成该周期并准备下一行。
            row = row + 1; before_edge = observed; // 保存已通过的输出状态。
            fields = $fscanf(fd, "%h %h", stimulus, expected); // 读取下一行测试向量。
        end // 结束有限向量主循环。
        if ((fields != -1) || !$feof(fd) || (row < 150)) begin // 确认正常文件结束且不是空或明显短的测试。
            $display("FAIL truncated vectors rows=%0d fields=%0d", row, fields); $stop; // 截断或格式错误必须阻止通过。
        end // 结束测试输入完整性检查。
        $fclose(fd); // 关闭只读测试文件。
        $display("PASS initialization rows=%0d ports=%0d width=%0d period_ps=%0d", row, C_NUM_PORTS, C_CREDIT_WIDTH, C_HALF_PERIOD_PS*2); // 仅在所有逐拍比较成功后输出结果。
        $finish; // 正常终止已完成的有限仿真。
    end // 结束初始信用模型比较过程。
    initial begin // 独立看门狗避免时钟或输入异常导致无限运行。
        #(64'd1000000000000); // 时间上限覆盖最大本地容量的初始化序列。
        $display("FAIL initialization timeout"); $stop; // 超时不能作为通过退出。
    end // 结束独立超时检查。
endmodule // 结束 upli_credit_initialization_tb 自检测试台。
