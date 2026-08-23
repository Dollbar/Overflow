`timescale 1ns/1ps // Define simulation time units for the portable SRAM model.
`default_nettype none // Reject accidental implicit nets in the SRAM source.

module kd28_sram_sp_model #( // Define a parameterized one-port synchronous SRAM model.
    parameter DATA_WIDTH = 32, // Set the stored word width in bits.
    parameter DEPTH = 256, // Set the number of addressable words.
    parameter ADDR_WIDTH = 8, // Set the address width required by DEPTH.
    parameter MASK_WIDTH = DATA_WIDTH / 8 // Set one active-high write mask per byte.
) ( // Begin the single-port SRAM interface.
    input  wire                  clk_i, // Receive the shared read and write clock.
    input  wire                  cs_i, // Enable a memory operation on this rising edge.
    input  wire                  we_i, // Select write when high and read when low.
    input  wire [ADDR_WIDTH-1:0] addr_i, // Select the word address for this operation.
    input  wire [DATA_WIDTH-1:0] wdata_i, // Receive write data for enabled byte lanes.
    input  wire [MASK_WIDTH-1:0] wmask_i, // Enable individual byte writes with high bits.
    output reg  [DATA_WIDTH-1:0] rdata_o // Hold the most recently registered read word.
); // End the single-port SRAM interface.
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1]; // Store the modeled SRAM contents without reset clearing.
    wire [DATA_WIDTH-1:0] write_bit_mask; // Expand active byte enables across all data bits.
    genvar mask_lane; // Identify one byte lane during elaboration.
    generate // Expand every mask bit without sequential loop variables.
        for (mask_lane = 0; mask_lane < MASK_WIDTH; mask_lane = mask_lane + 1) begin : gen_write_bit_mask // Visit every byte lane.
            assign write_bit_mask[mask_lane*8 +: 8] = {8{wmask_i[mask_lane]}}; // Replicate one byte enable across eight bits.
        end // End one generated mask lane.
    endgenerate // End the byte-mask expansion.

    always @(posedge clk_i) begin // Perform one synchronous memory operation per clock edge.
        if (cs_i) begin // Ignore the port while chip select is low.
            if (we_i) begin // Apply enabled byte lanes for a write operation.
                memory[addr_i] <= (memory[addr_i] & ~write_bit_mask) | (wdata_i & write_bit_mask); // Commit one masked word update.
            end else begin // Perform a registered synchronous read.
                rdata_o <= memory[addr_i]; // Capture the addressed word after the active edge.
            end // End the read or write selection.
        end // End the chip-select branch.
    end // End the synchronous memory process.
endmodule // End the kd28_sram_sp_model module.

`default_nettype wire // Restore implicit-net behavior for downstream source files.
