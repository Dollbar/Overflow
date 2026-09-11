`timescale 1ps/1ps // 控制时钟周期以皮秒明确声明。
module dl_basic_message_control #( // 模块实现Basic消息单本地请求、独立远端回复和真实提交时限。
    parameter C_CLOCK_PERIOD_PS = 640 // 此时钟必须稳定，不能静默继承可变UPLI周期。
)( // 原生同域输入与全部可观察输出。
    input wire i_clk, // 唯一原始控制时钟。
    input wire i_rstn, // 同步低有效全局复位。
    input wire i_local_valid, // 本地请求持续有效直至真正接纳。
    input wire [2:0] i_local_kind, // 本地mtype只支持一、四、五、六。
    input wire [15:0] i_local_rate, // 已按协议归一化的Rate编码。
    input wire i_device_valid, // 当前本地设备身份是否配置。
    input wire [9:0] i_device_id, // 当前十位本地设备编号。
    input wire i_device_type, // 零表示Switch，一表示Accelerator。
    input wire i_port_valid, // 当前本地端口编号是否配置。
    input wire [11:0] i_port, // 当前十二位本地端口编号。
    input wire i_folding, // 本端是否支持Folding。
    input wire i_tx_ready_advertised, // 是否声明主动发送TxReady通知能力。
    input wire i_symbols_valid, // 待激活PL发送器已提供有效符号的外部资格。
    input wire i_tx_limit_valid, // 外部已生效的pacing上限是否可用。
    input wire [15:0] i_tx_limit, // 外部实际pacing上限，不是待配置值。
    input wire i_rx_valid, // 可靠且正确分帧后的实际消息接收事件。
    input wire [31:0] i_rx_word, // 完整接收DWORD，保留字段忽略。
    input wire [3:0] i_source_take, // 外部真实仲裁消费，低到高对应mtype一、四、五、六。
    output wire o_local_ready, // 当前本地请求能否接纳。
    output wire o_local_pending, // 本地已接纳且尚未得到适用ACK的所有权。
    output wire o_local_waiting, // 本地请求已真正发出并等待ACK。
    output wire o_remote_pending, // 独立远端请求尚未真正回复。
    output wire [3:0] o_source_pending, // 按mtype一四五六排列的已就绪来源。
    output wire [127:0] o_source_words, // 四个完整且稳定的队首DWORD。
    output wire o_local_start, // 本沿实际接纳一个本地请求。
    output wire o_local_commit, // 本沿真正发出一个本地请求。
    output wire o_local_done, // 适用ACK完成旧本地等待。
    output wire o_reply_done, // 本沿真正回复一个旧远端请求。
    output wire o_rx_request, // 本沿接纳远端请求并保存回复义务。
    output wire o_rx_noop, // 接收NoOp且不产生ACK。
    output wire o_rx_unhandled, // 非本类或保留消息交给上层处理。
    output wire o_rx_unsupported, // 未启用Folding时的TxReady消息。
    output wire o_rx_unmatched_ack, // 没有匹配旧已发送本地请求的ACK。
    output wire o_rx_overlap, // 未回复的远端请求被第二请求违规重叠。
    output wire o_peer_rate_valid, // 是否已收到有效Rate请求。
    output wire [15:0] o_peer_rate, // 最近接纳的对端Rate编码。
    output wire o_peer_device_valid, // 最近对端设备身份是否有效。
    output wire [1:0] o_peer_device_type, // 原始对端Type编码，保留编码不提升为本地类型。
    output wire [9:0] o_peer_device_id, // 最近对端十位设备编号。
    output wire o_peer_port_valid, // 最近对端端口编号是否有效。
    output wire [11:0] o_peer_port, // 最近对端十二位端口编号。
    output wire o_peer_rate_update, // 本沿接纳新的Rate并需更新pacing。
    output wire o_deadline_miss, // 当前实际采样沿首次超过该回复一微秒预算。
    output wire o_deadline_fault, // 全局复位前保持已发生的迟到诊断。
    output wire o_protocol_fault, // 全局复位前保持已发生的协议输入诊断。
    output wire o_error // 本沿非法提交、请求类型或接收所有权错误。
); // 结束原生控制边界，不包含PLL或PHY实现。
    localparam C_ACK_CYCLES = 1000000/C_CLOCK_PERIOD_PS; // 一微秒上限必须向下取整而非放宽到下一拍。
    localparam [19:0] C_ACK_LAST = C_ACK_CYCLES[19:0]; // 最小一皮秒时最多允许一百万个完整周期。
    reg reg_local_busy; // 保存单个本地未完成请求。
    reg reg_local_sent; // 本地请求已在真实提交沿发出。
    reg [2:0] reg_local_kind; // 本地请求类型在接纳时冻结。
    reg [15:0] reg_local_upper; // 冻结本地消息高字段，固定头由类型重建。
    reg reg_remote_busy; // 保存单个独立远端回复义务。
    reg [2:0] reg_remote_kind; // 远端请求类型在接纳时冻结。
    reg [15:0] reg_remote_upper; // 冻结回复高字段与本地身份，固定头无需存储。
    reg [15:0] reg_remote_rate; // 此回复所对应的Rate上限。
    reg reg_local_first; // 同类型两槽并存时本地是否先入队。
    reg [19:0] cnt_remote_age; // 记录已过去的等待沿并在预算终点饱和。
    reg reg_remote_missed; // 同一远端请求只发出一次迟到事件。
    reg reg_deadline_fault; // 独立粘滞时限诊断不撤销回复。
    reg reg_protocol_fault; // 独立粘滞协议诊断不清除已保存所有权。
    reg reg_peer_rate_valid; // 保存对端Rate是否已通告。
    reg [15:0] reg_peer_rate; // 保存最新接纳Rate的原始编码。
    reg reg_peer_device_valid; // 保存最近已学习的设备Valid。
    reg [1:0] reg_peer_device_type; // 保存最近已学习的原始设备类型。
    reg [9:0] reg_peer_device_id; // 保存最近已学习的有效设备编号。
    reg reg_peer_port_valid; // 保存最近已学习的端口Valid。
    reg [11:0] reg_peer_port; // 保存最近已学习的有效端口编号。
    wire [2:0] rx_kind; // 已有线上mtype字段。
    wire [15:0] rx_rate; // 显式十六位Rate与远端字段快照。
    wire rx_identity_valid; // 显式单比特设备或端口Valid。
    wire [1:0] rx_device_type; // 无效身份清零后的两位类型。
    wire [9:0] rx_device_id; // 无效身份清零后的十位编号。
    wire [11:0] rx_port; // 无效身份清零后的十二位端口。
    wire flag_local_supported, flag_local_capable; // 本地类型和条件发送能力。
    wire flag_rx_basic, flag_rx_known, flag_rx_supported, flag_rx_ack, flag_rx_request; // 边界消息资格。
    wire flag_same_kind, flag_local_head, flag_remote_head, flag_remote_ready; // 两槽FIFO头及实际pacing资格。
    wire [3:0] sel_local, sel_remote; // 四类来源直接选择当前完整队首。
    wire flag_take_onehot; // 不接受多来源或无offer的提交。
    wire [3:0] sel_local_unqualified; // 不经过全局复位屏蔽的本地来源资格，仅用于内部错误判定。
    wire flag_local_head_unqualified, flag_remote_head_unqualified; // 两方向原始队首关系与复位屏蔽分开。
    wire flag_rx_error_supported, flag_rx_error_request, flag_rx_error_unmatched_ack; // 内部接收错误资格先独立计算，公开诊断最终由复位屏蔽。
    wire [3:0] sel_remote_unqualified; // 不依赖晚到pacing比较的远端类型及队首选择。
    wire flag_remote_take_unqualified; // 单资源消费与远端队首资格提前完成。
    wire flag_error_ready, flag_error_blocked; // 分别预计算允许回复与禁止回复时的输入诊断。
    wire [3:0] flag_rate_lt, flag_rate_eq; // 四个独立四位比较先并行完成。
    wire flag_rate_limit_ok; // 高位优先组合完整十六位小于或相等。
    wire flag_learn_device, flag_learn_port; // 只有接纳请求或匹配ACK更新身份。
    wire [15:0] word_device, word_port, word_local, word_reply; // 只形成消息高十六位的身份与Rate快照。
    wire unused_rx_reserved; // 明确消费被忽略的保留字段以便静态检查。
    assign unused_rx_reserved = ^{i_rx_word[15:13], i_rx_word[11:9], i_rx_word[1:0]}; // 保留字段不参与任何资格、状态或响应编码。
    assign rx_kind = i_rx_word[8:6]; // 位号来自已核对消息表。
    assign rx_rate = i_rx_word[31:16]; // 全部十六位作为固定宽度寄存输入。
    assign rx_identity_valid = i_rx_word[31]; // 设备和端口共用相同Valid位号。
    assign rx_device_type = rx_identity_valid ? i_rx_word[30:29] : 2'd0; // 保留类型仅作原始观察。
    assign rx_device_id = rx_identity_valid ? i_rx_word[25:16] : 10'd0; // 未配置时不保留旧编号。
    assign rx_port = rx_identity_valid ? i_rx_word[27:16] : 12'd0; // 未配置时端口明确为零。
    assign flag_local_supported = (i_local_kind == 3'd1) || (i_local_kind == 3'd4) || (i_local_kind == 3'd5) || (i_local_kind == 3'd6); // 不为保留类型生成请求。
    assign flag_local_capable = (i_local_kind != 3'd1) || (i_folding && i_tx_ready_advertised && i_symbols_valid); // TxReady必须来自适用PL发送资格。
    assign o_local_ready = i_rstn && !reg_local_busy && flag_local_supported && flag_local_capable; // 不因同沿ACK提前重用旧忙槽。
    assign o_local_start = i_local_valid && o_local_ready; // 唯一实际本地接纳边界。
    assign o_local_pending = i_rstn && reg_local_busy; // 全局复位期间屏蔽旧所有权。
    assign o_local_waiting = i_rstn && reg_local_busy && reg_local_sent; // 新请求提交同沿的提前ACK仍不匹配。
    assign o_remote_pending = i_rstn && reg_remote_busy; // 远端义务不依赖本地等待。
    assign flag_same_kind = reg_local_kind == reg_remote_kind; // 只有同类型需要两槽先后关系。
    assign flag_local_head_unqualified = reg_local_busy && !reg_local_sent && !(reg_remote_busy && flag_same_kind && !reg_local_first); // 原始本地队首只依赖已保存的所有权与顺序。
    assign flag_local_head = i_rstn && flag_local_head_unqualified; // 公开本地来源在复位期间必须为零。
    assign flag_remote_head_unqualified = reg_remote_busy && !(reg_local_busy && !reg_local_sent && flag_same_kind && reg_local_first); // 原始远端队首独立于输入复位的组合传播。
    assign flag_remote_head = i_rstn && flag_remote_head_unqualified; // 公开远端来源保留完整复位屏蔽。
    assign flag_rate_lt[0] = i_tx_limit[3:0] < reg_remote_rate[3:0]; // 此四位实际上限严格小于请求字段。
    assign flag_rate_eq[0] = i_tx_limit[3:0] == reg_remote_rate[3:0]; // 高位相等时才向下一组传递比较。
    assign flag_rate_lt[1] = i_tx_limit[7:4] < reg_remote_rate[7:4]; // 此四位实际上限严格小于请求字段。
    assign flag_rate_eq[1] = i_tx_limit[7:4] == reg_remote_rate[7:4]; // 高位相等时才向下一组传递比较。
    assign flag_rate_lt[2] = i_tx_limit[11:8] < reg_remote_rate[11:8]; // 此四位实际上限严格小于请求字段。
    assign flag_rate_eq[2] = i_tx_limit[11:8] == reg_remote_rate[11:8]; // 高位相等时才向下一组传递比较。
    assign flag_rate_lt[3] = i_tx_limit[15:12] < reg_remote_rate[15:12]; // 此四位实际上限严格小于请求字段。
    assign flag_rate_eq[3] = i_tx_limit[15:12] == reg_remote_rate[15:12]; // 高位相等时才向下一组传递比较。
    assign flag_rate_limit_ok = flag_rate_lt[3] || (flag_rate_eq[3] && flag_rate_lt[2]) || (flag_rate_eq[3] && flag_rate_eq[2] && flag_rate_lt[1]) || (flag_rate_eq[3] && flag_rate_eq[2] && flag_rate_eq[1] && flag_rate_lt[0]) || (&flag_rate_eq); // 完整相等也必须允许Rate确认。
    assign flag_remote_ready = (reg_remote_kind != 3'd4) || (i_tx_limit_valid && flag_rate_limit_ok); // RateACK必须在真实pacing限制满足后发送。
    assign sel_local = {flag_local_head && (reg_local_kind == 3'd6), flag_local_head && (reg_local_kind == 3'd5), flag_local_head && (reg_local_kind == 3'd4), flag_local_head && (reg_local_kind == 3'd1)}; // 本地四类来源固定映射。
    assign sel_remote = {flag_remote_head && (reg_remote_kind == 3'd6), flag_remote_head && (reg_remote_kind == 3'd5), flag_remote_head && flag_remote_ready && (reg_remote_kind == 3'd4), flag_remote_head && (reg_remote_kind == 3'd1)}; // 仅实际Rate来源经过pacing资格，其余三类回复直接使用各自队首。
    assign sel_remote_unqualified[0] = flag_remote_head_unqualified && (reg_remote_kind == 3'd1); // 提前选择真实远端方向及类型。
    assign sel_remote_unqualified[1] = flag_remote_head_unqualified && (reg_remote_kind == 3'd4); // 提前选择真实远端方向及类型。
    assign sel_remote_unqualified[2] = flag_remote_head_unqualified && (reg_remote_kind == 3'd5); // 提前选择真实远端方向及类型。
    assign sel_remote_unqualified[3] = flag_remote_head_unqualified && (reg_remote_kind == 3'd6); // 提前选择真实远端方向及类型。
    assign flag_remote_take_unqualified = flag_take_onehot && (|(i_source_take & sel_remote_unqualified)); // 提前检验唯一take与远端现有队首。
    assign o_source_pending = sel_local | sel_remote; // 每类最多一个当前可发送队首。
    assign o_source_words[31:0] = ({32{sel_local[0]}} & 32'h00000040) | ({32{sel_remote[0]}} & 32'h00001040); // 固定低字段按来源重建，高字段保持接纳沿快照。
    assign o_source_words[63:32] = ({32{sel_local[1]}} & {reg_local_upper, 16'h0100}) | ({32{sel_remote[1]}} & 32'h00001100); // 固定低字段按来源重建，高字段保持接纳沿快照。
    assign o_source_words[95:64] = ({32{sel_local[2]}} & {reg_local_upper, 16'h0140}) | ({32{sel_remote[2]}} & {reg_remote_upper, 16'h1140}); // 固定低字段按来源重建，高字段保持接纳沿快照。
    assign o_source_words[127:96] = ({32{sel_local[3]}} & {reg_local_upper, 16'h0180}) | ({32{sel_remote[3]}} & {reg_remote_upper, 16'h1180}); // 固定低字段按来源重建，高字段保持接纳沿快照。
    assign flag_take_onehot = (i_source_take != 4'd0) && ((i_source_take & (i_source_take-4'd1)) == 4'd0); // 唯一物理发送资源只允许一个来源。
    assign o_local_commit = i_rstn && flag_take_onehot && (|(i_source_take & sel_local)); // 真正提交后本地等待ACK。
    assign o_reply_done = i_rstn && flag_remote_take_unqualified && flag_remote_ready; // 真正提交恰好释放旧远端槽。
    assign flag_rx_basic = i_rstn && i_rx_valid && (i_rx_word[5:2] == 4'd0); // 接收资格不检查保留字段。
    assign flag_rx_known = (rx_kind == 3'd0) || (rx_kind == 3'd1) || (rx_kind == 3'd4) || (rx_kind == 3'd5) || (rx_kind == 3'd6); // 完整Basic类型目录。
    assign flag_rx_supported = flag_rx_basic && flag_rx_known && (rx_kind != 3'd0) && ((rx_kind != 3'd1) || i_folding); // 不将NoOp解释为带ACK的请求。
    assign flag_rx_ack = flag_rx_supported && i_rx_word[12]; // ACK不依赖保留Rate回显。
    assign flag_rx_request = flag_rx_supported && !i_rx_word[12]; // 请求与响应按明确Ack位分离。
    assign o_local_done = flag_rx_ack && reg_local_busy && reg_local_sent && (rx_kind == reg_local_kind); // 只匹配旧状态的已发送请求类型。
    assign o_rx_unmatched_ack = flag_rx_ack && !o_local_done; // 提前、重复或其它类型ACK只诊断。
    assign o_rx_request = flag_rx_request && (!reg_remote_busy || o_reply_done); // 本沿真实回复允许接纳下一远端请求。
    assign o_rx_overlap = flag_rx_request && reg_remote_busy && !o_reply_done; // 重叠请求不得覆盖旧消息。
    assign o_rx_noop = flag_rx_basic && (rx_kind == 3'd0); // NoOp全部高位均忽略且无回复。
    assign o_rx_unhandled = i_rstn && i_rx_valid && (!flag_rx_basic || !flag_rx_known); // 保留类和类型由后续完整解码处理。
    assign o_rx_unsupported = flag_rx_basic && (rx_kind == 3'd1) && !i_folding; // 缺少Folding能力时不伪造确认。
    assign sel_local_unqualified[0] = flag_local_head_unqualified && (reg_local_kind == 3'd1); // 内部错误判定提前选择真实本地队首及类型。
    assign sel_local_unqualified[1] = flag_local_head_unqualified && (reg_local_kind == 3'd4); // 内部错误判定提前选择真实本地队首及类型。
    assign sel_local_unqualified[2] = flag_local_head_unqualified && (reg_local_kind == 3'd5); // 内部错误判定提前选择真实本地队首及类型。
    assign sel_local_unqualified[3] = flag_local_head_unqualified && (reg_local_kind == 3'd6); // 内部错误判定提前选择真实本地队首及类型。
    assign flag_rx_error_supported = i_rx_valid && (i_rx_word[5:2] == 4'd0) && flag_rx_known && (rx_kind != 3'd0) && ((rx_kind != 3'd1) || i_folding); // 仅内部错误锥使用不含复位的完整消息资格。
    assign flag_rx_error_request = flag_rx_error_supported && !i_rx_word[12]; // 原始请求资格不改变公开接纳事件。
    assign flag_rx_error_unmatched_ack = flag_rx_error_supported && i_rx_word[12] && !(reg_local_busy && reg_local_sent && (rx_kind == reg_local_kind)); // 原始ACK匹配仍只依据旧已发送本地请求。
    assign flag_error_ready = ((i_source_take != 4'd0) && (!flag_take_onehot || ((i_source_take & ~(sel_local_unqualified | sel_remote_unqualified)) != 4'd0))) || (i_local_valid && !flag_local_supported) || flag_rx_error_unmatched_ack || (flag_rx_error_request && reg_remote_busy && !flag_remote_take_unqualified); // 允许旧回复时预先计算全部错误，不等待Rate结果。
    assign flag_error_blocked = ((i_source_take != 4'd0) && (!flag_take_onehot || ((i_source_take & ~sel_local_unqualified) != 4'd0))) || (i_local_valid && !flag_local_supported) || flag_rx_error_unmatched_ack || (flag_rx_error_request && reg_remote_busy); // 禁止旧回复时仍允许本地独立提交并记录真实重叠。
    assign o_error = i_rstn && (flag_error_ready || (!flag_remote_ready && flag_error_blocked)); // 禁止回复只能增加错误，晚到资格只通过最终合并。
    assign word_device = {i_device_valid, 1'b0, i_device_type, 3'd0, (i_device_valid ? i_device_id : 10'd0)}; // 固定低字段按来源重建，高字段保持接纳沿快照。
    assign word_port = {i_port_valid, 3'd0, (i_port_valid ? i_port : 12'd0)}; // 固定低字段按来源重建，高字段保持接纳沿快照。
    assign word_local = (i_local_kind == 3'd1) ? 16'd0 : ((i_local_kind == 3'd4) ? i_local_rate : ((i_local_kind == 3'd5) ? word_device : word_port)); // 固定低字段按来源重建，高字段保持接纳沿快照。
    assign word_reply = (rx_kind == 3'd5) ? word_device : ((rx_kind == 3'd6) ? word_port : 16'd0); // 固定低字段按来源重建，高字段保持接纳沿快照。
    assign flag_learn_device = (o_rx_request || o_local_done) && (rx_kind == 3'd5); // 请求和适用ACK各携带发送者身份。
    assign flag_learn_port = (o_rx_request || o_local_done) && (rx_kind == 3'd6); // 未匹配ACK不能污染已学习端口。
    assign o_peer_rate_update = o_rx_request && (rx_kind == 3'd4); // 只有新的Rate请求更新对端速率。
    assign o_peer_rate_valid = i_rstn && reg_peer_rate_valid; // 全局复位屏蔽旧Rate有效位。
    assign o_peer_rate = o_peer_rate_valid ? reg_peer_rate : 16'd0; // 未学习时输出确定零值。
    assign o_peer_device_valid = i_rstn && reg_peer_device_valid; // 设备Valid不因本地请求状态改变。
    assign o_peer_device_type = o_peer_device_valid ? reg_peer_device_type : 2'd0; // 无效身份不暴露旧类型。
    assign o_peer_device_id = o_peer_device_valid ? reg_peer_device_id : 10'd0; // 无效身份不暴露旧编号。
    assign o_peer_port_valid = i_rstn && reg_peer_port_valid; // 独立保存对端Port有效位。
    assign o_peer_port = o_peer_port_valid ? reg_peer_port : 12'd0; // 无效Port明确为零。
    assign o_deadline_miss = i_rstn && reg_remote_busy && !reg_remote_missed && (cnt_remote_age == C_ACK_LAST); // 当前采样沿将超过允许的完整周期数。
    assign o_deadline_fault = i_rstn && reg_deadline_fault; // 时限诊断不改变回复队首。
    assign o_protocol_fault = i_rstn && reg_protocol_fault; // 协议输入诊断由全局复位清除。
    generate // 非法计时参数必须阻止展开。
        if ((C_CLOCK_PERIOD_PS < 1) || (C_CLOCK_PERIOD_PS > 1000000000)) begin : gen_invalid // 保持真实计时范围明确。
            dl_basic_control_parameters_invalid Invalid_Inst (); // 未定义层次用于拒绝非法参数。
        end // 结束参数错误分支。
    endgenerate // 结束合法性检查。
    always @(posedge i_clk) begin // 保存本地唯一请求所有权。
        if (!i_rstn) reg_local_busy <= 1'b0; // 全局复位清空本地请求。
        else if (o_local_start) reg_local_busy <= 1'b1; // 接纳时建立所有权。
        else if (o_local_done) reg_local_busy <= 1'b0; // 只有适用ACK完成本地请求。
    end // 结束本地忙寄存更新。
    always @(posedge i_clk) begin // 保存本地已发送阶段。
        if (!i_rstn || o_local_start || o_local_done) reg_local_sent <= 1'b0; // 新请求不能继承旧已发送状态。
        else if (o_local_commit) reg_local_sent <= 1'b1; // 实际提交后才允许ACK匹配。
    end // 结束本地发送阶段更新。
    always @(posedge i_clk) begin // 冻结本地请求类型。
        if (!i_rstn) reg_local_kind <= 3'd0; // 复位清除旧类型。
        else if (o_local_start) reg_local_kind <= i_local_kind; // 接纳后不跟随上游变化。
    end // 结束本地类型更新。
    always @(posedge i_clk) begin // 冻结本地完整消息。
        if (!i_rstn) reg_local_upper <= 16'd0; // 复位清除旧字。
        else if (o_local_start) reg_local_upper <= word_local; // 含身份和保留字段的完整快照。
    end // 结束本地字更新。
    always @(posedge i_clk) begin // 保存独立远端回复所有权。
        if (!i_rstn) reg_remote_busy <= 1'b0; // 全局复位清空远端义务。
        else if (o_rx_request) reg_remote_busy <= 1'b1; // 同沿旧回复出队后可被新请求替换。
        else if (o_reply_done) reg_remote_busy <= 1'b0; // 真实回复结束这一项义务。
    end // 结束远端忙寄存更新。
    always @(posedge i_clk) begin // 冻结远端消息类型。
        if (!i_rstn) reg_remote_kind <= 3'd0; // 复位清除旧类型。
        else if (o_rx_request) reg_remote_kind <= rx_kind; // 重叠未接纳请求不覆盖类型。
    end // 结束远端类型更新。
    always @(posedge i_clk) begin // 冻结远端完整回复。
        if (!i_rstn) reg_remote_upper <= 16'd0; // 复位清除旧ACK。
        else if (o_rx_request) reg_remote_upper <= word_reply; // 后续CSR身份变化不改已有队首。
    end // 结束远端字更新。
    always @(posedge i_clk) begin // 保存这项Rate回复所需的pacing界。
        if (!i_rstn) reg_remote_rate <= 16'd0; // 复位清除旧限制。
        else if (o_rx_request) reg_remote_rate <= rx_rate; // 非Rate时该字段不参与资格。
    end // 结束远端Rate快照更新。
    always @(posedge i_clk) begin // 保存同类双槽进入次序。
        if (!i_rstn) reg_local_first <= 1'b0; // 复位时没有先入队本地请求。
        else if (o_rx_request) reg_local_first <= reg_local_busy && !reg_local_sent && !o_local_commit; // 已存在未提交本地队首先于新回复。
        else if (o_local_start) reg_local_first <= 1'b0; // 新本地请求不能越过旧或同沿新回复。
    end // 结束同类次序更新。
    always @(posedge i_clk) begin // 保存真实回复等待沿计数。
        if (!i_rstn || o_rx_request || o_reply_done || !reg_remote_busy) cnt_remote_age <= 20'd0; // 新接收从零个已过去周期开始。
        else if (cnt_remote_age != C_ACK_LAST) cnt_remote_age <= cnt_remote_age+20'd1; // 从零递增至终点即保持，零周期预算也无无符号恒假比较。
    end // 结束远端年龄计数。
    always @(posedge i_clk) begin // 每个远端请求只报告一次迟到。
        if (!i_rstn || o_rx_request || o_reply_done) reg_remote_missed <= 1'b0; // 新义务不能继承旧迟到标记。
        else if (o_deadline_miss) reg_remote_missed <= 1'b1; // 首次超过预算后保持。
    end // 结束每项迟到标记。
    always @(posedge i_clk) begin // 保持全局时限诊断。
        if (!i_rstn) reg_deadline_fault <= 1'b0; // 仅全局复位清除。
        else if (o_deadline_miss) reg_deadline_fault <= 1'b1; // 即使本沿终于回复也保留迟到证据。
    end // 结束粘滞时限诊断。
    always @(posedge i_clk) begin // 保持全局协议输入诊断。
        if (!i_rstn) reg_protocol_fault <= 1'b0; // 全局复位恢复清洁诊断状态。
        else if (o_error) reg_protocol_fault <= 1'b1; // 不影响其它正确义务继续前进。
    end // 结束粘滞协议诊断。
    always @(posedge i_clk) begin // 保存对端Rate有效位。
        if (!i_rstn) reg_peer_rate_valid <= 1'b0; // 复位后须重新接收Rate请求。
        else if (o_peer_rate_update) reg_peer_rate_valid <= 1'b1; // ACK不建立新的对端通告。
    end // 结束对端Rate有效寄存。
    always @(posedge i_clk) begin // 保存对端Rate数值。
        if (!i_rstn) reg_peer_rate <= 16'd0; // 复位数据确定。
        else if (o_peer_rate_update) reg_peer_rate <= rx_rate; // 仅新接纳请求更新。
    end // 结束对端Rate数值寄存。
    always @(posedge i_clk) begin // 保存对端设备Valid。
        if (!i_rstn) reg_peer_device_valid <= 1'b0; // 复位后身份未知。
        else if (flag_learn_device) reg_peer_device_valid <= rx_identity_valid; // 未配置对端主动撤销旧Valid。
    end // 结束设备Valid寄存。
    always @(posedge i_clk) begin // 保存对端原始Type。
        if (!i_rstn) reg_peer_device_type <= 2'd0; // 复位后输出由Valid屏蔽。
        else if (flag_learn_device) reg_peer_device_type <= rx_device_type; // 保留编码仅作为原始观察保存。
    end // 结束设备类型寄存。
    always @(posedge i_clk) begin // 保存有效对端设备编号。
        if (!i_rstn) reg_peer_device_id <= 10'd0; // 复位清除旧编号。
        else if (flag_learn_device) reg_peer_device_id <= rx_device_id; // 无效身份不泄露旧数据。
    end // 结束设备编号寄存。
    always @(posedge i_clk) begin // 保存对端端口Valid。
        if (!i_rstn) reg_peer_port_valid <= 1'b0; // 复位后端口未知。
        else if (flag_learn_port) reg_peer_port_valid <= rx_identity_valid; // 接纳请求或匹配ACK更新。
    end // 结束端口Valid寄存。
    always @(posedge i_clk) begin // 保存有效对端端口编号。
        if (!i_rstn) reg_peer_port <= 12'd0; // 复位清除旧编号。
        else if (flag_learn_port) reg_peer_port <= rx_port; // 未配置身份强制为零。
    end // 结束端口编号寄存。
endmodule // 结束Basic消息控制模块。
