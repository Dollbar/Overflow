`timescale 1ns/1ps
`default_nettype none

module tb_sram_macro_contract;
    logic clk_i;
    logic rst_i;
    logic a_req_i;
    logic a_we_i;
    logic [4:0] a_addr_i;
    logic [127:0] a_wdata;
    logic b_req_i;
    logic b_we_i;
    logic [4:0] b_addr_i;
    logic [127:0] b_wdata;
    logic [31:0] a_rdata32;
    logic [31:0] b_rdata32;
    logic [63:0] a_rdata64;
    logic [63:0] b_rdata64;
    logic [127:0] a_rdata128;
    logic [127:0] b_rdata128;
    logic a_rvalid32;
    logic b_rvalid32;
    logic a_rvalid64;
    logic b_rvalid64;
    logic a_rvalid128;
    logic b_rvalid128;
    logic [7:0] scenario_id;
    integer check_count;

    SRAM_32_32 u_sram32 (
        .clk_i, .rst_i, .a_req_i, .a_we_i, .a_addr_i,
        .a_wdata_i(a_wdata[31:0]), .a_rdata_o(a_rdata32),
        .a_rvalid_o(a_rvalid32), .b_req_i, .b_we_i, .b_addr_i,
        .b_wdata_i(b_wdata[31:0]), .b_rdata_o(b_rdata32),
        .b_rvalid_o(b_rvalid32)
    );
    SRAM_32_64 u_sram64 (
        .clk_i, .rst_i, .a_req_i, .a_we_i, .a_addr_i,
        .a_wdata_i(a_wdata[63:0]), .a_rdata_o(a_rdata64),
        .a_rvalid_o(a_rvalid64), .b_req_i, .b_we_i, .b_addr_i,
        .b_wdata_i(b_wdata[63:0]), .b_rdata_o(b_rdata64),
        .b_rvalid_o(b_rvalid64)
    );
    SRAM_32_128 u_sram128 (
        .clk_i, .rst_i, .a_req_i, .a_we_i, .a_addr_i,
        .a_wdata_i(a_wdata), .a_rdata_o(a_rdata128),
        .a_rvalid_o(a_rvalid128), .b_req_i, .b_we_i, .b_addr_i,
        .b_wdata_i(b_wdata), .b_rdata_o(b_rdata128),
        .b_rvalid_o(b_rvalid128)
    );

    always #5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/sram_macro_contract.vcd");
        $dumpvars(1, tb_sram_macro_contract);
    end
`endif

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        a_req_i = 1'b0;
        a_we_i = 1'b0;
        a_addr_i = '0;
        a_wdata = '0;
        b_req_i = 1'b0;
        b_we_i = 1'b0;
        b_addr_i = '0;
        b_wdata = '0;
        scenario_id = 8'd0;
        check_count = 0;

        repeat (3) @(negedge clk_i);
        rst_i = 1'b0;

        // Independent ports write different addresses in the same cycle.
        scenario_id = 8'd1;
        a_req_i = 1'b1;
        a_we_i = 1'b1;
        a_addr_i = 5'd3;
        a_wdata = 128'h01234567_89abcdef_fedcba98_76543210;
        b_req_i = 1'b1;
        b_we_i = 1'b1;
        b_addr_i = 5'd19;
        b_wdata = 128'h11223344_55667788_99aabbcc_ddeeff00;
        @(negedge clk_i);

        // Cross-read both locations. Registered data is valid after the next
        // active edge and remains stable while valid is asserted.
        scenario_id = 8'd2;
        a_we_i = 1'b0;
        a_addr_i = 5'd19;
        b_we_i = 1'b0;
        b_addr_i = 5'd3;
        @(negedge clk_i);
        if (!a_rvalid32 || !b_rvalid32 || !a_rvalid64 || !b_rvalid64 ||
            !a_rvalid128 || !b_rvalid128 ||
            (a_rdata32 !== 32'hddeeff00) ||
            (b_rdata32 !== 32'h76543210) ||
            (a_rdata64 !== 64'h99aabbcc_ddeeff00) ||
            (b_rdata64 !== 64'hfedcba98_76543210) ||
            (a_rdata128 !== 128'h11223344_55667788_99aabbcc_ddeeff00) ||
            (b_rdata128 !== 128'h01234567_89abcdef_fedcba98_76543210)) begin
            $fatal(1, "FAIL: SRAM registered dual-port read contract");
        end
        check_count = check_count + 1;

        // A request gap removes read-valid on the following cycle.
        scenario_id = 8'd3;
        a_req_i = 1'b0;
        b_req_i = 1'b0;
        @(negedge clk_i);
        if (a_rvalid32 || b_rvalid32 || a_rvalid64 || b_rvalid64 ||
            a_rvalid128 || b_rvalid128) begin
            $fatal(1, "FAIL: SRAM read-valid did not follow request gap");
        end
        check_count = check_count + 1;

        // Reset suppresses an in-flight read but does not clear memory.
        scenario_id = 8'd4;
        a_req_i = 1'b1;
        a_addr_i = 5'd3;
        rst_i = 1'b1;
        @(negedge clk_i);
        if (a_rvalid32 || a_rvalid64 || a_rvalid128) begin
            $fatal(1, "FAIL: SRAM reset did not suppress read-valid");
        end
        rst_i = 1'b0;
        @(negedge clk_i);
        if (!a_rvalid32 || !a_rvalid64 || !a_rvalid128 ||
            (a_rdata32 !== 32'h76543210) ||
            (a_rdata64 !== 64'hfedcba98_76543210) ||
            (a_rdata128 !== 128'h01234567_89abcdef_fedcba98_76543210)) begin
            $fatal(1, "FAIL: SRAM did not retain contents across reset");
        end
        check_count = check_count + 1;

        $display("PASS: SRAM 32x32/64/128 one-cycle dual-port contract checks=%0d",
                 check_count);
        $finish;
    end

    initial begin
        repeat (200) @(posedge clk_i);
        $fatal(1, "FAIL: SRAM macro contract timeout scenario=%0d", scenario_id);
    end

endmodule

`default_nettype wire
