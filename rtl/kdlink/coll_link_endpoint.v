`include "collective_defs.vh" // 引入 VC reverse 和 header 固定编码
module coll_link_endpoint #( // 定义单 hop VC credit CRC replay 和 PHY CDC 完整端点
    parameter STREAM_MODE = 1'b1 // 默认启用数据面静态窗口无反馈流式传输
) ( // 开始端口声明
    input  wire coll_clk_i, // 接收 collective core 时钟
    input  wire coll_rst_n_i, // 接收 collective 域低有效异步复位
    input  wire phy_clk_i, // 接收 PHY adapter 时钟
    input  wire phy_rst_n_i, // 接收 PHY 域低有效异步复位
    input  wire [1:0] local_rank_i, // 接收本 hop 本地 rank
    input  wire [7:0] link_epoch_i, // 接收当前 link epoch
    input  wire credit_init_valid_i, // 指示初始化一个 TX VC credit
    input  wire [1:0] credit_init_vc_i, // 接收初始化目标 VC
    input  wire [6:0] credit_init_count_i, // 接收初始化 credit 数量
    input  wire tx_vc0_valid_i, // 指示 VC0 packetized flit 有效
    output wire tx_vc0_ready_o, // 返回 VC0 flit 接收能力
    input  wire [639:0] tx_vc0_flit_i, // 接收 VC0 logical flit
    input  wire [4:0] tx_vc0_packet_flits_i, // 接收 VC0 队首完整 packet flit 数
    input  wire tx_vc1_valid_i, // 指示 VC1 packetized flit 有效
    output wire tx_vc1_ready_o, // 返回 VC1 flit 接收能力
    input  wire [639:0] tx_vc1_flit_i, // 接收 VC1 logical flit
    input  wire [4:0] tx_vc1_packet_flits_i, // 接收 VC1 队首完整 packet flit 数
    input  wire tx_vc2_valid_i, // 指示 VC2 packetized control flit 有效
    output wire tx_vc2_ready_o, // 返回 VC2 control flit 接收能力
    input  wire [639:0] tx_vc2_flit_i, // 接收 VC2 logical control flit
    input  wire [4:0] tx_vc2_packet_flits_i, // 接收 VC2 队首完整 packet flit 数
    output wire rx_commit_valid_o, // 指示一个 atomic committed RX payload 有效
    input  wire rx_commit_ready_i, // 接收下游 reduction DMA 接收能力
    output wire [511:0] rx_commit_payload_o, // 输出 committed RX payload
    output wire [6:0] rx_commit_bytes_o, // 输出 committed RX payload 有效字节数
    output wire rx_commit_last_o, // 指示 committed packet 尾 flit
    output wire [11:0] rx_commit_collective_id_o, // 输出 committed collective ID
    output wire rx_commit_phase_o, // 输出 committed phase
    output wire [1:0] rx_commit_dtype_o, // 输出 committed dtype
    output wire [15:0] rx_commit_chunk_id_o, // 输出 committed chunk ID
    output wire [15:0] rx_commit_packet_seq_o, // 输出 committed packet sequence
    output wire rx_ctrl_valid_o, // 指示一条已校验 global control token 有效
    input  wire rx_ctrl_ready_i, // 接收 rendezvous 控制器接收能力
    output wire [3:0] rx_ctrl_message_type_o, // 输出 global control 消息类型
    output wire [1:0] rx_ctrl_origin_rank_o, // 输出 token origin rank
    output wire [11:0] rx_ctrl_collective_id_o, // 输出 token collective ID
    output wire [31:0] rx_ctrl_signature_o, // 输出 descriptor signature
    output wire [3:0] rx_ctrl_ready_mask_o, // 输出 token ready mask
    output wire [3:0] rx_ctrl_visited_mask_o, // 输出 token visited mask
    output wire [7:0] rx_ctrl_generation_o, // 输出 setup generation
    output wire [7:0] rx_ctrl_status_o, // 输出 token status
    output wire [1:0] rx_ctrl_offending_rank_o, // 输出 offending rank
    output wire [31:0] rx_ctrl_length_bytes_o, // 输出 token Tensor 长度
    output wire [2:0] rx_ctrl_opcode_o, // 输出 token opcode
    output wire [1:0] rx_ctrl_dtype_o, // 输出 token dtype
    output wire retry_exhausted_o, // 指示 packet 达到七次 replay 上限
    output wire replay_empty_o, // 指示全部可靠 data packet 已收到 ACK 并释放 replay window
    output wire [27:0] tx_credit_count_o, // 输出四 VC 当前 TX credit
    output wire credit_error_o, // 汇总 credit underflow overflow 和 stale return
    output wire protocol_error_o, // 指示 RX header 或 reverse CRC 协议错误
    output wire duplicate_drop_o, // 指示 RX duplicate packet 被 exact-once 丢弃
    output wire cdc_error_o, // 汇总 PHY async FIFO 不变量错误
    output wire [639:0] phy_fwd_tx_flit_o, // 输出 PHY 域 forward TX flit
    output wire phy_fwd_tx_valid_o, // 指示 PHY 域 forward TX 有效
    input  wire phy_fwd_tx_ready_i, // 接收 PHY forward TX 能力
    input  wire [639:0] phy_fwd_rx_flit_i, // 接收 PHY 域 forward RX flit
    input  wire phy_fwd_rx_valid_i, // 接收 PHY 域 forward RX 有效
    output wire phy_fwd_rx_ready_o, // 返回 PHY forward RX 能力
    output wire [95:0] phy_rev_tx_word_o, // 输出 PHY 域 reverse TX word
    output wire phy_rev_tx_valid_o, // 指示 PHY 域 reverse TX 有效
    input  wire phy_rev_tx_ready_i, // 接收 PHY reverse TX 能力
    input  wire [95:0] phy_rev_rx_word_i, // 接收 PHY 域 reverse RX word
    input  wire phy_rev_rx_valid_i, // 接收 PHY 域 reverse RX 有效
    output wire phy_rev_rx_ready_o // 返回 PHY reverse RX 能力
); // 结束端口声明
    wire [644:0] tx_fifo0_data; wire [644:0] tx_fifo1_data; wire [644:0] tx_fifo2_data; wire [644:0] tx_fifo3_data; // 保存四 VC TX FIFO 队首 flit 和 packet 大小
    wire [6:0] tx_fifo3_count; // 保存 replay VC TX FIFO 占用
    wire tx_fifo0_valid; wire tx_fifo1_valid; wire tx_fifo2_valid; wire tx_fifo3_valid; // 保存四 VC TX FIFO 有效
    wire tx_fifo0_push_ready; wire tx_fifo1_push_ready; wire tx_fifo2_push_ready; wire tx_fifo3_push_ready; // 保存四 VC TX FIFO 写能力
    wire [3:0] tx_fifo_pop; // 保存 TX arbiter 四 VC pop
    wire [3:0] tx_credit_admit; // 保存四 VC packet admission
    wire tx_arb_valid; wire [639:0] tx_arb_flit; wire [1:0] tx_arb_vc; // 保存 TX VC arbitration 输出
    wire coll_phy_tx_ready; // 保存 PHY CDC collective 侧 forward TX 能力
    wire tx_send_fire; // 指示一个 forward flit 进入 PHY CDC
    wire credit_underflow; wire credit_overflow; wire credit_stale; // 保存 credit bank 错误脉冲
    wire original_select_vc0; wire original_select_vc1; wire original_fire; // 保存 replay store 输入选择
    wire [607:0] original_body; // 保存当前写 replay RAM 的原始 header 和 payload
    wire replay_store_ready; wire [(STREAM_MODE ? 5 : 3):0] replay_occupancy; // 保存 replay RAM 接收能力和参数化窗口占用
    wire replay_valid; wire replay_ready; wire [607:0] replay_body; // 保存 replay RAM 输出 body
    wire replay_crc_valid; wire [31:0] replay_crc; wire [95:0] replay_header; wire [511:0] replay_payload; // 保存 replay CRC 流水输出
    reg [6:0] replay_crc_inflight_q; // 保存已进入 CRC 尚未写 VC3 FIFO 的 replay flit 数
    wire replay_crc_fire; // 指示一个 replay body 进入 CRC 流水
    wire replay_fifo_push; // 指示一个重算 CRC 的 replay flit写入 VC3 FIFO
    wire [639:0] coll_phy_rx_flit; wire coll_phy_rx_valid; wire coll_phy_rx_ready; // 保存 PHY CDC collective 侧 forward RX
    wire [1:0] coll_phy_rx_vc; // 保存 RX flit header VC
    wire [3:0] rx_fifo_push; wire [3:0] rx_fifo_push_ready; // 保存四 VC RX FIFO push handshake
    wire [639:0] rx_fifo0_data; wire [639:0] rx_fifo1_data; wire [639:0] rx_fifo2_data; wire [639:0] rx_fifo3_data; // 保存四 VC RX FIFO 队首
    wire [3:0] rx_fifo_valid; wire [3:0] rx_fifo_pop; // 保存四 VC RX FIFO pop 握手
    wire rx_arb_valid; wire [639:0] rx_arb_flit; wire [1:0] rx_arb_vc; // 保存 RX packet boundary arbitration 输出
    /* verilator lint_off UNUSEDSIGNAL */ reg rx_wait_response_q; // 保留测试平台 debug 观测且不参与数据准入
    /* verilator lint_on UNUSEDSIGNAL */
    reg ctrl_pending_q; // 保存已通过 CRC 的 global control token
    reg [3:0] ctrl_message_q; reg [1:0] ctrl_origin_q; reg [11:0] ctrl_collective_q; // 保存 control identity
    reg [31:0] ctrl_signature_q; reg [3:0] ctrl_ready_mask_q; reg [3:0] ctrl_visited_mask_q; // 保存 control setup masks
    reg [7:0] ctrl_generation_q; reg [7:0] ctrl_status_q; reg [1:0] ctrl_offending_q; // 保存 control diagnostic fields
    reg [31:0] ctrl_length_q; reg [2:0] ctrl_opcode_q; reg [1:0] ctrl_dtype_q; // 保存 control descriptor fields
    wire rx_dispatch_enable; wire rx_dispatch_fire; // 保存 RX dispatch 资源准入
    wire depacket_valid; wire depacket_crc_good; wire [95:0] depacket_header; wire [511:0] depacket_payload; wire [6:0] depacket_bytes; // 保存 DATA depacketizer 检查输出
    wire ctrl_depacket_valid; wire ctrl_depacket_crc_good; wire [95:0] ctrl_depacket_header; /* verilator lint_off UNUSEDSIGNAL */ wire [511:0] ctrl_depacket_payload; /* verilator lint_on UNUSEDSIGNAL */ wire [6:0] ctrl_depacket_bytes; // 保存控制 depacketizer 检查输出且保留协议 reserved 位
    wire header_valid; // 保存 DATA forward header checker 结果
    wire ctrl_header_valid; wire [7:0] ctrl_header_status; // 保存控制 forward header checker 结果
    wire commit_flit_ready; wire commit_ack; wire commit_nack; wire [11:0] response_collective; wire response_phase; wire [15:0] response_sequence; wire [7:0] response_status; // 保存 atomic commit response
    reg [15:0] rx_credit_total_q [0:3]; // 保存每 VC 累计释放 RX 槽位总数
    wire reverse_event_valid; wire [3:0] reverse_event_type; wire [1:0] reverse_event_vc; wire [11:0] reverse_event_collective; wire reverse_event_phase; // 保存待编码 reverse 事件
    wire [15:0] reverse_event_sequence; wire [7:0] reverse_event_status; wire [15:0] reverse_event_credit_total; // 保存待编码 reverse 事件状态
    wire reverse_codec_tx_valid; wire [95:0] reverse_codec_tx_word; // 保存 reverse encoder 输出
    wire reverse_fifo_push_ready; wire reverse_fifo_valid; wire [95:0] reverse_fifo_word; // 保存 reverse TX 弹性 FIFO 状态
    reg [6:0] reverse_codec_inflight_q; // 保存已进入 reverse codec 尚未写 FIFO 的 word 数
    wire [95:0] coll_reverse_rx_word; wire coll_reverse_rx_valid; // 保存 PHY CDC collective 侧 reverse RX
    wire reverse_rx_valid; wire reverse_rx_crc_good; /* verilator lint_off UNUSEDSIGNAL */ wire [79:0] reverse_rx_body; /* verilator lint_on UNUSEDSIGNAL */ // 保存 reverse decoder 输出且保留诊断字段
    wire reverse_credit_valid; wire reverse_ack_valid; wire reverse_nack_valid; // 保存合法 reverse 消息分类
    wire reverse_epoch_good; // 指示 reverse word epoch 与当前 link 一致
    wire phy_reverse_coll_ready; // 保存 PHY CDC collective 侧 reverse TX 能力
    wire [3:0] rx_fifo_unused_overflow; wire [3:0] rx_fifo_unused_underflow; // 接收同步 FIFO 不变量端口
    integer vc_index; // 提供四 VC 累计 credit 复位索引
    assign original_select_vc0 = tx_vc0_valid_i; // 固定 VC0 为 replay store 输入首优先级
    assign original_select_vc1 = !tx_vc0_valid_i && tx_vc1_valid_i; // VC0 空闲时选择 VC1 replay store 输入
    assign tx_vc0_ready_o = tx_fifo0_push_ready && replay_store_ready; // VC0 同时保留 TX FIFO 和 replay entry
    assign tx_vc1_ready_o = !tx_vc0_valid_i && tx_fifo1_push_ready && replay_store_ready; // VC1 在单端口 replay store 可用时接收
    assign tx_vc2_ready_o = tx_fifo2_push_ready; // VC2 control 不进入 data replay RAM
    assign original_fire = (original_select_vc0 && tx_vc0_ready_o) || (original_select_vc1 && tx_vc1_ready_o); // 形成原始 data flit 接收握手
    assign original_body = original_select_vc0 ? tx_vc0_flit_i[607:0] : tx_vc1_flit_i[607:0]; // 选择当前原始 data body
    coll_sync_fifo #(.WIDTH(645), .DEPTH(64), .ADDR_W(6), .COUNT_W(7)) u_tx_fifo0 (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .push_data_i({tx_vc0_packet_flits_i, tx_vc0_flit_i}), .push_valid_i(tx_vc0_valid_i && tx_vc0_ready_o), .push_ready_o(tx_fifo0_push_ready), .pop_data_o(tx_fifo0_data), .pop_valid_o(tx_fifo0_valid), .pop_ready_i(tx_fifo_pop[0]), .occupancy_o(), .overflow_o(), .underflow_o()); // 实例化 VC0 TX FIFO
    coll_sync_fifo #(.WIDTH(645), .DEPTH(64), .ADDR_W(6), .COUNT_W(7)) u_tx_fifo1 (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .push_data_i({tx_vc1_packet_flits_i, tx_vc1_flit_i}), .push_valid_i(tx_vc1_valid_i && tx_vc1_ready_o), .push_ready_o(tx_fifo1_push_ready), .pop_data_o(tx_fifo1_data), .pop_valid_o(tx_fifo1_valid), .pop_ready_i(tx_fifo_pop[1]), .occupancy_o(), .overflow_o(), .underflow_o()); // 实例化 VC1 TX FIFO
    coll_sync_fifo #(.WIDTH(645), .DEPTH(64), .ADDR_W(6), .COUNT_W(7)) u_tx_fifo2 (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .push_data_i({tx_vc2_packet_flits_i, tx_vc2_flit_i}), .push_valid_i(tx_vc2_valid_i && tx_vc2_ready_o), .push_ready_o(tx_fifo2_push_ready), .pop_data_o(tx_fifo2_data), .pop_valid_o(tx_fifo2_valid), .pop_ready_i(tx_fifo_pop[2]), .occupancy_o(), .overflow_o(), .underflow_o()); // 实例化 VC2 TX FIFO
    coll_sync_fifo #(.WIDTH(645), .DEPTH(64), .ADDR_W(6), .COUNT_W(7)) u_tx_fifo3 (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .push_data_i({5'd16, replay_crc, replay_header, replay_payload}), .push_valid_i(replay_fifo_push), .push_ready_o(tx_fifo3_push_ready), .pop_data_o(tx_fifo3_data), .pop_valid_o(tx_fifo3_valid), .pop_ready_i(tx_fifo_pop[3]), .occupancy_o(tx_fifo3_count), .overflow_o(), .underflow_o()); // 实例化 VC3 replay TX FIFO
    coll_vc_credit_bank #(.STREAM_MODE(STREAM_MODE)) u_tx_credit (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .init_valid_i(credit_init_valid_i), .init_vc_i(credit_init_vc_i), .init_credit_i(credit_init_count_i), .send_valid_i(tx_send_fire), .send_vc_i(tx_arb_vc), .return_valid_i(reverse_credit_valid), .return_vc_i(reverse_rx_body[9:8]), .return_total_i(reverse_rx_body[79:64]), .reserve_flits0_i(tx_fifo0_data[644:640]), .reserve_flits1_i(tx_fifo1_data[644:640]), .reserve_flits2_i(tx_fifo2_data[644:640]), .reserve_flits3_i(tx_fifo3_data[644:640]), .admit_o(tx_credit_admit), .credit_count_o(tx_credit_count_o), .underflow_o(credit_underflow), .overflow_o(credit_overflow), .stale_return_o(credit_stale)); // 实例化四 VC TX credit bank
    coll_vc_arbiter u_tx_arbiter (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .valid_i({tx_fifo3_valid, tx_fifo2_valid, tx_fifo1_valid, tx_fifo0_valid}), .admit_i(tx_credit_admit), .flit0_i(tx_fifo0_data[639:0]), .flit1_i(tx_fifo1_data[639:0]), .flit2_i(tx_fifo2_data[639:0]), .flit3_i(tx_fifo3_data[639:0]), .ready_o(tx_fifo_pop), .valid_o(tx_arb_valid), .ready_i(coll_phy_tx_ready), .flit_o(tx_arb_flit), .vc_o(tx_arb_vc)); // 按 packet boundary 仲裁四 VC TX
    assign tx_send_fire = tx_arb_valid && coll_phy_tx_ready; // 仅 PHY CDC 接受后扣减 credit
    coll_replay_buffer #(.ENTRIES(STREAM_MODE ? 32 : 8), .INDEX_WIDTH(STREAM_MODE ? 5 : 3)) u_replay (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .store_start_i(original_fire && original_body[593]), .store_collective_id_i(original_body[545:534]), .store_phase_i(original_body[523]), .store_packet_seq_i(original_body[577:562]), .store_valid_i(original_fire), .store_body_i(original_body), .store_last_i(original_body[594]), .store_ready_o(replay_store_ready), .ack_valid_i(reverse_ack_valid), .ack_collective_id_i(reverse_rx_body[29:18]), .ack_phase_i(reverse_rx_body[30]), .ack_packet_seq_i(reverse_rx_body[46:31]), .nack_valid_i(reverse_nack_valid), .nack_collective_id_i(reverse_rx_body[29:18]), .nack_phase_i(reverse_rx_body[30]), .nack_packet_seq_i(reverse_rx_body[46:31]), .replay_valid_o(replay_valid), .replay_ready_i(replay_ready), .replay_body_o(replay_body), .replay_last_o(), .retry_exhausted_o(retry_exhausted_o), .occupancy_o(replay_occupancy)); // 流式模式保留三十二 packet replay window 且不阻塞 data TX
    assign replay_empty_o = ~|replay_occupancy; // 仅全部累计 ACK 回收后声明当前可靠发送已 drain
    assign replay_ready = tx_fifo3_push_ready && ({1'b0, tx_fifo3_count} + {1'b0, replay_crc_inflight_q} < 8'd48); // 为最长 replay packet预留 VC3 FIFO 空间
    assign replay_crc_fire = replay_valid && replay_ready; // 形成 replay CRC 输入握手
    coll_crc32_flit_pipeline u_replay_crc (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .valid_i(replay_crc_fire), .header_i(replay_body[607:512]), .payload_i(replay_body[511:0]), .payload_bytes_i(replay_body[592:586]), .valid_o(replay_crc_valid), .crc_o(replay_crc), .header_o(replay_header), .payload_o(replay_payload), .payload_bytes_o()); // 对修改 retry VC 字段后的 replay body 重算 CRC32
    assign replay_fifo_push = replay_crc_valid && tx_fifo3_push_ready; // 将 CRC 完成 replay flit写入 VC3 FIFO
    always @(posedge coll_clk_i or negedge coll_rst_n_i) begin // 统计 replay CRC 流水在途 flit
        if (!coll_rst_n_i) replay_crc_inflight_q <= 7'd0; // 清零 replay CRC 在途数
        else begin // 合并 replay CRC 输入和输出
            case ({replay_crc_fire, replay_fifo_push}) // 按同拍输入输出组合更新
                2'b10: replay_crc_inflight_q <= replay_crc_inflight_q + 1'b1; // 仅输入时增加在途数
                2'b01: replay_crc_inflight_q <= replay_crc_inflight_q - 1'b1; // 仅输出时减少在途数
                default: replay_crc_inflight_q <= replay_crc_inflight_q; // 同拍或空闲保持
            endcase // 结束在途数更新
        end // 结束正常统计
    end // 结束 replay 在途统计
    assign coll_phy_rx_vc = coll_phy_rx_flit[527:526]; // 从 RX header 提取 VC
    assign coll_phy_rx_ready = rx_fifo_push_ready[coll_phy_rx_vc]; // 仅目标 VC FIFO 有空间时消费 PHY CDC
    assign rx_fifo_push[0] = coll_phy_rx_valid && coll_phy_rx_ready && coll_phy_rx_vc == 2'd0; assign rx_fifo_push[1] = coll_phy_rx_valid && coll_phy_rx_ready && coll_phy_rx_vc == 2'd1; // 路由普通 data RX flit
    assign rx_fifo_push[2] = coll_phy_rx_valid && coll_phy_rx_ready && coll_phy_rx_vc == 2'd2; assign rx_fifo_push[3] = coll_phy_rx_valid && coll_phy_rx_ready && coll_phy_rx_vc == 2'd3; // 路由 control replay RX flit
    coll_sync_fifo #(.WIDTH(640), .DEPTH(STREAM_MODE ? 512 : 64), .ADDR_W(STREAM_MODE ? 9 : 6), .COUNT_W(STREAM_MODE ? 10 : 7)) u_rx_fifo0 (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .push_data_i(coll_phy_rx_flit), .push_valid_i(rx_fifo_push[0]), .push_ready_o(rx_fifo_push_ready[0]), .pop_data_o(rx_fifo0_data), .pop_valid_o(rx_fifo_valid[0]), .pop_ready_i(rx_fifo_pop[0]), .occupancy_o(), .overflow_o(rx_fifo_unused_overflow[0]), .underflow_o(rx_fifo_unused_underflow[0])); // 实例化流式 VC0 大窗口 RX FIFO
    coll_sync_fifo #(.WIDTH(640), .DEPTH(STREAM_MODE ? 512 : 64), .ADDR_W(STREAM_MODE ? 9 : 6), .COUNT_W(STREAM_MODE ? 10 : 7)) u_rx_fifo1 (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .push_data_i(coll_phy_rx_flit), .push_valid_i(rx_fifo_push[1]), .push_ready_o(rx_fifo_push_ready[1]), .pop_data_o(rx_fifo1_data), .pop_valid_o(rx_fifo_valid[1]), .pop_ready_i(rx_fifo_pop[1]), .occupancy_o(), .overflow_o(rx_fifo_unused_overflow[1]), .underflow_o(rx_fifo_unused_underflow[1])); // 实例化流式 VC1 大窗口 RX FIFO
    coll_sync_fifo #(.WIDTH(640), .DEPTH(64), .ADDR_W(6), .COUNT_W(7)) u_rx_fifo2 (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .push_data_i(coll_phy_rx_flit), .push_valid_i(rx_fifo_push[2]), .push_ready_o(rx_fifo_push_ready[2]), .pop_data_o(rx_fifo2_data), .pop_valid_o(rx_fifo_valid[2]), .pop_ready_i(rx_fifo_pop[2]), .occupancy_o(), .overflow_o(rx_fifo_unused_overflow[2]), .underflow_o(rx_fifo_unused_underflow[2])); // 实例化 VC2 RX FIFO
    coll_sync_fifo #(.WIDTH(640), .DEPTH(64), .ADDR_W(6), .COUNT_W(7)) u_rx_fifo3 (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .push_data_i(coll_phy_rx_flit), .push_valid_i(rx_fifo_push[3]), .push_ready_o(rx_fifo_push_ready[3]), .pop_data_o(rx_fifo3_data), .pop_valid_o(rx_fifo_valid[3]), .pop_ready_i(rx_fifo_pop[3]), .occupancy_o(), .overflow_o(rx_fifo_unused_overflow[3]), .underflow_o(rx_fifo_unused_underflow[3])); // 实例化 VC3 RX FIFO
    assign rx_dispatch_enable = commit_flit_ready; // 数据面只由本地 context 接收能力决定，不等待 ACK 或 reverse FIFO
    coll_vc_arbiter u_rx_arbiter (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .valid_i(rx_fifo_valid), .admit_i(4'b1111), .flit0_i(rx_fifo0_data), .flit1_i(rx_fifo1_data), .flit2_i(rx_fifo2_data), .flit3_i(rx_fifo3_data), .ready_o(rx_fifo_pop), .valid_o(rx_arb_valid), .ready_i(rx_dispatch_enable), .flit_o(rx_arb_flit), .vc_o(rx_arb_vc)); // 按 packet boundary 仲裁四 VC RX FIFO
    assign rx_dispatch_fire = rx_arb_valid && rx_dispatch_enable; // 形成 RX flit dispatch 握手
    always @(posedge coll_clk_i or negedge coll_rst_n_i) begin // 更新兼容 debug 状态但不阻塞流式 RX
        if (!coll_rst_n_i) rx_wait_response_q <= 1'b0; // 清除 packet 等待状态
        else rx_wait_response_q <= 1'b0; // 流式模式不以 ACK 反馈阻塞数据面
    end // 结束兼容 debug 状态更新
    coll_depacketizer u_depacketizer (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .valid_i(rx_dispatch_fire && rx_arb_flit[519:516] == `COLL_MESSAGE_TYPE_DATA), .flit_i(rx_arb_flit), .valid_o(depacket_valid), .crc_good_o(depacket_crc_good), .header_o(depacket_header), .payload_o(depacket_payload), .payload_bytes_o(depacket_bytes)); // 按 header message type 检查每个 DATA flit CRC32
    coll_header_checker u_header_checker (.header_i(depacket_header), .local_rank_i(local_rank_i), .link_epoch_i(link_epoch_i), .valid_o(header_valid), .status_o()); // 检查 DATA header version VC destination epoch 合法性
    coll_depacketizer u_ctrl_depacketizer (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .valid_i(rx_dispatch_fire && rx_arb_flit[519:516] != `COLL_MESSAGE_TYPE_DATA), .flit_i(rx_arb_flit), .valid_o(ctrl_depacket_valid), .crc_good_o(ctrl_depacket_crc_good), .header_o(ctrl_depacket_header), .payload_o(ctrl_depacket_payload), .payload_bytes_o(ctrl_depacket_bytes)); // 按 header message type 独立检查 VC2 global control CRC32
    coll_header_checker u_ctrl_header_checker (.header_i(ctrl_depacket_header), .local_rank_i(local_rank_i), .link_epoch_i(link_epoch_i), .valid_o(ctrl_header_valid), .status_o(ctrl_header_status)); // 检查 global control header 和单 flit形态
    assign rx_ctrl_valid_o = ctrl_pending_q; // 输出寄存控制 token 有效
    assign rx_ctrl_message_type_o = ctrl_message_q; // 输出寄存控制消息类型
    assign rx_ctrl_origin_rank_o = ctrl_origin_q; // 输出寄存 token origin rank
    assign rx_ctrl_collective_id_o = ctrl_collective_q; // 输出寄存 collective ID
    assign rx_ctrl_signature_o = ctrl_signature_q; // 输出寄存 descriptor signature
    assign rx_ctrl_ready_mask_o = ctrl_ready_mask_q; // 输出寄存 ready mask
    assign rx_ctrl_visited_mask_o = ctrl_visited_mask_q; // 输出寄存 visited mask
    assign rx_ctrl_generation_o = ctrl_generation_q; // 输出寄存 generation
    assign rx_ctrl_status_o = ctrl_status_q; // 输出寄存 status
    assign rx_ctrl_offending_rank_o = ctrl_offending_q; // 输出寄存 offending rank
    assign rx_ctrl_length_bytes_o = ctrl_length_q; // 输出寄存 Tensor 长度
    assign rx_ctrl_opcode_o = ctrl_opcode_q; // 输出寄存 opcode
    assign rx_ctrl_dtype_o = ctrl_dtype_q; // 输出寄存 dtype
    always @(posedge coll_clk_i or negedge coll_rst_n_i) begin // 捕获已通过 CRC 的单 flit控制 token
        if (!coll_rst_n_i) begin // 检测复位有效
            ctrl_pending_q <= 1'b0; // 清除控制 token 有效
            ctrl_message_q <= 4'd0; ctrl_origin_q <= 2'd0; ctrl_collective_q <= 12'd0; // 清零控制 identity
            ctrl_signature_q <= 32'd0; ctrl_ready_mask_q <= 4'd0; ctrl_visited_mask_q <= 4'd0; // 清零 setup 字段
            ctrl_generation_q <= 8'd0; ctrl_status_q <= 8'd0; ctrl_offending_q <= 2'd0; // 清零诊断字段
            ctrl_length_q <= 32'd0; ctrl_opcode_q <= 3'd0; ctrl_dtype_q <= 2'd0; // 清零 descriptor 字段
        end else begin // 处理控制 token 接收和消费
            if (ctrl_pending_q && rx_ctrl_ready_i) ctrl_pending_q <= 1'b0; // 下游接受后释放寄存 entry
            if (ctrl_depacket_valid && ctrl_depacket_crc_good && ctrl_header_valid && ctrl_depacket_bytes == 7'd16) begin // 检查完整合法 global control token
                ctrl_pending_q <= 1'b1; // 声明控制 token 待消费
                ctrl_message_q <= ctrl_depacket_header[7:4]; ctrl_origin_q <= ctrl_depacket_header[17:16]; ctrl_collective_q <= ctrl_depacket_header[33:22]; // 锁存 header identity
                ctrl_signature_q <= ctrl_depacket_payload[31:0]; ctrl_ready_mask_q <= ctrl_depacket_payload[35:32]; ctrl_visited_mask_q <= ctrl_depacket_payload[39:36]; // 锁存 setup masks
                ctrl_generation_q <= ctrl_depacket_payload[47:40]; ctrl_status_q <= ctrl_depacket_payload[55:48]; ctrl_offending_q <= ctrl_depacket_payload[57:56]; // 锁存诊断字段
                ctrl_length_q <= ctrl_depacket_payload[95:64]; ctrl_opcode_q <= ctrl_depacket_payload[98:96]; ctrl_dtype_q <= ctrl_depacket_payload[100:99]; // 锁存 descriptor 字段
            end // 结束合法控制 token 捕获
        end // 结束控制 token 正常更新
    end // 结束控制 token 接收寄存
    coll_packet_rx_stream_commit u_rx_commit (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .flit_valid_i(depacket_valid), .crc_good_i(depacket_crc_good && header_valid), .header_i(depacket_header), .payload_i(depacket_payload), .payload_bytes_i(depacket_bytes), .flit_ready_o(commit_flit_ready), .commit_valid_o(rx_commit_valid_o), .commit_ready_i(rx_commit_ready_i), .commit_payload_o(rx_commit_payload_o), .commit_payload_bytes_o(rx_commit_bytes_o), .commit_last_o(rx_commit_last_o), .commit_collective_id_o(rx_commit_collective_id_o), .commit_phase_o(rx_commit_phase_o), .commit_dtype_o(rx_commit_dtype_o), .commit_chunk_id_o(rx_commit_chunk_id_o), .commit_packet_seq_o(rx_commit_packet_seq_o), .ack_valid_o(commit_ack), .nack_valid_o(commit_nack), .response_collective_id_o(response_collective), .response_phase_o(response_phase), .response_packet_seq_o(response_sequence), .response_status_o(response_status), .duplicate_o(duplicate_drop_o)); // 并行 packet context 流式提交并保留 exact-once response
    assign reverse_event_valid = commit_ack || commit_nack || rx_dispatch_fire; // 合并 ACK NACK 和每 flit credit return
    assign reverse_event_type = commit_nack ? `COLL_REVERSE_TYPE_NACK : commit_ack ? `COLL_REVERSE_TYPE_ACK : `COLL_REVERSE_TYPE_CREDIT; // ACK NACK 优先于普通 credit
    assign reverse_event_vc = (commit_ack || commit_nack) ? (response_phase ? 2'd1 : 2'd0) : rx_arb_vc; // 选择 response 或当前释放槽位 VC
    assign reverse_event_collective = (commit_ack || commit_nack) ? response_collective : 12'd0; // 普通 credit 不携带 collective identity
    assign reverse_event_phase = (commit_ack || commit_nack) ? response_phase : 1'b0; // 选择 response phase
    assign reverse_event_sequence = (commit_ack || commit_nack) ? response_sequence : 16'd0; // 选择 response packet sequence
    assign reverse_event_status = commit_nack ? response_status : 8'd0; // NACK 携带精确错误状态
    assign reverse_event_credit_total = (commit_ack || commit_nack) ? rx_credit_total_q[reverse_event_vc] : (rx_credit_total_q[rx_arb_vc] + 1'b1); // credit word携带本次释放后的累计 total
    coll_reverse_codec u_reverse_codec (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .tx_valid_i(reverse_event_valid), .message_type_i(reverse_event_type), .vc_i(reverse_event_vc), .link_epoch_i(link_epoch_i), .collective_id_i(reverse_event_collective), .phase_i(reverse_event_phase), .packet_seq_i(reverse_event_sequence), .credit_delta_i(rx_dispatch_fire ? 7'd1 : 7'd0), .status_i(reverse_event_status), .credit_total_i(reverse_event_credit_total), .tx_valid_o(reverse_codec_tx_valid), .tx_word_o(reverse_codec_tx_word), .rx_valid_i(coll_reverse_rx_valid), .rx_word_i(coll_reverse_rx_word), .rx_valid_o(reverse_rx_valid), .rx_crc_good_o(reverse_rx_crc_good), .rx_body_o(reverse_rx_body)); // 编码本地 reverse 事件并检查远端 reverse word
    always @(posedge coll_clk_i or negedge coll_rst_n_i) begin // 更新 RX 累计 credit 和 reverse codec 在途数
        if (!coll_rst_n_i) begin // 检测复位有效
            reverse_codec_inflight_q <= 7'd0; // 清零 reverse codec 在途数
            for (vc_index = 0; vc_index < 4; vc_index = vc_index + 1) rx_credit_total_q[vc_index] <= 16'd64; // 以建链初始六十四 credit 为累计基线
        end else begin // 处理正常 reverse 事件
            if (rx_dispatch_fire) rx_credit_total_q[rx_arb_vc] <= rx_credit_total_q[rx_arb_vc] + 1'b1; // 仅 RX FIFO dequeue 后累计返回 credit
            case ({reverse_event_valid, reverse_codec_tx_valid}) // 合并 codec 输入和完成输出
                2'b10: reverse_codec_inflight_q <= reverse_codec_inflight_q + 1'b1; // 仅输入时增加在途数
                2'b01: reverse_codec_inflight_q <= reverse_codec_inflight_q - 1'b1; // 仅输出时减少在途数
                default: reverse_codec_inflight_q <= reverse_codec_inflight_q; // 同拍或空闲保持
            endcase // 结束 reverse 在途统计
        end // 结束正常更新
    end // 结束累计 credit 更新
    coll_sync_fifo #(.WIDTH(96), .DEPTH(64), .ADDR_W(6), .COUNT_W(7)) u_reverse_fifo (.clk_i(coll_clk_i), .rst_n_i(coll_rst_n_i), .push_data_i(reverse_codec_tx_word), .push_valid_i(reverse_codec_tx_valid), .push_ready_o(reverse_fifo_push_ready), .pop_data_o(reverse_fifo_word), .pop_valid_o(reverse_fifo_valid), .pop_ready_i(phy_reverse_coll_ready), .occupancy_o(), .overflow_o(), .underflow_o()); // 缓冲 CRC16 pipeline 与 PHY CDC 间 reverse word
    assign reverse_epoch_good = reverse_rx_body[17:10] == link_epoch_i; // 仅接受当前 link epoch reverse word
    assign reverse_credit_valid = reverse_rx_valid && reverse_rx_crc_good && reverse_epoch_good && reverse_rx_body[7:4] == `COLL_REVERSE_TYPE_CREDIT; // 分类合法累计 credit return
    assign reverse_ack_valid = reverse_rx_valid && reverse_rx_crc_good && reverse_epoch_good && reverse_rx_body[7:4] == `COLL_REVERSE_TYPE_ACK; // 分类合法累计 ACK
    assign reverse_nack_valid = reverse_rx_valid && reverse_rx_crc_good && reverse_epoch_good && reverse_rx_body[7:4] == `COLL_REVERSE_TYPE_NACK; // 分类合法精确 NACK
    coll_phy_adapter u_phy_adapter (.coll_clk_i(coll_clk_i), .coll_rst_n_i(coll_rst_n_i), .phy_clk_i(phy_clk_i), .phy_rst_n_i(phy_rst_n_i), .coll_tx_flit_i(tx_arb_flit), .coll_tx_valid_i(tx_arb_valid), .coll_tx_ready_o(coll_phy_tx_ready), .phy_tx_flit_o(phy_fwd_tx_flit_o), .phy_tx_valid_o(phy_fwd_tx_valid_o), .phy_tx_ready_i(phy_fwd_tx_ready_i), .phy_rx_flit_i(phy_fwd_rx_flit_i), .phy_rx_valid_i(phy_fwd_rx_valid_i), .phy_rx_ready_o(phy_fwd_rx_ready_o), .coll_rx_flit_o(coll_phy_rx_flit), .coll_rx_valid_o(coll_phy_rx_valid), .coll_rx_ready_i(coll_phy_rx_ready), .coll_reverse_tx_i(reverse_fifo_word), .coll_reverse_tx_valid_i(reverse_fifo_valid), .coll_reverse_tx_ready_o(phy_reverse_coll_ready), .phy_reverse_tx_o(phy_rev_tx_word_o), .phy_reverse_tx_valid_o(phy_rev_tx_valid_o), .phy_reverse_tx_ready_i(phy_rev_tx_ready_i), .phy_reverse_rx_i(phy_rev_rx_word_i), .phy_reverse_rx_valid_i(phy_rev_rx_valid_i), .phy_reverse_rx_ready_o(phy_rev_rx_ready_o), .coll_reverse_rx_o(coll_reverse_rx_word), .coll_reverse_rx_valid_o(coll_reverse_rx_valid), .coll_reverse_rx_ready_i(1'b1), .cdc_error_o(cdc_error_o)); // 跨接 coll 和异步 PHY forward reverse 通道
    assign credit_error_o = credit_underflow || credit_overflow || credit_stale; // 汇总 TX credit 协议错误
    assign protocol_error_o = (depacket_valid && (!depacket_crc_good || !header_valid)) || (ctrl_depacket_valid && (!ctrl_depacket_crc_good || !ctrl_header_valid || ctrl_depacket_bytes != 7'd16 || ctrl_header_status != 8'd0)) || (reverse_rx_valid && (!reverse_rx_crc_good || !reverse_epoch_good)) || (reverse_codec_tx_valid && !reverse_fifo_push_ready) || (replay_crc_valid && !tx_fifo3_push_ready) || (depacket_valid && !commit_flit_ready); // 汇总不可恢复协议和内部容量错误
endmodule // 结束单 hop reliable link endpoint
