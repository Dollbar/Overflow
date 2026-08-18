`timescale 1ns/1ps

package tile_noc_pkg;

    // Shared package consumers legitimately use different protocol subsets.
    /* verilator lint_off UNUSEDPARAM */
    localparam integer TILE_NOC_PORT_COUNT = 5;
    localparam integer TILE_NOC_VC_COUNT = 2;
    localparam integer TILE_NOC_FLIT_WIDTH = 160;
    localparam integer TILE_NOC_COORD_WIDTH = 4;
    /* verilator lint_on UNUSEDPARAM */

    typedef enum logic [2:0] {
        TILE_NOC_MSG_ACTIVATION = 3'd0,
        TILE_NOC_MSG_WEIGHT     = 3'd1,
        TILE_NOC_MSG_RESULT     = 3'd2,
        TILE_NOC_MSG_CONTROL    = 3'd3,
        TILE_NOC_MSG_RESPONSE   = 3'd4
    } tile_noc_msg_e;

    typedef enum logic [2:0] {
        TILE_NOC_PORT_LOCAL = 3'd0,
        TILE_NOC_PORT_NORTH = 3'd1,
        TILE_NOC_PORT_EAST  = 3'd2,
        TILE_NOC_PORT_SOUTH = 3'd3,
        TILE_NOC_PORT_WEST  = 3'd4
    } tile_noc_port_e;

    typedef enum logic [3:0] {
        TILE_NOC_CTRL_NOP          = 4'd0,
        TILE_NOC_CTRL_REGION_CLEAR = 4'd1,
        TILE_NOC_CTRL_START        = 4'd2,
        TILE_NOC_CTRL_RELEASE      = 4'd3
    } tile_noc_control_e;

    typedef struct packed {
        logic [3:0] aux;
        logic last;
        tile_noc_msg_e msg_type;
        logic [2:0] reserved;
        logic [4:0] tile_span;
        logic [3:0] dst_y;
        logic [3:0] dst_x;
        logic [7:0] tag;
        logic [127:0] payload;
    } tile_noc_flit_t;

endpackage
