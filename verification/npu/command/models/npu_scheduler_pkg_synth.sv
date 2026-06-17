`timescale 1ns/1ps

// Yosys-only parser facade for the two scheduler records consumed by the
// command gateway. The production package contains cross-package enum types
// that the repository Yosys frontend cannot parse. Field order and widths here
// match npu_scheduler_pkg.sv; Verilator lint uses the production package.
package npu_scheduler_pkg;

    localparam logic [3:0] NPU_TASK_DESCRIPTOR_VERSION = 4'd2;
    localparam logic [3:0] NPU_VECTOR_TASK_DESCRIPTOR_VERSION = 4'd3;
    localparam int unsigned NPU_TASK_DESCRIPTOR_WIDTH = 342;
    localparam int unsigned NPU_TASK_STATUS_WIDTH = 29;

    typedef enum logic [2:0] {
        NPU_TASK_GEMM   = 3'd0,
        NPU_TASK_VECTOR = 3'd1
    } npu_task_operation_e;

    typedef enum logic [3:0] {
        NPU_TASK_STATUS_OK               = 4'd0,
        NPU_TASK_ERROR_VERSION          = 4'd1,
        NPU_TASK_ERROR_OPERATION        = 4'd2,
        NPU_TASK_ERROR_DIMENSION        = 4'd3,
        NPU_TASK_ERROR_SIZE_ALIGNMENT   = 4'd4,
        NPU_TASK_ERROR_BUFFER_ALIGNMENT = 4'd5,
        NPU_TASK_ERROR_REGION           = 4'd6,
        NPU_TASK_ERROR_FORMAT           = 4'd7,
        NPU_TASK_ERROR_VECTOR_OPERATION = 4'd8,
        NPU_TASK_ERROR_COMPLETION       = 4'd9
    } npu_task_status_code_e;

    typedef struct packed {
        logic [3:0] version;
        npu_task_operation_e operation;
        logic [15:0] job_id;
        logic [318:0] remaining_fields;
    } npu_task_descriptor_t;

    typedef struct packed {
        logic [15:0] job_id;
        logic [7:0] tag;
        logic success;
        npu_task_status_code_e code;
    } npu_task_status_t;

endpackage
