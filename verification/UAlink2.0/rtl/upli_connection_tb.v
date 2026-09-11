// Paired UPLI connection control; Common 2.0 sections 4.1-4.3.
// UALink 工程连接控制自检；参考模型、有限枚举和随机向量见同目录生成器。
// 日期 2026-09-07；本文件是仿真 TB，不是可综合协议逻辑或整核认证。
`timescale 1ps/1ps // 仿真精度支持默认 640 ps 和参考 6400 ps 的 UPLI 周期。
module upli_connection_tb; // UPLI 双端连接自检测试模块，逐拍比较 Python 参考结果。
    parameter C_WAIT = 1'b0; // 选择 Completer 独立建连或等待 Originator 已完成。
    parameter integer C_HALF_PERIOD_PS = 320; // 仿真半周期，默认对应 1562.5 MHz。
    localparam integer C_ROWS = 34816; // 4096 段八拍历史，加 2048 拍随机 reset/readiness。
    reg i_clk; // 两端共用的 UPLI 时钟，由测试过程驱动。
    reg i_rstn; // 两端共用同步低有效复位，在采样沿前稳定。
    reg orig_ready; // Originator 保证能够接收接口信息的输入条件。
    reg comp_ready; // Completer 保证能够接收接口信息的输入条件。
    wire orig_req, comp_ack, comp_req, orig_ack; // 两端实际输出的四个协议握手信号。
    wire orig_tx, orig_rx, comp_tx, comp_rx; // 两端发送/接收方向的完成标志。
    wire orig_beats, comp_beats; // 两端的双向已连接标志，不包含信用资格。
    wire [9:0] observed; // 实际输出按独立向量契约组织，保留两端对称性检查。
    reg [12:0] vectors [0:C_ROWS-1]; // 生成向量包含三位激励及十位期望值。
    reg [9:0] before_edge; // 输入变化之前的观测快照，用于检查无异步状态更新。
    reg [4095:0] vector_path; // 加号参数给定生成向量路径，不绑定主机目录。
    integer row; // 有限向量枚举索引，检查失败时报告精确位置。
    assign observed = {orig_req, comp_ack, comp_req, orig_ack, orig_tx, comp_tx, orig_rx, comp_rx, orig_beats, comp_beats}; // 十项输出均纳入比较。

    // Originator 的 WAIT 参数也设置为当前配置，验证它不会因此等待对端建连。
    upli_connection_side #( // 实例化 Originator 一侧，不替外部 Completer 驱动信号。
        .C_IS_COMPLETER(1'b0), // Originator 必须允许主动发起请求。
        .C_COMPLETER_WAITS(C_WAIT) // 此参数在 Originator 角色中应无作用。
    ) Orig_Inst ( // 将本侧请求与对侧应答、反方向请求交叉连接。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_ready(orig_ready), // 同步时钟、复位和能力输入。
        .i_peer_req(comp_req), .i_peer_ack(comp_ack), // 来自 Completer 的请求和接受。
        .o_req(orig_req), .o_ack(orig_ack), // Originator 驱动的请求和反方向接受。
        .o_tx_connected(orig_tx), .o_rx_connected(orig_rx), .o_beats_connected(orig_beats) // 本侧连接资格。
    ); // 结束 Originator 实例的命名连接。

    // Completer 使用完全相同的单侧实现，以角色参数选择合法等待策略。
    upli_connection_side #( // 实例化 Completer 一侧，保留独立请求与接受寄存器。
        .C_IS_COMPLETER(1'b1), // Completer 角色允许等待 Originator 已连接。
        .C_COMPLETER_WAITS(C_WAIT) // 当前回归明确选择独立或等待策略。
    ) Comp_Inst ( // 与 Originator 实例共用时钟/复位，不存在 CDC。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_ready(comp_ready), // 同步时钟、复位和能力输入。
        .i_peer_req(orig_req), .i_peer_ack(orig_ack), // 来自 Originator 的请求和接受。
        .o_req(comp_req), .o_ack(comp_ack), // Completer 驱动的请求和反方向接受。
        .o_tx_connected(comp_tx), .o_rx_connected(comp_rx), .o_beats_connected(comp_beats) // 本侧连接资格。
    ); // 结束 Completer 实例的命名连接。

    initial begin // 初始化后以固定时序施加每行向量，失败立即非零退出。
        i_clk = 1'b0; i_rstn = 1'b0; orig_ready = 1'b0; comp_ready = 1'b0; // 首个采样沿明确处于复位。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin // 向量路径必须由可复现的运行入口提供。
            $display("FAIL missing VECTORS argument"); $stop; // Verilog-2001 停止调用在本 Verilator 入口中必须非零退出。
        end // 结束必需参数检查。
        $readmemh(vector_path, vectors); // 只载入生成的有限向量，不访问私有规范或工艺库。
        for (row = 0; row < C_ROWS; row = row + 1) begin // 每轮覆盖一个完整上升沿及沿前稳定性检查。
            before_edge = observed; // 记录沿前输出，忽略第一次尚未复位的初值。
            {i_rstn, orig_ready, comp_ready} = vectors[row][12:10]; // 激励在低电平半周期开始时改变。
            #(C_HALF_PERIOD_PS-1); // 将组合传播与真实采样沿分开观察。
            if ((row > 0) && (observed !== before_edge)) begin // 同步 reset/readiness 不得在边沿之间改写状态。
                $display("FAIL asynchronous state change row=%0d", row); $stop; // 报告意外组合或异步复位路径并停止。
            end // 结束沿前稳定性检查。
            #1 i_clk = 1'b1; // 到达 UPLI 上升沿，两端同时采样对侧旧寄存器状态。
            #1; // 等待非阻塞赋值完成，避免 TB 与 DUT 的采样竞态。
            if (observed !== vectors[row][9:0]) begin // 严格检查四信号、两方向及两端派生状态。
                $display("FAIL row=%0d actual=%h expected=%h", row, observed, vectors[row][9:0]); $stop; // 精确定位首个功能差异并停止。
            end // 结束沿后参考模型比较。
            #(C_HALF_PERIOD_PS-1) i_clk = 1'b0; // 完成当前周期，准备下一个低电平阶段。
        end // 结束全部枚举与随机向量检查。
        $display("PASS rows=%0d wait=%0d period_ps=%0d", C_ROWS, C_WAIT, C_HALF_PERIOD_PS*2); // 仅在所有比较通过后输出成功。
        $finish; // 正常结束本配置仿真。
    end // 结束自检主过程。

    initial begin // 独立看门狗防止测试入口或时序修改造成无界等待。
        #(C_ROWS*C_HALF_PERIOD_PS*2+C_HALF_PERIOD_PS*4); // 超过有限向量总时间才触发超时。
        $display("FAIL watchdog timeout"); $stop; // 超时必须作为失败而不是完成退出。
    end // 结束独立超时监视过程。
endmodule // 结束 upli_connection_tb 双端连接自检模块。
