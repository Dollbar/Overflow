`timescale 1ns/1ps // Define simulation time units for the portable SRAM model.
`default_nettype none // Reject accidental implicit nets in the SRAM source.

module kd28_sram_sdp_model #( // Define a parameterized simple-dual-port synchronous SRAM model.
    parameter DATA_WIDTH = 32, // Set the stored word width in bits.
    parameter DEPTH = 256, // Set the number of addressable words.
    parameter ADDR_WIDTH = 8, // Set the address width required by DEPTH.
    parameter MASK_WIDTH = DATA_WIDTH / 8 // Set one active-high write mask per byte.
) ( // Begin the independent write and read port interface.
    input  wire                  write_clk_i, // Receive the write-port clock.
    input  wire                  write_cs_i, // Enable a write-port operation on this edge.
    input  wire [ADDR_WIDTH-1:0] write_addr_i, // Select the write word address.
    input  wire [DATA_WIDTH-1:0] write_data_i, // Receive write data for enabled byte lanes.
    input  wire [MASK_WIDTH-1:0] write_mask_i, // Enable individual byte writes with high bits.
    input  wire                  read_clk_i, // Receive the read-port clock.
    input  wire                  read_cs_i, // Enable a registered read on this edge.
    input  wire [ADDR_WIDTH-1:0] read_addr_i, // Select the read word address.
    output reg  [DATA_WIDTH-1:0] read_data_o // Hold the most recently registered read word.
); // End the simple-dual-port SRAM interface.
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1]; // Store the modeled SRAM contents across both clock domains.
    wire [DATA_WIDTH-1:0] write_bit_mask; // Expand active byte enables across all data bits.
    genvar mask_lane; // Identify one byte lane during elaboration.
    generate // Expand every mask bit without sequential loop variables.
        for (mask_lane = 0; mask_lane < MASK_WIDTH; mask_lane = mask_lane + 1) begin : gen_write_bit_mask // Visit every byte lane.
            assign write_bit_mask[mask_lane*8 +: 8] = {8{write_mask_i[mask_lane]}}; // Replicate one byte enable across eight bits.
        end // End one generated mask lane.
    endgenerate // End the byte-mask expansion.

    always @(posedge write_clk_i) begin // Apply writes only in the write clock domain.
        if (write_cs_i) begin // Ignore the write port while chip select is low.
            memory[write_addr_i] <= (memory[write_addr_i] & ~write_bit_mask) | (write_data_i & write_bit_mask); // Commit one masked word update.
        end // End the write chip-select branch.
    end // End the write-domain process.

    always @(posedge read_clk_i) begin // Capture reads only in the read clock domain.
        if (read_cs_i) begin // Preserve the previous output while read chip select is low.
            read_data_o <= memory[read_addr_i]; // Register the addressed word with read-before-write behavior.
        end // End the read chip-select branch.
    end // End the read-domain process.
endmodule // End the kd28_sram_sdp_model module.

`default_nettype wire // Restore implicit-net behavior for downstream source files.
