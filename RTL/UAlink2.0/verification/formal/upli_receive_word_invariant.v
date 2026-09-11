// Read-only actual FIFO content relation, shared by channel account checkers.
// 日期2026-09-08；独立接受队列，不包含替代DUT或假设存储数据正确。
`timescale 1ps/1ps // 全部观察和shadow在实际共同UPLI沿推进。
module upli_receive_word_invariant #( // 单个实际账户完整字顺序关系检查模块。
    parameter integer C_DEPTH = 3, // 本次有限展开的逻辑容量。
    parameter integer C_WORD_WIDTH = 8, // 原payload及元数据补齐后的完整字宽。
    parameter integer C_COUNT_WIDTH = 4 // 由外层观察总线零扩展后的计数位宽。
) ( // 只有只读状态和独立边界事件，不驱动DUT任何信号。
    input wire i_clk, i_rstn, // 实际共同上升沿与同步复位。
    input wire i_push, i_pop, // 从原生入站资格和外部消费握手独立计算。
    input wire [C_WORD_WIDTH-1:0] i_word, // 原生输入的正确完整字，而非DUT写线。
    input wire [C_COUNT_WIDTH-1:0] i_count, i_unread, i_read_addr, i_write_addr, // 原账户真实计数及地址观察。
    input wire i_pending, // 真实在途读有效状态。
    input wire [1:0] i_cached, // 真实双缓存的有效数量。
    input wire [C_WORD_WIDTH-1:0] i_head, i_tail, i_read_result, // 真实缓存与SRAM注册Q。
    input wire [C_DEPTH*C_WORD_WIDTH-1:0] i_memory, // 实际逻辑行从地址零开始低序拼接。
    output wire [C_WORD_WIDTH-1:0] o_shadow_head, // 独立接受顺序的原队首完整字。
    output wire o_violation // 任意数量、地址或内容关系失败。
); // 结束实际账户只读不变量接口。
    localparam [17:0] C_LIMIT = C_DEPTH[17:0]; // 独立扩展算术覆盖全部实现容量域。
    localparam [31:0] C_WORDS = C_DEPTH; // 静态非负元素数用于完整展开。
    wire [17:0] count, unread, cached, read_addr, write_addr, prefetched, distance, survivors; // 独立检查域避免窄位回绕。
    reg [17:0] shadow_count; // 仅由边界接受和消费事件维护的占用。
    wire [C_DEPTH*C_WORD_WIDTH-1:0] shadow_words; // 与DUT环形地址无关的顺序队列。
    wire [C_DEPTH-1:0] bad_memory; // 每一实际有效行均参加内容检查。
    wire bad_tail, bad_control, bad_cache; // 双缓存、容量/地址及在途内容性质。
    genvar gen_word; // 每个shadow字分别具有时序更新块。
    assign count = {{(18-C_COUNT_WIDTH){1'b0}}, i_count}; // 零扩展总占用。
    assign unread = {{(18-C_COUNT_WIDTH){1'b0}}, i_unread}; // 零扩展实际后端数量。
    assign cached = {16'd0, i_cached}; // 明确扩展双缓存数量。
    assign read_addr = {{(18-C_COUNT_WIDTH){1'b0}}, i_read_addr}; // 真正循环读指针。
    assign write_addr = {{(18-C_COUNT_WIDTH){1'b0}}, i_write_addr}; // 真正循环写指针。
    assign prefetched = cached+{17'd0, i_pending}; // 预取所有权占据独立队列前缀。
    assign distance = (write_addr >= read_addr) ? write_addr-read_addr : write_addr+C_LIMIT-read_addr; // 非二次幂模容量距离。
    assign survivors = shadow_count-{17'd0, i_pop}; // 消费后的旧有效字长度。
    assign o_shadow_head = shadow_words[0 +: C_WORD_WIDTH]; // 只向外提供独立队首，外层按实际有效性选取。
    always @(posedge i_clk) begin // shadow数量不引用真实控制器的预取更新算法。
        if (!i_rstn) shadow_count <= 18'd0; // 复位取消所有旧shadow有效性。
        else shadow_count <= survivors+{17'd0, i_push}; // 每拍可独立接受一个字并消费一个旧字。
    end // 结束边界事件数量寄存器。
    generate // 固定逐字展开，实际存储与shadow布局不同。
        for (gen_word = 32'd0; gen_word < C_WORDS; gen_word = gen_word+32'd1) begin : gen_words // 当前逻辑地址与顺序位置。
            localparam [17:0] C_INDEX = gen_word; // 固定无符号逻辑地址。
            reg [C_WORD_WIDTH-1:0] reg_word; // 保存对应顺序位置的原接受字。
            wire [C_WORD_WIDTH-1:0] successor; // 消费后由独立队列下一位置前移。
            wire [17:0] offset, position; // 真实行相对未读队首的偏移与期望位置。
            assign shadow_words[gen_word*C_WORD_WIDTH +: C_WORD_WIDTH] = reg_word; // 低位置保存先接受的字。
            assign offset = (C_INDEX >= read_addr) ? C_INDEX-read_addr : C_INDEX+C_LIMIT-read_addr; // 实际循环地址与顺序队列的关系。
            assign position = prefetched+offset; // 实际未读部分位于缓存/在途之后。
            if (gen_word+1 < C_DEPTH) begin : gen_successor // 不创建越界固定切片。
                assign successor = shadow_words[(gen_word+1)*C_WORD_WIDTH +: C_WORD_WIDTH]; // 独立顺序前移候选。
            end else begin : gen_last // 最后位置不存在旧后继字。
                assign successor = {C_WORD_WIDTH{1'b0}}; // 无效尾部补零不生成有效所有权。
            end // 结束shadow后继边界。
            always @(posedge i_clk) begin // 一位置一寄存器更新块。
                if (!i_rstn) reg_word <= {C_WORD_WIDTH{1'b0}}; // 仅清验证队列，不清真实SRAM。
                else if (i_push && (survivors == C_INDEX)) reg_word <= i_word; // 新接受字追加在全部旧幸存字之后。
                else if (i_pop) reg_word <= successor; // 外部消费只移走原队首。
            end // 结束当前顺序字更新。
            assign bad_memory[gen_word] = (offset < unread) && (i_memory[gen_word*C_WORD_WIDTH +: C_WORD_WIDTH] != shadow_words[position*C_WORD_WIDTH +: C_WORD_WIDTH]); // 任一有效实际SRAM行必须等于原接受字。
        end // 结束全部真实行和shadow字检查。
        if (C_DEPTH > 1) begin : gen_second // 容量允许时检查第二缓存数据。
            assign bad_tail = (i_cached > 2'd1) && (i_tail != shadow_words[C_WORD_WIDTH +: C_WORD_WIDTH]); // 双缓存第二字保持原接受顺序。
        end else begin : gen_single // 容量一的数量关系禁止第二字有效。
            assign bad_tail = 1'b0; // 不生成越界切片。
        end // 结束深度一特殊结构。
    endgenerate // 结束顺序内容关系展开。
    assign bad_control = (count != shadow_count) || (count > C_LIMIT) || (unread > C_LIMIT) || (count != unread+prefetched) || (prefetched > 18'd2) || (read_addr >= C_LIMIT) || (write_addr >= C_LIMIT) || ((unread == C_LIMIT) ? (distance != 18'd0) : (distance != unread)) || (i_pop && (i_cached == 2'd0)) || (i_push && (count == C_LIMIT)); // 所有归纳辅助数量/地址关系本身均为被证明性质。
    assign bad_cache = bad_tail || ((i_cached != 2'd0) && (i_head != o_shadow_head)) || (i_pending && (i_read_result != shadow_words[cached*C_WORD_WIDTH +: C_WORD_WIDTH])); // 所有有效缓存/在途数据对应独立顺序前缀。
    assign o_violation = bad_control || bad_cache || (|bad_memory); // 任一账户完整字或顺序破坏都能触发失败。
endmodule // 结束upli_receive_word_invariant只读内容关系。
