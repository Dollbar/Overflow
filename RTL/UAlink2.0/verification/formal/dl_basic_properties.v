`timescale 1ps/1ps // 独立参考使用明确稳定时钟配置。
module dl_basic_properties #(parameter C_PERIOD_PS = 640) ( // 模块证明Basic完整实际状态与全部公开输出。
    input wire i_clk, // 真实原生输入保持符号自由。
    input wire i_rstn, // 真实原生输入保持符号自由。
    input wire i_local_valid, // 真实原生输入保持符号自由。
    input wire [2:0] i_local_kind, // 真实原生输入保持符号自由。
    input wire [15:0] i_local_rate, // 真实原生输入保持符号自由。
    input wire i_device_valid, // 真实原生输入保持符号自由。
    input wire [9:0] i_device_id, // 真实原生输入保持符号自由。
    input wire i_device_type, // 真实原生输入保持符号自由。
    input wire i_port_valid, // 真实原生输入保持符号自由。
    input wire [11:0] i_port, // 真实原生输入保持符号自由。
    input wire i_folding, // 真实原生输入保持符号自由。
    input wire i_tx_ready_advertised, // 真实原生输入保持符号自由。
    input wire i_symbols_valid, // 真实原生输入保持符号自由。
    input wire i_tx_limit_valid, // 真实原生输入保持符号自由。
    input wire [15:0] i_tx_limit, // 真实原生输入保持符号自由。
    input wire i_rx_valid, // 真实原生输入保持符号自由。
    input wire [31:0] i_rx_word, // 真实原生输入保持符号自由。
    input wire [3:0] i_source_take, // 真实原生输入保持符号自由。
    output wire [2:0] o_groups, // 分别报告参考状态界、全状态关系及公开输出。
    output wire o_violation // 完整关系的唯一归纳边界。
); // 结束证明接口。
    localparam [19:0] C_ALLOWED = (C_PERIOD_PS == 1) ? 20'd1000000 : ((C_PERIOD_PS == 640) ? 20'd1562 : ((C_PERIOD_PS == 6400) ? 20'd156 : ((C_PERIOD_PS == 1000000) ? 20'd1 : 20'd0))); // 独立字面表避免复用DUT时限除法。
    wire dut_local_ready; // 连接实际公开输出而不计算参考。
    wire dut_local_pending; // 连接实际公开输出而不计算参考。
    wire dut_local_waiting; // 连接实际公开输出而不计算参考。
    wire dut_remote_pending; // 连接实际公开输出而不计算参考。
    wire [3:0] dut_source_pending; // 连接实际公开输出而不计算参考。
    wire [127:0] dut_source_words; // 连接实际公开输出而不计算参考。
    wire dut_local_start; // 连接实际公开输出而不计算参考。
    wire dut_local_commit; // 连接实际公开输出而不计算参考。
    wire dut_local_done; // 连接实际公开输出而不计算参考。
    wire dut_reply_done; // 连接实际公开输出而不计算参考。
    wire dut_rx_request; // 连接实际公开输出而不计算参考。
    wire dut_rx_noop; // 连接实际公开输出而不计算参考。
    wire dut_rx_unhandled; // 连接实际公开输出而不计算参考。
    wire dut_rx_unsupported; // 连接实际公开输出而不计算参考。
    wire dut_rx_unmatched_ack; // 连接实际公开输出而不计算参考。
    wire dut_rx_overlap; // 连接实际公开输出而不计算参考。
    wire dut_peer_rate_valid; // 连接实际公开输出而不计算参考。
    wire [15:0] dut_peer_rate; // 连接实际公开输出而不计算参考。
    wire dut_peer_device_valid; // 连接实际公开输出而不计算参考。
    wire [1:0] dut_peer_device_type; // 连接实际公开输出而不计算参考。
    wire [9:0] dut_peer_device_id; // 连接实际公开输出而不计算参考。
    wire dut_peer_port_valid; // 连接实际公开输出而不计算参考。
    wire [11:0] dut_peer_port; // 连接实际公开输出而不计算参考。
    wire dut_peer_rate_update; // 连接实际公开输出而不计算参考。
    wire dut_deadline_miss; // 连接实际公开输出而不计算参考。
    wire dut_deadline_fault; // 连接实际公开输出而不计算参考。
    wire dut_protocol_fault; // 连接实际公开输出而不计算参考。
    wire dut_error; // 连接实际公开输出而不计算参考。
    (* keep *) wire [155:0] observed_state; // 只增加真实寄存器观察，绝不驱动DUT状态。
    wire [193:0] observed, expected; // 两侧均覆盖完整公开位宽。
    dl_basic_message_control #(.C_CLOCK_PERIOD_PS(C_PERIOD_PS)) DUT ( // 原始产品RTL完整实例。
        .i_clk(i_clk), // 原生连接不截断或替换输入。
        .i_rstn(i_rstn), // 原生连接不截断或替换输入。
        .i_local_valid(i_local_valid), // 原生连接不截断或替换输入。
        .i_local_kind(i_local_kind), // 原生连接不截断或替换输入。
        .i_local_rate(i_local_rate), // 原生连接不截断或替换输入。
        .i_device_valid(i_device_valid), // 原生连接不截断或替换输入。
        .i_device_id(i_device_id), // 原生连接不截断或替换输入。
        .i_device_type(i_device_type), // 原生连接不截断或替换输入。
        .i_port_valid(i_port_valid), // 原生连接不截断或替换输入。
        .i_port(i_port), // 原生连接不截断或替换输入。
        .i_folding(i_folding), // 原生连接不截断或替换输入。
        .i_tx_ready_advertised(i_tx_ready_advertised), // 原生连接不截断或替换输入。
        .i_symbols_valid(i_symbols_valid), // 原生连接不截断或替换输入。
        .i_tx_limit_valid(i_tx_limit_valid), // 原生连接不截断或替换输入。
        .i_tx_limit(i_tx_limit), // 原生连接不截断或替换输入。
        .i_rx_valid(i_rx_valid), // 原生连接不截断或替换输入。
        .i_rx_word(i_rx_word), // 原生连接不截断或替换输入。
        .i_source_take(i_source_take), // 原生连接不截断或替换输入。
        .o_local_ready(dut_local_ready), // 原生连接不截断或替换输入。
        .o_local_pending(dut_local_pending), // 原生连接不截断或替换输入。
        .o_local_waiting(dut_local_waiting), // 原生连接不截断或替换输入。
        .o_remote_pending(dut_remote_pending), // 原生连接不截断或替换输入。
        .o_source_pending(dut_source_pending), // 原生连接不截断或替换输入。
        .o_source_words(dut_source_words), // 原生连接不截断或替换输入。
        .o_local_start(dut_local_start), // 原生连接不截断或替换输入。
        .o_local_commit(dut_local_commit), // 原生连接不截断或替换输入。
        .o_local_done(dut_local_done), // 原生连接不截断或替换输入。
        .o_reply_done(dut_reply_done), // 原生连接不截断或替换输入。
        .o_rx_request(dut_rx_request), // 原生连接不截断或替换输入。
        .o_rx_noop(dut_rx_noop), // 原生连接不截断或替换输入。
        .o_rx_unhandled(dut_rx_unhandled), // 原生连接不截断或替换输入。
        .o_rx_unsupported(dut_rx_unsupported), // 原生连接不截断或替换输入。
        .o_rx_unmatched_ack(dut_rx_unmatched_ack), // 原生连接不截断或替换输入。
        .o_rx_overlap(dut_rx_overlap), // 原生连接不截断或替换输入。
        .o_peer_rate_valid(dut_peer_rate_valid), // 原生连接不截断或替换输入。
        .o_peer_rate(dut_peer_rate), // 原生连接不截断或替换输入。
        .o_peer_device_valid(dut_peer_device_valid), // 原生连接不截断或替换输入。
        .o_peer_device_type(dut_peer_device_type), // 原生连接不截断或替换输入。
        .o_peer_device_id(dut_peer_device_id), // 原生连接不截断或替换输入。
        .o_peer_port_valid(dut_peer_port_valid), // 原生连接不截断或替换输入。
        .o_peer_port(dut_peer_port), // 原生连接不截断或替换输入。
        .o_peer_rate_update(dut_peer_rate_update), // 原生连接不截断或替换输入。
        .o_deadline_miss(dut_deadline_miss), // 原生连接不截断或替换输入。
        .o_deadline_fault(dut_deadline_fault), // 原生连接不截断或替换输入。
        .o_protocol_fault(dut_protocol_fault), // 原生连接不截断或替换输入。
        .o_error(dut_error) // 原生连接不截断或替换输入。
    ); // 结束实际控制器实例。
    reg [1:0] ref_phase; // 本地零空闲、一排队、二等待的独立三阶段编码。
    reg [2:0] ref_local_type; // 历史本地消息类型。
    reg [15:0] ref_local_upper; // 仅保存线上高字段并独立重建报文。
    reg ref_remote; // 独立远端回复义务。
    reg [2:0] ref_remote_type; // 历史远端类型。
    reg [15:0] ref_reply_upper; // 接收沿冻结的本地回复身份。
    reg [15:0] ref_received_upper; // 每个已接纳请求的原始高字段。
    reg [1:0] ref_queue_count; // 规范化双项队列的当前项数。
    reg ref_head_local; // 当前全局最早排队项方向。
    reg ref_arrival_local_first; // 历史到达关系用来比较DUT保留的无效周期次序位。
    reg [19:0] ref_remaining; // 与DUT年龄相反的剩余预算计数。
    reg ref_missed; // 当前回复已报告过迟到。
    reg [1:0] ref_faults; // 协议与时限分别保持的粘滞诊断。
    reg ref_rate_valid; // 对端Rate学习历史。
    reg [15:0] ref_rate; // 学习的对端Rate字段。
    reg [15:0] ref_device; // 含有效位和原始类型的规范化身份包。
    reg [15:0] ref_port; // 含有效位的规范化端口包。
    wire exp_local_ready; // 完全由原生输入和独立参考历史计算。
    wire exp_local_pending; // 完全由原生输入和独立参考历史计算。
    wire exp_local_waiting; // 完全由原生输入和独立参考历史计算。
    wire exp_remote_pending; // 完全由原生输入和独立参考历史计算。
    wire [3:0] exp_source_pending; // 完全由原生输入和独立参考历史计算。
    wire [127:0] exp_source_words; // 完全由原生输入和独立参考历史计算。
    wire exp_local_start; // 完全由原生输入和独立参考历史计算。
    wire exp_local_commit; // 完全由原生输入和独立参考历史计算。
    wire exp_local_done; // 完全由原生输入和独立参考历史计算。
    wire exp_reply_done; // 完全由原生输入和独立参考历史计算。
    wire exp_rx_request; // 完全由原生输入和独立参考历史计算。
    wire exp_rx_noop; // 完全由原生输入和独立参考历史计算。
    wire exp_rx_unhandled; // 完全由原生输入和独立参考历史计算。
    wire exp_rx_unsupported; // 完全由原生输入和独立参考历史计算。
    wire exp_rx_unmatched_ack; // 完全由原生输入和独立参考历史计算。
    wire exp_rx_overlap; // 完全由原生输入和独立参考历史计算。
    wire exp_peer_rate_valid; // 完全由原生输入和独立参考历史计算。
    wire [15:0] exp_peer_rate; // 完全由原生输入和独立参考历史计算。
    wire exp_peer_device_valid; // 完全由原生输入和独立参考历史计算。
    wire [1:0] exp_peer_device_type; // 完全由原生输入和独立参考历史计算。
    wire [9:0] exp_peer_device_id; // 完全由原生输入和独立参考历史计算。
    wire exp_peer_port_valid; // 完全由原生输入和独立参考历史计算。
    wire [11:0] exp_peer_port; // 完全由原生输入和独立参考历史计算。
    wire exp_peer_rate_update; // 完全由原生输入和独立参考历史计算。
    wire exp_deadline_miss; // 完全由原生输入和独立参考历史计算。
    wire exp_deadline_fault; // 完全由原生输入和独立参考历史计算。
    wire exp_protocol_fault; // 完全由原生输入和独立参考历史计算。
    wire exp_error; // 完全由原生输入和独立参考历史计算。
    wire [15:0] incoming_upper; // 独立组合关系的显式位宽。
    wire [2:0] incoming_type; // 独立组合关系的显式位宽。
    wire incoming_valid; // 独立组合关系的显式位宽。
    wire incoming_ack; // 独立组合关系的显式位宽。
    wire known_type; // 独立组合关系的显式位宽。
    wire local_type_ok; // 独立组合关系的显式位宽。
    wire local_capable; // 独立组合关系的显式位宽。
    wire incoming_request; // 独立组合关系的显式位宽。
    wire local_eligible; // 独立组合关系的显式位宽。
    wire reply_eligible; // 独立组合关系的显式位宽。
    wire take_valid; // 独立组合关系的显式位宽。
    wire take_bad; // 独立组合关系的显式位宽。
    wire local_survives; // 独立组合关系的显式位宽。
    wire remote_survives; // 独立组合关系的显式位宽。
    wire learn_device; // 独立组合关系的显式位宽。
    wire learn_port; // 独立组合关系的显式位宽。
    wire [3:0] local_select; // 独立组合关系的显式位宽。
    wire [3:0] reply_select; // 独立组合关系的显式位宽。
    wire [31:0] local_packet; // 独立组合关系的显式位宽。
    wire [31:0] reply_packet; // 独立组合关系的显式位宽。
    wire [15:0] configured_device; // 独立组合关系的显式位宽。
    wire [15:0] configured_port; // 独立组合关系的显式位宽。
    wire [15:0] accepted_local_upper; // 独立组合关系的显式位宽。
    wire [15:0] accepted_reply_upper; // 独立组合关系的显式位宽。
    wire [15:0] incoming_device; // 独立组合关系的显式位宽。
    wire [15:0] incoming_port; // 独立组合关系的显式位宽。
    wire [19:0] age_from_remaining; // 独立组合关系的显式位宽。
    wire bounds_ok; // 独立组合关系的显式位宽。
    wire state_ok; // 独立组合关系的显式位宽。
    assign incoming_upper = i_rx_word[31:16]; // 显式十六位接收字段避免静态解析器将切片视为整个输入。
    assign incoming_type = i_rx_word[8:6]; // 已确认线上类型字段。
    assign known_type = (incoming_type == 3'd0) || (incoming_type == 3'd1) || (incoming_type >= 3'd4 && incoming_type <= 3'd6); // 目录包含NoOp与四类Basic事务。
    assign local_type_ok = (i_local_kind == 3'd1) || (i_local_kind >= 3'd4 && i_local_kind <= 3'd6); // 保留类型不得生成本地请求。
    assign local_capable = (i_local_kind != 3'd1) || (i_folding && i_tx_ready_advertised && i_symbols_valid); // TxReady的外部发送条件。
    assign incoming_valid = i_rstn && i_rx_valid && (i_rx_word[5:2] == 4'd0) && known_type && (incoming_type != 3'd0) && ((incoming_type != 3'd1) || i_folding); // 独立分类后才解释请求或确认。
    assign incoming_ack = incoming_valid && i_rx_word[12]; // 仅明确Ack位决定响应。
    assign incoming_request = incoming_valid && !i_rx_word[12]; // 请求携带独立远端义务。
    assign local_packet = {ref_local_upper, 7'd0, ref_local_type, 6'd0}; // 用类型与字段重建完整本地DWORD。
    assign reply_packet = (ref_remote_type == 3'd0) ? 32'd0 : {ref_reply_upper, 7'd8, ref_remote_type, 6'd0}; // 历史零类型对应复位零字，其余含Ack位。
    assign configured_device = {i_device_valid, 1'b0, i_device_type, 3'd0, (i_device_valid ? i_device_id : 10'd0)}; // 即使Valid为零，本地Type仍按已确认编码生成。
    assign configured_port = {i_port_valid, 3'd0, (i_port_valid ? i_port : 12'd0)}; // 未配置端口编号为零。
    assign accepted_local_upper = (i_local_kind == 3'd4) ? i_local_rate : ((i_local_kind == 3'd5) ? configured_device : ((i_local_kind == 3'd6) ? configured_port : 16'd0)); // 在接纳沿保存单独字段。
    assign accepted_reply_upper = (incoming_type == 3'd5) ? configured_device : ((incoming_type == 3'd6) ? configured_port : 16'd0); // Rate确认不回显请求高位。
    assign incoming_device = i_rx_word[31] ? (i_rx_word[31:16] & 16'he3ff) : 16'd0; // 保留原始Type但清除保留字段及无效身份。
    assign incoming_port = i_rx_word[31] ? (i_rx_word[31:16] & 16'h8fff) : 16'd0; // 端口有效位与十二位编号。
    assign local_eligible = i_rstn && (ref_phase == 2'd1) && (!ref_remote || (ref_local_type != ref_remote_type) || ref_head_local); // 不同类型可独立消费，相同类型依规范队首。
    assign reply_eligible = i_rstn && ref_remote && ((ref_phase != 2'd1) || (ref_local_type != ref_remote_type) || !ref_head_local) && ((ref_remote_type != 3'd4) || (i_tx_limit_valid && i_tx_limit <= ref_received_upper)); // 队首先行并满足已经实施的pacing。
    assign local_select[0] = local_eligible && (ref_local_type == 3'd1); // 固定来源号独立选择本地队首。
    assign reply_select[0] = reply_eligible && (ref_remote_type == 3'd1); // 固定来源号独立选择远端队首。
    assign exp_source_words[31:0] = local_select[0] ? local_packet : (reply_select[0] ? reply_packet : 32'd0); // 每来源明确选择完整字或零。
    assign local_select[1] = local_eligible && (ref_local_type == 3'd4); // 固定来源号独立选择本地队首。
    assign reply_select[1] = reply_eligible && (ref_remote_type == 3'd4); // 固定来源号独立选择远端队首。
    assign exp_source_words[63:32] = local_select[1] ? local_packet : (reply_select[1] ? reply_packet : 32'd0); // 每来源明确选择完整字或零。
    assign local_select[2] = local_eligible && (ref_local_type == 3'd5); // 固定来源号独立选择本地队首。
    assign reply_select[2] = reply_eligible && (ref_remote_type == 3'd5); // 固定来源号独立选择远端队首。
    assign exp_source_words[95:64] = local_select[2] ? local_packet : (reply_select[2] ? reply_packet : 32'd0); // 每来源明确选择完整字或零。
    assign local_select[3] = local_eligible && (ref_local_type == 3'd6); // 固定来源号独立选择本地队首。
    assign reply_select[3] = reply_eligible && (ref_remote_type == 3'd6); // 固定来源号独立选择远端队首。
    assign exp_source_words[127:96] = local_select[3] ? local_packet : (reply_select[3] ? reply_packet : 32'd0); // 每来源明确选择完整字或零。
    assign exp_source_pending = local_select | reply_select; // 每来源最多一个可提交队首。
    assign take_valid = ((i_source_take == 4'b0001) && exp_source_pending[0]) || ((i_source_take == 4'b0010) && exp_source_pending[1]) || ((i_source_take == 4'b0100) && exp_source_pending[2]) || ((i_source_take == 4'b1000) && exp_source_pending[3]); // 穷举四种合法物理消费，独立于DUT位算术检测。
    assign take_bad = (i_source_take != 4'd0) && !take_valid; // 非法非零消费不能触发任一方向提交。
    assign exp_local_ready = i_rstn && (ref_phase == 2'd0) && local_type_ok && local_capable; // 旧忙请求不能被同沿确认提前重用。
    assign exp_local_pending = i_rstn && (ref_phase != 2'd0); // 本地所有权跨发送保持。
    assign exp_local_waiting = i_rstn && (ref_phase == 2'd2); // 三阶段编码给出已发送等待。
    assign exp_remote_pending = i_rstn && ref_remote; // 两个方向具有独立所有权。
    assign exp_local_start = i_local_valid && exp_local_ready; // 真正接纳本地请求。
    assign exp_local_commit = take_valid && (|(i_source_take & local_select)); // 唯一实际本地提交。
    assign exp_reply_done = take_valid && (|(i_source_take & reply_select)); // 唯一实际远端回复。
    assign exp_local_done = incoming_ack && (ref_phase == 2'd2) && (incoming_type == ref_local_type); // 发送同沿的确认仍属于提前确认。
    assign exp_rx_request = incoming_request && (!ref_remote || exp_reply_done); // 可在旧回复真正出队沿接纳新请求。
    assign exp_rx_overlap = incoming_request && ref_remote && !exp_reply_done; // 未出队的旧回复不会被覆盖。
    assign exp_rx_unmatched_ack = incoming_ack && !exp_local_done; // 提前或异类确认只作诊断。
    assign exp_rx_noop = i_rstn && i_rx_valid && (i_rx_word[5:2] == 4'd0) && (incoming_type == 3'd0); // NoOp忽略所有高字段。
    assign exp_rx_unhandled = i_rstn && i_rx_valid && ((i_rx_word[5:2] != 4'd0) || !known_type); // 未覆盖类别及保留类型保留给上层。
    assign exp_rx_unsupported = i_rstn && i_rx_valid && (i_rx_word[5:2] == 4'd0) && (incoming_type == 3'd1) && !i_folding; // 没有Folding时不执行TxReady。
    assign exp_error = i_rstn && (take_bad || (i_local_valid && !local_type_ok) || exp_rx_unmatched_ack || exp_rx_overlap); // 非法事件与其它正确动作可以同沿存在。
    assign exp_peer_rate_update = exp_rx_request && (incoming_type == 3'd4); // 只由新请求学习Rate。
    assign learn_device = (exp_rx_request || exp_local_done) && (incoming_type == 3'd5); // 只有接纳请求或匹配确认学习身份。
    assign learn_port = (exp_rx_request || exp_local_done) && (incoming_type == 3'd6); // 端口学习与设备独立。
    assign exp_peer_rate_valid = i_rstn && ref_rate_valid; // 全局复位屏蔽观察。
    assign exp_peer_rate = exp_peer_rate_valid ? ref_rate : 16'd0; // 未学习Rate输出零。
    assign exp_peer_device_valid = i_rstn && ref_device[15]; // 独立身份包的有效位。
    assign exp_peer_device_type = exp_peer_device_valid ? ref_device[14:13] : 2'd0; // 原始类型观察不推广保留编码。
    assign exp_peer_device_id = exp_peer_device_valid ? ref_device[9:0] : 10'd0; // 独立身份包编号。
    assign exp_peer_port_valid = i_rstn && ref_port[15]; // 独立端口包有效位。
    assign exp_peer_port = exp_peer_port_valid ? ref_port[11:0] : 12'd0; // 独立端口包编号。
    assign exp_deadline_miss = i_rstn && ref_remote && !ref_missed && (ref_remaining == 20'd0); // 预算用尽后的采样沿首次迟到。
    assign exp_deadline_fault = i_rstn && ref_faults[0]; // 迟到不取消已保存回复。
    assign exp_protocol_fault = i_rstn && ref_faults[1]; // 诊断保持至全局复位。
    assign local_survives = (ref_phase == 2'd1) && !exp_local_commit; // 排队本地项提交后离开队列但保留事务所有权。
    assign remote_survives = ref_remote && !exp_reply_done; // 远端回复提交才离开队列。
    assign age_from_remaining = ref_remote ? (C_ALLOWED-ref_remaining) : 20'd0; // 从独立剩余预算映射回实际年龄位。
    always @(posedge i_clk) begin // 本地零空闲、一排队、二等待的独立三阶段编码。
        if (!i_rstn) ref_phase <= 2'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_local_start) ref_phase <= 2'd1; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_local_done) ref_phase <= 2'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_local_commit) ref_phase <= 2'd2; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 历史本地消息类型。
        if (!i_rstn) ref_local_type <= 3'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_local_start) ref_local_type <= i_local_kind; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 仅保存线上高字段并独立重建报文。
        if (!i_rstn) ref_local_upper <= 16'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_local_start) ref_local_upper <= accepted_local_upper; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 独立远端回复义务。
        if (!i_rstn) ref_remote <= 1'b0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_rx_request) ref_remote <= 1'b1; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_reply_done) ref_remote <= 1'b0; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 历史远端类型。
        if (!i_rstn) ref_remote_type <= 3'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_rx_request) ref_remote_type <= incoming_type; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 接收沿冻结的本地回复身份。
        if (!i_rstn) ref_reply_upper <= 16'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_rx_request) ref_reply_upper <= accepted_reply_upper; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 每个已接纳请求的原始高字段。
        if (!i_rstn) ref_received_upper <= 16'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_rx_request) ref_received_upper <= incoming_upper; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 规范化双项队列的当前项数。
        if (!i_rstn) ref_queue_count <= 2'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else ref_queue_count <= {1'b0, local_survives}+{1'b0, remote_survives}+{1'b0, exp_rx_request}+{1'b0, exp_local_start}; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 当前全局最早排队项方向。
        if (!i_rstn) ref_head_local <= 1'b0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (local_survives && remote_survives) ref_head_local <= ref_head_local; // 独立事件驱动参考历史，未出现事件时保持。
        else if (local_survives) ref_head_local <= 1'b1; // 独立事件驱动参考历史，未出现事件时保持。
        else if (remote_survives || exp_rx_request) ref_head_local <= 1'b0; // 独立事件驱动参考历史，未出现事件时保持。
        else ref_head_local <= exp_local_start; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 历史到达关系用来比较DUT保留的无效周期次序位。
        if (!i_rstn) ref_arrival_local_first <= 1'b0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_rx_request) ref_arrival_local_first <= local_survives; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_local_start) ref_arrival_local_first <= 1'b0; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 与DUT年龄相反的剩余预算计数。
        if (!i_rstn) ref_remaining <= 20'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_rx_request) ref_remaining <= C_ALLOWED; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_reply_done || !ref_remote) ref_remaining <= 20'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (ref_remaining != 20'd0) ref_remaining <= ref_remaining-20'd1; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 当前回复已报告过迟到。
        if (!i_rstn || exp_rx_request || exp_reply_done) ref_missed <= 1'b0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_deadline_miss) ref_missed <= 1'b1; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 协议与时限分别保持的粘滞诊断。
        if (!i_rstn) ref_faults <= 2'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else ref_faults <= ref_faults | {exp_error, exp_deadline_miss}; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 对端Rate学习历史。
        if (!i_rstn) ref_rate_valid <= 1'b0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_peer_rate_update) ref_rate_valid <= 1'b1; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 学习的对端Rate字段。
        if (!i_rstn) ref_rate <= 16'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (exp_peer_rate_update) ref_rate <= incoming_upper; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 含有效位和原始类型的规范化身份包。
        if (!i_rstn) ref_device <= 16'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (learn_device) ref_device <= incoming_device; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    always @(posedge i_clk) begin // 含有效位的规范化端口包。
        if (!i_rstn) ref_port <= 16'd0; // 独立事件驱动参考历史，未出现事件时保持。
        else if (learn_port) ref_port <= incoming_port; // 独立事件驱动参考历史，未出现事件时保持。
    end // 结束这一参考寄存器的更新。
    assign bounds_ok = (ref_phase <= 2'd2) && ((ref_local_type == 3'd0) || (ref_local_type == 3'd1) || (ref_local_type >= 3'd4 && ref_local_type <= 3'd6)) && ((ref_remote_type == 3'd0) || (ref_remote_type == 3'd1) || (ref_remote_type >= 3'd4 && ref_remote_type <= 3'd6)) && ((ref_phase == 2'd0) || (ref_local_type != 3'd0)) && (!ref_remote || (ref_remote_type != 3'd0)) && (ref_queue_count == ({1'b0, (ref_phase == 2'd1)}+{1'b0, ref_remote})) && ((ref_queue_count == 2'd2) || (ref_head_local == (ref_phase == 2'd1))) && ((ref_queue_count != 2'd2) || (ref_arrival_local_first == ref_head_local)) && (ref_remaining <= C_ALLOWED) && (ref_remote || ((ref_remaining == 20'd0) && !ref_missed)) && ((ref_device & 16'h1c00) == 16'd0) && (ref_device[15] || (ref_device == 16'd0)) && ((ref_port & 16'h7000) == 16'd0) && (ref_port[15] || (ref_port == 16'd0)); // 全部参考可达界与队列关系都是待证结论。
    assign state_ok = observed_state == {ref_port[11:0], ref_port[15], ref_device[9:0], ref_device[14:13], ref_device[15], ref_rate, ref_rate_valid, ref_faults[1], ref_faults[0], ref_missed, age_from_remaining, ref_arrival_local_first, ref_received_upper, reply_packet, ref_remote_type, ref_remote, local_packet, ref_local_type, (ref_phase == 2'd2), (ref_phase != 2'd0)}; // 完整156位真实状态逐一建立关系。
    assign observed = {dut_local_ready, dut_local_pending, dut_local_waiting, dut_remote_pending, dut_source_pending, dut_source_words, dut_local_start, dut_local_commit, dut_local_done, dut_reply_done, dut_rx_request, dut_rx_noop, dut_rx_unhandled, dut_rx_unsupported, dut_rx_unmatched_ack, dut_rx_overlap, dut_peer_rate_valid, dut_peer_rate, dut_peer_device_valid, dut_peer_device_type, dut_peer_device_id, dut_peer_port_valid, dut_peer_port, dut_peer_rate_update, dut_deadline_miss, dut_deadline_fault, dut_protocol_fault, dut_error}; // 按原生端口声明顺序绑定全部194输出位。
    assign expected = {exp_local_ready, exp_local_pending, exp_local_waiting, exp_remote_pending, exp_source_pending, exp_source_words, exp_local_start, exp_local_commit, exp_local_done, exp_reply_done, exp_rx_request, exp_rx_noop, exp_rx_unhandled, exp_rx_unsupported, exp_rx_unmatched_ack, exp_rx_overlap, exp_peer_rate_valid, exp_peer_rate, exp_peer_device_valid, exp_peer_device_type, exp_peer_device_id, exp_peer_port_valid, exp_peer_port, exp_peer_rate_update, exp_deadline_miss, exp_deadline_fault, exp_protocol_fault, exp_error}; // 按原生端口声明顺序绑定全部194输出位。
    assign o_groups = {observed != expected, !state_ok, !bounds_ok}; // 观察图审计核对三组实际关系的驱动。
    assign o_violation = |o_groups; // 归纳只假设前一沿此完整关系成立。
endmodule // 结束Basic独立完整状态参考。
