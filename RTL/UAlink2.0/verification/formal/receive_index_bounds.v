`timescale 1ps/1ps // 纯组合索引等价性质不推进任何真实存储状态。
module receive_index_bounds #(parameter integer C_DEPTH=128) ( // 接收队列动态索引范围证明模块。
    input wire [17:0] i_count, i_unread, i_read_addr, i_address, // 所有实际数量和所选逻辑行均任意。
    input wire [1:0] i_cached, // 原双缓存数量完整覆盖合法与非法编码。
    input wire i_pending, // 真实在途所有权的一位资格。
    output wire o_violation // 任何合法所有权下索引截断不等价即失败。
); // 结束独立索引定理模块接口。
    localparam [17:0] C_LIMIT=C_DEPTH; // 与原不变量相同的十八位数量域。
    localparam integer C_INDEX_WIDTH=(C_DEPTH<=2)?1:(C_DEPTH<=4)?2:(C_DEPTH<=8)?3:(C_DEPTH<=16)?4:(C_DEPTH<=32)?5:(C_DEPTH<=64)?6:(C_DEPTH<=128)?7:(C_DEPTH<=256)?8:(C_DEPTH<=512)?9:(C_DEPTH<=1024)?10:(C_DEPTH<=2048)?11:12; // 保存全部合法顺序位置的最小位宽。
    wire [17:0] cached, prefetched, offset, position, narrowed; // 所有原始与有界索引计算同时保留。
    wire owned; // 只表达旧完整不变量已检查的数量关系而不是求解器假设。
    assign cached={16'd0,i_cached}; // 原缓存数量无损扩展。
    assign prefetched=cached+{17'd0,i_pending}; // 缓存和在途共同占据队首。
    assign offset=(i_address>=i_read_addr)?i_address-i_read_addr:i_address+C_LIMIT-i_read_addr; // 与实际循环行到顺序位置的关系一致。
    assign position=prefetched+offset; // 逻辑 SRAM 行位于预取前缀之后。
    assign narrowed={{(18-C_INDEX_WIDTH){1'b0}},position[C_INDEX_WIDTH-1:0]}; // 只去除范围外无法有效使用的索引位。
    assign owned=(i_count<=C_LIMIT)&&(i_unread<=C_LIMIT)&&(i_count==i_unread+prefetched)&&(prefetched<=18'd2)&&(i_read_addr<C_LIMIT); // 这些关系本身由原归纳检查器证明。
    assign o_violation=(owned&&(i_address<C_LIMIT)&&(offset<i_unread)&&((position>=C_LIMIT)||(narrowed!=position)))||(owned&&i_pending&&(cached>=C_LIMIT)); // 对任意输入证明蕴含式而不设置任何 assume。
endmodule // 结束接收队列索引范围证明模块。
