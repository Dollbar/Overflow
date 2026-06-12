`timescale 1ns/1ps
package serdes_212g5_pam4_profile_pkg;
    localparam [63:0] SERDES_212G5_LINE_RATE_BPS = 64'd212500000000;
    localparam [63:0] SERDES_212G5_SYMBOL_RATE_BAUD = 64'd106250000000;
    localparam [31:0] SERDES_212G5_LINE_RATE_KBPS = 32'd212500000;
    localparam [31:0] SERDES_212G5_SYMBOL_RATE_KBAUD = 32'd106250000;
    localparam [31:0] SERDES_212G5_FOUR_LANE_GROSS_KBPS = 32'd850000000;
    localparam [63:0] SERDES_212G5_FOUR_LANE_GROSS_BPS = 64'd850000000000;
    localparam integer SERDES_212G5_BITS_PER_SYMBOL = 2;
    localparam integer SERDES_212G5_PCS_BLOCK_BITS = 66;
    localparam integer SERDES_212G5_PCS_DATA_BITS = 64;
    localparam integer SERDES_212G5_PAM4_SYMBOLS_PER_BLOCK = 33;
    // Exact block opportunity clock is 212500000000/66 Hz; it is not rounded.
    localparam [63:0] SERDES_212G5_BLOCK_RATE_NUMERATOR_HZ = 64'd212500000000;
    localparam integer SERDES_212G5_BLOCK_RATE_DENOMINATOR = 66;
    localparam integer SERDES_DEFAULT_PROPAGATION_CYCLES = 3;
    localparam integer SERDES_DEFAULT_MAX_LANE_SKEW_CYCLES = 2;
    localparam integer SERDES_DEFAULT_CDR_LOCK_CYCLES = 8;
    localparam integer SERDES_DEFAULT_BLOCK_LOCK_CYCLES = 8;
    localparam integer SERDES_DEFAULT_BURST_ERROR_LENGTH_BLOCKS = 4;
    localparam integer SERDES_DEFAULT_ELASTIC_DEPTH = 64;
endpackage
