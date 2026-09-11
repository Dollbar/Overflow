// UPLI normal credit return metadata queue; Common 2.0 sections 2.6 and 4.3.
// 日期 2026-09-08；仅保存已退休 beat 的原 VC/Pool，不包含 payload 缓冲。
// Output enable reserves the next registered bus cycle, never cancelling a prior grant.
// 输出许可预约沿后总线周期；已注册的信用承诺不能被下游丢弃。
`timescale 1ps/1ps // 保持 UPLI 统一时间精度，综合逻辑没有延时。
module upli_credit_return_queue #( // 正常信用元数据保存与同类批次归还模块。
    parameter integer C_NUM_PORTS = 1, // 启用一个、两个或四个独立返回端口。
    parameter integer C_DEPTH = 4, // 每端口退休元数据槽数，允许一至十六及非二次幂。
    parameter integer C_COUNT_WIDTH = (C_DEPTH <= 1) ? 1 : ((C_DEPTH <= 3) ? 2 : ((C_DEPTH <= 7) ? 3 : ((C_DEPTH <= 15) ? 4 : 5))) // 从深度导出的端口宽度，非法独立覆盖在层次检查时拒绝。
) ( // 本地退休握手与原生无 ready 返回接口属于同一时钟域。
    input wire i_clk, // 所有寄存器使用 UPLI 上升沿时钟。
    input wire i_rstn, // 同步低有效复位，取消未完成的局部状态。
    input wire [C_NUM_PORTS-1:0] i_return_enable, // 本地预约许可只生成启用端口，原生返回输出仍固定四端口形状。
    input wire i_retire_valid, // 上游呈现一个已经退休缓冲的保存元数据。
    input wire [1:0] i_retire_port, // 此退休记录属于哪一个物理 UPLI port。
    input wire [1:0] i_retire_vc, // 必须回放原始 beat 的 VC，Pool 信用也保留。
    input wire i_retire_pool, // 保存的信用类型，不得从当前请求重新推断。
    output wire o_retire_ready, // 选中端口沿前有空间才允许本地入队。
    output wire [3:0] o_credit_valid, // 每端口注册的一至四信用批次有效信号。
    output wire [3:0] o_credit_pool, // 批次原始 Pool 类型，无效周期为零。
    output wire [7:0] o_credit_vc, // 每端口两个 bit 的原始 VC 元信息。
    output wire [7:0] o_credit_num, // 每端口批次实际信用数量减一的编码。
    output wire [4*C_COUNT_WIDTH-1:0] o_pending_count // 每端口尚未调度到注册输出的记录数量。
); // 结束正常信用返回队列参数与接口。
    localparam integer C_DERIVED_WIDTH = (C_DEPTH <= 1) ? 1 : ((C_DEPTH <= 3) ? 2 : ((C_DEPTH <= 7) ? 3 : ((C_DEPTH <= 15) ? 4 : 5))); // 校验接口计数宽度必须等于深度所需最小宽度。
    localparam [31:0] C_SLOT_LIMIT = C_DEPTH; // 显式常量供存储槽展开与静态检查使用。
    localparam [4:0] C_DEPTH_VALUE = C_DEPTH[4:0]; // 合法深度范围内显式取五位容量常量。
    wire [3:0] port_ready; // 各端口空间及地址匹配的独立条件。
    genvar gen_port, gen_slot, gen_head; // 常量展开端口、元数据槽及最多四项队首观察。
    assign o_retire_ready = i_rstn && (|port_ready); // 复位期间及未使用端口不会承诺接纳。
    generate // 所有容量与实例数量在 elaboration 时固定。
        if (((C_NUM_PORTS != 1) && (C_NUM_PORTS != 2) && (C_NUM_PORTS != 4)) || (C_DEPTH < 1) || (C_DEPTH > 16) || (C_COUNT_WIDTH != C_DERIVED_WIDTH)) begin : gen_invalid // 拒绝非法深度、端口数或不一致的派生计数宽度。
            upli_return_parameters_invalid Invalid_Inst (); // 未定义层次使非法参数的编译或综合明确失败。
        end // 结束非法配置拒绝分支。
        for (gen_port = 0; gen_port < 4; gen_port = gen_port+1) begin : gen_ports // 保持固定四端口原生信号形状。
            if (gen_port < C_NUM_PORTS) begin : gen_active // 仅启用端口生成元数据和控制寄存器。
                localparam [1:0] C_PORT = gen_port; // 当前展开端口的双位比较常量。
                reg [C_COUNT_WIDTH-1:0] cnt_pending; // 包括队首在内的沿前有效退休记录数量。
                wire [4:0] count_extended, survivors; // 扩展减法避免小深度截断批次数量。
                wire [C_COUNT_WIDTH-1:0] count_next; // 资格限制下零至深度范围的更新计数。
                wire [3*C_DEPTH-1:0] saved_metadata; // 低位槽是队首，每项保存 Pool 和原 VC。
                wire [11:0] head_metadata; // 最多前四项元数据，超出实际深度的项固定零。
                wire [1:0] head_vc; // 队首原 VC 的双位命名观察点。
                wire [3:0] head_equal; // 各前缀项有效且与原队首元数据一致。
                reg [2:0] batch_count; // 本沿从旧队列选择的零至四个信用。
                wire flag_accept, flag_publish; // 本地接纳与注册返回的独立资格。
                reg reg_valid_o, reg_pool_o; // 独立注册的批次有效及信用类型。
                reg [1:0] reg_vc_o, reg_num_o; // 独立注册的 VC 和数量编码。
                assign count_extended = {{(5-C_COUNT_WIDTH){1'b0}}, cnt_pending}; // 零扩展当前队列长度供比较和减法使用。
                assign survivors = count_extended - {2'b00, batch_count}; // 仅减去沿前存在且同类的记录。
                assign count_next = survivors[C_COUNT_WIDTH-1:0] + {{(C_COUNT_WIDTH-1){1'b0}}, flag_accept}; // 沿前非满才接纳，增加一项不会超过深度。
                assign port_ready[gen_port] = (i_retire_port == C_PORT) && (count_extended < C_DEPTH_VALUE); // 不借用同拍排空产生的新空间。
                assign flag_accept = i_rstn && i_retire_valid && port_ready[gen_port]; // 每通道最多一个被选端口接纳元数据。
                assign flag_publish = batch_count != 3'd0; // 零项不能被误编码为一个信用返回。
                assign head_vc = head_metadata[1:0]; // 原 VC 的固定切片，不重编码 Pool 来源。
                assign o_pending_count[gen_port*C_COUNT_WIDTH +: C_COUNT_WIDTH] = cnt_pending; // 调试数量不计已注册的在途输出批次。
                assign o_credit_valid[gen_port] = reg_valid_o; // 返回总线有效必须保持注册边界。
                assign o_credit_pool[gen_port] = reg_pool_o; // 返回原始保存的信用类型。
                assign o_credit_vc[gen_port*2 +: 2] = reg_vc_o; // 返回原始保存的 VC。
                assign o_credit_num[gen_port*2 +: 2] = reg_num_o; // 数量编码不随本地输入组合跳变。
                for (gen_head = 0; gen_head < 4; gen_head = gen_head+1) begin : gen_heads // 只观察最多四个可合并的旧队首项。
                    localparam [4:0] C_HEAD_INDEX = gen_head; // 当前队首偏移的显式宽度常量。
                    if (gen_head < C_DEPTH) begin : gen_present // 固定切片只生成实际存在的存储地址。
                        assign head_metadata[gen_head*3 +: 3] = saved_metadata[gen_head*3 +: 3]; // 读取真实保存的三位记录。
                    end else begin : gen_absent // 深度不足四时禁止越界引用数组。
                        assign head_metadata[gen_head*3 +: 3] = 3'b000; // 无效观察槽的数据不影响合批资格。
                    end // 结束队首观察槽边界分支。
                    assign head_equal[gen_head] = (count_extended > C_HEAD_INDEX) && (head_metadata[gen_head*3 +: 3] == head_metadata[2:0]); // 有效且全部三位一致才能加入前缀。
                end // 结束最多四项的队首比较。
                always @(*) begin // 从沿前队列计算相邻同类的最长合法批次。
                    batch_count = 3'd0; // 未获许可或队列为空时不发布。
                    if (i_return_enable[gen_port] && head_equal[0]) begin // 许可只预约当前沿后的新输出周期。
                        batch_count = 3'd1; // 已存在的队首至少能归还一个信用。
                        if (head_equal[1]) batch_count = 3'd2; // 第二项也同类时可归还两个。
                        if (head_equal[1] && head_equal[2]) batch_count = 3'd3; // 不能跳过不同类的第二项直接合并第三项。
                        if (&head_equal[3:1]) batch_count = 3'd4; // 连续四项同类才使用最大批次。
                    end // 结束有资格旧队首的批次选择。
                end // 结束组合最长前缀计算。
                always @(posedge i_clk) begin // 单独保存本端口队列有效记录数量。
                    if (!i_rstn) cnt_pending <= {C_COUNT_WIDTH{1'b0}}; // 复位清除全部待返回记录。
                    else cnt_pending <= count_next; // 保存受空间和合法批次资格限制的计数。
                end // 结束本端口占用计数寄存器。
                for (gen_slot = 0; gen_slot < C_SLOT_LIMIT; gen_slot = gen_slot+1) begin : gen_slots // 为每个三位元数据槽生成实际寄存器。
                    localparam [4:0] C_SLOT_INDEX = gen_slot; // 本槽与幸存长度比较时使用无符号五位索引。
                    reg [2:0] reg_saved; // 此物理槽保存一项原始 Pool 和 VC。
                    wire [2:0] shift_one, shift_two, shift_three, shift_four; // 常量候选地址避免可越界的动态读索引。
                    assign saved_metadata[gen_slot*3 +: 3] = reg_saved; // 公开给同端口的队首和移位逻辑读取。
                    if (gen_slot+1 < C_DEPTH) begin : gen_one // 仅引用实际存在的后继一号槽。
                        assign shift_one = saved_metadata[(gen_slot+1)*3 +: 3]; // 单项出队后的本槽候选内容。
                    end else begin : gen_no_one // 不存在的后继一号槽补零。
                        assign shift_one = 3'b000; // 无效尾部不能泄漏旧元信息。
                    end // 结束后继一号槽边界选择。
                    if (gen_slot+2 < C_DEPTH) begin : gen_two // 仅引用实际存在的后继二号槽。
                        assign shift_two = saved_metadata[(gen_slot+2)*3 +: 3]; // 两项出队后的本槽候选内容。
                    end else begin : gen_no_two // 不存在的后继二号槽补零。
                        assign shift_two = 3'b000; // 无效尾部维持确定数据。
                    end // 结束后继二号槽边界选择。
                    if (gen_slot+3 < C_DEPTH) begin : gen_three // 仅引用实际存在的后继三号槽。
                        assign shift_three = saved_metadata[(gen_slot+3)*3 +: 3]; // 三项出队后的本槽候选内容。
                    end else begin : gen_no_three // 不存在的后继三号槽补零。
                        assign shift_three = 3'b000; // 无效尾部不构成有效记录。
                    end // 结束后继三号槽边界选择。
                    if (gen_slot+4 < C_DEPTH) begin : gen_four // 仅引用实际存在的后继四号槽。
                        assign shift_four = saved_metadata[(gen_slot+4)*3 +: 3]; // 四项出队后的本槽候选内容。
                    end else begin : gen_no_four // 不存在的后继四号槽补零。
                        assign shift_four = 3'b000; // 超过存储边界的候选显式补零。
                    end // 结束后继四号槽边界选择。
                    always @(posedge i_clk) begin // 单独更新此三位元数据寄存器。
                        if (!i_rstn) reg_saved <= 3'b000; // 复位清除真实保存字段而非只清有效位。
                        else if (flag_accept && (survivors == C_SLOT_INDEX)) reg_saved <= {i_retire_pool, i_retire_vc}; // 新接受记录写在全部旧幸存记录之后。
                        else if (flag_publish) begin // 有旧批次离开时按其实际数量压紧队列。
                            case (batch_count) // 明确按一至四项批次选择后继数据。
                                3'd1: reg_saved <= shift_one; // 仅弹出一个旧记录。
                                3'd2: reg_saved <= shift_two; // 同时弹出两个同类旧记录。
                                3'd3: reg_saved <= shift_three; // 同时弹出三个同类旧记录。
                                3'd4: reg_saved <= shift_four; // 同时弹出最大四项同类记录。
                                default: reg_saved <= reg_saved; // 非发布分支不改变保存字段。
                            endcase // 结束实际批次数量的槽移位选择。
                        end // 结束有效批次的存储移位更新。
                    end // 结束当前元数据槽的同步寄存器。
                end // 结束本端口全部元数据存储展开。
                always @(posedge i_clk) begin // 单独注册原生批次有效信号。
                    if (!i_rstn) reg_valid_o <= 1'b0; // 同步复位取消可见信用批次。
                    else reg_valid_o <= flag_publish; // 已许可的旧记录在沿后形成总线承诺。
                end // 结束批次有效输出寄存器。
                always @(posedge i_clk) begin // 单独注册队首保存的信用类型。
                    if (!i_rstn) reg_pool_o <= 1'b0; // 复位时输出类型确定为零。
                    else reg_pool_o <= flag_publish && head_metadata[2]; // 无效周期清零，绝不重推断信用类型。
                end // 结束 Pool 输出寄存器。
                always @(posedge i_clk) begin // 单独注册队首保存的原 VC。
                    if (!i_rstn) reg_vc_o <= 2'b00; // 复位不保留旧 VC 字段。
                    else if (flag_publish) reg_vc_o <= head_vc; // Pool 和专用信用均回放同一份原 VC。
                    else reg_vc_o <= 2'b00; // 无效输出周期元数据清零。
                end // 结束 VC 输出寄存器。
                always @(posedge i_clk) begin // 单独寄存实际批次数量减一编码。
                    if (!i_rstn) reg_num_o <= 2'b00; // 复位保持无有效批次的零编码。
                    else begin // 数量编码显式枚举，避免依赖窄位减法回绕。
                        case (batch_count) // 零项由 valid 抑制，其余数量使用标准减一编码。
                            3'd2: reg_num_o <= 2'd1; // 两个信用编码为一。
                            3'd3: reg_num_o <= 2'd2; // 三个信用编码为二。
                            3'd4: reg_num_o <= 2'd3; // 四个信用编码为三。
                            default: reg_num_o <= 2'd0; // 一个信用或无效周期编码为零。
                        endcase // 结束明确的信用数量编码选择。
                    end // 结束非复位周期的编码寄存更新。
                end // 结束批次数量输出寄存器。
            end else begin : gen_unused // 未启用端口没有存储、接纳或返回。
                assign port_ready[gen_port] = 1'b0; // 非法端口地址不会别名到已启用队列。
                assign o_pending_count[gen_port*C_COUNT_WIDTH +: C_COUNT_WIDTH] = {C_COUNT_WIDTH{1'b0}}; // 未用端口占用恒零。
                assign o_credit_valid[gen_port] = 1'b0; // 未用端口永不发布信用。
                assign o_credit_pool[gen_port] = 1'b0; // 未用端口类型恒零。
                assign o_credit_vc[gen_port*2 +: 2] = 2'b00; // 未用端口 VC 字段恒零。
                assign o_credit_num[gen_port*2 +: 2] = 2'b00; // 未用端口数量字段恒零。
            end // 结束有效与未用端口结构选择。
        end // 结束四端口原生接口的展开。
    endgenerate // 结束正常信用元数据队列结构。
endmodule // 结束 upli_credit_return_queue 正常返回模块。
