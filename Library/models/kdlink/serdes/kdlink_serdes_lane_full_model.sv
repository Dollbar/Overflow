module kdlink_serdes_lane_full_model #(
    parameter integer PROPAGATION_CYCLES = 3,
    parameter integer STATIC_SKEW_CYCLES = 0,
    parameter integer CDR_LOCK_CYCLES = 8,
    parameter integer BLOCK_LOCK_CYCLES = 8,
    parameter integer JITTER_PERIOD_BLOCKS = 0,
    parameter integer JITTER_EXTRA_CYCLES = 0,
    parameter integer BURST_ERROR_LENGTH_BLOCKS = 4,
    parameter integer ELASTIC_DEPTH = 64,
    parameter [65:0] CORRUPTION_MASK = 66'd3
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire admin_up_i,
    input wire signal_detect_i,
    input wire rx_ready_i,
    input wire force_loss_of_lock_i,
    input wire tx_block_valid_i,
    input wire [65:0] tx_block_i,
    input wire inject_drop_i,
    input wire inject_corrupt_i,
    input wire inject_burst_i,
    input wire [31:0] error_period_blocks_i,
    output reg rx_block_valid_o,
    output reg [65:0] rx_block_o,
    output wire cdr_locked_o,
    output wire block_locked_o,
    output wire lane_ready_o,
    output wire [2:0] lane_state_o,
    output reg [31:0] offered_blocks_o,
    output reg [31:0] delivered_blocks_o,
    output reg [31:0] dropped_blocks_o,
    output reg [31:0] corrupted_blocks_o,
    output reg [31:0] overflow_blocks_o,
    output reg [31:0] retrain_events_o
);
    localparam [2:0] LANE_DOWN = 3'd0;
    localparam [2:0] LANE_CDR_LOCK = 3'd1;
    localparam [2:0] LANE_BLOCK_LOCK = 3'd2;
    localparam [2:0] LANE_READY = 3'd3;
    localparam [2:0] LANE_FAULT = 3'd4;
    localparam integer BASE_LATENCY = PROPAGATION_CYCLES + STATIC_SKEW_CYCLES;
    localparam integer POINTER_WIDTH = (ELASTIC_DEPTH <= 2) ? 1 : $clog2(ELASTIC_DEPTH);
    localparam integer JITTER_DIVISOR = (JITTER_PERIOD_BLOCKS > 0) ? JITTER_PERIOD_BLOCKS : 1;
    localparam integer LAST_POINTER_INTEGER = ELASTIC_DEPTH - 1;
    localparam [POINTER_WIDTH:0] ELASTIC_DEPTH_COUNT = ELASTIC_DEPTH[POINTER_WIDTH:0];
    localparam [POINTER_WIDTH-1:0] LAST_POINTER = LAST_POINTER_INTEGER[POINTER_WIDTH-1:0];

    reg [2:0] lane_state_q;
    reg [31:0] lock_count_q;
    reg [31:0] offered_sequence_q;
    reg [31:0] periodic_error_count_q;
    reg [31:0] burst_remaining_q;
    reg [31:0] cycle_count_q;
    reg [31:0] last_due_cycle_q;
    reg [65:0] block_fifo [0:ELASTIC_DEPTH-1];
    reg [31:0] due_fifo [0:ELASTIC_DEPTH-1];
    reg [POINTER_WIDTH-1:0] read_pointer_q;
    reg [POINTER_WIDTH-1:0] write_pointer_q;
    reg [POINTER_WIDTH:0] fifo_count_q;
    integer queue_index;

    wire lane_available;
    wire accept_block;
    wire explicit_drop;
    wire periodic_error;
    wire burst_error;
    wire corrupt_block;
    wire pop_block;
    wire fifo_full;
    wire jitter_event;
    wire [31:0] requested_due_cycle;
    wire [31:0] ordered_due_cycle;

    assign lane_available = admin_up_i && signal_detect_i && rx_ready_i && !force_loss_of_lock_i;
    assign cdr_locked_o = (lane_state_q == LANE_BLOCK_LOCK) || (lane_state_q == LANE_READY);
    assign block_locked_o = (lane_state_q == LANE_READY);
    assign lane_ready_o = (lane_state_q == LANE_READY);
    assign lane_state_o = lane_state_q;
    assign accept_block = tx_block_valid_i && lane_available && lane_ready_o;
    assign explicit_drop = accept_block && inject_drop_i;
    assign periodic_error = accept_block && (error_period_blocks_i != 32'd0) &&
        (periodic_error_count_q >= error_period_blocks_i - 32'd1);
    assign burst_error = accept_block && ((burst_remaining_q != 32'd0) || inject_burst_i);
    assign corrupt_block = accept_block && !inject_drop_i &&
        (inject_corrupt_i || periodic_error || burst_error);
    assign fifo_full = (fifo_count_q == ELASTIC_DEPTH_COUNT);
    assign pop_block = (fifo_count_q != 0) && (due_fifo[read_pointer_q] <= cycle_count_q);
    assign jitter_event = accept_block && (JITTER_PERIOD_BLOCKS > 0) &&
        ((offered_sequence_q % JITTER_DIVISOR) == JITTER_DIVISOR - 1);
    assign requested_due_cycle = cycle_count_q + BASE_LATENCY +
        ((jitter_event) ? JITTER_EXTRA_CYCLES : 0);
    assign ordered_due_cycle = (fifo_count_q == 0 || requested_due_cycle > last_due_cycle_q) ?
        requested_due_cycle : last_due_cycle_q + 32'd1;

    initial begin
        if (PROPAGATION_CYCLES < 1) $fatal(1, "PROPAGATION_CYCLES must be at least one");
        if (STATIC_SKEW_CYCLES < 0) $fatal(1, "STATIC_SKEW_CYCLES must be non-negative");
        if (CDR_LOCK_CYCLES < 1 || BLOCK_LOCK_CYCLES < 1) begin
            $fatal(1, "lock intervals must be at least one cycle");
        end
        if (JITTER_PERIOD_BLOCKS < 0 || JITTER_EXTRA_CYCLES < 0) begin
            $fatal(1, "jitter parameters must be non-negative");
        end
        if (BURST_ERROR_LENGTH_BLOCKS < 1 || ELASTIC_DEPTH < 2) begin
            $fatal(1, "burst length and elastic depth are too small");
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            lane_state_q <= LANE_DOWN;
            lock_count_q <= 32'd0;
            offered_sequence_q <= 32'd0;
            periodic_error_count_q <= 32'd0;
            burst_remaining_q <= 32'd0;
            cycle_count_q <= 32'd0;
            last_due_cycle_q <= 32'd0;
            read_pointer_q <= {POINTER_WIDTH{1'b0}};
            write_pointer_q <= {POINTER_WIDTH{1'b0}};
            fifo_count_q <= {(POINTER_WIDTH+1){1'b0}};
            rx_block_valid_o <= 1'b0;
            rx_block_o <= 66'd0;
            offered_blocks_o <= 32'd0;
            delivered_blocks_o <= 32'd0;
            dropped_blocks_o <= 32'd0;
            corrupted_blocks_o <= 32'd0;
            overflow_blocks_o <= 32'd0;
            retrain_events_o <= 32'd0;
            for (queue_index = 0; queue_index < ELASTIC_DEPTH; queue_index = queue_index + 1) begin
                block_fifo[queue_index] <= 66'd0;
                due_fifo[queue_index] <= 32'd0;
            end
        end else begin
            cycle_count_q <= cycle_count_q + 32'd1;
            rx_block_valid_o <= 1'b0;

            if (!admin_up_i || !signal_detect_i || !rx_ready_i) begin
                if (lane_state_q == LANE_READY) retrain_events_o <= retrain_events_o + 32'd1;
                lane_state_q <= LANE_DOWN;
                lock_count_q <= 32'd0;
                offered_sequence_q <= 32'd0;
                periodic_error_count_q <= 32'd0;
                burst_remaining_q <= 32'd0;
                last_due_cycle_q <= cycle_count_q;
                read_pointer_q <= {POINTER_WIDTH{1'b0}};
                write_pointer_q <= {POINTER_WIDTH{1'b0}};
                fifo_count_q <= {(POINTER_WIDTH+1){1'b0}};
            end else if (force_loss_of_lock_i) begin
                if (lane_state_q == LANE_READY) retrain_events_o <= retrain_events_o + 32'd1;
                lane_state_q <= LANE_FAULT;
                lock_count_q <= 32'd0;
                offered_sequence_q <= 32'd0;
                periodic_error_count_q <= 32'd0;
                burst_remaining_q <= 32'd0;
                last_due_cycle_q <= cycle_count_q;
                read_pointer_q <= {POINTER_WIDTH{1'b0}};
                write_pointer_q <= {POINTER_WIDTH{1'b0}};
                fifo_count_q <= {(POINTER_WIDTH+1){1'b0}};
            end else begin
                case (lane_state_q)
                    LANE_DOWN, LANE_FAULT: begin
                        lane_state_q <= LANE_CDR_LOCK;
                        lock_count_q <= 32'd1;
                    end
                    LANE_CDR_LOCK: begin
                        if (lock_count_q >= CDR_LOCK_CYCLES) begin
                            lane_state_q <= LANE_BLOCK_LOCK;
                            lock_count_q <= 32'd1;
                        end else begin
                            lock_count_q <= lock_count_q + 32'd1;
                        end
                    end
                    LANE_BLOCK_LOCK: begin
                        if (lock_count_q >= BLOCK_LOCK_CYCLES) begin
                            lane_state_q <= LANE_READY;
                            lock_count_q <= lock_count_q;
                        end else begin
                            lock_count_q <= lock_count_q + 32'd1;
                        end
                    end
                    default: lane_state_q <= LANE_READY;
                endcase

                if (pop_block) begin
                    rx_block_valid_o <= 1'b1;
                    rx_block_o <= block_fifo[read_pointer_q];
                    delivered_blocks_o <= delivered_blocks_o + 32'd1;
                    read_pointer_q <= (read_pointer_q == LAST_POINTER) ?
                        {POINTER_WIDTH{1'b0}} : read_pointer_q + 1'b1;
                end

                if (accept_block) begin
                    offered_blocks_o <= offered_blocks_o + 32'd1;
                    offered_sequence_q <= offered_sequence_q + 32'd1;
                    if (periodic_error) periodic_error_count_q <= 32'd0;
                    else periodic_error_count_q <= periodic_error_count_q + 32'd1;

                    if (inject_burst_i && burst_remaining_q == 0) begin
                        burst_remaining_q <= BURST_ERROR_LENGTH_BLOCKS - 1;
                    end else if (burst_remaining_q != 0) begin
                        burst_remaining_q <= burst_remaining_q - 32'd1;
                    end

                    if (explicit_drop) begin
                        dropped_blocks_o <= dropped_blocks_o + 32'd1;
                    end else if (fifo_full && !pop_block) begin
                        overflow_blocks_o <= overflow_blocks_o + 32'd1;
                        dropped_blocks_o <= dropped_blocks_o + 32'd1;
                    end else begin
                        block_fifo[write_pointer_q] <= corrupt_block ?
                            (tx_block_i ^ CORRUPTION_MASK) : tx_block_i;
                        due_fifo[write_pointer_q] <= ordered_due_cycle;
                        last_due_cycle_q <= ordered_due_cycle;
                        write_pointer_q <= (write_pointer_q == LAST_POINTER) ?
                            {POINTER_WIDTH{1'b0}} : write_pointer_q + 1'b1;
                        if (corrupt_block) corrupted_blocks_o <= corrupted_blocks_o + 32'd1;
                    end
                end

                case ({accept_block && !explicit_drop && (!fifo_full || pop_block), pop_block})
                    2'b10: fifo_count_q <= fifo_count_q + 1'b1;
                    2'b01: fifo_count_q <= fifo_count_q - 1'b1;
                    default: fifo_count_q <= fifo_count_q;
                endcase
            end
        end
    end
endmodule
