// UPLI initial credit publisher; Common 2.0 sections 2.6 and 4.3.
// 日期 2026-09-08；每实例一个通道，不包含正常信用回收或真实数据存储。
// The return-direction connection must remain asserted until interface reset.
// 返回方向连接须保持至复位；容量参数由集成层绑定真实接收资源。
`timescale 1ps/1ps // 声明统一精度，可综合逻辑不包含延时。
module upli_credit_initializer #( // 初始信用发布模块为每个有效端口独立扫描接收容量。
    parameter integer C_NUM_PORTS = 1, // 一个 station 的原生 UPLI 端口数允许一、二或四。
    parameter integer C_CREDIT_WIDTH = 4, // 本地容量计数宽度范围为三至十六位。
    parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY = 8, // 未显式逐账户覆盖时使用的容量。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = {C_NUM_PORTS*5{C_DEFAULT_CAPACITY}} // 低位依次为各端口 VC0..3 及共享池。
) ( // 原生返回总线无 ready，输出电平由对端在下一沿采样。
    input wire i_clk, // 本模块全部状态属于同一 UPLI 上升沿域。
    input wire i_rstn, // 同步低有效复位，清理所有发布进度和输出。
    input wire i_credit_connected, // 返回者到信用接收者的方向已完成连接。
    output wire [3:0] o_credit_valid, // 各端口本周期输出一个一至四信用批次。
    output wire [3:0] o_credit_pool, // 有效批次来自共享池而非某专用 VC。
    output wire [7:0] o_credit_vc, // 各端口双位 VC 编码，初始池信用固定为零。
    output wire [7:0] o_credit_num, // 各端口实际发布数量减一的双位编码。
    output wire [3:0] o_credit_init_done // 各端口最后初始批次之后的粘滞完成电平。
); // 结束初始信用发布器参数与端口声明。
    genvar gen_port; // 常量展开四端口形状，未使用端口明确置零。
    generate // 参数合法性及每端口独立发布状态均在 elaboration 确定。
        if (((C_NUM_PORTS != 1) && (C_NUM_PORTS != 2) && (C_NUM_PORTS != 4)) || (C_CREDIT_WIDTH < 3) || (C_CREDIT_WIDTH > 16)) begin : gen_invalid // 拒绝截断端口或容量的非法实例配置。
            upli_initializer_parameters_invalid Invalid_Inst (); // 有意未定义模块令非法配置的层次检查失败。
        end // 结束参数合法性分支。
        for (gen_port = 0; gen_port < 4; gen_port = gen_port + 1) begin : gen_ports // 展开固定协议形状而非运行时动态数组。
            if (gen_port < C_NUM_PORTS) begin : gen_active // 仅为启用端口生成寄存器。
                localparam [2:0] ST_VC0 = 3'd0, ST_VC1 = 3'd1, ST_VC2 = 3'd2, ST_VC3 = 3'd3, ST_POOL = 3'd4, ST_DONE = 3'd5; // 按专用 VC、共享池、完成的顺序扫描。
                localparam [C_CREDIT_WIDTH:0] C_BATCH = {{(C_CREDIT_WIDTH-2){1'b0}}, 3'd4}; // 扩展宽度的最大每拍批次数量。
                localparam [5*C_CREDIT_WIDTH-1:0] C_PORT_CAPACITIES = C_CAPACITIES[gen_port*5*C_CREDIT_WIDTH +: 5*C_CREDIT_WIDTH]; // 常量提取本端口五账户容量。
                reg [2:0] state_current, state_next; // 三位账户阶段及其组合后继，不是协议线上编码。
                reg [C_CREDIT_WIDTH-1:0] cnt_issued; // 当前账户已调度到注册输出的信用数。
                reg [C_CREDIT_WIDTH-1:0] selected_capacity; // 按账户阶段选择的静态接收容量。
                wire [C_CREDIT_WIDTH:0] remaining; // 扩展减法得到当前账户尚待发布数量。
                wire flag_active, flag_last, flag_publish; // 扫描资格、账户末批及非零发布资格。
                reg [1:0] encoded_count; // 独立组合编码当前非零批次的一至四信用。
                reg reg_valid_o, reg_pool_o, reg_done_o; // 各自单独更新的原生控制输出寄存器。
                reg [1:0] reg_vc_o, reg_num_o; // 各自单独更新的批次元信息寄存器。
                assign remaining = {1'b0, selected_capacity} - {1'b0, cnt_issued}; // 合法可达状态中已发布数不会大于容量。
                assign flag_active = i_credit_connected && (state_current < ST_DONE); // 不等另一连接方向，也不在完成后重新扫描。
                assign flag_last = remaining <= C_BATCH; // 零容量账户也在一个扫描周期后前进。
                assign flag_publish = flag_active && (remaining != {(C_CREDIT_WIDTH+1){1'b0}}); // 零容量绝不能伪造一个信用批次。
                assign o_credit_valid[gen_port] = reg_valid_o; // 对端只能观察寄存后的有效信号。
                assign o_credit_pool[gen_port] = reg_pool_o; // 无效输出周期的池元信息固定为零。
                assign o_credit_vc[gen_port*2 +: 2] = reg_vc_o; // 低位端口的双位元信息位于打包低端。
                assign o_credit_num[gen_port*2 +: 2] = reg_num_o; // 编码不受发送方 TDM 相位限制。
                assign o_credit_init_done[gen_port] = reg_done_o; // 完成电平独立于其它端口保持。
                always @(*) begin // 静态账户容量选择，未用状态不会产生任意数据。
                    selected_capacity = {C_CREDIT_WIDTH{1'b0}}; // 完整组合默认值，避免锁存器。
                    case (state_current) // 状态索引对应四专用账户和一个共享池。
                        ST_VC0: selected_capacity = C_PORT_CAPACITIES[0*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 第零个 VC 的静态容量。
                        ST_VC1: selected_capacity = C_PORT_CAPACITIES[1*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 第一个 VC 的静态容量。
                        ST_VC2: selected_capacity = C_PORT_CAPACITIES[2*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 第二个 VC 的静态容量。
                        ST_VC3: selected_capacity = C_PORT_CAPACITIES[3*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 第三个 VC 的静态容量。
                        ST_POOL: selected_capacity = C_PORT_CAPACITIES[4*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 跨 VC 的唯一共享池容量。
                        default: selected_capacity = {C_CREDIT_WIDTH{1'b0}}; // 完成或非法状态不选择任何接收账户。
                    endcase // 结束静态容量选择。
                end // 结束账户解码组合过程。
                always @(*) begin // 计算账户阶段后继，非法状态不自动重发初始信用。
                    state_next = state_current; // 断连前等待或完成状态默认保持。
                    if (flag_active && flag_last) state_next = state_current + 3'd1; // 最后批调度后进入下一账户或完成阶段。
                end // 结束扫描阶段组合转移。
                always @(posedge i_clk) begin // 唯一同步状态寄存器更新。
                    if (!i_rstn) state_current <= ST_VC0; // 复位后必须从 VC0 开始一次新发布。
                    else state_current <= state_next; // 只按组合后继更新，不产生额外时钟。
                end // 结束账户阶段状态寄存器。
                always @(posedge i_clk) begin // 单独保存当前账户的已发布计数。
                    if (!i_rstn) cnt_issued <= {C_CREDIT_WIDTH{1'b0}}; // 同步复位清除部分发布历史。
                    else if (flag_active) begin // 连接前不预消耗任何初始化进度。
                        if (flag_last) cnt_issued <= {C_CREDIT_WIDTH{1'b0}}; // 账户完成后为下一个账户清零。
                        else cnt_issued <= cnt_issued + C_BATCH[C_CREDIT_WIDTH-1:0]; // 剩余大于四时加四仍不超过容量。
                    end // 结束活动账户计数更新。
                end // 结束发布进度寄存器。
                always @(*) begin // 直接生成数量减一编码，避免四信用被两位加法截断。
                    encoded_count = 2'd0; // 一信用及无效周期的安全默认编码。
                    if (remaining >= C_BATCH) encoded_count = 2'd3; // 四或更多剩余信用本拍发布四个。
                    else begin // 小尾批仅可能是零至三个信用。
                        case (remaining[1:0]) // 明确编码两信用及三信用的小尾批。
                            2'd2: encoded_count = 2'd1; // 实际两个信用编码为一。
                            2'd3: encoded_count = 2'd2; // 实际三个信用编码为二。
                            default: encoded_count = 2'd0; // 一个编码零，零批次由 valid 抑制。
                        endcase // 结束尾批编码选择。
                    end // 结束小尾批分支。
                end // 结束信用数量编码组合逻辑。
                always @(posedge i_clk) begin // 单独注册批次有效，不含输出反压。
                    if (!i_rstn) reg_valid_o <= 1'b0; // 复位沿必须取消所有可见批次。
                    else reg_valid_o <= flag_publish; // 连接且剩余非零时驱动一个新批次。
                end // 结束信用有效输出寄存器。
                always @(posedge i_clk) begin // 单独注册专用账户或共享池选择。
                    if (!i_rstn) reg_pool_o <= 1'b0; // 复位时元信息固定为零。
                    else reg_pool_o <= flag_publish && (state_current == ST_POOL); // 只有有效池批次置位。
                end // 结束池选择输出寄存器。
                always @(posedge i_clk) begin // 单独注册端口 VC 元信息。
                    if (!i_rstn) reg_vc_o <= 2'd0; // 复位不保留旧账户标识。
                    else reg_vc_o <= (flag_publish && (state_current < ST_POOL)) ? state_current[1:0] : 2'd0; // 池或空闲输出明确使用零 VC。
                end // 结束 VC 输出寄存器。
                always @(posedge i_clk) begin // 单独注册批次数量编码。
                    if (!i_rstn) reg_num_o <= 2'd0; // 复位期间无有效归还且编码清零。
                    else if (flag_publish) reg_num_o <= encoded_count; // 仅有效批次寄存已计算的数量编码。
                    else reg_num_o <= 2'd0; // 无效周期明确清零，不保留上一批次编码。
                end // 结束数量输出寄存器。
                always @(posedge i_clk) begin // 独立粘滞完成状态只在最后批的后续周期置位。
                    if (!i_rstn) reg_done_o <= 1'b0; // 只有 UPLI 复位可以撤销已承诺的初始化完成。
                    else if (i_credit_connected && (state_current == ST_DONE)) reg_done_o <= 1'b1; // 最后批驱动时仍是 POOL 阶段，因而不会同周期首次 done。
                end // 结束初始化完成输出寄存器。
            end else begin : gen_unused // 未实现端口保持原生总线的确定零值。
                assign o_credit_valid[gen_port] = 1'b0; // 未用端口不能发布信用。
                assign o_credit_pool[gen_port] = 1'b0; // 未用端口没有有效池字段。
                assign o_credit_vc[gen_port*2 +: 2] = 2'd0; // 未用端口 VC 元信息为零。
                assign o_credit_num[gen_port*2 +: 2] = 2'd0; // 未用端口批次编码为零。
                assign o_credit_init_done[gen_port] = 1'b0; // 未用端口不宣告初始化完成。
            end // 结束有效与未用端口分支。
        end // 结束固定四端口形状展开。
    endgenerate // 结束参数化初始信用发布结构。
endmodule // 结束 upli_credit_initializer 单通道初始发布模块。
