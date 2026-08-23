`default_nettype none // Reject accidental implicit nets in the FIFO-mapped SDP STA smoke design.

module kd28_fifo_sdp_sta_top ( // Exercise every fixed SDP macro class with independent write and read clocks.
    input  wire         write_clk_i, // Receive the representative FIFO producer clock.
    input  wire         read_clk_i, // Receive the unrelated representative FIFO consumer clock.
    input  wire         write_cs_i, // Enable writes across the representative mapped lanes.
    input  wire         read_cs_i, // Enable reads across the representative mapped lanes.
    input  wire [10:0]  write_addr_i, // Provide enough row address bits for the largest fixed macro.
    input  wire [10:0]  read_addr_i, // Provide enough read row address bits for the largest fixed macro.
    input  wire [255:0] write_data_i, // Provide enough write data bits for the widest fixed macro.
    input  wire [31:0]  write_mask_i, // Provide enough byte enables for the widest fixed macro.
    output wire [479:0] read_data_o // Preserve registered outputs from all four fixed SDP classes.
); // End the FIFO-mapped SDP STA interface.
    wire [31:0] read_256x32; // Carry the smallest fixed SDP macro result.
    wire [63:0] read_512x64; // Carry the medium-small fixed SDP macro result.
    wire [127:0] read_1024x128; // Carry the medium-large fixed SDP macro result.
    wire [255:0] read_2048x256; // Carry the largest fixed SDP macro result.

    KD28_SRAM_SDP_256X32 u_sdp_256x32 ( // Instantiate the FIFO mapping class used through 256 logical words.
        .WCLK(write_clk_i), .WCS(write_cs_i), .WA(write_addr_i[7:0]), .D(write_data_i[31:0]), .WM(write_mask_i[3:0]), .RCLK(read_clk_i), .RCS(read_cs_i), .RA(read_addr_i[7:0]), .Q(read_256x32) // Connect both independent macro ports.
    ); // End the 256x32 fixed SDP STA instance.

    KD28_SRAM_SDP_512X64 u_sdp_512x64 ( // Instantiate the FIFO mapping class used through 512 logical words.
        .WCLK(write_clk_i), .WCS(write_cs_i), .WA(write_addr_i[8:0]), .D(write_data_i[63:0]), .WM(write_mask_i[7:0]), .RCLK(read_clk_i), .RCS(read_cs_i), .RA(read_addr_i[8:0]), .Q(read_512x64) // Connect both independent macro ports.
    ); // End the 512x64 fixed SDP STA instance.

    KD28_SRAM_SDP_1024X128 u_sdp_1024x128 ( // Instantiate the FIFO mapping class used through 1024 logical words.
        .WCLK(write_clk_i), .WCS(write_cs_i), .WA(write_addr_i[9:0]), .D(write_data_i[127:0]), .WM(write_mask_i[15:0]), .RCLK(read_clk_i), .RCS(read_cs_i), .RA(read_addr_i[9:0]), .Q(read_1024x128) // Connect both independent macro ports.
    ); // End the 1024x128 fixed SDP STA instance.

    KD28_SRAM_SDP_2048X256 u_sdp_2048x256 ( // Instantiate the FIFO mapping class used through 2048 words per bank.
        .WCLK(write_clk_i), .WCS(write_cs_i), .WA(write_addr_i), .D(write_data_i), .WM(write_mask_i), .RCLK(read_clk_i), .RCS(read_cs_i), .RA(read_addr_i), .Q(read_2048x256) // Connect both independent macro ports.
    ); // End the 2048x256 fixed SDP STA instance.

    assign read_data_o = {read_2048x256, read_1024x128, read_512x64, read_256x32}; // Preserve every mapped fixed macro result at the top boundary.
endmodule // End the FIFO-mapped SDP STA smoke design.

`default_nettype wire // Restore implicit-net behavior after the FIFO-mapped SDP STA smoke design.
