module kdlink_v2_bonded_port ( // 定义双 slice 全双工 bonded port
    input wire clk_i, // 接收一 GHz bonded port 时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [1:0] configured_slice_mask_i, // 接收软件允许的 slice mask
    input wire [1:0] slice_fault_i, // 接收每 slice 独立 sticky fault
    input wire [1:0] tx_valid_i, // 接收两个逻辑 packet lane 有效标志
    output wire [1:0] tx_ready_o, // 输出两个逻辑 lane 本地许可
    input wire [191:0] tx_header_i, // 接收两个不含 CRC 的 header
    input wire [1023:0] tx_payload_i, // 接收两个五百一十二位 payload
    input wire [13:0] tx_payload_bytes_i, // 接收两个 payload 字节数
    input wire [1:0] ack_valid_i, // 接收两个 origin slice 的精确 ACK
    input wire [23:0] ack_collective_id_i, // 接收两个 ACK collective identity
    input wire [1:0] ack_phase_i, // 接收两个 ACK phase identity
    input wire [23:0] ack_packet_seq_i, // 接收两个 ACK packet sequence
    input wire [1:0] nack_valid_i, // 接收两个 origin slice 的精确 NACK
    input wire [23:0] nack_collective_id_i, // 接收两个 NACK collective identity
    input wire [1:0] nack_phase_i, // 接收两个 NACK phase identity
    input wire [23:0] nack_packet_seq_i, // 接收两个 NACK packet sequence
    output wire [1:0] slice_tx_valid_o, // 输出两个物理 slice TX valid
    output wire [1279:0] slice_tx_flit_o, // 输出两个物理 slice TX flit
    input wire [1:0] slice_rx_valid_i, // 接收两个物理 slice RX valid
    input wire [1279:0] slice_rx_flit_i, // 接收两个物理 slice RX flit
    output wire [1:0] rx_valid_o, // 输出最多两个全局有序 payload valid
    output wire [191:0] rx_header_o, // 输出两个全局有序 header
    output wire [1023:0] rx_payload_o, // 输出两个全局有序 payload
    output wire [13:0] rx_payload_bytes_o, // 输出两个全局有序字节数
    output wire [1:0] active_slice_mask_o, // 输出当前健康 active slice mask
    output wire degraded_o, // 指示 bonded port 单 slice 降级
    output wire link_down_o, // 指示 bonded port 没有 active slice
    output wire [8:0] reorder_occupancy_o, // 输出全局 reorder occupancy
    output wire [7:0] replay_occupancy_o, // 输出两个独立 replay occupancy
    output reg [63:0] stripe_packet_count_o, // 输出每 slice 新 packet 分配计数
    output wire [1:0] crc_error_o, // 输出每 slice CRC error 脉冲
    output wire duplicate_drop_o, // 输出全局 duplicate drop 脉冲
    output wire reorder_error_o, // 输出全局 reorder window error
    output wire [1:0] retry_exhausted_o // 输出每 slice retry exhausted
); // 结束端口声明
    wire [1:0] active_mask; // 保存配置与健康共同决定的 active mask
    reg lane0_slice_d; // 保存逻辑 lane 零目标 slice
    reg lane1_slice_d; // 保存逻辑 lane 一目标 slice
    wire any_active; // 标记至少一个 slice active
    wire lane0_fire; // 指示逻辑 lane 零传输成立
    wire lane1_fire; // 指示逻辑 lane 一传输成立
    wire [1:0] replay_store_ready; // 保存两个 origin replay buffer 空间许可
    wire [1:0] replay_valid; // 保存两个 origin replay 输出有效
    wire [1215:0] replay_body; // 保存两个 origin replay body
    wire [1:0] replay_last; // 保存两个 origin replay 尾部标志
    wire [1:0] replay_ready; // 保存两个 origin replay 仲裁许可
    wire [7:0] replay_occupancy; // 保存两个 origin replay occupancy
    wire [1:0] replay_target; // 保存两个 replay packet 健康目标 slice
    wire replay0_to_phys0; // 标记 origin 零 replay 发送到 physical 零
    wire replay0_to_phys1; // 标记 origin 零 replay 发送到 physical 一
    wire replay1_to_phys0; // 标记 origin 一 replay 发送到 physical 零
    wire replay1_to_phys1; // 标记 origin 一 replay 发送到 physical 一
    wire phys0_replay_valid; // 标记 physical 零被 replay 占用
    wire phys1_replay_valid; // 标记 physical 一被 replay 占用
    wire phys0_replay_select1; // 标记 physical 零选择 origin 一 replay
    wire phys1_replay_select1; // 标记 physical 一选择 origin 一 replay
    wire lane0_replay_block; // 标记 lane 零目标被 replay 占用
    wire lane1_replay_block; // 标记 lane 一目标被 replay 占用
    wire lane_conflict; // 标记两个逻辑 lane 竞争同一 slice
    wire store0_valid; // 指示 origin 零 replay store 有效
    wire store1_valid; // 指示 origin 一 replay store 有效
    wire [607:0] store0_body; // 保存 origin 零 store body
    wire [607:0] store1_body; // 保存 origin 一 store body
    wire store0_start; // 指示 origin 零 packet 开始
    wire store1_start; // 指示 origin 一 packet 开始
    wire store0_last; // 指示 origin 零 packet 尾部
    wire store1_last; // 指示 origin 一 packet 尾部
    wire normal0_to_phys0; // 标记 lane 零发送到 physical 零
    wire normal0_to_phys1; // 标记 lane 零发送到 physical 一
    wire normal1_to_phys0; // 标记 lane 一发送到 physical 零
    wire normal1_to_phys1; // 标记 lane 一发送到 physical 一
    wire phys0_normal_valid; // 标记 physical 零 normal 数据有效
    wire phys1_normal_valid; // 标记 physical 一 normal 数据有效
    wire phys0_normal_select1; // 标记 physical 零 normal 选择 lane 一
    wire phys1_normal_select1; // 标记 physical 一 normal 选择 lane 一
    wire [1:0] codec_tx_valid_q; // 保存 arbitration 后注册有效
    wire [191:0] codec_tx_header_q; // 保存 arbitration 后注册 header
    wire [1023:0] codec_tx_payload_q; // 保存 arbitration 后注册 payload
    wire [13:0] codec_tx_bytes_q; // 保存 arbitration 后注册字节数
    wire [1:0] codec_rx_valid; // 保存两个 codec RX 检查完成有效
    wire [1:0] codec_rx_crc_good; // 保存两个 codec RX CRC 结果
    wire [191:0] codec_rx_header; // 保存两个 codec RX header
    wire [1023:0] codec_rx_payload; // 保存两个 codec RX payload
    wire [13:0] codec_rx_bytes; // 保存两个 codec RX 字节数
    wire [1:0] reorder_accept_valid; // 保存通过健康和 CRC 检查的 RX valid
    assign active_mask = configured_slice_mask_i & ~slice_fault_i; // 屏蔽发生 fault 的 slice
    assign active_slice_mask_o = active_mask; // 输出 active mask
    assign any_active = |active_mask; // 汇总 active 状态
    assign degraded_o = active_mask[0] ^ active_mask[1]; // 仅一个 slice active 时进入降级
    assign link_down_o = !any_active; // 两个 slice 均失效时 link down
    always @(*) begin // 按 packet identity 选择固定目标 slice
        lane0_slice_d = 1'b0; // 默认 lane 零选择 slice 零
        lane1_slice_d = 1'b0; // 默认 lane 一选择 slice 零
        case (active_mask) // 根据 active mask 选择 striping 模式
            2'b01: begin lane0_slice_d = 1'b0; lane1_slice_d = 1'b0; end // 单 slice 零降级模式
            2'b10: begin lane0_slice_d = 1'b1; lane1_slice_d = 1'b1; end // 单 slice 一降级模式
            2'b11: begin lane0_slice_d = tx_header_i[70]; lane1_slice_d = tx_header_i[166]; end // 双 slice 按 packet sequence 奇偶条带化
            default: begin lane0_slice_d = 1'b0; lane1_slice_d = 1'b0; end // link down 时保持安全选择
        endcase // 结束 active mask 选择
    end // 结束 packet slice 选择
    assign replay_target[0] = active_mask[0] ? 1'b0 : 1'b1; // origin 零优先原 slice 否则改走 slice 一
    assign replay_target[1] = active_mask[1] ? 1'b1 : 1'b0; // origin 一优先原 slice 否则改走 slice 零
    assign replay0_to_phys0 = replay_valid[0] && any_active && !replay_target[0]; // 路由 origin 零 replay 到 physical 零
    assign replay0_to_phys1 = replay_valid[0] && any_active && replay_target[0]; // 路由 origin 零 replay 到 physical 一
    assign replay1_to_phys0 = replay_valid[1] && any_active && !replay_target[1] && !replay0_to_phys0; // 路由 origin 一 replay 到空闲 physical 零
    assign replay1_to_phys1 = replay_valid[1] && any_active && replay_target[1] && !replay0_to_phys1; // 路由 origin 一 replay 到空闲 physical 一
    assign phys0_replay_valid = replay0_to_phys0 || replay1_to_phys0; // 汇总 physical 零 replay 占用
    assign phys1_replay_valid = replay0_to_phys1 || replay1_to_phys1; // 汇总 physical 一 replay 占用
    assign phys0_replay_select1 = replay1_to_phys0; // 选择 physical 零 replay source
    assign phys1_replay_select1 = replay1_to_phys1; // 选择 physical 一 replay source
    assign replay_ready[0] = replay0_to_phys0 || replay0_to_phys1; // 许可 origin 零 replay 推进
    assign replay_ready[1] = replay1_to_phys0 || replay1_to_phys1; // 许可 origin 一 replay 推进
    assign lane0_replay_block = lane0_slice_d ? phys1_replay_valid : phys0_replay_valid; // 检查 lane 零目标 replay 占用
    assign lane1_replay_block = lane1_slice_d ? phys1_replay_valid : phys0_replay_valid; // 检查 lane 一目标 replay 占用
    assign tx_ready_o[0] = any_active && replay_store_ready[lane0_slice_d] && !lane0_replay_block; // 形成 lane 零本地 ready
    assign lane0_fire = tx_valid_i[0] && tx_ready_o[0]; // 形成 lane 零本地握手
    assign lane_conflict = lane0_fire && (lane0_slice_d == lane1_slice_d); // lane 零优先解决同 slice 竞争
    assign tx_ready_o[1] = any_active && replay_store_ready[lane1_slice_d] && !lane1_replay_block && !lane_conflict; // 形成 lane 一本地 ready
    assign lane1_fire = tx_valid_i[1] && tx_ready_o[1]; // 形成 lane 一本地握手
    assign store0_valid = (lane0_fire && !lane0_slice_d) || (lane1_fire && !lane1_slice_d); // 汇总 origin 零 store valid
    assign store1_valid = (lane0_fire && lane0_slice_d) || (lane1_fire && lane1_slice_d); // 汇总 origin 一 store valid
    assign store0_body = (lane0_fire && !lane0_slice_d) ? {tx_header_i[95:0], tx_payload_i[511:0]} : {tx_header_i[191:96], tx_payload_i[1023:512]}; // 选择 origin 零 store body
    assign store1_body = (lane0_fire && lane0_slice_d) ? {tx_header_i[95:0], tx_payload_i[511:0]} : {tx_header_i[191:96], tx_payload_i[1023:512]}; // 选择 origin 一 store body
    assign store0_start = store0_valid && store0_body[529]; // 提取 origin 零 SOP 标志
    assign store1_start = store1_valid && store1_body[529]; // 提取 origin 一 SOP 标志
    assign store0_last = store0_valid && store0_body[530]; // 提取 origin 零 EOP 标志
    assign store1_last = store1_valid && store1_body[530]; // 提取 origin 一 EOP 标志
    kdlink_v2_replay_buffer u_replay0 ( // 实例化 slice 零独立 replay 状态
        .clk_i(clk_i), .rst_n_i(rst_n_i), .store_start_i(store0_start), .store_valid_i(store0_valid), .store_body_i(store0_body), .store_last_i(store0_last), .store_ready_o(replay_store_ready[0]), // 连接 origin 零 store 通路
        .ack_valid_i(ack_valid_i[0]), .ack_collective_id_i(ack_collective_id_i[11:0]), .ack_phase_i(ack_phase_i[0]), .ack_packet_seq_i(ack_packet_seq_i[11:0]), // 连接 origin 零 ACK
        .nack_valid_i(nack_valid_i[0]), .nack_collective_id_i(nack_collective_id_i[11:0]), .nack_phase_i(nack_phase_i[0]), .nack_packet_seq_i(nack_packet_seq_i[11:0]), // 连接 origin 零 NACK
        .replay_valid_o(replay_valid[0]), .replay_ready_i(replay_ready[0]), .replay_body_o(replay_body[607:0]), .replay_last_o(replay_last[0]), .retry_exhausted_o(retry_exhausted_o[0]), .occupancy_o(replay_occupancy[3:0]) // 连接 origin 零 replay 输出和状态
    ); // 结束 slice 零 replay 实例
    kdlink_v2_replay_buffer u_replay1 ( // 实例化 slice 一独立 replay 状态
        .clk_i(clk_i), .rst_n_i(rst_n_i), .store_start_i(store1_start), .store_valid_i(store1_valid), .store_body_i(store1_body), .store_last_i(store1_last), .store_ready_o(replay_store_ready[1]), // 连接 origin 一 store 通路
        .ack_valid_i(ack_valid_i[1]), .ack_collective_id_i(ack_collective_id_i[23:12]), .ack_phase_i(ack_phase_i[1]), .ack_packet_seq_i(ack_packet_seq_i[23:12]), // 连接 origin 一 ACK
        .nack_valid_i(nack_valid_i[1]), .nack_collective_id_i(nack_collective_id_i[23:12]), .nack_phase_i(nack_phase_i[1]), .nack_packet_seq_i(nack_packet_seq_i[23:12]), // 连接 origin 一 NACK
        .replay_valid_o(replay_valid[1]), .replay_ready_i(replay_ready[1]), .replay_body_o(replay_body[1215:608]), .replay_last_o(replay_last[1]), .retry_exhausted_o(retry_exhausted_o[1]), .occupancy_o(replay_occupancy[7:4]) // 连接 origin 一 replay 输出和状态
    ); // 结束 slice 一 replay 实例
    assign replay_occupancy_o = replay_occupancy; // 输出两个独立 replay occupancy
    assign normal0_to_phys0 = lane0_fire && !lane0_slice_d; // 路由 lane 零 normal 到 physical 零
    assign normal0_to_phys1 = lane0_fire && lane0_slice_d; // 路由 lane 零 normal 到 physical 一
    assign normal1_to_phys0 = lane1_fire && !lane1_slice_d; // 路由 lane 一 normal 到 physical 零
    assign normal1_to_phys1 = lane1_fire && lane1_slice_d; // 路由 lane 一 normal 到 physical 一
    assign phys0_normal_valid = normal0_to_phys0 || normal1_to_phys0; // 汇总 physical 零 normal valid
    assign phys1_normal_valid = normal0_to_phys1 || normal1_to_phys1; // 汇总 physical 一 normal valid
    assign phys0_normal_select1 = normal1_to_phys0; // 选择 physical 零 normal source
    assign phys1_normal_select1 = normal1_to_phys1; // 选择 physical 一 normal source
    kdlink_v2_bonded_tx_register u_tx_register ( // 实例化 shared arbitration 到 codec 的独立时序分区
        .clk_i(clk_i), .rst_n_i(rst_n_i), .replay_valid_i({phys1_replay_valid, phys0_replay_valid}), .replay_select1_i({phys1_replay_select1, phys0_replay_select1}), .replay_body_i(replay_body), // 连接 replay arbitration 输入
        .normal_valid_i({phys1_normal_valid, phys0_normal_valid}), .normal_select1_i({phys1_normal_select1, phys0_normal_select1}), .normal_header_i(tx_header_i), .normal_payload_i(tx_payload_i), .normal_payload_bytes_i(tx_payload_bytes_i), // 连接 normal arbitration 输入
        .codec_valid_o(codec_tx_valid_q), .codec_header_o(codec_tx_header_q), .codec_payload_o(codec_tx_payload_q), .codec_payload_bytes_o(codec_tx_bytes_q) // 连接注册后的 codec 输入
    ); // 结束 bonded TX 注册分区实例
    kdlink_v2_slice u_slice0 ( // 实例化 physical slice 零独立 codec
        .clk_i(clk_i), .rst_n_i(rst_n_i), .tx_valid_i(codec_tx_valid_q[0]), .tx_header_i(codec_tx_header_q[95:0]), .tx_payload_i(codec_tx_payload_q[511:0]), .tx_payload_bytes_i(codec_tx_bytes_q[6:0]), .tx_valid_o(slice_tx_valid_o[0]), .tx_flit_o(slice_tx_flit_o[639:0]), // 连接 slice 零 TX
        .rx_valid_i(slice_rx_valid_i[0]), .rx_flit_i(slice_rx_flit_i[639:0]), .rx_valid_o(codec_rx_valid[0]), .rx_crc_good_o(codec_rx_crc_good[0]), .rx_header_o(codec_rx_header[95:0]), .rx_payload_o(codec_rx_payload[511:0]), .rx_payload_bytes_o(codec_rx_bytes[6:0]) // 连接 slice 零 RX
    ); // 结束 physical slice 零实例
    kdlink_v2_slice u_slice1 ( // 实例化 physical slice 一独立 codec
        .clk_i(clk_i), .rst_n_i(rst_n_i), .tx_valid_i(codec_tx_valid_q[1]), .tx_header_i(codec_tx_header_q[191:96]), .tx_payload_i(codec_tx_payload_q[1023:512]), .tx_payload_bytes_i(codec_tx_bytes_q[13:7]), .tx_valid_o(slice_tx_valid_o[1]), .tx_flit_o(slice_tx_flit_o[1279:640]), // 连接 slice 一 TX
        .rx_valid_i(slice_rx_valid_i[1]), .rx_flit_i(slice_rx_flit_i[1279:640]), .rx_valid_o(codec_rx_valid[1]), .rx_crc_good_o(codec_rx_crc_good[1]), .rx_header_o(codec_rx_header[191:96]), .rx_payload_o(codec_rx_payload[1023:512]), .rx_payload_bytes_o(codec_rx_bytes[13:7]) // 连接 slice 一 RX
    ); // 结束 physical slice 一实例
    assign crc_error_o = codec_rx_valid & ~codec_rx_crc_good; // 报告每 slice CRC error 脉冲
    assign reorder_accept_valid = codec_rx_valid & codec_rx_crc_good & active_mask; // 只提交健康 slice 的 CRC 通过 flit
    kdlink_v2_bonded_reorder u_reorder ( // 实例化 bonded port 全局顺序恢复窗口
        .clk_i(clk_i), .rst_n_i(rst_n_i), .accept_valid_i(reorder_accept_valid), .accept_header_i(codec_rx_header), .accept_payload_i(codec_rx_payload), .accept_payload_bytes_i(codec_rx_bytes), // 连接两个 slice RX 输入
        .output_valid_o(rx_valid_o), .output_header_o(rx_header_o), .output_payload_o(rx_payload_o), .output_payload_bytes_o(rx_payload_bytes_o), .occupancy_o(reorder_occupancy_o), // 连接双 lane 有序输出
        .duplicate_drop_o(duplicate_drop_o), .window_error_o(reorder_error_o) // 连接 exact-once 和窗口错误状态
    ); // 结束 bonded reorder 实例
    always @(posedge clk_i or negedge rst_n_i) begin // 更新每 slice 新 packet 分配计数
        if (!rst_n_i) begin // 检测复位有效
            stripe_packet_count_o <= 64'd0; // 清零两个 slice packet 计数
        end else begin // 处理正常 packet 计数
            if (store0_start) stripe_packet_count_o[31:0] <= stripe_packet_count_o[31:0] + 32'd1; // 统计分配到 slice 零的新 packet
            if (store1_start) stripe_packet_count_o[63:32] <= stripe_packet_count_o[63:32] + 32'd1; // 统计分配到 slice 一的新 packet
        end // 结束正常 packet 计数
    end // 结束 packet 计数时序逻辑
endmodule // 结束双 slice bonded port
