`timescale 1ns/1ps // Define simulation time units for the synchronous FIFO wrapper.
`default_nettype none // Reject accidental implicit nets in the FIFO source.

module kd28_sync_fifo #( // Define a parameterized ready-valid synchronous FIFO.
    parameter DATA_WIDTH = 32, // Set the payload width and require a whole number of bytes.
    parameter DEPTH = 16, // Set the exact logical FIFO capacity in words.
    parameter ADDR_WIDTH = (DEPTH <= 2) ? 1 : (DEPTH <= 4) ? 2 : (DEPTH <= 8) ? 3 : (DEPTH <= 16) ? 4 : (DEPTH <= 32) ? 5 : (DEPTH <= 64) ? 6 : (DEPTH <= 128) ? 7 : (DEPTH <= 256) ? 8 : (DEPTH <= 512) ? 9 : (DEPTH <= 1024) ? 10 : (DEPTH <= 2048) ? 11 : (DEPTH <= 4096) ? 12 : (DEPTH <= 8192) ? 13 : (DEPTH <= 16384) ? 14 : (DEPTH <= 32768) ? 15 : 16, // Derive storage address width through 65536 words.
    parameter COUNT_WIDTH = ADDR_WIDTH + 1 // Size logical and stored-word counters.
) ( // Begin the synchronous FIFO interface.
    input  wire                  clk_i, // Receive the shared write and read clock.
    input  wire                  rst_n_i, // Receive the active-low asynchronous FIFO reset.
    input  wire [DATA_WIDTH-1:0] write_data_i, // Receive the producer payload.
    input  wire                  write_valid_i, // Indicate a producer payload is available.
    output wire                  write_ready_o, // Indicate logical FIFO capacity is available.
    output wire [DATA_WIDTH-1:0] read_data_o, // Present the registered consumer payload.
    output wire                  read_valid_o, // Indicate the registered consumer payload is valid.
    input  wire                  read_ready_i // Indicate the consumer accepts the current payload.
); // End the synchronous FIFO interface.
    localparam MASK_WIDTH = DATA_WIDTH / 8; // Provide one active write mask per payload byte.
    reg [ADDR_WIDTH-1:0] write_ptr_q; // Track the next SRAM write address.
    reg [ADDR_WIDTH-1:0] read_ptr_q; // Track the next SRAM read address to issue.
    reg [COUNT_WIDTH-1:0] total_count_q; // Track all logical words including staged output data.
    reg [COUNT_WIDTH-1:0] stored_count_q; // Track SRAM words not yet issued to the read pipeline.
    reg read_pending_q; // Track one SRAM read whose data arrives after the active edge.
    reg [DATA_WIDTH-1:0] output_data_q; // Hold the consumer payload stable during backpressure.
    reg output_valid_q; // Track validity of the registered consumer payload.
    wire write_fire; // Indicate one producer transfer on this edge.
    wire read_fire; // Indicate one consumer transfer on this edge.
    wire read_issue; // Request one registered SRAM read when the output path has room.
    wire [DATA_WIDTH-1:0] sram_read_data; // Carry the registered SRAM read result.

    assign write_ready_o = (total_count_q < DEPTH); // Apply backpressure at the exact configured capacity.
    assign write_fire = write_valid_i && write_ready_o; // Form the producer transfer event.
    assign read_data_o = output_data_q; // Drive the consumer payload from the output register.
    assign read_valid_o = output_valid_q; // Drive consumer validity from registered state.
    assign read_fire = output_valid_q && read_ready_i; // Form the consumer transfer event.
    assign read_issue = !read_pending_q && (!output_valid_q || read_fire) && (stored_count_q != {COUNT_WIDTH{1'b0}}); // Issue a read only when its result can be staged safely.

    kd28_sram_sdp_model #( // Instantiate the KD28 simple-dual-port storage model.
        .DATA_WIDTH(DATA_WIDTH), // Match SRAM word width to the FIFO payload.
        .DEPTH(DEPTH), // Match SRAM depth to the logical FIFO capacity.
        .ADDR_WIDTH(ADDR_WIDTH), // Pass the derived address width to storage.
        .MASK_WIDTH(MASK_WIDTH) // Enable every complete payload byte.
    ) u_storage ( // Bind the synchronous FIFO to the KD28 SRAM model.
        .write_clk_i(clk_i), // Use the FIFO clock for SRAM writes.
        .write_cs_i(write_fire), // Write storage only after a producer handshake.
        .write_addr_i(write_ptr_q), // Address the next free FIFO word.
        .write_data_i(write_data_i), // Store the accepted producer payload.
        .write_mask_i({MASK_WIDTH{1'b1}}), // Enable every payload byte on each FIFO write.
        .read_clk_i(clk_i), // Use the FIFO clock for SRAM reads.
        .read_cs_i(read_issue), // Read storage only for a safe prefetch request.
        .read_addr_i(read_ptr_q), // Address the oldest unread SRAM word.
        .read_data_o(sram_read_data) // Receive the registered SRAM word.
    ); // End the KD28 SRAM instance.

    always @(posedge clk_i or negedge rst_n_i) begin // Update FIFO pointers, counts, and output staging.
        if (!rst_n_i) begin // Clear all visible FIFO state while preserving SRAM contents.
            write_ptr_q <= {ADDR_WIDTH{1'b0}}; // Restart writes at address zero.
            read_ptr_q <= {ADDR_WIDTH{1'b0}}; // Restart read issue at address zero.
            total_count_q <= {COUNT_WIDTH{1'b0}}; // Mark the logical FIFO empty.
            stored_count_q <= {COUNT_WIDTH{1'b0}}; // Mark SRAM as containing no valid FIFO words.
            read_pending_q <= 1'b0; // Discard any pre-reset read pipeline state.
            output_data_q <= {DATA_WIDTH{1'b0}}; // Clear the externally visible payload register.
            output_valid_q <= 1'b0; // Mark the externally visible payload invalid.
        end else begin // Process producer, SRAM, and consumer events.
            read_pending_q <= read_issue; // Delay the SRAM read request by its one-cycle latency.
            if (write_fire) begin // Advance the circular write pointer after an accepted word.
                if (write_ptr_q == DEPTH - 1) begin // Detect the configured final storage address.
                    write_ptr_q <= {ADDR_WIDTH{1'b0}}; // Wrap the write pointer to address zero.
                end else begin // Handle a non-wrapping write pointer increment.
                    write_ptr_q <= write_ptr_q + 1'b1; // Advance to the next storage word.
                end // End the write pointer wrap selection.
            end // End the accepted write branch.
            if (read_issue) begin // Advance the circular read pointer after issuing a read.
                if (read_ptr_q == DEPTH - 1) begin // Detect the configured final storage address.
                    read_ptr_q <= {ADDR_WIDTH{1'b0}}; // Wrap the read pointer to address zero.
                end else begin // Handle a non-wrapping read pointer increment.
                    read_ptr_q <= read_ptr_q + 1'b1; // Advance to the next unread storage word.
                end // End the read pointer wrap selection.
            end // End the issued read branch.
            case ({write_fire, read_fire}) // Update logical occupancy for independent producer and consumer events.
                2'b10: total_count_q <= total_count_q + 1'b1; // Count one newly accepted word.
                2'b01: total_count_q <= total_count_q - 1'b1; // Remove one consumed word.
                default: total_count_q <= total_count_q; // Preserve occupancy for idle or balanced transfers.
            endcase // End the logical occupancy update.
            case ({write_fire, read_issue}) // Update the number of valid words still resident in SRAM.
                2'b10: stored_count_q <= stored_count_q + 1'b1; // Add one accepted word to unread storage.
                2'b01: stored_count_q <= stored_count_q - 1'b1; // Remove one word issued to the read pipeline.
                default: stored_count_q <= stored_count_q; // Preserve stored occupancy for idle or balanced events.
            endcase // End the stored-word occupancy update.
            if (read_pending_q) begin // Capture an SRAM result from the previous read request.
                output_data_q <= sram_read_data; // Replace the output register with the next FIFO word.
                output_valid_q <= 1'b1; // Mark the captured output word valid.
            end else if (read_fire) begin // Clear an output word when no replacement arrives.
                output_valid_q <= 1'b0; // Mark the output register empty after consumption.
            end // End the output staging update.
        end // End the reset or normal-operation selection.
    end // End the synchronous FIFO state process.
endmodule // End the kd28_sync_fifo module.

`default_nettype wire // Restore implicit-net behavior for downstream source files.
