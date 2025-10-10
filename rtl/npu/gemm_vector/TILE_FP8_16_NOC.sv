`timescale 1ns/1ps
`default_nettype none

module TILE_FP8_16_NOC #(
    parameter bit DAZ = 1'b0,
    parameter bit FTZ = 1'b0,
    parameter logic [3:0] LOCAL_X = 4'd0,
    parameter logic [3:0] LOCAL_Y = 4'd0,
    parameter bit RUNTIME_COORDINATES = 1'b0,
    parameter bit STATIC_WEIGHT_MODE = 1'b0,
    parameter bit EXACT_OUTPUT_MODE = 1'b0
) (
    input  logic                         clk_i,
    input  logic                         rst_i,
    input  logic                         clear_i,
    input  logic                   [3:0] local_x_i,
    input  logic                   [3:0] local_y_i,
    input  logic                         routed_mode_i,
    output logic                         routed_mode_o,

    input  logic                         direct_a_valid_i,
    output logic                         direct_a_ready_o,
    input  logic                 [127:0] direct_a_data_i,
    input  fp8_pkg::fp8_format_e         direct_a_format_i,
    input  fp8_pkg::fp8_rounding_e       direct_a_rounding_i,
    input  logic                   [7:0] direct_a_tag_i,
    input  logic                   [4:0] direct_a_tiles_left_i,
    input  logic                         direct_b_valid_i,
    output logic                         direct_b_ready_o,
    input  logic                 [127:0] direct_b_data_i,
    input  fp8_pkg::fp8_format_e         direct_b_format_i,
    input  logic                   [7:0] direct_b_tag_i,
    input  logic                   [4:0] direct_b_tiles_left_i,

    input  logic                         direct_a_east_ready_i,
    output logic                         direct_a_east_valid_o,
    output logic                 [127:0] direct_a_east_data_o,
    output fp8_pkg::fp8_format_e         direct_a_east_format_o,
    output fp8_pkg::fp8_rounding_e       direct_a_east_rounding_o,
    output logic                   [7:0] direct_a_east_tag_o,
    output logic                   [4:0] direct_a_east_tiles_left_o,
    input  logic                         direct_b_south_ready_i,
    output logic                         direct_b_south_valid_o,
    output logic                 [127:0] direct_b_south_data_o,
    output fp8_pkg::fp8_format_e         direct_b_south_format_o,
    output logic                   [3:0] direct_b_south_column_o,
    output logic                   [7:0] direct_b_south_tag_o,
    output logic                   [4:0] direct_b_south_tiles_left_o,

    input  logic                   [3:0] noc_in_valid_i,
    output logic                   [7:0] noc_in_ready_o,
    input  logic                   [3:0] noc_in_vc_i,
    input  logic                 [639:0] noc_in_flit_i,
    output logic                   [3:0] noc_out_valid_o,
    input  logic                   [3:0] noc_out_ready_i,
    output logic                   [3:0] noc_out_vc_o,
    output logic                 [639:0] noc_out_flit_o,

    input  logic                         noc_tx_valid_i,
    output logic                         noc_tx_ready_o,
    input  logic                         noc_tx_vc_i,
    input  logic                 [159:0] noc_tx_flit_i,
    output logic                         noc_rx_valid_o,
    input  logic                         noc_rx_ready_i,
    output logic                         noc_rx_vc_o,
    output logic                 [159:0] noc_rx_flit_o,

    input  logic                         result_ready_i,
    output logic                         result_valid_o,
    output logic                 [511:0] result_data_o,
    output logic                  [15:0] result_invalid_o,
    input  logic                         exact_result_ready_i,
    output logic                         exact_result_valid_o,
    output logic                [1103:0] exact_result_sum_o,
    output logic                  [31:0] exact_result_special_o,
    output logic                  [31:0] exact_result_zero_sign_o,
    output logic                  [15:0] exact_result_invalid_o,
    output logic                  [31:0] exact_result_rounding_o,
    output logic                         input_pair_issue_o,
    output logic                         weights_loaded_o,
    output logic                         weight_block_loaded_o,
    output logic                         resident_weight_tag_valid_o,
    output logic                   [7:0] resident_weight_tag_o,
    output logic                         tag_protocol_error_o,
    output logic                         output_overflow_o
);

    localparam logic [2:0] PORT_LOCAL = tile_noc_pkg::TILE_NOC_PORT_LOCAL;
    localparam logic [2:0] PORT_NORTH = tile_noc_pkg::TILE_NOC_PORT_NORTH;
    localparam logic [2:0] PORT_EAST = tile_noc_pkg::TILE_NOC_PORT_EAST;
    localparam logic [2:0] PORT_SOUTH = tile_noc_pkg::TILE_NOC_PORT_SOUTH;
    localparam logic [2:0] PORT_WEST = tile_noc_pkg::TILE_NOC_PORT_WEST;
    localparam integer MSG_LSB = 152;
    localparam integer AUX_LSB = 156;

    logic routed_mode_q;
    logic [4:0] router_in_valid;
    logic [9:0] router_in_ready;
    logic [4:0] router_in_vc;
    logic [799:0] router_in_flit;
    logic [4:0] router_out_valid;
    logic [4:0] router_out_ready;
    logic [4:0] router_out_vc;
    logic [799:0] router_out_flit;
    logic local_is_activation;
    logic local_is_weight;
    logic local_is_compute;
    logic local_a_selected;
    logic local_b_selected;
    logic local_last;
    logic local_valid;
    logic local_vc;
    logic [159:0] local_flit;
    logic local_consumer_ready;
    logic local_buffer_push;
    logic local_buffer_pop;
    logic [159:0] local_buffer_flit_q [0:1];
    logic local_buffer_vc_q [0:1];
    logic local_buffer_wr_ptr_q;
    logic local_buffer_rd_ptr_q;
    logic [1:0] local_buffer_count_q;
    logic [1:0] local_buffer_write_enable;
    logic [2:0] local_message_type;
    logic tile_a_valid;
    logic tile_a_ready;
    logic [127:0] tile_a_data;
    fp8_pkg::fp8_format_e tile_a_format;
    fp8_pkg::fp8_rounding_e tile_a_rounding;
    logic tile_b_valid;
    logic tile_b_ready;
    logic [127:0] tile_b_data;
    fp8_pkg::fp8_format_e tile_b_format;
    logic tile_a_east_ready;
    logic tile_a_east_valid;
    logic [127:0] tile_a_east_data;
    fp8_pkg::fp8_format_e tile_a_east_format;
    fp8_pkg::fp8_rounding_e tile_a_east_rounding;
    logic tile_b_south_ready;
    logic tile_b_south_valid;
    logic [127:0] tile_b_south_data;
    fp8_pkg::fp8_format_e tile_b_south_format;
    logic [3:0] tile_b_south_column;
    logic routed_activation_last_q;
    logic routed_weight_last_q;
    logic routed_batch_ready_q;
    logic tile_issue_enable_q;
    logic [5:0] routed_activation_count_q;
    logic [5:0] routed_weight_count_q;
    logic local_activation_accept;
    logic local_weight_accept;
    logic local_activation_accept_q;
    logic local_weight_accept_q;
    logic local_activation_last_accept_q;
    logic local_weight_last_accept_q;
    logic routed_batch_last_issue;
    logic routed_activation_issue_q;
    logic routed_weight_issue_q;
    logic tile_a_issue;
    logic tile_b_issue;
    logic tile_a_accept;
    logic tile_b_accept;
    logic tile_a_accept_q;
    logic tile_b_accept_q;
    logic [12:0] a_route_meta_pending_q;
    logic [12:0] b_route_meta_pending_q;
    logic [12:0] a_route_meta_mem [0:31];
    logic [12:0] b_route_meta_mem [0:31];
    logic [4:0] a_route_meta_wr_ptr_q;
    logic [4:0] a_route_meta_rd_ptr_q;
    logic [4:0] b_route_meta_wr_ptr_q;
    logic [4:0] b_route_meta_rd_ptr_q;
    logic [12:0] a_route_meta_head;
    logic [12:0] b_route_meta_head;
    logic [7:0] a_forward_tag_q;
    logic [4:0] a_forward_tiles_left_q;
    logic [7:0] b_forward_tag_q;
    logic [4:0] b_forward_tiles_left_q;
    logic a_forward_required_q;
    logic b_forward_required_q;
    logic [3:0] b_load_column_q;
    logic [7:0] b_load_tag_q;
    logic b_load_tag_valid_q;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            routed_mode_q <= routed_mode_i;
        end
    end

    // A context may reuse a resident B block across clears, but it must retain
    // the same tag.  Mixed-tag columns and A/B tag mismatches are reported as
    // sticky protocol errors; datapath timing is unchanged and software can
    // quarantine the affected result stream.
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            resident_weight_tag_valid_o <= 1'b0;
            resident_weight_tag_o <= 8'd0;
            tag_protocol_error_o <= 1'b0;
            b_load_column_q <= 4'd0;
            b_load_tag_q <= 8'd0;
            b_load_tag_valid_q <= 1'b0;
        end else if (clear_i) begin
            if (!STATIC_WEIGHT_MODE) begin
                resident_weight_tag_valid_o <= 1'b0;
                resident_weight_tag_o <= 8'd0;
            end
            tag_protocol_error_o <= 1'b0;
            b_load_column_q <= 4'd0;
            b_load_tag_q <= 8'd0;
            b_load_tag_valid_q <= 1'b0;
        end else begin
            if (tile_b_issue) begin
                if (b_load_column_q == 4'd0) begin
                    b_load_tag_q <= b_route_meta_head[12:5];
                    b_load_tag_valid_q <= 1'b1;
                end else if (b_load_tag_valid_q &&
                             (b_route_meta_head[12:5] != b_load_tag_q)) begin
                    tag_protocol_error_o <= 1'b1;
                end
                if (b_load_column_q == 4'd15) begin
                    resident_weight_tag_valid_o <= 1'b1;
                    resident_weight_tag_o <= b_route_meta_head[12:5];
                    b_load_tag_valid_q <= 1'b0;
                end
                b_load_column_q <= b_load_column_q + 4'd1;
            end
            if (tile_a_issue && resident_weight_tag_valid_o &&
                (a_route_meta_head[12:5] != resident_weight_tag_o)) begin
                tag_protocol_error_o <= 1'b1;
            end
        end
    end

    assign routed_mode_o = routed_mode_q;
    assign local_valid = local_buffer_count_q != 2'd0;
    assign local_flit = local_buffer_flit_q[local_buffer_rd_ptr_q];
    assign local_vc = local_buffer_vc_q[local_buffer_rd_ptr_q];
    assign local_message_type = local_flit[MSG_LSB +: 3];
    assign local_last = local_flit[155];
    assign local_is_activation =
        local_message_type == tile_noc_pkg::TILE_NOC_MSG_ACTIVATION;
    assign local_is_weight =
        local_message_type == tile_noc_pkg::TILE_NOC_MSG_WEIGHT;
    assign local_is_compute = local_is_activation || local_is_weight;
    assign local_activation_accept = local_valid && local_consumer_ready &&
                                     routed_mode_q && local_is_activation;
    assign local_weight_accept = local_valid && local_consumer_ready &&
                                 routed_mode_q && local_is_weight;
    assign routed_batch_last_issue = routed_batch_ready_q &&
        ((routed_activation_count_q == 6'd0) ||
         (routed_activation_issue_q &&
          (routed_activation_count_q == 6'd1))) &&
        ((routed_weight_count_q == 6'd0) ||
         (routed_weight_issue_q &&
          (routed_weight_count_q == 6'd1))) &&
        (routed_activation_issue_q || routed_weight_issue_q);
    assign local_buffer_push = router_out_valid[PORT_LOCAL] &&
                               router_out_ready[PORT_LOCAL];
    assign local_buffer_pop = local_valid && local_consumer_ready;
    assign local_buffer_write_enable[0] = local_buffer_push &&
                                          !local_buffer_wr_ptr_q;
    assign local_buffer_write_enable[1] = local_buffer_push &&
                                           local_buffer_wr_ptr_q;

    generate
        for (genvar local_slot = 0; local_slot < 2;
             local_slot = local_slot + 1) begin : gen_local_buffer_slots
            for (genvar local_slice = 0; local_slice < 10;
                 local_slice = local_slice + 1) begin : gen_local_buffer_slices
                tile_router_output_slice #(
                    .WIDTH (16)
                ) u_local_payload_slice (
                    .clk_i  (clk_i),
                    .load_i (local_buffer_write_enable[local_slot]),
                    .data_i (router_out_flit[PORT_LOCAL*160 +
                                              local_slice*16 +: 16]),
                    .data_o (local_buffer_flit_q[local_slot]
                                                [local_slice*16 +: 16])
                );
            end
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            local_buffer_wr_ptr_q <= 1'b0;
            local_buffer_rd_ptr_q <= 1'b0;
            local_buffer_count_q <= 2'd0;
        end else begin
            if (local_buffer_push) begin
                local_buffer_wr_ptr_q <= ~local_buffer_wr_ptr_q;
            end
            if (local_buffer_pop) begin
                local_buffer_rd_ptr_q <= ~local_buffer_rd_ptr_q;
            end
            unique case ({local_buffer_push, local_buffer_pop})
                2'b10: local_buffer_count_q <= local_buffer_count_q + 2'd1;
                2'b01: local_buffer_count_q <= local_buffer_count_q - 2'd1;
                default: local_buffer_count_q <= local_buffer_count_q;
            endcase
        end
    end

    // Payload与VC内容由count/指针丢弃，无需复位；payload已由16位局部使能切片保存。
    always_ff @(posedge clk_i) begin
        if (local_buffer_write_enable[0]) begin
            local_buffer_vc_q[0] <= router_out_vc[PORT_LOCAL];
        end
        if (local_buffer_write_enable[1]) begin
            local_buffer_vc_q[1] <= router_out_vc[PORT_LOCAL];
        end
    end

    // Register local FIFO acceptance before it reaches the batch controller.
    // This preserves the complete-wavefront launch rule without feeding FIFO
    // ready through last detection and counter control in one cycle.
    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            local_activation_accept_q <= 1'b0;
            local_weight_accept_q <= 1'b0;
            local_activation_last_accept_q <= 1'b0;
            local_weight_last_accept_q <= 1'b0;
        end else begin
            local_activation_accept_q <= local_activation_accept;
            local_weight_accept_q <= local_weight_accept;
            local_activation_last_accept_q <= local_activation_accept &&
                                              local_last;
            local_weight_last_accept_q <= local_weight_accept && local_last;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            routed_activation_last_q <= 1'b0;
            routed_weight_last_q <= 1'b0;
            routed_batch_ready_q <= 1'b0;
            tile_issue_enable_q <= STATIC_WEIGHT_MODE || !routed_mode_i;
            routed_activation_count_q <= 6'd0;
            routed_weight_count_q <= 6'd0;
            routed_activation_issue_q <= 1'b0;
            routed_weight_issue_q <= 1'b0;
        end else begin
            routed_activation_issue_q <= tile_a_issue && routed_mode_q;
            routed_weight_issue_q <= tile_b_issue && routed_mode_q;
            if (local_activation_accept_q) begin
                routed_activation_count_q <= routed_activation_count_q + 6'd1;
                if (local_activation_last_accept_q) begin
                    routed_activation_last_q <= 1'b1;
                end
            end
            if (local_weight_accept_q) begin
                routed_weight_count_q <= routed_weight_count_q + 6'd1;
                if (local_weight_last_accept_q) begin
                    routed_weight_last_q <= 1'b1;
                end
            end
            if (STATIC_WEIGHT_MODE) begin
                routed_batch_ready_q <= 1'b0;
                tile_issue_enable_q <= 1'b1;
                if (routed_activation_issue_q &&
                    (routed_activation_count_q != 6'd0)) begin
                    routed_activation_count_q <=
                        routed_activation_count_q - 6'd1;
                end
                if (routed_weight_issue_q &&
                    (routed_weight_count_q != 6'd0)) begin
                    routed_weight_count_q <= routed_weight_count_q - 6'd1;
                end
                if (routed_activation_issue_q &&
                    (routed_activation_count_q == 6'd1)) begin
                    routed_activation_last_q <= 1'b0;
                end
                if (routed_weight_issue_q &&
                    (routed_weight_count_q == 6'd1)) begin
                    routed_weight_last_q <= 1'b0;
                end
            end else begin
                if ((routed_activation_last_q ||
                     local_activation_last_accept_q) &&
                    (routed_weight_last_q ||
                     local_weight_last_accept_q)) begin
                    routed_batch_ready_q <= 1'b1;
                    tile_issue_enable_q <= 1'b1;
                end
                if (routed_batch_ready_q && routed_activation_issue_q) begin
                    routed_activation_count_q <=
                        routed_activation_count_q - 6'd1;
                end
                if (routed_batch_ready_q && routed_weight_issue_q) begin
                    routed_weight_count_q <= routed_weight_count_q - 6'd1;
                end
                if (routed_batch_last_issue) begin
                    routed_activation_last_q <= 1'b0;
                    routed_weight_last_q <= 1'b0;
                    routed_batch_ready_q <= 1'b0;
                    routed_activation_count_q <= 6'd0;
                    routed_weight_count_q <= 6'd0;
                    tile_issue_enable_q <= !routed_mode_q;
                end
            end
        end
    end

    // NoC只把每行A/每列B送到方阵边界Tile；边界Tile接收后，
    // 后续Tile经direct链路传播。同一通道同时到达时，给NoC本地flit
    // 固定优先级，ready精确反压未被选中的direct输入。
    assign local_a_selected = local_valid && local_is_activation &&
                              !routed_batch_ready_q;
    assign local_b_selected = local_valid && local_is_weight &&
                              !routed_batch_ready_q;
    assign tile_a_valid = local_a_selected || direct_a_valid_i;
    assign tile_a_data = local_a_selected ? local_flit[127:0] : direct_a_data_i;
    assign tile_a_format = local_a_selected ?
                           fp8_pkg::fp8_format_e'(local_flit[AUX_LSB]) :
                           direct_a_format_i;
    assign tile_a_rounding = local_a_selected ?
                             fp8_pkg::fp8_rounding_e'(
                                 local_flit[AUX_LSB + 1 +: 2]) :
                             direct_a_rounding_i;
    assign tile_b_valid = local_b_selected || direct_b_valid_i;
    assign tile_b_data = local_b_selected ? local_flit[127:0] : direct_b_data_i;
    assign tile_b_format = local_b_selected ?
                           fp8_pkg::fp8_format_e'(local_flit[AUX_LSB]) :
                           direct_b_format_i;

    assign tile_a_accept = tile_a_valid && tile_a_ready;
    assign tile_b_accept = tile_b_valid && tile_b_ready;
    assign a_route_meta_head = tile_a_accept_q &&
        (a_route_meta_rd_ptr_q == a_route_meta_wr_ptr_q) ?
        a_route_meta_pending_q : a_route_meta_mem[a_route_meta_rd_ptr_q];
    assign b_route_meta_head = tile_b_accept_q &&
        (b_route_meta_rd_ptr_q == b_route_meta_wr_ptr_q) ?
        b_route_meta_pending_q : b_route_meta_mem[b_route_meta_rd_ptr_q];

    assign direct_a_ready_o = !local_a_selected && tile_a_ready;
    assign direct_b_ready_o = !local_b_selected && tile_b_ready;
    assign tile_a_east_ready = !a_forward_required_q || direct_a_east_ready_i;
    assign tile_b_south_ready = !b_forward_required_q || direct_b_south_ready_i;
    assign direct_a_east_valid_o = tile_a_east_valid && a_forward_required_q;
    assign direct_a_east_data_o = tile_a_east_data;
    assign direct_a_east_format_o = tile_a_east_format;
    assign direct_a_east_rounding_o = tile_a_east_rounding;
    assign direct_a_east_tag_o = a_forward_tag_q;
    assign direct_a_east_tiles_left_o =
        (a_forward_tiles_left_q > 5'd1) ?
        (a_forward_tiles_left_q - 5'd1) : 5'd0;
    assign direct_b_south_valid_o = tile_b_south_valid && b_forward_required_q;
    assign direct_b_south_data_o = tile_b_south_data;
    assign direct_b_south_format_o = tile_b_south_format;
    assign direct_b_south_column_o = tile_b_south_column;
    assign direct_b_south_tag_o = b_forward_tag_q;
    assign direct_b_south_tiles_left_o =
        (b_forward_tiles_left_q > 5'd1) ?
        (b_forward_tiles_left_q - 5'd1) : 5'd0;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            a_route_meta_wr_ptr_q <= 5'd0;
            a_route_meta_rd_ptr_q <= 5'd0;
            b_route_meta_wr_ptr_q <= 5'd0;
            b_route_meta_rd_ptr_q <= 5'd0;
            a_forward_tag_q <= 8'd0;
            a_forward_tiles_left_q <= 5'd0;
            b_forward_tag_q <= 8'd0;
            b_forward_tiles_left_q <= 5'd0;
            a_forward_required_q <= 1'b0;
            b_forward_required_q <= 1'b0;
        end else begin
            if (tile_a_accept_q) begin
                a_route_meta_wr_ptr_q <= a_route_meta_wr_ptr_q + 5'd1;
            end
            if (tile_b_accept_q) begin
                b_route_meta_wr_ptr_q <= b_route_meta_wr_ptr_q + 5'd1;
            end
            if (tile_a_issue) begin
                a_route_meta_rd_ptr_q <= a_route_meta_rd_ptr_q + 5'd1;
                a_forward_tag_q <= a_route_meta_head[12:5];
                a_forward_tiles_left_q <= a_route_meta_head[4:0];
                a_forward_required_q <= a_route_meta_head[4:0] > 5'd1;
            end
            if (tile_b_issue) begin
                b_route_meta_rd_ptr_q <= b_route_meta_rd_ptr_q + 5'd1;
                b_forward_tag_q <= b_route_meta_head[12:5];
                b_forward_tiles_left_q <= b_route_meta_head[4:0];
                b_forward_required_q <= b_route_meta_head[4:0] > 5'd1;
            end
        end
    end

    // Pipeline accepted-route metadata independently of the payload SRAM.  The
    // head bypass above covers the one-entry case where payload issue follows
    // acceptance on the immediately next cycle.
    always_ff @(posedge clk_i) begin
        if (tile_a_accept) begin
            a_route_meta_pending_q <= local_a_selected ?
                {local_flit[135:128], local_flit[148:144]} :
                {direct_a_tag_i, direct_a_tiles_left_i};
        end
        if (tile_b_accept) begin
            b_route_meta_pending_q <= local_b_selected ?
                {local_flit[135:128], local_flit[148:144]} :
                {direct_b_tag_i, direct_b_tiles_left_i};
        end
        if (rst_i || clear_i) begin
            tile_a_accept_q <= 1'b0;
            tile_b_accept_q <= 1'b0;
        end else begin
            tile_a_accept_q <= tile_a_accept;
            tile_b_accept_q <= tile_b_accept;
        end
    end

    always_ff @(posedge clk_i) begin
        if (tile_a_accept_q) begin
            a_route_meta_mem[a_route_meta_wr_ptr_q] <= a_route_meta_pending_q;
        end
        if (tile_b_accept_q) begin
            b_route_meta_mem[b_route_meta_wr_ptr_q] <= b_route_meta_pending_q;
        end
    end

    assign local_consumer_ready =
        local_is_activation ?
            (tile_a_ready && !routed_batch_ready_q) :
        local_is_weight ?
            (tile_b_ready && !routed_batch_ready_q) : noc_rx_ready_i;
    assign router_out_ready[PORT_LOCAL] = local_buffer_count_q != 2'd2;
    assign noc_rx_valid_o = local_valid && !local_is_compute;
    assign noc_rx_vc_o = local_vc;
    assign noc_rx_flit_o = local_flit;

    assign router_in_valid[PORT_LOCAL] = noc_tx_valid_i;
    assign router_in_vc[PORT_LOCAL] = noc_tx_vc_i;
    assign router_in_flit[PORT_LOCAL*160 +: 160] = noc_tx_flit_i;
    assign noc_tx_ready_o = noc_tx_vc_i ?
                            router_in_ready[PORT_LOCAL*2 + 1] :
                            router_in_ready[PORT_LOCAL*2];

    assign router_in_valid[PORT_NORTH] = noc_in_valid_i[0];
    assign router_in_valid[PORT_EAST] = noc_in_valid_i[1];
    assign router_in_valid[PORT_SOUTH] = noc_in_valid_i[2];
    assign router_in_valid[PORT_WEST] = noc_in_valid_i[3];
    assign router_in_vc[PORT_NORTH] = noc_in_vc_i[0];
    assign router_in_vc[PORT_EAST] = noc_in_vc_i[1];
    assign router_in_vc[PORT_SOUTH] = noc_in_vc_i[2];
    assign router_in_vc[PORT_WEST] = noc_in_vc_i[3];
    assign router_in_flit[PORT_NORTH*160 +: 160] = noc_in_flit_i[0*160 +: 160];
    assign router_in_flit[PORT_EAST*160 +: 160] = noc_in_flit_i[1*160 +: 160];
    assign router_in_flit[PORT_SOUTH*160 +: 160] = noc_in_flit_i[2*160 +: 160];
    assign router_in_flit[PORT_WEST*160 +: 160] = noc_in_flit_i[3*160 +: 160];
    assign noc_in_ready_o[0*2 +: 2] = router_in_ready[PORT_NORTH*2 +: 2];
    assign noc_in_ready_o[1*2 +: 2] = router_in_ready[PORT_EAST*2 +: 2];
    assign noc_in_ready_o[2*2 +: 2] = router_in_ready[PORT_SOUTH*2 +: 2];
    assign noc_in_ready_o[3*2 +: 2] = router_in_ready[PORT_WEST*2 +: 2];

    assign noc_out_valid_o[0] = router_out_valid[PORT_NORTH];
    assign noc_out_valid_o[1] = router_out_valid[PORT_EAST];
    assign noc_out_valid_o[2] = router_out_valid[PORT_SOUTH];
    assign noc_out_valid_o[3] = router_out_valid[PORT_WEST];
    assign noc_out_vc_o[0] = router_out_vc[PORT_NORTH];
    assign noc_out_vc_o[1] = router_out_vc[PORT_EAST];
    assign noc_out_vc_o[2] = router_out_vc[PORT_SOUTH];
    assign noc_out_vc_o[3] = router_out_vc[PORT_WEST];
    assign noc_out_flit_o[0*160 +: 160] = router_out_flit[PORT_NORTH*160 +: 160];
    assign noc_out_flit_o[1*160 +: 160] = router_out_flit[PORT_EAST*160 +: 160];
    assign noc_out_flit_o[2*160 +: 160] = router_out_flit[PORT_SOUTH*160 +: 160];
    assign noc_out_flit_o[3*160 +: 160] = router_out_flit[PORT_WEST*160 +: 160];
    assign router_out_ready[PORT_NORTH] = noc_out_ready_i[0];
    assign router_out_ready[PORT_EAST] = noc_out_ready_i[1];
    assign router_out_ready[PORT_SOUTH] = noc_out_ready_i[2];
    assign router_out_ready[PORT_WEST] = noc_out_ready_i[3];

    tile_router #(
        .LOCAL_X (LOCAL_X),
        .LOCAL_Y (LOCAL_Y),
        .RUNTIME_COORDINATES (RUNTIME_COORDINATES)
    ) u_router (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .clear_i     (clear_i),
        .local_x_i   (local_x_i),
        .local_y_i   (local_y_i),
        .in_valid_i  (router_in_valid),
        .in_ready_o  (router_in_ready),
        .in_vc_i     (router_in_vc),
        .in_flit_i   (router_in_flit),
        .out_valid_o (router_out_valid),
        .out_ready_i (router_out_ready),
        .out_vc_o    (router_out_vc),
        .out_flit_o  (router_out_flit)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    TILE_FP8_16_FIFO #(
        .DAZ (DAZ),
        .FTZ (FTZ),
        .STATIC_WEIGHT_MODE (STATIC_WEIGHT_MODE),
        .EXACT_OUTPUT_MODE (EXACT_OUTPUT_MODE)
    ) u_tile (
        .clk_i                    (clk_i),
        .rst_i                    (rst_i),
        .clear_i                  (clear_i),
        .input_issue_enable_i     (tile_issue_enable_q),
        .a_valid_i                (tile_a_valid),
        .a_ready_o                (tile_a_ready),
        .a_data_i                 (tile_a_data),
        .a_format_i               (tile_a_format),
        .rounding_i               (tile_a_rounding),
        .b_valid_i                (tile_b_valid),
        .b_ready_o                (tile_b_ready),
        .b_data_i                 (tile_b_data),
        .b_format_i               (tile_b_format),
        .a_east_ready_i           (tile_a_east_ready),
        .a_east_valid_o           (tile_a_east_valid),
        .a_east_data_o            (tile_a_east_data),
        .a_east_format_o          (tile_a_east_format),
        .a_east_rounding_o        (tile_a_east_rounding),
        .b_south_ready_i          (tile_b_south_ready),
        .b_south_valid_o          (tile_b_south_valid),
        .b_south_data_o           (tile_b_south_data),
        .b_south_format_o         (tile_b_south_format),
        .b_south_column_o         (tile_b_south_column),
        .result_ready_i           (result_ready_i),
        .result_valid_o           (result_valid_o),
        .result_data_o            (result_data_o),
        .result_invalid_o         (result_invalid_o),
        .exact_result_ready_i     (exact_result_ready_i),
        .exact_result_valid_o     (exact_result_valid_o),
        .exact_result_sum_o       (exact_result_sum_o),
        .exact_result_special_o   (exact_result_special_o),
        .exact_result_zero_sign_o (exact_result_zero_sign_o),
        .exact_result_invalid_o   (exact_result_invalid_o),
        .exact_result_rounding_o  (exact_result_rounding_o),
        .exact_result_level_o     (),
        .input_pair_valid_o       (),
        .input_pair_issue_o       (input_pair_issue_o),
        .input_a_issue_o          (tile_a_issue),
        .input_b_issue_o          (tile_b_issue),
        .weights_loaded_o         (weights_loaded_o),
        .weight_block_loaded_o    (weight_block_loaded_o),
        .input_a_full_o           (),
        .input_a_empty_o          (),
        .input_a_level_o          (),
        .input_b_full_o           (),
        .input_b_empty_o          (),
        .input_b_level_o          (),
        .result_lane_full_o       (),
        .result_lane_empty_o      (),
        .result_lane_level_o      (),
        .output_overflow_o        (output_overflow_o),
        .act_right_valid_o        (),
        .act_right_data_o         (),
        .act_right_format_o       ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

endmodule

`default_nettype wire
