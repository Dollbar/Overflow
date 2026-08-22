`timescale 1ns/1ps // 定义三十二节点 collective 测试时间单位
module tb_kdlink_collective32_int32; // 定义四 MiB 每节点 RS AG AR 端到端自校验测试
    localparam integer FLITS_PER_CHUNK = 128; // 固定每 bank 每 chunk 一百二十八 flit
    localparam integer TENSOR_BYTES_PER_NODE = 4194304; // 固定每节点四 MiB Tensor
    logic clk; // 生成一 GHz collective 时钟
    logic rst_n; // 生成低有效复位
    logic load_valid_i; // 驱动并行 Tensor load valid
    wire load_ready_o; // 观察并行 Tensor load ready
    logic [4:0] load_chunk_i; // 驱动加载 chunk 索引
    logic [6:0] load_flit_i; // 驱动加载 flit 索引
    logic [262143:0] load_data_i; // 驱动三十二节点十六 bank 加载数据
    logic start_i; // 驱动 collective 启动脉冲
    wire start_ready_o; // 观察 collective 启动许可
    logic [2:0] opcode_i; // 驱动 RS AG 或 AR opcode
    logic [11:0] collective_id_i; // 驱动 collective identity
    logic [7:0] link_epoch_i; // 驱动 link epoch
    logic direct_cfg_valid_i; // 驱动 AllToAllv pair count 配置有效位
    wire direct_cfg_ready_o; // 观察 AllToAllv pair count 配置许可
    logic [4:0] direct_cfg_src_i; // 驱动 AllToAllv 配置 source
    logic [4:0] direct_cfg_dst_i; // 驱动 AllToAllv 配置 destination
    logic [7:0] direct_cfg_flits_i; // 驱动 AllToAllv pair flit count
    logic [4:0] p2p_src_node_i; // 驱动 PointToPoint source
    logic [4:0] p2p_dst_node_i; // 驱动 PointToPoint destination
    logic [7:0] p2p_flits_i; // 驱动 PointToPoint flit count
    wire busy_o; // 观察 operation active 状态
    wire done_o; // 观察 operation completion 脉冲
    wire operation_error_o; // 观察 operation error
    wire lane_alignment_error_o; // 观察跨 lane alignment error
    wire [31:0] operation_cycles_o; // 观察 descriptor-to-completion 周期数
    logic [4:0] result_chunk_i; // 驱动结果读取 chunk 索引
    logic [6:0] result_flit_i; // 驱动结果读取 flit 索引
    wire [262143:0] result_data_o; // 观察三十二节点十六 bank 结果数据
    wire [15:0] fabric_protocol_error_o; // 观察八 plane 双 slice fabric 错误
    integer chunk_index; // 提供三十二 chunk 循环索引
    integer flit_index; // 提供每 chunk 一百二十八 flit 循环索引
    integer endpoint_index; // 提供五百一十二 endpoint bank 循环索引
    integer node_index; // 保存当前 endpoint node
    integer bank_index; // 保存当前 endpoint bank
    integer lane_index; // 提供每 payload 十六个 INT32 lane 循环索引
    integer initial_value; // 保存当前测试 Tensor 初始 lane 值
    integer base_value; // 保存覆盖全三十二位的数据混合基值
    integer expected_value; // 保存当前 AllReduce 期望 lane SUM
    integer rs_cycles; // 保存 ReduceScatter 实测完整周期
    integer ag_cycles; // 保存 AllGather 实测完整周期
    integer ar_cycles; // 保存 AllReduce 实测完整周期
    integer alltoall_cycles; // 保存 AllToAll 实测完整周期
    integer alltoallv_cycles; // 保存 AllToAllv 实测完整周期
    integer p2p_cycles; // 保存 PointToPoint 实测完整周期
    integer direct_src_index; // 提供 AllToAllv source 配置循环索引
    integer direct_dst_index; // 提供 AllToAllv destination 配置循环索引
    real ar_effective_gbps; // 保存四 MiB AllReduce 实测有效 Tensor 带宽
    kdlink_collective32_int32 #(.FLITS_PER_CHUNK(FLITS_PER_CHUNK)) u_dut ( // 实例化三十二节点流式 collective 系统
        .clk_i(clk), .rst_n_i(rst_n), // 连接时钟和复位
        .load_valid_i(load_valid_i), .load_ready_o(load_ready_o), .load_chunk_i(load_chunk_i), .load_flit_i(load_flit_i), .load_data_i(load_data_i), // 连接并行 Tensor load
        .start_i(start_i), .start_ready_o(start_ready_o), .opcode_i(opcode_i), .collective_id_i(collective_id_i), .link_epoch_i(link_epoch_i), // 连接 descriptor 控制
        .direct_cfg_valid_i(direct_cfg_valid_i), .direct_cfg_ready_o(direct_cfg_ready_o), .direct_cfg_src_i(direct_cfg_src_i), .direct_cfg_dst_i(direct_cfg_dst_i), .direct_cfg_flits_i(direct_cfg_flits_i), // 连接 direct count 配置
        .p2p_src_node_i(p2p_src_node_i), .p2p_dst_node_i(p2p_dst_node_i), .p2p_flits_i(p2p_flits_i), // 连接 PointToPoint descriptor
        .busy_o(busy_o), .done_o(done_o), .operation_error_o(operation_error_o), .lane_alignment_error_o(lane_alignment_error_o), .operation_cycles_o(operation_cycles_o), // 连接 operation 状态
        .result_chunk_i(result_chunk_i), .result_flit_i(result_flit_i), .result_data_o(result_data_o), .fabric_protocol_error_o(fabric_protocol_error_o) // 连接并行 result 读取和 fabric 状态
    ); // 结束 collective 系统实例
    always #0.5 clk = ~clk; // 生成一 GHz 时钟
    initial begin // 执行四 MiB Tensor RS AG AR 端到端测试
        clk = 1'b0; // 初始化时钟
        rst_n = 1'b0; // 初始保持复位
        load_valid_i = 1'b0; // 清除 Tensor load valid
        load_chunk_i = 5'd0; // 清零加载 chunk
        load_flit_i = 7'd0; // 清零加载 flit
        for (endpoint_index = 0; endpoint_index < 512; endpoint_index = endpoint_index + 1) load_data_i[endpoint_index*512 +: 512] = 512'd0; // 清零全部加载数据
        start_i = 1'b0; // 清除 collective 启动
        opcode_i = 3'd0; // 默认选择 ReduceScatter
        collective_id_i = 12'h321; // 设置 collective identity
        link_epoch_i = 8'h5A; // 设置 link epoch
        direct_cfg_valid_i = 1'b0; // 清除 AllToAllv 配置有效位
        direct_cfg_src_i = 5'd0; // 清零 AllToAllv source
        direct_cfg_dst_i = 5'd0; // 清零 AllToAllv destination
        direct_cfg_flits_i = 8'd0; // 清零 AllToAllv pair count
        p2p_src_node_i = 5'd0; // 初始化 PointToPoint source
        p2p_dst_node_i = 5'd1; // 初始化 PointToPoint destination
        p2p_flits_i = 8'd1; // 初始化 PointToPoint count
        result_chunk_i = 5'd0; // 清零结果读取 chunk
        result_flit_i = 7'd0; // 清零结果读取 flit
        rs_cycles = 0; // 清零 RS 周期记录
        ag_cycles = 0; // 清零 AG 周期记录
        ar_cycles = 0; // 清零 AR 周期记录
        alltoall_cycles = 0; // 清零 AllToAll 周期记录
        alltoallv_cycles = 0; // 清零 AllToAllv 周期记录
        p2p_cycles = 0; // 清零 PointToPoint 周期记录
        ar_effective_gbps = 0.0; // 清零 AR 带宽记录
        repeat (4) @(posedge clk); // 等待复位稳定
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        for (chunk_index = 0; chunk_index < 32; chunk_index = chunk_index + 1) begin // 加载首轮四 MiB 每节点 Tensor
            for (flit_index = 0; flit_index < FLITS_PER_CHUNK; flit_index = flit_index + 1) begin // 加载当前 chunk 全部 bank flit
                @(negedge clk); // 在下降沿建立并行 load 数据
                if (!load_ready_o) $fatal(1, "Tensor load unexpectedly blocked chunk=%0d flit=%0d", chunk_index, flit_index); // 要求 idle load 无停顿
                load_valid_i = 1'b1; // 提交当前全 node/bank load word
                load_chunk_i = chunk_index[4:0]; // 写入当前 chunk 索引
                load_flit_i = flit_index[6:0]; // 写入当前 flit 索引
                for (endpoint_index = 0; endpoint_index < 512; endpoint_index = endpoint_index + 1) begin // 构造全部 node/bank 初始 Tensor
                    node_index = endpoint_index / 16; // 反解当前 node
                    bank_index = endpoint_index & 15; // 反解当前 bank
                    for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 构造当前 payload 十六个 lane
                        base_value = (chunk_index * 32'h9e37_79b9) ^ (bank_index * 32'h7f4a_7c15) ^ (flit_index * 32'h6a09_e667) ^ (lane_index * 32'hbb67_ae85); // 形成确定性全位翻转模式
                        initial_value = node_index + base_value; // 保留对 node index 的线性关系以便闭式计算 SUM
                        load_data_i[endpoint_index*512 + lane_index*32 +: 32] = initial_value[31:0]; // 写入当前 INT32 lane
                    end // 结束当前 payload lane 构造
                end // 结束全部 endpoint 初始 Tensor 构造
            end // 结束当前 chunk 加载
        end // 结束首轮 Tensor 加载
        @(negedge clk); load_valid_i = 1'b0; opcode_i = 3'd0; start_i = 1'b1; // 启动 ReduceScatter operation
        @(negedge clk); start_i = 1'b0; // 清除 ReduceScatter 启动脉冲
        wait (done_o); #0.01; // 等待 ReduceScatter descriptor-to-completion
        rs_cycles = operation_cycles_o; // 保存 ReduceScatter 完整周期数
        if (operation_error_o || lane_alignment_error_o || fabric_protocol_error_o != 16'd0) $fatal(1, "ReduceScatter status failure op=%b align=%b fabric=%h", operation_error_o, lane_alignment_error_o, fabric_protocol_error_o); // 要求 RS 无错误
        for (chunk_index = 0; chunk_index < 32; chunk_index = chunk_index + 1) begin // 检查每个 chunk 的最终 owner
            for (flit_index = 0; flit_index < FLITS_PER_CHUNK; flit_index = flit_index + 1) begin // 检查当前 chunk 全部 flit
                @(negedge clk); result_chunk_i = chunk_index[4:0]; result_flit_i = flit_index[6:0]; #0.01; // 选择当前并行 result word
                for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 检查 owner node 十六 bank
                    endpoint_index = chunk_index*16 + bank_index; // RS chunk owner node 等于 chunk identity
                    for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 检查当前 payload 十六 lane
                        base_value = (chunk_index * 32'h9e37_79b9) ^ (bank_index * 32'h7f4a_7c15) ^ (flit_index * 32'h6a09_e667) ^ (lane_index * 32'hbb67_ae85); // 重建确定性全位基值
                        expected_value = 496 + 32*base_value; // 计算三十二 node modulo SUM
                        if (result_data_o[endpoint_index*512 + lane_index*32 +: 32] != expected_value[31:0]) $fatal(1, "RS result mismatch chunk=%0d flit=%0d bank=%0d lane=%0d got=%h expected=%h", chunk_index, flit_index, bank_index, lane_index, result_data_o[endpoint_index*512 + lane_index*32 +: 32], expected_value[31:0]); // 要求 owner chunk bit-exact
                    end // 结束 owner payload lane 检查
                end // 结束 owner bank 检查
            end // 结束当前 chunk flit 检查
        end // 结束 ReduceScatter owner 检查
        @(negedge clk); opcode_i = 3'd1; collective_id_i = 12'h322; start_i = 1'b1; // 在 RS 结果上启动 AllGather
        @(negedge clk); start_i = 1'b0; // 清除 AllGather 启动脉冲
        wait (done_o); #0.01; // 等待 AllGather descriptor-to-completion
        ag_cycles = operation_cycles_o; // 保存 AllGather 完整周期数
        if (operation_error_o || lane_alignment_error_o || fabric_protocol_error_o != 16'd0) $fatal(1, "AllGather status failure op=%b align=%b fabric=%h", operation_error_o, lane_alignment_error_o, fabric_protocol_error_o); // 要求 AG 无错误
        for (chunk_index = 0; chunk_index < 32; chunk_index = chunk_index + 1) begin // 检查所有 node 的完整 AllGather Tensor
            for (flit_index = 0; flit_index < FLITS_PER_CHUNK; flit_index = flit_index + 1) begin // 检查当前 chunk 全部 flit
                @(negedge clk); result_chunk_i = chunk_index[4:0]; result_flit_i = flit_index[6:0]; #0.01; // 选择当前并行 result word
                for (endpoint_index = 0; endpoint_index < 512; endpoint_index = endpoint_index + 1) begin // 检查全部 node/bank
                    bank_index = endpoint_index & 15; // 反解当前 bank
                    for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 检查当前 payload 十六 lane
                        base_value = (chunk_index * 32'h9e37_79b9) ^ (bank_index * 32'h7f4a_7c15) ^ (flit_index * 32'h6a09_e667) ^ (lane_index * 32'hbb67_ae85); // 重建确定性全位基值
                        expected_value = 496 + 32*base_value; // 计算三十二 node modulo SUM
                        if (result_data_o[endpoint_index*512 + lane_index*32 +: 32] != expected_value[31:0]) $fatal(1, "AG result mismatch chunk=%0d flit=%0d endpoint=%0d lane=%0d", chunk_index, flit_index, endpoint_index, lane_index); // 要求所有 node 完整 bit-exact Tensor
                    end // 结束当前 payload lane 检查
                end // 结束全部 endpoint 检查
            end // 结束当前 chunk flit 检查
        end // 结束 AllGather 完整 Tensor 检查
        for (chunk_index = 0; chunk_index < 32; chunk_index = chunk_index + 1) begin // 重新加载 AllReduce 首态 Tensor
            for (flit_index = 0; flit_index < FLITS_PER_CHUNK; flit_index = flit_index + 1) begin // 加载当前 chunk 全部 bank flit
                @(negedge clk); // 在下降沿建立并行 reload 数据
                if (!load_ready_o) $fatal(1, "Tensor reload unexpectedly blocked chunk=%0d flit=%0d", chunk_index, flit_index); // 要求 idle reload 无停顿
                load_valid_i = 1'b1; // 提交当前全 node/bank reload word
                load_chunk_i = chunk_index[4:0]; // 写入当前 chunk 索引
                load_flit_i = flit_index[6:0]; // 写入当前 flit 索引
                for (endpoint_index = 0; endpoint_index < 512; endpoint_index = endpoint_index + 1) begin // 构造全部 node/bank 初始 Tensor
                    node_index = endpoint_index / 16; // 反解当前 node
                    bank_index = endpoint_index & 15; // 反解当前 bank
                    for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 构造当前 payload 十六 lane
                        base_value = (chunk_index * 32'h9e37_79b9) ^ (bank_index * 32'h7f4a_7c15) ^ (flit_index * 32'h6a09_e667) ^ (lane_index * 32'hbb67_ae85); // 形成同一确定性全位模式
                        initial_value = node_index + base_value; // 保留可闭式归约关系
                        load_data_i[endpoint_index*512 + lane_index*32 +: 32] = initial_value[31:0]; // 写入当前 INT32 lane
                    end // 结束当前 payload lane 构造
                end // 结束全部 endpoint reload 构造
            end // 结束当前 chunk reload
        end // 结束 AllReduce Tensor reload
        @(negedge clk); load_valid_i = 1'b0; opcode_i = 3'd2; collective_id_i = 12'h323; start_i = 1'b1; // 启动完整 AllReduce
        @(negedge clk); start_i = 1'b0; // 清除 AllReduce 启动脉冲
        wait (done_o); #0.01; // 等待完整 AllReduce descriptor-to-completion
        ar_cycles = operation_cycles_o; // 保存 AllReduce 完整周期数
        ar_effective_gbps = TENSOR_BYTES_PER_NODE * 1.0 / ar_cycles; // 按一 GHz 计算每节点有效 Tensor GB/s
        if (ar_cycles > 8388) $fatal(1, "AllReduce effective bandwidth below 500 GB/s cycles=%0d bandwidth=%0f", ar_cycles, ar_effective_gbps); // 要求四 MiB Tensor 至少五百 GB/s
        if (operation_error_o || lane_alignment_error_o || fabric_protocol_error_o != 16'd0) $fatal(1, "AllReduce status failure op=%b align=%b fabric=%h", operation_error_o, lane_alignment_error_o, fabric_protocol_error_o); // 要求 AR 无错误
        for (chunk_index = 0; chunk_index < 32; chunk_index = chunk_index + 1) begin // 检查完整 AllReduce Tensor
            for (flit_index = 0; flit_index < FLITS_PER_CHUNK; flit_index = flit_index + 1) begin // 检查当前 chunk 全部 flit
                @(negedge clk); result_chunk_i = chunk_index[4:0]; result_flit_i = flit_index[6:0]; #0.01; // 选择当前并行 result word
                for (endpoint_index = 0; endpoint_index < 512; endpoint_index = endpoint_index + 1) begin // 检查全部 node/bank
                    bank_index = endpoint_index & 15; // 反解当前 bank
                    for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 检查当前 payload 十六 lane
                        base_value = (chunk_index * 32'h9e37_79b9) ^ (bank_index * 32'h7f4a_7c15) ^ (flit_index * 32'h6a09_e667) ^ (lane_index * 32'hbb67_ae85); // 重建确定性全位基值
                        expected_value = 496 + 32*base_value; // 计算三十二 node modulo SUM
                        if (result_data_o[endpoint_index*512 + lane_index*32 +: 32] != expected_value[31:0]) $fatal(1, "AR result mismatch chunk=%0d flit=%0d endpoint=%0d lane=%0d", chunk_index, flit_index, endpoint_index, lane_index); // 要求 AllReduce 全 Tensor bit-exact
                    end // 结束当前 payload lane 检查
                end // 结束全部 endpoint 检查
            end // 结束当前 chunk flit 检查
        end // 结束 AllReduce 完整 Tensor 检查
        @(negedge clk); opcode_i = 3'd3; collective_id_i = 12'hc5a; link_epoch_i = 8'ha5; start_i = 1'b1; // 启动等长 AllToAll 覆盖 direct full-count 路径
        @(negedge clk); start_i = 1'b0; // 清除 AllToAll 启动脉冲
        wait (done_o); #0.01; // 等待 AllToAll 完成
        alltoall_cycles = operation_cycles_o; // 保存 AllToAll 完整周期
        if (operation_error_o || lane_alignment_error_o || fabric_protocol_error_o != 16'd0) $fatal(1, "AllToAll status failure op=%b align=%b fabric=%h", operation_error_o, lane_alignment_error_o, fabric_protocol_error_o); // 要求 AllToAll 无错误
        @(negedge clk); result_chunk_i = 5'd31; result_flit_i = 7'd127; #0.01; // 抽查 source 31 发往 destination 0 的最后一个 flit
        for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 检查 destination 0 全部 bank
            for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 检查当前 payload 全部 lane
                base_value = (0 * 32'h9e37_79b9) ^ (bank_index * 32'h7f4a_7c15) ^ (127 * 32'h6a09_e667) ^ (lane_index * 32'hbb67_ae85); // 重建 destination chunk 对应归约值
                expected_value = 496 + 32*base_value; // 计算期望 AllReduce 载荷
                if (result_data_o[bank_index*512 + lane_index*32 +: 32] != expected_value[31:0]) $fatal(1, "AllToAll result mismatch bank=%0d lane=%0d", bank_index, lane_index); // 要求 direct memory bit-exact
            end // 结束当前 payload lane 检查
        end // 结束 destination 0 bank 检查
        for (direct_src_index = 0; direct_src_index < 32; direct_src_index = direct_src_index + 1) begin // 配置全部 AllToAllv source-destination pair
            for (direct_dst_index = 0; direct_dst_index < 32; direct_dst_index = direct_dst_index + 1) begin // 遍历当前 source 全部 destination
                @(negedge clk); // 在下降沿建立 pair 配置
                if (!direct_cfg_ready_o) $fatal(1, "AllToAllv configuration unexpectedly blocked src=%0d dst=%0d", direct_src_index, direct_dst_index); // 要求 idle 配置无停顿
                direct_cfg_valid_i = 1'b1; // 提交当前 pair count
                direct_cfg_src_i = direct_src_index[4:0]; // 设置 source identity
                direct_cfg_dst_i = direct_dst_index[4:0]; // 设置 destination identity
                base_value = (direct_src_index * 32'h0000_003d) ^ (direct_dst_index * 32'h0000_00a7) ^ 32'h0000_005a; // 形成确定性 pair count 混合值
                direct_cfg_flits_i = {1'b0, base_value[6:0]}; // 用高熵合法 count 覆盖全部数据位
                if ((direct_src_index == 0 && direct_dst_index == 31) || (direct_src_index == 31 && direct_dst_index == 0)) direct_cfg_flits_i = 8'd128; // 为边界 pair 覆盖最大合法 count
            end // 结束 destination 配置
        end // 结束 source 配置
        @(negedge clk); direct_cfg_valid_i = 1'b0; opcode_i = 3'd4; collective_id_i = 12'h5a3; link_epoch_i = 8'h3c; start_i = 1'b1; // 启动变长 AllToAllv
        @(negedge clk); start_i = 1'b0; // 清除 AllToAllv 启动脉冲
        wait (done_o); #0.01; // 等待 AllToAllv 完成
        alltoallv_cycles = operation_cycles_o; // 保存 AllToAllv 完整周期
        if (operation_error_o || lane_alignment_error_o || fabric_protocol_error_o != 16'd0) $fatal(1, "AllToAllv status failure op=%b align=%b fabric=%h", operation_error_o, lane_alignment_error_o, fabric_protocol_error_o); // 要求 AllToAllv 无错误
        @(negedge clk); result_chunk_i = 5'd0; result_flit_i = 7'd127; #0.01; // 抽查 source 0 发往 destination 31 的最大 count pair
        for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 检查 destination 31 全部 bank
            for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 检查当前 payload 全部 lane
                base_value = (31 * 32'h9e37_79b9) ^ (bank_index * 32'h7f4a_7c15) ^ (127 * 32'h6a09_e667) ^ (lane_index * 32'hbb67_ae85); // 重建 destination chunk 对应归约值
                expected_value = 496 + 32*base_value; // 计算期望 AllReduce 载荷
                if (result_data_o[(31*16 + bank_index)*512 + lane_index*32 +: 32] != expected_value[31:0]) $fatal(1, "AllToAllv result mismatch bank=%0d lane=%0d", bank_index, lane_index); // 要求 variable direct memory bit-exact
            end // 结束当前 payload lane 检查
        end // 结束 destination 31 bank 检查
        @(negedge clk); opcode_i = 3'd5; collective_id_i = 12'hf0f; link_epoch_i = 8'hc3; p2p_src_node_i = 5'd29; p2p_dst_node_i = 5'd2; p2p_flits_i = 8'd127; start_i = 1'b1; // 启动非相邻节点 PointToPoint
        @(negedge clk); start_i = 1'b0; // 清除 PointToPoint 启动脉冲
        wait (done_o); #0.01; // 等待 PointToPoint 完成
        p2p_cycles = operation_cycles_o; // 保存 PointToPoint 完整周期
        if (operation_error_o || lane_alignment_error_o || fabric_protocol_error_o != 16'd0) $fatal(1, "PointToPoint status failure op=%b align=%b fabric=%h", operation_error_o, lane_alignment_error_o, fabric_protocol_error_o); // 要求 PointToPoint 无错误
        @(negedge clk); result_chunk_i = 5'd29; result_flit_i = 7'd126; #0.01; // 抽查 PointToPoint 最后一个有效 flit
        for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin // 检查 destination 2 全部 bank
            for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin // 检查当前 payload 全部 lane
                base_value = (2 * 32'h9e37_79b9) ^ (bank_index * 32'h7f4a_7c15) ^ (126 * 32'h6a09_e667) ^ (lane_index * 32'hbb67_ae85); // 重建 destination chunk 对应归约值
                expected_value = 496 + 32*base_value; // 计算期望 AllReduce 载荷
                if (result_data_o[(2*16 + bank_index)*512 + lane_index*32 +: 32] != expected_value[31:0]) $fatal(1, "PointToPoint result mismatch bank=%0d lane=%0d", bank_index, lane_index); // 要求 PointToPoint direct memory bit-exact
            end // 结束当前 payload lane 检查
        end // 结束 destination 2 bank 检查
        $display("TB_KDLINK_COLLECTIVE32_INT32_PASS tensor_bytes_per_node=%0d rs_cycles=%0d ag_cycles=%0d ar_cycles=%0d alltoall_cycles=%0d alltoallv_cycles=%0d p2p_cycles=%0d ar_effective_GBps=%0.3f threshold_GBps=500.000 nodes=32 banks=16 bubbles=0", TENSOR_BYTES_PER_NODE, rs_cycles, ag_cycles, ar_cycles, alltoall_cycles, alltoallv_cycles, p2p_cycles, ar_effective_gbps); // 报告完整 32-node RTL collective 性能
        $finish; // 结束测试
    end // 结束主测试流程
    initial begin // 设置仿真超时
        #100000; // 等待最大端到端测试时长
        $fatal(1, "KDLink collective32 timeout"); // 超时失败
    end // 结束超时保护
endmodule // 结束三十二节点 collective 测试
