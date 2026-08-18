module kdlink_v2_collective32_int32 #( // 定义三十二节点十六 bank 流式 Ring collective 系统
    parameter integer FLITS_PER_CHUNK = 128 // 配置每 bank 每 chunk 的连续 flit 数
) ( // 开始端口声明
    input wire clk_i, // 接收一 GHz collective/fabric 时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire load_valid_i, // 接收并行 Tensor memory 加载有效位
    output wire load_ready_o, // 返回 Tensor memory 加载许可
    input wire [4:0] load_chunk_i, // 接收并行加载 chunk 索引
    input wire [6:0] load_flit_i, // 接收并行加载 bank 内 flit 索引
    input wire [262143:0] load_data_i, // 接收三十二节点乘十六 bank 的 512-bit 加载数据
    input wire start_i, // 接收 collective 启动脉冲
    output wire start_ready_o, // 返回 collective 启动许可
    input wire [2:0] opcode_i, // 接收 RS AG 或 AR opcode
    input wire [11:0] collective_id_i, // 接收 collective identity
    input wire [7:0] link_epoch_i, // 接收当前 link epoch
    input wire direct_cfg_valid_i, // 接收 AllToAllv source-destination flit count 配置
    output wire direct_cfg_ready_o, // 返回 AllToAllv 配置许可
    input wire [4:0] direct_cfg_src_i, // 接收 AllToAllv source node
    input wire [4:0] direct_cfg_dst_i, // 接收 AllToAllv destination node
    input wire [7:0] direct_cfg_flits_i, // 接收每 bank 对应 source-destination flit 数
    input wire [4:0] p2p_src_node_i, // 接收 PointToPoint source node
    input wire [4:0] p2p_dst_node_i, // 接收 PointToPoint destination node
    input wire [7:0] p2p_flits_i, // 接收 PointToPoint 每 bank flit 数
    output wire busy_o, // 指示 collective operation active
    output reg done_o, // 输出 collective 完成脉冲
    output reg operation_error_o, // 指示非法 opcode 或 fabric 不变量错误
    output reg lane_alignment_error_o, // 指示五百一十二路 RX valid 未对齐
    output reg [31:0] operation_cycles_o, // 输出 descriptor-to-completion 周期数
    input wire [4:0] result_chunk_i, // 接收并行结果读取 chunk 索引
    input wire [6:0] result_flit_i, // 接收并行结果读取 flit 索引
    output wire [262143:0] result_data_o, // 输出三十二节点乘十六 bank 的 512-bit 结果数据
    output wire [15:0] fabric_protocol_error_o // 输出八 plane 双 slice fabric 协议错误
); // 结束端口声明
    localparam integer ENDPOINT_LANES = 512; // 固定三十二节点乘十六 bank lane 数
    localparam integer MEMORY_WORDS = 32*16*32*FLITS_PER_CHUNK; // 计算全部节点 Tensor memory word 数
    localparam [31:0] ALLTOALL_ENDPOINT_FLITS = 16384*FLITS_PER_CHUNK; // 计算等长 AllToAll endpoint flit 总数
    localparam [2:0] STATE_IDLE = 3'd0; // 定义空闲状态
    localparam [2:0] STATE_RS_SEND = 3'd1; // 定义 ReduceScatter 连续发射状态
    localparam [2:0] STATE_AG_SEND = 3'd2; // 定义 AllGather 连续发射状态
    localparam [2:0] STATE_WAIT_RX = 3'd3; // 定义等待 fabric 尾部排空状态
    localparam [2:0] STATE_DRAIN = 3'd4; // 定义 reduction 写回排空状态
    localparam [2:0] STATE_DIRECT_SEND = 3'd5; // 定义 destination-indexed direct exchange 状态
    /* verilator lint_off WIDTHEXPAND */ // 固定参数和 integer 地址计算均限制在已声明 memory 范围
    reg [2:0] state_q; // 保存 collective 控制状态
    reg [2:0] opcode_q; // 保存 active operation opcode
    reg [11:0] collective_id_q; // 保存 active collective identity
    reg [7:0] link_epoch_q; // 保存 active link epoch
    reg [4:0] step_q; // 保存当前 Ring step 零至三十
    reg [6:0] flit_index_q; // 保存当前 bank 内 flit 索引
    reg [31:0] expected_receive_cycles_q; // 保存本 operation 期望接收周期数
    reg [31:0] receive_cycles_q; // 保存已完成的全 lane 接收周期数
    reg [2:0] drain_count_q; // 保存尾部 reduction 排空周期数
    reg [511:0] tensor_mem_q [0:MEMORY_WORDS-1]; // 保存 512 个独立 bank 的 Tensor chunk memory
    reg [511:0] direct_result_mem_q [0:MEMORY_WORDS-1]; // 保存 direct collective 独立 destination Tensor memory
    reg [7:0] direct_count_q [0:1023]; // 保存 AllToAllv 三十二乘三十二 source-destination flit count
    reg [7:0] direct_step_max_q [0:31]; // 保存每个 permutation step 的最大 AllToAllv count
    reg [31:0] configured_endpoint_flits_q; // 保存 AllToAllv 配置的 endpoint flit 总数
    reg [4:0] p2p_src_q; // 保存 active PointToPoint source node
    reg [4:0] p2p_dst_q; // 保存 active PointToPoint destination node
    reg [7:0] p2p_flits_q; // 保存 active PointToPoint 每 bank flit 数
    reg [31:0] expected_receive_flits_q; // 保存 direct operation 期望 endpoint flit 总数
    reg [31:0] received_flits_q; // 保存 direct operation 已接收 endpoint flit 总数
    reg result_direct_q; // 选择最近 operation 的 direct result memory
    reg [327679:0] fabric_tx_flit_d; // 保存五百一十二路组合 TX logical flit
    reg [511:0] fabric_tx_valid_d; // 保存五百一十二路 TX valid
    wire [511:0] fabric_tx_valid; // 保存五百一十二路 TX valid
    wire [511:0] fabric_tx_ready; // 保存五百一十二路 TX ready
    wire [511:0] fabric_rx_valid; // 保存五百一十二路 RX valid
    wire [327679:0] fabric_rx_flit; // 保存五百一十二路 RX logical flit
    wire [511:0] fabric_rx_ready; // 保存五百一十二路 RX ready
    wire send_active; // 标记当前处于任一 phase 连续发射状态
    wire send_fire; // 标记五百一十二路同拍 TX 被 fabric 接受
    wire receive_cycle_fire; // 标记五百一十二路同拍 RX 完整到达
    reg [9:0] receive_lane_count_d; // 保存当前周期 direct RX endpoint flit 数
    reg [31:0] direct_expected_flits_d; // 保存待启动 direct operation endpoint flit 总数
    wire [7:0] direct_step_limit_d; // 保存当前 direct permutation step 最大 flit count
    wire [31:0] direct_source_valid; // 保存当前 direct step 三十二 source valid
    wire [255:0] direct_source_pair_counts; // 保存当前 step 每 source 的 AllToAllv pair count
    wire [255:0] direct_source_counts; // 保存 opcode 选择后的当前 source count
    wire [511:0] reduce_valid; // 保存每 endpoint bank 的 RS reduction 结果有效位
    wire [49151:0] reduce_header; // 保存每 endpoint bank 的对齐 reduction header
    wire [262143:0] reduce_result; // 保存每 endpoint bank 的 INT32 reduction 结果
    wire [511:0] reduce_request_valid; // 保存每 endpoint bank 的 RS reduction 请求有效位
    wire [49151:0] reduce_request_header; // 保存每 endpoint bank 的 RS 输入 header
    wire [262143:0] reduce_local; // 保存每 endpoint bank 的本地 reduction operand
    wire [262143:0] reduce_remote; // 保存每 endpoint bank 的远端 reduction operand
    integer endpoint_index; // 提供五百一十二 endpoint bank 循环索引
    integer node_index; // 保存当前 endpoint node 索引
    integer bank_index; // 保存当前 endpoint bank 索引
    integer send_chunk_index; // 保存当前 Ring step 发送 chunk 索引
    integer tx_memory_index; // 保存当前 TX Tensor memory 地址
    integer direct_destination; // 保存 direct operation 当前 destination
    integer direct_node_count; // 保存 direct operation 当前 source-destination flit 数
    integer direct_count_index; // 提供 direct count 配置和求和索引
    integer direct_reset_index; // 提供 direct count reset 索引
    integer direct_step_reset_index; // 提供 direct step max reset 索引
    assign busy_o = state_q != STATE_IDLE; // 非空闲状态表示 operation active
    assign load_ready_o = (state_q == STATE_IDLE) && !start_i; // 仅 idle 且未启动时允许 Tensor memory 加载
    assign start_ready_o = (state_q == STATE_IDLE) && !load_valid_i; // 仅 idle 且未加载时允许 collective 启动
    assign direct_cfg_ready_o = (state_q == STATE_IDLE) && !start_i && !load_valid_i; // 仅空闲窗口允许更新 AllToAllv count 表
    assign send_active = (state_q == STATE_RS_SEND) || (state_q == STATE_AG_SEND) || (state_q == STATE_DIRECT_SEND); // 汇总全部连续发射状态
    assign fabric_tx_valid = fabric_tx_valid_d; // 输出逐 endpoint valid
    assign send_fire = send_active && (&(fabric_tx_ready | ~fabric_tx_valid_d)); // 仅全部 active ingress 可接收时推进全局序列
    assign fabric_rx_ready = {ENDPOINT_LANES{1'b1}}; // endpoint Tensor memory 持续接收 fabric 输出
    assign receive_cycle_fire = &fabric_rx_valid; // 全部 endpoint bank 同拍有效构成一个完整 payload 周期
    always @(*) begin // 构造当前 step 五百一十二路 Ring 或 direct logical flit
        fabric_tx_valid_d = 512'd0; // 默认全部 endpoint 不发送
        node_index = 0; // 默认 node 索引为零
        bank_index = 0; // 默认 bank 索引为零
        send_chunk_index = 0; // 默认发送 chunk 为零
        tx_memory_index = 0; // 默认 TX memory 地址为零
        direct_destination = 0; // 默认 direct destination 为零
        direct_node_count = 0; // 默认 direct count 为零
        for (endpoint_index = 0; endpoint_index < ENDPOINT_LANES; endpoint_index = endpoint_index + 1) begin // 构造全部 endpoint bank flit
            fabric_tx_flit_d[endpoint_index*640 +: 640] = 640'd0; // 默认当前 TX flit 全部字段为零
            node_index = endpoint_index / 16; // 反解当前 endpoint node
            bank_index = endpoint_index & 15; // 反解当前 endpoint bank
            direct_destination = (node_index + step_q) & 31; // direct permutation 每 step 覆盖一个 destination
            if (state_q == STATE_RS_SEND) send_chunk_index = (node_index - step_q - 1) & 31; // 计算 ReduceScatter 当前发送 chunk
            else if (state_q == STATE_AG_SEND) send_chunk_index = (node_index - step_q) & 31; // 计算 AllGather 当前发送 chunk
            else send_chunk_index = direct_destination; // direct source memory 以 destination 为 chunk 索引
            if ((state_q == STATE_RS_SEND) || (state_q == STATE_AG_SEND)) fabric_tx_valid_d[endpoint_index] = 1'b1; // Ring phase 全 endpoint 同拍有效
            else if (state_q == STATE_DIRECT_SEND) begin // 为 direct collective 形成逐 source 有效掩码
                direct_node_count = direct_source_counts[node_index*8 +: 8]; // 读取分层 scheduler 已选择的 source count
                fabric_tx_valid_d[endpoint_index] = direct_source_valid[node_index]; // 将每 source valid 复制到十六个 bank
            end // 结束 direct valid 形成
            tx_memory_index = (((node_index*16 + bank_index)*32 + send_chunk_index)*FLITS_PER_CHUNK) + flit_index_q; // 计算当前 Tensor memory 读地址
            fabric_tx_flit_d[endpoint_index*640 +: 512] = tensor_mem_q[tx_memory_index]; // 写入当前 Tensor payload
            fabric_tx_flit_d[endpoint_index*640 + 512 + 0 +: 4] = 4'd2; // 写入协议版本
            fabric_tx_flit_d[endpoint_index*640 + 512 + 4 +: 4] = 4'd0; // 写入 DATA message type
            fabric_tx_flit_d[endpoint_index*640 + 512 + 8 +: 3] = opcode_q; // 写入 operation opcode
            fabric_tx_flit_d[endpoint_index*640 + 512 + 11 +: 2] = 2'd0; // 写入 INT32 dtype
            fabric_tx_flit_d[endpoint_index*640 + 512 + 13 +: 3] = (opcode_q == 3'd5) ? 3'd4 : ((opcode_q >= 3'd3) ? 3'd3 : 3'd2); // 选择 collective、AllToAllv 或 PointToPoint VC
            fabric_tx_flit_d[endpoint_index*640 + 512 + 16] = (state_q == STATE_AG_SEND) || (state_q == STATE_DIRECT_SEND); // direct 和 AG 均为无 reduction 写回 phase
            fabric_tx_flit_d[endpoint_index*640 + 512 + 17] = flit_index_q[3:0] == 4'd0; // 每十六 flit packet 首拍写入 SOP
            fabric_tx_flit_d[endpoint_index*640 + 512 + 18] = (flit_index_q[3:0] == 4'd15) || ((state_q == STATE_DIRECT_SEND) && (direct_node_count != 0) && ({1'b0, flit_index_q} + 8'd1 >= direct_node_count)); // 每十六 flit 或 variable direct chunk 尾拍写入 EOP
            fabric_tx_flit_d[endpoint_index*640 + 512 + 20 +: 5] = node_index[4:0]; // 写入 source node
            fabric_tx_flit_d[endpoint_index*640 + 512 + 25 +: 5] = (state_q == STATE_DIRECT_SEND) ? direct_destination[4:0] : ((node_index == 31) ? 5'd0 : node_index[4:0] + 5'd1); // 写入 Ring next hop 或 direct destination
            fabric_tx_flit_d[endpoint_index*640 + 512 + 30 +: 3] = bank_index[3:1]; // 写入静态 plane identity
            fabric_tx_flit_d[endpoint_index*640 + 512 + 33 +: 5] = 5'd31; // 写入单级 fabric hop limit
            fabric_tx_flit_d[endpoint_index*640 + 512 + 38 +: 8] = link_epoch_q; // 写入 link epoch
            fabric_tx_flit_d[endpoint_index*640 + 512 + 46 +: 12] = collective_id_q; // 写入 collective identity
            fabric_tx_flit_d[endpoint_index*640 + 512 + 58 +: 12] = (state_q == STATE_DIRECT_SEND) ? node_index[11:0] : send_chunk_index[11:0]; // direct 结果以 source identity 为 chunk
            fabric_tx_flit_d[endpoint_index*640 + 512 + 70 +: 12] = {9'd0, flit_index_q[6:4]}; // 写入 chunk 内 packet sequence
            fabric_tx_flit_d[endpoint_index*640 + 512 + 82 +: 6] = {2'd0, flit_index_q[3:0]}; // 写入 packet 内 flit sequence
            fabric_tx_flit_d[endpoint_index*640 + 512 + 88 +: 7] = 7'd64; // 写入完整 payload 字节数
        end // 结束全部 endpoint bank flit 构造
    end // 结束 TX flit 组合逻辑
    always @(*) begin // 统计 direct operation 总 flit 与本周期接收 lane 数
        receive_lane_count_d = 10'd0; // 默认本周期无 RX endpoint flit
        for (direct_count_index = 0; direct_count_index < ENDPOINT_LANES; direct_count_index = direct_count_index + 1) receive_lane_count_d = receive_lane_count_d + fabric_rx_valid[direct_count_index]; // 汇总五百一十二 endpoint valid
        direct_expected_flits_d = 32'd0; // 默认无 direct payload
        if (opcode_i == 3'd3) direct_expected_flits_d = ALLTOALL_ENDPOINT_FLITS; // AllToAll 覆盖全部 source-destination pair
        else if (opcode_i == 3'd4) direct_expected_flits_d = configured_endpoint_flits_q; // AllToAllv 使用配置时增量维护的总数
        else if (opcode_i == 3'd5) direct_expected_flits_d = p2p_flits_i*16; // PointToPoint 发送一个 node 的十六 bank
    end // 结束 direct 计数组合逻辑
    genvar direct_source_index;
    generate
        for (direct_source_index = 0; direct_source_index < 32; direct_source_index = direct_source_index + 1) begin : g_direct_count_read
            wire [4:0] current_destination;
            assign current_destination = direct_source_index + step_q;
            assign direct_source_pair_counts[direct_source_index*8 +: 8] = direct_count_q[direct_source_index*32 + current_destination];
        end
    endgenerate
    kdlink_v2_direct_scheduler32 #(.FLITS_PER_CHUNK(FLITS_PER_CHUNK)) u_direct_scheduler (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .opcode_i(opcode_q), .step_i(step_q), .flit_index_i(flit_index_q),
        .source_pair_counts_i(direct_source_pair_counts), .alltoallv_step_limit_i(direct_step_max_q[step_q]),
        .p2p_src_node_i(p2p_src_q), .p2p_dst_node_i(p2p_dst_q), .p2p_flits_i(p2p_flits_q),
        .source_valid_o(direct_source_valid), .source_count_o(direct_source_counts), .step_limit_o(direct_step_limit_d)
    );
    kdlink_v2_fabric32 u_fabric ( // 实例化八 plane 三十二节点逻辑 fabric
        .clk_i(clk_i), .rst_n_i(rst_n_i), // 连接 collective/fabric 同域时钟复位
        .endpoint_tx_valid_i(fabric_tx_valid), .endpoint_tx_ready_o(fabric_tx_ready), .endpoint_tx_flit_i(fabric_tx_flit_d), // 连接五百一十二路 endpoint TX
        .endpoint_rx_valid_o(fabric_rx_valid), .endpoint_rx_ready_i(fabric_rx_ready), .endpoint_rx_flit_o(fabric_rx_flit), // 连接五百一十二路 endpoint RX
        .protocol_error_o(fabric_protocol_error_o) // 连接 fabric 协议状态
    ); // 结束八 plane fabric 实例
    genvar reduce_endpoint; // 提供五百一十二 endpoint bank reduction 生成索引
    generate // 为每个 endpoint bank 建立规则化 reduction operand 读取边界
        for (reduce_endpoint = 0; reduce_endpoint < ENDPOINT_LANES; reduce_endpoint = reduce_endpoint + 1) begin : g_reduce // 生成当前 endpoint bank reduction
            localparam integer REDUCE_NODE = reduce_endpoint / 16; // 固定当前 reduction node identity
            localparam integer REDUCE_BANK = reduce_endpoint % 16; // 固定当前 reduction bank identity
            wire [4:0] rx_chunk; // 提取当前 RX chunk identity
            wire [6:0] rx_tensor_flit; // 重建当前 RX chunk 内 flit 索引
            assign rx_chunk = fabric_rx_flit[reduce_endpoint*640 + 512 + 58 +: 5]; // 提取 header chunk 低五位
            assign rx_tensor_flit = {fabric_rx_flit[reduce_endpoint*640 + 512 + 70 +: 3], fabric_rx_flit[reduce_endpoint*640 + 512 + 82 +: 4]}; // 合成七位 flit 索引
            assign reduce_request_valid[reduce_endpoint] = fabric_rx_valid[reduce_endpoint] && (fabric_rx_flit[reduce_endpoint*640 + 512 + 8 +: 3] <= 3'd2) && !fabric_rx_flit[reduce_endpoint*640 + 512 + 16]; // 仅 Ring RS phase 形成 reduction 请求
            assign reduce_request_header[reduce_endpoint*96 +: 96] = fabric_rx_flit[reduce_endpoint*640 + 512 +: 96]; // 提取当前 RX header
            assign reduce_local[reduce_endpoint*512 +: 512] = tensor_mem_q[(((REDUCE_NODE*16 + REDUCE_BANK)*32 + rx_chunk)*FLITS_PER_CHUNK) + rx_tensor_flit]; // 从本地 bank memory 读取 reduction operand
            assign reduce_remote[reduce_endpoint*512 +: 512] = fabric_rx_flit[reduce_endpoint*640 +: 512]; // 提取当前远端 payload
        end // 结束当前 endpoint bank reduction 生成
    endgenerate // 结束五百一十二路 reduction 生成
    kdlink_v2_int32_reduce_array512 u_reduce_array ( // 实例化五百一十二 bank 规则化 reduction 阵列
        .clk_i(clk_i), .rst_n_i(rst_n_i), // 连接 reduction 阵列时钟复位
        .valid_i(reduce_request_valid), .header_i(reduce_request_header), .local_i(reduce_local), .remote_i(reduce_remote), // 连接全部 bank reduction 请求
        .valid_o(reduce_valid), .header_o(reduce_header), .result_o(reduce_result) // 连接全部 bank reduction 结果
    ); // 结束 reduction 阵列实例
    genvar result_endpoint; // 提供五百一十二 endpoint bank 结果读映射索引
    generate // 建立并行 Tensor result memory 读取边界
        for (result_endpoint = 0; result_endpoint < ENDPOINT_LANES; result_endpoint = result_endpoint + 1) begin : g_result // 生成当前 endpoint bank 结果读取
            localparam integer RESULT_NODE = result_endpoint / 16; // 固定当前结果 node identity
            localparam integer RESULT_BANK = result_endpoint % 16; // 固定当前结果 bank identity
            assign result_data_o[result_endpoint*512 +: 512] = result_direct_q ? direct_result_mem_q[(((RESULT_NODE*16 + RESULT_BANK)*32 + result_chunk_i)*FLITS_PER_CHUNK) + result_flit_i] : tensor_mem_q[(((RESULT_NODE*16 + RESULT_BANK)*32 + result_chunk_i)*FLITS_PER_CHUNK) + result_flit_i]; // 读取最近 Ring 或 direct operation 结果
        end // 结束当前 endpoint bank 结果映射
    endgenerate // 结束并行结果读取边界
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 Tensor memory、Ring schedule 和 completion
        if (!rst_n_i) begin // 检测复位有效
            state_q <= STATE_IDLE; // 复位进入空闲状态
            opcode_q <= 3'd0; // 清零 active opcode
            collective_id_q <= 12'd0; // 清零 collective identity
            link_epoch_q <= 8'd0; // 清零 link epoch
            step_q <= 5'd0; // 清零 Ring step
            flit_index_q <= 7'd0; // 清零 bank 内 flit 索引
            expected_receive_cycles_q <= 32'd0; // 清零期望接收周期数
            receive_cycles_q <= 32'd0; // 清零实际接收周期数
            drain_count_q <= 3'd0; // 清零尾部排空计数
            p2p_src_q <= 5'd0; // 清零 PointToPoint source
            p2p_dst_q <= 5'd0; // 清零 PointToPoint destination
            p2p_flits_q <= 8'd0; // 清零 PointToPoint count
            expected_receive_flits_q <= 32'd0; // 清零 direct 期望 flit
            received_flits_q <= 32'd0; // 清零 direct 已接收 flit
            configured_endpoint_flits_q <= 32'd0; // 清零 AllToAllv 配置总数
            result_direct_q <= 1'b0; // 默认选择 Ring Tensor memory
            done_o <= 1'b0; // 清除 completion 脉冲
            operation_error_o <= 1'b0; // 清除 operation error
            lane_alignment_error_o <= 1'b0; // 清除 lane alignment error
            operation_cycles_o <= 32'd0; // 清零 operation 周期计数
            for (direct_reset_index = 0; direct_reset_index < 1024; direct_reset_index = direct_reset_index + 1) direct_count_q[direct_reset_index] <= 8'd0; // 清零 AllToAllv count 表
            for (direct_step_reset_index = 0; direct_step_reset_index < 32; direct_step_reset_index = direct_step_reset_index + 1) direct_step_max_q[direct_step_reset_index] <= 8'd0; // 清零 permutation step maximum
        end else begin // 处理正常 collective operation
            done_o <= 1'b0; // 默认本周期无 completion 脉冲
            if (state_q != STATE_IDLE) operation_cycles_o <= operation_cycles_o + 32'd1; // active 期间累计 descriptor-to-completion 周期
            if (|fabric_protocol_error_o) operation_error_o <= 1'b1; // sticky 捕获任一 plane 协议错误
            if ((opcode_q <= 3'd2) && (|fabric_rx_valid) && !(&fabric_rx_valid)) lane_alignment_error_o <= 1'b1; // Ring operation sticky 捕获跨 plane/slice RX 未对齐
            if (direct_cfg_valid_i && direct_cfg_ready_o) begin // 更新一个 AllToAllv pair count
                if (direct_cfg_flits_i > FLITS_PER_CHUNK) operation_error_o <= 1'b1; // 拒绝超过本地 chunk 容量的 count
                else begin // 提交合法 pair count 和增量统计
                    configured_endpoint_flits_q <= configured_endpoint_flits_q - {20'd0, direct_count_q[direct_cfg_src_i*32 + direct_cfg_dst_i], 4'd0} + {20'd0, direct_cfg_flits_i, 4'd0}; // 更新全部十六 bank endpoint flit 总数
                    direct_count_q[direct_cfg_src_i*32 + direct_cfg_dst_i] <= direct_cfg_flits_i; // 更新 pair count
                    if (direct_cfg_flits_i > direct_step_max_q[direct_cfg_dst_i-direct_cfg_src_i]) direct_step_max_q[direct_cfg_dst_i-direct_cfg_src_i] <= direct_cfg_flits_i; // 单调更新当前 permutation step maximum
                end // 结束合法配置提交
            end // 结束 direct count 配置
            if (load_valid_i && load_ready_o) begin // 接受一个全 node/bank 并行 Tensor load word
                for (endpoint_index = 0; endpoint_index < ENDPOINT_LANES; endpoint_index = endpoint_index + 1) begin // 写入全部 endpoint bank memory
                    tensor_mem_q[(((endpoint_index)*32 + load_chunk_i)*FLITS_PER_CHUNK) + load_flit_i] <= load_data_i[endpoint_index*512 +: 512]; // 写入当前 endpoint bank Tensor word
                end // 结束全部 endpoint bank memory 加载
            end // 结束并行 Tensor load
            for (endpoint_index = 0; endpoint_index < ENDPOINT_LANES; endpoint_index = endpoint_index + 1) begin // 提交全部 RX Tensor memory side effect
                if (fabric_rx_valid[endpoint_index] && (fabric_rx_flit[endpoint_index*640 + 512 + 8 +: 3] <= 3'd2) && fabric_rx_flit[endpoint_index*640 + 512 + 16]) begin // AllGather phase 直接提交远端 payload
                    tensor_mem_q[(((endpoint_index)*32 + fabric_rx_flit[endpoint_index*640 + 512 + 58 +: 5])*FLITS_PER_CHUNK) + {fabric_rx_flit[endpoint_index*640 + 512 + 70 +: 3], fabric_rx_flit[endpoint_index*640 + 512 + 82 +: 4]}] <= fabric_rx_flit[endpoint_index*640 +: 512]; // 写入 AG 收到的完整 payload
                end // 结束 AG memory 写回
                if (fabric_rx_valid[endpoint_index] && (fabric_rx_flit[endpoint_index*640 + 512 + 8 +: 3] >= 3'd3)) begin // direct operation 写入独立 destination memory
                    direct_result_mem_q[(((endpoint_index)*32 + fabric_rx_flit[endpoint_index*640 + 512 + 58 +: 5])*FLITS_PER_CHUNK) + {fabric_rx_flit[endpoint_index*640 + 512 + 70 +: 3], fabric_rx_flit[endpoint_index*640 + 512 + 82 +: 4]}] <= fabric_rx_flit[endpoint_index*640 +: 512]; // 以 source chunk identity 提交 direct payload
                end // 结束 direct memory 写回
                if (reduce_valid[endpoint_index]) begin // ReduceScatter reduction pipeline 结果有效
                    tensor_mem_q[(((endpoint_index)*32 + reduce_header[endpoint_index*96 + 58 +: 5])*FLITS_PER_CHUNK) + {reduce_header[endpoint_index*96 + 70 +: 3], reduce_header[endpoint_index*96 + 82 +: 4]}] <= reduce_result[endpoint_index*512 +: 512]; // 写入十六 lane INT32 reduction 结果
                end // 结束 RS reduction memory 写回
            end // 结束全部 RX memory side effect
            if (state_q == STATE_IDLE && start_i && start_ready_o) begin // 接受新 collective operation
                if (opcode_i > 3'd5 || ((opcode_i == 3'd5) && ((p2p_src_node_i == p2p_dst_node_i) || (p2p_flits_i == 0) || (p2p_flits_i > FLITS_PER_CHUNK)))) begin // 检查六种 opcode 和 PointToPoint 参数
                    operation_error_o <= 1'b1; // 报告非法 operation
                end else begin // 锁存合法 operation 配置
                    opcode_q <= opcode_i; // 锁存 active opcode
                    collective_id_q <= collective_id_i; // 锁存 collective identity
                    link_epoch_q <= link_epoch_i; // 锁存 link epoch
                    step_q <= 5'd0; // 从 Ring step 零开始
                    flit_index_q <= 7'd0; // 从 chunk flit 零开始
                    expected_receive_cycles_q <= (opcode_i == 3'd2) ? 62*FLITS_PER_CHUNK : 31*FLITS_PER_CHUNK; // 计算 RS/AG/AR 完整接收周期
                    receive_cycles_q <= 32'd0; // 清零 operation 接收进度
                    drain_count_q <= 3'd0; // 清零尾部排空计数
                    p2p_src_q <= p2p_src_node_i; // 锁存 PointToPoint source
                    p2p_dst_q <= p2p_dst_node_i; // 锁存 PointToPoint destination
                    p2p_flits_q <= p2p_flits_i; // 锁存 PointToPoint count
                    expected_receive_flits_q <= direct_expected_flits_d; // 锁存 direct endpoint flit 总数
                    received_flits_q <= 32'd0; // 清零 direct 接收进度
                    result_direct_q <= opcode_i >= 3'd3; // 选择对应 operation 结果 memory
                    operation_cycles_o <= 32'd0; // 清零 descriptor-to-completion 周期
                    operation_error_o <= 1'b0; // 清除前一 operation error
                    lane_alignment_error_o <= 1'b0; // 清除前一 operation alignment error
                    if (opcode_i >= 3'd3) state_q <= STATE_DIRECT_SEND; // direct collective 进入 permutation 调度
                    else if (opcode_i == 3'd1) state_q <= STATE_AG_SEND; // AllGather 直接进入 AG phase
                    else state_q <= STATE_RS_SEND; // ReduceScatter 和 AllReduce 从 RS phase 开始
                end // 结束合法 operation 启动
            end // 结束 operation 启动处理
            if (send_fire) begin // 全部 endpoint bank 当前 flit 被 fabric 接受
                if (((state_q == STATE_DIRECT_SEND) && ((direct_step_limit_d == 0) || ({1'b0, flit_index_q} + 8'd1 >= direct_step_limit_d))) || ((state_q != STATE_DIRECT_SEND) && (flit_index_q == FLITS_PER_CHUNK-1))) begin // 检查当前 Ring 或 variable direct step 尾部
                    flit_index_q <= 7'd0; // 下一 step 从 flit 零开始
                    if (((state_q == STATE_DIRECT_SEND) && (step_q == 5'd31)) || ((state_q != STATE_DIRECT_SEND) && (step_q == 5'd30))) begin // 检查 Ring 三十一步或 direct 三十二 permutation step 全部发射
                        step_q <= 5'd0; // 下一 phase 或 idle 从 step 零开始
                        if ((state_q == STATE_RS_SEND) && (opcode_q == 3'd2)) state_q <= STATE_AG_SEND; // AllReduce 无气泡切换至 AG phase
                        else if ((state_q == STATE_DIRECT_SEND) && (expected_receive_flits_q == 0)) state_q <= STATE_DRAIN; // 空 AllToAllv 直接进入完成排空
                        else state_q <= STATE_WAIT_RX; // 单 phase、AG 或 direct 尾部等待 fabric 排空
                    end else begin // 当前 phase 仍有后续 Ring step
                        step_q <= step_q + 5'd1; // 推进至下一 Ring step
                    end // 结束 phase step 推进
                end else begin // 当前 step 仍有后续 flit
                    flit_index_q <= flit_index_q + 7'd1; // 连续推进 chunk flit
                end // 结束 chunk flit 推进
            end // 结束 TX fire 处理
            if ((opcode_q <= 3'd2) && receive_cycle_fire && (state_q != STATE_IDLE) && (state_q != STATE_DRAIN)) begin // 统计一个 Ring 五百一十二路完整 RX payload 周期
                receive_cycles_q <= receive_cycles_q + 32'd1; // 累加完整接收周期数
                if (receive_cycles_q + 32'd1 >= expected_receive_cycles_q) begin // 检查 operation 最后一组 RX payload
                    state_q <= STATE_DRAIN; // 进入 reduction 尾部排空
                    drain_count_q <= 3'd0; // 从排空周期零开始
                end // 结束最后接收周期检查
            end // 结束 RX 周期统计
            if ((opcode_q >= 3'd3) && (state_q != STATE_IDLE) && (state_q != STATE_DRAIN) && (receive_lane_count_d != 0)) begin // 累计 direct endpoint flit 接收
                received_flits_q <= received_flits_q + receive_lane_count_d; // 累加本周期所有有效 endpoint
                if (received_flits_q + receive_lane_count_d >= expected_receive_flits_q) begin // 检查最后一组 direct payload
                    state_q <= STATE_DRAIN; // 进入写回尾部排空
                    drain_count_q <= 3'd0; // 清零排空计数
                end // 结束 direct completion 检查
            end // 结束 direct RX 计数
            if (state_q == STATE_DRAIN) begin // 等待最后三级 RS reduction 或 AG write 提交
                if (drain_count_q == 3'd4) begin // 检查保守尾部排空完成
                    state_q <= STATE_IDLE; // operation 返回空闲
                    done_o <= 1'b1; // 输出单周期 completion
                end else begin // 尾部仍在排空
                    drain_count_q <= drain_count_q + 3'd1; // 推进排空计数
                end // 结束尾部排空推进
            end // 结束 drain 状态处理
        end // 结束正常 collective operation
    end // 结束 Tensor memory 和控制更新
    /* verilator lint_on WIDTHEXPAND */ // 恢复参数和 integer 宽度检查
endmodule // 结束三十二节点流式 collective 系统
