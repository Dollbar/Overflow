`timescale 1ns/1ps
`default_nettype none

module tile_router #(
    parameter logic [3:0] LOCAL_X = 4'd0,
    parameter logic [3:0] LOCAL_Y = 4'd0,
    parameter bit RUNTIME_COORDINATES = 1'b0
) (
    input  logic                                           clk_i,
    input  logic                                           rst_i,
    input  logic                                           clear_i,
    input  logic [tile_noc_pkg::TILE_NOC_COORD_WIDTH-1:0] local_x_i,
    input  logic [tile_noc_pkg::TILE_NOC_COORD_WIDTH-1:0] local_y_i,
    input  logic [tile_noc_pkg::TILE_NOC_PORT_COUNT-1:0]  in_valid_i,
    output logic [tile_noc_pkg::TILE_NOC_PORT_COUNT*
                  tile_noc_pkg::TILE_NOC_VC_COUNT-1:0]    in_ready_o,
    input  logic [tile_noc_pkg::TILE_NOC_PORT_COUNT-1:0]  in_vc_i,
    input  logic [tile_noc_pkg::TILE_NOC_PORT_COUNT*
                  tile_noc_pkg::TILE_NOC_FLIT_WIDTH-1:0]  in_flit_i,
    output logic [tile_noc_pkg::TILE_NOC_PORT_COUNT-1:0]  out_valid_o,
    input  logic [tile_noc_pkg::TILE_NOC_PORT_COUNT-1:0]  out_ready_i,
    output logic [tile_noc_pkg::TILE_NOC_PORT_COUNT-1:0]  out_vc_o,
    output logic [tile_noc_pkg::TILE_NOC_PORT_COUNT*
                  tile_noc_pkg::TILE_NOC_FLIT_WIDTH-1:0]  out_flit_o
);

    localparam integer PORT_COUNT = tile_noc_pkg::TILE_NOC_PORT_COUNT;
    localparam integer VC_COUNT = tile_noc_pkg::TILE_NOC_VC_COUNT;
    localparam integer FLIT_WIDTH = tile_noc_pkg::TILE_NOC_FLIT_WIDTH;
    localparam integer LANE_COUNT = PORT_COUNT * VC_COUNT;
    localparam integer DST_X_LSB = 136;
    localparam integer DST_Y_LSB = 140;
    localparam integer COORD_WIDTH = tile_noc_pkg::TILE_NOC_COORD_WIDTH;
    localparam logic [2:0] PORT_LOCAL = tile_noc_pkg::TILE_NOC_PORT_LOCAL;
    localparam logic [2:0] PORT_NORTH = tile_noc_pkg::TILE_NOC_PORT_NORTH;
    localparam logic [2:0] PORT_EAST = tile_noc_pkg::TILE_NOC_PORT_EAST;
    localparam logic [2:0] PORT_SOUTH = tile_noc_pkg::TILE_NOC_PORT_SOUTH;
    localparam logic [2:0] PORT_WEST = tile_noc_pkg::TILE_NOC_PORT_WEST;

    logic [FLIT_WIDTH-1:0] input_head_q [0:LANE_COUNT-1];
    logic [1:0] input_count_q [0:LANE_COUNT-1];
    logic input_read_ptr_q [0:LANE_COUNT-1];
    logic input_write_ptr_q [0:LANE_COUNT-1];
    logic [2:0] route_head_q [0:LANE_COUNT-1];
    logic [2:0] route_tail_q [0:LANE_COUNT-1];
    logic [2:0] route_port [0:LANE_COUNT-1];
    logic lane_enqueue_request [0:LANE_COUNT-1];
    logic lane_enqueue [0:LANE_COUNT-1];
    logic lane_dequeue [0:LANE_COUNT-1];
    logic lane_reserved [0:LANE_COUNT-1];
    logic [FLIT_WIDTH-1:0] lane_enqueue_flit [0:LANE_COUNT-1];
    logic [2:0] lane_enqueue_route [0:LANE_COUNT-1];

    logic output_valid_q [0:PORT_COUNT-1];
    logic output_vc_q [0:PORT_COUNT-1];
    logic [FLIT_WIDTH-1:0] output_flit_q [0:PORT_COUNT-1];
    logic [3:0] round_robin_q [0:PORT_COUNT-1];
    logic grant_valid [0:PORT_COUNT-1];
    logic [3:0] grant_lane [0:PORT_COUNT-1];
    logic [LANE_COUNT-1:0] request_vector [0:PORT_COUNT-1];
    logic [LANE_COUNT-1:0] priority_mask [0:PORT_COUNT-1];
    logic [LANE_COUNT-1:0] masked_request [0:PORT_COUNT-1];
    logic [LANE_COUNT-1:0] selected_request [0:PORT_COUNT-1];
    logic [LANE_COUNT-1:0] grant_onehot [0:PORT_COUNT-1];
    logic [FLIT_WIDTH-1:0] grant_flit [0:PORT_COUNT-1];
    logic grant_vc [0:PORT_COUNT-1];
    logic output_can_load [0:PORT_COUNT-1];
    logic output_payload_load [0:PORT_COUNT-1];
    logic selection_valid_q [0:PORT_COUNT-1];
    logic [LANE_COUNT-1:0] selection_onehot_q [0:PORT_COUNT-1];
    logic [3:0] selection_lane_q [0:PORT_COUNT-1];
    logic selection_advance [0:PORT_COUNT-1];
    logic selection_can_load [0:PORT_COUNT-1];
    logic [COORD_WIDTH-1:0] local_x;
    logic [COORD_WIDTH-1:0] local_y;
    logic lane_control_flush;
    logic selection_control_flush;
    logic output_control_flush;

    integer sequential_lane_index;
    integer sequential_selection_index;
    integer sequential_output_index;

    assign local_x = RUNTIME_COORDINATES ? local_x_i : LOCAL_X;
    assign local_y = RUNTIME_COORDINATES ? local_y_i : LOCAL_Y;

    generate
        (* keep = "true", dont_touch = "true" *)
        tile_flush_buffer #(
            .BUFFER_ID (100)
        ) u_lane_control_flush_buffer (
            .rst_i   (rst_i),
            .clear_i (clear_i),
            .flush_o (lane_control_flush)
        );

        (* keep = "true", dont_touch = "true" *)
        tile_flush_buffer #(
            .BUFFER_ID (101)
        ) u_selection_control_flush_buffer (
            .rst_i   (rst_i),
            .clear_i (clear_i),
            .flush_o (selection_control_flush)
        );

        (* keep = "true", dont_touch = "true" *)
        tile_flush_buffer #(
            .BUFFER_ID (102)
        ) u_output_control_flush_buffer (
            .rst_i   (rst_i),
            .clear_i (clear_i),
            .flush_o (output_control_flush)
        );
    endgenerate

    // 参数坐标用于独立Router；端口坐标用于大阵列共享同一份模块实现。
    /* verilator lint_off UNSIGNED */
    /* verilator lint_off CMPCONST */
    function automatic logic [2:0] route_for_coordinates(
        input logic [COORD_WIDTH-1:0] destination_x,
        input logic [COORD_WIDTH-1:0] destination_y
    );
        begin
            if (destination_x > local_x) begin
                route_for_coordinates = PORT_EAST;
            end else if (destination_x < local_x) begin
                route_for_coordinates = PORT_WEST;
            end else if (destination_y > local_y) begin
                route_for_coordinates = PORT_SOUTH;
            end else if (destination_y < local_y) begin
                route_for_coordinates = PORT_NORTH;
            end else begin
                route_for_coordinates = PORT_LOCAL;
            end
        end
    endfunction
    /* verilator lint_on CMPCONST */
    /* verilator lint_on UNSIGNED */

    /* verilator lint_off UNSIGNED */
    always_comb begin
        for (integer route_lane_index = 0; route_lane_index < LANE_COUNT;
             route_lane_index = route_lane_index + 1) begin
            route_port[route_lane_index] = route_head_q[route_lane_index];
        end
    end
    /* verilator lint_on UNSIGNED */

    always_comb begin
        in_ready_o = '0;
        for (integer ready_port_index = 0; ready_port_index < PORT_COUNT;
             ready_port_index = ready_port_index + 1) begin
            for (integer ready_vc_index = 0; ready_vc_index < VC_COUNT;
                 ready_vc_index = ready_vc_index + 1) begin
                in_ready_o[ready_port_index*VC_COUNT + ready_vc_index] =
                    (input_count_q[ready_port_index*VC_COUNT + ready_vc_index] < 2'd2);
            end
        end
    end

    always_comb begin
        for (integer enqueue_lane_index = 0; enqueue_lane_index < LANE_COUNT;
             enqueue_lane_index = enqueue_lane_index + 1) begin
            lane_enqueue_request[enqueue_lane_index] = 1'b0;
            lane_enqueue[enqueue_lane_index] = 1'b0;
            lane_enqueue_flit[enqueue_lane_index] = '0;
            lane_enqueue_route[enqueue_lane_index] = PORT_LOCAL;
        end
        for (integer enqueue_port_index = 0; enqueue_port_index < PORT_COUNT;
             enqueue_port_index = enqueue_port_index + 1) begin
            for (integer enqueue_vc_index = 0; enqueue_vc_index < VC_COUNT;
                 enqueue_vc_index = enqueue_vc_index + 1) begin
                lane_enqueue_request[enqueue_port_index*VC_COUNT + enqueue_vc_index] =
                    in_valid_i[enqueue_port_index] &&
                    (in_vc_i[enqueue_port_index] == enqueue_vc_index[0]);
                lane_enqueue[enqueue_port_index*VC_COUNT + enqueue_vc_index] =
                    lane_enqueue_request[enqueue_port_index*VC_COUNT + enqueue_vc_index] &&
                    in_ready_o[enqueue_port_index*VC_COUNT + enqueue_vc_index];
                lane_enqueue_flit[enqueue_port_index*VC_COUNT + enqueue_vc_index] =
                    in_flit_i[enqueue_port_index*FLIT_WIDTH +: FLIT_WIDTH];
                lane_enqueue_route[enqueue_port_index*VC_COUNT + enqueue_vc_index] =
                    route_for_coordinates(
                        in_flit_i[enqueue_port_index*FLIT_WIDTH + DST_X_LSB +: COORD_WIDTH],
                        in_flit_i[enqueue_port_index*FLIT_WIDTH + DST_Y_LSB +: COORD_WIDTH]
                    );
            end
        end
    end

    always_comb begin
        for (integer dequeue_lane_index = 0; dequeue_lane_index < LANE_COUNT;
             dequeue_lane_index = dequeue_lane_index + 1) begin
            lane_dequeue[dequeue_lane_index] = 1'b0;
            lane_reserved[dequeue_lane_index] = 1'b0;
        end
        for (integer dequeue_output_index = 0; dequeue_output_index < PORT_COUNT;
             dequeue_output_index = dequeue_output_index + 1) begin
            output_can_load[dequeue_output_index] =
                !output_valid_q[dequeue_output_index] || out_ready_i[dequeue_output_index];
            selection_advance[dequeue_output_index] =
                selection_valid_q[dequeue_output_index] &&
                output_can_load[dequeue_output_index];
            selection_can_load[dequeue_output_index] =
                !selection_valid_q[dequeue_output_index] ||
                selection_advance[dequeue_output_index];
            output_payload_load[dequeue_output_index] =
                selection_advance[dequeue_output_index];
            for (integer selected_lane_index = 0; selected_lane_index < LANE_COUNT;
                 selected_lane_index = selected_lane_index + 1) begin
                lane_reserved[selected_lane_index] = lane_reserved[selected_lane_index] |
                    (selection_valid_q[dequeue_output_index] &&
                     selection_onehot_q[dequeue_output_index][selected_lane_index]);
                lane_dequeue[selected_lane_index] = lane_dequeue[selected_lane_index] |
                    (selection_advance[dequeue_output_index] &&
                     selection_onehot_q[dequeue_output_index][selected_lane_index]);
            end
        end
        for (integer alloc_output_index = 0; alloc_output_index < PORT_COUNT;
             alloc_output_index = alloc_output_index + 1) begin
            request_vector[alloc_output_index] = '0;
            for (integer request_lane_index = 0; request_lane_index < LANE_COUNT;
                 request_lane_index = request_lane_index + 1) begin
                request_vector[alloc_output_index][request_lane_index] =
                    selection_can_load[alloc_output_index] &&
                    !lane_reserved[request_lane_index] &&
                    (input_count_q[request_lane_index] != 2'd0) &&
                    (route_port[request_lane_index] == alloc_output_index[2:0]);
            end
            priority_mask[alloc_output_index] =
                {LANE_COUNT{1'b1}} << round_robin_q[alloc_output_index];
            masked_request[alloc_output_index] =
                request_vector[alloc_output_index] & priority_mask[alloc_output_index];
            selected_request[alloc_output_index] =
                (|masked_request[alloc_output_index]) ?
                masked_request[alloc_output_index] : request_vector[alloc_output_index];
            grant_onehot[alloc_output_index] = selected_request[alloc_output_index] &
                (~selected_request[alloc_output_index] + 10'd1);
            grant_valid[alloc_output_index] = |grant_onehot[alloc_output_index];
            grant_lane[alloc_output_index] = 4'd0;
            unique case (grant_onehot[alloc_output_index])
                10'b0000000001: grant_lane[alloc_output_index] = 4'd0;
                10'b0000000010: grant_lane[alloc_output_index] = 4'd1;
                10'b0000000100: grant_lane[alloc_output_index] = 4'd2;
                10'b0000001000: grant_lane[alloc_output_index] = 4'd3;
                10'b0000010000: grant_lane[alloc_output_index] = 4'd4;
                10'b0000100000: grant_lane[alloc_output_index] = 4'd5;
                10'b0001000000: grant_lane[alloc_output_index] = 4'd6;
                10'b0010000000: grant_lane[alloc_output_index] = 4'd7;
                10'b0100000000: grant_lane[alloc_output_index] = 4'd8;
                10'b1000000000: grant_lane[alloc_output_index] = 4'd9;
                default: grant_lane[alloc_output_index] = 4'd0;
            endcase
            grant_flit[alloc_output_index] = '0;
            grant_vc[alloc_output_index] = 1'b0;
            for (integer mux_lane_index = 0; mux_lane_index < LANE_COUNT;
                 mux_lane_index = mux_lane_index + 1) begin
                grant_flit[alloc_output_index] = grant_flit[alloc_output_index] |
                    ({FLIT_WIDTH{selection_onehot_q[alloc_output_index][mux_lane_index]}} &
                     input_head_q[mux_lane_index]);
                grant_vc[alloc_output_index] = grant_vc[alloc_output_index] |
                    (selection_onehot_q[alloc_output_index][mux_lane_index] &
                     mux_lane_index[0]);
            end
        end
    end

    generate
        for (genvar input_slice_lane = 0; input_slice_lane < LANE_COUNT;
             input_slice_lane = input_slice_lane + 1) begin : gen_input_slice_lanes
            for (genvar input_slice_index = 0; input_slice_index < FLIT_WIDTH/16;
                 input_slice_index = input_slice_index + 1) begin : gen_input_slices
                tile_router_input_slice #(
                    .WIDTH (16)
                ) u_input_slice (
                    .clk_i          (clk_i),
                    .enqueue_i      (lane_enqueue[input_slice_lane]),
                    .write_select_i (input_write_ptr_q[input_slice_lane]),
                    .read_select_i  (input_read_ptr_q[input_slice_lane]),
                    .enqueue_data_i (lane_enqueue_flit[input_slice_lane]
                                     [input_slice_index*16 +: 16]),
                    .head_data_o    (input_head_q[input_slice_lane]
                                     [input_slice_index*16 +: 16])
                );
            end
        end

        for (genvar output_slice_port = 0; output_slice_port < PORT_COUNT;
             output_slice_port = output_slice_port + 1) begin : gen_output_slice_ports
            for (genvar output_slice_index = 0; output_slice_index < FLIT_WIDTH/16;
                 output_slice_index = output_slice_index + 1) begin : gen_output_slices
                tile_router_output_slice #(
                    .WIDTH (16)
                ) u_output_slice (
                    .clk_i  (clk_i),
                    .load_i (output_payload_load[output_slice_port]),
                    .data_i (grant_flit[output_slice_port][output_slice_index*16 +: 16]),
                    .data_o (output_flit_q[output_slice_port][output_slice_index*16 +: 16])
                );
            end
        end
    endgenerate

    always_comb begin
        out_valid_o = '0;
        out_vc_o = '0;
        out_flit_o = '0;
        for (integer flatten_output_index = 0; flatten_output_index < PORT_COUNT;
             flatten_output_index = flatten_output_index + 1) begin
            out_valid_o[flatten_output_index] = output_valid_q[flatten_output_index];
            out_vc_o[flatten_output_index] = output_vc_q[flatten_output_index];
            out_flit_o[flatten_output_index*FLIT_WIDTH +: FLIT_WIDTH] =
                output_flit_q[flatten_output_index];
        end
    end

    always_ff @(posedge clk_i) begin
        if (lane_control_flush) begin
            for (sequential_lane_index = 0; sequential_lane_index < LANE_COUNT;
                 sequential_lane_index = sequential_lane_index + 1) begin
                input_count_q[sequential_lane_index] <= 2'd0;
                input_read_ptr_q[sequential_lane_index] <= 1'b0;
                input_write_ptr_q[sequential_lane_index] <= 1'b0;
            end
        end else begin
            for (sequential_lane_index = 0; sequential_lane_index < LANE_COUNT;
                 sequential_lane_index = sequential_lane_index + 1) begin
                unique case ({lane_enqueue[sequential_lane_index],
                              lane_dequeue[sequential_lane_index]})
                    2'b10: begin
                        input_count_q[sequential_lane_index] <=
                            input_count_q[sequential_lane_index] + 2'd1;
                        if (input_count_q[sequential_lane_index] == 2'd0) begin
                            route_head_q[sequential_lane_index] <=
                                lane_enqueue_route[sequential_lane_index];
                        end else begin
                            route_tail_q[sequential_lane_index] <=
                                lane_enqueue_route[sequential_lane_index];
                        end
                    end
                    2'b01: begin
                        input_count_q[sequential_lane_index] <=
                            input_count_q[sequential_lane_index] - 2'd1;
                        if (input_count_q[sequential_lane_index] == 2'd2) begin
                            route_head_q[sequential_lane_index] <=
                                route_tail_q[sequential_lane_index];
                        end
                    end
                    2'b11: begin
                        input_count_q[sequential_lane_index] <=
                            input_count_q[sequential_lane_index];
                        if (input_count_q[sequential_lane_index] == 2'd1) begin
                            route_head_q[sequential_lane_index] <=
                                lane_enqueue_route[sequential_lane_index];
                        end else begin
                            route_head_q[sequential_lane_index] <=
                                route_tail_q[sequential_lane_index];
                            route_tail_q[sequential_lane_index] <=
                                lane_enqueue_route[sequential_lane_index];
                        end
                    end
                    default: begin
                        input_count_q[sequential_lane_index] <=
                            input_count_q[sequential_lane_index];
                    end
                endcase
                if (lane_enqueue[sequential_lane_index]) begin
                    input_write_ptr_q[sequential_lane_index] <=
                        ~input_write_ptr_q[sequential_lane_index];
                end
                if (lane_dequeue[sequential_lane_index]) begin
                    input_read_ptr_q[sequential_lane_index] <=
                        ~input_read_ptr_q[sequential_lane_index];
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (selection_control_flush) begin
            for (sequential_selection_index = 0; sequential_selection_index < PORT_COUNT;
                 sequential_selection_index = sequential_selection_index + 1) begin
                selection_valid_q[sequential_selection_index] <= 1'b0;
                selection_onehot_q[sequential_selection_index] <= '0;
                selection_lane_q[sequential_selection_index] <= 4'd0;
            end
        end else begin
            for (sequential_selection_index = 0; sequential_selection_index < PORT_COUNT;
                 sequential_selection_index = sequential_selection_index + 1) begin
                if (selection_can_load[sequential_selection_index]) begin
                    selection_valid_q[sequential_selection_index] <=
                        grant_valid[sequential_selection_index];
                    selection_onehot_q[sequential_selection_index] <=
                        grant_onehot[sequential_selection_index];
                    selection_lane_q[sequential_selection_index] <=
                        grant_lane[sequential_selection_index];
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (output_control_flush) begin
            for (sequential_output_index = 0; sequential_output_index < PORT_COUNT;
                 sequential_output_index = sequential_output_index + 1) begin
                output_valid_q[sequential_output_index] <= 1'b0;
                round_robin_q[sequential_output_index] <= 4'd0;
            end
        end else begin
            for (sequential_output_index = 0; sequential_output_index < PORT_COUNT;
                 sequential_output_index = sequential_output_index + 1) begin
                if (output_can_load[sequential_output_index]) begin
                    output_valid_q[sequential_output_index] <=
                        selection_valid_q[sequential_output_index];
                    if (selection_valid_q[sequential_output_index]) begin
                        output_vc_q[sequential_output_index] <=
                            grant_vc[sequential_output_index];
                        if (selection_lane_q[sequential_output_index] ==
                            4'(LANE_COUNT-1)) begin
                            round_robin_q[sequential_output_index] <= 4'd0;
                        end else begin
                            round_robin_q[sequential_output_index] <=
                                selection_lane_q[sequential_output_index] + 4'd1;
                        end
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
