`timescale 1ns/1ps
`default_nettype none

// 根节点把逻辑方阵地址转换为各Tile行/列边界的物理NoC目的地址。
module gemm_root_dispatcher #(
    parameter integer ARRAY_X = 16,
    parameter integer ARRAY_Y = 16,
    parameter integer ACTIVE_CONTEXTS = 16
) (
    input  logic         clk_i,
    input  logic         rst_i,
    input  logic         clear_i,
    input  logic         in_valid_i,
    output logic         in_ready_o,
    input  logic         in_vc_i,
    input  logic [159:0] in_flit_i,
    output logic         out_valid_o,
    input  logic         out_ready_i,
    output logic         out_vc_o,
    output logic [159:0] out_flit_o,
    output logic         protocol_error_o,
    output logic         context_full_o
);

    localparam logic [5:0] ARRAY_X_LIMIT = ARRAY_X[5:0];
    localparam logic [5:0] ARRAY_Y_LIMIT = ARRAY_Y[5:0];
    localparam integer CONTEXT_INDEX_WIDTH =
        (ACTIVE_CONTEXTS <= 1) ? 1 : $clog2(ACTIVE_CONTEXTS);

    tile_noc_pkg::tile_noc_flit_t input_flit;
    tile_noc_pkg::tile_noc_flit_t live_dispatch_flit;
    tile_noc_pkg::tile_noc_flit_t allocation_commit_flit;
    logic context_valid_q [0:ACTIVE_CONTEXTS-1];
    logic [7:0] context_tag_q [0:ACTIVE_CONTEXTS-1];
    logic [3:0] context_anchor_x_q [0:ACTIVE_CONTEXTS-1];
    logic [3:0] context_anchor_y_q [0:ACTIVE_CONTEXTS-1];
    logic [4:0] context_span_q [0:ACTIVE_CONTEXTS-1];
    logic [3:0] context_a_tile_row_q [0:ACTIVE_CONTEXTS-1];
    logic [3:0] context_a_local_row_q [0:ACTIVE_CONTEXTS-1];
    logic [3:0] context_b_tile_column_q [0:ACTIVE_CONTEXTS-1];
    logic [3:0] context_b_local_column_q [0:ACTIVE_CONTEXTS-1];
    logic context_match;
    logic context_free;
    logic stream_context_match;
    logic [15:0] context_match_vector;
    logic [15:0] context_free_vector;
    logic [CONTEXT_INDEX_WIDTH-1:0] context_match_index;
    logic [CONTEXT_INDEX_WIDTH-1:0] context_free_index;
    logic [CONTEXT_INDEX_WIDTH-1:0] selected_context_index;
    logic compute_message;
    logic activation_message;
    logic weight_message;
    logic release_message;
    logic geometry_valid;
    logic stream_context_shape_valid;
    logic context_available;
    logic input_fire;
    logic live_dispatch_fire;
    logic allocation_capture;
    logic allocation_data_capture;
    logic allocation_validation_fire;
    logic allocation_dispatch_fire;
    logic allocation_commit_fire;
    logic allocation_shape_valid;
    logic allocation_dispatch_permitted;
    logic allocation_last_position_error;
    logic output_slot_available;
    logic stream_last_position_error;
    logic [5:0] region_limit_x;
    logic [5:0] region_limit_y;
    logic output_valid_q;
    logic output_vc_q;
    logic [159:0] output_flit_q;
    logic egress_fifo_in_ready;
    logic allocation_pending_q;
    logic allocation_validation_pending_q;
    logic allocation_vc_q;
    tile_noc_pkg::tile_noc_flit_t allocation_flit_q;
    logic [CONTEXT_INDEX_WIDTH-1:0] allocation_context_index_q;
    logic allocation_new_context_q;
    logic allocation_geometry_valid_q;
    logic allocation_dispatch_permitted_q;
    logic allocation_last_position_error_q;
    logic allocation_activation;
    logic allocation_weight;
    logic stream_context_valid_q;
    logic [7:0] stream_context_tag_q;
    logic [CONTEXT_INDEX_WIDTH-1:0] stream_context_index_q;
    logic [ACTIVE_CONTEXTS-1:0] stream_context_onehot_q;
    logic [3:0] stream_anchor_x_q;
    logic [3:0] stream_anchor_y_q;
    logic [4:0] stream_span_q;
    logic stream_tag_load_inverted;
    logic stream_tag_load_buffered;
    logic stream_index_load_inverted;
    logic stream_index_load_buffered;
    logic stream_onehot_load_inverted;
    logic stream_onehot_load_buffered;
    logic stream_shape_load_inverted;
    logic stream_shape_load_buffered;

    // ACTIVE_CONTEXTS最多为16。固定宽度并行请求向量避免由“找到后停止”
    // 的循环写法推导出16级串行优先链，后者会落在根分发器的关键路径上。
    function automatic logic [CONTEXT_INDEX_WIDTH-1:0] priority_index16(
        input logic [15:0] request
    );
        begin
            casez (request)
                16'b???????????????1: priority_index16 = CONTEXT_INDEX_WIDTH'(0);
                16'b??????????????10: priority_index16 = CONTEXT_INDEX_WIDTH'(1);
                16'b?????????????100: priority_index16 = CONTEXT_INDEX_WIDTH'(2);
                16'b????????????1000: priority_index16 = CONTEXT_INDEX_WIDTH'(3);
                16'b???????????10000: priority_index16 = CONTEXT_INDEX_WIDTH'(4);
                16'b??????????100000: priority_index16 = CONTEXT_INDEX_WIDTH'(5);
                16'b?????????1000000: priority_index16 = CONTEXT_INDEX_WIDTH'(6);
                16'b????????10000000: priority_index16 = CONTEXT_INDEX_WIDTH'(7);
                16'b???????100000000: priority_index16 = CONTEXT_INDEX_WIDTH'(8);
                16'b??????1000000000: priority_index16 = CONTEXT_INDEX_WIDTH'(9);
                16'b?????10000000000: priority_index16 = CONTEXT_INDEX_WIDTH'(10);
                16'b????100000000000: priority_index16 = CONTEXT_INDEX_WIDTH'(11);
                16'b???1000000000000: priority_index16 = CONTEXT_INDEX_WIDTH'(12);
                16'b??10000000000000: priority_index16 = CONTEXT_INDEX_WIDTH'(13);
                16'b?100000000000000: priority_index16 = CONTEXT_INDEX_WIDTH'(14);
                16'b1000000000000000: priority_index16 = CONTEXT_INDEX_WIDTH'(15);
                default:              priority_index16 = CONTEXT_INDEX_WIDTH'(0);
            endcase
        end
    endfunction

    assign input_flit = tile_noc_pkg::tile_noc_flit_t'(in_flit_i);
    assign activation_message =
        input_flit.msg_type == tile_noc_pkg::TILE_NOC_MSG_ACTIVATION;
    assign weight_message =
        input_flit.msg_type == tile_noc_pkg::TILE_NOC_MSG_WEIGHT;
    assign compute_message = activation_message || weight_message;
    assign release_message =
        (input_flit.msg_type == tile_noc_pkg::TILE_NOC_MSG_CONTROL) &&
        (input_flit.aux == tile_noc_pkg::TILE_NOC_CTRL_RELEASE);
    assign region_limit_x = {2'b00, input_flit.dst_x} +
                            {1'b0, input_flit.tile_span};
    assign region_limit_y = {2'b00, input_flit.dst_y} +
                            {1'b0, input_flit.tile_span};
    assign geometry_valid = (input_flit.tile_span != 5'd0) &&
                            (input_flit.tile_span <= 5'd16) &&
                            (region_limit_x <= ARRAY_X_LIMIT) &&
                            (region_limit_y <= ARRAY_Y_LIMIT);

    always_comb begin
        context_match_vector = 16'd0;
        context_free_vector = 16'd0;
        for (integer lookup_index = 0;
             lookup_index < ACTIVE_CONTEXTS;
             lookup_index = lookup_index + 1) begin
            context_match_vector[lookup_index] =
                context_valid_q[lookup_index] &&
                (context_tag_q[lookup_index] == input_flit.tag);
            context_free_vector[lookup_index] = !context_valid_q[lookup_index];
        end
    end

    assign context_match = |context_match_vector;
    assign context_free = |context_free_vector;
    assign stream_context_match = stream_context_valid_q &&
                                  (stream_context_tag_q == input_flit.tag);
    assign context_match_index = priority_index16(context_match_vector);
    assign context_free_index = priority_index16(context_free_vector);

    assign selected_context_index = context_match ?
                                    context_match_index : context_free_index;

    assign stream_context_shape_valid =
        (stream_anchor_x_q == input_flit.dst_x) &&
        (stream_anchor_y_q == input_flit.dst_y) &&
        (stream_span_q == input_flit.tile_span);
    assign context_available = stream_context_match ? 1'b1 :
                               (context_match || context_free);
    assign output_slot_available = !output_valid_q || egress_fifo_in_ready;
    // 新tag的首包进入一个专用分配暂存级；已有tag与控制包仍直接进入
    // 输出暂存级。分配未完成时暂停输入，避免两个不同新tag抢同一空槽。
    assign in_ready_o = !allocation_pending_q &&
                        !allocation_validation_pending_q &&
                        output_slot_available &&
                        (!compute_message || context_available);
    assign input_fire = in_valid_i && in_ready_o;
    // 同一tag的稳态快路径独立计算，不复用含CAM检索结果的input_fire。
    // 这样能阻止综合器把慢速tag检索网络重新并入计数器写使能。
    assign live_dispatch_fire = in_valid_i && !allocation_pending_q &&
        !allocation_validation_pending_q &&
        output_slot_available &&
        (!compute_message ||
         (stream_context_match && geometry_valid &&
          stream_context_shape_valid));
    // tag切换先只捕获CAM选择结果；几何、形状和last检查在下一周期基于
    // 已寄存的flit完成，避免把所有校验串到分配寄存器的写使能上。
    assign allocation_capture = input_fire && compute_message &&
                                !stream_context_match;
    assign allocation_data_capture = in_valid_i && !allocation_pending_q &&
                                     !allocation_validation_pending_q &&
                                     output_slot_available;
    // 新上下文先在独立验证级检查几何和形状，再由提交级写上下文和输出。
    // 两级期间均暂停输入；捕获周期不占输出槽，因此提交不依赖下游ready。
    assign allocation_validation_fire = allocation_pending_q;
    assign allocation_dispatch_fire = allocation_validation_pending_q;
    assign context_full_o = in_valid_i && compute_message &&
                            !context_match && !context_free;

    // 稳态输出只读取stream cache索引；tag切换首包只写分配暂存级。
    // 两套坐标映射不共享数据多路器，避免CAM结果进入输出flit的D路径。
    always_comb begin
        live_dispatch_flit = input_flit;
        if (activation_message) begin
            live_dispatch_flit.dst_x = input_flit.dst_x;
            live_dispatch_flit.dst_y = input_flit.dst_y +
                context_a_tile_row_q[stream_context_index_q];
        end else if (weight_message) begin
            live_dispatch_flit.dst_x = input_flit.dst_x +
                context_b_tile_column_q[stream_context_index_q];
            live_dispatch_flit.dst_y = input_flit.dst_y;
        end
    end

    always_comb begin
        allocation_commit_flit = allocation_flit_q;
        if (allocation_activation) begin
            allocation_commit_flit.dst_x = allocation_flit_q.dst_x;
            allocation_commit_flit.dst_y = allocation_flit_q.dst_y +
                (allocation_new_context_q ? 4'd0 :
                 context_a_tile_row_q[allocation_context_index_q]);
        end else if (allocation_weight) begin
            allocation_commit_flit.dst_x = allocation_flit_q.dst_x +
                (allocation_new_context_q ? 4'd0 :
                 context_b_tile_column_q[allocation_context_index_q]);
            allocation_commit_flit.dst_y = allocation_flit_q.dst_y;
        end
    end

    assign stream_last_position_error = input_flit.last && compute_message &&
        ((activation_message &&
          ((context_a_local_row_q[stream_context_index_q] != 4'd15) ||
           ({1'b0, context_a_tile_row_q[stream_context_index_q]} + 5'd1 !=
            input_flit.tile_span))) ||
         (weight_message &&
          ((context_b_local_column_q[stream_context_index_q] != 4'd15) ||
           ({1'b0, context_b_tile_column_q[stream_context_index_q]} + 5'd1 !=
            input_flit.tile_span))));

    gemm_root_dispatcher_egress_fifo u_egress_fifo (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .clear_i     (clear_i),
        .in_valid_i  (output_valid_q),
        .in_ready_o  (egress_fifo_in_ready),
        .in_vc_i     (output_vc_q),
        .in_flit_i   (output_flit_q),
        .out_valid_o (out_valid_o),
        .out_ready_i (out_ready_i),
        .out_vc_o    (out_vc_o),
        .out_flit_o  (out_flit_o)
    );
    assign allocation_activation =
        allocation_flit_q.msg_type == tile_noc_pkg::TILE_NOC_MSG_ACTIVATION;
    assign allocation_weight =
        allocation_flit_q.msg_type == tile_noc_pkg::TILE_NOC_MSG_WEIGHT;
    assign allocation_shape_valid = allocation_new_context_q ||
        ((context_anchor_x_q[allocation_context_index_q] ==
          allocation_flit_q.dst_x) &&
         (context_anchor_y_q[allocation_context_index_q] ==
          allocation_flit_q.dst_y) &&
         (context_span_q[allocation_context_index_q] ==
          allocation_flit_q.tile_span));
    assign allocation_dispatch_permitted = allocation_geometry_valid_q &&
                                           allocation_shape_valid;
    assign allocation_last_position_error = allocation_flit_q.last &&
        (allocation_new_context_q ||
         (allocation_activation &&
          ((context_a_local_row_q[allocation_context_index_q] != 4'd15) ||
           ({1'b0, context_a_tile_row_q[allocation_context_index_q]} +
            5'd1 != allocation_flit_q.tile_span))) ||
         (allocation_weight &&
          ((context_b_local_column_q[allocation_context_index_q] != 4'd15) ||
           ({1'b0, context_b_tile_column_q[allocation_context_index_q]} +
            5'd1 != allocation_flit_q.tile_span))));
    assign allocation_commit_fire = allocation_dispatch_fire &&
                                    allocation_dispatch_permitted_q;

    // stream cache数据位不复位，并按负载类型拆成四个本地写使能岛。
    // stream_context_valid_q是唯一可观察有效边界。
    gemm_root_dispatcher_control_inverter u_stream_tag_load_inverter (
        .data_i (allocation_commit_fire),
        .data_o (stream_tag_load_inverted)
    );
    gemm_root_dispatcher_control_inverter u_stream_tag_load_restore (
        .data_i (stream_tag_load_inverted),
        .data_o (stream_tag_load_buffered)
    );
    gemm_root_dispatcher_control_inverter u_stream_index_load_inverter (
        .data_i (allocation_commit_fire),
        .data_o (stream_index_load_inverted)
    );
    gemm_root_dispatcher_control_inverter u_stream_index_load_restore (
        .data_i (stream_index_load_inverted),
        .data_o (stream_index_load_buffered)
    );
    gemm_root_dispatcher_control_inverter u_stream_onehot_load_inverter (
        .data_i (allocation_commit_fire),
        .data_o (stream_onehot_load_inverted)
    );
    gemm_root_dispatcher_control_inverter u_stream_onehot_load_restore (
        .data_i (stream_onehot_load_inverted),
        .data_o (stream_onehot_load_buffered)
    );
    gemm_root_dispatcher_control_inverter u_stream_shape_load_inverter (
        .data_i (allocation_commit_fire),
        .data_o (stream_shape_load_inverted)
    );
    gemm_root_dispatcher_control_inverter u_stream_shape_load_restore (
        .data_i (stream_shape_load_inverted),
        .data_o (stream_shape_load_buffered)
    );

    always_ff @(posedge clk_i) begin
        if (stream_tag_load_buffered) begin
            stream_context_tag_q <= allocation_flit_q.tag;
        end
        if (stream_index_load_buffered) begin
            stream_context_index_q <= allocation_context_index_q;
        end
        if (stream_onehot_load_buffered) begin
            stream_context_onehot_q <=
                ACTIVE_CONTEXTS'(1) << allocation_context_index_q;
        end
        if (stream_shape_load_buffered) begin
            stream_anchor_x_q <= allocation_flit_q.dst_x;
            stream_anchor_y_q <= allocation_flit_q.dst_y;
            stream_span_q <= allocation_flit_q.tile_span;
        end
    end

    // 宽数据寄存器不需要复位。它们与带clear的控制状态分离，避免同步
    // clear被综合成两个160位寄存器组的共同写使能；有效位会屏蔽旧数据。
    always_ff @(posedge clk_i) begin
        if (allocation_data_capture) begin
            allocation_vc_q <= in_vc_i;
        end
        // 只用输出槽状态驱动整个宽寄存器组。槽被占用且下游停顿时保持；
        // 槽可写时即使没有有效输入，写入的无效数据也会被output_valid屏蔽。
        if (output_slot_available) begin
            if (allocation_dispatch_fire) begin
                output_vc_q <= allocation_vc_q;
            end else begin
                output_vc_q <= in_vc_i;
            end
        end
    end

    // 两组160-bit宽寄存器各拆成10个16-bit timing island。本地双反相
    // 缓冲不改变周期或极性，并把单个load网络的叶子扇出限制为16。
    for (genvar data_slice = 0; data_slice < 10;
         data_slice = data_slice + 1) begin : gen_data_slice
        logic allocation_load_inverted;
        logic allocation_load_buffered;
        logic output_load_inverted;
        logic output_load_buffered;

        gemm_root_dispatcher_control_inverter u_allocation_load_inverter (
            .data_i (allocation_data_capture),
            .data_o (allocation_load_inverted)
        );
        gemm_root_dispatcher_control_inverter u_allocation_load_restore (
            .data_i (allocation_load_inverted),
            .data_o (allocation_load_buffered)
        );
        gemm_root_dispatcher_control_inverter u_output_load_inverter (
            .data_i (output_slot_available),
            .data_o (output_load_inverted)
        );
        gemm_root_dispatcher_control_inverter u_output_load_restore (
            .data_i (output_load_inverted),
            .data_o (output_load_buffered)
        );

        always_ff @(posedge clk_i) begin
            if (allocation_load_buffered) begin
                allocation_flit_q[data_slice*16 +: 16] <=
                    input_flit[data_slice*16 +: 16];
            end
            if (output_load_buffered) begin
                if (allocation_dispatch_fire) begin
                    output_flit_q[data_slice*16 +: 16] <=
                        allocation_commit_flit[data_slice*16 +: 16];
                end else begin
                    output_flit_q[data_slice*16 +: 16] <=
                        live_dispatch_flit[data_slice*16 +: 16];
                end
            end
        end
    end

    // 每个上下文使用常量数组索引保存状态。这样连续同一tag的数据包只经过
    // stream_context_index比较，不再让16路CAM优先编码结果穿过可变数组写端口
    // 后才到达行/列计数器。
    for (genvar context_entry = 0; context_entry < ACTIVE_CONTEXTS;
         context_entry = context_entry + 1) begin : gen_context_state
        localparam logic [CONTEXT_INDEX_WIDTH-1:0] CONTEXT_ENTRY_INDEX =
            CONTEXT_INDEX_WIDTH'(context_entry);
        logic release_entry;
        logic allocate_entry;
        logic live_entry;

        assign release_entry = input_fire && release_message &&
                               context_match &&
                               (context_match_index == CONTEXT_ENTRY_INDEX);
        assign allocate_entry = allocation_commit_fire &&
                                (allocation_context_index_q ==
                                 CONTEXT_ENTRY_INDEX);
        assign live_entry = live_dispatch_fire && compute_message &&
                            stream_context_onehot_q[context_entry];

        always_ff @(posedge clk_i) begin
            if (rst_i || clear_i) begin
                context_valid_q[context_entry] <= 1'b0;
            end else begin
                if (release_entry) begin
                    context_valid_q[context_entry] <= 1'b0;
                end
                if (allocate_entry && allocation_new_context_q) begin
                    context_valid_q[context_entry] <= 1'b1;
                end
            end
        end

        // 无效上下文的数据内容无需复位；valid位是其唯一可观察边界。
        always_ff @(posedge clk_i) begin
            if (live_entry && activation_message) begin
                if (context_a_local_row_q[context_entry] == 4'd15) begin
                    context_a_local_row_q[context_entry] <= 4'd0;
                    if ({1'b0, context_a_tile_row_q[context_entry]} + 5'd1 ==
                        input_flit.tile_span) begin
                        context_a_tile_row_q[context_entry] <= 4'd0;
                    end else begin
                        context_a_tile_row_q[context_entry] <=
                            context_a_tile_row_q[context_entry] + 4'd1;
                    end
                end else begin
                    context_a_local_row_q[context_entry] <=
                        context_a_local_row_q[context_entry] + 4'd1;
                end
            end
            if (live_entry && weight_message) begin
                if (context_b_local_column_q[context_entry] == 4'd15) begin
                    context_b_local_column_q[context_entry] <= 4'd0;
                    if ({1'b0, context_b_tile_column_q[context_entry]} +
                        5'd1 == input_flit.tile_span) begin
                        context_b_tile_column_q[context_entry] <= 4'd0;
                    end else begin
                        context_b_tile_column_q[context_entry] <=
                            context_b_tile_column_q[context_entry] + 4'd1;
                    end
                end else begin
                    context_b_local_column_q[context_entry] <=
                        context_b_local_column_q[context_entry] + 4'd1;
                end
            end
            if (allocate_entry) begin
                if (allocation_new_context_q) begin
                    context_tag_q[context_entry] <= allocation_flit_q.tag;
                    context_anchor_x_q[context_entry] <=
                        allocation_flit_q.dst_x;
                    context_anchor_y_q[context_entry] <=
                        allocation_flit_q.dst_y;
                    context_span_q[context_entry] <=
                        allocation_flit_q.tile_span;
                    context_a_tile_row_q[context_entry] <= 4'd0;
                    context_a_local_row_q[context_entry] <=
                        allocation_activation ? 4'd1 : 4'd0;
                    context_b_tile_column_q[context_entry] <= 4'd0;
                    context_b_local_column_q[context_entry] <=
                        allocation_weight ? 4'd1 : 4'd0;
                end else if (allocation_activation) begin
                    if (context_a_local_row_q[context_entry] == 4'd15) begin
                        context_a_local_row_q[context_entry] <= 4'd0;
                        if ({1'b0, context_a_tile_row_q[context_entry]} +
                            5'd1 == allocation_flit_q.tile_span) begin
                            context_a_tile_row_q[context_entry] <= 4'd0;
                        end else begin
                            context_a_tile_row_q[context_entry] <=
                                context_a_tile_row_q[context_entry] + 4'd1;
                        end
                    end else begin
                        context_a_local_row_q[context_entry] <=
                            context_a_local_row_q[context_entry] + 4'd1;
                    end
                end else if (allocation_weight) begin
                    if (context_b_local_column_q[context_entry] == 4'd15) begin
                        context_b_local_column_q[context_entry] <= 4'd0;
                        if ({1'b0, context_b_tile_column_q[context_entry]} +
                            5'd1 == allocation_flit_q.tile_span) begin
                            context_b_tile_column_q[context_entry] <= 4'd0;
                        end else begin
                            context_b_tile_column_q[context_entry] <=
                                context_b_tile_column_q[context_entry] + 4'd1;
                        end
                    end else begin
                        context_b_local_column_q[context_entry] <=
                            context_b_local_column_q[context_entry] + 4'd1;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            output_valid_q <= 1'b0;
            allocation_pending_q <= 1'b0;
            allocation_validation_pending_q <= 1'b0;
            stream_context_valid_q <= 1'b0;
            protocol_error_o <= 1'b0;
        end else begin
            if (output_valid_q && egress_fifo_in_ready) begin
                output_valid_q <= 1'b0;
            end
            if (live_dispatch_fire) begin
                output_valid_q <= 1'b1;
            end
            if (allocation_capture) begin
                allocation_pending_q <= 1'b1;
                allocation_context_index_q <= selected_context_index;
                allocation_new_context_q <= !context_match;
                allocation_geometry_valid_q <= geometry_valid;
            end
            if (allocation_validation_fire) begin
                allocation_pending_q <= 1'b0;
                allocation_validation_pending_q <= 1'b1;
                allocation_dispatch_permitted_q <=
                    allocation_dispatch_permitted;
                allocation_last_position_error_q <=
                    allocation_last_position_error;
            end
            if (allocation_dispatch_fire) begin
                allocation_validation_pending_q <= 1'b0;
                stream_context_valid_q <= 1'b0;
            end
            if (allocation_commit_fire) begin
                output_valid_q <= 1'b1;
                stream_context_valid_q <= 1'b1;
            end
            if (input_fire && compute_message && stream_context_match &&
                (!geometry_valid || !stream_context_shape_valid ||
                 stream_last_position_error)) begin
                protocol_error_o <= 1'b1;
            end
            if (allocation_dispatch_fire &&
                (!allocation_dispatch_permitted_q ||
                 allocation_last_position_error_q)) begin
                protocol_error_o <= 1'b1;
            end
            if (input_fire && release_message && context_match) begin
                if (stream_context_valid_q &&
                    (stream_context_tag_q == input_flit.tag)) begin
                    stream_context_valid_q <= 1'b0;
                end
            end
        end
    end

endmodule

`default_nettype wire
