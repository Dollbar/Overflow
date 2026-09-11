// LLR receive event state for UALink 200G DL/PL 2.0.
// LLR接收事件状态；依据第二点六点四及第二点六点六点一至四节。
// 单时钟同步复位；无payload存储、CDC、CRC计算或发送watchdog。
module dl_replay_receiver ( // 声明独立接收状态模块。
    input wire i_clk, // 唯一接收状态时钟。
    input wire i_rstn, // 低有效同步复位；释放须满足本域时序。
    input wire i_link_reset, // 同步链路清除，优先于全部接收事件。
    input wire i_event_valid, // 当前沿存在一个已分类接收事件。
    input wire i_event_discard, // 该事件已由上游分类为存储丢弃，头和CRC不参与。
    input wire i_crc_ok, // 普通事件的外部CRC判决。
    input wire [23:0] i_header, // 完整二十四位逻辑LLR头，尚非线上串行位序。
    input wire [7:0] i_replay_limit, // 同域八位重发阈值，默认五十由外部CSR提供。
    output wire o_ingress_event, // 向其它接收消费者指示本沿实际事件。
    output wire o_accept, // 接受匹配的payload或NOP。
    output wire o_payload_accept, // 本沿允许提交payload到接收路径。
    output wire o_sequence_valid, // 诊断恢复序号有效，不代表顺序匹配。
    output wire [8:0] o_sequence, // 恢复的九位序号，无效时输出零。
    output wire o_replay_request, // 请求发送侧把剩余Replay Request数量设为三。
    output wire o_command_valid, // CRC和编码合法的ACK或Replay命令，不依赖payload接纳。
    output wire o_command_request, // 有效命令为Replay Request，否则为ACK。
    output wire [8:0] o_command_target, // 命令九位目标，无效时为零。
    output wire o_crc_error, // CRC错误或保留op的计数事件。
    output wire o_zero_sequence, // CRC正确但显式序号为零的日志事件。
    output wire o_zero_command, // CRC正确但命令目标为零的日志事件。
    output wire o_backpressure_drop, // 已分类存储丢弃的日志事件。
    output wire o_unexpected, // 可信恢复序号不符合预期。
    output wire o_ambiguous_drop, // 仅因模糊状态无法信任压缩序号。
    output wire o_replay_drop, // 重放状态下拒绝压缩序号。
    output wire [8:0] o_last_sequence, // 当前最后已接纳序号。
    output wire [2:0] o_bad_crc_count, // 当前三位饱和错误计数。
    output wire [7:0] o_unexpected_count, // 当前八位饱和重放异常计数。
    output wire o_ambiguous, // 当前压缩序号模糊状态。
    output wire o_replay // 当前接收重放状态。
); // 结束接口声明。
    reg [8:0] reg_last_sequence; // 最后已接纳的完整序号，零不可由正常可达状态产生。
    reg [2:0] cnt_bad_crc; // 三位饱和错误计数。
    reg [7:0] cnt_unexpected; // 八位饱和重放异常计数。
    reg reg_ambiguous; // 压缩序号是否不可置信。
    reg reg_replay; // 是否处于接收重放。
    wire flag_event; // 复位资格检查后的真实接收事件。
    wire flag_explicit; // 显式格式选择，不单独表明op合法。
    wire flag_command; // 命令格式选择。
    wire flag_op_valid; // op与payload组合合法。
    wire flag_storage; // 已分类存储丢弃。
    wire flag_invalid; // 普通事件CRC或op错误。
    wire flag_zero_sequence; // 普通CRC正确显式零序号。
    wire flag_zero_command; // 普通CRC正确命令零目标。
    wire flag_valid; // 普通CRC和字段均合法。
    wire flag_sequence_wrap; // 低三位跨界或同低位payload决定高六位进位。
    wire [5:0] dec_sequence_high_next; // 当前高六位预计算递增并在六位边界环回。
    wire [8:0] dec_sequence; // 九位加法截断实现模五百一十二恢复。
    wire [8:0] dec_expected; // 有效序号环的下一payload或当前NOP序号。
    wire flag_trusted; // 当前完整或可置信压缩序号。
    wire flag_accept; // 本沿接纳资格。
    wire flag_unexpected; // 本沿可信但非期望序号。
    wire flag_untrusted; // 本沿合法但压缩序号不可信。
    wire flag_start_replay; // 从非重放状态发起请求。
    wire flag_count_unexpected; // 已处重放时的实际异常事件。
    wire [2:0] cnt_bad_next; // 错误计数的饱和增量。
    wire [7:0] cnt_unexpected_next; // 重放异常计数的饱和增量。
    wire flag_retry; // 增量达到配置阈值时重新赋值三份请求。
    assign flag_event = i_rstn && !i_link_reset && i_event_valid; // 复位或无事件时所有提交脉冲为零。
    assign flag_explicit = (i_header[23:21] == 3'd0) || (i_header[23:21] == 3'd1); // 显式格式。
    assign flag_command = (i_header[23:21] == 3'd2) || (i_header[23:21] == 3'd3); // ACK或Replay Request。
    assign flag_op_valid = (i_header[23:21] == 3'd0) || ((i_header[23:21] == 3'd1) && i_header[20]) || flag_command; // NOP不能使用Replay op。
    assign flag_storage = flag_event && i_event_discard; // 上游已完成分类，不在本模块决定物理接纳优先级。
    assign flag_invalid = flag_event && !i_event_discard && (!i_crc_ok || !flag_op_valid); // 仅普通事件计CRC类错误。
    assign flag_zero_sequence = flag_event && !i_event_discard && i_crc_ok && flag_op_valid && flag_explicit && (i_header[16:8] == 9'd0); // CRC正确的零序号单列日志。
    assign flag_zero_command = flag_event && !i_event_discard && i_crc_ok && flag_command && (i_header[19:11] == 9'd0); // CRC正确的零命令目标单列日志。
    assign flag_valid = flag_event && !i_event_discard && i_crc_ok && flag_op_valid && (flag_explicit ? (i_header[16:8] != 9'd0) : (i_header[19:11] != 9'd0)); // 保留位按规范忽略。
    assign flag_sequence_wrap = (i_header[10:8] < reg_last_sequence[2:0]) || (i_header[20] && (i_header[10:8] == reg_last_sequence[2:0])); // 编码恢复进位不依赖完整九位加法。
    assign dec_sequence_high_next = reg_last_sequence[8:3] + 6'd1; // 高位递增由当前寄存状态预计算。
    assign dec_sequence = flag_explicit ? i_header[16:8] : {(flag_sequence_wrap ? dec_sequence_high_next : reg_last_sequence[8:3]), i_header[10:8]}; // 低位直接使用收到字段，高位独立选择，仍为模五百一十二。
    assign dec_expected = i_header[20] ? ((reg_last_sequence == 9'd511) ? 9'd1 : reg_last_sequence + 9'd1) : reg_last_sequence; // payload跳过零，NOP不消耗序号。
    assign flag_trusted = flag_explicit || (!reg_ambiguous && !reg_replay); // 两个状态均清除才信任压缩序号。
    assign flag_accept = flag_valid && flag_trusted && (flag_explicit ? (i_header[16:8] == dec_expected) : (i_header[10:8] == dec_expected[2:0])); // 显式比较完整期望，压缩比较期望低位；完整序号仍由恢复路径给出。
    assign flag_unexpected = flag_valid && flag_trusted && !flag_accept; // 不改变最后已接纳序号。
    assign flag_untrusted = flag_valid && !flag_trusted; // 仍允许独立命令消费者处理命令。
    assign flag_start_replay = flag_unexpected && !reg_replay; // 首次异常进入重放并请求三个副本。
    assign flag_count_unexpected = reg_replay && (flag_storage || flag_invalid || (flag_valid && !flag_accept)); // 无事件和零字段日志不推进异常计数。
    assign cnt_bad_next = (cnt_bad_crc == 3'd7) ? 3'd7 : cnt_bad_crc + 3'd1; // 三位计数饱和不环回。
    assign cnt_unexpected_next = (cnt_unexpected == 8'd255) ? 8'd255 : cnt_unexpected + 8'd1; // 八位计数饱和不环回。
    assign flag_retry = flag_count_unexpected && (cnt_unexpected_next >= i_replay_limit); // 阈值零仍需真实异常事件才触发。
    always @(posedge i_clk) begin // 最后接纳序号独立寄存。
        if (!i_rstn) reg_last_sequence <= 9'd511; // 同步初始化为有效环末尾。
        else if (i_link_reset) reg_last_sequence <= 9'd511; // 同步链路清除使用相同初值。
        else if (flag_accept) reg_last_sequence <= dec_sequence; // 仅接纳更新，异常保持。
    end // 结束序号寄存。
    always @(posedge i_clk) begin // 坏CRC类计数独立寄存。
        if (!i_rstn) cnt_bad_crc <= 3'd0; // 同步复位。
        else if (i_link_reset) cnt_bad_crc <= 3'd0; // 同步链路清除使用相同初值。
        else if (flag_accept) cnt_bad_crc <= 3'd0; // 匹配payload或NOP恢复计数。
        else if (flag_storage || flag_invalid) cnt_bad_crc <= cnt_bad_next; // 已分类丢弃或无效事件增量。
    end // 结束错误计数。
    always @(posedge i_clk) begin // 重放异常计数独立寄存。
        if (!i_rstn) cnt_unexpected <= 8'd0; // 同步复位。
        else if (i_link_reset) cnt_unexpected <= 8'd0; // 同步链路清除使用相同初值。
        else if (flag_accept || flag_start_replay || flag_retry) cnt_unexpected <= 8'd0; // 恢复或请求触发后清零。
        else if (flag_count_unexpected) cnt_unexpected <= cnt_unexpected_next; // 只按真实异常接收事件增加。
    end // 结束重放异常计数。
    always @(posedge i_clk) begin // 模糊状态独立寄存。
        if (!i_rstn) reg_ambiguous <= 1'b0; // 同步复位。
        else if (i_link_reset) reg_ambiguous <= 1'b0; // 同步链路清除使用相同初值。
        else if (flag_accept) reg_ambiguous <= 1'b0; // 匹配可置信序号恢复。
        else if ((flag_storage || flag_invalid) && (cnt_bad_next == 3'd7)) reg_ambiguous <= 1'b1; // 第七个错误及之后置位。
    end // 结束模糊状态。
    always @(posedge i_clk) begin // 接收重放状态独立寄存。
        if (!i_rstn) reg_replay <= 1'b0; // 同步复位。
        else if (i_link_reset) reg_replay <= 1'b0; // 同步链路清除使用相同初值。
        else if (flag_accept) reg_replay <= 1'b0; // 匹配payload或NOP退出。
        else if (flag_start_replay) reg_replay <= 1'b1; // 首次可信异常进入。
    end // 结束重放状态。
    assign o_ingress_event = flag_event; // 向独立ACK处理器提供所有入站事件。
    assign o_accept = flag_accept; // 匹配的NOP或payload。
    assign o_payload_accept = flag_accept && i_header[20]; // 接收内容写入资格。
    assign o_sequence_valid = flag_valid; // 序号诊断不等同于接纳。
    assign o_sequence = flag_valid ? dec_sequence : 9'd0; // 无效事件清零诊断总线。
    assign o_replay_request = flag_start_replay || flag_retry; // 向发送侧请求计数赋值三。
    assign o_command_valid = flag_valid && flag_command; // 命令不以payload接纳为前提。
    assign o_command_request = flag_valid && (i_header[23:21] == 3'd3); // 有效Replay Request命令类别。
    assign o_command_target = (flag_valid && flag_command) ? i_header[19:11] : 9'd0; // 有效命令目标。
    assign o_crc_error = flag_invalid; // CRC及保留op日志事件。
    assign o_zero_sequence = flag_zero_sequence; // 显式零序号日志事件。
    assign o_zero_command = flag_zero_command; // 命令零目标日志事件。
    assign o_backpressure_drop = flag_storage; // 上游已分类的存储丢弃事件。
    assign o_unexpected = flag_unexpected; // 可信恢复序号非预期。
    assign o_ambiguous_drop = flag_untrusted && !reg_replay; // 仅模糊不能自行发起重放。
    assign o_replay_drop = flag_untrusted && reg_replay; // 重放时不信任压缩序号。
    assign o_last_sequence = reg_last_sequence; // 当前已接纳序号直接观察。
    assign o_bad_crc_count = cnt_bad_crc; // 当前饱和错误计数直接观察。
    assign o_unexpected_count = cnt_unexpected; // 当前重放异常计数直接观察。
    assign o_ambiguous = reg_ambiguous; // 当前模糊状态直接观察。
    assign o_replay = reg_replay; // 当前接收重放状态直接观察。
endmodule // 结束LLR接收事件有限状态模块。
