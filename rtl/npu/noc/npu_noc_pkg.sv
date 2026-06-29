`timescale 1ns/1ps

package npu_noc_pkg;

    /* verilator lint_off UNUSEDPARAM */
    localparam int unsigned NPU_NOC_ROWS = 2;
    localparam int unsigned NPU_NOC_COLUMNS = 4;
    localparam int unsigned NPU_NOC_PODS = 8;
    localparam int unsigned NPU_NOC_PORTS = 5;
    localparam int unsigned NPU_NOC_DATA_LANES = 2;
    localparam int unsigned NPU_NOC_DATA_VCS = 4;
    localparam int unsigned NPU_NOC_CONTROL_VCS = 1;
    localparam int unsigned NPU_NOC_DATA_FIFO_DEPTH = 8;
    localparam int unsigned NPU_NOC_CONTROL_FIFO_DEPTH = 4;
    localparam int unsigned NPU_NOC_DATA_PACKET_FLITS = 32;
    localparam int unsigned NPU_NOC_CONTROL_PACKET_FLITS = 4;
    localparam int unsigned NPU_NOC_AGE_THRESHOLD = 64;

    localparam int unsigned NPU_NOC_PORT_LOCAL = 0;
    localparam int unsigned NPU_NOC_PORT_WEST = 1;
    localparam int unsigned NPU_NOC_PORT_EAST = 2;
    localparam int unsigned NPU_NOC_PORT_NORTH = 3;
    localparam int unsigned NPU_NOC_PORT_SOUTH = 4;

    localparam int unsigned NPU_NOC_POD_ID_WIDTH = 3;
    localparam int unsigned NPU_NOC_COLUMN_WIDTH = 2;
    localparam int unsigned NPU_NOC_ROW_WIDTH = 1;
    localparam int unsigned NPU_NOC_TRAFFIC_CLASS_WIDTH = 2;

    localparam int unsigned NPU_NOC_CONTROL_CDC_DEPTH = 8;
    localparam int unsigned NPU_NOC_DATA_CDC_DEPTH = 16;
    localparam int unsigned NPU_NOC_CONTROL_CDC_WIDTH = 160;
    localparam int unsigned NPU_NOC_DATA_CDC_WIDTH = 1176;

    localparam int unsigned NPU_NOC_VC_ESCAPE = 0;
    localparam int unsigned NPU_NOC_VC_DEMAND = 1;
    localparam int unsigned NPU_NOC_VC_WRITEBACK = 2;
    localparam int unsigned NPU_NOC_VC_COLLECTIVE = 3;
    /* verilator lint_on UNUSEDPARAM */

endpackage
