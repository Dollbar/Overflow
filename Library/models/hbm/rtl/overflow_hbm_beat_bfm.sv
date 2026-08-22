module overflow_hbm_beat_bfm #(
    parameter integer PARTITIONS = 8,
    parameter integer PARTITION_BITS = 3,
    parameter integer ADDR_WIDTH = 35,
    parameter integer TAG_WIDTH = 16,
    parameter integer DATA_BYTES = 128,
    parameter integer READ_LATENCY_CYCLES = 500,
    parameter integer WRITE_LATENCY_CYCLES = 500,
    parameter integer PAYLOAD_BYTES_PER_CYCLE_PER_PARTITION = 625,
    parameter integer MAX_OUTSTANDING_PER_PARTITION = 64,
    parameter integer QUEUE_DEPTH = 512,
    parameter [63:0] CAPACITY_BYTES_PER_PARTITION = 64'd24000000000
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire req_valid_i,
    output wire req_ready_o,
    output wire req_error_o,
    input wire req_write_i,
    input wire [PARTITION_BITS-1:0] req_partition_i,
    input wire [ADDR_WIDTH-1:0] req_address_i,
    input wire [TAG_WIDTH-1:0] req_tag_i,
    input wire [DATA_BYTES*8-1:0] req_write_data_i,
    input wire [DATA_BYTES-1:0] req_byte_enable_i,
    input wire inject_correctable_i,
    input wire inject_uncorrectable_i,
    output reg rsp_valid_o,
    input wire rsp_ready_i,
    output reg rsp_write_o,
    output reg [PARTITION_BITS-1:0] rsp_partition_o,
    output reg [TAG_WIDTH-1:0] rsp_tag_o,
    output reg [DATA_BYTES*8-1:0] rsp_read_data_o,
    output reg [1:0] rsp_status_o,
    output reg [63:0] accepted_beats_o,
    output reg [63:0] completed_beats_o,
    output reg [63:0] backpressure_cycles_o
);
    localparam [1:0] STATUS_OK = 2'd0;
    localparam [1:0] STATUS_ECC_CORRECTED = 2'd1;
    localparam [1:0] STATUS_ECC_UNCORRECTABLE = 2'd2;
    localparam [63:0] TOKEN_CAPACITY =
        (DATA_BYTES > PAYLOAD_BYTES_PER_CYCLE_PER_PARTITION) ?
        DATA_BYTES : PAYLOAD_BYTES_PER_CYCLE_PER_PARTITION + DATA_BYTES - 1;

    reg entry_valid [0:QUEUE_DEPTH-1];
    reg entry_write [0:QUEUE_DEPTH-1];
    reg [PARTITION_BITS-1:0] entry_partition [0:QUEUE_DEPTH-1];
    reg [ADDR_WIDTH-1:0] entry_address [0:QUEUE_DEPTH-1];
    reg [TAG_WIDTH-1:0] entry_tag [0:QUEUE_DEPTH-1];
    reg [DATA_BYTES*8-1:0] entry_write_data [0:QUEUE_DEPTH-1];
    reg [DATA_BYTES-1:0] entry_byte_enable [0:QUEUE_DEPTH-1];
    reg entry_correctable [0:QUEUE_DEPTH-1];
    reg entry_uncorrectable [0:QUEUE_DEPTH-1];
    reg [63:0] entry_due_cycle [0:QUEUE_DEPTH-1];
    reg [63:0] entry_sequence [0:QUEUE_DEPTH-1];
    reg [63:0] cycle_count_q;
    reg [63:0] sequence_q;
    reg [63:0] token_bytes [0:PARTITIONS-1];
    reg [63:0] last_completion_cycle [0:PARTITIONS-1];
    reg [31:0] outstanding [0:PARTITIONS-1];
    reg [7:0] memory [longint unsigned];

    integer reset_index;
    integer partition_index;
    integer scan_index;
    integer byte_index;
    integer free_slot;
    integer due_slot;
    reg free_slot_valid;
    reg due_slot_valid;
    reg [63:0] selected_due_cycle;
    reg [63:0] selected_sequence;
    reg [63:0] request_due_cycle;
    reg [63:0] memory_key;
    reg [DATA_BYTES*8-1:0] read_data;
    wire partition_valid;
    wire address_valid;
    wire request_valid;
    wire request_accept;
    wire [PARTITION_BITS-1:0] safe_partition;

    assign partition_valid = (req_partition_i < PARTITIONS);
    assign address_valid = ((req_address_i % DATA_BYTES) == 0) &&
        ({1'b0, req_address_i} + DATA_BYTES <= CAPACITY_BYTES_PER_PARTITION);
    assign request_valid = partition_valid && address_valid;
    assign safe_partition = partition_valid ? req_partition_i : {PARTITION_BITS{1'b0}};
    assign req_error_o = req_valid_i && !request_valid;
    assign req_ready_o = request_valid && free_slot_valid &&
        (outstanding[safe_partition] < MAX_OUTSTANDING_PER_PARTITION) &&
        (token_bytes[safe_partition] >= DATA_BYTES);
    assign request_accept = req_valid_i && req_ready_o;

    initial begin
        if (PARTITIONS < 1 || (1 << PARTITION_BITS) < PARTITIONS) begin
            $fatal(1, "PARTITION_BITS cannot represent PARTITIONS");
        end
        if (ADDR_WIDTH > 63 || DATA_BYTES < 1 || (DATA_BYTES & (DATA_BYTES - 1)) != 0) begin
            $fatal(1, "address width or power-of-two DATA_BYTES is unsupported");
        end
        if (READ_LATENCY_CYCLES < 1 || WRITE_LATENCY_CYCLES < 1) begin
            $fatal(1, "HBM response latency must be positive");
        end
        if (PAYLOAD_BYTES_PER_CYCLE_PER_PARTITION < 1 ||
            MAX_OUTSTANDING_PER_PARTITION < 1 || QUEUE_DEPTH < PARTITIONS) begin
            $fatal(1, "HBM queue and bandwidth parameters are invalid");
        end
    end

    always @* begin
        free_slot = 0;
        free_slot_valid = 1'b0;
        due_slot = 0;
        due_slot_valid = 1'b0;
        selected_due_cycle = 64'hffff_ffff_ffff_ffff;
        selected_sequence = 64'hffff_ffff_ffff_ffff;
        for (scan_index = 0; scan_index < QUEUE_DEPTH; scan_index = scan_index + 1) begin
            if (!entry_valid[scan_index] && !free_slot_valid) begin
                free_slot = scan_index;
                free_slot_valid = 1'b1;
            end
            if (entry_valid[scan_index] && entry_due_cycle[scan_index] <= cycle_count_q &&
                ((entry_due_cycle[scan_index] < selected_due_cycle) ||
                 ((entry_due_cycle[scan_index] == selected_due_cycle) &&
                  (entry_sequence[scan_index] < selected_sequence)))) begin
                due_slot = scan_index;
                due_slot_valid = 1'b1;
                selected_due_cycle = entry_due_cycle[scan_index];
                selected_sequence = entry_sequence[scan_index];
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cycle_count_q <= 64'd0;
            sequence_q <= 64'd0;
            rsp_valid_o <= 1'b0;
            rsp_write_o <= 1'b0;
            rsp_partition_o <= {PARTITION_BITS{1'b0}};
            rsp_tag_o <= {TAG_WIDTH{1'b0}};
            rsp_read_data_o <= {(DATA_BYTES*8){1'b0}};
            rsp_status_o <= STATUS_OK;
            accepted_beats_o <= 64'd0;
            completed_beats_o <= 64'd0;
            backpressure_cycles_o <= 64'd0;
            memory.delete();
            for (reset_index = 0; reset_index < QUEUE_DEPTH; reset_index = reset_index + 1) begin
                entry_valid[reset_index] <= 1'b0;
                entry_write[reset_index] <= 1'b0;
                entry_partition[reset_index] <= {PARTITION_BITS{1'b0}};
                entry_address[reset_index] <= {ADDR_WIDTH{1'b0}};
                entry_tag[reset_index] <= {TAG_WIDTH{1'b0}};
                entry_write_data[reset_index] <= {(DATA_BYTES*8){1'b0}};
                entry_byte_enable[reset_index] <= {DATA_BYTES{1'b0}};
                entry_correctable[reset_index] <= 1'b0;
                entry_uncorrectable[reset_index] <= 1'b0;
                entry_due_cycle[reset_index] <= 64'd0;
                entry_sequence[reset_index] <= 64'd0;
            end
            for (partition_index = 0; partition_index < PARTITIONS; partition_index = partition_index + 1) begin
                token_bytes[partition_index] <= 64'd0;
                last_completion_cycle[partition_index] <= 64'd0;
                outstanding[partition_index] <= 32'd0;
            end
        end else begin
            cycle_count_q <= cycle_count_q + 64'd1;
            if (req_valid_i && !req_ready_o) backpressure_cycles_o <= backpressure_cycles_o + 64'd1;

            for (partition_index = 0; partition_index < PARTITIONS; partition_index = partition_index + 1) begin
                if (request_accept && req_partition_i == partition_index) begin
                    token_bytes[partition_index] <=
                        (((token_bytes[partition_index] + PAYLOAD_BYTES_PER_CYCLE_PER_PARTITION) > TOKEN_CAPACITY) ?
                         TOKEN_CAPACITY :
                         (token_bytes[partition_index] + PAYLOAD_BYTES_PER_CYCLE_PER_PARTITION)) - DATA_BYTES;
                end else begin
                    token_bytes[partition_index] <=
                        ((token_bytes[partition_index] + PAYLOAD_BYTES_PER_CYCLE_PER_PARTITION) > TOKEN_CAPACITY) ?
                        TOKEN_CAPACITY : token_bytes[partition_index] + PAYLOAD_BYTES_PER_CYCLE_PER_PARTITION;
                end
            end

            if (rsp_valid_o && rsp_ready_i) rsp_valid_o <= 1'b0;

            if ((!rsp_valid_o || rsp_ready_i) && due_slot_valid) begin
                rsp_valid_o <= 1'b1;
                rsp_write_o <= entry_write[due_slot];
                rsp_partition_o <= entry_partition[due_slot];
                rsp_tag_o <= entry_tag[due_slot];
                rsp_read_data_o <= {(DATA_BYTES*8){1'b0}};
                rsp_status_o <= STATUS_OK;
                memory_key = (entry_partition[due_slot] * CAPACITY_BYTES_PER_PARTITION) +
                    entry_address[due_slot];
                if (entry_write[due_slot]) begin
                    for (byte_index = 0; byte_index < DATA_BYTES; byte_index = byte_index + 1) begin
                        if (entry_byte_enable[due_slot][byte_index]) begin
                            memory[memory_key + byte_index] =
                                entry_write_data[due_slot][byte_index*8 +: 8];
                        end
                    end
                end else begin
                    read_data = {(DATA_BYTES*8){1'b0}};
                    for (byte_index = 0; byte_index < DATA_BYTES; byte_index = byte_index + 1) begin
                        if (memory.exists(memory_key + byte_index)) begin
                            read_data[byte_index*8 +: 8] = memory[memory_key + byte_index];
                        end
                    end
                    if (entry_uncorrectable[due_slot]) begin
                        rsp_read_data_o <= read_data ^ {{(DATA_BYTES*8-2){1'b0}}, 2'b11};
                        rsp_status_o <= STATUS_ECC_UNCORRECTABLE;
                    end else begin
                        rsp_read_data_o <= read_data;
                        if (entry_correctable[due_slot]) rsp_status_o <= STATUS_ECC_CORRECTED;
                    end
                end
                entry_valid[due_slot] <= 1'b0;
                outstanding[entry_partition[due_slot]] <=
                    outstanding[entry_partition[due_slot]] - 32'd1;
                completed_beats_o <= completed_beats_o + 64'd1;
            end

            if (request_accept) begin
                sequence_q <= sequence_q + 64'd1;
                request_due_cycle = cycle_count_q +
                    (req_write_i ? WRITE_LATENCY_CYCLES : READ_LATENCY_CYCLES);
                if (request_due_cycle < last_completion_cycle[req_partition_i]) begin
                    request_due_cycle = last_completion_cycle[req_partition_i];
                end
                last_completion_cycle[req_partition_i] <= request_due_cycle;
                entry_valid[free_slot] <= 1'b1;
                entry_write[free_slot] <= req_write_i;
                entry_partition[free_slot] <= req_partition_i;
                entry_address[free_slot] <= req_address_i;
                entry_tag[free_slot] <= req_tag_i;
                entry_write_data[free_slot] <= req_write_data_i;
                entry_byte_enable[free_slot] <= req_byte_enable_i;
                entry_correctable[free_slot] <= inject_correctable_i;
                entry_uncorrectable[free_slot] <= inject_uncorrectable_i;
                entry_due_cycle[free_slot] <= request_due_cycle;
                entry_sequence[free_slot] <= sequence_q;
                if (due_slot_valid && (!rsp_valid_o || rsp_ready_i) &&
                    entry_partition[due_slot] == req_partition_i) begin
                    outstanding[req_partition_i] <= outstanding[req_partition_i];
                end else begin
                    outstanding[req_partition_i] <= outstanding[req_partition_i] + 32'd1;
                end
                accepted_beats_o <= accepted_beats_o + 64'd1;
            end
        end
    end
endmodule
