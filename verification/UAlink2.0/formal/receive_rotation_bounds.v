`timescale 1ps/1ps // 纯组合旋转索引定理不修改真实存储。
module receive_rotation_bounds ( // 一百二十八字队列整体对齐索引证明模块。
    input wire [17:0] i_count, i_unread, i_read_addr, i_address, // 数量与任意真实行均独立取值。
    input wire [1:0] i_cached, // 双缓存全部编码参加证明。
    input wire i_pending, // 原在途所有权资格。
    output wire o_violation // 任何原有效行与旋转索引不等价即失败。
); // 结束独立旋转索引定理接口。
    wire [17:0] cached, prefetched, offset, position; // 与原完整内容不变量相同的宽算术。
    wire [6:0] rotation, rotated_position; // 一百二十八字循环的精确模索引。
    wire owned; // 原数量不变量成立的组合条件。
    assign cached={16'd0,i_cached}; // 原缓存数量完整零扩展。
    assign prefetched=cached+{17'd0,i_pending}; // 当前已预取的独立队列前缀。
    assign offset=(i_address>=i_read_addr)?i_address-i_read_addr:i_address+18'd128-i_read_addr; // 当前实际行相对未读队首的原环距离。
    assign position=prefetched+offset; // 原完整顺序队列索引。
    assign rotation=prefetched[6:0]-i_read_addr[6:0]; // 将独立顺序队列对齐实际物理地址。
    assign rotated_position=i_address[6:0]+rotation; // 整体向右旋转后当前行对应的顺序位置。
    assign owned=(i_count<=18'd128)&&(i_unread<=18'd128)&&(i_count==i_unread+prefetched)&&(prefetched<=18'd2)&&(i_read_addr<18'd128); // 所有条件都来自原检查器被证明的数量关系。
    assign o_violation=(owned&&(i_address<18'd128)&&(offset<i_unread)&&((position>=18'd128)||(position!={11'd0,rotated_position})))||(owned&&i_pending&&(cached>18'd1)); // 对任意输入验证蕴含关系而不引入 assume。
endmodule // 结束一百二十八字整体旋转索引定理模块。
