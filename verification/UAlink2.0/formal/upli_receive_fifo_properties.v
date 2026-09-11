// Prove storage ownership and legal address scheduling over original FIFO state.
// 日期 2026-09-08；脚本只添加观察输出，不替换状态、驱动或 SRAM 读结果。
`timescale 1ps/1ps // 形式步骤对应一个共同采样沿。
module upli_receive_fifo_properties #( // 接收 FIFO 真实控制状态的独立守恒检查模块。
    parameter integer C_DEPTH = 5, // 被证明的逻辑容量配置。
    parameter integer C_DATA_WIDTH = 32, // 保留 DUT 的真实数据输入宽度。
    parameter integer C_COUNT_WIDTH = (C_DEPTH < 2) ? 1 : (C_DEPTH < 4) ? 2 : (C_DEPTH < 8) ? 3 : (C_DEPTH < 16) ? 4 : (C_DEPTH < 32) ? 5 : (C_DEPTH < 64) ? 6 : (C_DEPTH < 128) ? 7 : (C_DEPTH < 256) ? 8 : (C_DEPTH < 512) ? 9 : (C_DEPTH < 1024) ? 10 : (C_DEPTH < 2048) ? 11 : (C_DEPTH < 4096) ? 12 : (C_DEPTH < 8192) ? 13 : (C_DEPTH < 16384) ? 14 : (C_DEPTH < 32768) ? 15 : 16 // 派生宽度与实际控制器匹配。
) ( // 环境允许任意输入组合，不假设内部计数合法。
    input wire i_clk, // 共享时钟由形式步骤推进。
    input wire i_rstn, // 同步复位清除 DUT 与独立历史状态。
    input wire i_write_valid, // 任意本地生产者有效信号。
    input wire [C_DATA_WIDTH-1:0] i_write_data, // 任意完整存储字。
    input wire i_read_ready, // 任意下游消费准备信号。
    input wire [C_DATA_WIDTH-1:0] i_sram_read_data, // 任意后端读值，本证明不冒充 SRAM 数据一致性。
    output wire o_violation // 任一容量、守恒、地址或预约属性失败。
); // 结束 FIFO 控制性质接口。
    localparam [17:0] C_LIMIT = C_DEPTH[17:0]; // 十八位检查算术覆盖两个最大容量相加。
    wire ready, valid, write_cs, read_cs, pending; // 原 DUT 的真实接口和在途状态观察。
    wire [C_COUNT_WIDTH-1:0] count, unread, write_addr, read_addr; // 原 DUT 的计数与地址。
    wire [1:0] cached; // 原 DUT 的双输出缓存有效数量。
    wire [17:0] count_wide, unread_wide, cached_wide, pending_wide, write_wide, read_wide; // 检查域独立扩展，避免窄位回绕掩盖溢出。
    wire [17:0] distance; // 从两个真实指针独立计算模容量距离。
    reg [17:0] previous_count; // 前一沿实际总占用历史。
    reg [1:0] previous_events; // 前一沿真实接受写和消费读的历史。
    wire [17:0] accepted_wide, consumed_wide; // 将各一次握手扩展到守恒检查宽度。
    upli_receive_fifo Fifo_Inst ( // 脚本先参数化真实 DUT 再加观察，不能重新从原 AST 派生而丢失观察端口。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_write_valid(i_write_valid), .i_write_data(i_write_data), .o_write_ready(ready), // 任意生产者环境保持真实连接。
        .i_read_ready(i_read_ready), .o_read_valid(valid), .o_read_data(), .o_count(count), // 数据值完整性由实际 SRAM 仿真另证。
        .o_sram_write_cs(write_cs), .o_sram_write_addr(write_addr), .o_sram_write_data(), // 原始 SRAM 写资格和地址。
        .o_sram_read_cs(read_cs), .o_sram_read_addr(read_addr), .i_sram_read_data(i_sram_read_data), // 原始 SRAM 读资格和地址。
        .o_formal_unread(unread), .o_formal_pending(pending), .o_formal_cached(cached) // 原状态只增加输出观察，未切断任何驱动。
    ); // 结束实际控制器形式实例。
    assign count_wide = {{(18-C_COUNT_WIDTH){1'b0}}, count}; // 扩展总占用到独立检查域。
    assign unread_wide = {{(18-C_COUNT_WIDTH){1'b0}}, unread}; // 扩展后端未读所有权数量。
    assign cached_wide = {16'd0, cached}; // 扩展双缓存实际占用。
    assign pending_wide = {17'd0, pending}; // 一项在途读取仍算有效所有权。
    assign write_wide = {{(18-C_COUNT_WIDTH){1'b0}}, write_addr}; // 扩展循环写地址。
    assign read_wide = {{(18-C_COUNT_WIDTH){1'b0}}, read_addr}; // 扩展循环读地址。
    assign distance = (write_wide >= read_wide) ? (write_wide-read_wide) : (write_wide+C_LIMIT-read_wide); // 按实际非二次幂容量计算距离。
    assign accepted_wide = {17'd0, previous_events[1]}; // 前一沿真实接受数量只能为零或一。
    assign consumed_wide = {17'd0, previous_events[0]}; // 前一沿真实消费数量只能为零或一。
    always @(posedge i_clk) begin // 保存前一沿实际总占用，独立于 DUT 的更新公式。
        if (!i_rstn) previous_count <= 18'd0; // reset 后独立基线与 DUT 同步清零。
        else previous_count <= count_wide; // 只观察实际数量，不构造期望新计数。
    end // 结束独立占用历史寄存器。
    always @(posedge i_clk) begin // 从外部真实握手记录前一沿的所有权变化。
        if (!i_rstn) previous_events <= 2'b00; // reset 期间无合法生产或消费。
        else previous_events <= {ready && i_write_valid, valid && i_read_ready}; // 不借用 DUT 内部算术使检查自证。
    end // 结束真实握手历史寄存器。
    assign o_violation = (count_wide > C_LIMIT) || (count_wide != unread_wide+cached_wide+pending_wide) || (cached_wide+pending_wide > 18'd2) || (write_wide >= C_LIMIT) || (read_wide >= C_LIMIT) || (unread_wide > C_LIMIT) || ((unread_wide == C_LIMIT) ? (distance != 18'd0) : (unread_wide != distance)) || (read_cs && (unread_wide == 18'd0)) || (write_cs && read_cs && (write_addr == read_addr)) || (valid != (cached != 2'd0)) || ((previous_count+accepted_wide) != (count_wide+consumed_wide)); // 所有关系均为待证明性质而非输入假设。
endmodule // 结束 upli_receive_fifo_properties 容量与地址性质模块。
