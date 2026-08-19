module kdlink_v2_replay_window #(
    parameter integer SLOT_BITS = 10
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire store_start_i,
    input wire store_valid_i,
    input wire [607:0] store_body_i,
    input wire store_last_i,
    output wire store_ready_o,
    input wire ack_valid_i,
    input wire [11:0] ack_collective_id_i,
    input wire ack_phase_i,
    input wire [11:0] ack_packet_seq_i,
    input wire nack_valid_i,
    input wire [11:0] nack_collective_id_i,
    input wire nack_phase_i,
    input wire [11:0] nack_packet_seq_i,
    output wire replay_valid_o,
    input wire replay_ready_i,
    output wire [607:0] replay_body_o,
    output wire replay_last_o,
    output reg retry_exhausted_o,
    output wire [SLOT_BITS:0] occupancy_o
);
    localparam integer SLOTS = (1 << SLOT_BITS);
    reg [607:0] body_mem [0:SLOTS*16-1];
    reg slot_valid_q [0:SLOTS-1];
    reg slot_complete_q [0:SLOTS-1];
    reg [11:0] collective_q [0:SLOTS-1];
    reg phase_q [0:SLOTS-1];
    reg [11:0] sequence_q [0:SLOTS-1];
    reg [4:0] flit_count_q [0:SLOTS-1];
    reg [2:0] retry_count_q [0:SLOTS-1];
    reg store_active_q;
    reg [SLOT_BITS-1:0] store_slot_q;
    reg [3:0] store_flit_q;
    reg replay_active_q;
    reg [SLOT_BITS-1:0] replay_slot_q;
    reg [3:0] replay_flit_q;
    reg replay_output_valid_q;
    reg [607:0] replay_output_body_q;
    reg replay_output_last_q;
    reg [SLOT_BITS:0] occupancy_q;
    wire [SLOT_BITS-1:0] store_slot;
    wire [SLOT_BITS-1:0] ack_slot;
    wire [SLOT_BITS-1:0] nack_slot;
    wire store_slot_available;
    wire store_fire;
    wire store_allocate;
    wire ack_match;
    wire ack_release;
    wire nack_match;
    wire replay_load;
    wire replay_source_last;
    reg [607:0] replay_source_body;
    integer reset_index;

    assign store_slot = store_body_i[582 +: SLOT_BITS];
    assign ack_slot = ack_packet_seq_i[SLOT_BITS-1:0];
    assign nack_slot = nack_packet_seq_i[SLOT_BITS-1:0];
    assign store_slot_available = !slot_valid_q[store_slot];
    assign store_ready_o = store_active_q || store_slot_available;
    assign store_fire = store_valid_i && store_ready_o;
    assign store_allocate = store_fire && !store_active_q && store_start_i;
    assign ack_match = slot_valid_q[ack_slot] &&
        (collective_q[ack_slot] == ack_collective_id_i) &&
        (phase_q[ack_slot] == ack_phase_i) &&
        (sequence_q[ack_slot] == ack_packet_seq_i);
    assign ack_release = ack_valid_i && ack_match;
    assign nack_match = slot_valid_q[nack_slot] && slot_complete_q[nack_slot] &&
        (collective_q[nack_slot] == nack_collective_id_i) &&
        (phase_q[nack_slot] == nack_phase_i) &&
        (sequence_q[nack_slot] == nack_packet_seq_i);
    assign replay_load = replay_active_q && (!replay_output_valid_q || replay_ready_i);
    assign replay_source_last = replay_active_q &&
        ({1'b0, replay_flit_q} + 5'd1 == flit_count_q[replay_slot_q]);
    assign replay_valid_o = replay_output_valid_q;
    assign replay_body_o = replay_output_body_q;
    assign replay_last_o = replay_output_last_q;
    assign occupancy_o = occupancy_q;

    always @(*) begin
        replay_source_body = body_mem[{replay_slot_q, 4'b0000} |
            {{SLOT_BITS{1'b0}}, replay_flit_q}];
        replay_source_body[527:525] = 3'd6;
        replay_source_body[531] = 1'b1;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            store_active_q <= 1'b0;
            store_slot_q <= {SLOT_BITS{1'b0}};
            store_flit_q <= 4'd0;
            replay_active_q <= 1'b0;
            replay_slot_q <= {SLOT_BITS{1'b0}};
            replay_flit_q <= 4'd0;
            replay_output_valid_q <= 1'b0;
            replay_output_body_q <= 608'd0;
            replay_output_last_q <= 1'b0;
            retry_exhausted_o <= 1'b0;
            occupancy_q <= {(SLOT_BITS+1){1'b0}};
            for (reset_index = 0; reset_index < SLOTS; reset_index = reset_index + 1) begin
                slot_valid_q[reset_index] <= 1'b0;
                slot_complete_q[reset_index] <= 1'b0;
                collective_q[reset_index] <= 12'd0;
                phase_q[reset_index] <= 1'b0;
                sequence_q[reset_index] <= 12'd0;
                flit_count_q[reset_index] <= 5'd0;
                retry_count_q[reset_index] <= 3'd0;
            end
        end else begin
            retry_exhausted_o <= 1'b0;
            case ({store_allocate, ack_release})
                2'b10: occupancy_q <= occupancy_q + 1'b1;
                2'b01: occupancy_q <= occupancy_q - 1'b1;
                default: occupancy_q <= occupancy_q;
            endcase
            if (!replay_output_valid_q || replay_ready_i) begin
                if (replay_load) begin
                    replay_output_valid_q <= 1'b1;
                    replay_output_body_q <= replay_source_body;
                    replay_output_last_q <= replay_source_last;
                end else begin
                    replay_output_valid_q <= 1'b0;
                    replay_output_last_q <= 1'b0;
                end
            end

            if (store_fire && (store_active_q || store_start_i)) begin
                body_mem[{(store_active_q ? store_slot_q : store_slot), 4'b0000} |
                    {{SLOT_BITS{1'b0}},
                    (store_active_q ? store_flit_q : 4'd0)}] <= store_body_i;
                if (!store_active_q) begin
                    store_slot_q <= store_slot;
                    store_flit_q <= 4'd0;
                    slot_valid_q[store_slot] <= 1'b1;
                    slot_complete_q[store_slot] <= 1'b0;
                    collective_q[store_slot] <= store_body_i[569:558];
                    phase_q[store_slot] <= store_body_i[528];
                    sequence_q[store_slot] <= store_body_i[593:582];
                    retry_count_q[store_slot] <= 3'd0;
                end
                if (store_last_i) begin
                    slot_complete_q[store_active_q ? store_slot_q : store_slot] <= 1'b1;
                    flit_count_q[store_active_q ? store_slot_q : store_slot] <=
                        {1'b0, (store_active_q ? store_flit_q : 4'd0)} + 5'd1;
                    store_active_q <= 1'b0;
                    store_flit_q <= 4'd0;
                end else begin
                    store_active_q <= 1'b1;
                    store_flit_q <= (store_active_q ? store_flit_q : 4'd0) + 1'b1;
                end
            end

            if (ack_release) begin
                slot_valid_q[ack_slot] <= 1'b0;
                slot_complete_q[ack_slot] <= 1'b0;
            end

            if (nack_valid_i && nack_match && !replay_active_q) begin
                if (retry_count_q[nack_slot] == 3'd7) begin
                    retry_exhausted_o <= 1'b1;
                end else begin
                    retry_count_q[nack_slot] <= retry_count_q[nack_slot] + 1'b1;
                    replay_active_q <= 1'b1;
                    replay_slot_q <= nack_slot;
                    replay_flit_q <= 4'd0;
                end
            end

            if (replay_load) begin
                if (replay_source_last) begin
                    replay_active_q <= 1'b0;
                    replay_flit_q <= 4'd0;
                end else begin
                    replay_flit_q <= replay_flit_q + 1'b1;
                end
            end
        end
    end
endmodule
