`default_nettype none

module npu_kd28_sram_sta_top (
    input  wire         clk_i,
    input  wire         write_cs_i,
    input  wire         read_cs_i,
    input  wire [10:0]  write_addr_i,
    input  wire [10:0]  read_addr_i,
    input  wire [127:0] write_data_i,
    output wire [127:0] read_data_o
);
    wire [255:0] physical_read_data;

    KD28_SRAM_SDP_2048X256 u_local_bank (
        .WCLK(clk_i),
        .WCS(write_cs_i),
        .WA(write_addr_i),
        .D({128'd0, write_data_i}),
        .WM({16'd0, 16'hffff}),
        .RCLK(clk_i),
        .RCS(read_cs_i),
        .RA(read_addr_i),
        .Q(physical_read_data)
    );

    assign read_data_o = physical_read_data[127:0];
endmodule

`default_nettype wire
