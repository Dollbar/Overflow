module coll_replay_buffer #( // 定义固定窗口 packet replay 存储器
    parameter ENTRIES = 8, // 配置最多保留 packet 数量
    parameter INDEX_WIDTH = 3 // 配置 entry 索引位宽
) ( // 开始端口声明
    input  wire clk_i, // 接收 link core 时钟
    input  wire rst_n_i, // 接收低有效异步复位
    input  wire store_start_i, // 指示开始保存新 packet
    input  wire [11:0] store_collective_id_i, // 接收新 packet collective ID
    input  wire store_phase_i, // 接收新 packet phase
    input  wire [15:0] store_packet_seq_i, // 接收新 packet sequence
    input  wire store_valid_i, // 接收 packet body flit 有效
    input  wire [607:0] store_body_i, // 接收不含 CRC 的 header 和 payload
    input  wire store_last_i, // 指示当前保存 flit 为 packet 尾部
    output wire store_ready_o, // 指示 replay 存储可接收当前 flit
    input  wire ack_valid_i, // 接收累计 ACK 有效
    input  wire [11:0] ack_collective_id_i, // 接收 ACK collective ID
    input  wire ack_phase_i, // 接收 ACK phase
    input  wire [15:0] ack_packet_seq_i, // 接收最高连续 committed sequence
    input  wire nack_valid_i, // 接收精确 NACK 有效
    input  wire [11:0] nack_collective_id_i, // 接收 NACK collective ID
    input  wire nack_phase_i, // 接收 NACK phase
    input  wire [15:0] nack_packet_seq_i, // 接收待 replay packet sequence
    output wire replay_valid_o, // 指示 replay body flit 有效
    input  wire replay_ready_i, // 接收 VC3 下游接收能力
    output wire [607:0] replay_body_o, // 输出设置 retry 和 VC3 后的 body flit
    output wire replay_last_o, // 指示 replay packet 尾部
    output reg retry_exhausted_o, // 指示 packet 已达到七次 replay
    output wire [INDEX_WIDTH:0] occupancy_o // 输出当前有效 replay entry 数量
); // 结束端口声明
    reg [607:0] body_mem [0:ENTRIES*16-1]; // 保存每 entry 最多十六个 body flit
    reg entry_valid_q [0:ENTRIES-1]; // 保存 replay entry 有效位
    reg entry_complete_q [0:ENTRIES-1]; // 保存 packet 已完整写入标志
    reg [11:0] collective_id_q [0:ENTRIES-1]; // 保存 entry collective ID
    reg phase_q [0:ENTRIES-1]; // 保存 entry phase
    reg [15:0] packet_seq_q [0:ENTRIES-1]; // 保存 entry packet sequence
    reg [4:0] flit_count_q [0:ENTRIES-1]; // 保存 entry flit 数量一至十六
    reg store_active_q; // 指示当前 packet 正在保存
    reg [INDEX_WIDTH-1:0] store_entry_q; // 保存当前写 entry 索引
    reg [3:0] store_flit_q; // 保存当前写 flit 索引
    reg replay_active_q; // 指示当前 packet 正在 replay
    reg [INDEX_WIDTH-1:0] replay_entry_q; // 保存当前 replay entry 索引
    reg [3:0] replay_flit_q; // 保存当前 replay flit 索引
    reg [INDEX_WIDTH-1:0] free_index_d; // 保存最低空闲 entry 索引
    reg free_found_d; // 指示存在空闲 entry
    reg [INDEX_WIDTH-1:0] nack_index_d; // 保存 NACK 匹配 entry 索引
    reg nack_found_d; // 指示找到 NACK entry
    reg [INDEX_WIDTH:0] occupancy_d; // 保存有效 entry 组合计数
    reg [607:0] replay_body_d; // 保存设置 replay header 后的 body
    integer scan_index; // 提供固定 entry 状态扫描索引
    wire store_fire; // 指示保存 flit 完成握手
    wire replay_fire; // 指示 replay flit 完成握手
    wire retry_request; wire retry_allowed; wire retry_limit_hit; wire [2:0] retry_count_unused; // 保存匹配 NACK retry limiter 状态
    assign store_ready_o = store_active_q || free_found_d; // packet 内保留 entry 后持续接收
    assign store_fire = store_valid_i && store_ready_o; // 形成保存 flit 握手
    assign replay_valid_o = replay_active_q; // replay active 时输出有效
    assign replay_last_o = replay_active_q && ({1'b0, replay_flit_q} + 1'b1 == flit_count_q[replay_entry_q]); // 比较当前 flit 是否为 packet 尾部
    assign replay_fire = replay_valid_o && replay_ready_i; // 形成 replay flit 握手
    assign replay_body_o = replay_body_d; // 输出组合修改后的 replay body
    assign occupancy_o = occupancy_d; // 输出有效 entry 数量
    assign retry_request = nack_valid_i && nack_found_d && !replay_active_q; // 仅空闲 replay 输出时向匹配 entry 请求 retry
    coll_replay_retry_table #(.ENTRIES(ENTRIES), .INDEX_WIDTH(INDEX_WIDTH)) u_retry_table ( // 实例化可独立形式证明的七次 retry limiter
        .clk_i(clk_i), .rst_n_i(rst_n_i), .reset_valid_i(store_start_i && !store_active_q && free_found_d), .reset_index_i(free_index_d), // 新 packet entry 清零 retry
        .request_valid_i(retry_request), .request_index_i(nack_index_d), .request_allowed_o(retry_allowed), .request_exhausted_o(retry_limit_hit), .request_count_o(retry_count_unused) // 匹配 NACK 查询并更新 retry 次数
    ); // 结束 retry limiter 实例
    always @(*) begin // 扫描空闲 entry、NACK entry 和 occupancy
        free_index_d = {INDEX_WIDTH{1'b0}}; // 默认空闲索引零
        free_found_d = 1'b0; // 默认没有空闲 entry
        nack_index_d = {INDEX_WIDTH{1'b0}}; // 默认 NACK 索引零
        nack_found_d = 1'b0; // 默认没有匹配 NACK entry
        occupancy_d = {(INDEX_WIDTH+1){1'b0}}; // 默认 occupancy 为零
        for (scan_index = 0; scan_index < ENTRIES; scan_index = scan_index + 1) begin // 遍历固定 replay entry
            if (entry_valid_q[scan_index]) begin // 检查当前 entry 有效
                occupancy_d = occupancy_d + 1'b1; // 统计当前有效 entry
            end else if (!free_found_d) begin // 检查最低空闲 entry 尚未找到
                free_index_d = scan_index[INDEX_WIDTH-1:0]; // 记录最低空闲索引
                free_found_d = 1'b1; // 标记已找到空闲 entry
            end // 结束空闲和 occupancy 统计
            if (!nack_found_d && entry_valid_q[scan_index] && entry_complete_q[scan_index] && collective_id_q[scan_index] == nack_collective_id_i && phase_q[scan_index] == nack_phase_i && packet_seq_q[scan_index] == nack_packet_seq_i) begin // 检查精确 NACK identity
                nack_index_d = scan_index[INDEX_WIDTH-1:0]; // 记录 NACK entry 索引
                nack_found_d = 1'b1; // 标记 NACK entry 已找到
            end // 结束 NACK identity 匹配
        end // 结束固定 replay entry 扫描
    end // 结束 replay entry 组合扫描
    always @(*) begin // 组合修改 replay header 的 VC 和 retry 字段
        replay_body_d = body_mem[{replay_entry_q, 4'b0000} + {{INDEX_WIDTH{1'b0}}, replay_flit_q}]; // 读取当前 replay body
        replay_body_d[527:526] = 2'd3; // 将 header VC 字段设置为 VC3
        replay_body_d[595] = 1'b1; // 将 header retry 字段设置为一
    end // 结束 replay body 修改
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 replay buffer 状态
        if (!rst_n_i) begin // 检测复位有效
            store_active_q <= 1'b0; // 清除 packet 保存状态
            store_entry_q <= {INDEX_WIDTH{1'b0}}; // 清零保存 entry 索引
            store_flit_q <= 4'd0; // 清零保存 flit 索引
            replay_active_q <= 1'b0; // 清除 replay 状态
            replay_entry_q <= {INDEX_WIDTH{1'b0}}; // 清零 replay entry 索引
            replay_flit_q <= 4'd0; // 清零 replay flit 索引
            retry_exhausted_o <= 1'b0; // 清除 retry exhausted 脉冲
            for (scan_index = 0; scan_index < ENTRIES; scan_index = scan_index + 1) begin // 复位全部 replay entry
                entry_valid_q[scan_index] <= 1'b0; // 清除 entry 有效位
                entry_complete_q[scan_index] <= 1'b0; // 清除 entry 完整标志
                collective_id_q[scan_index] <= 12'd0; // 清零 collective ID
                phase_q[scan_index] <= 1'b0; // 清零 phase
                packet_seq_q[scan_index] <= 16'd0; // 清零 packet sequence
                flit_count_q[scan_index] <= 5'd0; // 清零 flit 数量
            end // 结束 replay entry 复位
        end else begin // 处理 replay buffer 正常运行
            retry_exhausted_o <= 1'b0; // 默认清除单周期 exhausted 脉冲
            if (store_start_i && !store_active_q && free_found_d) begin // 检查开始保存新 packet
                store_active_q <= 1'b1; // 进入 packet 保存状态
                store_entry_q <= free_index_d; // 保留最低空闲 entry
                store_flit_q <= 4'd0; // 从 packet flit 零开始
                entry_valid_q[free_index_d] <= 1'b1; // 标记 entry 已占用
                entry_complete_q[free_index_d] <= 1'b0; // 标记 packet 尚未完整
                collective_id_q[free_index_d] <= store_collective_id_i; // 保存 collective ID
                phase_q[free_index_d] <= store_phase_i; // 保存 phase
                packet_seq_q[free_index_d] <= store_packet_seq_i; // 保存 packet sequence
            end // 结束新 packet entry 保留
            if (store_fire && (store_active_q || store_start_i)) begin // 检查保存当前 packet flit
                body_mem[{(store_active_q ? store_entry_q : free_index_d), 4'b0000} + {{INDEX_WIDTH{1'b0}}, (store_active_q ? store_flit_q : 4'd0)}] <= store_body_i; // 写入当前 packet body
                if (store_last_i) begin // 检查 packet 尾 flit
                    entry_complete_q[store_active_q ? store_entry_q : free_index_d] <= 1'b1; // 标记 packet 已完整保存
                    flit_count_q[store_active_q ? store_entry_q : free_index_d] <= {1'b0, (store_active_q ? store_flit_q : 4'd0)} + 1'b1; // 保存 packet flit 数量
                    store_active_q <= 1'b0; // 释放 packet 保存状态
                    store_flit_q <= 4'd0; // 清零保存 flit 索引
                end else begin // 处理 packet 中间 flit
                    store_active_q <= 1'b1; // 保持 packet 保存状态
                    store_entry_q <= store_active_q ? store_entry_q : free_index_d; // 保持或锁存当前 entry
                    store_flit_q <= (store_active_q ? store_flit_q : 4'd0) + 1'b1; // 推进保存 flit 索引
                end // 结束 packet 保存尾部选择
            end // 结束保存 flit 处理
            if (ack_valid_i) begin // 检查累计 ACK 到达
                for (scan_index = 0; scan_index < ENTRIES; scan_index = scan_index + 1) begin // 扫描同 sequence space entry
                    if (entry_valid_q[scan_index] && collective_id_q[scan_index] == ack_collective_id_i && phase_q[scan_index] == ack_phase_i && ((ack_packet_seq_i - packet_seq_q[scan_index]) < 16'h8000)) begin // 检查 entry 被累计 ACK 覆盖
                        entry_valid_q[scan_index] <= 1'b0; // 释放已 ACK replay entry
                        entry_complete_q[scan_index] <= 1'b0; // 清除 packet 完整标志
                    end // 结束累计 ACK 覆盖判断
                end // 结束 ACK entry 扫描
            end // 结束累计 ACK 处理
            if (retry_request) begin // 检查可启动精确 packet replay
                if (retry_limit_hit) begin // 检查 retry 已达到上限
                    retry_exhausted_o <= 1'b1; // 报告 retry exhausted
                end else if (retry_allowed) begin // 处理允许再次 replay
                    replay_active_q <= 1'b1; // 启动 replay packet 输出
                    replay_entry_q <= nack_index_d; // 锁存 replay entry
                    replay_flit_q <= 4'd0; // 从 SOP flit 开始 replay
                end // 结束 retry 上限选择
            end // 结束 NACK replay 启动
            if (replay_fire) begin // 检查 replay flit 输出完成
                if (replay_last_o) begin // 检查 packet 尾部已输出
                    replay_active_q <= 1'b0; // 结束当前 packet replay
                    replay_flit_q <= 4'd0; // 清零 replay flit 索引
                end else begin // 处理 packet 后续 replay flit
                    replay_flit_q <= replay_flit_q + 1'b1; // 推进 replay flit 索引
                end // 结束 replay flit 尾部选择
            end // 结束 replay flit 输出处理
        end // 结束 replay buffer 复位选择
    end // 结束 replay buffer 时序逻辑
endmodule // 结束 packet replay buffer
