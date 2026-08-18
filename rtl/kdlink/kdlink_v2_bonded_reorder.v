module kdlink_v2_bonded_reorder ( // 定义双 slice 全局 packet/flit 顺序恢复窗口
    input wire clk_i, // 接收 bonded port 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [1:0] accept_valid_i, // 接收两个 slice 的 CRC 通过 flit
    input wire [191:0] accept_header_i, // 接收两个 slice 的对齐 header
    input wire [1023:0] accept_payload_i, // 接收两个 slice 的对齐 payload
    input wire [13:0] accept_payload_bytes_i, // 接收两个 slice 的有效字节数
    output wire [1:0] output_valid_o, // 输出最多两个连续有序 flit
    output wire [191:0] output_header_o, // 输出两个有序 header
    output wire [1023:0] output_payload_o, // 输出两个有序 payload
    output wire [13:0] output_payload_bytes_o, // 输出两个有序有效字节数
    output wire [8:0] occupancy_o, // 输出六十四 flit 窗口占用数
    output reg duplicate_drop_o, // 指示 duplicate 或 stale flit 被丢弃
    output reg window_error_o // 指示超窗或槽位冲突
); // 结束端口声明
    reg slot_valid_q [0:63]; // 保存四 packet 共六十四 flit reorder slot 有效位
    reg [11:0] packet_seq_q [0:63]; // 保存 slot packet sequence tag
    reg [5:0] flit_seq_q [0:63]; // 保存 slot flit sequence tag
    reg [95:0] header_q [0:63]; // 保存 slot header
    reg [511:0] payload_q [0:63]; // 保存 slot payload
    reg [6:0] payload_bytes_q [0:63]; // 保存 slot payload 字节数
    reg [3:0] expected_pair_low_q; // 保存双 packet pair index 低四位
    reg [6:0] expected_pair_high_q; // 保存双 packet pair index 高七位
    reg [6:0] expected_pair_high_next_q; // 预计算 pair 高段下一值以隔离完成判定和加法
    reg expected_pair_wrap_q; // 保存当前 pair 低段处于回卷值以切断高段进位路径
    reg [5:0] expected_flit0_q; // 保存当前偶 context 下一 flit sequence
    reg [5:0] expected_flit1_q; // 保存当前奇 context 下一 flit sequence
    reg context0_done_q; // 标记偶 context 已到 EOP
    reg context1_done_q; // 标记奇 context 已到 EOP
    reg [8:0] occupancy_q; // 保存 reorder window occupancy
    reg [1:0] output_count_q; // 保存上一周期已提交 flit 数以隔离匹配和 occupancy 算术
    reg [1:0] output_valid_q; // 保存注册化双 context 输出有效位
    reg [191:0] output_header_q; // 保存注册化双 context 输出 header
    reg [1023:0] output_payload_q; // 保存注册化双 context 输出 payload
    reg [13:0] output_payload_bytes_q; // 保存注册化双 context 输出有效字节数
    reg [1:0] accept_valid_q; // 保存输入检查流水有效位
    reg [191:0] accept_header_q; // 保存输入检查流水 header
    reg [1023:0] accept_payload_q; // 保存输入检查流水 payload
    reg [13:0] accept_payload_bytes_q; // 保存输入检查流水字节数
    reg [1:0] write_valid_q; // 保存验证完成的双 lane 写许可
    reg [1:0] write_unique_q; // 保存双 lane occupancy 新增许可
    reg [127:0] write_onehot_q; // 保存双 lane 注册 onehot 地址
    reg [191:0] write_header_q; // 保存待写双 lane header
    reg [1023:0] write_payload_q; // 保存待写双 lane payload
    reg [13:0] write_payload_bytes_q; // 保存待写双 lane 字节数
    wire [11:0] accept0_packet_seq; // 提取 slice 零 packet sequence
    wire [11:0] accept1_packet_seq; // 提取 slice 一 packet sequence
    wire [5:0] accept0_flit_seq; // 提取 slice 零 flit sequence
    wire [5:0] accept1_flit_seq; // 提取 slice 一 flit sequence
    wire [5:0] accept0_index; // 形成 slice 零直接映射索引
    wire [5:0] accept1_index; // 形成 slice 一直接映射索引
    wire [63:0] accept0_onehot; // 形成 slice 零写 slot onehot
    wire [63:0] accept1_onehot; // 形成 slice 一写 slot onehot
    wire [5:0] output0_index; // 形成偶 context flit 索引
    wire [5:0] output1_index; // 形成奇 context flit 索引
    wire [11:0] accept0_distance; // 计算 slice 零 packet 前向距离
    wire [11:0] accept1_distance; // 计算 slice 一 packet 前向距离
    wire [11:0] expected_packet_seq; // 组合当前偶 context packet sequence
    wire output0_match; // 标记第一预期 flit 已在窗口
    wire output1_match; // 标记第二预期 flit 已在窗口
    wire [11:0] second_packet_seq; // 保存奇 context packet sequence
    wire accept0_existing_same; // 标记 slice 零重复命中
    wire accept1_existing_same; // 标记 slice 一重复命中
    wire accept_pair_same; // 标记两个输入是同一 flit
    wire accept_pair_collision; // 标记两个输入映射同槽但 identity 不同
    wire accept0_stale; // 标记 slice 零输入落后 expected
    wire accept1_stale; // 标记 slice 一输入落后 expected
    wire accept0_too_far; // 标记 slice 零输入超出十六 packet 窗口
    wire accept1_too_far; // 标记 slice 一输入超出十六 packet 窗口
    wire accept0_slot_busy; // 标记 slice 零索引被其他 identity 占用
    wire accept1_slot_busy; // 标记 slice 一索引被其他 identity 占用
    wire accept0_slot_releasing; // 标记 slice 零目标槽位将在本拍提交释放
    wire accept1_slot_releasing; // 标记 slice 一目标槽位将在本拍提交释放
    wire accept0_fire; // 指示 slice 零输入写入窗口
    wire accept1_fire; // 指示 slice 一输入写入窗口
    wire accept0_unique; // 指示 slice 零输入新增 occupancy
    wire accept1_unique; // 指示 slice 一输入新增 occupancy
    wire context0_complete_now; // 标记偶 context 本周期后完成
    wire context1_complete_now; // 标记奇 context 本周期后完成
    integer reset_index; // 提供固定 reorder slot 复位索引
    assign accept0_packet_seq = accept_header_q[81:70]; // 提取流水 lane 零 packet sequence
    assign accept1_packet_seq = accept_header_q[177:166]; // 提取流水 lane 一 packet sequence
    assign accept0_flit_seq = accept_header_q[87:82]; // 提取流水 lane 零 flit sequence
    assign accept1_flit_seq = accept_header_q[183:178]; // 提取流水 lane 一 flit sequence
    assign accept0_index = {accept0_packet_seq[1:0], accept0_flit_seq[3:0]}; // 映射 lane 零到六十四槽
    assign accept1_index = {accept1_packet_seq[1:0], accept1_flit_seq[3:0]}; // 映射 lane 一到六十四槽
    assign accept0_onehot = 64'd1 << accept0_index; // 将 lane 零地址提前解码为 onehot
    assign accept1_onehot = 64'd1 << accept1_index; // 将 lane 一地址提前解码为 onehot
    assign expected_packet_seq = {expected_pair_high_q, expected_pair_low_q, 1'b0}; // 从分段 pair counter 形成偶 packet sequence
    assign second_packet_seq = {expected_pair_high_q, expected_pair_low_q, 1'b1}; // 奇 context 固定为相邻 packet
    assign output0_index = {expected_packet_seq[1:0], expected_flit0_q[3:0]}; // 映射偶 context 当前 flit
    assign output1_index = {second_packet_seq[1:0], expected_flit1_q[3:0]}; // 映射奇 context 当前 flit
    assign output0_match = !context0_done_q && slot_valid_q[output0_index]; // 直接映射和四 packet 窗口保证有效槽位 identity 唯一
    assign output1_match = !context1_done_q && slot_valid_q[output1_index]; // 写入冲突检查保证奇 context 有效槽位 identity 唯一
    assign context0_complete_now = context0_done_q || (output0_match && header_q[output0_index][18]); // 汇总偶 context EOP 完成状态
    assign context1_complete_now = context1_done_q || (output1_match && header_q[output1_index][18]); // 汇总奇 context EOP 完成状态
    assign output_valid_o = output_valid_q; // 输出注册化双 context valid
    assign output_header_o = output_header_q; // 输出注册化双 context header
    assign output_payload_o = output_payload_q; // 输出注册化双 context payload
    assign output_payload_bytes_o = output_payload_bytes_q; // 输出注册化双 context 字节数
    assign occupancy_o = occupancy_q; // 输出 reorder occupancy
    assign accept0_distance = accept0_packet_seq - expected_packet_seq; // 计算 lane 零 modulo packet 距离
    assign accept1_distance = accept1_packet_seq - expected_packet_seq; // 计算 lane 一 modulo packet 距离
    assign accept0_stale = accept0_distance[11]; // 半空间高位表示 stale identity
    assign accept1_stale = accept1_distance[11]; // 半空间高位表示 stale identity
    assign accept0_slot_releasing = (output0_match && (output0_index == accept0_index)) || (output1_match && (output1_index == accept0_index)); // 检测 lane 零映射槽位本拍释放
    assign accept1_slot_releasing = (output0_match && (output0_index == accept1_index)) || (output1_match && (output1_index == accept1_index)); // 检测 lane 一映射槽位本拍释放
    assign accept0_too_far = !accept0_stale && (accept0_distance > 12'd3) && !((accept0_distance <= 12'd5) && accept0_slot_releasing); // 仅允许流水检查级复用本拍释放槽位
    assign accept1_too_far = !accept1_stale && (accept1_distance > 12'd3) && !((accept1_distance <= 12'd5) && accept1_slot_releasing); // 仅允许流水检查级复用本拍释放槽位
    assign accept0_existing_same = slot_valid_q[accept0_index] && (packet_seq_q[accept0_index] == accept0_packet_seq) && (flit_seq_q[accept0_index] == accept0_flit_seq); // 检查 lane 零重复 slot
    assign accept1_existing_same = slot_valid_q[accept1_index] && (packet_seq_q[accept1_index] == accept1_packet_seq) && (flit_seq_q[accept1_index] == accept1_flit_seq); // 检查 lane 一重复 slot
    assign accept0_slot_busy = slot_valid_q[accept0_index] && !accept0_existing_same && !accept0_slot_releasing; // 忽略本拍提交释放的 lane 零 slot
    assign accept1_slot_busy = slot_valid_q[accept1_index] && !accept1_existing_same && !accept1_slot_releasing; // 忽略本拍提交释放的 lane 一 slot
    assign accept_pair_same = accept_valid_q[0] && accept_valid_q[1] && (accept0_packet_seq == accept1_packet_seq) && (accept0_flit_seq == accept1_flit_seq); // 检查流水双 lane duplicate
    assign accept_pair_collision = accept_valid_q[0] && accept_valid_q[1] && (accept0_index == accept1_index) && !accept_pair_same; // 检查流水双 lane slot collision
    assign accept0_fire = accept_valid_q[0] && !accept0_stale && !accept0_too_far && !accept0_slot_busy && (accept0_flit_seq < 6'd16); // 仅向空闲或本拍释放地址写入 lane 零 flit
    assign accept1_fire = accept_valid_q[1] && !accept1_stale && !accept1_too_far && !accept1_slot_busy && !accept_pair_same && !accept_pair_collision && (accept1_flit_seq < 6'd16); // 仅向空闲或本拍释放地址写入 lane 一 flit
    assign accept0_unique = accept0_fire && !accept0_existing_same && !accept0_slot_busy; // 只对新 lane 零 identity 增加 occupancy
    assign accept1_unique = accept1_fire && !accept1_existing_same && !accept1_slot_busy; // 只对新 lane 一 identity 增加 occupancy
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 reorder 窗口和 expected identity
        if (!rst_n_i) begin // 检测复位有效
            expected_pair_low_q <= 4'd0; // 从 pair index 低位零开始
            expected_pair_high_q <= 7'd0; // 从 pair index 高位零开始
            expected_pair_high_next_q <= 7'd1; // 初始化 pair 高段预计算值
            expected_pair_wrap_q <= 1'b0; // 清除 pair 低段回卷状态
            expected_flit0_q <= 6'd0; // 从偶 context flit 零开始
            expected_flit1_q <= 6'd0; // 从奇 context flit 零开始
            context0_done_q <= 1'b0; // 清除偶 context 完成状态
            context1_done_q <= 1'b0; // 清除奇 context 完成状态
            occupancy_q <= 9'd0; // 清零窗口 occupancy
            output_count_q <= 2'd0; // 清零延迟提交计数
            output_valid_q <= 2'b00; // 清除注册化输出有效位
            output_header_q <= 192'd0; // 清零注册化输出 header
            output_payload_q <= 1024'd0; // 清零注册化输出 payload
            output_payload_bytes_q <= 14'd0; // 清零注册化输出字节数
            accept_valid_q <= 2'b00; // 清除输入检查流水有效位
            accept_header_q <= 192'd0; // 清零输入检查流水 header
            accept_payload_q <= 1024'd0; // 清零输入检查流水 payload
            accept_payload_bytes_q <= 14'd0; // 清零输入检查流水字节数
            write_valid_q <= 2'b00; // 清除验证后写许可
            write_unique_q <= 2'b00; // 清除验证后 occupancy 许可
            write_onehot_q <= 128'd0; // 清零注册 onehot 地址
            write_header_q <= 192'd0; // 清零待写 header
            write_payload_q <= 1024'd0; // 清零待写 payload
            write_payload_bytes_q <= 14'd0; // 清零待写字节数
            duplicate_drop_o <= 1'b0; // 清除 duplicate 脉冲
            window_error_o <= 1'b0; // 清除 window error 脉冲
            for (reset_index = 0; reset_index < 64; reset_index = reset_index + 1) slot_valid_q[reset_index] <= 1'b0; // 清除全部 slot 有效位
        end else begin // 处理正常 reorder 更新
            expected_pair_high_next_q <= expected_pair_high_q + 7'd1; // 独立预计算高段递增结果
            accept_valid_q <= accept_valid_i; // 注册下一组双 slice 输入有效位
            accept_header_q <= accept_header_i; // 注册下一组双 slice header
            accept_payload_q <= accept_payload_i; // 注册下一组双 slice payload
            accept_payload_bytes_q <= accept_payload_bytes_i; // 注册下一组双 slice 字节数
            write_valid_q <= {accept1_fire, accept0_fire}; // 注册协议验证完成的双 lane 写许可
            write_unique_q <= {accept1_unique, accept0_unique}; // 注册精确 occupancy 新增许可
            write_onehot_q <= {accept1_onehot, accept0_onehot}; // 注册双 lane onehot 写地址
            write_header_q <= accept_header_q; // 将验证后的 header 传入 slot 写级
            write_payload_q <= accept_payload_q; // 将验证后的 payload 传入 slot 写级
            write_payload_bytes_q <= accept_payload_bytes_q; // 将验证后的字节数传入 slot 写级
            output_count_q <= {1'b0, output0_match} + {1'b0, output1_match}; // 注册本周期提交数量
            output_valid_q <= {output1_match, output0_match}; // 注册本周期双 context 提交有效位
            if (output0_match) begin // 捕获偶 context 有序输出
                output_header_q[95:0] <= header_q[output0_index]; // 注册偶 context header
                output_payload_q[511:0] <= payload_q[output0_index]; // 注册偶 context payload
                output_payload_bytes_q[6:0] <= payload_bytes_q[output0_index]; // 注册偶 context 字节数
            end // 结束偶 context 输出捕获
            if (output1_match) begin // 捕获奇 context 有序输出
                output_header_q[191:96] <= header_q[output1_index]; // 注册奇 context header
                output_payload_q[1023:512] <= payload_q[output1_index]; // 注册奇 context payload
                output_payload_bytes_q[13:7] <= payload_bytes_q[output1_index]; // 注册奇 context 字节数
            end // 结束奇 context 输出捕获
            duplicate_drop_o <= (accept_valid_q[0] && (accept0_stale || accept0_existing_same)) || (accept_valid_q[1] && (accept1_stale || accept1_existing_same)) || accept_pair_same; // 报告流水 stale 和 duplicate drop
            window_error_o <= (accept_valid_q[0] && (accept0_too_far || accept0_slot_busy || (accept0_flit_seq >= 6'd16))) || (accept_valid_q[1] && (accept1_too_far || accept1_slot_busy || (accept1_flit_seq >= 6'd16))) || accept_pair_collision; // 报告流水超窗和槽位冲突
            for (reset_index = 0; reset_index < 64; reset_index = reset_index + 1) begin // 按 onehot 更新固定 slot 避免可变地址写 decoder 关键路径
                if (write_valid_q[0] && write_onehot_q[reset_index]) begin // 检查注册 lane 零 onehot 命中当前 slot
                    slot_valid_q[reset_index] <= 1'b1; // 标记 lane 零 slot 有效
                    packet_seq_q[reset_index] <= write_header_q[81:70]; // 保存 lane 零 packet tag
                    flit_seq_q[reset_index] <= write_header_q[87:82]; // 保存 lane 零 flit tag
                    header_q[reset_index] <= write_header_q[95:0]; // 保存 lane 零注册 header
                    payload_q[reset_index] <= write_payload_q[511:0]; // 保存 lane 零注册 payload
                    payload_bytes_q[reset_index] <= write_payload_bytes_q[6:0]; // 保存 lane 零注册字节数
                end // 结束 lane 零 onehot 写入
                if (write_valid_q[1] && write_onehot_q[64+reset_index]) begin // 检查注册 lane 一 onehot 命中当前 slot
                    slot_valid_q[reset_index] <= 1'b1; // 标记 lane 一 slot 有效
                    packet_seq_q[reset_index] <= write_header_q[177:166]; // 保存 lane 一 packet tag
                    flit_seq_q[reset_index] <= write_header_q[183:178]; // 保存 lane 一 flit tag
                    header_q[reset_index] <= write_header_q[191:96]; // 保存 lane 一注册 header
                    payload_q[reset_index] <= write_payload_q[1023:512]; // 保存 lane 一注册 payload
                    payload_bytes_q[reset_index] <= write_payload_bytes_q[13:7]; // 保存 lane 一注册字节数
                end // 结束 lane 一 onehot 写入
                if ((output0_match && (output0_index == reset_index[5:0])) || (output1_match && (output1_index == reset_index[5:0]))) slot_valid_q[reset_index] <= 1'b0; // 最后释放已提交 slot 保证同时 duplicate 不重占
            end // 结束固定 slot onehot 更新
            if (context0_complete_now && context1_complete_now) begin // 检查相邻双 packet context 均完成
                if (expected_pair_wrap_q) begin // 使用已注册回卷状态避免低段比较穿越高段加法
                    expected_pair_low_q <= 4'd0; // 回卷 pair counter 低位
                    expected_pair_high_q <= expected_pair_high_next_q; // 使用预计算结果推进七位高段
                    expected_pair_wrap_q <= 1'b0; // 离开低段回卷值
                end else begin // 处理普通 pair counter 推进
                    expected_pair_low_q <= expected_pair_low_q + 4'd1; // 推进四位低段
                    if (expected_pair_low_q == 4'hE) expected_pair_wrap_q <= 1'b1; // 提前登记下一 pair 的回卷状态
                end // 结束分段 pair counter 推进
                expected_flit0_q <= 6'd0; // 复位下一偶 context flit
                expected_flit1_q <= 6'd0; // 复位下一奇 context flit
                context0_done_q <= 1'b0; // 打开下一偶 context
                context1_done_q <= 1'b0; // 打开下一奇 context
            end else begin // 处理双 context 独立推进
                if (output0_match && header_q[output0_index][18]) context0_done_q <= 1'b1; // 标记偶 context EOP
                else if (output0_match) expected_flit0_q <= expected_flit0_q + 6'd1; // 推进偶 context flit
                if (output1_match && header_q[output1_index][18]) context1_done_q <= 1'b1; // 标记奇 context EOP
                else if (output1_match) expected_flit1_q <= expected_flit1_q + 6'd1; // 推进奇 context flit
            end // 结束双 context 推进
            occupancy_q <= occupancy_q + {{8{1'b0}}, write_unique_q[0]} + {{8{1'b0}}, write_unique_q[1]} - {{7{1'b0}}, output_count_q}; // 按注册事件更新精确窗口 occupancy
        end // 结束正常 reorder 更新
    end // 结束 reorder 时序逻辑
endmodule // 结束双 slice reorder 窗口
