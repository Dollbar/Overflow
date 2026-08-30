`timescale 1ns/1ps
`default_nettype none

// Two-source read adapter for one Pod-shared SRAM client slot. It tracks the
// accepted request owner until the corresponding response is consumed, so DMA
// and one compute-local loader can safely share a physical arbitration client.
module npu_pod_sram_read_mux #(
    parameter int unsigned ADDRESS_WIDTH = 24,
    parameter int unsigned DATA_WIDTH = 1024
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic dma_request_valid_i,
    output logic dma_request_ready_o,
    input  logic [ADDRESS_WIDTH-1:0] dma_request_address_i,
    output logic dma_response_valid_o,
    input  logic dma_response_ready_i,
    output logic [DATA_WIDTH-1:0] dma_response_data_o,

    input  logic loader_request_valid_i,
    output logic loader_request_ready_o,
    input  logic [ADDRESS_WIDTH-1:0] loader_request_address_i,
    output logic loader_response_valid_o,
    input  logic loader_response_ready_i,
    output logic [DATA_WIDTH-1:0] loader_response_data_o,

    output logic downstream_request_valid_o,
    input  logic downstream_request_ready_i,
    output logic [ADDRESS_WIDTH-1:0] downstream_request_address_o,
    input  logic downstream_response_valid_i,
    output logic downstream_response_ready_o,
    input  logic [DATA_WIDTH-1:0] downstream_response_data_i,

    output logic busy_o,
    output logic protocol_error_o
);

    logic response_pending_q;
    logic response_owner_loader_q;
    logic prefer_loader_q;
    logic selected_loader;
    logic request_slot_available;
    logic request_fire;
    logic response_fire;

    always_comb begin
        selected_loader = 1'b0;
        if (dma_request_valid_i && loader_request_valid_i) begin
            selected_loader = prefer_loader_q;
        end else if (loader_request_valid_i) begin
            selected_loader = 1'b1;
        end

        downstream_response_ready_o = response_pending_q &&
            (response_owner_loader_q ? loader_response_ready_i :
                                       dma_response_ready_i);
        response_fire = downstream_response_valid_i &&
                        downstream_response_ready_o;
        request_slot_available = !response_pending_q || response_fire;
        downstream_request_valid_o = request_slot_available &&
            (dma_request_valid_i || loader_request_valid_i);
        downstream_request_address_o = selected_loader ?
            loader_request_address_i : dma_request_address_i;
        dma_request_ready_o = downstream_request_ready_i &&
            downstream_request_valid_o && !selected_loader;
        loader_request_ready_o = downstream_request_ready_i &&
            downstream_request_valid_o && selected_loader;

        dma_response_valid_o = downstream_response_valid_i &&
                               response_pending_q &&
                               !response_owner_loader_q;
        loader_response_valid_o = downstream_response_valid_i &&
                                  response_pending_q &&
                                  response_owner_loader_q;
        dma_response_data_o = downstream_response_data_i;
        loader_response_data_o = downstream_response_data_i;
    end

    assign request_fire = downstream_request_valid_o &&
                          downstream_request_ready_i;
    assign busy_o = response_pending_q;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            response_pending_q <= 1'b0;
            response_owner_loader_q <= 1'b0;
            prefer_loader_q <= 1'b0;
            protocol_error_o <= 1'b0;
        end else begin
            if (downstream_response_valid_i && !response_pending_q) begin
                protocol_error_o <= 1'b1;
            end
            case ({request_fire, response_fire})
                2'b10: response_pending_q <= 1'b1;
                2'b01: response_pending_q <= 1'b0;
                2'b11: response_pending_q <= 1'b1;
                default: response_pending_q <= response_pending_q;
            endcase
            if (request_fire) begin
                response_owner_loader_q <= selected_loader;
                prefer_loader_q <= !selected_loader;
            end
        end
    end

endmodule

`default_nettype wire
