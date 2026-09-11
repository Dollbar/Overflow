// Four-channel UPLI startup integration; no payload FIFO or transaction core.
// 日期 2026-09-08；真实连接控制、初始发布与发送银行相连，不强制信用状态。
`timescale 1ps/1ps // 精度支持正常及参考频率的同步采样。
module upli_credit_startup_tb; // 四通道信用启动集成测试模块，检查真实连接及本地消费事件。
    parameter integer C_NUM_PORTS = 1; // 每通道实际有效端口数量。
    parameter integer C_CREDIT_WIDTH = 4; // 五账户容量的本地计数宽度。
    parameter integer C_HALF_PERIOD_PS = 320; // 仿真时钟半周期。
    parameter C_WAIT = 1'b0; // Completer 可选等待 Originator 方向先完成。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = 20'hf4310; // 所有通道各自独立拥有同一容量配置。
    localparam integer C_BALANCE_BITS = C_NUM_PORTS*5*C_CREDIT_WIDTH; // 一通道五账户余额的打包位数。
    localparam integer C_CHANNEL_BITS = C_BALANCE_BITS+33; // 发布总线加银行余额、确认及诊断的观测宽度。
    localparam integer C_OBSERVED_BITS = 4*C_CHANNEL_BITS+4; // 四通道状态和四个真实握手信号。
    reg i_clk; // 所有实例共用的唯一 UPLI 时钟。
    reg [11:0] stimulus; // 复位、两侧 readiness 和四通道本地消费事件。
    reg [C_OBSERVED_BITS-1:0] expected; // 独立组合模型提供的沿后状态。
    wire [C_OBSERVED_BITS-1:0] observed; // 真实实例直接输出的全部观测值。
    reg [C_OBSERVED_BITS-1:0] before_edge; // 检查输出在输入改变后仍保持至采样沿。
    wire orig_req, orig_ack, comp_req, comp_ack; // 两个单侧模块分别驱动请求与应答。
    wire orig_tx, comp_tx, beats_connected; // 返回方向和双向 beat 的实际连接资格。
    wire unused_orig_rx, unused_comp_rx, unused_comp_beats; // 对称派生输出不重复纳入向量。
    reg [4095:0] vector_path; // 入口显式指定的测试向量文件路径。
    integer fd, fields, row; // 文件句柄、解析字段数及逐拍比较计数。
    genvar gen_channel; // 四个通道的编译时实例展开索引。
    assign observed[C_OBSERVED_BITS-1 -: 4] = {orig_req, comp_ack, comp_req, orig_ack}; // 真实握手电平单独比较，不能伪造常连接条件。
    upli_connection_side #( // Originator 侧必须能够主动请求连接。
        .C_IS_COMPLETER(1'b0), .C_COMPLETER_WAITS(C_WAIT) // WAIT 不得影响 Originator 的合法启动。
    ) Orig_Inst ( // 与 Completer 的输出交叉相连，采样自然使用沿前电平。
        .i_clk(i_clk), .i_rstn(stimulus[11]), .i_ready(stimulus[10]), // 时钟、同步复位和本侧能力输入。
        .i_peer_req(comp_req), .i_peer_ack(comp_ack), .o_req(orig_req), .o_ack(orig_ack), // 双端原生握手接线。
        .o_tx_connected(orig_tx), .o_rx_connected(unused_orig_rx), .o_beats_connected(beats_connected) // 真实派生连接状态。
    ); // 结束 Originator 连接控制实例。
    upli_connection_side #( // Completer 可独立启动或等待 Originator 方向。
        .C_IS_COMPLETER(1'b1), .C_COMPLETER_WAITS(C_WAIT) // 当前回归选择明确等待策略。
    ) Comp_Inst ( // 反方向同样使用实际对端寄存器输出。
        .i_clk(i_clk), .i_rstn(stimulus[11]), .i_ready(stimulus[9]), // 与 Originator 共享时钟和接口复位。
        .i_peer_req(orig_req), .i_peer_ack(orig_ack), .o_req(comp_req), .o_ack(comp_ack), // Completer 请求和应答实际参与闭环。
        .o_tx_connected(comp_tx), .o_rx_connected(unused_comp_rx), .o_beats_connected(unused_comp_beats) // 两端方向含义保持明确。
    ); // 结束 Completer 连接控制实例。
    generate // 依次实例化 req、orig_data、rd_rsp、wr_rsp 四个独立通道。
        for (gen_channel = 0; gen_channel < 4; gen_channel = gen_channel + 1) begin : gen_channels // 不共享四通道信用存储。
            wire credit_connected; // 按真实返回者而非 beat 发送者选择连接方向。
            wire [27:0] publication; // 此通道的注册初始发布总线。
            wire [C_BALANCE_BITS-1:0] balances; // 此通道独立发送银行的余额。
            wire [3:0] confirmed; // 各端口经连续采样过滤后的完成确认。
            wire error; // 本地非法消费事件诊断，不是线上错误字段。
            assign credit_connected = (gen_channel < 2) ? comp_tx : orig_tx; // 请求和原始数据由 Completer 返信用，响应通道由 Originator 返信用。
            assign observed[gen_channel*C_CHANNEL_BITS +: C_CHANNEL_BITS] = {publication, balances, confirmed, error}; // 比较发布与消费的全部状态而非仅最终总和。
            upli_credit_initializer #( // 初始资源发布器采用本通道的真实参数。
                .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), // 参数与银行及向量一致。
                .C_DEFAULT_CAPACITY({C_CREDIT_WIDTH{1'b1}}), .C_CAPACITIES(C_CAPACITIES) // 容量未对应物理数据存储，本测试只验证信用启动。
            ) Initializer_Inst ( // 无 ready 的注册输出直接连接接收信用银行。
                .i_clk(i_clk), .i_rstn(stimulus[11]), .i_credit_connected(credit_connected), // 连接前必须静默且复位清除部分发布。
                .o_credit_valid(publication[27:24]), .o_credit_pool(publication[23:20]), // 四端口可以同时独立发布。
                .o_credit_vc(publication[19:12]), .o_credit_num(publication[11:4]), .o_credit_init_done(publication[3:0]) // 批次编码和粘滞完成信号。
            ); // 结束本通道初始信用发布实例。
            upli_credit_bank #( // 接收原生信用并检查沿前消费资格。
                .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), // 与发布器保持端口和计数宽度匹配。
                .C_DEFAULT_CAPACITY({C_CREDIT_WIDTH{1'b1}}), .C_CAPACITIES(C_CAPACITIES), .C_INIT_CYCLES(2) // 本集成 profile 使用两拍过滤。
            ) Bank_Inst ( // 数据消费是测试注入事件，不伪装成完整 UPLI beat 事务。
                .i_clk(i_clk), .i_rstn(stimulus[11]), .i_credit_connected(credit_connected), .i_beats_connected(beats_connected), // 实际两方向连接限制由握手模块提供。
                .i_credit_valid(publication[27:24]), .i_credit_pool(publication[23:20]), // 只能在沿上采样发布器之前周期的输出。
                .i_credit_vc(publication[19:12]), .i_credit_num(publication[11:4]), .i_credit_init_done(publication[3:0]), // 不通过测试台直接改余额或 init 状态。
                .i_send_valid(stimulus[gen_channel+5]), .i_send_port(stimulus[4:3]), .i_send_vc(stimulus[2:1]), .i_send_pool(stimulus[0]), // 四通道独立有效位及测试账户选择。
                .o_balances(balances), .o_init_confirmed(confirmed), .o_error(error) // 所有状态与独立模型比较。
            ); // 结束本通道发送信用银行实例。
        end // 结束四通道真实模块展开。
    endgenerate // 结束信用启动集成结构。
    initial begin // 使用独立模型轨迹比较实际模块连接。
        i_clk = 1'b0; stimulus = 12'b0; row = 0; // 首沿之前施加同步复位输入。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin // 必须明确指定完整向量输入。
            $display("FAIL missing VECTORS"); $stop; // 没有向量时不能空跑通过。
        end // 结束路径参数检查。
        fd = $fopen(vector_path, "r"); // 只读模式打开生成轨迹。
        if (fd == 0) begin // 检查文件可读性，避免错误跳过所有测试。
            $display("FAIL vector open"); $stop; // 输入路径问题以非零终止。
        end // 结束文件句柄检查。
        before_edge = observed; // 第一次复位前不检查未定义的上电状态。
        fields = $fscanf(fd, "%h %h", stimulus, expected); // 读取输入和全状态期望。
        while (fields == 2) begin // 依次处理完整向量行。
            #(C_HALF_PERIOD_PS-1); // 沿前留出组合稳定时间。
            if ((row > 0) && (observed !== before_edge)) begin // 注册握手与信用状态不能随低沿输入立即变化。
                $display("FAIL asynchronous startup row=%0d", row); $stop; // 捕获错误的同拍或异步旁路。
            end // 结束沿前同步性检查。
            #1 i_clk = 1'b1; // 两端和四通道所有寄存器同时采样旧值。
            #1; // 等待非阻塞更新完成后比较。
            if (observed !== expected) begin // 检查完整连接及信用管线状态。
                $display("FAIL startup row=%0d actual=%h expected=%h", row, observed, expected); $stop; // 输出第一处模块集成差异。
            end // 结束独立模型沿后比较。
            #(C_HALF_PERIOD_PS-1) i_clk = 1'b0; // 完成当前周期。
            row = row + 1; before_edge = observed; // 保存已检查状态后读取下一行。
            fields = $fscanf(fd, "%h %h", stimulus, expected); // 读取后续输入和期望。
        end // 结束有限轨迹比较循环。
        if ((fields != -1) || !$feof(fd) || (row < 300)) begin // 拒绝畸形、空或明显截断的轨迹。
            $display("FAIL startup vectors rows=%0d fields=%0d", row, fields); $stop; // 输入完整性错误不能通过。
        end // 结束轨迹数量与格式检查。
        $fclose(fd); // 关闭已消费的只读文件。
        $display("PASS startup rows=%0d ports=%0d width=%0d wait=%0d period_ps=%0d", row, C_NUM_PORTS, C_CREDIT_WIDTH, C_WAIT, C_HALF_PERIOD_PS*2); // 所有连接和通道逐拍一致后报告。
        $finish; // 正常终止本配置仿真。
    end // 结束四通道启动自检主过程。
    initial begin // 独立看门狗保护有限测试的终止性。
        #(64'd1000000000000); // 宽裕上限覆盖声明的模型轨迹长度。
        $display("FAIL startup timeout"); $stop; // 超时失败防止挂起被当作通过。
    end // 结束启动测试看门狗。
endmodule // 结束 upli_credit_startup_tb 四通道启动集成自检模块。
