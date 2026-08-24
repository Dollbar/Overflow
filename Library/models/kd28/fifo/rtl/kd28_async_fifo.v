`timescale 1ns/1ps // Define simulation time units for the asynchronous FIFO wrapper.
`default_nettype none // Reject accidental implicit nets in the FIFO source.

module kd28_async_fifo #( // Define a Gray-pointer ready-valid asynchronous FIFO.
    parameter DATA_WIDTH = 32, // Set the payload width and require a whole number of bytes.
    parameter DEPTH = 16, // Set a power-of-two logical FIFO capacity from 4 through 65536.
    parameter ADDR_WIDTH = (DEPTH <= 4) ? 2 : (DEPTH <= 8) ? 3 : (DEPTH <= 16) ? 4 : (DEPTH <= 32) ? 5 : (DEPTH <= 64) ? 6 : (DEPTH <= 128) ? 7 : (DEPTH <= 256) ? 8 : (DEPTH <= 512) ? 9 : (DEPTH <= 1024) ? 10 : (DEPTH <= 2048) ? 11 : (DEPTH <= 4096) ? 12 : (DEPTH <= 8192) ? 13 : (DEPTH <= 16384) ? 14 : (DEPTH <= 32768) ? 15 : 16 // Derive the address width through 65536 words.
) ( // Begin the asynchronous FIFO interface.
    input  wire                  write_clk_i, // Receive the producer clock.
    input  wire                  write_rst_n_i, // Receive the producer-domain active-low asynchronous reset.
    input  wire [DATA_WIDTH-1:0] write_data_i, // Receive the producer payload.
    input  wire                  write_valid_i, // Indicate a producer payload is available.
    output wire                  write_ready_o, // Indicate synchronized FIFO capacity is available.
    input  wire                  read_clk_i, // Receive the consumer clock.
    input  wire                  read_rst_n_i, // Receive the consumer-domain active-low asynchronous reset.
    output wire [DATA_WIDTH-1:0] read_data_o, // Present the registered consumer payload.
    output wire                  read_valid_o, // Indicate the registered consumer payload is valid.
    input  wire                  read_ready_i // Indicate the consumer accepts the current payload.
); // End the asynchronous FIFO interface.
    localparam PTR_WIDTH = ADDR_WIDTH + 1; // Add one wrap bit to each binary and Gray pointer.
    reg [PTR_WIDTH-1:0] write_bin_q; // Track the local binary write pointer.
    reg [PTR_WIDTH-1:0] write_gray_q; // Track the local Gray-coded write pointer.
    reg [PTR_WIDTH-1:0] read_bin_q; // Track the local binary read-issue pointer.
    reg [PTR_WIDTH-1:0] read_gray_q; // Track the local Gray-coded read-issue pointer.
    reg [PTR_WIDTH-1:0] read_consume_bin_q; // Track words actually accepted by the consumer.
    reg [PTR_WIDTH-1:0] read_consume_gray_q; // Track accepted words in Gray code for safe write-domain full detection.
    (* async_reg = "true" *) reg [PTR_WIDTH-1:0] read_gray_wsync1_q; // Hold the first consumed-pointer synchronizer stage in the write domain.
    (* async_reg = "true" *) reg [PTR_WIDTH-1:0] read_gray_wsync2_q; // Hold the second consumed-pointer synchronizer stage in the write domain.
    (* async_reg = "true" *) reg [PTR_WIDTH-1:0] write_gray_rsync1_q; // Hold the first write-pointer synchronizer stage in the read domain.
    (* async_reg = "true" *) reg [PTR_WIDTH-1:0] write_gray_rsync2_q; // Hold the second write-pointer synchronizer stage in the read domain.
    reg write_full_q; // Track the conservative write-domain full condition.
    reg read_pending_q; // Track one SRAM read whose data arrives after a read-clock edge.
    reg [DATA_WIDTH-1:0] output_data_q; // Hold the consumer payload stable during backpressure.
    reg output_valid_q; // Track validity of the registered consumer payload.
    wire write_fire; // Indicate one producer transfer in the write domain.
    wire [PTR_WIDTH-1:0] write_bin_next; // Carry the next binary write pointer.
    wire [PTR_WIDTH-1:0] write_gray_next; // Carry the next Gray-coded write pointer.
    wire write_full_next; // Predict full state after the optional current write.
    wire raw_empty; // Indicate no unread SRAM entry is visible in the read domain.
    wire read_fire; // Indicate one consumer transfer in the read domain.
    wire read_issue; // Request one registered SRAM read when the output path has room.
    wire [PTR_WIDTH-1:0] read_bin_next; // Carry the next binary read-issue pointer.
    wire [PTR_WIDTH-1:0] read_gray_next; // Carry the next Gray-coded read-issue pointer.
    wire [PTR_WIDTH-1:0] read_consume_bin_next; // Carry the next consumer-accepted binary pointer.
    wire [PTR_WIDTH-1:0] read_consume_gray_next; // Carry the next consumer-accepted Gray pointer.
    wire [DATA_WIDTH-1:0] sram_read_data; // Carry the registered SRAM read result.

    assign write_ready_o = !write_full_q; // Apply producer backpressure from synchronized Gray pointers.
    assign write_fire = write_valid_i && write_ready_o; // Form the write-domain producer transfer.
    assign write_bin_next = write_bin_q + write_fire; // Advance the binary write pointer only after a transfer.
    assign write_gray_next = (write_bin_next >> 1) ^ write_bin_next; // Convert the next binary write pointer to Gray code.
    assign write_full_next = (write_gray_next == {~read_gray_wsync2_q[PTR_WIDTH-1:PTR_WIDTH-2], read_gray_wsync2_q[PTR_WIDTH-3:0]}); // Detect one complete write-pointer lap over the synchronized read pointer.
    assign raw_empty = (read_gray_q == write_gray_rsync2_q); // Compare local read issue position with the synchronized write position.
    assign read_data_o = output_data_q; // Drive the consumer payload from the output register.
    assign read_valid_o = output_valid_q; // Drive consumer validity from registered state.
    assign read_fire = output_valid_q && read_ready_i; // Form the read-domain consumer transfer.
    assign read_issue = !read_pending_q && (!output_valid_q || read_fire) && !raw_empty; // Issue a read only when its result can be staged safely.
    assign read_bin_next = read_bin_q + read_issue; // Advance the binary read pointer only after issuing SRAM access.
    assign read_gray_next = (read_bin_next >> 1) ^ read_bin_next; // Convert the next binary read pointer to Gray code.
    assign read_consume_bin_next = read_consume_bin_q + read_fire; // Advance capacity only after the consumer accepts a word.
    assign read_consume_gray_next = (read_consume_bin_next >> 1) ^ read_consume_bin_next; // Convert accepted occupancy to Gray code.

    kd28_fifo_sdp_storage_map #( // Map logical dual-clock storage onto fixed KD28 SDP SRAM cells.
        .DATA_WIDTH(DATA_WIDTH), // Match SRAM word width to the FIFO payload.
        .DEPTH(DEPTH), // Match SRAM depth to the logical FIFO capacity.
        .ADDR_WIDTH(ADDR_WIDTH) // Pass the derived address width to storage.
    ) u_storage ( // Bind both asynchronous domains to the fixed-macro storage mapper.
        .write_clk_i(write_clk_i), // Use the producer clock for SRAM writes.
        .write_cs_i(write_fire), // Write storage only after a producer handshake.
        .write_addr_i(write_bin_q[ADDR_WIDTH-1:0]), // Address the next free circular FIFO word.
        .write_data_i(write_data_i), // Store the accepted producer payload.
        .read_clk_i(read_clk_i), // Use the consumer clock for SRAM reads.
        .read_cs_i(read_issue), // Read storage only for a safe prefetch request.
        .read_addr_i(read_bin_q[ADDR_WIDTH-1:0]), // Address the oldest unread circular FIFO word.
        .read_data_o(sram_read_data) // Receive the registered SRAM word in the read domain.
    ); // End the KD28 SRAM instance.

    always @(posedge write_clk_i or negedge write_rst_n_i) begin // Update write pointers and synchronized read state.
        if (!write_rst_n_i) begin // Clear all write-domain FIFO state.
            write_bin_q <= {PTR_WIDTH{1'b0}}; // Restart binary writes at address zero.
            write_gray_q <= {PTR_WIDTH{1'b0}}; // Restart Gray-coded writes at address zero.
            read_gray_wsync1_q <= {PTR_WIDTH{1'b0}}; // Clear the first read-pointer synchronizer stage.
            read_gray_wsync2_q <= {PTR_WIDTH{1'b0}}; // Clear the second read-pointer synchronizer stage.
            write_full_q <= 1'b0; // Mark synchronized write capacity available.
        end else begin // Process normal write-domain activity.
            read_gray_wsync1_q <= read_consume_gray_q; // Sample the consumed Gray pointer into the write domain.
            read_gray_wsync2_q <= read_gray_wsync1_q; // Complete the consumed-pointer synchronization.
            write_bin_q <= write_bin_next; // Save the next binary write position.
            write_gray_q <= write_gray_next; // Save the next Gray-coded write position.
            write_full_q <= write_full_next; // Save the predicted full state.
        end // End the write-domain reset selection.
    end // End the write-domain FIFO process.

    always @(posedge read_clk_i or negedge read_rst_n_i) begin // Update read pointers, synchronized write state, and output staging.
        if (!read_rst_n_i) begin // Clear all read-domain FIFO state.
            read_bin_q <= {PTR_WIDTH{1'b0}}; // Restart binary reads at address zero.
            read_gray_q <= {PTR_WIDTH{1'b0}}; // Restart Gray-coded reads at address zero.
            read_consume_bin_q <= {PTR_WIDTH{1'b0}}; // Restart consumer accounting at address zero.
            read_consume_gray_q <= {PTR_WIDTH{1'b0}}; // Restart Gray-coded consumer accounting at address zero.
            write_gray_rsync1_q <= {PTR_WIDTH{1'b0}}; // Clear the first write-pointer synchronizer stage.
            write_gray_rsync2_q <= {PTR_WIDTH{1'b0}}; // Clear the second write-pointer synchronizer stage.
            read_pending_q <= 1'b0; // Discard any pre-reset SRAM read pipeline state.
            output_data_q <= {DATA_WIDTH{1'b0}}; // Clear the externally visible payload register.
            output_valid_q <= 1'b0; // Mark the externally visible payload invalid.
        end else begin // Process normal read-domain activity.
            write_gray_rsync1_q <= write_gray_q; // Sample the Gray write pointer into the read domain.
            write_gray_rsync2_q <= write_gray_rsync1_q; // Complete the two-stage pointer synchronization.
            read_bin_q <= read_bin_next; // Save the next binary read-issue position.
            read_gray_q <= read_gray_next; // Save the next Gray-coded read-issue position.
            read_consume_bin_q <= read_consume_bin_next; // Save the number of words accepted by the consumer.
            read_consume_gray_q <= read_consume_gray_next; // Save the accepted-word pointer for CDC synchronization.
            read_pending_q <= read_issue; // Delay the SRAM read request by its one-cycle latency.
            if (read_pending_q) begin // Capture an SRAM result from the previous read request.
                output_data_q <= sram_read_data; // Replace the output register with the next FIFO word.
                output_valid_q <= 1'b1; // Mark the captured output word valid.
            end else if (read_fire) begin // Clear an output word when no replacement arrives.
                output_valid_q <= 1'b0; // Mark the output register empty after consumption.
            end // End the output staging update.
        end // End the read-domain reset selection.
    end // End the read-domain FIFO process.
endmodule // End the kd28_async_fifo module.

`default_nettype wire // Restore implicit-net behavior for downstream source files.
