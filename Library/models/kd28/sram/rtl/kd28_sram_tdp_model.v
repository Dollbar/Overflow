`timescale 1ns/1ps // Define simulation time units for the portable SRAM model.
`default_nettype none // Reject accidental implicit nets in the SRAM source.

module kd28_sram_tdp_model #( // Define a parameterized true-dual-port synchronous SRAM model.
    parameter DATA_WIDTH = 32, // Set the stored word width in bits.
    parameter DEPTH = 256, // Set the number of addressable words.
    parameter ADDR_WIDTH = 8, // Set the address width required by DEPTH.
    parameter MASK_WIDTH = DATA_WIDTH / 8 // Set one active-high write mask per byte.
) ( // Begin the shared-clock true-dual-port interface.
    input  wire                  clk_i, // Receive the shared clock for both ports.
    input  wire                  a_cs_i, // Enable port A on this rising edge.
    input  wire                  a_we_i, // Select a port A write when high.
    input  wire [ADDR_WIDTH-1:0] a_addr_i, // Select the port A word address.
    input  wire [DATA_WIDTH-1:0] a_wdata_i, // Receive port A write data.
    input  wire [MASK_WIDTH-1:0] a_wmask_i, // Enable individual port A byte writes.
    output reg  [DATA_WIDTH-1:0] a_rdata_o, // Hold the most recently registered port A read.
    input  wire                  b_cs_i, // Enable port B on this rising edge.
    input  wire                  b_we_i, // Select a port B write when high.
    input  wire [ADDR_WIDTH-1:0] b_addr_i, // Select the port B word address.
    input  wire [DATA_WIDTH-1:0] b_wdata_i, // Receive port B write data.
    input  wire [MASK_WIDTH-1:0] b_wmask_i, // Enable individual port B byte writes.
    output reg  [DATA_WIDTH-1:0] b_rdata_o // Hold the most recently registered port B read.
); // End the true-dual-port SRAM interface.
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1]; // Store the modeled SRAM contents without reset clearing.
    wire [DATA_WIDTH-1:0] a_write_bit_mask; // Expand port A byte enables across all data bits.
    wire [DATA_WIDTH-1:0] b_write_bit_mask; // Expand port B byte enables across all data bits.
    genvar mask_lane; // Identify one byte lane during elaboration.
    generate // Expand both port masks without sequential loop variables.
        for (mask_lane = 0; mask_lane < MASK_WIDTH; mask_lane = mask_lane + 1) begin : gen_write_bit_masks // Visit every byte lane.
            assign a_write_bit_mask[mask_lane*8 +: 8] = {8{a_wmask_i[mask_lane]}}; // Replicate one port A byte enable across eight bits.
            assign b_write_bit_mask[mask_lane*8 +: 8] = {8{b_wmask_i[mask_lane]}}; // Replicate one port B byte enable across eight bits.
        end // End one generated mask lane.
    endgenerate // End both byte-mask expansions.

    always @(posedge clk_i) begin // Perform both port operations on the shared rising edge.
        if (a_cs_i) begin // Ignore port A while its chip select is low.
            if (a_we_i) begin // Apply enabled byte lanes for a port A write.
                memory[a_addr_i] <= (memory[a_addr_i] & ~a_write_bit_mask) | (a_wdata_i & a_write_bit_mask); // Commit one masked port A word.
            end else begin // Perform a registered port A read.
                a_rdata_o <= memory[a_addr_i]; // Capture the previous addressed word for port A.
            end // End the port A read or write selection.
        end // End the port A chip-select branch.
        if (b_cs_i) begin // Ignore port B while its chip select is low.
            if (b_we_i) begin // Apply enabled byte lanes for a port B write.
                memory[b_addr_i] <= (memory[b_addr_i] & ~b_write_bit_mask) | (b_wdata_i & b_write_bit_mask); // Commit one masked port B word.
            end else begin // Perform a registered port B read.
                b_rdata_o <= memory[b_addr_i]; // Capture the previous addressed word for port B.
            end // End the port B read or write selection.
        end // End the port B chip-select branch.
    end // End the shared-clock memory process.
endmodule // End the kd28_sram_tdp_model module.

`default_nettype wire // Restore implicit-net behavior for downstream source files.
