`timescale 1ns/1ps

package npu_pod_noc_pkg;

    // Pod/NoC v0.1 freezes only the synchronous logical attachment. Router
    // virtual channels, credits, routing state, and CDC remain externally owned.
    /* verilator lint_off UNUSEDPARAM */
    localparam logic [3:0] NPU_POD_NOC_VERSION = 4'd1;
    localparam int unsigned NPU_POD_NOC_POD_COUNT = 8;
    localparam int unsigned NPU_POD_NOC_POD_ID_WIDTH = 3;
    localparam int unsigned NPU_POD_NOC_TRAFFIC_CLASS_WIDTH = 2;
    localparam int unsigned NPU_POD_NOC_CONTROL_LANES = 1;
    localparam int unsigned NPU_POD_NOC_DATA_LANES = 2;
    localparam int unsigned NPU_POD_NOC_CONTROL_BYTES = 16;
    localparam int unsigned NPU_POD_NOC_DATA_BYTES = 128;

    // Packed flits place the opaque payload at the least-significant end,
    // followed by byte validity and routing metadata common to both widths.
    localparam int unsigned NPU_POD_NOC_COMMON_METADATA_WIDTH =
        4 + 1 + 1 + NPU_POD_NOC_POD_ID_WIDTH +
        NPU_POD_NOC_POD_ID_WIDTH + NPU_POD_NOC_TRAFFIC_CLASS_WIDTH;
    localparam int unsigned NPU_POD_NOC_CONTROL_FLIT_WIDTH =
        NPU_POD_NOC_CONTROL_BYTES * 8 + NPU_POD_NOC_CONTROL_BYTES +
        NPU_POD_NOC_COMMON_METADATA_WIDTH;
    localparam int unsigned NPU_POD_NOC_DATA_FLIT_WIDTH =
        NPU_POD_NOC_DATA_BYTES * 8 + NPU_POD_NOC_DATA_BYTES +
        NPU_POD_NOC_COMMON_METADATA_WIDTH;
    /* verilator lint_on UNUSEDPARAM */

endpackage
