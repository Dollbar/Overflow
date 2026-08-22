`default_nettype none // Reject accidental implicit nets in the KD28 STA smoke design.

module kd28_sta_smoke_top ( // Define an explicit-instance smoke design for all KD28 SRAM families.
    input  wire        clk_i, // Receive the shared smoke-test clock.
    input  wire        sp_cs_i, // Enable the single-port smoke macro.
    input  wire        sp_we_i, // Select a single-port smoke write.
    input  wire [7:0]  sp_addr_i, // Select a single-port smoke address.
    input  wire [31:0] sp_wdata_i, // Receive single-port smoke write data.
    input  wire [3:0]  sp_wmask_i, // Receive single-port smoke byte enables.
    output wire [31:0] sp_rdata_o, // Return single-port smoke read data.
    input  wire        sdp_wcs_i, // Enable the simple-dual-port smoke write.
    input  wire [7:0]  sdp_waddr_i, // Select a simple-dual-port write address.
    input  wire [31:0] sdp_wdata_i, // Receive simple-dual-port smoke write data.
    input  wire [3:0]  sdp_wmask_i, // Receive simple-dual-port smoke byte enables.
    input  wire        sdp_rcs_i, // Enable the simple-dual-port smoke read.
    input  wire [7:0]  sdp_raddr_i, // Select a simple-dual-port read address.
    output wire [31:0] sdp_rdata_o, // Return simple-dual-port smoke read data.
    input  wire        tdp_acs_i, // Enable true-dual-port smoke port A.
    input  wire        tdp_awe_i, // Select a true-dual-port smoke port A write.
    input  wire [4:0]  tdp_aaddr_i, // Select a true-dual-port smoke port A address.
    input  wire [31:0] tdp_awdata_i, // Receive true-dual-port smoke port A write data.
    input  wire [3:0]  tdp_awmask_i, // Receive true-dual-port smoke port A byte enables.
    output wire [31:0] tdp_ardata_o, // Return true-dual-port smoke port A read data.
    input  wire        tdp_bcs_i, // Enable true-dual-port smoke port B.
    input  wire        tdp_bwe_i, // Select a true-dual-port smoke port B write.
    input  wire [4:0]  tdp_baddr_i, // Select a true-dual-port smoke port B address.
    input  wire [31:0] tdp_bwdata_i, // Receive true-dual-port smoke port B write data.
    input  wire [3:0]  tdp_bwmask_i, // Receive true-dual-port smoke port B byte enables.
    output wire [31:0] tdp_brdata_o // Return true-dual-port smoke port B read data.
); // End the KD28 STA smoke interface.
    KD28_SRAM_SP_256X32 u_sp ( // Instantiate one fixed single-port KD28 cell.
        .CLK(clk_i), // Connect the single-port clock.
        .CS(sp_cs_i), // Connect single-port chip select.
        .WE(sp_we_i), // Connect single-port write enable.
        .A(sp_addr_i), // Connect the single-port address bus.
        .D(sp_wdata_i), // Connect the single-port write data bus.
        .WM(sp_wmask_i), // Connect the single-port byte-mask bus.
        .Q(sp_rdata_o) // Connect the single-port read data bus.
    ); // End the fixed single-port KD28 cell.

    KD28_SRAM_SDP_256X32 u_sdp ( // Instantiate one fixed simple-dual-port KD28 cell.
        .WCLK(clk_i), // Connect the simple-dual-port write clock.
        .WCS(sdp_wcs_i), // Connect simple-dual-port write chip select.
        .WA(sdp_waddr_i), // Connect the simple-dual-port write address bus.
        .D(sdp_wdata_i), // Connect the simple-dual-port write data bus.
        .WM(sdp_wmask_i), // Connect the simple-dual-port byte-mask bus.
        .RCLK(clk_i), // Connect the simple-dual-port read clock.
        .RCS(sdp_rcs_i), // Connect simple-dual-port read chip select.
        .RA(sdp_raddr_i), // Connect the simple-dual-port read address bus.
        .Q(sdp_rdata_o) // Connect the simple-dual-port read data bus.
    ); // End the fixed simple-dual-port KD28 cell.

    KD28_SRAM_TDP_32X32 u_tdp ( // Instantiate one fixed true-dual-port KD28 cell.
        .CLK(clk_i), // Connect the shared true-dual-port clock.
        .ACS(tdp_acs_i), // Connect port A chip select.
        .AWE(tdp_awe_i), // Connect port A write enable.
        .AA(tdp_aaddr_i), // Connect the port A address bus.
        .AD(tdp_awdata_i), // Connect the port A write data bus.
        .AWM(tdp_awmask_i), // Connect the port A byte-mask bus.
        .AQ(tdp_ardata_o), // Connect the port A read data bus.
        .BCS(tdp_bcs_i), // Connect port B chip select.
        .BWE(tdp_bwe_i), // Connect port B write enable.
        .BA(tdp_baddr_i), // Connect the port B address bus.
        .BD(tdp_bwdata_i), // Connect the port B write data bus.
        .BWM(tdp_bwmask_i), // Connect the port B byte-mask bus.
        .BQ(tdp_brdata_o) // Connect the port B read data bus.
    ); // End the fixed true-dual-port KD28 cell.
endmodule // End the kd28_sta_smoke_top module.

`default_nettype wire // Restore implicit-net behavior after the smoke design.
