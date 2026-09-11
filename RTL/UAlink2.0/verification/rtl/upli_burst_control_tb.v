// Native burst control against pre-existing independent sender and passive monitor.
// 日期2026-09-08；只检验控制，未把输入银行快照当作实际银行/存储集成。
`timescale 1ps/1ps // 支持正常与参考UPLI时钟周期的逐沿检查。
module upli_burst_control_tb; // 正常请求/OrigData准入、TDM和完整预约自检模块。
    parameter integer C_NUM_PORTS = 1; // 真实控制RTL的展开端口数量。
    parameter integer C_CREDIT_WIDTH = 4; // 模型银行快照的账户计数位宽。
    parameter integer C_HALF_PERIOD_PS = 320; // 两种已声明UPLI周期的半周期。
    localparam integer C_BANK_BITS = C_NUM_PORTS*5*C_CREDIT_WIDTH; // 单通道全部端口五账户余额宽度。
    localparam integer C_BASE = C_BANK_BITS*2; // 高位控制字段位于两组银行输入之上。
    reg i_clk; // 唯一共同UPLI时钟。
    reg [C_BASE+22:0] stimulus; // 复位、连接、候选描述符、初始化与两组沿前余额。
    reg [21:0] expected; // 独立模型本沿发出事件与沿前控制状态。
    reg [6:0] expected_after; // 独立模型沿后busy及TDM状态。
    wire accepted, req_valid, req_pool, data_valid, data_pool, data_last, known; // 原生发出和本地候选握手。
    wire [1:0] req_port, req_vc, data_port, data_vc, data_offset, phase; // 原始元数据与TDM相位。
    wire [3:0] busy; // 逐port尚未发完的真实数据描述符所有权。
    wire [21:0] observed; // 实际完整事件及状态总线。
    wire [6:0] state_observed; // 单独检查沿后寄存器状态。
    reg [6:0] previous_state; // 确保输入变化不异步修改busy或phase。
    reg [4095:0] vector_path; // 从运行入口显式传入的向量路径。
    integer fd, fields, row, requests, beats, overlays; // 实际文件解析和活动计数。
    assign state_observed = {busy, known, phase}; // 状态不通过TB重构RTL内部算法。
    assign observed = {req_valid, req_port, req_vc, req_pool, data_valid, data_port, data_vc, data_pool, data_offset, data_last, state_observed}; // 比较所有有效和无效输出字段。
    upli_burst_control #( // 实际可综合控制器而非TB替代调度器。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH) // 形状与原生快照一致。
    ) Control_Inst ( // 输入仅为真实候选与沿前已持有信用观察。
        .i_clk(i_clk), .i_rstn(stimulus[C_BASE+22]), .i_beats_connected(stimulus[C_BASE+21]), // 同步复位和双向连接资格。
        .i_candidate_valid(stimulus[C_BASE+20]), .i_candidate_port(stimulus[C_BASE+18 +: 2]), .i_candidate_vc(stimulus[C_BASE+16 +: 2]), // 原候选端口及VC。
        .i_candidate_pool(stimulus[C_BASE+15]), .i_candidate_has_data(stimulus[C_BASE+14]), .i_candidate_num_beats(stimulus[C_BASE+12 +: 2]), .i_candidate_data_pools(stimulus[C_BASE+8 +: 4]), // 整笔原生数据数量和本地pool计划。
        .i_req_init(stimulus[C_BASE+4 +: 4]), .i_data_init(stimulus[C_BASE +: 4]), // 已由银行确认而非当前初始done输入。
        .i_req_balances(stimulus[C_BANK_BITS +: C_BANK_BITS]), .i_data_balances(stimulus[0 +: C_BANK_BITS]), // 沿前注册余额，不含本沿返还旁路。
        .o_candidate_accepted(accepted), .o_req_valid(req_valid), .o_req_port(req_port), .o_req_vc(req_vc), .o_req_pool(req_pool), // 本地握手与实际请求发出。
        .o_data_valid(data_valid), .o_data_port(data_port), .o_data_vc(data_vc), .o_data_pool(data_pool), .o_data_offset(data_offset), .o_data_last(data_last), // 真实OrigData完整控制字段。
        .o_busy(busy), .o_tdm_known(known), .o_tdm_port(phase) // 控制状态独立比对。
    ); // 结束实际突发控制模块实例。
    initial begin // 完整逐沿自检并保留原模型生成期望。
        i_clk = 1'b0; stimulus = {(C_BASE+23){1'b0}}; row = 0; requests = 0; beats = 0; overlays = 0; // 初始输入为同步复位。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin // 空向量路径不得空跑通过。
            $display("FAIL burst missing VECTORS"); $stop; // 明确输入缺失错误。
        end // 结束运行参数检查。
        fd = $fopen(vector_path, "r"); // 只读加载独立参考向量。
        if (fd == 0) begin // 文件不可读即失败。
            $display("FAIL burst vector open"); $stop; // 不跳过测试内容。
        end // 结束文件可读性检查。
        previous_state = state_observed; // 首次复位前不约束上电寄存器。
        fields = $fscanf(fd, "%h %h %h", stimulus, expected, expected_after); // 每行包含完整本沿和沿后期望。
        while (fields == 3) begin // 消费有限的完整输入轨迹。
            #(C_HALF_PERIOD_PS-1); // 等待组合准入和发送字段稳定。
            if ((row > 0) && (state_observed !== previous_state)) begin // 改变描述符或连接不能异步改状态。
                $display("FAIL burst asynchronous state row=%0d", row); $stop; // 捕获异步复位/错误组合状态路径。
            end // 结束寄存状态稳定性检查。
            if ((row > 0) && ((observed !== expected) || (accepted !== req_valid))) begin // 首次复位后每沿比较完整事件和状态。
                $display("FAIL burst pre row=%0d actual=%h expected=%h", row, observed, expected); $stop; // 第一处差异即终止。
            end // 结束沿前完整发出语义比较。
            if (req_valid) requests = requests+1; // 计数实际请求，而非候选次数。
            if (data_valid) beats = beats+1; // 计数实际数据发出。
            if (req_valid && !stimulus[C_BASE+14] && data_valid) overlays = overlays+1; // 观察真实read与旧数据同拍。
            #1 i_clk = 1'b1; // 全部控制状态在共同上升沿推进。
            #1; // 等待非阻塞更新后检查新所有权。
            if (state_observed !== expected_after) begin // 原生事件后的busy和TDM必须与模型一致。
                $display("FAIL burst post row=%0d actual=%h expected=%h", row, state_observed, expected_after); $stop; // 捕获漏推进、重复保留和错误清理。
            end // 结束沿后寄存器状态检查。
            #(C_HALF_PERIOD_PS-1) i_clk = 1'b0; // 完成当前时钟周期。
            row = row+1; previous_state = state_observed; // 保存已通过状态并进入下一行。
            fields = $fscanf(fd, "%h %h %h", stimulus, expected, expected_after); // 不重用DUT输出生成期望。
        end // 结束逐沿模型比较。
        if ((fields != -1) || !$feof(fd) || (row < 1000) || (requests < 200) || (beats < 200) || (overlays == 0)) begin // 拒绝截断、空跑和缺关键活动的轨迹。
            $display("FAIL burst incomplete rows=%0d requests=%0d beats=%0d overlays=%0d fields=%0d", row, requests, beats, overlays, fields); $stop; // 不能只靠未触发断言宣称通过。
        end // 结束轨迹完整性与实际活动检查。
        $fclose(fd); // 关闭已检查的有限向量文件。
        $display("PASS burst_control rows=%0d ports=%0d credit_width=%0d period_ps=%0d requests=%0d data=%0d read_overlays=%0d", row, C_NUM_PORTS, C_CREDIT_WIDTH, C_HALF_PERIOD_PS*2, requests, beats, overlays); // 仅报告实际控制仿真范围。
        $finish; // 全部逐沿比较通过后正常结束。
    end // 结束正常突发控制自检过程。
    initial begin // 独立看门狗避免异常轨迹悬挂。
        #(64'd1000000000000); // 足够覆盖最长声明矩阵而不影响正常周期。
        $display("FAIL burst timeout"); $stop; // 超时必须失败。
    end // 结束控制测试看门狗。
endmodule // 结束upli_burst_control_tb原生正常突发控制自检模块。
