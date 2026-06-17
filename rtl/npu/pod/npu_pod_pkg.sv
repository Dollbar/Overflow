`timescale 1ns/1ps

package npu_pod_pkg;

    // Package users commonly consume only one subset of the architectural
    // constants or transfer types.
    /* verilator lint_off UNUSEDPARAM */
    localparam int unsigned NPU_POD_COUNT = 8;
    localparam int unsigned NPU_POD_MESH_ROWS = 2;
    localparam int unsigned NPU_POD_MESH_COLUMNS = 4;
    localparam int unsigned NPU_CLUSTERS_PER_POD = 2;
    localparam int unsigned NPU_POD_HBM_LANES = 5;
    localparam int unsigned NPU_POD_SHARED_SRAM_BYTES = 16 * 1024 * 1024;

    localparam int unsigned NPU_POD_ID_WIDTH = 3;
    localparam int unsigned NPU_POD_ROW_WIDTH = 1;
    localparam int unsigned NPU_POD_COLUMN_WIDTH = 2;
    localparam int unsigned NPU_POD_CLUSTER_WIDTH = 1;
    localparam int unsigned NPU_POD_JOB_ID_WIDTH = 16;

    localparam logic [3:0] NPU_POD_LOCAL_TRANSFER_VERSION = 4'd1;

    typedef enum logic [1:0] {
        NPU_POD_TARGET_TENSOR_ACTIVATION = 2'd0,
        NPU_POD_TARGET_TENSOR_WEIGHT     = 2'd1,
        NPU_POD_TARGET_VECTOR_B          = 2'd2,
        NPU_POD_TARGET_VECTOR_C          = 2'd3
    } npu_pod_local_target_e;

    typedef enum logic [2:0] {
        NPU_POD_LOCAL_OK                = 3'd0,
        NPU_POD_LOCAL_ERROR_VERSION     = 3'd1,
        NPU_POD_LOCAL_ERROR_WORD_COUNT  = 3'd2,
        NPU_POD_LOCAL_ERROR_BANK_RANGE  = 3'd3,
        NPU_POD_LOCAL_ERROR_ALIGNMENT   = 3'd4,
        NPU_POD_LOCAL_ERROR_SRAM_RANGE  = 3'd5,
        NPU_POD_LOCAL_ERROR_OFFSET      = 3'd6
    } npu_pod_local_error_e;

    typedef struct packed {
        logic [3:0] version;
        logic [NPU_POD_JOB_ID_WIDTH-1:0] transfer_id;
        npu_pod_local_target_e target;
        logic [3:0] buffer_id;
        logic [3:0] bank_start;
        logic [31:0] local_offset;
        logic [23:0] data_sram_address;
        logic [23:0] scale_sram_address;
        logic [3:0] word_count;
    } npu_pod_local_transfer_t;

    typedef struct packed {
        logic [NPU_POD_JOB_ID_WIDTH-1:0] transfer_id;
        logic success;
        npu_pod_local_error_e error_code;
    } npu_pod_local_completion_t;

    // Keep explicit arithmetic here because the repository Yosys frontend
    // cannot evaluate $bits(type_name) in a package declaration.
    localparam int unsigned NPU_POD_LOCAL_TRANSFER_WIDTH =
        4 + NPU_POD_JOB_ID_WIDTH + 2 + 4 + 4 + 32 + 24 + 24 + 4;
    localparam int unsigned NPU_POD_LOCAL_COMPLETION_WIDTH =
        NPU_POD_JOB_ID_WIDTH + 1 + 3;
    /* verilator lint_on UNUSEDPARAM */

endpackage
