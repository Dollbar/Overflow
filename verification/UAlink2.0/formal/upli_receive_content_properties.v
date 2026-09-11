// Real SDP-memory FIFO content proof against an independent accepted-word queue.
// 日期 2026-09-08；真实SRAM无复位、不切断Q，shadow仅为验证状态而非产品存储。
`timescale 1ps/1ps // 一个形式步骤推进共同UPLI时钟的全部实际端口。
module upli_receive_content_properties #( // 同步存储数据顺序、在途内容与复位隔离检查模块。
    parameter integer C_DEPTH = 3, // 实际逻辑容量，形式成本随完整存储展开增加。
    parameter integer C_DATA_WIDTH = 8, // 不透明完整字，可包含payload及保存元数据。
    parameter integer C_COUNT_WIDTH = (C_DEPTH < 2) ? 1 : (C_DEPTH < 4) ? 2 : (C_DEPTH < 8) ? 3 : (C_DEPTH < 16) ? 4 : (C_DEPTH < 32) ? 5 : (C_DEPTH < 64) ? 6 : (C_DEPTH < 128) ? 7 : (C_DEPTH < 256) ? 8 : (C_DEPTH < 512) ? 9 : (C_DEPTH < 1024) ? 10 : (C_DEPTH < 2048) ? 11 : (C_DEPTH < 4096) ? 12 : (C_DEPTH < 8192) ? 13 : (C_DEPTH < 16384) ? 14 : (C_DEPTH < 32768) ? 15 : 16 // 从逻辑深度派生并与真实控制器形状保持一致。
) ( // 外部数据与有效/准备信号均为独立符号量。
    input wire i_clk, // DUT、实际SRAM及独立队列共同上升沿。
    input wire i_rstn, // 同步复位取消所有有效字但不重置物理SRAM。
    input wire i_write_valid, // 任意本地生产者有效输入。
    input wire [C_DATA_WIDTH-1:0] i_write_data, // 每次接受的数据独立任意，不能只证明特定测试常数。
    input wire i_read_ready, // 任意消费者反压，不以活性假设隐藏停顿。
    output wire o_violation // 任一实际数据与已接受顺序不一致即失败。
); // 结束实际存储内容性质接口。
    localparam [17:0] C_LIMIT = C_DEPTH[17:0]; // 扩展算术覆盖最大深度和两指针距离之和。
    localparam [31:0] C_WORDS = C_DEPTH; // 非负静态展开数量使每个shadow字单独可观察。
    wire ready, valid, pending; // 实际存储接口与原在途有效寄存器。
    wire [C_COUNT_WIDTH-1:0] count, unread, read_addr, write_addr; // 实际所有权数量和循环指针。
    wire [1:0] cached; // 真实双输出缓存的有效数量。
    wire [C_DATA_WIDTH-1:0] data, head, tail, read_result; // 原始头、尾及真实SRAM注册读值。
    wire [C_DEPTH*C_DATA_WIDTH-1:0] memory_words, shadow_words; // 实际逻辑行观察与独立顺序队列，地址零均处于低位。
    wire push, pop; // 外部实际握手是shadow唯一数据来源和退休事件。
    wire [17:0] count_wide, unread_wide, cached_wide, pending_wide; // 所有权关系的统一独立检查域。
    wire [17:0] read_wide, write_wide, distance, survivors; // 模环地址距离与本次消费后shadow长度。
    wire [17:0] prefetched; // 真实缓存和在途结果占据shadow队列最前部。
    reg [17:0] shadow_count; // 独立统计实际外部接受减消费，不复制内部预取算法。
    wire [C_DEPTH-1:0] bad_memory; // 每个物理逻辑行的内容对应性质。
    wire bad_control, bad_cache, bad_tail; // 数量/指针和各输出流水内容关系。
    genvar gen_word; // 为每个shadow字及实际行生成独立检查。
    upli_receive_storage Storage_Inst ( // 脚本先展开原始模型与参数，仅增加只读观察。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_write_valid(i_write_valid), .i_write_data(i_write_data), .o_write_ready(ready), // 原写口保持真实数据路径。
        .i_read_ready(i_read_ready), .o_read_valid(valid), .o_read_data(data), .o_count(count), // 原消费输出被独立队列直接检查。
        .o_formal_unread(unread), .o_formal_pending(pending), .o_formal_cached(cached), // 原控制器状态只读，不用自由输入替换。
        .o_formal_head(head), .o_formal_tail(tail), .o_formal_read_addr(read_addr), .o_formal_write_addr(write_addr), // 原数据缓存与地址的实际驱动仍保留。
        .o_formal_read_result(read_result), .o_formal_memory(memory_words) // 包含真实SRAM状态及注册读输出，不使用任意Q抽象。
    ); // 结束实际存储及原行为模型实例。
    assign push = i_rstn && ready && i_write_valid; // 仅被实际接口接受的字进入独立队列。
    assign pop = i_rstn && valid && i_read_ready; // 仅外部真实消费释放shadow队首。
    assign count_wide = {{(18-C_COUNT_WIDTH){1'b0}}, count}; // 零扩展真实总占用。
    assign unread_wide = {{(18-C_COUNT_WIDTH){1'b0}}, unread}; // 零扩展实际后端未读所有权。
    assign cached_wide = {16'd0, cached}; // 双缓存数量显式扩展。
    assign pending_wide = {17'd0, pending}; // 在途字占一个逻辑容量。
    assign read_wide = {{(18-C_COUNT_WIDTH){1'b0}}, read_addr}; // 循环读指针扩展到关系检查域。
    assign write_wide = {{(18-C_COUNT_WIDTH){1'b0}}, write_addr}; // 循环写指针扩展到关系检查域。
    assign distance = (write_wide >= read_wide) ? (write_wide-read_wide) : (write_wide+C_LIMIT-read_wide); // 支持非二次幂的模深度距离。
    assign survivors = shadow_count-{17'd0, pop}; // 独立消费之后新字应追加的位置。
    assign prefetched = cached_wide+pending_wide; // 已取出的头部仍保留在shadow顺序队列中。
    always @(posedge i_clk) begin // 独立计数只依赖外部事件而非内部读请求。
        if (!i_rstn) shadow_count <= 18'd0; // 同步复位使旧shadow内容全部失去有效性。
        else shadow_count <= survivors+{17'd0, push}; // 并发输入/消费以独立加减关系更新。
    end // 结束独立队列总占用寄存器。
    generate // 每个队列元素有自己的时序块，避免验证实现与DUT环形地址共用算法。
        for (gen_word = 32'd0; gen_word < C_WORDS; gen_word = gen_word+32'd1) begin : gen_words // 完整展开本次声明的逻辑字数量。
            localparam [17:0] C_INDEX = gen_word; // 当前固定物理地址及shadow位置的显式无符号编码。
            reg [C_DATA_WIDTH-1:0] reg_word; // 此shadow位置保存已接受而未消费的完整字。
            wire [C_DATA_WIDTH-1:0] successor; // 消费时由下一位置移动到本位置。
            wire [17:0] offset, logical_position; // 当前物理行相对真实读指针的环距离及shadow索引。
            assign shadow_words[gen_word*C_DATA_WIDTH +: C_DATA_WIDTH] = reg_word; // 以顺序视图提供独立期望字。
            assign offset = (C_INDEX >= read_wide) ? (C_INDEX-read_wide) : (C_INDEX+C_LIMIT-read_wide); // 根据当前真实读指针定位此物理行的未读序号。
            assign logical_position = prefetched+offset; // SRAM未读部分位于所有已预取字之后。
            if (gen_word+1 < C_DEPTH) begin : gen_successor // 仅为实际存在的后继生成固定切片。
                assign successor = shadow_words[(gen_word+1)*C_DATA_WIDTH +: C_DATA_WIDTH]; // 独立shift队列按接收顺序左移。
            end else begin : gen_last // 队尾不存在后继数据。
                assign successor = {C_DATA_WIDTH{1'b0}}; // 无效末尾清零，不作为新有效数据来源。
            end // 结束有后继与末尾位置选择。
            always @(posedge i_clk) begin // 此shadow字只记录真实写入和消费者退休。
                if (!i_rstn) reg_word <= {C_DATA_WIDTH{1'b0}}; // 验证队列复位不代表实际SRAM被复位。
                else if (push && (survivors == C_INDEX)) reg_word <= i_write_data; // 新输入放在消费后的所有旧字之后。
                else if (pop) reg_word <= successor; // 删除且只删除真实消费者接纳的队首。
            end // 结束当前shadow字的独立寄存器。
            assign bad_memory[gen_word] = (offset < unread_wide) && (memory_words[gen_word*C_DATA_WIDTH +: C_DATA_WIDTH] != shadow_words[logical_position*C_DATA_WIDTH +: C_DATA_WIDTH]); // 所有具有未读所有权的真实物理行必须保存对应已接受完整字。
        end // 结束全部逻辑字的内容关系展开。
        if (C_DEPTH > 1) begin : gen_second // 只有容量允许时比较真实第二缓存内容。
            assign bad_tail = (cached > 2'd1) && (tail != shadow_words[C_DATA_WIDTH +: C_DATA_WIDTH]); // 双缓存的第二项必须是独立队列的第二个旧字。
        end else begin : gen_single // 深度一的容量关系禁止存在第二项。
            assign bad_tail = 1'b0; // 不创建越界shadow切片，缓存数量仍由控制性质检查。
        end // 结束第二输出缓存的容量边界检查。
    endgenerate // 结束独立shift队列及真实存储行性质。
    assign bad_control = (count_wide != shadow_count) || (count_wide > C_LIMIT) || (unread_wide > C_LIMIT) || (count_wide != unread_wide+prefetched) || (prefetched > 18'd2) || (read_wide >= C_LIMIT) || (write_wide >= C_LIMIT) || ((unread_wide == C_LIMIT) ? (distance != 18'd0) : (distance != unread_wide)) || (valid != (cached != 2'd0)) || (ready != (i_rstn && (shadow_count < C_LIMIT))); // 所有支持内容归纳的数量和地址关系同时被证明而非假设。
    assign bad_cache = bad_tail || (valid && ((head != shadow_words[0 +: C_DATA_WIDTH]) || (data != head))) || (!valid && (data != {C_DATA_WIDTH{1'b0}})) || (pending && (read_result != shadow_words[cached_wide*C_DATA_WIDTH +: C_DATA_WIDTH])); // 每个有效流水位置必须等于真实已接受顺序中的相应完整字。
    assign o_violation = bad_control || bad_cache || (|bad_memory); // 任一完整字、顺序或资源关系失败都会使证明失败。
endmodule // 结束 upli_receive_content_properties 实际SRAM内容与顺序检查模块。
