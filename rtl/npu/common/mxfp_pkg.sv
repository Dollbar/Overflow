`timescale 1ns/1ps

package mxfp_pkg;

    // Leaf compilation units intentionally consume different subsets.
    /* verilator lint_off UNUSEDPARAM */
    localparam int unsigned MX_BLOCK_SIZE = 32;
    localparam int unsigned MX_SCALE_WIDTH = 8;
    localparam int unsigned MX_LANES_PER_BEAT = 16;
    localparam int unsigned MX_ELEMENT_CONTAINER_WIDTH = 8;
    localparam logic [7:0] MX_E8M0_NAN = 8'hff;
    localparam logic signed [8:0] MX_E8M0_BIAS = 9'sd127;
    /* verilator lint_on UNUSEDPARAM */

    // v0.2 deliberately supports only MXFP4 E2M1 and MXFP8 E4M3FN.  The E8M0
    // scale and fixed 32-element block are mandatory in both supported modes.
    typedef enum logic [1:0] {
        MXFP4_E2M1 = 2'd0,
        MXFP8_E4M3 = 2'd1,
        MXFP_RESERVED_2 = 2'd2,
        MXFP_RESERVED_3 = 2'd3
    } mxfp_format_e;

    typedef logic [MX_SCALE_WIDTH-1:0] mxfp_scale_t;
    typedef logic [MX_LANES_PER_BEAT*MX_ELEMENT_CONTAINER_WIDTH-1:0]
        mxfp_lane_beat_t;

    typedef struct packed {
        logic signed [8:0] exponent;
        logic              is_nan;
    } mxfp_scale_decoded_t;

    // The four-bit significand is always Q1.3. E2M1 and E4M3 fraction bits
    // are zero-extended into that common exact multiplier representation.
    typedef struct packed {
        logic              sign;
        logic signed [7:0] element_exponent;
        logic signed [8:0] scale_exponent;
        logic        [3:0] significand;
        logic              is_zero;
        logic              is_subnormal;
        logic              is_normal;
        logic              is_inf;
        logic              is_nan;
    } mxfp_decoded_t;

    // Element and scale exponents remain separate so a 32-element block can
    // be reduced exactly before its shared power-of-two scale is applied.
    typedef struct packed {
        logic               sign;
        logic signed [8:0]  element_exponent;
        logic signed [9:0]  scale_exponent;
        logic        [7:0]  significand;
        logic               is_zero;
        logic               is_inf;
        logic               is_nan;
    } mxfp_product_t;

endpackage
