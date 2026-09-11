// DL 两级消息仲裁器：选择完整且已具备发送资格的外部消息源。
// 版本与范围：UALink 200G DL/PL 2.0 §2.4.1.2；2026-09-08 初始独立模块。
// 历史：实现源组轮询与 UART 整条消息占用；编码、信用、时限及队列由集成层承担。
`timescale 1ps/1ps // 与本地仿真环境统一时间单位，RTL 内部不使用延时。
module dl_message_arbiter ( // DL 消息仲裁器模块，每个有效 segment 最多消费一个 DWORD。
    input wire i_clk, // 所有调度状态所在的唯一正沿时钟。
    input wire i_rstn, // 同步低有效本地复位，不等于 UART 协议复位消息。
    input wire i_uart_cancel, // 同步撤销本地 UART transport，保持其它来源及全部轮询历史。
    input wire i_segment_available, // 当前沿实际提供一个 DL segment 的消息服务机会。
    input wire [10:0] i_source_pending, // 各源队首已经完整暂存且具备发送资格。
    input wire [351:0] i_source_words, // 源零位于最低 DWORD，UART 按公开索引提供当前字。
    input wire [5:0] i_uart_word_count, // UART 首字沿采样的总长度，含头且合法范围为二至三十三。
    output wire o_valid, // 当前沿实际发送一个消息 DWORD 的事件。
    output wire [31:0] o_word, // 当前发送 DWORD，事件无效时输出零。
    output wire [3:0] o_source, // 当前本地来源索引零至十，不是线上消息字段。
    output wire [5:0] o_word_index, // 当前有效字在完整消息中的从零起始索引。
    output wire o_last, // 当前 DWORD 完成整条消息，非 UART 源每字均完成。
    output wire [10:0] o_source_take, // 每个源只有对应位为一时才能消耗一个 DWORD。
    output wire [10:0] o_message_done, // 每个源只有对应位为一时才能移除完整队首消息。
    output wire o_error, // 本地接口长度或暂存资格违约，不是协议线上错误码。
    output wire o_locked, // UART 头已消费且仍需独占后续服务机会。
    output wire [5:0] o_uart_word_index // 外部 UART 暂存器应呈现的当前字索引，空闲为零。
); // 结束固定十一源仲裁器接口。
    reg [1:0] reg_group_next; // 下一条消息从哪个源组开始轮询。
    reg [2:0] reg_basic_next; // Basic 组的下一个初始候选位置。
    reg reg_control_next; // Control 组两个来源的下一个初始候选。
    reg [1:0] reg_uart_next; // UART 组四个来源的下一个初始候选。
    reg reg_uart_locked; // 只在首字服务后保存 UART transport 所有权。
    reg [5:0] cnt_uart_index; // 被锁定消息的下一个待发 DWORD 索引。
    reg [5:0] reg_uart_last; // 首字沿捕获的末字索引，后续输入长度改变不影响本消息。
    wire flag_uart_locked; // 取消沿立即屏蔽旧所有权，允许其它消息使用当前服务机会。
    wire flag_uart_length_valid; // 首字准入的本地长度检查。
    wire [10:0] flag_eligible; // 过滤无效 UART 长度后的空闲仲裁候选。
    wire flag_basic, flag_control, flag_uart; // 三个源组各自是否有可服务队首。
    reg [3:0] sel_basic, sel_control, sel_uart; // 各组内部轮询的本地来源索引。
    reg [1:0] sel_group; // 最终被选中的组，锁定时强制为 UART。
    reg [3:0] sel_source; // 最终被选中的来源，锁定时强制为 UART transport。
    wire flag_found, flag_emit, flag_last, flag_complete, flag_start; // 资格、实际服务及消息状态更新条件。
    genvar gen_source; // 固定展开十一位独热事件，不引入可变协议源数。
    assign flag_uart_locked = reg_uart_locked && !i_uart_cancel; // 选择逻辑使用有效占用，真实寄存器在采样沿清零。
    assign flag_uart_length_valid = (i_uart_word_count >= 6'd2) && (i_uart_word_count <= 6'd33); // 合法传输包含一个头和一至三十二个负载字。
    assign flag_eligible = i_source_pending & {3'b111, (flag_uart_length_valid && !i_uart_cancel), 7'b1111111}; // 空闲选择同时屏蔽非法长度和取消沿的新 UART transport。
    assign flag_basic = |flag_eligible[4:0]; // 五种 Basic 消息按组参与末级轮询。
    assign flag_control = |flag_eligible[6:5]; // 两种 Control 消息按组参与末级轮询。
    assign flag_uart = |flag_eligible[10:7]; // 四种 UART 消息仍具有各自的组内优先次序。
    always @(*) begin // 从 Basic 保存的轮询起点开始检查五种消息。
        sel_basic = 4'd0; // 无请求时给出确定索引，实际服务由组资格屏蔽。
        case (reg_basic_next) // 显式列出每个循环次序，避免统一固定优先级。
            3'd0: begin // 从 No-Op 来源开始，空缺来源跳过。
                if (flag_eligible[0]) sel_basic = 4'd0; else if (flag_eligible[1]) sel_basic = 4'd1; else if (flag_eligible[2]) sel_basic = 4'd2; else if (flag_eligible[3]) sel_basic = 4'd3; else if (flag_eligible[4]) sel_basic = 4'd4; // 按零一二三四查找。
            end // 结束 Basic 起点零的循环次序。
            3'd1: begin // 从 Tx Ready 来源开始并允许回绕。
                if (flag_eligible[1]) sel_basic = 4'd1; else if (flag_eligible[2]) sel_basic = 4'd2; else if (flag_eligible[3]) sel_basic = 4'd3; else if (flag_eligible[4]) sel_basic = 4'd4; else if (flag_eligible[0]) sel_basic = 4'd0; // 按一二三四零查找。
            end // 结束 Basic 起点一的循环次序。
            3'd2: begin // 从 TL Rate 来源开始并允许回绕。
                if (flag_eligible[2]) sel_basic = 4'd2; else if (flag_eligible[3]) sel_basic = 4'd3; else if (flag_eligible[4]) sel_basic = 4'd4; else if (flag_eligible[0]) sel_basic = 4'd0; else if (flag_eligible[1]) sel_basic = 4'd1; // 按二三四零一查找。
            end // 结束 Basic 起点二的循环次序。
            3'd3: begin // 从 Device ID 来源开始并允许回绕。
                if (flag_eligible[3]) sel_basic = 4'd3; else if (flag_eligible[4]) sel_basic = 4'd4; else if (flag_eligible[0]) sel_basic = 4'd0; else if (flag_eligible[1]) sel_basic = 4'd1; else if (flag_eligible[2]) sel_basic = 4'd2; // 按三四零一二查找。
            end // 结束 Basic 起点三的循环次序。
            3'd4: begin // 从 Port Number 来源开始并允许回绕。
                if (flag_eligible[4]) sel_basic = 4'd4; else if (flag_eligible[0]) sel_basic = 4'd0; else if (flag_eligible[1]) sel_basic = 4'd1; else if (flag_eligible[2]) sel_basic = 4'd2; else if (flag_eligible[3]) sel_basic = 4'd3; // 按四零一二三查找。
            end // 结束 Basic 起点四的循环次序。
            default: sel_basic = 4'd0; // 复位可达状态之外的编码保持确定值，不承诺故障恢复协议。
        endcase // 结束 Basic 组循环选择。
    end // 结束 Basic 组合仲裁。
    always @(*) begin // Control 独立保存两来源的公平顺序。
        sel_control = 4'd5; // 无请求时索引无效，仍给出确定值。
        if (!reg_control_next) begin // 首先查 Link Width 再查 Channel On/Offline。
            if (flag_eligible[5]) sel_control = 4'd5; else if (flag_eligible[6]) sel_control = 4'd6; // 允许跳过当前空源。
        end else begin // 完成前一来源后交换查找起点。
            if (flag_eligible[6]) sel_control = 4'd6; else if (flag_eligible[5]) sel_control = 4'd5; // 轮询顺序六后五。
        end // 结束 Control 当前起点选择。
    end // 结束 Control 组合仲裁。
    always @(*) begin // UART transport、信用与两种 reset 消息分别轮询。
        sel_uart = 4'd7; // 无请求时保持确定索引，组资格负责禁止服务。
        case (reg_uart_next) // 按捕获的组内起点选择一条完整消息。
            2'd0: begin // 从 transport 来源开始。
                if (flag_eligible[7]) sel_uart = 4'd7; else if (flag_eligible[8]) sel_uart = 4'd8; else if (flag_eligible[9]) sel_uart = 4'd9; else if (flag_eligible[10]) sel_uart = 4'd10; // 按七八九十查找。
            end // 结束 UART 起点零的循环次序。
            2'd1: begin // 从 credit update 来源开始。
                if (flag_eligible[8]) sel_uart = 4'd8; else if (flag_eligible[9]) sel_uart = 4'd9; else if (flag_eligible[10]) sel_uart = 4'd10; else if (flag_eligible[7]) sel_uart = 4'd7; // 按八九十七查找。
            end // 结束 UART 起点一的循环次序。
            2'd2: begin // 从 reset request 来源开始。
                if (flag_eligible[9]) sel_uart = 4'd9; else if (flag_eligible[10]) sel_uart = 4'd10; else if (flag_eligible[7]) sel_uart = 4'd7; else if (flag_eligible[8]) sel_uart = 4'd8; // 按九十七八查找。
            end // 结束 UART 起点二的循环次序。
            2'd3: begin // 从 reset response 来源开始。
                if (flag_eligible[10]) sel_uart = 4'd10; else if (flag_eligible[7]) sel_uart = 4'd7; else if (flag_eligible[8]) sel_uart = 4'd8; else if (flag_eligible[9]) sel_uart = 4'd9; // 按十七八九查找。
            end // 结束 UART 起点三的循环次序。
            default: sel_uart = 4'd7; // 为未知仿真值提供确定默认分支。
        endcase // 结束 UART 组循环选择。
    end // 结束 UART 组合仲裁。
    always @(*) begin // 末级在三个源组之间轮询，不能把十一源压成一个环。
        sel_group = 2'd0; // 空闲默认指向 Basic，最终服务仍需组资格。
        case (reg_group_next) // 只有消息完成才改变该轮询起点。
            2'd0: begin // 初始顺序 Basic、Control、UART。
                if (flag_basic) sel_group = 2'd0; else if (flag_control) sel_group = 2'd1; else if (flag_uart) sel_group = 2'd2; // 跳过没有消息的组。
            end // 结束末级起点 Basic 的循环次序。
            2'd1: begin // 从 Control 开始并回绕到 Basic。
                if (flag_control) sel_group = 2'd1; else if (flag_uart) sel_group = 2'd2; else if (flag_basic) sel_group = 2'd0; // 保留组间公平轮询。
            end // 结束末级起点 Control 的循环次序。
            2'd2: begin // 从 UART 开始并回绕到 Control。
                if (flag_uart) sel_group = 2'd2; else if (flag_basic) sel_group = 2'd0; else if (flag_control) sel_group = 2'd1; // 完成 UART 后才允许推进起点。
            end // 结束末级起点 UART 的循环次序。
            default: sel_group = 2'd0; // 非可达编码输出确定默认值。
        endcase // 结束未锁定时的组选择。
        if (flag_uart_locked) sel_group = 2'd2; // 已发出的 UART 头要求后续所有字保持组所有权。
        case (sel_group) // 从已选源组中取出该组的轮询赢家。
            2'd0: sel_source = sel_basic; // Basic 内部独立轮询的赢家。
            2'd1: sel_source = sel_control; // Control 内部独立轮询的赢家。
            2'd2: sel_source = flag_uart_locked ? 4'd7 : sel_uart; // 锁定期间其它 UART 控制源也不能穿插。
            default: sel_source = 4'd0; // 所有组合路径均明确赋值。
        endcase // 结束完整本地来源选择。
    end // 结束两级选择组合逻辑。
    assign flag_found = flag_uart_locked ? i_source_pending[7] : (flag_basic || flag_control || flag_uart); // 丢失锁定源时只保持占用，不能转发竞争消息。
    assign flag_emit = i_rstn && i_segment_available && flag_found; // 只有真实服务机会且非复位才产生消耗。
    assign flag_last = flag_uart_locked ? (cnt_uart_index == reg_uart_last) : (sel_source != 4'd7); // 非传输消息单字完成，传输头至少还需一个负载字。
    assign flag_complete = flag_emit && flag_last; // 只有被实际服务的末字才能退休消息。
    assign flag_start = flag_emit && !flag_uart_locked && (sel_source == 4'd7); // 首次服务 UART transport 才捕获长度和所有权。
    assign o_valid = flag_emit; // 直接表达当前沿的 DWORD 服务事件。
    assign o_word = flag_emit ? i_source_words[sel_source*32'd32 +: 32'd32] : 32'd0; // 从完整外部暂存队首取当前字，事件无效时清零。
    assign o_source = flag_emit ? sel_source : 4'd0; // 无效事件不泄露仲裁中的候选索引。
    assign o_word_index = (flag_emit && flag_uart_locked) ? cnt_uart_index : 6'd0; // 所有首字和单字消息的索引均为零。
    assign o_last = flag_complete; // 向发送路径公布实际消息末字事件。
    assign o_error = i_rstn && !i_uart_cancel && (flag_uart_locked ? !i_source_pending[7] : (i_source_pending[7] && !flag_uart_length_valid)); // 本地违约诊断独立于是否提供 segment 服务机会。
    assign o_locked = i_rstn && flag_uart_locked; // 复位沿前抑制公开占用观察，内部仍同步清零。
    assign o_uart_word_index = (i_rstn && flag_uart_locked) ? cnt_uart_index : 6'd0; // 外部源始终能确定完整暂存器的当前读地址。
    generate // 固定展开逐源事件以保证互斥的消费和完成输出。
        for (gen_source = 32'd0; gen_source < 32'd11; gen_source = gen_source+32'd1) begin : gen_sources // 每个合法本地来源恰有一个事件位。
            localparam [3:0] C_SOURCE = gen_source[3:0]; // 显式截取固定生成编号用于四位比较。
            assign o_source_take[gen_source] = flag_emit && (sel_source == C_SOURCE); // 只有最终赢家可消耗当前 DWORD。
            assign o_message_done[gen_source] = flag_complete && (sel_source == C_SOURCE); // 只有最终赢家的末字可退休完整消息。
        end // 结束逐源独热输出展开。
    endgenerate // 结束固定十一源事件结构。
    always @(posedge i_clk) begin // 更新组间轮询起点，不在 UART 中间字推进。
        if (!i_rstn) reg_group_next <= 2'd0; // 同步复位使第一轮从 Basic 开始。
        else if (flag_complete) reg_group_next <= (sel_group == 2'd2) ? 2'd0 : sel_group+2'd1; // 完成后从赢家的下一组开始。
    end // 结束组间轮询寄存器更新。
    always @(posedge i_clk) begin // Basic 只在本组消息实际完成时推进。
        if (!i_rstn) reg_basic_next <= 3'd0; // 同步复位恢复第一个 Basic 来源。
        else if (flag_complete && (sel_group == 2'd0)) reg_basic_next <= (sel_source == 4'd4) ? 3'd0 : sel_source[2:0]+3'd1; // 从选中来源的下一项循环查找。
    end // 结束 Basic 轮询寄存器更新。
    always @(posedge i_clk) begin // Control 两来源独立于其它组的流量推进。
        if (!i_rstn) reg_control_next <= 1'b0; // 同步复位从来源五开始。
        else if (flag_complete && (sel_group == 2'd1)) reg_control_next <= (sel_source == 4'd5); // 完成五后优先六，完成六后优先五。
    end // 结束 Control 轮询寄存器更新。
    always @(posedge i_clk) begin // UART 组只在整条消息结束时改变组内顺序。
        if (!i_rstn) reg_uart_next <= 2'd0; // 同步复位从 UART transport 开始。
        else if (flag_complete && (sel_group == 2'd2)) begin // 完成整条消息后明确选择下一个相对来源。
            case (sel_source) // 显式回绕，不依赖窄位算术下溢。
                4'd7: reg_uart_next <= 2'd1; // 完成 transport 后先考虑 credit update。
                4'd8: reg_uart_next <= 2'd2; // 完成信用消息后先考虑 reset request。
                4'd9: reg_uart_next <= 2'd3; // 完成 reset request 后先考虑 reset response。
                default: reg_uart_next <= 2'd0; // 完成 reset response 后回到 transport。
            endcase // 结束 UART 下一轮起点映射。
        end // 结束 UART 整条消息完成更新。
    end // 结束 UART 组轮询寄存器更新。
    always @(posedge i_clk) begin // 首字建立所有权，末字、全局复位或传输取消才清除。
        if (!i_rstn || i_uart_cancel) reg_uart_locked <= 1'b0; // 同步复位丢弃本地未完成消息占用。
        else if (flag_start) reg_uart_locked <= 1'b1; // UART 头提交后独占后续消息槽。
        else if (flag_complete) reg_uart_locked <= 1'b0; // 整条消息完成后允许重新两级仲裁。
    end // 结束 UART 所有权寄存器更新。
    always @(posedge i_clk) begin // 下一个待发字索引只跟随实际服务事件推进。
        if (!i_rstn || i_uart_cancel) cnt_uart_index <= 6'd0; // 同步复位恢复外部队首头字地址。
        else if (flag_start) cnt_uart_index <= 6'd1; // 头已经消费，下一字是首个负载。
        else if (flag_emit && flag_uart_locked) begin // 暂停或源违约时保留当前未消费字。
            if (flag_last) cnt_uart_index <= 6'd0; // 最后一个负载被服务后恢复头字索引。
            else cnt_uart_index <= cnt_uart_index+6'd1; // 已发出的非末字推进到下一个有效负载。
        end // 结束 UART 实际字服务的索引更新。
    end // 结束 UART 字索引寄存器更新。
    always @(posedge i_clk) begin // 消息总长度只在头字真实提交时捕获。
        if (!i_rstn || i_uart_cancel) reg_uart_last <= 6'd0; // 全局复位或传输取消清除无效的旧消息长度。
        else if (flag_start) reg_uart_last <= i_uart_word_count-6'd1; // 首字准入已保证减一范围为一至三十二。
    end // 结束 UART 末字索引寄存器更新。
endmodule // 结束 DL 完整消息两级仲裁器。
