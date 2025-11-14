module coll_packet_rx_commit ( // 定义最多十六 flit packet 原子校验提交和去重单元
    input  wire clk_i, // 接收 link core 时钟
    input  wire rst_n_i, // 接收低有效异步复位
    input  wire flit_valid_i, // 接收 depacketizer 检查完成 flit 有效
    input  wire crc_good_i, // 接收当前 flit CRC 正确标志
    /* verilator lint_off UNUSEDSIGNAL */ input wire [95:0] header_i, /* verilator lint_on UNUSEDSIGNAL */ // 接收不含 CRC 的 forward header 且协议保留位由上游忽略
    input  wire [511:0] payload_i, // 接收当前 flit payload
    input  wire [6:0] payload_bytes_i, // 接收当前 flit payload 有效字节数
    output wire flit_ready_o, // 返回 packet staging 接收能力
    output wire commit_valid_o, // 指示完整 packet 已校验并可提交
    input  wire commit_ready_i, // 接收下游 atomic commit 能力
    output wire [511:0] commit_payload_o, // 输出当前 commit flit payload
    output wire [6:0] commit_payload_bytes_o, // 输出当前 commit flit有效字节数
    output wire commit_last_o, // 指示当前 commit flit 为 packet 尾部
    output wire [11:0] commit_collective_id_o, // 输出当前 atomic commit packet collective ID
    output wire commit_phase_o, // 输出当前 atomic commit packet phase
    output wire [1:0] commit_dtype_o, // 输出当前 atomic commit packet dtype
    output wire [15:0] commit_chunk_id_o, // 输出当前 atomic commit packet chunk ID
    output wire [15:0] commit_packet_seq_o, // 输出当前 atomic commit packet sequence
    output reg ack_valid_o, // 指示累计 ACK 生成
    output reg nack_valid_o, // 指示精确 NACK 生成
    output reg [11:0] response_collective_id_o, // 输出 ACK NACK collective ID
    output reg response_phase_o, // 输出 ACK NACK phase
    output reg [15:0] response_packet_seq_o, // 输出 ACK NACK packet sequence
    output reg [7:0] response_status_o, // 输出 ACK NACK status
    output reg duplicate_o // 指示已 committed duplicate 被丢弃
); // 结束端口声明
    reg [511:0] payload_mem [0:15]; // 保存待原子提交 packet payload
    reg [6:0] bytes_mem [0:15]; // 保存每 flit payload 有效字节数
    reg receive_active_q; // 指示 packet 正在接收
    reg drain_bad_q; // 指示坏 packet 正在 drain 至 EOP
    reg single_pending_q; // 指示单 flit packet 等待已流水的 duplicate 判定
    reg [3:0] history_match_group_q; // 保存四组 committed history 比较结果
    reg [4:0] receive_count_q; // 保存已接收 flit 数量
    reg [7:0] expected_flit_seq_q; // 保存下一期望 flit sequence
    reg [11:0] collective_id_q; // 保存当前 packet collective ID
    reg phase_q; // 保存当前 packet phase
    reg [1:0] dtype_q; // 保存当前 packet dtype
    reg [15:0] chunk_id_q; // 保存当前 packet chunk ID
    reg [15:0] packet_seq_q; // 保存当前 packet sequence
    reg [2:0] src_rank_q; // 保存当前 packet hop source rank
    reg [7:0] link_epoch_q; // 保存当前 packet link epoch
    reg commit_active_q; // 指示完整 packet 正在读流水或输出提交
    reg [4:0] read_remaining_q; // 保存尚未发射至读流水的 flit 数量
    reg [3:0] read_index_q; // 保存下一 staging 读索引
    (* keep = "true" *) reg [15:0] address_valid_q; // 为十六数据段物理保留读地址级有效副本
    reg address_last_q; // 指示读地址对应 packet 尾 flit
    (* keep = "true" *) reg [1:0] address_low_q [0:63]; // 为四 bank 十六数据段物理保留低位读索引副本
    (* keep = "true" *) reg [1:0] address_high_q [0:15]; // 为十六数据段物理保留高位 bank 索引副本
    (* keep = "true" *) reg [15:0] bank_valid_q; // 为十六数据段物理保留四 bank 候选级有效副本
    reg bank_last_q; // 传递四 bank 候选级 packet 尾标志
    (* keep = "true" *) reg [1:0] bank_high_q [0:15]; // 物理保留与 bank 候选对齐的高位索引副本
    reg [511:0] bank_payload0_q; // 保存 bank 零候选 payload
    reg [511:0] bank_payload1_q; // 保存 bank 一候选 payload
    reg [511:0] bank_payload2_q; // 保存 bank 二候选 payload
    reg [511:0] bank_payload3_q; // 保存 bank 三候选 payload
    reg [6:0] bank_bytes0_q; // 保存 bank 零候选字节数
    reg [6:0] bank_bytes1_q; // 保存 bank 一候选字节数
    reg [6:0] bank_bytes2_q; // 保存 bank 二候选字节数
    reg [6:0] bank_bytes3_q; // 保存 bank 三候选字节数
    (* keep = "true" *) reg [15:0] output_valid_q; // 为十六数据段物理保留固定输出级 commit 有效副本
    reg output_last_q; // 保存固定输出级 packet 尾标志
    reg [511:0] output_payload_q; // 保存固定输出级 payload
    reg [6:0] output_bytes_q; // 保存固定输出级 payload 字节数
    wire [3:0] history_match_group_d; // 接收独立 committed identity history 四组命中
    integer stage_index; // 提供固定 staging 分段流水索引
    wire input_fire; // 指示接收当前检查完成 flit
    wire identity_match; // 指示 packet 中间 flit identity 一致
    wire flit_error; // 指示当前 flit CRC sequence length 或 identity 错误
    wire commit_fire; // 指示当前 commit flit 被接受
    wire pipeline_advance; // 指示三级 staging 读流水可以整体前推
    assign flit_ready_o = !commit_active_q && !single_pending_q; // 单 buffer 在提交或单 flit去重判定期间停止接收下一 packet
    assign input_fire = flit_valid_i && flit_ready_o; // 形成 RX flit 接收握手
    assign identity_match = header_i[33:22] == collective_id_q && header_i[11] == phase_q && header_i[13:12] == dtype_q && header_i[49:34] == chunk_id_q && header_i[65:50] == packet_seq_q && header_i[18:16] == src_rank_q && header_i[91:84] == link_epoch_q; // 比较 packet identity 和 hop epoch 字段
    assign flit_error = !crc_good_i || header_i[3:0] != 4'd1 || header_i[7:4] != 4'd0 || header_i[10:8] > 3'd2 || header_i[80:74] != payload_bytes_i || payload_bytes_i > 7'd64 || header_i[18:16] > 3'd3 || header_i[21:19] > 3'd3 || (!receive_active_q && !header_i[81]) || (receive_active_q && (!identity_match || header_i[73:66] != expected_flit_seq_q || header_i[81])) || (receive_count_q == 5'd15 && !header_i[82]); // 汇总 packet header framing 和 CRC 错误
    assign commit_valid_o = output_valid_q[0]; // 输出读流水段零末级统一 commit 有效
    assign commit_payload_o = output_payload_q; // 输出读流水末级 payload
    assign commit_payload_bytes_o = output_bytes_q; // 输出读流水末级 payload 字节数
    assign commit_last_o = output_valid_q[0] && output_last_q; // 输出与 payload 对齐的 packet 尾标志
    assign commit_collective_id_o = collective_id_q; // 输出 staging 锁存的 packet collective ID
    assign commit_phase_o = phase_q; // 输出 staging 锁存的 packet phase
    assign commit_dtype_o = dtype_q; // 输出 staging 锁存的 packet dtype
    assign commit_chunk_id_o = chunk_id_q; // 输出 staging 锁存的 packet chunk ID
    assign commit_packet_seq_o = packet_seq_q; // 输出 staging 锁存的 packet sequence
    assign commit_fire = commit_valid_o && commit_ready_i; // 形成 commit flit 握手
    assign pipeline_advance = !output_valid_q[0] || commit_ready_i; // 以段零判断下游接收或输出空闲
    coll_rx_identity_history u_identity_history ( // 实例化独立可形式证明的 committed identity 去重窗口
        .clk_i(clk_i), .rst_n_i(rst_n_i), .query_collective_id_i(header_i[33:22]), .query_phase_i(header_i[11]), .query_packet_seq_i(header_i[65:50]), .query_src_rank_i(header_i[18:16]), .query_epoch_i(header_i[91:84]), .query_match_group_o(history_match_group_d), // 连接 ingress identity 查询
        .commit_valid_i(commit_fire && commit_last_o), .commit_collective_id_i(collective_id_q), .commit_phase_i(phase_q), .commit_packet_seq_i(packet_seq_q), .commit_src_rank_i(src_rank_q), .commit_epoch_i(link_epoch_q) // 仅在完整 atomic commit 握手后写入 identity
    ); // 结束 identity history 实例
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 packet staging、commit 和 response 状态
        if (!rst_n_i) begin // 检测复位有效
            receive_active_q <= 1'b0; // 清除 packet 接收状态
            drain_bad_q <= 1'b0; // 清除坏 packet drain 状态
            single_pending_q <= 1'b0; // 清除单 flit pending 状态
            history_match_group_q <= 4'd0; // 清除 committed history 分组命中
            receive_count_q <= 5'd0; // 清零接收 flit 数量
            expected_flit_seq_q <= 8'd0; // 清零期望 flit sequence
            collective_id_q <= 12'd0; // 清零 collective ID
            phase_q <= 1'b0; // 清零 phase
            dtype_q <= 2'd0; // 清零 dtype
            chunk_id_q <= 16'd0; // 清零 chunk ID
            packet_seq_q <= 16'd0; // 清零 packet sequence
            src_rank_q <= 3'd0; // 清零 hop source rank
            link_epoch_q <= 8'd0; // 清零 link epoch
            commit_active_q <= 1'b0; // 清除 packet commit 状态
            read_remaining_q <= 5'd0; // 清零待读 flit 数量
            read_index_q <= 4'd0; // 清零 staging 读索引
            address_valid_q <= 16'd0; // 清除全部分段读地址复制级有效
            address_last_q <= 1'b0; // 清除读地址级尾标志
            bank_valid_q <= 16'd0; // 清除全部分段四 bank 候选级有效
            bank_last_q <= 1'b0; // 清除四 bank 候选级尾标志
            bank_payload0_q <= 512'd0; // 清零 bank 零候选 payload
            bank_payload1_q <= 512'd0; // 清零 bank 一候选 payload
            bank_payload2_q <= 512'd0; // 清零 bank 二候选 payload
            bank_payload3_q <= 512'd0; // 清零 bank 三候选 payload
            bank_bytes0_q <= 7'd0; // 清零 bank 零候选字节数
            bank_bytes1_q <= 7'd0; // 清零 bank 一候选字节数
            bank_bytes2_q <= 7'd0; // 清零 bank 二候选字节数
            bank_bytes3_q <= 7'd0; // 清零 bank 三候选字节数
            output_valid_q <= 16'd0; // 清除全部分段固定输出级有效
            output_last_q <= 1'b0; // 清除固定输出级尾标志
            output_payload_q <= 512'd0; // 清零固定输出级 payload
            output_bytes_q <= 7'd0; // 清零固定输出级字节数
            ack_valid_o <= 1'b0; // 清除 ACK 脉冲
            nack_valid_o <= 1'b0; // 清除 NACK 脉冲
            response_collective_id_o <= 12'd0; // 清零 response collective ID
            response_phase_o <= 1'b0; // 清零 response phase
            response_packet_seq_o <= 16'd0; // 清零 response packet sequence
            response_status_o <= 8'd0; // 清零 response status
            duplicate_o <= 1'b0; // 清除 duplicate 脉冲
            for (stage_index = 0; stage_index < 64; stage_index = stage_index + 1) address_low_q[stage_index] <= 2'd0; // 清零全部 bank 分段低位索引
            for (stage_index = 0; stage_index < 16; stage_index = stage_index + 1) address_high_q[stage_index] <= 2'd0; // 清零全部分段高位索引
            for (stage_index = 0; stage_index < 16; stage_index = stage_index + 1) bank_high_q[stage_index] <= 2'd0; // 清零全部 bank 级高位索引
        end else begin // 处理 packet receiver 正常运行
            ack_valid_o <= 1'b0; // 默认清除 ACK 脉冲
            nack_valid_o <= 1'b0; // 默认清除 NACK 脉冲
            duplicate_o <= 1'b0; // 默认清除 duplicate 脉冲
            if (single_pending_q) begin // 检查单 flit packet 已完成去重判定流水
                single_pending_q <= 1'b0; // 消费当前 pending packet
                if (|history_match_group_q) begin // 检查 replay window 内 duplicate
                    ack_valid_o <= 1'b1; // duplicate 重新发送 ACK
                    duplicate_o <= 1'b1; // 报告 duplicate drop
                    response_collective_id_o <= collective_id_q; // 返回 duplicate collective ID
                    response_phase_o <= phase_q; // 返回 duplicate phase
                    response_packet_seq_o <= packet_seq_q; // 返回 duplicate packet sequence
                    response_status_o <= 8'd0; // ACK status 成功
                end else begin // 处理新的单 flit packet
                    commit_active_q <= 1'b1; // 启动 staging 读流水和 atomic commit
                    read_remaining_q <= 5'd1; // 单 flit packet 需要读取一个 flit
                    read_index_q <= 4'd0; // 从 staging flit 零开始读取
                end // 结束单 flit duplicate 选择
            end // 结束单 flit pending 处理
            if (input_fire) begin // 检查接收一个检查完成 flit
                if (drain_bad_q) begin // 检查正在 drain 坏 packet
                    if (header_i[82]) drain_bad_q <= 1'b0; // 在 EOP 后结束坏 packet drain
                end else if (flit_error) begin // 检查当前 flit导致 packet 失败
                    receive_active_q <= 1'b0; // 丢弃当前 packet staging
                    drain_bad_q <= !header_i[82]; // 非 EOP 时继续 drain 后续坏 packet flit
                    nack_valid_o <= 1'b1; // 生成精确 NACK
                    response_collective_id_o <= receive_active_q ? collective_id_q : header_i[33:22]; // 返回 packet collective ID
                    response_phase_o <= receive_active_q ? phase_q : header_i[11]; // 返回 packet phase
                    response_packet_seq_o <= receive_active_q ? packet_seq_q : header_i[65:50]; // 返回 packet sequence
                    response_status_o <= crc_good_i ? 8'h33 : 8'h30; // 区分 sequence framing 与 forward CRC
                    receive_count_q <= 5'd0; // 清零 staging flit 数量
                end else if (!receive_active_q) begin // 处理合法 SOP flit
                    collective_id_q <= header_i[33:22]; // 锁存 packet collective ID
                    phase_q <= header_i[11]; // 锁存 packet phase
                    dtype_q <= header_i[13:12]; // 锁存 packet dtype
                    chunk_id_q <= header_i[49:34]; // 锁存 packet chunk ID
                    packet_seq_q <= header_i[65:50]; // 锁存 packet sequence
                    src_rank_q <= header_i[18:16]; // 锁存 packet hop source rank
                    link_epoch_q <= header_i[91:84]; // 锁存 packet link epoch
                    history_match_group_q <= history_match_group_d; // 流水锁存四组 replay history 比较结果
                    payload_mem[0] <= payload_i; // 暂存 SOP payload
                    bytes_mem[0] <= payload_bytes_i; // 暂存 SOP payload 字节数
                    receive_count_q <= 5'd1; // 记录已接收一个 flit
                    expected_flit_seq_q <= 8'd1; // 下一 flit sequence 应为一
                    if (header_i[82]) begin // 检查单 flit packet
                        receive_active_q <= 1'b0; // 无需继续接收 packet
                        single_pending_q <= 1'b1; // 下一拍使用寄存 history 分组完成 duplicate 判定
                    end else begin // 处理多 flit packet SOP
                        receive_active_q <= 1'b1; // 继续接收 packet 后续 flit
                    end // 结束 SOP EOP 选择
                end else begin // 处理合法 packet 中间或尾 flit
                    payload_mem[receive_count_q[3:0]] <= payload_i; // 暂存当前 packet payload
                    bytes_mem[receive_count_q[3:0]] <= payload_bytes_i; // 暂存当前 payload 字节数
                    receive_count_q <= receive_count_q + 1'b1; // 增加 packet flit 数量
                    expected_flit_seq_q <= expected_flit_seq_q + 1'b1; // 推进期望 flit sequence
                    if (header_i[82]) begin // 检查 packet 尾 flit
                        receive_active_q <= 1'b0; // 结束 packet 接收
                        if (|history_match_group_q) begin // 检查完整 packet duplicate
                            ack_valid_o <= 1'b1; // duplicate 重新发送 ACK
                            duplicate_o <= 1'b1; // 报告 duplicate drop
                            response_collective_id_o <= collective_id_q; // 返回 duplicate collective ID
                            response_phase_o <= phase_q; // 返回 duplicate phase
                            response_packet_seq_o <= packet_seq_q; // 返回 duplicate packet sequence
                            response_status_o <= 8'd0; // ACK status 成功
                        end else begin // 处理新的完整 packet
                            commit_active_q <= 1'b1; // 启动 staging 读流水和 atomic commit
                            read_remaining_q <= receive_count_q + 1'b1; // 锁存完整 packet 待读 flit 数量
                            read_index_q <= 4'd0; // 从 staging SOP flit 开始读取
                        end // 结束 duplicate 选择
                    end // 结束 EOP packet 提交
                end // 结束 packet 接收状态选择
            end // 结束 RX flit 接收处理
            if (commit_fire) begin // 检查 atomic commit flit 被下游接受
                if (commit_last_o) begin // 检查完整 packet commit 完成
                    commit_active_q <= 1'b0; // 结束 packet commit 输出
                    read_remaining_q <= 5'd0; // 清零待读 flit 数量
                    ack_valid_o <= 1'b1; // 仅完整 atomic commit 后生成 ACK
                    response_collective_id_o <= collective_id_q; // 返回 committed collective ID
                    response_phase_o <= phase_q; // 返回 committed phase
                    response_packet_seq_o <= packet_seq_q; // 返回 committed packet sequence
                    response_status_o <= 8'd0; // ACK status 成功
                end else begin // 处理 packet 后续 commit flit
                end // 结束 commit 尾部选择
            end // 结束 atomic commit 处理
            if (pipeline_advance) begin // 检查 staging 读流水允许整体前推
                output_last_q <= bank_last_q; // 将 bank 尾标志前推至固定输出级
                if (bank_valid_q[0]) begin // 检查段零存在有效 bank 候选
                    case (bank_high_q[0]) // 选择与 payload 对齐的字节数 bank
                        2'd0: output_bytes_q <= bank_bytes0_q; // 选择 bank 零字节数
                        2'd1: output_bytes_q <= bank_bytes1_q; // 选择 bank 一字节数
                        2'd2: output_bytes_q <= bank_bytes2_q; // 选择 bank 二字节数
                        default: output_bytes_q <= bank_bytes3_q; // 选择 bank 三字节数
                    endcase // 结束字节数 bank 选择
                end // 结束有效 bank 候选处理
                bank_last_q <= address_last_q; // 将地址级尾标志前推至 bank 候选级
                for (stage_index = 0; stage_index < 16; stage_index = stage_index + 1) bank_high_q[stage_index] <= address_high_q[stage_index]; // 传递高位索引副本至 bank 候选级
                if (address_valid_q[0]) begin // 检查段零存在有效读地址
                    case (address_low_q[0]) // 选择 bank 零字节数条目
                        2'd0: bank_bytes0_q <= bytes_mem[0]; // 读取 bank 零字节数零
                        2'd1: bank_bytes0_q <= bytes_mem[1]; // 读取 bank 零字节数一
                        2'd2: bank_bytes0_q <= bytes_mem[2]; // 读取 bank 零字节数二
                        default: bank_bytes0_q <= bytes_mem[3]; // 读取 bank 零字节数三
                    endcase // 结束 bank 零字节数读取
                    case (address_low_q[16]) // 选择 bank 一字节数条目
                        2'd0: bank_bytes1_q <= bytes_mem[4]; // 读取 bank 一字节数零
                        2'd1: bank_bytes1_q <= bytes_mem[5]; // 读取 bank 一字节数一
                        2'd2: bank_bytes1_q <= bytes_mem[6]; // 读取 bank 一字节数二
                        default: bank_bytes1_q <= bytes_mem[7]; // 读取 bank 一字节数三
                    endcase // 结束 bank 一字节数读取
                    case (address_low_q[32]) // 选择 bank 二字节数条目
                        2'd0: bank_bytes2_q <= bytes_mem[8]; // 读取 bank 二字节数零
                        2'd1: bank_bytes2_q <= bytes_mem[9]; // 读取 bank 二字节数一
                        2'd2: bank_bytes2_q <= bytes_mem[10]; // 读取 bank 二字节数二
                        default: bank_bytes2_q <= bytes_mem[11]; // 读取 bank 二字节数三
                    endcase // 结束 bank 二字节数读取
                    case (address_low_q[48]) // 选择 bank 三字节数条目
                        2'd0: bank_bytes3_q <= bytes_mem[12]; // 读取 bank 三字节数零
                        2'd1: bank_bytes3_q <= bytes_mem[13]; // 读取 bank 三字节数一
                        2'd2: bank_bytes3_q <= bytes_mem[14]; // 读取 bank 三字节数二
                        default: bank_bytes3_q <= bytes_mem[15]; // 读取 bank 三字节数三
                    endcase // 结束 bank 三字节数读取
                end // 结束有效地址读取处理
                address_last_q <= read_remaining_q == 5'd1; // 最后一个待读 flit 标记 packet 尾部
                if (commit_active_q && read_remaining_q != 5'd0) begin // 检查需要发射 staging 读地址
                    for (stage_index = 0; stage_index < 64; stage_index = stage_index + 1) address_low_q[stage_index] <= read_index_q[1:0]; // 复制低位索引限制 bank mux 扇出
                    for (stage_index = 0; stage_index < 16; stage_index = stage_index + 1) address_high_q[stage_index] <= read_index_q[3:2]; // 复制高位索引限制输出 mux 扇出
                    read_index_q <= read_index_q + 1'b1; // 推进下一 staging 读索引
                    read_remaining_q <= read_remaining_q - 1'b1; // 递减待读 flit 数量
                end // 结束 staging 读地址发射
            end // 结束读流水整体前推
            for (stage_index = 0; stage_index < 16; stage_index = stage_index + 1) begin // 独立前推十六个三十二位 staging 数据段
                if (!output_valid_q[stage_index] || commit_ready_i) begin // 检查当前数据段流水允许前推
                    output_valid_q[stage_index] <= bank_valid_q[stage_index]; // 前推当前段 bank 候选有效
                    if (bank_valid_q[stage_index]) begin // 检查当前段存在有效 bank 候选
                        case (bank_high_q[stage_index]) // 使用当前段本地 bank 索引选择输出
                            2'd0: output_payload_q[stage_index*32 +: 32] <= bank_payload0_q[stage_index*32 +: 32]; // 选择 bank 零当前段
                            2'd1: output_payload_q[stage_index*32 +: 32] <= bank_payload1_q[stage_index*32 +: 32]; // 选择 bank 一当前段
                            2'd2: output_payload_q[stage_index*32 +: 32] <= bank_payload2_q[stage_index*32 +: 32]; // 选择 bank 二当前段
                            default: output_payload_q[stage_index*32 +: 32] <= bank_payload3_q[stage_index*32 +: 32]; // 选择 bank 三当前段
                        endcase // 结束当前段输出 bank 选择
                    end // 结束当前段有效 bank 处理
                    bank_valid_q[stage_index] <= address_valid_q[stage_index]; // 前推当前段地址有效至 bank 级
                    if (address_valid_q[stage_index]) begin // 检查当前段存在有效读地址
                        case (address_low_q[stage_index]) // 选择 bank 零当前段条目
                            2'd0: bank_payload0_q[stage_index*32 +: 32] <= payload_mem[0][stage_index*32 +: 32]; // 读取 bank 零条目零
                            2'd1: bank_payload0_q[stage_index*32 +: 32] <= payload_mem[1][stage_index*32 +: 32]; // 读取 bank 零条目一
                            2'd2: bank_payload0_q[stage_index*32 +: 32] <= payload_mem[2][stage_index*32 +: 32]; // 读取 bank 零条目二
                            default: bank_payload0_q[stage_index*32 +: 32] <= payload_mem[3][stage_index*32 +: 32]; // 读取 bank 零条目三
                        endcase // 结束 bank 零当前段读取
                        case (address_low_q[16+stage_index]) // 选择 bank 一当前段条目
                            2'd0: bank_payload1_q[stage_index*32 +: 32] <= payload_mem[4][stage_index*32 +: 32]; // 读取 bank 一条目零
                            2'd1: bank_payload1_q[stage_index*32 +: 32] <= payload_mem[5][stage_index*32 +: 32]; // 读取 bank 一条目一
                            2'd2: bank_payload1_q[stage_index*32 +: 32] <= payload_mem[6][stage_index*32 +: 32]; // 读取 bank 一条目二
                            default: bank_payload1_q[stage_index*32 +: 32] <= payload_mem[7][stage_index*32 +: 32]; // 读取 bank 一条目三
                        endcase // 结束 bank 一当前段读取
                        case (address_low_q[32+stage_index]) // 选择 bank 二当前段条目
                            2'd0: bank_payload2_q[stage_index*32 +: 32] <= payload_mem[8][stage_index*32 +: 32]; // 读取 bank 二条目零
                            2'd1: bank_payload2_q[stage_index*32 +: 32] <= payload_mem[9][stage_index*32 +: 32]; // 读取 bank 二条目一
                            2'd2: bank_payload2_q[stage_index*32 +: 32] <= payload_mem[10][stage_index*32 +: 32]; // 读取 bank 二条目二
                            default: bank_payload2_q[stage_index*32 +: 32] <= payload_mem[11][stage_index*32 +: 32]; // 读取 bank 二条目三
                        endcase // 结束 bank 二当前段读取
                        case (address_low_q[48+stage_index]) // 选择 bank 三当前段条目
                            2'd0: bank_payload3_q[stage_index*32 +: 32] <= payload_mem[12][stage_index*32 +: 32]; // 读取 bank 三条目零
                            2'd1: bank_payload3_q[stage_index*32 +: 32] <= payload_mem[13][stage_index*32 +: 32]; // 读取 bank 三条目一
                            2'd2: bank_payload3_q[stage_index*32 +: 32] <= payload_mem[14][stage_index*32 +: 32]; // 读取 bank 三条目二
                            default: bank_payload3_q[stage_index*32 +: 32] <= payload_mem[15][stage_index*32 +: 32]; // 读取 bank 三条目三
                        endcase // 结束 bank 三当前段读取
                    end // 结束当前段有效地址读取
                    address_valid_q[stage_index] <= commit_active_q && read_remaining_q != 5'd0; // 发射当前段新读地址有效
                end // 结束当前数据段流水前推
            end // 结束十六个 staging 数据段前推
        end // 结束 packet receiver 复位选择
    end // 结束 packet receiver 时序逻辑
endmodule // 结束 packet 原子提交和去重单元

/* verilator lint_off DECLFILENAME */ // 允许流式 context 模块与历史 packet commit 文件共存
module coll_packet_rx_stream_commit #( // 定义允许输入输出并行推进的 packet context 提交单元
    parameter integer CONTEXTS = 32 // 配置在途 packet context 数量
) ( // 开始流式提交端口声明
    input wire clk_i, // 接收 link core 时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire flit_valid_i, // 接收 CRC 流水输出 flit 有效
    input wire crc_good_i, // 接收当前 flit CRC 检查结果
    /* verilator lint_off UNUSEDSIGNAL */ input wire [95:0] header_i, // 接收当前 flit header
    /* verilator lint_on UNUSEDSIGNAL */
    input wire [511:0] payload_i, // 接收当前 flit payload
    input wire [6:0] payload_bytes_i, // 接收当前 flit 有效字节数
    output wire flit_ready_o, // 返回 packet context 接收能力
    output wire commit_valid_o, // 输出流式 commit flit 有效
    input wire commit_ready_i, // 接收下游 commit 能力
    output wire [511:0] commit_payload_o, // 输出当前 commit payload
    output wire [6:0] commit_payload_bytes_o, // 输出当前 commit 有效字节数
    output wire commit_last_o, // 输出当前 commit packet 尾标志
    output wire [11:0] commit_collective_id_o, // 输出当前 packet collective ID
    output wire commit_phase_o, // 输出当前 packet phase
    output wire [1:0] commit_dtype_o, // 输出当前 packet dtype
    output wire [15:0] commit_chunk_id_o, // 输出当前 packet chunk ID
    output wire [15:0] commit_packet_seq_o, // 输出当前 packet sequence
    output reg ack_valid_o, // 输出完整 packet ACK 旁路脉冲
    output reg nack_valid_o, // 输出坏 packet NACK 旁路脉冲
    output reg [11:0] response_collective_id_o, // 输出 ACK NACK collective ID
    output reg response_phase_o, // 输出 ACK NACK phase
    output reg [15:0] response_packet_seq_o, // 输出 ACK NACK packet sequence
    output reg [7:0] response_status_o, // 输出 ACK NACK 状态
    output reg duplicate_o // 输出 duplicate 丢弃脉冲
); // 结束流式提交端口声明
    localparam integer SLOT_W = 5; // 定义三十二 context 的索引宽度
    localparam [SLOT_W:0] CONTEXTS_LIMIT = 6'd32; // 保存 context queue 容量的匹配位宽
    reg [511:0] payload_mem [0:CONTEXTS-1][0:15]; // 保存各 context 的 packet payload
    reg [6:0] bytes_mem [0:CONTEXTS-1][0:15]; // 保存各 context 的 payload 字节数
    reg [11:0] slot_collective_q [0:CONTEXTS-1]; // 保存各 context collective ID
    reg slot_phase_q [0:CONTEXTS-1]; // 保存各 context phase
    reg [1:0] slot_dtype_q [0:CONTEXTS-1]; // 保存各 context dtype
    reg [15:0] slot_chunk_q [0:CONTEXTS-1]; // 保存各 context chunk ID
    reg [15:0] slot_sequence_q [0:CONTEXTS-1]; // 保存各 context packet sequence
    reg [2:0] slot_source_q [0:CONTEXTS-1]; // 保存各 context source rank
    reg [7:0] slot_epoch_q [0:CONTEXTS-1]; // 保存各 context link epoch
    reg [4:0] slot_flits_q [0:CONTEXTS-1]; // 保存各 context packet flit 数量
    reg [SLOT_W-1:0] head_q; // 保存最老已完成 context 索引
    reg [SLOT_W-1:0] tail_q; // 保存下一个可分配 context 索引
    reg [SLOT_W:0] queue_count_q; // 保存已完成待提交 context 数量
    reg rx_active_q; // 指示当前输入 packet 正在接收
    reg drain_bad_q; // 指示当前坏 packet 正在 drain 至 EOP
    reg duplicate_q; // 保存当前 packet 是否命中 exact-once history
    reg [SLOT_W-1:0] rx_slot_q; // 保存当前输入 packet context 索引
    reg [3:0] rx_count_q; // 保存当前输入 packet 已接收 flit 数量
    reg [7:0] expected_seq_q; // 保存当前输入 packet 下一个期望 flit sequence
    reg [11:0] rx_collective_q; // 保存当前输入 packet collective ID
    reg rx_phase_q; // 保存当前输入 packet phase
    reg [1:0] rx_dtype_q; // 保存当前输入 packet dtype
    reg [15:0] rx_chunk_q; // 保存当前输入 packet chunk ID
    reg [15:0] rx_sequence_q; // 保存当前输入 packet sequence
    reg [2:0] rx_source_q; // 保存当前输入 packet source rank
    reg [7:0] rx_epoch_q; // 保存当前输入 packet epoch
    reg [3:0] out_index_q; // 保存当前输出 packet flit 索引
    wire input_fire; // 指示当前 CRC flit 被 context 接收
    wire output_fire; // 指示当前 commit flit 被下游接收
    wire output_last_now; // 指示当前输出 flit 是 packet 尾部
    wire queue_full; // 指示 context queue 已满
    wire sop_i; // 提取当前 flit SOP
    wire eop_i; // 提取当前 flit EOP
    wire identity_match; // 指示当前 flit identity 与 packet 首 flit一致
    wire history_match; // 指示当前 SOP 命中已提交 history
    wire flit_error; // 指示当前 flit framing CRC 或序列错误
    wire enqueue_event; // 指示当前输入 packet 完成并进入 context queue
    wire dequeue_event; // 指示当前输出 packet 完成并离开 context queue
    wire [3:0] history_match_group; // 保存四组 history 查询结果
    /* verilator lint_off UNUSEDSIGNAL */ wire commit_active_q; // 保留测试平台 active 观测且不参与数据路径
    /* verilator lint_on UNUSEDSIGNAL */
    integer reset_index; // 提供 context 元数据复位索引
    assign queue_full = queue_count_q >= CONTEXTS_LIMIT; // 判断已完成 context 是否达到容量
    assign flit_ready_o = drain_bad_q || rx_active_q || !queue_full || dequeue_event; // 输入 ready 不依赖下游 ready，满 context 时才施加背压
    assign input_fire = flit_valid_i && flit_ready_o; // 形成输入握手
    assign sop_i = header_i[81]; // 提取 SOP header 位
    assign eop_i = header_i[82]; // 提取 EOP header 位
    assign identity_match = header_i[33:22] == rx_collective_q && header_i[11] == rx_phase_q && header_i[13:12] == rx_dtype_q && header_i[49:34] == rx_chunk_q && header_i[65:50] == rx_sequence_q && header_i[18:16] == rx_source_q && header_i[91:84] == rx_epoch_q; // 比较 packet identity
    assign history_match = |history_match_group; // 合并 history 命中分组
    assign flit_error = !crc_good_i || header_i[3:0] != 4'd1 || header_i[7:4] != 4'd0 || header_i[10:8] > 3'd2 || header_i[80:74] != payload_bytes_i || payload_bytes_i > 7'd64 || header_i[18:16] > 3'd3 || header_i[21:19] > 3'd3 || (!rx_active_q && !sop_i) || (rx_active_q && (sop_i || !identity_match || header_i[73:66] != expected_seq_q || header_i[81])) || (rx_active_q && rx_count_q == 4'd15 && !eop_i); // 汇总输入 packet 协议错误
    assign commit_active_q = queue_count_q != 0; // 提供测试平台 active 观测且不参与数据路径
    assign output_last_now = queue_count_q != 0 && out_index_q == (slot_flits_q[head_q][3:0] - 4'd1); // 判断当前输出 context 尾 flit
    assign commit_valid_o = queue_count_q != 0; // 只要 queue 非空就持续输出 commit flit
    assign commit_payload_o = payload_mem[head_q][out_index_q]; // 输出当前 context payload
    assign commit_payload_bytes_o = bytes_mem[head_q][out_index_q]; // 输出当前 context 字节数
    assign commit_last_o = commit_valid_o && output_last_now; // 输出 packet 尾标志
    assign commit_collective_id_o = slot_collective_q[head_q]; // 输出当前 context collective ID
    assign commit_phase_o = slot_phase_q[head_q]; // 输出当前 context phase
    assign commit_dtype_o = slot_dtype_q[head_q]; // 输出当前 context dtype
    assign commit_chunk_id_o = slot_chunk_q[head_q]; // 输出当前 context chunk ID
    assign commit_packet_seq_o = slot_sequence_q[head_q]; // 输出当前 context packet sequence
    assign output_fire = commit_valid_o && commit_ready_i; // 形成 commit 输出握手
    assign dequeue_event = output_fire && output_last_now; // 形成 packet 完成事件
    assign enqueue_event = input_fire && !drain_bad_q && !flit_error && eop_i && !(duplicate_q || (!rx_active_q && history_match)); // 仅新 packet EOP 分配 queue entry
    coll_rx_identity_history u_identity_history ( // 实例化可流水查询和提交的 exact-once history
        .clk_i(clk_i), .rst_n_i(rst_n_i), .query_collective_id_i(header_i[33:22]), .query_phase_i(header_i[11]), .query_packet_seq_i(header_i[65:50]), .query_src_rank_i(header_i[18:16]), .query_epoch_i(header_i[91:84]), .query_match_group_o(history_match_group), // 连接当前 SOP identity 查询
        .commit_valid_i(dequeue_event), .commit_collective_id_i(slot_collective_q[head_q]), .commit_phase_i(slot_phase_q[head_q]), .commit_packet_seq_i(slot_sequence_q[head_q]), .commit_src_rank_i(slot_source_q[head_q]), .commit_epoch_i(slot_epoch_q[head_q]) // 仅完整输出后写入 history
    ); // 结束 history 实例
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 context 分配、输入解析、输出提交和旁路响应
        if (!rst_n_i) begin // 检测复位有效
            head_q <= {SLOT_W{1'b0}}; // 清零 context 读指针
            tail_q <= {SLOT_W{1'b0}}; // 清零 context 写指针
            queue_count_q <= {(SLOT_W+1){1'b0}}; // 清零完成 queue 占用
            rx_active_q <= 1'b0; // 清除输入 packet 状态
            drain_bad_q <= 1'b0; // 清除坏 packet drain 状态
            duplicate_q <= 1'b0; // 清除 duplicate 状态
            rx_slot_q <= {SLOT_W{1'b0}}; // 清零输入 context 索引
            rx_count_q <= 4'd0; // 清零输入 flit 计数
            expected_seq_q <= 8'd0; // 清零输入 sequence 期望
            rx_collective_q <= 12'd0; // 清零输入 collective
            rx_phase_q <= 1'b0; // 清零输入 phase
            rx_dtype_q <= 2'd0; // 清零输入 dtype
            rx_chunk_q <= 16'd0; // 清零输入 chunk
            rx_sequence_q <= 16'd0; // 清零输入 sequence
            rx_source_q <= 3'd0; // 清零输入 source
            rx_epoch_q <= 8'd0; // 清零输入 epoch
            out_index_q <= 4'd0; // 清零输出 flit 索引
            ack_valid_o <= 1'b0; // 清除 ACK 脉冲
            nack_valid_o <= 1'b0; // 清除 NACK 脉冲
            response_collective_id_o <= 12'd0; // 清零 response collective
            response_phase_o <= 1'b0; // 清零 response phase
            response_packet_seq_o <= 16'd0; // 清零 response sequence
            response_status_o <= 8'd0; // 清零 response status
            duplicate_o <= 1'b0; // 清除 duplicate 脉冲
            for (reset_index = 0; reset_index < CONTEXTS; reset_index = reset_index + 1) begin // 复位所有 context 元数据
                slot_collective_q[reset_index] <= 12'd0; // 清零 context collective
                slot_phase_q[reset_index] <= 1'b0; // 清零 context phase
                slot_dtype_q[reset_index] <= 2'd0; // 清零 context dtype
                slot_chunk_q[reset_index] <= 16'd0; // 清零 context chunk
                slot_sequence_q[reset_index] <= 16'd0; // 清零 context sequence
                slot_source_q[reset_index] <= 3'd0; // 清零 context source
                slot_epoch_q[reset_index] <= 8'd0; // 清零 context epoch
                slot_flits_q[reset_index] <= 5'd0; // 清零 context flit 数量
            end // 结束 context 元数据复位
        end else begin // 处理流式 context 正常运行
            ack_valid_o <= 1'b0; // 默认清除 ACK 脉冲
            nack_valid_o <= 1'b0; // 默认清除 NACK 脉冲
            duplicate_o <= 1'b0; // 默认清除 duplicate 脉冲
            case ({enqueue_event, dequeue_event}) // 合并输入入队和输出出队计数
                2'b10: queue_count_q <= queue_count_q + 1'b1; // 仅输入完成 packet 时增加占用
                2'b01: queue_count_q <= queue_count_q - 1'b1; // 仅输出完成 packet 时减少占用
                default: queue_count_q <= queue_count_q; // 同拍入出或空闲时保持占用
            endcase // 结束 queue 占用更新
            if (enqueue_event) tail_q <= tail_q + 1'b1; // 推进 context 写指针
            if (dequeue_event) head_q <= head_q + 1'b1; // 推进 context 读指针
            if (output_fire) begin // 检查当前 commit flit 被下游接受
                if (output_last_now) begin // 检查当前 packet 输出完成
                    out_index_q <= 4'd0; // 为下一个 packet 清零 flit 索引
                    ack_valid_o <= 1'b1; // 输出完成 packet ACK 旁路脉冲
                    response_collective_id_o <= slot_collective_q[head_q]; // 返回完成 packet collective
                    response_phase_o <= slot_phase_q[head_q]; // 返回完成 packet phase
                    response_packet_seq_o <= slot_sequence_q[head_q]; // 返回完成 packet sequence
                    response_status_o <= 8'd0; // 返回成功状态
                end else begin // 处理 packet 中间 flit 输出
                    out_index_q <= out_index_q + 1'b1; // 推进输出 flit 索引
                end // 结束输出 packet 边界处理
            end // 结束 commit 输出握手处理
            if (input_fire) begin // 检查当前 CRC flit 被输入 context 接收
                if (drain_bad_q) begin // 处理坏 packet drain 状态
                    if (eop_i) drain_bad_q <= 1'b0; // 在 EOP 后释放坏 packet drain
                end else if (flit_error) begin // 处理当前 flit 协议错误
                    nack_valid_o <= 1'b1; // 输出精确 NACK 旁路脉冲
                    response_collective_id_o <= rx_active_q ? rx_collective_q : header_i[33:22]; // 返回 packet collective
                    response_phase_o <= rx_active_q ? rx_phase_q : header_i[11]; // 返回 packet phase
                    response_packet_seq_o <= rx_active_q ? rx_sequence_q : header_i[65:50]; // 返回 packet sequence
                    response_status_o <= crc_good_i ? 8'h33 : 8'h30; // 区分 framing 和 CRC 错误
                    if (eop_i) begin // 处理错误 flit 同时为 packet 尾部
                        rx_active_q <= 1'b0; // 直接结束当前 packet
                        drain_bad_q <= 1'b0; // 清除坏 packet drain
                    end else begin // 处理错误 packet 仍有后续 flit
                        drain_bad_q <= 1'b1; // 继续 drain 至 EOP
                    end // 结束错误 packet 边界处理
                end else if (!rx_active_q) begin // 处理合法 SOP flit
                    rx_slot_q <= tail_q; // 分配当前 packet context
                    rx_collective_q <= header_i[33:22]; // 锁存 packet collective
                    rx_phase_q <= header_i[11]; // 锁存 packet phase
                    rx_dtype_q <= header_i[13:12]; // 锁存 packet dtype
                    rx_chunk_q <= header_i[49:34]; // 锁存 packet chunk
                    rx_sequence_q <= header_i[65:50]; // 锁存 packet sequence
                    rx_source_q <= header_i[18:16]; // 锁存 packet source
                    rx_epoch_q <= header_i[91:84]; // 锁存 packet epoch
                    duplicate_q <= history_match; // 锁存当前 packet duplicate 状态
                    payload_mem[tail_q][0] <= payload_i; // 写入 packet SOP payload
                    bytes_mem[tail_q][0] <= payload_bytes_i; // 写入 packet SOP 字节数
                    slot_collective_q[tail_q] <= header_i[33:22]; // 写入 context collective
                    slot_phase_q[tail_q] <= header_i[11]; // 写入 context phase
                    slot_dtype_q[tail_q] <= header_i[13:12]; // 写入 context dtype
                    slot_chunk_q[tail_q] <= header_i[49:34]; // 写入 context chunk
                    slot_sequence_q[tail_q] <= header_i[65:50]; // 写入 context sequence
                    slot_source_q[tail_q] <= header_i[18:16]; // 写入 context source
                    slot_epoch_q[tail_q] <= header_i[91:84]; // 写入 context epoch
                    slot_flits_q[tail_q] <= 5'd1; // 默认记录 SOP 单 flit
                    if (eop_i) begin // 处理单 flit packet
                        rx_active_q <= 1'b0; // 清除输入 packet 状态
                        if (history_match) begin // 处理 duplicate 单 flit packet
                            ack_valid_o <= 1'b1; // duplicate 重新 ACK
                            response_collective_id_o <= header_i[33:22]; // 返回 duplicate collective
                            response_phase_o <= header_i[11]; // 返回 duplicate phase
                            response_packet_seq_o <= header_i[65:50]; // 返回 duplicate sequence
                            response_status_o <= 8'd0; // 返回 duplicate 成功状态
                            duplicate_o <= 1'b1; // 报告 duplicate 丢弃
                        end // 结束 duplicate 单 flit处理
                    end else begin // 处理多 flit packet SOP
                        rx_active_q <= 1'b1; // 保持输入 packet 状态
                        rx_count_q <= 4'd1; // 下一 flit 写入索引一
                        expected_seq_q <= 8'd1; // 下一 flit 期望 sequence 一
                    end // 结束 SOP 边界处理
                end else begin // 处理合法 packet 中间或尾 flit
                    payload_mem[rx_slot_q][rx_count_q] <= payload_i; // 写入当前 packet payload
                    bytes_mem[rx_slot_q][rx_count_q] <= payload_bytes_i; // 写入当前 packet 字节数
                    slot_flits_q[rx_slot_q] <= rx_count_q + 1'b1; // 更新当前 packet flit 数量
                    if (eop_i) begin // 处理 packet EOP flit
                        rx_active_q <= 1'b0; // 结束输入 packet 状态
                        if (duplicate_q) begin // 处理 duplicate 多 flit packet
                            ack_valid_o <= 1'b1; // duplicate 重新 ACK
                            response_collective_id_o <= rx_collective_q; // 返回 duplicate collective
                            response_phase_o <= rx_phase_q; // 返回 duplicate phase
                            response_packet_seq_o <= rx_sequence_q; // 返回 duplicate sequence
                            response_status_o <= 8'd0; // 返回 duplicate 成功状态
                            duplicate_o <= 1'b1; // 报告 duplicate 丢弃
                        end // 结束 duplicate 多 flit处理
                    end else begin // 处理 packet 中间 flit
                        rx_count_q <= rx_count_q + 1'b1; // 推进输入 flit 索引
                        expected_seq_q <= expected_seq_q + 1'b1; // 推进输入 sequence 期望
                    end // 结束 packet EOP 处理
                end // 结束输入 flit 状态选择
            end // 结束输入 flit 握手处理
        end // 结束流式 context 正常运行
    end // 结束流式 context 时序逻辑
endmodule // 结束并行 packet context 提交单元
/* verilator lint_on DECLFILENAME */ // 恢复文件名检查
