`timescale 1ns/1ps
`default_nettype none

// One physical-lane, five-port deterministic XY Router. Cardinal ports use
// internal per-VC credits; the Local port uses ready/valid at the Pod boundary.
module npu_noc_lane_router #(
    parameter int unsigned LOCAL_POD_ID = 0,
    parameter int unsigned PAYLOAD_BYTES = 128,
    parameter int unsigned FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH,
    parameter int unsigned VCS = npu_noc_pkg::NPU_NOC_DATA_VCS,
    parameter int unsigned FIFO_DEPTH = npu_noc_pkg::NPU_NOC_DATA_FIFO_DEPTH,
    parameter int unsigned MAX_PACKET_FLITS =
        npu_noc_pkg::NPU_NOC_DATA_PACKET_FLITS,
    parameter int unsigned AGE_THRESHOLD = npu_noc_pkg::NPU_NOC_AGE_THRESHOLD,
    parameter int unsigned PORTS = npu_noc_pkg::NPU_NOC_PORTS,
    parameter int unsigned VC_WIDTH = (VCS <= 1) ? 1 : $clog2(VCS),
    parameter int unsigned SLOT_COUNT = PORTS * VCS,
    parameter int unsigned SLOT_WIDTH =
        (SLOT_COUNT <= 1) ? 1 : $clog2(SLOT_COUNT),
    parameter int unsigned FIFO_LEVEL_WIDTH = $clog2(FIFO_DEPTH + 1),
    parameter int unsigned CREDIT_WIDTH = $clog2(FIFO_DEPTH + 1),
    parameter int unsigned PACKET_COUNT_WIDTH = $clog2(MAX_PACKET_FLITS + 2),
    parameter int unsigned AGE_WIDTH = $clog2(AGE_THRESHOLD + 1)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic quiesce_i,

    input  logic [PORTS-1:0] port_enable_i,

    input  logic [PORTS-1:0] rx_valid_i,
    output logic [PORTS-1:0] rx_ready_o,
    input  logic [PORTS*VC_WIDTH-1:0] rx_vc_i,
    input  logic [PORTS*FLIT_WIDTH-1:0] rx_flit_i,
    output logic [PORTS*VCS-1:0] rx_credit_o,

    output logic [PORTS-1:0] tx_valid_o,
    input  logic [PORTS-1:0] tx_ready_i,
    output logic [PORTS*VC_WIDTH-1:0] tx_vc_o,
    output logic [PORTS*FLIT_WIDTH-1:0] tx_flit_o,
    input  logic [PORTS*VCS-1:0] tx_credit_i,

    output logic busy_o,
    output logic quiesced_o,
    output logic protocol_error_o,
    output logic [PORTS*64-1:0] accepted_flits_o,
    output logic [PORTS*64-1:0] transmitted_flits_o,
    output logic [PORTS*64-1:0] blocked_cycles_o,
    output logic [PORTS*64-1:0] accepted_packets_o,
    output logic [PORTS*64-1:0] transmitted_packets_o,
    output logic [PORTS*64-1:0] maximum_wait_cycles_o,
    output logic [PORTS*64-1:0] credit_low_watermark_o,
    output logic [PORTS*64-1:0] invalid_route_events_o
);

    localparam int unsigned PAYLOAD_BITS = PAYLOAD_BYTES * 8;
    localparam int unsigned KEEP_LSB = PAYLOAD_BITS;
    localparam int unsigned TRAFFIC_CLASS_LSB = KEEP_LSB + PAYLOAD_BYTES;
    localparam int unsigned DESTINATION_LSB = TRAFFIC_CLASS_LSB + 2;
    localparam int unsigned SOURCE_LSB = DESTINATION_LSB + 3;
    localparam int unsigned EOP_BIT = SOURCE_LSB + 3;
    localparam int unsigned SOP_BIT = EOP_BIT + 1;
    localparam int unsigned VERSION_LSB = SOP_BIT + 1;
    localparam logic [1:0] LOCAL_COLUMN = LOCAL_POD_ID[1:0];
    localparam logic LOCAL_ROW = LOCAL_POD_ID[2];
    localparam logic [PACKET_COUNT_WIDTH-1:0] MAX_PACKET_COUNT =
        PACKET_COUNT_WIDTH'(MAX_PACKET_FLITS);
    localparam logic [AGE_WIDTH-1:0] AGE_LIMIT =
        AGE_WIDTH'(AGE_THRESHOLD);
    localparam logic [CREDIT_WIDTH-1:0] CREDIT_RESET =
        CREDIT_WIDTH'(FIFO_DEPTH);

    logic [SLOT_COUNT-1:0] fifo_push_valid;
    logic [SLOT_COUNT-1:0] fifo_push_ready;
    logic [SLOT_COUNT*FLIT_WIDTH-1:0] fifo_push_data;
    logic [SLOT_COUNT-1:0] fifo_pop_valid;
    logic [SLOT_COUNT-1:0] fifo_pop_ready;
    logic [SLOT_COUNT*FLIT_WIDTH-1:0] fifo_pop_data;
    logic [SLOT_COUNT*FIFO_LEVEL_WIDTH-1:0] fifo_level;

    logic [VC_WIDTH-1:0] selected_rx_vc [0:PORTS-1];
    logic [PORTS-1:0] rx_accept;
    logic [PORTS-1:0] rx_protocol_error;
    logic [SLOT_COUNT-1:0] packet_active_q;
    logic [SLOT_COUNT*3-1:0] packet_source_q;
    logic [SLOT_COUNT*3-1:0] packet_destination_q;
    logic [SLOT_COUNT*2-1:0] packet_traffic_class_q;
    logic [SLOT_COUNT*PACKET_COUNT_WIDTH-1:0] packet_length_q;
    logic [SLOT_COUNT-1:0] packet_protocol_error;

    logic [npu_noc_pkg::NPU_NOC_PORTS-1:0] route_port_onehot
        [0:SLOT_COUNT-1];
    logic [SLOT_COUNT-1:0] route_protocol_error;
    logic [SLOT_COUNT*AGE_WIDTH-1:0] age_q;

    logic [PORTS-1:0] grant_valid_q;
    logic [PORTS*SLOT_WIDTH-1:0] grant_slot_q;
    logic [PORTS*SLOT_WIDTH-1:0] round_robin_q;
    logic [PORTS-1:0] grant_allocate;
    logic [PORTS*SLOT_WIDTH-1:0] grant_allocate_slot;
    logic [SLOT_COUNT-1:0] slot_owned;
    logic [SLOT_COUNT-1:0] age_opportunity;
    logic [PORTS-1:0] tx_fire;
    logic [PORTS-1:0] tx_eop;
    logic [SLOT_COUNT-1:0] invalid_route_drop;
    logic [PORTS-1:0] selected_head_valid;
    logic [PORTS*VC_WIDTH-1:0] selected_head_vc;
    logic [PORTS*FLIT_WIDTH-1:0] selected_head_flit;
    logic [PORTS-1:0] selected_credit_available;

    logic [PORTS*VCS*CREDIT_WIDTH-1:0] credit_count_q;
    logic [PORTS*VCS-1:0] credit_protocol_error;
    logic [PORTS-1:0] credit_full;

    logic [PORTS*64-1:0] accepted_flits_q;
    logic [PORTS*64-1:0] transmitted_flits_q;
    logic [PORTS*64-1:0] blocked_cycles_q;
    logic [PORTS*64-1:0] accepted_packets_q;
    logic [PORTS*64-1:0] transmitted_packets_q;
    logic [PORTS*64-1:0] maximum_wait_cycles_q;
    logic [PORTS*64-1:0] credit_low_watermark_q;
    logic [PORTS*64-1:0] invalid_route_events_q;
    logic protocol_error_q;
    logic configuration_error;

    generate
        for (genvar slot = 0; slot < SLOT_COUNT; slot++) begin : g_fifo
            npu_noc_vc_fifo #(
                .WIDTH(FLIT_WIDTH),
                .DEPTH(FIFO_DEPTH)
            ) u_fifo (
                .clk_i,
                .rst_i,
                .clear_i,
                .push_valid_i(fifo_push_valid[slot]),
                .push_ready_o(fifo_push_ready[slot]),
                .push_data_i(fifo_push_data[
                    slot*FLIT_WIDTH +: FLIT_WIDTH]),
                .pop_valid_o(fifo_pop_valid[slot]),
                .pop_ready_i(fifo_pop_ready[slot]),
                .pop_data_o(fifo_pop_data[
                    slot*FLIT_WIDTH +: FLIT_WIDTH]),
                .level_o(fifo_level[
                    slot*FIFO_LEVEL_WIDTH +: FIFO_LEVEL_WIDTH])
            );
        end
    endgenerate

    always_comb begin
        fifo_push_valid = '0;
        /* verilator lint_off WIDTHCONCAT */
        fifo_push_data = '0;
        /* verilator lint_on WIDTHCONCAT */
        rx_ready_o = '0;
        rx_accept = '0;
        rx_protocol_error = '0;
        for (integer port = 0; port < PORTS; port++) begin
            integer selected_vc_index;
            if (VCS <= 1) begin
                selected_rx_vc[port] = '0;
            end else if (port == npu_noc_pkg::NPU_NOC_PORT_LOCAL) begin
                selected_rx_vc[port] = rx_flit_i[
                    port*FLIT_WIDTH + TRAFFIC_CLASS_LSB +: VC_WIDTH];
            end else begin
                selected_rx_vc[port] = rx_vc_i[
                    port*VC_WIDTH +: VC_WIDTH];
            end
            selected_vc_index = int'($unsigned(selected_rx_vc[port]));

            if (port_enable_i[port] &&
                (selected_vc_index < VCS)) begin
                rx_ready_o[port] = fifo_push_ready[
                    port*VCS + selected_vc_index];
                if ((port == npu_noc_pkg::NPU_NOC_PORT_LOCAL) &&
                    quiesce_i && rx_flit_i[port*FLIT_WIDTH + SOP_BIT]) begin
                    rx_ready_o[port] = 1'b0;
                end
                if (port == npu_noc_pkg::NPU_NOC_PORT_LOCAL) begin
                    rx_accept[port] = rx_valid_i[port] && rx_ready_o[port];
                end else begin
                    rx_accept[port] = rx_valid_i[port] && rx_ready_o[port];
                    if (rx_valid_i[port] && !rx_ready_o[port]) begin
                        rx_protocol_error[port] = 1'b1;
                    end
                end
                if (rx_accept[port]) begin
                    fifo_push_valid[
                        port*VCS + selected_vc_index] = 1'b1;
                    fifo_push_data[
                        (port*VCS + selected_vc_index)*
                        FLIT_WIDTH +:
                        FLIT_WIDTH] = rx_flit_i[
                            port*FLIT_WIDTH +: FLIT_WIDTH];
                end
            end else if (rx_valid_i[port]) begin
                rx_protocol_error[port] = 1'b1;
            end
        end
    end

    always_comb begin
        packet_protocol_error = '0;
        for (integer slot = 0; slot < SLOT_COUNT; slot++) begin
            if (fifo_push_valid[slot] && fifo_push_ready[slot]) begin
                if (!packet_active_q[slot]) begin
                    if (!fifo_push_data[slot*FLIT_WIDTH + SOP_BIT]) begin
                        packet_protocol_error[slot] = 1'b1;
                    end
                end else begin
                    if (fifo_push_data[slot*FLIT_WIDTH + SOP_BIT] ||
                        (fifo_push_data[
                            slot*FLIT_WIDTH + SOURCE_LSB +: 3] !=
                         packet_source_q[slot*3 +: 3]) ||
                        (fifo_push_data[
                            slot*FLIT_WIDTH + DESTINATION_LSB +: 3] !=
                         packet_destination_q[slot*3 +: 3]) ||
                        (fifo_push_data[
                            slot*FLIT_WIDTH + TRAFFIC_CLASS_LSB +: 2] !=
                         packet_traffic_class_q[slot*2 +: 2])) begin
                        packet_protocol_error[slot] = 1'b1;
                    end
                end
                if ((!packet_active_q[slot] && (MAX_PACKET_FLITS < 1)) ||
                    (packet_active_q[slot] &&
                     (packet_length_q[
                        slot*PACKET_COUNT_WIDTH +: PACKET_COUNT_WIDTH] >=
                      MAX_PACKET_COUNT))) begin
                    packet_protocol_error[slot] = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            packet_active_q <= '0;
            packet_source_q <= '0;
            packet_destination_q <= '0;
            packet_traffic_class_q <= '0;
            packet_length_q <= '0;
        end else begin
            for (integer slot = 0; slot < SLOT_COUNT; slot++) begin
                if (fifo_push_valid[slot] && fifo_push_ready[slot]) begin
                    if (!packet_active_q[slot]) begin
                        packet_source_q[slot*3 +: 3] <= fifo_push_data[
                            slot*FLIT_WIDTH + SOURCE_LSB +: 3];
                        packet_destination_q[slot*3 +: 3] <= fifo_push_data[
                            slot*FLIT_WIDTH + DESTINATION_LSB +: 3];
                        packet_traffic_class_q[slot*2 +: 2] <= fifo_push_data[
                            slot*FLIT_WIDTH + TRAFFIC_CLASS_LSB +: 2];
                        packet_length_q[
                            slot*PACKET_COUNT_WIDTH +: PACKET_COUNT_WIDTH] <= 1;
                        packet_active_q[slot] <=
                            !fifo_push_data[slot*FLIT_WIDTH + EOP_BIT];
                    end else if (fifo_push_data[
                        slot*FLIT_WIDTH + EOP_BIT]) begin
                        packet_active_q[slot] <= 1'b0;
                        packet_length_q[
                            slot*PACKET_COUNT_WIDTH +: PACKET_COUNT_WIDTH] <= '0;
                    end else if (packet_length_q[
                        slot*PACKET_COUNT_WIDTH +: PACKET_COUNT_WIDTH] <
                        MAX_PACKET_COUNT + 1'b1) begin
                        packet_length_q[
                            slot*PACKET_COUNT_WIDTH +: PACKET_COUNT_WIDTH] <=
                            packet_length_q[
                                slot*PACKET_COUNT_WIDTH +:
                                PACKET_COUNT_WIDTH] + 1'b1;
                    end
                end
            end
        end
    end

    /* Parameter-specialized boundary Routers make one unsigned comparison
       constant at the outer rows or columns. */
    /* verilator lint_off UNSIGNED */
    /* verilator lint_off CMPCONST */
    always_comb begin
        route_protocol_error = '0;
        for (integer slot = 0; slot < SLOT_COUNT; slot++) begin
            logic [2:0] destination;
            logic [1:0] destination_column;
            logic destination_row;
            destination = fifo_pop_data[
                slot*FLIT_WIDTH + DESTINATION_LSB +: 3];
            destination_column = destination[1:0];
            destination_row = destination[2];
            route_port_onehot[slot] = '0;
            if (fifo_pop_valid[slot]) begin
                if (destination_column > LOCAL_COLUMN) begin
                    route_port_onehot[slot][
                        npu_noc_pkg::NPU_NOC_PORT_EAST] = 1'b1;
                end else if (destination_column < LOCAL_COLUMN) begin
                    route_port_onehot[slot][
                        npu_noc_pkg::NPU_NOC_PORT_WEST] = 1'b1;
                end else if (destination_row > LOCAL_ROW) begin
                    route_port_onehot[slot][
                        npu_noc_pkg::NPU_NOC_PORT_SOUTH] = 1'b1;
                end else if (destination_row < LOCAL_ROW) begin
                    route_port_onehot[slot][
                        npu_noc_pkg::NPU_NOC_PORT_NORTH] = 1'b1;
                end else begin
                    route_port_onehot[slot][
                        npu_noc_pkg::NPU_NOC_PORT_LOCAL] = 1'b1;
                end
                if (|(route_port_onehot[slot] & ~port_enable_i)) begin
                    route_protocol_error[slot] = 1'b1;
                end
            end
        end
    end
    /* verilator lint_on CMPCONST */
    /* verilator lint_on UNSIGNED */

    always_comb begin
        slot_owned = '0;
        for (integer output_port = 0; output_port < PORTS; output_port++) begin
            integer owned_slot;
            owned_slot = int'($unsigned(grant_slot_q[
                output_port*SLOT_WIDTH +: SLOT_WIDTH]));
            if (grant_valid_q[output_port] && (owned_slot < SLOT_COUNT)) begin
                slot_owned[owned_slot] = 1'b1;
            end
        end
    end

    always_comb begin
        grant_allocate = '0;
        grant_allocate_slot = '0;
        age_opportunity = '0;
        for (integer output_port = 0; output_port < PORTS; output_port++) begin
            logic found_aged;
            logic found_any;
            found_aged = 1'b0;
            found_any = 1'b0;
            if (!grant_valid_q[output_port] && port_enable_i[output_port]) begin
                for (integer candidate = 0; candidate < SLOT_COUNT;
                     candidate++) begin
                    if (!slot_owned[candidate] &&
                        fifo_pop_valid[candidate] &&
                        route_port_onehot[candidate][output_port]) begin
                        age_opportunity[candidate] = 1'b1;
                    end
                end
                for (integer candidate = 0; candidate < SLOT_COUNT;
                     candidate++) begin
                    if (!found_aged &&
                        (candidate >= $unsigned(round_robin_q[
                            output_port*SLOT_WIDTH +: SLOT_WIDTH])) &&
                        !slot_owned[candidate] &&
                        fifo_pop_valid[candidate] &&
                        route_port_onehot[candidate][output_port] &&
                        (age_q[candidate*AGE_WIDTH +: AGE_WIDTH] >=
                         AGE_LIMIT)) begin
                        grant_allocate[output_port] = 1'b1;
                        grant_allocate_slot[
                            output_port*SLOT_WIDTH +: SLOT_WIDTH] =
                            candidate[SLOT_WIDTH-1:0];
                        found_aged = 1'b1;
                        found_any = 1'b1;
                    end
                end
                for (integer candidate = 0; candidate < SLOT_COUNT;
                     candidate++) begin
                    if (!found_aged &&
                        (candidate < $unsigned(round_robin_q[
                            output_port*SLOT_WIDTH +: SLOT_WIDTH])) &&
                        !slot_owned[candidate] &&
                        fifo_pop_valid[candidate] &&
                        route_port_onehot[candidate][output_port] &&
                        (age_q[candidate*AGE_WIDTH +: AGE_WIDTH] >=
                         AGE_LIMIT)) begin
                        grant_allocate[output_port] = 1'b1;
                        grant_allocate_slot[
                            output_port*SLOT_WIDTH +: SLOT_WIDTH] =
                            candidate[SLOT_WIDTH-1:0];
                        found_aged = 1'b1;
                        found_any = 1'b1;
                    end
                end
                if (!found_aged) begin
                    for (integer candidate = 0; candidate < SLOT_COUNT;
                         candidate++) begin
                        if (!found_any &&
                            (candidate >= $unsigned(round_robin_q[
                                output_port*SLOT_WIDTH +: SLOT_WIDTH])) &&
                            !slot_owned[candidate] &&
                            fifo_pop_valid[candidate] &&
                            route_port_onehot[candidate][output_port]) begin
                            grant_allocate[output_port] = 1'b1;
                            grant_allocate_slot[
                                output_port*SLOT_WIDTH +: SLOT_WIDTH] =
                                candidate[SLOT_WIDTH-1:0];
                            found_any = 1'b1;
                        end
                    end
                    for (integer candidate = 0; candidate < SLOT_COUNT;
                         candidate++) begin
                        if (!found_any &&
                            (candidate < $unsigned(round_robin_q[
                                output_port*SLOT_WIDTH +: SLOT_WIDTH])) &&
                            !slot_owned[candidate] &&
                            fifo_pop_valid[candidate] &&
                            route_port_onehot[candidate][output_port]) begin
                            grant_allocate[output_port] = 1'b1;
                            grant_allocate_slot[
                                output_port*SLOT_WIDTH +: SLOT_WIDTH] =
                                candidate[SLOT_WIDTH-1:0];
                            found_any = 1'b1;
                        end
                    end
                end
            end
        end
    end

    always_comb begin
        selected_head_valid = '0;
        selected_head_vc = '0;
        selected_head_flit = '0;
        selected_credit_available = '0;
        tx_valid_o = '0;
        tx_vc_o = '0;
        tx_flit_o = '0;
        tx_fire = '0;
        tx_eop = '0;
        fifo_pop_ready = '0;
        rx_credit_o = '0;
        invalid_route_drop = '0;
        for (integer output_port = 0; output_port < PORTS; output_port++) begin
            integer slot;
            integer vc;
            slot = int'($unsigned(grant_slot_q[
                output_port*SLOT_WIDTH +: SLOT_WIDTH]));
            vc = slot % VCS;
            if (grant_valid_q[output_port] && (slot < SLOT_COUNT)) begin
                selected_head_valid[output_port] = fifo_pop_valid[slot];
                selected_head_vc[
                    output_port*VC_WIDTH +: VC_WIDTH] = vc[VC_WIDTH-1:0];
                selected_head_flit[
                    output_port*FLIT_WIDTH +: FLIT_WIDTH] =
                    fifo_pop_data[slot*FLIT_WIDTH +: FLIT_WIDTH];
                if (output_port == npu_noc_pkg::NPU_NOC_PORT_LOCAL) begin
                    selected_credit_available[output_port] = 1'b1;
                    tx_valid_o[output_port] = selected_head_valid[output_port];
                    tx_fire[output_port] = tx_valid_o[output_port] &&
                                           tx_ready_i[output_port];
                end else begin
                    selected_credit_available[output_port] =
                        credit_count_q[
                            (output_port*VCS + vc)*CREDIT_WIDTH +:
                            CREDIT_WIDTH] != '0;
                    tx_valid_o[output_port] = selected_head_valid[output_port] &&
                        selected_credit_available[output_port] &&
                        port_enable_i[output_port];
                    tx_fire[output_port] = tx_valid_o[output_port];
                end
                tx_vc_o[output_port*VC_WIDTH +: VC_WIDTH] =
                    selected_head_vc[
                        output_port*VC_WIDTH +: VC_WIDTH];
                tx_flit_o[output_port*FLIT_WIDTH +: FLIT_WIDTH] =
                    selected_head_flit[
                        output_port*FLIT_WIDTH +: FLIT_WIDTH];
                tx_eop[output_port] = selected_head_flit[
                    output_port*FLIT_WIDTH + EOP_BIT];
                if (tx_fire[output_port]) begin
                    fifo_pop_ready[slot] = 1'b1;
                end
            end
        end
        for (integer slot = 0; slot < SLOT_COUNT; slot++) begin
            if (fifo_pop_valid[slot] && route_protocol_error[slot] &&
                !fifo_pop_ready[slot]) begin
                fifo_pop_ready[slot] = 1'b1;
                invalid_route_drop[slot] = 1'b1;
            end
        end
        for (integer input_port = 1; input_port < PORTS; input_port++) begin
            for (integer vc = 0; vc < VCS; vc++) begin
                if (fifo_pop_valid[input_port*VCS + vc] &&
                    fifo_pop_ready[input_port*VCS + vc]) begin
                    rx_credit_o[input_port*VCS + vc] = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            grant_valid_q <= '0;
            grant_slot_q <= '0;
            round_robin_q <= '0;
        end else begin
            for (integer output_port = 0; output_port < PORTS; output_port++) begin
                if (!grant_valid_q[output_port] &&
                    grant_allocate[output_port]) begin
                    grant_valid_q[output_port] <= 1'b1;
                    grant_slot_q[
                        output_port*SLOT_WIDTH +: SLOT_WIDTH] <=
                        grant_allocate_slot[
                            output_port*SLOT_WIDTH +: SLOT_WIDTH];
                end
                if (tx_fire[output_port] && tx_eop[output_port]) begin
                    logic [SLOT_WIDTH:0] next_slot;
                    grant_valid_q[output_port] <= 1'b0;
                    next_slot = grant_slot_q[
                        output_port*SLOT_WIDTH +: SLOT_WIDTH] + 1'b1;
                    if (next_slot >= (SLOT_WIDTH+1)'(SLOT_COUNT)) begin
                        round_robin_q[
                            output_port*SLOT_WIDTH +: SLOT_WIDTH] <= '0;
                    end else begin
                        round_robin_q[
                            output_port*SLOT_WIDTH +: SLOT_WIDTH] <=
                            next_slot[SLOT_WIDTH-1:0];
                    end
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            age_q <= '0;
        end else begin
            for (integer slot = 0; slot < SLOT_COUNT; slot++) begin
                if (!fifo_pop_valid[slot] || fifo_pop_ready[slot]) begin
                    age_q[slot*AGE_WIDTH +: AGE_WIDTH] <= '0;
                end else if (age_opportunity[slot] &&
                             (age_q[slot*AGE_WIDTH +: AGE_WIDTH] <
                              AGE_LIMIT)) begin
                    age_q[slot*AGE_WIDTH +: AGE_WIDTH] <=
                        age_q[slot*AGE_WIDTH +: AGE_WIDTH] + 1'b1;
                end
            end
        end
    end

    always_comb begin
        credit_protocol_error = '0;
        credit_full = '1;
        for (integer output_port = 0; output_port < PORTS; output_port++) begin
            for (integer vc = 0; vc < VCS; vc++) begin
                logic send_this_vc;
                logic return_this_vc;
                logic [CREDIT_WIDTH-1:0] count;
                count = credit_count_q[
                    (output_port*VCS + vc)*CREDIT_WIDTH +: CREDIT_WIDTH];
                send_this_vc = tx_fire[output_port] &&
                    (selected_head_vc[
                        output_port*VC_WIDTH +: VC_WIDTH] ==
                     VC_WIDTH'(vc));
                return_this_vc = tx_credit_i[output_port*VCS + vc];
                if (output_port != npu_noc_pkg::NPU_NOC_PORT_LOCAL) begin
                    if (send_this_vc && (count == '0)) begin
                        credit_protocol_error[output_port*VCS + vc] = 1'b1;
                    end
                    if (return_this_vc && !send_this_vc &&
                        (count == CREDIT_RESET)) begin
                        credit_protocol_error[output_port*VCS + vc] = 1'b1;
                    end
                    if (count != CREDIT_RESET) begin
                        credit_full[output_port] = 1'b0;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            for (integer output_port = 0; output_port < PORTS; output_port++) begin
                for (integer vc = 0; vc < VCS; vc++) begin
                    credit_count_q[
                        (output_port*VCS + vc)*CREDIT_WIDTH +:
                        CREDIT_WIDTH] <= CREDIT_RESET;
                end
            end
        end else begin
            for (integer output_port = 1; output_port < PORTS; output_port++) begin
                for (integer vc = 0; vc < VCS; vc++) begin
                    logic send_this_vc;
                    logic return_this_vc;
                    send_this_vc = tx_fire[output_port] &&
                        (selected_head_vc[
                            output_port*VC_WIDTH +: VC_WIDTH] ==
                         VC_WIDTH'(vc));
                    return_this_vc = tx_credit_i[output_port*VCS + vc];
                    case ({return_this_vc, send_this_vc})
                        2'b10: credit_count_q[
                            (output_port*VCS + vc)*CREDIT_WIDTH +:
                            CREDIT_WIDTH] <= credit_count_q[
                                (output_port*VCS + vc)*CREDIT_WIDTH +:
                                CREDIT_WIDTH] + 1'b1;
                        2'b01: credit_count_q[
                            (output_port*VCS + vc)*CREDIT_WIDTH +:
                            CREDIT_WIDTH] <= credit_count_q[
                                (output_port*VCS + vc)*CREDIT_WIDTH +:
                                CREDIT_WIDTH] - 1'b1;
                        default: credit_count_q[
                            (output_port*VCS + vc)*CREDIT_WIDTH +:
                            CREDIT_WIDTH] <= credit_count_q[
                                (output_port*VCS + vc)*CREDIT_WIDTH +:
                                CREDIT_WIDTH];
                    endcase
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            accepted_flits_q <= '0;
            transmitted_flits_q <= '0;
            blocked_cycles_q <= '0;
            accepted_packets_q <= '0;
            transmitted_packets_q <= '0;
            maximum_wait_cycles_q <= '0;
            invalid_route_events_q <= '0;
            for (integer port = 0; port < PORTS; port++) begin
                if (port == npu_noc_pkg::NPU_NOC_PORT_LOCAL) begin
                    credit_low_watermark_q[port*64 +: 64] <= '0;
                end else begin
                    credit_low_watermark_q[port*64 +: 64] <=
                        64'(FIFO_DEPTH);
                end
            end
            protocol_error_q <= 1'b0;
        end else begin
            for (integer port = 0; port < PORTS; port++) begin
                if (rx_accept[port]) begin
                    accepted_flits_q[port*64 +: 64] <=
                        accepted_flits_q[port*64 +: 64] + 1'b1;
                    if (rx_flit_i[port*FLIT_WIDTH + SOP_BIT]) begin
                        accepted_packets_q[port*64 +: 64] <=
                            accepted_packets_q[port*64 +: 64] + 1'b1;
                    end
                end
                if (tx_fire[port]) begin
                    transmitted_flits_q[port*64 +: 64] <=
                        transmitted_flits_q[port*64 +: 64] + 1'b1;
                    if (tx_eop[port]) begin
                        transmitted_packets_q[port*64 +: 64] <=
                            transmitted_packets_q[port*64 +: 64] + 1'b1;
                    end
                end
                if (grant_valid_q[port] && selected_head_valid[port] &&
                    !tx_fire[port]) begin
                    blocked_cycles_q[port*64 +: 64] <=
                        blocked_cycles_q[port*64 +: 64] + 1'b1;
                end
                if (grant_allocate[port]) begin
                    integer allocated_slot;
                    allocated_slot = int'($unsigned(grant_allocate_slot[
                        port*SLOT_WIDTH +: SLOT_WIDTH]));
                    if ((allocated_slot < SLOT_COUNT) &&
                        (64'($unsigned(age_q[
                            allocated_slot*AGE_WIDTH +: AGE_WIDTH])) >
                         maximum_wait_cycles_q[port*64 +: 64])) begin
                        maximum_wait_cycles_q[port*64 +: 64] <=
                            64'($unsigned(age_q[
                                allocated_slot*AGE_WIDTH +: AGE_WIDTH]));
                    end
                end
                for (integer vc = 0; vc < VCS; vc++) begin
                    logic [CREDIT_WIDTH-1:0] credit_after_send;
                    credit_after_send = credit_count_q[
                        (port*VCS + vc)*CREDIT_WIDTH +: CREDIT_WIDTH];
                    if ((port != npu_noc_pkg::NPU_NOC_PORT_LOCAL) &&
                        tx_fire[port] &&
                        (selected_head_vc[
                            port*VC_WIDTH +: VC_WIDTH] == VC_WIDTH'(vc)) &&
                        (credit_after_send != '0)) begin
                        credit_after_send = credit_after_send - 1'b1;
                        if (64'($unsigned(credit_after_send)) <
                            credit_low_watermark_q[port*64 +: 64]) begin
                            credit_low_watermark_q[port*64 +: 64] <=
                                64'($unsigned(credit_after_send));
                        end
                    end
                end
                if (|invalid_route_drop[port*VCS +: VCS]) begin
                    invalid_route_events_q[port*64 +: 64] <=
                        invalid_route_events_q[port*64 +: 64] +
                        64'($countones(
                            invalid_route_drop[port*VCS +: VCS]));
                end
            end
            if ((|rx_protocol_error) || (|packet_protocol_error) ||
                (|route_protocol_error) || (|credit_protocol_error)) begin
                protocol_error_q <= 1'b1;
            end
        end
    end

    assign configuration_error = (PORTS != 5) ||
        (LOCAL_POD_ID >= npu_noc_pkg::NPU_NOC_PODS) ||
        (PAYLOAD_BYTES < 1) || (FLIT_WIDTH <= VERSION_LSB + 3) ||
        (VCS < 1) || (VCS > 4) || (FIFO_DEPTH < 2) ||
        (MAX_PACKET_FLITS < 1) || (AGE_THRESHOLD < 1);
    assign busy_o = (|fifo_pop_valid) || (|grant_valid_q);
    assign quiesced_o = quiesce_i && !busy_o && (&credit_full);
    assign protocol_error_o = protocol_error_q || configuration_error;
    assign accepted_flits_o = accepted_flits_q;
    assign transmitted_flits_o = transmitted_flits_q;
    assign blocked_cycles_o = blocked_cycles_q;
    assign accepted_packets_o = accepted_packets_q;
    assign transmitted_packets_o = transmitted_packets_q;
    assign maximum_wait_cycles_o = maximum_wait_cycles_q;
    assign credit_low_watermark_o = credit_low_watermark_q;
    assign invalid_route_events_o = invalid_route_events_q;

`ifdef FORMAL
    logic formal_past_valid_q;
    initial formal_past_valid_q = 1'b0;
    always_ff @(posedge clk_i) begin
        formal_past_valid_q <= 1'b1;
        if (formal_past_valid_q && !$past(rst_i || clear_i) &&
            !rst_i && !clear_i) begin
            for (integer output_port = 0; output_port < PORTS;
                 output_port++) begin
                if ($past(grant_valid_q[output_port] &&
                    !(tx_fire[output_port] && tx_eop[output_port]))) begin
                    assert (grant_valid_q[output_port]);
                    assert (grant_slot_q[
                        output_port*SLOT_WIDTH +: SLOT_WIDTH] ==
                        $past(grant_slot_q[
                            output_port*SLOT_WIDTH +: SLOT_WIDTH]));
                end
            end
        end
        if (!rst_i && !clear_i) begin
            for (integer output_port = 1; output_port < PORTS;
                 output_port++) begin
                for (integer vc = 0; vc < VCS; vc++) begin
                    logic formal_past_send;
                    logic formal_past_return;
                    assert (credit_count_q[
                        (output_port*VCS + vc)*CREDIT_WIDTH +:
                        CREDIT_WIDTH] <= CREDIT_RESET);
                    formal_past_send = $past(tx_fire[output_port] &&
                        (selected_head_vc[
                            output_port*VC_WIDTH +: VC_WIDTH] ==
                         VC_WIDTH'(vc)));
                    formal_past_return = $past(
                        tx_credit_i[output_port*VCS + vc]);
                    if (formal_past_valid_q &&
                        !$past(rst_i || clear_i)) begin
                        case ({formal_past_return, formal_past_send})
                            2'b10: assert (credit_count_q[
                                (output_port*VCS + vc)*CREDIT_WIDTH +:
                                CREDIT_WIDTH] == $past(credit_count_q[
                                    (output_port*VCS + vc)*CREDIT_WIDTH +:
                                    CREDIT_WIDTH]) + 1'b1);
                            2'b01: assert (credit_count_q[
                                (output_port*VCS + vc)*CREDIT_WIDTH +:
                                CREDIT_WIDTH] == $past(credit_count_q[
                                    (output_port*VCS + vc)*CREDIT_WIDTH +:
                                    CREDIT_WIDTH]) - 1'b1);
                            default: assert (credit_count_q[
                                (output_port*VCS + vc)*CREDIT_WIDTH +:
                                CREDIT_WIDTH] == $past(credit_count_q[
                                    (output_port*VCS + vc)*CREDIT_WIDTH +:
                                    CREDIT_WIDTH]));
                        endcase
                    end
                end
            end
            for (integer first_port = 0; first_port < PORTS;
                 first_port++) begin
                for (integer second_port = first_port + 1;
                     second_port < PORTS; second_port++) begin
                    if (grant_valid_q[first_port] &&
                        grant_valid_q[second_port]) begin
                        assert (grant_slot_q[
                            first_port*SLOT_WIDTH +: SLOT_WIDTH] !=
                            grant_slot_q[
                                second_port*SLOT_WIDTH +: SLOT_WIDTH]);
                    end
                end
            end
            for (integer output_port = 0; output_port < PORTS;
                 output_port++) begin
                if (tx_fire[output_port]) begin
                    assert (selected_head_valid[output_port]);
                    assert (grant_valid_q[output_port]);
                end
            end
        end
    end
`endif

    wire _unused_local_credit_inputs = &{1'b0,
        tx_credit_i[npu_noc_pkg::NPU_NOC_PORT_LOCAL*VCS +: VCS],
        tx_ready_i[PORTS-1:1], fifo_level};

endmodule

`default_nettype wire
