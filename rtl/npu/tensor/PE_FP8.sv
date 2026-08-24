`timescale 1ns/1ps
`default_nettype none

// MX processing element used by the Tile reduction architecture. The PE owns
// no dot-product state: it only registers A/B forwarding and emits one exact
// MX product. Reduction and long-K state live once per Tile.
module PE_FP8 #(
    parameter bit DAZ = 1'b0,
    parameter bit FTZ = 1'b0
) (
    input  logic                     clk_i,
    input  logic                     rst_i,
    input  logic                     clear_i,
    input  logic                     a_valid_i,
    input  logic               [7:0] a_i,
    input  mxfp_pkg::mxfp_format_e   a_format_i,
    input  mxfp_pkg::mxfp_scale_t    a_scale_i,
    input  logic                     a_block_first_i,
    input  logic                     a_block_last_i,
    input  logic                     a_matrix_first_i,
    input  logic                     a_matrix_last_i,
    input  logic               [7:0] a_tag_i,
    input  logic                     b_valid_i,
    input  logic               [7:0] b_i,
    input  mxfp_pkg::mxfp_format_e   b_format_i,
    input  mxfp_pkg::mxfp_scale_t    b_scale_i,
    output logic                     a_valid_o,
    output logic               [7:0] a_o,
    output mxfp_pkg::mxfp_format_e   a_format_o,
    output mxfp_pkg::mxfp_scale_t    a_scale_o,
    output logic                     a_block_first_o,
    output logic                     a_block_last_o,
    output logic                     a_matrix_first_o,
    output logic                     a_matrix_last_o,
    output logic               [7:0] a_tag_o,
    output logic                     b_valid_o,
    output logic               [7:0] b_o,
    output mxfp_pkg::mxfp_format_e   b_format_o,
    output mxfp_pkg::mxfp_scale_t    b_scale_o,
    output logic                     product_valid_o,
    output mxfp_pkg::mxfp_product_t  product_o,
    output logic                     product_invalid_o
);

    mxfp_pkg::mxfp_decoded_t a_decoded;
    mxfp_pkg::mxfp_decoded_t b_decoded;
    logic pair_valid;

    // FTZ is a Tile-result policy; exact PE products never flush.
    wire _unused_ftz = FTZ;

    assign pair_valid = a_valid_i && b_valid_i && !rst_i && !clear_i;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            a_valid_o <= 1'b0;
            a_o <= 8'd0;
            a_format_o <= mxfp_pkg::MXFP8_E4M3;
            a_scale_o <= 8'd127;
            a_block_first_o <= 1'b0;
            a_block_last_o <= 1'b0;
            a_matrix_first_o <= 1'b0;
            a_matrix_last_o <= 1'b0;
            a_tag_o <= 8'd0;
            b_valid_o <= 1'b0;
            b_o <= 8'd0;
            b_format_o <= mxfp_pkg::MXFP8_E4M3;
            b_scale_o <= 8'd127;
        end else if (clear_i) begin
            a_valid_o <= 1'b0;
            b_valid_o <= 1'b0;
        end else begin
            a_valid_o <= a_valid_i;
            b_valid_o <= b_valid_i;
            if (a_valid_i) begin
                a_o <= a_i;
                a_format_o <= a_format_i;
                a_scale_o <= a_scale_i;
                a_block_first_o <= a_block_first_i;
                a_block_last_o <= a_block_last_i;
                a_matrix_first_o <= a_matrix_first_i;
                a_matrix_last_o <= a_matrix_last_i;
                a_tag_o <= a_tag_i;
            end
            if (b_valid_i) begin
                b_o <= b_i;
                b_format_o <= b_format_i;
                b_scale_o <= b_scale_i;
            end
        end
    end

    mxfp_unpack #(.DAZ(DAZ)) u_unpack_a (
        .data_i(a_i),
        .format_i(a_format_i),
        .scale_i(a_scale_i),
        .decoded_o(a_decoded)
    );

    mxfp_unpack #(.DAZ(DAZ)) u_unpack_b (
        .data_i(b_i),
        .format_i(b_format_i),
        .scale_i(b_scale_i),
        .decoded_o(b_decoded)
    );

    mxfp_mul_exact u_multiply (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .valid_i(pair_valid),
        .a_i(a_decoded),
        .b_i(b_decoded),
        .valid_o(product_valid_o),
        .product_o(product_o),
        .invalid_o(product_invalid_o)
    );

endmodule

`default_nettype wire
