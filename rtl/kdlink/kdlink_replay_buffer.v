module kdlink_replay_buffer #( // 定义单 slice 独立 packet replay 存储器
    parameter ENTRIES = 8, // 配置保留的未确认 packet 数量
    parameter INDEX_WIDTH = 3 // 配置 replay entry 索引位宽
) ( // 开始端口声明
    input wire clk_i, // 接收 slice 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire store_start_i, // 指示当前 flit 是新 packet 首部
    input wire store_valid_i, // 指示当前 packet body 有效
    input wire [607:0] store_body_i, // 接收不含 CRC 的 header 和 payload
    input wire store_last_i, // 指示当前 flit 是 packet 尾部
    output wire store_ready_o, // 指示本地 replay 窗口可以接收
    input wire ack_valid_i, // 接收精确 packet ACK
    input wire [11:0] ack_collective_id_i, // 接收 ACK collective identity
    input wire ack_phase_i, // 接收 ACK phase identity
    input wire [11:0] ack_packet_seq_i, // 接收 ACK packet sequence
    input wire nack_valid_i, // 接收精确 packet NACK
    input wire [11:0] nack_collective_id_i, // 接收 NACK collective identity
    input wire nack_phase_i, // 接收 NACK phase identity
    input wire [11:0] nack_packet_seq_i, // 接收 NACK packet sequence
    output wire replay_valid_o, // 指示 replay flit 有效
    input wire replay_ready_i, // 接收本地健康 slice 仲裁许可
    output wire [607:0] replay_body_o, // 输出设置 retry 和 replay VC 的 packet body
    output wire replay_last_o, // 指示当前 replay flit 是 packet 尾部
    output reg retry_exhausted_o, // 指示同一 packet 已达到七次 retry
    output wire [INDEX_WIDTH:0] occupancy_o // 输出当前 replay entry 占用数
); // 结束端口声明
    reg [607:0] body_mem [0:ENTRIES*16-1]; // 保存每 entry 最多十六个 flit
    reg entry_valid_q [0:ENTRIES-1]; // 保存 entry 有效状态
    reg entry_complete_q [0:ENTRIES-1]; // 保存 packet 已完整写入状态
    reg [11:0] collective_id_q [0:ENTRIES-1]; // 保存 collective identity
    reg phase_q [0:ENTRIES-1]; // 保存 phase identity
    reg [11:0] packet_seq_q [0:ENTRIES-1]; // 保存 packet sequence
    reg [4:0] flit_count_q [0:ENTRIES-1]; // 保存 packet flit 数量
    reg [2:0] retry_count_q [0:ENTRIES-1]; // 保存每 packet retry 次数
    reg store_active_q; // 标记 packet 正在连续写入
    reg [INDEX_WIDTH-1:0] store_entry_q; // 保存当前写 entry
    reg [3:0] store_flit_q; // 保存当前写 flit 索引
    reg replay_active_q; // 标记 packet 正在 replay
    reg [INDEX_WIDTH-1:0] replay_entry_q; // 保存当前 replay entry
    reg [3:0] replay_flit_q; // 保存当前 replay flit 索引
    reg [INDEX_WIDTH-1:0] free_index_d; // 保存最低空闲 entry
    reg free_found_d; // 标记存在空闲 entry
    reg [INDEX_WIDTH-1:0] nack_index_d; // 保存 NACK 匹配 entry
    reg nack_found_d; // 标记 NACK 匹配成功
    reg [INDEX_WIDTH:0] occupancy_d; // 保存组合 occupancy
    reg [607:0] replay_body_d; // 保存协议字段修改后的 replay body
    reg replay_output_valid_q; // 保存 replay 输出寄存器有效位
    reg [607:0] replay_output_body_q; // 保存 replay 输出寄存器 body
    reg replay_output_last_q; // 保存 replay 输出寄存器尾部标志
    integer entry_index; // 提供固定 entry 扫描索引
    wire store_fire; // 指示当前 store 传输成立
    wire replay_load; // 指示从 replay memory 装载输出寄存器
    wire replay_source_last; // 指示当前 memory source 是 packet 尾部
    wire start_entry; // 指示当前周期保留新 entry
    assign store_ready_o = store_active_q || free_found_d; // packet 内保持 entry 或分配新 entry
    assign store_fire = store_valid_i && store_ready_o; // 形成 store 本地握手
    assign start_entry = store_start_i && !store_active_q && free_found_d; // 检测合法 packet 开始
    assign replay_valid_o = replay_output_valid_q; // 输出寄存器有效时持续输出
    assign replay_last_o = replay_output_last_q; // 输出注册后的 packet 尾部标志
    assign replay_source_last = replay_active_q && ({1'b0, replay_flit_q} + 5'd1 == flit_count_q[replay_entry_q]); // 比较 memory source packet 尾 flit
    assign replay_load = replay_active_q && (!replay_output_valid_q || replay_ready_i); // 输出为空或本周期消费时装载下一 flit
    assign replay_body_o = replay_output_body_q; // 输出注册后的 replay body
    assign occupancy_o = occupancy_d; // 输出组合 occupancy
    always @(*) begin // 扫描空闲 entry、NACK entry 和 occupancy
        free_index_d = {INDEX_WIDTH{1'b0}}; // 默认空闲索引为零
        free_found_d = 1'b0; // 默认没有空闲 entry
        nack_index_d = {INDEX_WIDTH{1'b0}}; // 默认 NACK 索引为零
        nack_found_d = 1'b0; // 默认没有 NACK 匹配
        occupancy_d = {(INDEX_WIDTH+1){1'b0}}; // 默认 occupancy 为零
        for (entry_index = 0; entry_index < ENTRIES; entry_index = entry_index + 1) begin // 遍历固定 replay entry
            if (entry_valid_q[entry_index]) begin // 检查当前 entry 有效
                occupancy_d = occupancy_d + {{INDEX_WIDTH{1'b0}}, 1'b1}; // 累计有效 entry
            end else if (!free_found_d) begin // 检查最低空闲 entry 尚未找到
                free_index_d = entry_index[INDEX_WIDTH-1:0]; // 记录最低空闲 entry
                free_found_d = 1'b1; // 标记空闲 entry 已找到
            end // 结束 occupancy 和空闲选择
            if (!nack_found_d && entry_valid_q[entry_index] && entry_complete_q[entry_index] && (collective_id_q[entry_index] == nack_collective_id_i) && (phase_q[entry_index] == nack_phase_i) && (packet_seq_q[entry_index] == nack_packet_seq_i)) begin // 匹配完整 NACK identity
                nack_index_d = entry_index[INDEX_WIDTH-1:0]; // 记录匹配 entry
                nack_found_d = 1'b1; // 标记匹配成功
            end // 结束 NACK identity 匹配
        end // 结束固定 entry 扫描
    end // 结束组合 entry 扫描
    always @(*) begin // 修改 replay header 的 VC 和 retry 字段
        replay_body_d = body_mem[{replay_entry_q, 4'b0000} + {{INDEX_WIDTH{1'b0}}, replay_flit_q}]; // 读取当前 replay flit
        replay_body_d[527:525] = 3'd6; // 将 v2 header VC 设置为 replay VC 六
        replay_body_d[531] = 1'b1; // 将 v2 header retry 标志设置为一
    end // 结束 replay header 修改
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 replay buffer 全部状态
        if (!rst_n_i) begin // 检测复位有效
            store_active_q <= 1'b0; // 清除 packet store 状态
            store_entry_q <= {INDEX_WIDTH{1'b0}}; // 清零 store entry
            store_flit_q <= 4'd0; // 清零 store flit
            replay_active_q <= 1'b0; // 清除 replay 状态
            replay_entry_q <= {INDEX_WIDTH{1'b0}}; // 清零 replay entry
            replay_flit_q <= 4'd0; // 清零 replay flit
            replay_output_valid_q <= 1'b0; // 清除 replay 输出有效位
            replay_output_body_q <= 608'd0; // 清零 replay 输出 body
            replay_output_last_q <= 1'b0; // 清除 replay 输出尾部标志
            retry_exhausted_o <= 1'b0; // 清除 retry exhausted
            for (entry_index = 0; entry_index < ENTRIES; entry_index = entry_index + 1) begin // 复位全部 replay entry
                entry_valid_q[entry_index] <= 1'b0; // 清除 entry 有效位
                entry_complete_q[entry_index] <= 1'b0; // 清除 entry 完整位
                collective_id_q[entry_index] <= 12'd0; // 清零 collective identity
                phase_q[entry_index] <= 1'b0; // 清零 phase identity
                packet_seq_q[entry_index] <= 12'd0; // 清零 packet sequence
                flit_count_q[entry_index] <= 5'd0; // 清零 packet flit 数量
                retry_count_q[entry_index] <= 3'd0; // 清零 packet retry 计数
            end // 结束全部 entry 复位
        end else begin // 处理正常 replay buffer 更新
            retry_exhausted_o <= 1'b0; // 默认清除单周期 exhausted 脉冲
            if (!replay_output_valid_q || replay_ready_i) begin // 检查 replay 输出寄存器可以更新
                if (replay_load) begin // 检查存在可装载的 replay source
                    replay_output_valid_q <= 1'b1; // 标记注册 replay flit 有效
                    replay_output_body_q <= replay_body_d; // 注册 memory read 和 header 修改结果
                    replay_output_last_q <= replay_source_last; // 注册 packet 尾部状态
                end else begin // 处理没有 replay source 的空闲周期
                    replay_output_valid_q <= 1'b0; // 清除已消费的 replay 输出
                    replay_output_last_q <= 1'b0; // 清除已消费的尾部状态
                end // 结束 replay 输出装载选择
            end // 结束 replay 输出寄存器更新
            if (start_entry) begin // 检查新 packet entry 分配
                store_active_q <= 1'b1; // 标记 packet 正在写入
                store_entry_q <= free_index_d; // 锁存新 entry
                store_flit_q <= 4'd0; // 从 flit 零开始
                entry_valid_q[free_index_d] <= 1'b1; // 标记新 entry 有效
                entry_complete_q[free_index_d] <= 1'b0; // 标记 packet 尚未完整
                collective_id_q[free_index_d] <= store_body_i[569:558]; // 保存 v2 collective identity
                phase_q[free_index_d] <= store_body_i[528]; // 保存 v2 phase identity
                packet_seq_q[free_index_d] <= store_body_i[593:582]; // 保存 v2 packet sequence
                retry_count_q[free_index_d] <= 3'd0; // 清零新 packet retry 计数
            end // 结束新 packet entry 分配
            if (store_fire && (store_active_q || start_entry)) begin // 检查 packet flit store 成立
                body_mem[{(store_active_q ? store_entry_q : free_index_d), 4'b0000} + {{INDEX_WIDTH{1'b0}}, (store_active_q ? store_flit_q : 4'd0)}] <= store_body_i; // 写入 packet flit body
                if (store_last_i) begin // 检查 packet 尾部
                    entry_complete_q[store_active_q ? store_entry_q : free_index_d] <= 1'b1; // 标记 packet 完整
                    flit_count_q[store_active_q ? store_entry_q : free_index_d] <= {1'b0, (store_active_q ? store_flit_q : 4'd0)} + 5'd1; // 保存 packet flit 数量
                    store_active_q <= 1'b0; // 结束 packet store
                    store_flit_q <= 4'd0; // 清零 packet flit 索引
                end else begin // 处理 packet 中间 flit
                    store_active_q <= 1'b1; // 保持 packet store
                    store_entry_q <= store_active_q ? store_entry_q : free_index_d; // 保持当前 packet entry
                    store_flit_q <= (store_active_q ? store_flit_q : 4'd0) + 4'd1; // 推进 packet flit 索引
                end // 结束 packet 尾部选择
            end // 结束 packet flit store
            if (ack_valid_i) begin // 检查精确 ACK 到达
                for (entry_index = 0; entry_index < ENTRIES; entry_index = entry_index + 1) begin // 扫描 ACK identity
                    if (entry_valid_q[entry_index] && (collective_id_q[entry_index] == ack_collective_id_i) && (phase_q[entry_index] == ack_phase_i) && (packet_seq_q[entry_index] == ack_packet_seq_i)) begin // 匹配 ACK packet
                        entry_valid_q[entry_index] <= 1'b0; // 释放已确认 entry
                        entry_complete_q[entry_index] <= 1'b0; // 清除 packet 完整位
                    end // 结束 ACK packet 匹配
                end // 结束 ACK identity 扫描
            end // 结束精确 ACK 处理
            if (nack_valid_i && nack_found_d && !replay_active_q) begin // 检查可启动的精确 NACK
                if (retry_count_q[nack_index_d] == 3'd7) begin // 检查 retry 已达到上限
                    retry_exhausted_o <= 1'b1; // 报告 retry exhausted
                end else begin // 处理允许的 retry
                    retry_count_q[nack_index_d] <= retry_count_q[nack_index_d] + 3'd1; // 增加 retry 计数
                    replay_active_q <= 1'b1; // 启动 packet replay
                    replay_entry_q <= nack_index_d; // 锁存 replay entry
                    replay_flit_q <= 4'd0; // 从 packet 首 flit 开始
                end // 结束 retry 上限选择
            end // 结束精确 NACK 处理
            if (replay_load) begin // 检查 replay memory source 已装入输出寄存器
                if (replay_source_last) begin // 检查 replay packet 尾部
                    replay_active_q <= 1'b0; // 结束 packet replay
                    replay_flit_q <= 4'd0; // 清零 replay flit 索引
                end else begin // 处理 replay packet 中间 flit
                    replay_flit_q <= replay_flit_q + 4'd1; // 推进 replay flit 索引
                end // 结束 replay 尾部选择
            end // 结束 replay flit 发送
        end // 结束正常状态更新
    end // 结束 replay buffer 时序逻辑
endmodule // 结束单 slice replay buffer
