`timescale 1ns/1ps // 定义Core Plane数字仿真的时间单位，不参与综合功能。
`default_nettype none // 禁止隐式网络隐藏Group矩阵连接错误。
module switch_core_plane_8x8 #( // 实现一个具有逐包所有权的八输入八输出Group级交换平面。
    parameter integer DATA_WIDTH = 512, // 指定每个内部flit的数据位宽，必须由集成配置保持为正数。
    parameter integer META_WIDTH = 128 // 指定每个内部flit的元数据位宽，完整路由在SOP前已由入口生成。
) ( // 所有端口位于同一个已同步的fabric时钟域。
    input wire clk, // 在上升沿更新仲裁保持、逐包owner和轮询指针。
    input wire i_rstn, // 同步低有效复位清除全部路径所有权和公平状态。
    input wire [7:0] i_valid, // 每个Source Group提供一个ready/valid输入流。
    input wire [7:0] i_route_valid, // 入口查表结果有效位使非法目的在本级失败关闭。
    output reg [7:0] o_ready, // 每个输入只有被其目标出口选中时才能观察对应ready。
    input wire [8*DATA_WIDTH-1:0] i_data, // 八个输入数据按source编号从低位开始扁平排列。
    input wire [8*META_WIDTH-1:0] i_meta, // 八个输入元数据与数据保持相同source排列。
    input wire [23:0] i_dst_group, // 每个输入使用三位目标Group编号选择唯一出口。
    input wire [7:0] i_sop, // SOP声明新packet并允许建立新的出口owner。
    input wire [7:0] i_eop, // EOP仅在真实输出握手后释放owner并推进轮询。
    output reg [7:0] o_valid, // 每个出口独立声明已选择输入的有效状态。
    input wire [7:0] i_ready, // 每个Destination Group独立提供下游接纳能力。
    output reg [8*DATA_WIDTH-1:0] o_data, // 每个出口转发完整数据且在停顿期间保持同一source。
    output reg [8*META_WIDTH-1:0] o_meta, // 每个出口原样转发内部元数据。
    output reg [7:0] o_sop, // 每个出口转发被选source的SOP标志。
    output reg [7:0] o_eop, // 每个出口转发被选source的EOP标志。
    output reg [7:0] o_route_error, // 非owner输入的无效路由被拒绝并形成逐source诊断。
    output reg [7:0] o_protocol_error, // 没有已建owner的非SOP输入被拒绝并形成诊断。
    output wire [7:0] o_owner_valid, // 暴露已真实接纳且尚未完成EOP的packet owner状态。
    output wire o_quiescent
); // 结束Core Plane扁平ready/valid接口定义。
    localparam [3:0] GROUP_COUNT = 4'd8; // 固定本模块为八个Source Group和八个Destination Group。
    reg [7:0] owner_valid_q; // 每个出口保存一个已接受多beat packet的owner有效位。
    reg [2:0] owner_source_q [0:7]; // 每个出口保存被锁定的Source Group编号。
    reg [7:0] hold_valid_q; // 每个出口保存尚未握手的首次仲裁结果以满足stall稳定性。
    reg [2:0] hold_source_q [0:7]; // 每个出口保存停顿期间不可替换的Source Group编号。
    reg [2:0] rr_pointer_q [0:7]; // 每个出口保存下一次新packet仲裁的起始Source Group。
    reg [7:0] selected_valid; // 组合逻辑为每个出口标记当前是否存在合法选择。
    reg [2:0] selected_source [0:7]; // 组合逻辑为每个出口保存owner、hold或新仲裁source。
    reg [7:0] source_locked; // 标记已属于任一owner或hold的source以判断新SOP合法性。
    integer egress_index; // 固定八出口循环在综合时展开为独立仲裁逻辑。
    integer source_index; // 固定八source循环用于建立锁定集合与输出映射。
    integer scan_offset; // 固定八项轮询扫描用于寻找第一个eligible source。
    integer candidate_source; // 保存轮询加法后的0至7候选source索引。
    integer pointer_value; // 将三位轮询寄存器显式扩展为整数后再执行索引加法。
    assign o_owner_valid = owner_valid_q; // 只报告已握手packet，不把预握手stall hold冒充owner。
    assign o_quiescent = !(|owner_valid_q) && !(|hold_valid_q);
    always @(*) begin // 完整计算路由错误、八个仲裁选择和扁平输出以避免锁存器。
        o_ready = 8'h00; // 默认所有未选输入保持反压。
        o_valid = 8'h00; // 默认所有未选出口无有效数据。
        o_data = {(8*DATA_WIDTH){1'b0}}; // 默认未选出口数据为确定零。
        o_meta = {(8*META_WIDTH){1'b0}}; // 默认未选出口元数据为确定零。
        o_sop = 8'h00; // 默认未选出口不声明packet开始。
        o_eop = 8'h00; // 默认未选出口不声明packet结束。
        o_route_error = 8'h00; // 默认没有输入路由错误。
        o_protocol_error = 8'h00; // 默认没有输入packet边界错误。
        selected_valid = 8'h00; // 默认八个出口都没有候选source。
        source_locked = 8'h00; // 每次组合求值重新建立source锁定集合。
        scan_offset = 0; // owner/hold覆盖全部出口时循环不执行，仍需给组合临时量确定默认值。
        candidate_source = 0; // 为组合扫描临时量提供完整默认赋值以避免锁存器。
        pointer_value = 0; // 为轮询指针扩展临时量提供完整默认赋值。
        for (egress_index = 0; egress_index < GROUP_COUNT; egress_index = egress_index + 1) begin // 扫描全部出口的持久状态。
            selected_source[egress_index] = 3'd0; // 为没有候选的出口提供确定source索引。
            if (owner_valid_q[egress_index]) begin // 已接受packet拥有最高选择优先级。
                source_locked[owner_source_q[egress_index]] = 1'b1; // owner source不能参与其它出口的新仲裁。
            end // 结束已接受packet的source锁定。
            if (hold_valid_q[egress_index]) begin // 尚未握手的stall选择同样必须排他保持。
                source_locked[hold_source_q[egress_index]] = 1'b1; // hold source不能被其它出口抢走。
            end // 结束预握手stall source锁定。
        end // 完成全部持久source锁定集合。
        for (source_index = 0; source_index < GROUP_COUNT; source_index = source_index + 1) begin // 逐source执行失败关闭资格检查。
            if (i_valid[source_index] && !source_locked[source_index] && !i_route_valid[source_index]) begin // 新输入没有有效indexed route结果。
                o_route_error[source_index] = 1'b1; // 无效route不参与仲裁且不获得ready。
            end // 结束无效route诊断。
            if (i_valid[source_index] && !source_locked[source_index] && i_route_valid[source_index] && !i_sop[source_index]) begin // 新输入必须从SOP开始。
                o_protocol_error[source_index] = 1'b1; // 无owner body beat失败关闭以防packet中途注入。
            end // 结束packet边界诊断。
        end // 完成全部输入合法性检查。
        for (egress_index = 0; egress_index < GROUP_COUNT; egress_index = egress_index + 1) begin // 每个Destination Group独立选择一个source。
            if (owner_valid_q[egress_index]) begin // 已接受packet固定使用保存的出口路径。
                selected_valid[egress_index] = 1'b1; // owner存在时不运行新的轮询仲裁。
                selected_source[egress_index] = owner_source_q[egress_index]; // 包内beat继续来自同一source。
            end else if (hold_valid_q[egress_index]) begin // 未握手选择必须先于新竞争者。
                selected_valid[egress_index] = 1'b1; // hold保证输出在stall期间不会换源。
                selected_source[egress_index] = hold_source_q[egress_index]; // 使用保存的首次仲裁结果。
            end else begin // 空闲出口可以从轮询指针开始寻找新SOP。
                pointer_value = {29'd0, rr_pointer_q[egress_index]}; // 在加法前将当前三位指针显式无符号扩展为三十二位。
                for (scan_offset = 0; scan_offset < GROUP_COUNT; scan_offset = scan_offset + 1) begin // 最多扫描八个source且不会永久跳过请求。
                    candidate_source = pointer_value + scan_offset; // 使用同宽整数形成当前轮询候选的线性编号。
                    if (candidate_source >= 8) candidate_source = candidate_source - 8; // 将候选编号明确回绕到0至7。
                    if (!selected_valid[egress_index] && i_valid[candidate_source] && i_route_valid[candidate_source] && // 只接受存在有效route的新输入。
                        i_sop[candidate_source] && !source_locked[candidate_source] && // 新路径必须从未被其它路径占用的SOP开始。
                        i_dst_group[candidate_source*3 +: 3] == egress_index[2:0]) begin // 输入声明的目标必须等于当前出口。
                        selected_valid[egress_index] = 1'b1; // 第一个eligible请求赢得本轮新packet仲裁。
                        selected_source[egress_index] = candidate_source[2:0]; // 保存获胜source供输出映射和时序状态使用。
                    end // 后续请求保留等待以实现确定轮询优先级。
                end // 结束当前出口的完整轮询扫描。
            end // 结束owner、hold和新仲裁三级选择。
            if (selected_valid[egress_index]) begin // 合法选择建立唯一source到出口的数据通路。
                o_valid[egress_index] = i_valid[selected_source[egress_index]]; // owner气泡不会释放路径但出口valid可暂时为零。
                o_data[egress_index*DATA_WIDTH +: DATA_WIDTH] = i_data[selected_source[egress_index]*DATA_WIDTH +: DATA_WIDTH]; // 转发完整数据位。
                o_meta[egress_index*META_WIDTH +: META_WIDTH] = i_meta[selected_source[egress_index]*META_WIDTH +: META_WIDTH]; // 转发完整元数据位。
                o_sop[egress_index] = i_sop[selected_source[egress_index]]; // 转发实际source的SOP状态。
                o_eop[egress_index] = i_eop[selected_source[egress_index]]; // 转发实际source的EOP状态。
                o_ready[selected_source[egress_index]] = i_ready[egress_index]; // 只有所选source收到目标出口ready。
            end // 没有选择的出口继续保持确定零。
        end // 完成八个出口的独立组合映射。
        if (!i_rstn) begin // 同步复位有效期间组合接口也立即失败关闭。
            o_ready = 8'h00; // 复位期间不接纳任何输入。
            o_valid = 8'h00; // 复位期间不发送任何输出。
            o_route_error = 8'h00; // 复位期间不报告运行时route错误。
            o_protocol_error = 8'h00; // 复位期间不报告运行时packet错误。
        end // 结束复位期间组合抑制。
    end // 结束Core Plane组合仲裁和数据映射。
    genvar state_index; // 每个生成索引对应一个独立Destination Group状态切片。
    generate // 将八个出口状态展开为互不共享写端的时序块。
        for (state_index = 0; state_index < 8; state_index = state_index + 1) begin : g_output_state // 固定展开八套owner、hold和轮询寄存器。
            always @(posedge clk) begin // 当前出口只在单一fabric上升沿更新自己的状态。
                if (!i_rstn) begin // 同步复位清除当前出口的未完成packet和公平历史。
                    owner_valid_q[state_index] <= 1'b0; // 复位后当前出口没有已接受packet owner。
                    owner_source_q[state_index] <= 3'd0; // 无效owner source复位为确定零。
                    hold_valid_q[state_index] <= 1'b0; // 复位后当前出口没有预握手stall选择。
                    hold_source_q[state_index] <= 3'd0; // 无效hold source复位为确定零。
                    rr_pointer_q[state_index] <= 3'd0; // 当前出口首次从source0开始轮询。
                end else if (owner_valid_q[state_index]) begin // 已接受多beat packet只能等待自身beat或EOP。
                    if (o_valid[state_index] && i_ready[state_index] && o_eop[state_index]) begin // EOP真实握手完成packet。
                        owner_valid_q[state_index] <= 1'b0; // 释放当前出口packet owner。
                        if (owner_source_q[state_index] == 3'd7) rr_pointer_q[state_index] <= 3'd0; // source7完成后公平指针回绕。
                        else rr_pointer_q[state_index] <= owner_source_q[state_index] + 3'd1; // 其它source完成后从下一source开始。
                    end // 非EOP握手和包内气泡都保持owner不变。
                end else if (hold_valid_q[state_index]) begin // 预握手stall路径等待下游真正接纳首拍。
                    if (o_valid[state_index] && i_ready[state_index]) begin // 保存选择的首拍现在完成真实握手。
                        hold_valid_q[state_index] <= 1'b0; // 首拍接纳后不再需要预握手hold。
                        if (o_eop[state_index]) begin // 单beat packet在同一握手完成。
                            if (hold_source_q[state_index] == 3'd7) rr_pointer_q[state_index] <= 3'd0; // source7完成后回绕轮询。
                            else rr_pointer_q[state_index] <= hold_source_q[state_index] + 3'd1; // 单beat完成后推进公平指针。
                        end else begin // 多beat packet从首拍握手开始建立正式owner。
                            owner_valid_q[state_index] <= 1'b1; // 保存路径直到后续EOP握手。
                            owner_source_q[state_index] <= hold_source_q[state_index]; // 正式owner继承停顿期间保存的source。
                        end // 结束单beat完成与多beatowner建立处理。
                    end // 尚未握手时所有hold状态保持不变。
                end else if (selected_valid[state_index] && o_valid[state_index]) begin // 空闲出口本周期产生了新的合法SOP选择。
                    if (!i_ready[state_index]) begin // 下游stall要求跨周期保存winner。
                        hold_valid_q[state_index] <= 1'b1; // 建立预握手hold保证输出稳定。
                        hold_source_q[state_index] <= selected_source[state_index]; // 保存首次仲裁source防止竞争者替换。
                    end else if (o_eop[state_index]) begin // 无stall单beat packet立即完成。
                        if (selected_source[state_index] == 3'd7) rr_pointer_q[state_index] <= 3'd0; // source7完成后回绕轮询。
                        else rr_pointer_q[state_index] <= selected_source[state_index] + 3'd1; // 单beat完成后推进公平指针。
                    end else begin // 无stall多beat packet的SOP已经被目标接纳。
                        owner_valid_q[state_index] <= 1'b1; // 从该握手开始锁定整个packet路径。
                        owner_source_q[state_index] <= selected_source[state_index]; // 保存获胜source直到EOP真实握手。
                    end // 结束新选择的stall、单beat和多beat处理。
                end // 无有效新选择时保留当前空闲与轮询状态。
            end // 结束当前Destination Group状态寄存过程。
        end // 完成八个出口状态切片生成。
    endgenerate // 结束Core Plane时序状态展开。
endmodule // 结束八输入八输出packet-atomic Core Plane实现。
`default_nettype wire // 恢复后续编译单元的默认网络规则。
