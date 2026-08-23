`default_nettype none // Reject accidental implicit nets in the mapped FIFO synthesis smoke design.

module kd28_fifo_mapping_smoke_top ( // Elaborate FIFO wrappers and every fixed SDP mapping class.
    input  wire         clk_i, // Receive the synchronous FIFO and direct-map clock.
    input  wire         rst_n_i, // Receive the synchronous FIFO active-low reset.
    input  wire         write_clk_i, // Receive the asynchronous FIFO write clock.
    input  wire         write_rst_n_i, // Receive the asynchronous FIFO write reset.
    input  wire         read_clk_i, // Receive the asynchronous FIFO read clock.
    input  wire         read_rst_n_i, // Receive the asynchronous FIFO read reset.
    input  wire [263:0] data_i, // Provide enough payload bits for every mapping configuration.
    input  wire [11:0]  addr_i, // Provide enough address bits for every mapping configuration.
    input  wire         valid_i, // Enable representative writes and producer transfers.
    input  wire         ready_i, // Enable representative reads and consumer transfers.
    output wire [415:0] data_o, // Retain every wrapper and direct-map output through synthesis.
    output wire         ready_o, // Retain both FIFO producer-ready results through synthesis.
    output wire         valid_o // Retain both FIFO consumer-valid results through synthesis.
); // End the mapped FIFO smoke interface.
    wire [23:0] sync_data; // Carry the mapped synchronous FIFO payload.
    wire sync_ready; // Carry synchronous FIFO producer readiness.
    wire sync_valid; // Carry synchronous FIFO consumer validity.
    wire [15:0] async_data; // Carry the mapped asynchronous FIFO payload.
    wire async_ready; // Carry asynchronous FIFO producer readiness.
    wire async_valid; // Carry asynchronous FIFO consumer validity.
    wire [39:0] map_512_data; // Carry the 512x64-class direct-map output.
    wire [71:0] map_1024_data; // Carry the 1024x128-class direct-map output.
    wire [263:0] map_2048_data; // Carry the banked and tiled 2048x256-class output.

    kd28_sync_fifo #(.DATA_WIDTH(24), .DEPTH(5), .ADDR_WIDTH(3), .COUNT_WIDTH(4)) u_sync_fifo ( // Map a non-power-of-two FIFO through one 256x32 SRAM.
        .clk_i(clk_i), .rst_n_i(rst_n_i), .write_data_i(data_i[23:0]), .write_valid_i(valid_i), .write_ready_o(sync_ready), .read_data_o(sync_data), .read_valid_o(sync_valid), .read_ready_i(ready_i) // Connect the complete synchronous ready-valid interface.
    ); // End the mapped synchronous FIFO instance.

    kd28_async_fifo #(.DATA_WIDTH(16), .DEPTH(8), .ADDR_WIDTH(3)) u_async_fifo ( // Map an independent-clock FIFO through one 256x32 SRAM.
        .write_clk_i(write_clk_i), .write_rst_n_i(write_rst_n_i), .write_data_i(data_i[15:0]), .write_valid_i(valid_i), .write_ready_o(async_ready), .read_clk_i(read_clk_i), .read_rst_n_i(read_rst_n_i), .read_data_o(async_data), .read_valid_o(async_valid), .read_ready_i(ready_i) // Connect the complete asynchronous ready-valid interface.
    ); // End the mapped asynchronous FIFO instance.

    kd28_fifo_sdp_storage_map #(.DATA_WIDTH(40), .DEPTH(300), .ADDR_WIDTH(9)) u_map_512 ( // Force selection of one 512x64 fixed macro.
        .write_clk_i(clk_i), .write_cs_i(valid_i), .write_addr_i(addr_i[8:0]), .write_data_i(data_i[39:0]), .read_clk_i(clk_i), .read_cs_i(ready_i), .read_addr_i(addr_i[8:0]), .read_data_o(map_512_data) // Connect the direct logical storage interface.
    ); // End the 512x64-class mapping instance.

    kd28_fifo_sdp_storage_map #(.DATA_WIDTH(72), .DEPTH(600), .ADDR_WIDTH(10)) u_map_1024 ( // Force selection of one 1024x128 fixed macro.
        .write_clk_i(clk_i), .write_cs_i(valid_i), .write_addr_i(addr_i[9:0]), .write_data_i(data_i[71:0]), .read_clk_i(clk_i), .read_cs_i(ready_i), .read_addr_i(addr_i[9:0]), .read_data_o(map_1024_data) // Connect the direct logical storage interface.
    ); // End the 1024x128-class mapping instance.

    kd28_fifo_sdp_storage_map #(.DATA_WIDTH(264), .DEPTH(4096), .ADDR_WIDTH(12)) u_map_2048 ( // Force two banks and two lanes of 2048x256 fixed macros.
        .write_clk_i(clk_i), .write_cs_i(valid_i), .write_addr_i(addr_i), .write_data_i(data_i), .read_clk_i(clk_i), .read_cs_i(ready_i), .read_addr_i(addr_i), .read_data_o(map_2048_data) // Connect the banked and tiled logical storage interface.
    ); // End the 2048x256-class mapping instance.

    assign data_o = {map_2048_data, map_1024_data, map_512_data, async_data, sync_data}; // Preserve every fixed-macro output at the smoke boundary.
    assign ready_o = sync_ready ^ async_ready; // Preserve both independent producer-ready results.
    assign valid_o = sync_valid ^ async_valid; // Preserve both independent consumer-valid results.
endmodule // End the mapped FIFO synthesis smoke design.

`default_nettype wire // Restore implicit-net behavior after the mapped FIFO smoke design.
