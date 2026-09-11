// UART 来源完整归纳：以独立移位队列验证固定暂存槽的全部有效数据。
`timescale 1ps/1ps // 形式验证使用统一单位，不含仿真延时。
module uart_tx_properties ( // UART 来源完整状态、数据与事件的形式验证模块。
    input wire i_clk, // DUT 与独立参考状态的共同正沿时钟。
    input wire i_rstn, // 自由变化的同步低有效复位。
    input wire i_channel4_enabled, // 任意通道使能，包含活动期间关闭的故障输入。
    input wire [11:0] i_payload_fill, // 全部十二位 FIFO 占用输入均不作合法流量假设。
    input wire i_payload_valid, // 任意 FIFO 队首有效及无限停顿。
    input wire [31:0] i_payload_word, // 所有 payload 数据位均为自由符号输入。
    input wire i_credit_valid, // 任意解码信用更新事件。
    input wire [11:0] i_credit_value, // 任意绝对信用值及环回。
    input wire i_source_take, // 包含未 pending 消费负例的自由输入。
    output wire [4:0] o_groups, // 五组完整性质，必须共同参与归纳。
    output wire o_violation // 任何状态、数据或公开事件关系失败均置位。
); // 结束 UART 来源完整归纳的自由输入接口。
    reg [5:0] ref_total; // 独立捕获的当前整条消息 payload 数量，零表示空闲。
    reg [5:0] ref_to_load; // 还需实际接收的 FIFO payload 数量。
    reg [5:0] ref_held; // 移位队列中真实尚未发送的 payload 字数。
    reg ref_header_sent; // 头已送出，独立于 DUT 的消息索引寄存器。
    reg [11:0] ref_tx; // 独立完整消息退休计数。
    reg [11:0] ref_fc; // 独立保存最近更新，不从 DUT 计数反馈。
    wire [49:0] observed_state; // 由脚本连接到全部真实控制寄存器，不作为自由输入。
    wire [1023:0] observed_payload; // 由脚本连接到三十二个真实暂存字的固定总线。
    wire [1023:0] ref_queue, shifted_actual; // 独立队列顺序及根据已消费量移动的实际固定槽。
    wire [31:0] mismatched_words; // 每个真实仍持有的参考字都要比较全部三十二位。
    wire actual_ready, actual_pending, actual_busy, actual_done, actual_error; // 真实公开的资格、完成与故障输出。
    wire [31:0] actual_word; // 真实当前头或 payload。
    wire [5:0] actual_total, actual_index, actual_reserved, actual_held; // 真实消息长度及两种占用。
    wire [11:0] actual_tx, actual_fc; // 真实公开信用状态。
    wire ref_busy, ref_ready, ref_pending, ref_capture, ref_load, ref_take, ref_pop, ref_done; // 全部事件仅由独立参考状态和自由输入生成。
    wire [12:0] ref_difference; // 扩展差值明确包含模数，不复用 DUT 的窄减法连线。
    wire [11:0] ref_available; // 扩展模减法的低十二位。
    wire [5:0] ref_capture_count, ref_loaded, ref_consumed, ref_index; // 独立长度、已捕获、已发 payload 及消息索引。
    wire [6:0] load_plus_held; // 扩展和避免状态边界被六位溢出掩盖。
    wire [31:0] ref_header_word, ref_word; // 独立构造的标准头和队首 payload。
    wire ref_error, bounds_ok, state_ok; // 参考故障语义以及完整状态不变量。
    genvar gen_word; // 固定三十二个独立移位队列字。
    dl_uart_tx_source Source_Inst ( // 真实产品 RTL 的所有接口都被纳入证明。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_channel4_enabled(i_channel4_enabled), // 全部复位及通道轨迹保持自由。
        .i_payload_fill(i_payload_fill), .i_payload_valid(i_payload_valid), .i_payload_word(i_payload_word), // 任意 FIFO 输入及数据字。
        .i_credit_valid(i_credit_valid), .i_credit_value(i_credit_value), .i_source_take(i_source_take), // 任意信用及服务事件。
        .o_payload_ready(actual_ready), .o_source_pending(actual_pending), .o_word(actual_word), // 真实数据和上下游资格。
        .o_word_count(actual_total), .o_word_index(actual_index), .o_busy(actual_busy), // 真实消息与所有权观察。
        .o_reserved_words(actual_reserved), .o_staged_words(actual_held), // 信用预约和实际数据持有量均比较。
        .o_tx_counter(actual_tx), .o_latest_fc(actual_fc), .o_message_done(actual_done), .o_error(actual_error) // 所有公开状态与事件参与证明。
    ); // 结束真实 DUT 实例。
    assign ref_busy = ref_total != 6'd0; // 参考所有权由剩余消息记录派生。
    assign ref_difference = {1'b0, ref_fc}+13'd4096-{1'b0, ref_tx}; // 无符号扩展差值在一整个额外模空间内计算。
    assign ref_available = ref_difference[11:0]; // 对扩展差值取规定的模四千零九十六余数。
    assign ref_capture_count = ((i_payload_fill <= 12'd32) && (i_payload_fill <= ref_available)) ? i_payload_fill[5:0] : (((ref_available <= 12'd32) && (ref_available < i_payload_fill)) ? ref_available[5:0] : 6'd32); // 独立选择哪个约束成为最小值，不读取 DUT 预约数量。
    assign ref_capture = i_rstn && i_channel4_enabled && !ref_busy && (i_payload_fill != 12'd0) && (ref_available != 12'd0); // 空闲正信用与实际填充共同产生参考预约。
    assign ref_ready = i_rstn && i_channel4_enabled && (ref_to_load != 6'd0); // 只要仍欠捕获字就允许实际 FIFO 传递。
    assign ref_pending = i_rstn && i_channel4_enabled && ref_busy && (ref_to_load == 6'd0); // 独立参考只有全部字到齐后才提供来源。
    assign ref_load = ref_ready && i_payload_valid; // 只跟随独立接收资格更新移位队列。
    assign ref_take = ref_pending && i_source_take; // 未就绪的非法 take 不成为参考消费。
    assign ref_pop = ref_take && ref_header_sent; // 头不会从 payload 队列移除任何字。
    assign ref_done = ref_pop && (ref_held == 6'd1); // 队列最后一个 payload 消耗才退休整条消息。
    assign ref_loaded = ref_total-ref_to_load; // 由独立总长和欠加载量得到已捕获数量。
    assign ref_consumed = ref_loaded-ref_held; // 从已捕获量与队列长度推导真实已发 payload 数量。
    assign ref_index = ref_header_sent ? ref_consumed+6'd1 : 6'd0; // 已发头后当前索引为已发 payload 加一。
    assign load_plus_held = {1'b0, ref_to_load}+{1'b0, ref_held}; // 填充期的守恒关系使用扩展位宽。
    assign ref_header_word = (({26'd0, ref_total}-32'd1) << 27) | 32'h00000004; // 独立按规范位位置构造完整 stream0 头。
    assign ref_word = ref_pending ? (ref_header_sent ? ref_queue[31:0] : ref_header_word) : 32'd0; // 发送数据只取独立队列头，不索引 DUT 暂存。
    assign ref_error = i_rstn && ((i_source_take && !ref_pending) || (!i_channel4_enabled && ref_header_sent)); // 非法消费和活动关闭的独立诊断语义。
    assign shifted_actual = observed_payload >> (ref_consumed*32); // 把 DUT 已发送固定前缀移走，与真实剩余队列逐字比较。
    generate // 全部三十二字的数据关系参与同一次完整归纳。
        for (gen_word = 0; gen_word < 32; gen_word = gen_word+1) begin : gen_queue // 参考队列在每次 payload 消费时整体左移队首。
            localparam [5:0] C_WORD = gen_word[5:0]; // 固定队列位置。
            reg [31:0] ref_word_reg; // 当前独立参考队列位置的数据寄存器。
            wire [31:0] next_word; // 消费后由下一队列位置移来的数据。
            assign ref_queue[gen_word*32 +: 32] = ref_word_reg; // 队列零位置位于最低 DWORD。
            if (gen_word < 31) begin : gen_next // 末位置之外都从下一位置移入数据。
                assign next_word = ref_queue[(gen_word+1)*32 +: 32]; // 固定连线移位，不跟随 DUT 可变读地址。
            end else begin : gen_last // 末位置消费后填零，不制造有效新字。
                assign next_word = 32'd0; // 空闲尾部不参与有效字数据不变量。
            end // 结束固定队列后继选择。
            assign mismatched_words[gen_word] = (C_WORD < ref_held) && (ref_word_reg != shifted_actual[gen_word*32 +: 32]); // 每个仍持有的字都检查，未使用槽没有任意数据假设。
            always @(posedge i_clk) begin // 每个参考队列字独立保存，只使用参考握手事件。
                if (!i_rstn) ref_word_reg <= 32'd0; // 同步复位清除参考数据。
                else if (ref_pop) ref_word_reg <= next_word; // 实际参考 payload 消费后整体移动剩余队列。
                else if (ref_load && (ref_held == C_WORD)) ref_word_reg <= i_payload_word; // 真实接收字追加到独立队列尾部。
            end // 结束独立参考字的唯一时序驱动。
        end // 结束完整参考队列与逐字数据关系。
    endgenerate // 结束全部有效数据不变量展开。
    assign bounds_ok = (ref_total <= 6'd32) && (ref_to_load <= ref_total) && (ref_held <= ref_total) && (ref_consumed <= 6'd31) && (!ref_busy ? ((ref_to_load == 6'd0) && (ref_held == 6'd0) && !ref_header_sent) : ((ref_to_load != 6'd0) ? (!ref_header_sent && (load_plus_held == {1'b0, ref_total})) : ((ref_held != 6'd0) && (ref_header_sent || (ref_held == ref_total))))); // 状态界与阶段守恒本身是要证明的结论，不能作为外加假设。
    assign state_ok = observed_state == {ref_fc, ref_tx, ref_held, ref_index, ref_loaded, ref_total, (ref_busy && (ref_to_load == 6'd0)), ref_busy}; // 全部真实控制状态同时对应独立参考，不留下自由状态切口。
    assign o_groups[0] = !bounds_ok || !state_ok; // 完整参考状态范围与真实 DUT 控制关系。
    assign o_groups[1] = {actual_ready, actual_pending, actual_total, actual_index, actual_busy, actual_reserved, actual_held, actual_tx, actual_fc, actual_done, actual_error} != {ref_ready, ref_pending, (ref_pending ? ref_total+6'd1 : 6'd0), (ref_pending ? ref_index : 6'd0), (i_rstn && ref_busy), (i_rstn ? ref_total : 6'd0), (i_rstn ? ref_held : 6'd0), (i_rstn ? ref_tx : 12'd0), (i_rstn ? ref_fc : 12'd0), ref_done, ref_error}; // 独立比较全部公开控制、状态及诊断位。
    assign o_groups[2] = actual_word != ref_word; // 无效输出和每个头/payload 数据位都必须相等。
    assign o_groups[3] = |mismatched_words; // 不只证明当前输出字，也证明所有尚未输出的真实暂存内容。
    assign o_groups[4] = (actual_ready && actual_pending) || (actual_done && (!actual_pending || !i_source_take || (actual_index == 6'd0))) || (actual_held > actual_reserved) || (actual_reserved > 6'd32); // 附加检查阶段互斥、末字消费和有界所有权。
    assign o_violation = |o_groups; // 五组完整性质共同成为前一步假设和下一步结论。
    always @(posedge i_clk) begin // 保存独立消息总长，只有预约和末字退休改变它。
        if (!i_rstn) ref_total <= 6'd0; // 同步复位清除参考预约。
        else if (ref_done) ref_total <= 6'd0; // 最后一个参考 payload 释放整条消息。
        else if (ref_capture) ref_total <= ref_capture_count; // 依据沿前信用与填充独立捕获数量。
    end // 结束独立总长寄存器。
    always @(posedge i_clk) begin // 欠加载量递减，避免复用 DUT 的写入计数更新。
        if (!i_rstn) ref_to_load <= 6'd0; // 复位不再等待任何旧 FIFO 字。
        else if (ref_capture) ref_to_load <= ref_capture_count; // 新消息最初欠全部 payload。
        else if (ref_load) ref_to_load <= ref_to_load-6'd1; // 只在实际参考 FIFO 捕获时减一。
    end // 结束参考欠加载量寄存器。
    always @(posedge i_clk) begin // 队列长度跟随参考真实接收和 payload 消费。
        if (!i_rstn) ref_held <= 6'd0; // 同步复位清空逻辑队列。
        else if (ref_load) ref_held <= ref_held+6'd1; // 接收一个字增加队列长度。
        else if (ref_pop) ref_held <= ref_held-6'd1; // payload 消费减一，头不会进入本分支。
    end // 结束独立参考队列长度。
    always @(posedge i_clk) begin // 单独保存头是否已经发出。
        if (!i_rstn) ref_header_sent <= 1'b0; // 复位没有活动头。
        else if (ref_done) ref_header_sent <= 1'b0; // 末 payload 后准备下一条消息头。
        else if (ref_take && !ref_header_sent) ref_header_sent <= 1'b1; // 仅参考头服务建立 payload 阶段。
    end // 结束独立参考头阶段寄存器。
    always @(posedge i_clk) begin // 独立发送信用按完整参考消息更新。
        if (!i_rstn) ref_tx <= 12'd0; // 初始累计发送 payload 为零。
        else if (ref_done) ref_tx <= ref_tx+{6'd0, ref_total}; // 头不计入已完成消息信用。
    end // 结束独立参考发送信用计数。
    always @(posedge i_clk) begin // 独立最近信用只记录输入更新。
        if (!i_rstn) ref_fc <= 12'd0; // 复位后没有对端信用。
        else if (i_credit_valid) ref_fc <= i_credit_value; // 更新替换绝对值，重复不累加。
    end // 结束独立参考信用寄存器。
endmodule // 结束完整 UART 来源状态与真实数据归纳模块。
