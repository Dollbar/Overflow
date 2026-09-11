// Normal-return queue conservation properties over the actual DUT ports.
// 日期 2026-09-08；不预设队列计数合法，不切断真实元数据或状态驱动。
`timescale 1ps/1ps // 形式步骤与其它 UPLI 同步模块保持一致的声明精度。
module upli_credit_return_properties #( // 正常返回计数守恒及旧队列归还资格检查模块。
    parameter integer C_NUM_PORTS = 1, // 当前证明配置的启用端口数。
    parameter integer C_DEPTH = 4 // 当前证明配置的实际队列深度。
) ( // 所有环境输入保持为独立二值符号量。
    input wire i_clk, // 每个形式步骤对应一个 UPLI 采样沿。
    input wire i_rstn, // 同步复位清除 DUT 和历史观察状态。
    input wire [C_NUM_PORTS-1:0] i_return_enable, // 本地下一输出周期的总线预约许可。
    input wire i_retire_valid, // 本地退休元数据请求有效。
    input wire [1:0] i_retire_port, // 请求可能指向未使用的物理端口。
    input wire [1:0] i_retire_vc, // 任意原 VC 元数据，计数证明不约束其取值。
    input wire i_retire_pool, // 任意保存信用类型，数据完整性另外由参考仿真检查。
    output wire o_violation // 任一容量、守恒、资格或未用端口输出不满足。
); // 结束形式检查模块接口。
    localparam integer C_COUNT_WIDTH = (C_DEPTH <= 1) ? 1 : ((C_DEPTH <= 3) ? 2 : ((C_DEPTH <= 7) ? 3 : ((C_DEPTH <= 15) ? 4 : 5))); // 精确匹配由深度推导的 DUT 数量端口宽度。
    localparam [5:0] C_LIMIT = C_DEPTH[5:0]; // 加法与容量比较统一使用六位无符号范围。
    wire ready; // DUT 的真实沿前接纳许可。
    wire [3:0] valid, pool; // DUT 实际注册的返回批次有效及类型。
    wire [7:0] vcs, nums; // DUT 实际注册的保存 VC 和数量编码。
    wire [4*C_COUNT_WIDTH-1:0] counts; // DUT 的真实可见队列占用计数。
    reg [4*C_COUNT_WIDTH-1:0] previous_counts; // 独立保存前一采样沿之前的计数。
    reg [3:0] accepted_previous; // 每端口前一沿真实 ready/valid 握手的接纳量。
    reg [C_NUM_PORTS-1:0] enabled_previous; // 前一沿为注册返回预约的总线许可。
    wire [3:0] bad; // 所有端口的属性分别归约。
    genvar gen_port; // 固定展开四端口原生输出形状。
    upli_credit_return_queue #( // 保留实际 DUT 原始输入、寄存器和数据路径。
        .C_NUM_PORTS(C_NUM_PORTS), .C_DEPTH(C_DEPTH) // 使用同一深度推导的计数位宽。
    ) Return_Inst ( // 不把内部状态替换为自由变化的输入。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_return_enable(i_return_enable), // 共享实际环境时钟、复位及许可。
        .i_retire_valid(i_retire_valid), .i_retire_port(i_retire_port), .i_retire_vc(i_retire_vc), .i_retire_pool(i_retire_pool), // 完整退休元数据输入保持符号化。
        .o_retire_ready(ready), .o_credit_valid(valid), .o_credit_pool(pool), .o_credit_vc(vcs), .o_credit_num(nums), .o_pending_count(counts) // 属性只观察 DUT 真正输出。
    ); // 结束真实 DUT 的形式实例。
    always @(posedge i_clk) begin // 保存一拍前实际队列长度以建立局部守恒等式。
        if (!i_rstn) previous_counts <= {(4*C_COUNT_WIDTH){1'b0}}; // 复位后历史基线与 DUT 同时归零。
        else previous_counts <= counts; // 记录实际旧计数，不预测下一状态。
    end // 结束队列长度历史寄存器。
    always @(posedge i_clk) begin // 保存产生本拍注册输出所依据的沿前许可。
        if (!i_rstn) enabled_previous <= {C_NUM_PORTS{1'b0}}; // 复位沿没有合法新发布承诺。
        else enabled_previous <= i_return_enable; // 输入下一周期变化不取消此前已经承诺的输出。
    end // 结束返回许可历史寄存器。
    generate // 为每端口建立不依赖软件模型的算术检查。
        for (gen_port = 0; gen_port < 4; gen_port = gen_port+1) begin : gen_ports // 固定包含全部未用端口的检查。
            localparam [1:0] C_PORT = gen_port; // 退休目标地址比较的双位常量。
            wire [5:0] old_count, new_count, returned, accepted; // 额外位宽避免检查算术本身回绕。
            assign old_count = {{(6-C_COUNT_WIDTH){1'b0}}, previous_counts[gen_port*C_COUNT_WIDTH +: C_COUNT_WIDTH]}; // 零扩展前一沿真实数量。
            assign new_count = {{(6-C_COUNT_WIDTH){1'b0}}, counts[gen_port*C_COUNT_WIDTH +: C_COUNT_WIDTH]}; // 零扩展本沿真实数量。
            assign returned = valid[gen_port] ? ({4'b0000, nums[gen_port*2 +: 2]} + 6'd1) : 6'd0; // 从实际有效和数量编码独立恢复发布量。
            assign accepted = {5'b00000, accepted_previous[gen_port]}; // 每通道每拍最多接受一个本地记录。
            always @(posedge i_clk) begin // 每个端口独立记录前一沿真实接受事件。
                if (!i_rstn) accepted_previous[gen_port] <= 1'b0; // 复位不接受任何在途本地输入。
                else accepted_previous[gen_port] <= ready && i_retire_valid && (i_retire_port == C_PORT); // 只有真实握手进入守恒加法。
            end // 结束本端口接纳事件历史寄存器。
            if (gen_port < C_NUM_PORTS) begin : gen_active // 有效队列必须满足资源和发布资格属性。
                assign bad[gen_port] = (new_count > C_LIMIT) || ((old_count+accepted) != (new_count+returned)) || (returned > old_count) || (valid[gen_port] && !enabled_previous[gen_port]); // 不假设计数合法，而是将上界和旧队列资格一起证明。
            end else begin : gen_unused // 未用端口不允许数量或任何元信息出现。
                assign bad[gen_port] = (new_count != 6'd0) || valid[gen_port] || pool[gen_port] || (vcs[gen_port*2 +: 2] != 2'd0) || (nums[gen_port*2 +: 2] != 2'd0); // 固定零形状不能制造虚假信用或别名。
            end // 结束有效与未用端口属性选择。
        end // 结束全部四端口形式展开。
    endgenerate // 结束独立守恒及无旁路检查结构。
    assign o_violation = |bad; // 任一端口失败均使整体属性失败。
endmodule // 结束 upli_credit_return_properties 形式检查模块。
