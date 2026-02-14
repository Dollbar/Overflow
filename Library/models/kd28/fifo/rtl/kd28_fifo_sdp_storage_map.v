`timescale 1ns/1ps // Define simulation time units for the fixed-macro FIFO storage mapper.
`default_nettype none // Reject accidental implicit nets in the storage mapper source.

module kd28_fifo_sdp_storage_map #( // Map one logical FIFO memory onto fixed KD28 SDP SRAM cells.
    parameter DATA_WIDTH = 32, // Set the byte-addressable logical FIFO payload width.
    parameter DEPTH = 16, // Set the logical number of FIFO storage words.
    parameter ADDR_WIDTH = (DEPTH <= 2) ? 1 : (DEPTH <= 4) ? 2 : (DEPTH <= 8) ? 3 : (DEPTH <= 16) ? 4 : (DEPTH <= 32) ? 5 : (DEPTH <= 64) ? 6 : (DEPTH <= 128) ? 7 : (DEPTH <= 256) ? 8 : (DEPTH <= 512) ? 9 : (DEPTH <= 1024) ? 10 : (DEPTH <= 2048) ? 11 : (DEPTH <= 4096) ? 12 : (DEPTH <= 8192) ? 13 : (DEPTH <= 16384) ? 14 : (DEPTH <= 32768) ? 15 : 16 // Derive the logical address width through 65536 words.
) ( // Begin the logical simple-dual-port storage interface.
    input  wire                  write_clk_i, // Receive the FIFO producer clock.
    input  wire                  write_cs_i, // Enable one complete logical-word write.
    input  wire [ADDR_WIDTH-1:0] write_addr_i, // Select the logical write address.
    input  wire [DATA_WIDTH-1:0] write_data_i, // Receive the logical write payload.
    input  wire                  read_clk_i, // Receive the FIFO consumer clock.
    input  wire                  read_cs_i, // Enable one registered logical-word read.
    input  wire [ADDR_WIDTH-1:0] read_addr_i, // Select the logical read address.
    output wire [DATA_WIDTH-1:0] read_data_o // Return one registered word from the selected SRAM bank.
); // End the logical storage interface.
    localparam MACRO_DEPTH = (DEPTH <= 256) ? 256 : (DEPTH <= 512) ? 512 : (DEPTH <= 1024) ? 1024 : 2048; // Select the fixed macro depth from logical depth.
    localparam MACRO_WIDTH = (DEPTH <= 256) ? 32 : (DEPTH <= 512) ? 64 : (DEPTH <= 1024) ? 128 : 256; // Select the paired fixed macro word width.
    localparam MACRO_ADDR_WIDTH = (MACRO_DEPTH == 256) ? 8 : (MACRO_DEPTH == 512) ? 9 : (MACRO_DEPTH == 1024) ? 10 : 11; // Derive the selected fixed macro address width.
    localparam MACRO_MASK_WIDTH = MACRO_WIDTH / 8; // Derive the selected fixed macro byte-mask width.
    localparam WIDTH_TILES = (DATA_WIDTH + MACRO_WIDTH - 1) / MACRO_WIDTH; // Count fixed macros required to cover one logical word.
    localparam DEPTH_BANKS = (DEPTH + MACRO_DEPTH - 1) / MACRO_DEPTH; // Count fixed macro banks required to cover logical depth.
    localparam PHYSICAL_WIDTH = WIDTH_TILES * MACRO_WIDTH; // Determine the padded physical word width across all lanes.
    localparam BANK_WIDTH = (DEPTH_BANKS <= 2) ? 1 : (DEPTH_BANKS <= 4) ? 2 : (DEPTH_BANKS <= 8) ? 3 : (DEPTH_BANKS <= 16) ? 4 : 5; // Derive the bank-select width through 32 banks.
    localparam MAPPED_ADDR_WIDTH = MACRO_ADDR_WIDTH + BANK_WIDTH; // Cover the fixed row and every possible bank-select bit.
    wire [MAPPED_ADDR_WIDTH-1:0] write_address_extended; // Normalize the logical write address to the mapped array width.
    wire [MAPPED_ADDR_WIDTH-1:0] read_address_extended; // Normalize the logical read address to the mapped array width.
    wire [MACRO_ADDR_WIDTH-1:0] macro_write_address; // Select the row within one fixed write bank.
    wire [MACRO_ADDR_WIDTH-1:0] macro_read_address; // Select the row within one fixed read bank.
    wire [BANK_WIDTH-1:0] write_bank_select; // Select the fixed bank receiving a write.
    wire [BANK_WIDTH-1:0] read_bank_select; // Select the fixed bank receiving a read.
    reg [BANK_WIDTH-1:0] read_bank_q; // Retain the bank associated with the registered SRAM result.
    wire [PHYSICAL_WIDTH-1:0] write_data_padded; // Pad the logical write word through the final physical lane.
    wire [DEPTH_BANKS*PHYSICAL_WIDTH-1:0] bank_read_data; // Collect every fixed bank and lane read output.
    wire [DEPTH_BANKS-1:0] write_bank_enable; // Enable writes only in the selected fixed bank.
    wire [DEPTH_BANKS-1:0] read_bank_enable; // Enable reads only in the selected fixed bank.

    assign write_address_extended = {{(MAPPED_ADDR_WIDTH-ADDR_WIDTH){1'b0}}, write_addr_i}; // Zero-extend the logical write address.
    assign read_address_extended = {{(MAPPED_ADDR_WIDTH-ADDR_WIDTH){1'b0}}, read_addr_i}; // Zero-extend the logical read address.
    assign macro_write_address = write_address_extended[MACRO_ADDR_WIDTH-1:0]; // Extract the fixed-bank write row.
    assign macro_read_address = read_address_extended[MACRO_ADDR_WIDTH-1:0]; // Extract the fixed-bank read row.
    assign write_bank_select = write_address_extended[MACRO_ADDR_WIDTH +: BANK_WIDTH]; // Extract the logical write bank index.
    assign read_bank_select = read_address_extended[MACRO_ADDR_WIDTH +: BANK_WIDTH]; // Extract the logical read bank index.
    assign write_data_padded = {{(PHYSICAL_WIDTH-DATA_WIDTH){1'b0}}, write_data_i}; // Fill unused upper physical bits with zeros.
    assign read_data_o = bank_read_data[(read_bank_q*PHYSICAL_WIDTH) +: DATA_WIDTH]; // Select the registered bank and discard padded upper lanes.

    always @(posedge read_clk_i) begin // Align bank selection with the fixed macro registered read result.
        if (read_cs_i) begin // Update the output bank only for an issued logical read.
            read_bank_q <= read_bank_select; // Retain the bank whose SRAM output updates after this edge.
        end // End the issued-read branch.
    end // End the registered read-bank selection process.

    genvar bank_index; // Identify one fixed depth bank during elaboration.
    genvar lane_index; // Identify one fixed width lane during elaboration.
    generate // Build the selected fixed SDP macro array.
        for (bank_index = 0; bank_index < DEPTH_BANKS; bank_index = bank_index + 1) begin : gen_depth_bank // Replicate fixed banks through logical depth.
            assign write_bank_enable[bank_index] = write_cs_i && (write_bank_select == bank_index); // Decode one logical write bank.
            assign read_bank_enable[bank_index] = read_cs_i && (read_bank_select == bank_index); // Decode one logical read bank.
            for (lane_index = 0; lane_index < WIDTH_TILES; lane_index = lane_index + 1) begin : gen_width_lane // Replicate fixed macros through logical width.
                if (MACRO_DEPTH == 256) begin : gen_sdp_256x32 // Select the smallest fixed SDP macro class.
                    KD28_SRAM_SDP_256X32 u_sram ( // Instantiate one 256-word by 32-bit fixed KD28 SRAM.
                        .WCLK(write_clk_i), // Connect the independent FIFO write clock.
                        .WCS(write_bank_enable[bank_index]), // Enable writes only for this decoded bank.
                        .WA(macro_write_address), // Address one row within this fixed bank.
                        .D(write_data_padded[lane_index*MACRO_WIDTH +: MACRO_WIDTH]), // Drive one padded logical width lane.
                        .WM({MACRO_MASK_WIDTH{1'b1}}), // Enable every byte for complete FIFO word writes.
                        .RCLK(read_clk_i), // Connect the independent FIFO read clock.
                        .RCS(read_bank_enable[bank_index]), // Enable reads only for this decoded bank.
                        .RA(macro_read_address), // Address one row within this fixed bank.
                        .Q(bank_read_data[(bank_index*PHYSICAL_WIDTH)+(lane_index*MACRO_WIDTH) +: MACRO_WIDTH]) // Collect one registered width lane.
                    ); // End the 256-word fixed SRAM instance.
                end else if (MACRO_DEPTH == 512) begin : gen_sdp_512x64 // Select the medium-small fixed SDP macro class.
                    KD28_SRAM_SDP_512X64 u_sram ( // Instantiate one 512-word by 64-bit fixed KD28 SRAM.
                        .WCLK(write_clk_i), // Connect the independent FIFO write clock.
                        .WCS(write_bank_enable[bank_index]), // Enable writes only for this decoded bank.
                        .WA(macro_write_address), // Address one row within this fixed bank.
                        .D(write_data_padded[lane_index*MACRO_WIDTH +: MACRO_WIDTH]), // Drive one padded logical width lane.
                        .WM({MACRO_MASK_WIDTH{1'b1}}), // Enable every byte for complete FIFO word writes.
                        .RCLK(read_clk_i), // Connect the independent FIFO read clock.
                        .RCS(read_bank_enable[bank_index]), // Enable reads only for this decoded bank.
                        .RA(macro_read_address), // Address one row within this fixed bank.
                        .Q(bank_read_data[(bank_index*PHYSICAL_WIDTH)+(lane_index*MACRO_WIDTH) +: MACRO_WIDTH]) // Collect one registered width lane.
                    ); // End the 512-word fixed SRAM instance.
                end else if (MACRO_DEPTH == 1024) begin : gen_sdp_1024x128 // Select the medium-large fixed SDP macro class.
                    KD28_SRAM_SDP_1024X128 u_sram ( // Instantiate one 1024-word by 128-bit fixed KD28 SRAM.
                        .WCLK(write_clk_i), // Connect the independent FIFO write clock.
                        .WCS(write_bank_enable[bank_index]), // Enable writes only for this decoded bank.
                        .WA(macro_write_address), // Address one row within this fixed bank.
                        .D(write_data_padded[lane_index*MACRO_WIDTH +: MACRO_WIDTH]), // Drive one padded logical width lane.
                        .WM({MACRO_MASK_WIDTH{1'b1}}), // Enable every byte for complete FIFO word writes.
                        .RCLK(read_clk_i), // Connect the independent FIFO read clock.
                        .RCS(read_bank_enable[bank_index]), // Enable reads only for this decoded bank.
                        .RA(macro_read_address), // Address one row within this fixed bank.
                        .Q(bank_read_data[(bank_index*PHYSICAL_WIDTH)+(lane_index*MACRO_WIDTH) +: MACRO_WIDTH]) // Collect one registered width lane.
                    ); // End the 1024-word fixed SRAM instance.
                end else begin : gen_sdp_2048x256 // Select the largest fixed SDP macro class and bank it as required.
                    KD28_SRAM_SDP_2048X256 u_sram ( // Instantiate one 2048-word by 256-bit fixed KD28 SRAM.
                        .WCLK(write_clk_i), // Connect the independent FIFO write clock.
                        .WCS(write_bank_enable[bank_index]), // Enable writes only for this decoded bank.
                        .WA(macro_write_address), // Address one row within this fixed bank.
                        .D(write_data_padded[lane_index*MACRO_WIDTH +: MACRO_WIDTH]), // Drive one padded logical width lane.
                        .WM({MACRO_MASK_WIDTH{1'b1}}), // Enable every byte for complete FIFO word writes.
                        .RCLK(read_clk_i), // Connect the independent FIFO read clock.
                        .RCS(read_bank_enable[bank_index]), // Enable reads only for this decoded bank.
                        .RA(macro_read_address), // Address one row within this fixed bank.
                        .Q(bank_read_data[(bank_index*PHYSICAL_WIDTH)+(lane_index*MACRO_WIDTH) +: MACRO_WIDTH]) // Collect one registered width lane.
                    ); // End the 2048-word fixed SRAM instance.
                end // End the fixed macro class selection.
            end // End the logical width tiling loop.
        end // End the logical depth banking loop.
    endgenerate // End the fixed SDP macro array.
endmodule // End the kd28_fifo_sdp_storage_map module.

`default_nettype wire // Restore implicit-net behavior for downstream source files.
