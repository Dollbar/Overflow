// UART 发送来源：先预留整条消息的信用，再完整暂存 payload 后参与仲裁。
// 依据 UALink 200G DL/PL 2.0；2026-09-08，stream0 发送数据路径子集。
// 信用更新节流、完整 Stream Reset 和外部 FIFO 由后续集成承担。
`timescale 1ps/1ps // 使用统一仿真精度，硬件逻辑不含延时。
module dl_uart_tx_source ( // 单条 UART transport 的暂存与实际发送来源模块。
    input wire i_clk, // 控制与暂存数据使用同一个正沿时钟。
    input wire i_rstn, // 同步低有效本地复位，须与外部 FIFO 和仲裁器协调。
    input wire i_channel4_enabled, // 允许正常 UART 数据发送的已协商状态。
    input wire [11:0] i_payload_fill, // 外部独占消费 FIFO 的完整未读 DWORD 数量。
    input wire i_payload_valid, // 外部 FIFO 当前队首已从存储器读回并保持有效。
    input wire [31:0] i_payload_word, // 外部 FIFO 的当前不透明 payload DWORD。
    input wire i_credit_valid, // 上游已经确认合法的 stream0 信用更新事件。
    input wire [11:0] i_credit_value, // 最新信用消息中的绝对 DataFCSeq 值。
    input wire i_source_take, // 仲裁器实际消费本来源当前 DWORD 的事件。
    output wire o_payload_ready, // 本来源可以接收一个已预留消息的 payload 字。
    output wire o_source_pending, // 整条消息已经暂存完整且当前通道允许服务。
    output wire [31:0] o_word, // 仲裁器当前应服务的头或 payload，无资格时为零。
    output wire [5:0] o_word_count, // 含头的整消息字数，范围二至三十三。
    output wire [5:0] o_word_index, // 当前待发字的消息内索引，头为零。
    output wire o_busy, // 已预留的消息仍在填充、等待或发送中。
    output wire [5:0] o_reserved_words, // 当前整条消息预留的 payload 信用，直到完成才释放。
    output wire [5:0] o_staged_words, // 暂存中实际持有且尚未发送的 payload 字数。
    output wire [11:0] o_tx_counter, // 已完成消息累计发送的 payload 计数，模四千零九十六。
    output wire [11:0] o_latest_fc, // 最近接收并保存的绝对信用更新值。
    output wire o_message_done, // 当前真实服务沿完成整条已捕获消息。
    output wire o_error // 非法消费或活动消息中关闭通道的本地接口诊断。
); // 结束 UART 暂存来源的固定原生接口。
    reg reg_busy; // 单一预约所有权禁止同一信用被再次预留。
    reg reg_ready; // 全部捕获 payload 都已存入固定暂存寄存器。
    reg [5:0] reg_payload_count; // 开始预留时捕获的消息 payload 数量。
    reg [5:0] cnt_loaded; // 已从外部 FIFO 捕获的字数及下一个写入索引。
    reg [5:0] cnt_word_index; // 下一个待发消息 DWORD 的索引，包含头。
    reg [5:0] cnt_held; // 实际持有且未发送的暂存 payload 数量。
    reg [11:0] cnt_tx; // 只有整条消息完成时才递增的发送信用计数。
    reg [11:0] reg_latest_fc; // 最新合法绝对信用值，不对重复消息累加。
    wire [11:0] available_credits, capture_limit; // 当前未提交信用及与外部填充的最小值。
    wire [5:0] capture_count; // 最多三十二字的本次完整预约数量。
    wire [4:0] payload_address, header_length; // 头之外的暂存地址和标准五位减一长度。
    wire [1023:0] staged_payload; // 三十二个独立寄存 DWORD 的固定排列。
    wire [31:0] current_payload; // 当前索引对应的已暂存 payload。
    wire flag_capture, flag_load, flag_take, flag_payload_take, flag_complete; // 预约、填充和真实服务事件。
    genvar gen_word; // 在展开期创建固定三十二个字的独立存储和写使能。
    assign available_credits = reg_latest_fc-cnt_tx; // 十二位减法自然完成规定的模四千零九十六运算。
    assign capture_limit = (available_credits < i_payload_fill) ? available_credits : i_payload_fill; // 信用与已存在 FIFO 数据共同限制预约。
    assign capture_count = (capture_limit > 12'd32) ? 6'd32 : capture_limit[5:0]; // 再施加标准单消息最大 payload 限制。
    assign flag_capture = i_rstn && i_channel4_enabled && !reg_busy && (capture_limit != 12'd0); // 只用沿前信用和填充建立唯一完整预约。
    assign o_payload_ready = i_rstn && i_channel4_enabled && reg_busy && !reg_ready; // 暂存未满才从外部读回队首接收数据。
    assign flag_load = o_payload_ready && i_payload_valid; // 外部 FIFO 只有真正的双向握手才能消费一个字。
    assign o_source_pending = i_rstn && i_channel4_enabled && reg_busy && reg_ready; // 未完整暂存不得提交头，禁用期暂停全部来源事件。
    assign flag_take = o_source_pending && i_source_take; // 非法仲裁消费输入不能改变消息内发送进度。
    assign flag_payload_take = flag_take && (cnt_word_index != 6'd0); // 头服务不释放 payload 存储容量。
    assign flag_complete = flag_take && (cnt_word_index == reg_payload_count); // 捕获的最后一个 payload 真正服务后才完成。
    assign payload_address = cnt_word_index[4:0]-5'd1; // 索引三十二通过五位减一正确定位最后一个暂存字。
    assign header_length = reg_payload_count[4:0]-5'd1; // payload 三十二对应编码三十一，payload 一对应零。
    assign current_payload = staged_payload[payload_address*32 +: 32]; // 只选取当前固定暂存字，不依赖外部 FIFO 读延时。
    assign o_word = o_source_pending ? ((cnt_word_index == 6'd0) ? {header_length, 27'd4} : current_payload) : 32'd0; // stream0 标准头或真实 payload；无资格不暴露旧数据。
    assign o_word_count = o_source_pending ? reg_payload_count+6'd1 : 6'd0; // 对仲裁器提供稳定且包含头的完整长度。
    assign o_word_index = o_source_pending ? cnt_word_index : 6'd0; // 暂停期间公开事件索引归零，内部索引保持。
    assign o_busy = i_rstn && reg_busy; // 复位期间屏蔽旧的消息预约观察。
    assign o_reserved_words = (i_rstn && reg_busy) ? reg_payload_count : 6'd0; // 预约数量在填充和整个发送期间保持不变。
    assign o_staged_words = i_rstn ? cnt_held : 6'd0; // 固件总容量计算应同时包含这些未发送数据。
    assign o_tx_counter = i_rstn ? cnt_tx : 12'd0; // 公开已完成消息的实际 payload 信用计数。
    assign o_latest_fc = i_rstn ? reg_latest_fc : 12'd0; // 公开沿前最近信用值供状态检查。
    assign o_message_done = flag_complete; // 与实际最后一次消费同沿产生消息完成事件。
    assign o_error = i_rstn && ((i_source_take && !o_source_pending) || (!i_channel4_enabled && reg_ready && (cnt_word_index != 6'd0))); // 活动关闭必须由集成层先排空或协调复位处理。
    generate // 暂存寄存器只由对应固定写地址更新，所有数据同域。
        for (gen_word = 32'd0; gen_word < 32'd32; gen_word = gen_word+32'd1) begin : gen_words // 固定最大消息的三十二个独立 DWORD 槽。
            localparam [5:0] C_WORD = gen_word[5:0]; // 当前槽的展开期常量索引。
            reg [31:0] reg_word; // 当前槽只保存一个已经握手捕获的 payload 字。
            assign staged_payload[gen_word*32 +: 32] = reg_word; // 固定排列不改变数据字节或比特顺序。
            always @(posedge i_clk) begin // 每个生成实例只驱动自身唯一的数据寄存器。
                if (!i_rstn) reg_word <= 32'd0; // 同步清除旧暂存内容，控制有效性同时复位。
                else if (flag_load && (cnt_loaded == C_WORD)) reg_word <= i_payload_word; // 只在该槽实际接收 FIFO 字时捕获数据。
            end // 结束单个暂存字的独立写入逻辑。
        end // 结束固定暂存存储的展开。
    endgenerate // 结束完整 payload 暂存结构。
    always @(posedge i_clk) begin // 保存唯一消息预约所有权。
        if (!i_rstn) reg_busy <= 1'b0; // 同步复位丢弃旧预约，外部 FIFO 必须同时协调。
        else if (flag_complete) reg_busy <= 1'b0; // 末 payload 真正送出后才允许下一条预约。
        else if (flag_capture) reg_busy <= 1'b1; // 沿前信用和填充通过后建立预约。
    end // 结束消息预约状态寄存器。
    always @(posedge i_clk) begin // 保存完整暂存是否已经完成。
        if (!i_rstn) reg_ready <= 1'b0; // 复位禁止旧消息重新参与仲裁。
        else if (flag_complete || flag_capture) reg_ready <= 1'b0; // 完成或新预约时重新等待完整数据。
        else if (flag_load && (cnt_loaded+6'd1 == reg_payload_count)) reg_ready <= 1'b1; // 最后一个预约字握手后才允许发头。
    end // 结束整消息暂存资格寄存器。
    always @(posedge i_clk) begin // 独立保存本条消息的不可变 payload 长度。
        if (!i_rstn) reg_payload_count <= 6'd0; // 复位不保留旧长度。
        else if (flag_complete) reg_payload_count <= 6'd0; // 退休后清除已释放的预约计数。
        else if (flag_capture) reg_payload_count <= capture_count; // 长度只在空闲预约沿采样一次。
    end // 结束捕获消息长度寄存器。
    always @(posedge i_clk) begin // 保存下一个固定暂存写地址。
        if (!i_rstn) cnt_loaded <= 6'd0; // 同步复位从零槽重新填充。
        else if (flag_complete || flag_capture) cnt_loaded <= 6'd0; // 消息边界重新建立捕获计数。
        else if (flag_load) cnt_loaded <= cnt_loaded+6'd1; // FIFO 停顿时不越过尚未取得的数据。
    end // 结束暂存填充计数寄存器。
    always @(posedge i_clk) begin // 保存包含头的当前消息服务索引。
        if (!i_rstn) cnt_word_index <= 6'd0; // 复位后第一字总是头。
        else if (flag_complete || flag_capture) cnt_word_index <= 6'd0; // 两个消息边界都回到头索引。
        else if (flag_take) cnt_word_index <= cnt_word_index+6'd1; // 只有真实来源消费才能推进一个 DWORD。
    end // 结束当前消息字索引寄存器。
    always @(posedge i_clk) begin // 保存实际未发出的暂存 payload 容量占用。
        if (!i_rstn) cnt_held <= 6'd0; // 同步复位释放本地逻辑暂存所有权。
        else if (flag_complete || flag_capture) cnt_held <= 6'd0; // 新消息尚无数据，完成消息最后一字也已送出。
        else if (flag_load) cnt_held <= cnt_held+6'd1; // 捕获一个实际 FIFO 字增加真实暂存占用。
        else if (flag_payload_take) cnt_held <= cnt_held-6'd1; // 实际 payload 送出后释放一字，头不会释放。
    end // 结束真实暂存占用寄存器。
    always @(posedge i_clk) begin // 保存协议发送方向的绝对模信用计数。
        if (!i_rstn) cnt_tx <= 12'd0; // 初始发送计数为零。
        else if (flag_complete) cnt_tx <= cnt_tx+{6'd0, reg_payload_count}; // 只按已完成消息的 payload 数扣账，不计头。
    end // 结束发送信用计数寄存器。
    always @(posedge i_clk) begin // 保存最近合法接收的绝对信用值。
        if (!i_rstn) reg_latest_fc <= 12'd0; // 初始没有对端授予的信用。
        else if (i_credit_valid) reg_latest_fc <= i_credit_value; // 新更新直接替换，重复相同值不会重复授权。
    end // 结束绝对信用记录寄存器。
endmodule // 结束完整暂存的 UART TX 来源。
