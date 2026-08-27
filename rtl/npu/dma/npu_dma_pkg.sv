`timescale 1ns/1ps

package npu_dma_pkg;

    localparam int unsigned NPU_DMA_COMMAND_ID_WIDTH = 16;
    localparam int unsigned NPU_DMA_HBM_ADDRESS_WIDTH = 35;
    localparam int unsigned NPU_DMA_SRAM_ADDRESS_WIDTH = 24;
    localparam int unsigned NPU_DMA_X_COUNT_WIDTH = 18;
    localparam int unsigned NPU_DMA_YZ_COUNT_WIDTH = 16;
    localparam int unsigned NPU_DMA_BEAT_COUNT_WIDTH = 18;
    localparam logic [3:0] NPU_DMA_COMMAND_VERSION = 4'd1;

    typedef enum logic [1:0] {
        NPU_DMA_HBM_TO_SRAM = 2'd0,
        NPU_DMA_SRAM_TO_HBM = 2'd1
    } npu_dma_operation_e;

    typedef enum logic [2:0] {
        NPU_DMA_ERROR_OK                = 3'd0,
        NPU_DMA_ERROR_DESCRIPTOR        = 3'd1,
        NPU_DMA_ERROR_ADDRESS           = 3'd2,
        NPU_DMA_ERROR_HBM_UNCORRECTABLE = 3'd3,
        NPU_DMA_ERROR_HBM_DATA          = 3'd4,
        NPU_DMA_ERROR_SRAM              = 3'd5,
        NPU_DMA_ERROR_INTERNAL          = 3'd6
    } npu_dma_error_e;

    typedef struct packed {
        logic [3:0] version;
        npu_dma_operation_e operation;
        logic [NPU_DMA_COMMAND_ID_WIDTH-1:0] command_id;
        logic [NPU_DMA_HBM_ADDRESS_WIDTH-1:0] hbm_base_address;
        logic [NPU_DMA_SRAM_ADDRESS_WIDTH-1:0] sram_base_address;
        logic [NPU_DMA_X_COUNT_WIDTH-1:0] x_beat_count;
        logic [NPU_DMA_YZ_COUNT_WIDTH-1:0] y_count;
        logic [NPU_DMA_YZ_COUNT_WIDTH-1:0] z_count;
        logic [NPU_DMA_HBM_ADDRESS_WIDTH-1:0] hbm_y_stride;
        logic [NPU_DMA_HBM_ADDRESS_WIDTH-1:0] hbm_z_stride;
        logic [NPU_DMA_SRAM_ADDRESS_WIDTH-1:0] sram_y_stride;
        logic [NPU_DMA_SRAM_ADDRESS_WIDTH-1:0] sram_z_stride;
        logic [1:0] qos;
    } npu_dma_command_t;

    typedef struct packed {
        logic [NPU_DMA_COMMAND_ID_WIDTH-1:0] command_id;
        logic success;
        npu_dma_error_e error_code;
        logic corrected_ecc_seen;
        logic [NPU_DMA_BEAT_COUNT_WIDTH-1:0] beats_completed;
    } npu_dma_completion_t;

    /* verilator lint_off UNUSEDPARAM */
    localparam int unsigned NPU_DMA_COMMAND_WIDTH =
        4 + 2 + NPU_DMA_COMMAND_ID_WIDTH + NPU_DMA_HBM_ADDRESS_WIDTH +
        NPU_DMA_SRAM_ADDRESS_WIDTH + NPU_DMA_X_COUNT_WIDTH +
        2*NPU_DMA_YZ_COUNT_WIDTH + 2*NPU_DMA_HBM_ADDRESS_WIDTH +
        2*NPU_DMA_SRAM_ADDRESS_WIDTH + 2;
    localparam int unsigned NPU_DMA_COMPLETION_WIDTH =
        NPU_DMA_COMMAND_ID_WIDTH + 1 + 3 + 1 + NPU_DMA_BEAT_COUNT_WIDTH;
    /* verilator lint_on UNUSEDPARAM */

endpackage
