// DL 消息仲裁形式性质：以最后完成来源和剩余字数建立独立状态模型。
`timescale 1ps/1ps // 保持统一时间单位，形式模型不包含任何延时。
module dl_message_properties ( // DL 消息仲裁器的完整事件与状态归纳验证模块。
    input wire i_clk, // DUT 与独立参考状态共用一个正沿采样时钟。
    input wire i_rstn, // 任意变化的同步低有效复位，不假设初始寄存值。
    input wire i_segment_available, // 任意服务机会，包含任意长度停顿。
    input wire [10:0] i_source_pending, // 全部十一来源均为自由输入，允许资格撤回负例。
    input wire [351:0] i_source_words, // 每个来源的全部三十二位数据均独立符号化。
    input wire [5:0] i_uart_word_count, // 包含零、一及超过三十三的非法长度。
    output wire [5:0] o_groups, // 六组不变量结论，归纳不能只证明其中一组。
    output wire o_violation // 全部状态关系和输出检查的并集。
); // 结束完整符号化形式接口。
    reg [1:0] ref_group_last; // 最后完成的组，复位使用 UART 使下一个起点为 Basic。
    reg [2:0] ref_basic_last; // 最后完成的 Basic 相对编号，而非 DUT 下一游标。
    reg ref_control_last; // 最后完成的 Control 相对编号。
    reg [1:0] ref_uart_last; // 最后完成的 UART 相对编号。
    reg [5:0] ref_remaining; // 当前 UART 还未消费的字数，零表示没有所有权。
    reg [5:0] ref_sent; // 当前 UART 已消费字数，用于检查公开的下一字索引。
    wire [20:0] observed_state; // 脚本只绑定到真实 DUT 寄存输出，不作为输入或状态替代。
    wire actual_valid, actual_last, actual_error, actual_locked; // 实际完整控制输出。
    wire [31:0] actual_word; // 实际发出的三十二位数据。
    wire [3:0] actual_source; // 实际本地来源编号。
    wire [5:0] actual_index, actual_uart_index; // 实际当前字及外部存储读地址。
    wire [10:0] actual_take, actual_done; // 实际逐来源消费与整消息完成事件。
    wire [10:0] eligible, winner, ref_take, ref_done; // 独立距离比较的候选、赢家及参考事件。
    wire [7:0] rank [0:10]; // 组距离在高位、组内距离在低位的字典序键。
    wire [3:0] source_term [0:10]; // 通过参考消费独热向量选择来源编号。
    wire [31:0] word_term [0:10]; // 每个来源的数据按独立参考消费掩码参与归约。
    wire ref_active, ref_valid, ref_last_word, ref_error; // 参考剩余计数派生的控制语义。
    wire [3:0] ref_source; // 从全部独立赢家事件组合得到的来源。
    wire [31:0] ref_word; // 每来源逐位掩码归约得到的期望 DWORD。
    wire [5:0] ref_event_index, ref_uart_index; // 当前事件和外部读地址的独立预期。
    wire [6:0] ref_total; // 扩展加法验证已发加未发长度，防止六位回绕掩盖越界。
    wire [1:0] next_group, next_uart; // 将最后完成编号转换为 DUT 下一起点以建立状态关系。
    wire [2:0] next_basic; // Basic 五项的下一起点关系。
    wire [3:0] take_count; // 精确四位和验证十一事件最多有一个，不使用下溢位技巧。
    wire flag_reference_bounds, flag_state_relation; // 状态合法性及真实 DUT 与独立模型的关系。
    genvar gen_source, gen_peer; // 固定十一源两两比较，不复用 DUT 的 case 仲裁代码。
    dl_message_arbiter Arbiter_Inst ( // 真实产品实例的全部输入保持自由符号值。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_segment_available(i_segment_available), // 唯一采样时钟和全部复位/服务轨迹。
        .i_source_pending(i_source_pending), .i_source_words(i_source_words), .i_uart_word_count(i_uart_word_count), // 保留所有正常及负例输入。
        .o_valid(actual_valid), .o_word(actual_word), .o_source(actual_source), .o_word_index(actual_index), .o_last(actual_last), // 全部服务数据与边界。
        .o_source_take(actual_take), .o_message_done(actual_done), .o_error(actual_error), // 全部消费、完成和错误观察。
        .o_locked(actual_locked), .o_uart_word_index(actual_uart_index) // 连续 UART 所有权及公开读地址。
    ); // 结束真实产品实例。
    assign ref_active = (ref_remaining != 6'd0); // 参考模型用剩余字数而非单独锁定位保存消息所有权。
    generate // 为每个来源独立构造循环距离和两两优先关系。
        for (gen_source = 0; gen_source < 11; gen_source = gen_source+1) begin : gen_sources // 十一类合法来源的固定集合。
            localparam [3:0] C_SOURCE = gen_source[3:0]; // 固定本地来源编号。
            localparam [3:0] C_GROUP = (gen_source < 5) ? 4'd0 : (gen_source < 7) ? 4'd1 : 4'd2; // 字面来源集合对应三个消息组。
            localparam [3:0] C_LOCAL = (gen_source < 5) ? C_SOURCE : (gen_source < 7) ? C_SOURCE-4'd5 : C_SOURCE-4'd7; // 各组来源的相对编号。
            localparam [3:0] C_SIZE = (gen_source < 5) ? 4'd5 : (gen_source < 7) ? 4'd2 : 4'd4; // 三个组的固定来源数量。
            wire [3:0] local_last, group_distance, local_distance; // 扩展到四位的最后完成编号及循环距离。
            wire [10:0] outranked; // 每个竞争来源是否比本来源距离更小。
            assign local_last = (gen_source < 5) ? {1'b0, ref_basic_last} : (gen_source < 7) ? {3'b000, ref_control_last} : {2'b00, ref_uart_last}; // 使用参考历史而非读取 DUT 游标。
            assign group_distance = (C_GROUP > {2'b00, ref_group_last}) ? C_GROUP-{2'b00, ref_group_last} : 4'd3+C_GROUP-{2'b00, ref_group_last}; // 刚完成的组距离最大，下一个组距离最小。
            assign local_distance = (C_LOCAL > local_last) ? C_LOCAL-local_last : C_SIZE+C_LOCAL-local_last; // 刚完成来源排在同组所有其它来源之后。
            assign rank[gen_source] = {group_distance, local_distance}; // 字典序先比较组，再比较组内来源，不能退化为平面来源环。
            assign eligible[gen_source] = i_source_pending[gen_source] && ((gen_source != 7) || ((i_uart_word_count >= 6'd2) && (i_uart_word_count <= 6'd33))); // 空闲 UART 非法长度不参与竞争。
            for (gen_peer = 0; gen_peer < 11; gen_peer = gen_peer+1) begin : gen_peers // 对全部候选建立严格的小于关系。
                assign outranked[gen_peer] = eligible[gen_peer] && (rank[gen_peer] < rank[gen_source]); // 任一更近的可用来源都会否决当前来源。
            end // 结束一个来源的全部竞争比较。
            assign winner[gen_source] = eligible[gen_source] && !(|outranked); // 只有最小字典距离的可用来源成为空闲仲裁赢家。
            assign ref_take[gen_source] = i_rstn && i_segment_available && (ref_active ? ((gen_source == 7) && i_source_pending[7]) : winner[gen_source]); // 活动消息期间不再执行任何新来源仲裁。
            assign ref_done[gen_source] = ref_take[gen_source] && ref_last_word; // 只有实际服务的末字可以移除完整消息。
            assign source_term[gen_source] = ref_take[gen_source] ? C_SOURCE : 4'd0; // 用独立事件直接构造期望来源。
            assign word_term[gen_source] = i_source_words[gen_source*32 +: 32] & {32{ref_take[gen_source]}}; // 每个自由数据位都参与对应的有效输出检查。
        end // 结束十一来源参考关系展开。
    endgenerate // 结束完整来源集合的距离选择结构。
    assign ref_valid = |ref_take; // 至少一个参考消费事件才有输出有效。
    assign ref_last_word = ref_valid && (ref_active ? (ref_remaining == 6'd1) : !ref_take[7]); // UART 以剩余一字判断结束，其余消息每字结束。
    assign ref_source = source_term[0] | source_term[1] | source_term[2] | source_term[3] | source_term[4] | source_term[5] | source_term[6] | source_term[7] | source_term[8] | source_term[9] | source_term[10]; // 独热归约覆盖每一合法来源。
    assign ref_word = word_term[0] | word_term[1] | word_term[2] | word_term[3] | word_term[4] | word_term[5] | word_term[6] | word_term[7] | word_term[8] | word_term[9] | word_term[10]; // 与 DUT 可变索引 mux 不同的逐位参考结构。
    assign ref_error = i_rstn && (ref_active ? !i_source_pending[7] : (i_source_pending[7] && ((i_uart_word_count < 6'd2) || (i_uart_word_count > 6'd33)))); // 即使没有 segment，接口违约仍需诊断。
    assign ref_event_index = (ref_valid && ref_active) ? ref_sent : 6'd0; // 首字及所有无效事件的索引为零。
    assign ref_uart_index = (i_rstn && ref_active) ? ref_sent : 6'd0; // 外部读地址只在公开活动消息中有效。
    assign ref_total = {1'b0, ref_sent}+{1'b0, ref_remaining}; // 七位和覆盖最大可能的非法六位状态，归纳不靠回绕压低总长。
    assign next_group = (ref_group_last == 2'd2) ? 2'd0 : ref_group_last+2'd1; // 独立模型记录最后赢家，DUT 记录下一起点。
    assign next_basic = (ref_basic_last == 3'd4) ? 3'd0 : ref_basic_last+3'd1; // 五来源的合法回绕关系。
    assign next_uart = (ref_uart_last == 2'd3) ? 2'd0 : ref_uart_last+2'd1; // 四来源的合法回绕关系。
    assign flag_reference_bounds = (ref_group_last <= 2'd2) && (ref_basic_last <= 3'd4) && (ref_remaining <= 6'd32) && (ref_active ? ((ref_sent >= 6'd1) && (ref_total <= 7'd33)) : (ref_sent == 6'd0)); // 状态边界自身参与 reset 和归纳结论，不能直接假设。
    assign flag_state_relation = (observed_state[1:0] == next_group) && (observed_state[4:2] == next_basic) && (observed_state[5] == !ref_control_last) && (observed_state[7:6] == next_uart) && (observed_state[8] == ref_active) && (observed_state[14:9] == ref_sent) && (!ref_active || ({1'b0, observed_state[20:15]} == ref_total-7'd1)); // 空闲旧长度不影响行为，活动长度必须等于已发加未发减一。
    assign take_count = {3'b000, actual_take[0]}+{3'b000, actual_take[1]}+{3'b000, actual_take[2]}+{3'b000, actual_take[3]}+{3'b000, actual_take[4]}+{3'b000, actual_take[5]}+{3'b000, actual_take[6]}+{3'b000, actual_take[7]}+{3'b000, actual_take[8]}+{3'b000, actual_take[9]}+{3'b000, actual_take[10]}; // 十一位的精确总和用于独立单赢家检查。
    assign o_groups[0] = !flag_reference_bounds || !flag_state_relation; // 所有行为相关状态关系与合法范围均必须保持。
    assign o_groups[1] = ({actual_valid, actual_source, actual_index, actual_last, actual_error, actual_locked, actual_uart_index} != {ref_valid, ref_source, ref_event_index, ref_last_word, ref_error, (i_rstn && ref_active), ref_uart_index}); // 比较所有控制和公开状态位。
    assign o_groups[2] = (actual_take != ref_take); // 独立比较全部十一来源的 DWORD 消耗。
    assign o_groups[3] = (actual_done != ref_done); // 独立比较全部十一来源的完整消息退休。
    assign o_groups[4] = (actual_word != ref_word); // 每一个有效或清零的数据位都必须正确。
    assign o_groups[5] = (take_count > 4'd1) || ((actual_done & ~actual_take) != 11'd0) || (actual_valid && (actual_source > 4'd10)) || (actual_locked && actual_valid && (actual_source != 4'd7)); // 附加检查单赢家、退休包含关系及 UART 不被穿插。
    assign o_violation = |o_groups; // 完整并集作为归纳假设和结论，不切掉任何组。
    always @(posedge i_clk) begin // 参考组历史只由独立模型的整消息退休推进。
        if (!i_rstn) ref_group_last <= 2'd2; // 合法复位后的下一组为 Basic。
        else if (ref_last_word) ref_group_last <= (ref_source < 4'd5) ? 2'd0 : (ref_source < 4'd7) ? 2'd1 : 2'd2; // 记录最后完成来源所属组。
    end // 结束参考组历史更新。
    always @(posedge i_clk) begin // 参考 Basic 历史不跟随 DUT 的游标或事件。
        if (!i_rstn) ref_basic_last <= 3'd4; // 复位使相对来源零具有最小正向距离。
        else if (ref_last_word && (ref_source < 4'd5)) ref_basic_last <= ref_source[2:0]; // 只有本组完成才改写最后赢家。
    end // 结束参考 Basic 历史更新。
    always @(posedge i_clk) begin // 参考 Control 只记录刚完成的是五还是六。
        if (!i_rstn) ref_control_last <= 1'b1; // 复位使来源五先于来源六。
        else if (ref_last_word && ((ref_source == 4'd5) || (ref_source == 4'd6))) ref_control_last <= (ref_source == 4'd6); // 记录相对编号零或一。
    end // 结束参考 Control 历史更新。
    always @(posedge i_clk) begin // 参考 UART 历史在整条 transport 末字才更新。
        if (!i_rstn) ref_uart_last <= 2'd3; // 复位使 transport 成为第一个候选。
        else if (ref_last_word && (ref_source >= 4'd7)) begin // UART 组的四个来源均明确映射为相对编号。
            case (ref_source) // 记录当前赢家而非下一来源。
                4'd7: ref_uart_last <= 2'd0; // transport 的组内编号为零。
                4'd8: ref_uart_last <= 2'd1; // credit update 的组内编号为一。
                4'd9: ref_uart_last <= 2'd2; // reset request 的组内编号为二。
                default: ref_uart_last <= 2'd3; // reset response 的组内编号为三。
            endcase // 结束参考 UART 组编号记录。
        end // 结束参考 UART 整消息完成更新。
    end // 结束参考 UART 历史寄存器。
    always @(posedge i_clk) begin // 剩余字数仅在真实参考服务时扣减。
        if (!i_rstn) ref_remaining <= 6'd0; // 同步复位丢弃所有待发送参考字。
        else if (ref_take[7]) begin // 没有消费或撤回资格时必须保持原剩余量。
            if (ref_active) ref_remaining <= ref_remaining-6'd1; // 活动消息每次服务恰好减一，不读取变化的输入长度。
            else ref_remaining <= i_uart_word_count-6'd1; // 首字已消费，剩余量等于完整长度减一。
        end // 结束参考 UART 消费更新。
    end // 结束参考剩余字数寄存器。
    always @(posedge i_clk) begin // 已发送数量独立于 DUT 末字索引增长。
        if (!i_rstn) ref_sent <= 6'd0; // 同步复位回到没有活动消息的状态。
        else if (ref_take[7]) begin // 每个真正消费的 UART 字才改变历史。
            if (ref_last_word) ref_sent <= 6'd0; // 末字后不再保留活动字索引。
            else ref_sent <= ref_sent+6'd1; // 头或非末尾负载恰好增加一个已消费字。
        end // 结束参考已发数量更新。
    end // 结束参考已发字数寄存器。
endmodule // 结束独立 DL 消息仲裁归纳性质模块。
