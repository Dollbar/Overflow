// Native UPLI Write Response sender; Common 2.0 sections 2.5/2.6/2.7.6/2.7.8/4.3.
// 日期2026-09-11；独立信用银行和 TDM 相位，无本地候选队列或命令执行。
`timescale 1ns/1ps // 统一发送组件仿真单位，不在可综合状态中引入延时。
`default_nettype none // 禁止隐式网络掩盖真实信用与原生字段接线。
module upli_write_response_sender #( // 单 Beat Write Response 的真实准入与发送模块。
    parameter integer C_NUM_PORTS = 1, // station 支持一、二或四个原生端口。
    parameter integer C_CREDIT_WIDTH = 4, // 每个账户的信用计数位宽支持三至十六。
    parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY = 4, // 默认账户容量，实际容量由接收资源声明。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = {C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 每端口低位依次 VC0..3 和共享 Pool。
    parameter integer C_INIT_COUNT_WIDTH = 4, // 信用初始化连续确认的计数参数位宽。
    parameter integer C_INIT_CYCLES = 2 // 初始完成必须连续采样超过一个周期。
) ( // 所有实际发送与信用状态属于同一时钟和共同 reset。
    input wire i_clk, // 公共 UPLI 上升沿时钟。
    input wire i_rstn, // 同步低有效复位清空全部本通道状态。
    input wire i_credit_connected, // 返回信用方向已建立真实连接。
    input wire i_beats_connected, // 双向连接已满足发出原生 Beat 的资格。
    input wire i_candidate_valid, // 上游已构造且在接受之前保持的完整响应候选。
    input wire [1:0] i_candidate_port, // 候选目标端口，不能绕过本通道独立时隙。
    input wire [1:0] i_candidate_vc, // 原响应 VC，专用信用按此选择。
    input wire i_candidate_pool, // 本拍使用共享 Pool 信用而非专用 VC。
    input wire [100:0] i_candidate_payload, // 固定 Auth64/Type2/Tag11/Status4/Src10/Dst10 本地容器。
    input wire [3:0] i_credit_valid, // 四端口返回有效可同时到达，不受 TDM 限制。
    input wire [3:0] i_credit_pool, // 各端口返回对应的原信用类型。
    input wire [7:0] i_credit_vc, // 每端口两位返回 VC 元信息。
    input wire [7:0] i_credit_num, // 每端口两位编码表示实际归还一至四信用。
    input wire [3:0] i_credit_init_done, // 各端口初始发布完成的持续电平。
    output wire o_candidate_accepted, // 本地所有权转移仅发生在真实原生发送的同一沿。
    output wire o_valid, // 生产 typed leaf 输出的实际 WrRspVld。
    output wire [1:0] o_type_info, // 保留原响应类别提示全部位。
    output wire [10:0] o_tag, // 保留原响应完整十一位标签。
    output wire [3:0] o_status, // 透明传递状态，不代替命令资格检查。
    output wire [9:0] o_src, // 原响应 debug 源标识，不用于准入路由决策。
    output wire [9:0] o_dst, // 原响应完整目标加速器标识。
    output wire [1:0] o_port, // 实际发送的端口及原生 TDM 标识。
    output wire [1:0] o_vc, // 实际发出的原响应 VC。
    output wire o_pool, // 实际发出的信用账户类型。
    output wire [63:0] o_auth_tag, // 完整授权标签由上游按授权上下文准备。
    output wire o_valid_parity, // 公共保护原语生成的原生有效保护。
    output wire o_auth_tag_parity, // 完整授权标签的独立偶校验。
    output wire o_control_parity, // 四十二位原生控制组的独立偶校验。
    output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_balances, // 单个真实银行的沿前注册余额。
    output wire [3:0] o_init_confirmed, // 经过连续采样确认的各端口初始信用资格。
    output wire o_credit_error, // 真实银行上一个采样沿的本地拒绝诊断。
    output wire o_credit_error_sticky, // 到共同 reset 才清除的错误汇总，不是恢复完成状态。
    output wire o_tdm_known, // 首次实际发送已经确定本通道独立相位。
    output wire [1:0] o_tdm_port // 当前独立发送时隙，尚未建立时输出零。
); // 结束真实发送器接口，不增加原生 ready 或透明队列。
    localparam PORT_COUNT = C_NUM_PORTS; // 固定生成端口数量，实际合法性由真实银行参数检查负责。
    localparam PHASE_MASK_VALUE = C_NUM_PORTS - 1; // 原生端口数一二四对应自然两位循环掩码。
    localparam [1:0] PHASE_MASK = PHASE_MASK_VALUE[1:0]; // 显式取两位常量，不让参数宽度漂移到状态寄存器。
    wire [C_NUM_PORTS*5-1:0] account_ready; // 并行查看每个候选匹配账户的沿前非空资格。
    wire flag_send; // 连接、候选、信用及独立时隙共同决定的原生发送事件。
    wire [1:0] next_phase; // 已建立时隙在每个周期固定前进一次。
    reg reg_phase_known; // 仅真实首发建立，共同 reset 清除。
    reg [1:0] reg_phase; // 本 Write Response 通道独立的两位 TDM 状态。
    reg reg_credit_error; // 保存曾经出现的真实银行错误，不干预其正常计数。
    genvar gen_port, gen_account; // 固定展开端口和各自的五个账户。
    assign flag_send = i_rstn && i_credit_connected && i_beats_connected && i_candidate_valid && (|account_ready) && (!reg_phase_known || (reg_phase == i_candidate_port)); // 不旁路同沿返回或同沿初始化确认。
    assign o_candidate_accepted = o_valid; // 唯一实际发出事件也是上游候选退休事件。
    assign o_tdm_known = reg_phase_known; // 对外暴露真实寄存相位资格。
    assign o_tdm_port = reg_phase; // 未建立状态由共同 reset 确定为零。
    assign next_phase = (reg_phase + 2'd1) & PHASE_MASK; // 空周期也按配置端口数轮转。
    assign o_credit_error_sticky = reg_credit_error || o_credit_error; // 新出现的注册诊断立即加入持续汇总。
    always @(posedge i_clk) begin // 首发资格寄存器仅保存独立通道相位是否已知。
        if (!i_rstn) reg_phase_known <= 1'b0; // 新 epoch 尚未确定时隙。
        else if (o_valid) reg_phase_known <= 1'b1; // 信用实际消耗时建立并保持资格。
    end // 结束独立相位资格寄存过程。
    always @(posedge i_clk) begin // 已建立相位不能因候选或无信用而停止。
        if (!i_rstn) reg_phase <= 2'd0; // 共同 reset 清除前一 epoch 的时隙。
        else if (reg_phase_known) reg_phase <= next_phase; // 每周期前进，不以输出有效门控时隙。
        else if (o_valid) reg_phase <= (i_candidate_port + 2'd1) & PHASE_MASK; // 首发使用候选端口，沿后进入下一个时隙。
    end // 结束独立 TDM 计数过程。
    always @(posedge i_clk) begin // 保存诊断历史，当前 bank 拒绝仍由其原始输出提供。
        if (!i_rstn) reg_credit_error <= 1'b0; // reset 清除本地错误汇总。
        else if (o_credit_error) reg_credit_error <= 1'b1; // 持续记录银行诊断，不虚构恢复状态。
    end // 结束信用错误历史寄存过程。
    generate // 常量展开每个端口和账户的非空准入检查。
        for (gen_port = 32'd0; gen_port < PORT_COUNT; gen_port = gen_port + 32'd1) begin : gen_ports // 未配置端口不会产生任何发送资格。
            localparam [1:0] PORT_ID = gen_port[1:0]; // 两位原生端口比较常量。
            for (gen_account = 32'd0; gen_account < 32'd5; gen_account = gen_account + 32'd1) begin : gen_accounts // 每端口四个 VC 和一个 Pool 独立检查。
                localparam [1:0] VC_ID = gen_account[1:0]; // 专用账户使用完整两位 VC 比较。
                assign account_ready[gen_port*5+gen_account] = (i_candidate_port == PORT_ID) && o_init_confirmed[gen_port] && ((gen_account == 4) ? i_candidate_pool : (!i_candidate_pool && (i_candidate_vc == VC_ID))) && (|o_balances[(gen_port*5+gen_account)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]); // 只查看匹配账户的已注册非零余额。
            end // 结束本端口五个信用账户检查。
        end // 结束全部已配置端口检查。
    endgenerate // 结束固定资格检查逻辑。
    upli_credit_bank #( // 本通道只有一个真实银行，不复制计数算法。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), // 保持端口数量与每个计数宽度完全一致。
        .C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY), .C_CAPACITIES(C_CAPACITIES), // 实际容量参数直接映射原接收资源声明。
        .C_INIT_COUNT_WIDTH(C_INIT_COUNT_WIDTH), .C_INIT_CYCLES(C_INIT_CYCLES) // 完整复用沿前初始化确认语义。
    ) u_bank ( // 接受全部原始信用事件，发送端不制造反向 ready。
        .i_clk(i_clk), .i_rstn(i_rstn), // 银行与相位、typed 输出共时钟与 reset。
        .i_credit_connected(i_credit_connected), .i_beats_connected(i_beats_connected), // 直接传入外部真实连接资格。
        .i_credit_valid(i_credit_valid), .i_credit_pool(i_credit_pool), // 返回信用不受候选或 TDM 限制。
        .i_credit_vc(i_credit_vc), .i_credit_num(i_credit_num), .i_credit_init_done(i_credit_init_done), // 完整保留四端口返回字段与初始化电平。
        .i_send_valid(o_valid), .i_send_port(o_port), .i_send_vc(o_vc), .i_send_pool(o_pool), // 仅按真实 native 发送事件扣原账户一次。
        .o_balances(o_balances), .o_init_confirmed(o_init_confirmed), .o_error(o_credit_error) // 真实银行状态与诊断直接对外可查。
    ); // 结束唯一 Write Response 信用银行实例。
    upli_write_response_channel u_channel ( // 实際 typed leaf 负责完整字段和公共 parity 输出。
        .i_rstn(i_rstn), .i_valid(flag_send), .o_valid(o_valid), // 相同 reset 与真实准入事件禁止产生幽灵响应。
        .i_type_info(i_candidate_payload[36:35]), .o_type_info(o_type_info), // 本地容器的类别提示完整两位。
        .i_tag(i_candidate_payload[34:24]), .o_tag(o_tag), // 完整十一位标签不能退化为十位。
        .i_status(i_candidate_payload[23:20]), .o_status(o_status), // 状态值透明交给原生通道。
        .i_src(i_candidate_payload[19:10]), .o_src(o_src), // 保留十位 debug 源标识。
        .i_dst(i_candidate_payload[9:0]), .o_dst(o_dst), // 保留十位目标标识用于后续路由。
        .i_auth_tag(i_candidate_payload[100:37]), .o_auth_tag(o_auth_tag), // 完整六十四位授权标签独立保护。
        .i_port(i_candidate_port), .o_port(o_port), .i_vc(i_candidate_vc), .o_vc(o_vc), // 原始端口与 VC 来自同一个稳定候选。
        .i_pool(i_candidate_pool), .o_pool(o_pool), // 实际选定信用类型与扣账选择一致。
        .o_valid_parity(o_valid_parity), .o_auth_tag_parity(o_auth_tag_parity), .o_control_parity(o_control_parity) // 原生保护码只由公共 leaf 路径提供。
    ); // 结束生产 Write Response 字段与保护码实例。
endmodule // 结束 upli_write_response_sender 无队列真实原生发送模块。
`default_nettype wire // 恢复后续独立源码编译设置。
