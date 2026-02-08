`timescale 1ns/1ps
`default_nettype none

// Selects the E8M0 shared scale from the maximum exponent of 32 FP32 values.
module mxfp_scale_block32 (
    // Only the FP32 exponent fields participate in scale selection.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [1023:0]                  block_data_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input  mxfp_pkg::mxfp_format_e        format_i,
    output mxfp_pkg::mxfp_scale_t         scale_o
);

    logic [7:0] exponent_level0 [0:31];
    logic [7:0] exponent_level1 [0:15];
    logic [7:0] exponent_level2 [0:7];
    logic [7:0] exponent_level3 [0:3];
    logic [7:0] exponent_level4 [0:1];
    logic [7:0] maximum_exponent;
    logic [31:0] special_lane;
    logic maximum_special;
    logic format_valid;
    logic [4:0] element_max_exponent;

    // Keep the 32-way maximum as a balanced five-level tree.  A procedural
    // running maximum infers a 32-comparator serial chain in ASIC synthesis.
    generate
        for (genvar lane = 0; lane < 32; lane++) begin : g_exponent_leaf
            assign exponent_level0[lane] =
                (block_data_i[lane*32 + 23 +: 8] == 8'h00) ? 8'd0 :
                block_data_i[lane*32 + 23 +: 8];
            assign special_lane[lane] =
                block_data_i[lane*32 + 23 +: 8] == 8'hff;
        end
        for (genvar node = 0; node < 16; node++) begin : g_max_level1
            assign exponent_level1[node] =
                (exponent_level0[node*2] > exponent_level0[node*2+1]) ?
                exponent_level0[node*2] : exponent_level0[node*2+1];
        end
        for (genvar node = 0; node < 8; node++) begin : g_max_level2
            assign exponent_level2[node] =
                (exponent_level1[node*2] > exponent_level1[node*2+1]) ?
                exponent_level1[node*2] : exponent_level1[node*2+1];
        end
        for (genvar node = 0; node < 4; node++) begin : g_max_level3
            assign exponent_level3[node] =
                (exponent_level2[node*2] > exponent_level2[node*2+1]) ?
                exponent_level2[node*2] : exponent_level2[node*2+1];
        end
        for (genvar node = 0; node < 2; node++) begin : g_max_level4
            assign exponent_level4[node] =
                (exponent_level3[node*2] > exponent_level3[node*2+1]) ?
                exponent_level3[node*2] : exponent_level3[node*2+1];
        end
    endgenerate

    assign maximum_exponent =
        (exponent_level4[0] > exponent_level4[1]) ?
        exponent_level4[0] : exponent_level4[1];
    assign maximum_special = |special_lane;

    always_comb begin
        unique case (format_i)
            mxfp_pkg::MXFP4_E2M1: begin
                format_valid = 1'b1;
                element_max_exponent = 5'd2;
            end
            mxfp_pkg::MXFP8_E4M3: begin
                format_valid = 1'b1;
                element_max_exponent = 5'd8;
            end
            default: begin
                format_valid = 1'b0;
                element_max_exponent = 5'd0;
            end
        endcase

        if (!format_valid || maximum_special) begin
            scale_o = mxfp_pkg::MX_E8M0_NAN;
        end else if (maximum_exponent > {3'd0, element_max_exponent}) begin
            scale_o = maximum_exponent - {3'd0, element_max_exponent};
        end else begin
            scale_o = 8'd0;
        end
    end

endmodule

`default_nettype wire
