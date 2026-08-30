`timescale 1ns/1ps

// Yosys-only parser facade for npu_command_pkg. The production package derives
// widths from scheduler and Pod packages; this frontend cannot resolve package
// references from inside another package. Verilator uses the production ABI.
package npu_command_pkg;

    localparam logic [3:0] NPU_DECODED_COMMAND_VERSION = 4'd1;
    localparam int unsigned NPU_DECODED_REQUEST_ID_WIDTH = 16;
    localparam int unsigned NPU_DECODED_TARGET_WIDTH = 4;
    localparam int unsigned NPU_DECODED_COMMAND_PAYLOAD_WIDTH = 342;
    localparam int unsigned NPU_DECODED_COMMAND_WIDTH = 372;
    localparam int unsigned NPU_UNIFIED_COMPLETION_WIDTH = 66;

    typedef enum logic [1:0] {
        NPU_DECODED_TASK  = 2'd0,
        NPU_DECODED_LOCAL = 2'd1,
        NPU_DECODED_DMA   = 2'd2
    } npu_decoded_command_class_e;

    typedef enum logic [1:0] {
        NPU_COMPLETION_TASK    = 2'd0,
        NPU_COMPLETION_LOCAL   = 2'd1,
        NPU_COMPLETION_DMA     = 2'd2,
        NPU_COMPLETION_COMMAND = 2'd3
    } npu_completion_source_e;

    typedef enum logic [7:0] {
        NPU_COMMAND_OK                    = 8'd0,
        NPU_COMMAND_ERROR_VERSION         = 8'd1,
        NPU_COMMAND_ERROR_CLASS           = 8'd2,
        NPU_COMMAND_ERROR_POD             = 8'd3,
        NPU_COMMAND_ERROR_TARGET          = 8'd4,
        NPU_COMMAND_ERROR_REQUEST_ID      = 8'd5,
        NPU_COMMAND_ERROR_PAYLOAD_VERSION = 8'd6
    } npu_command_error_e;

    typedef struct packed {
        logic [3:0] version;
        npu_decoded_command_class_e command_class;
        logic [15:0] request_id;
        logic [2:0] pod_id;
        logic target_valid;
        logic [3:0] target;
        logic [341:0] payload;
    } npu_decoded_command_t;

    typedef struct packed {
        npu_completion_source_e source;
        logic [15:0] request_id;
        logic [2:0] pod_id;
        logic [3:0] target;
        logic success;
        logic [7:0] code;
        logic [31:0] detail;
    } npu_unified_completion_t;

endpackage
