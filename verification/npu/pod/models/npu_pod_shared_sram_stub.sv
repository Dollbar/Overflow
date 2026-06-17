`timescale 1ns/1ps
`default_nettype none

// Verification-only compact shared-SRAM model for complete-Pod control/data
// integration. Production macro mapping is checked independently against the
// real npu_pod_shared_sram hierarchy.
/* verilator lint_off DECLFILENAME */
module npu_pod_shared_sram #(
    parameter int unsigned CLIENTS = 16,
    parameter int unsigned BANKS = 8,
    parameter int unsigned DATA_BYTES = 128,
    parameter int unsigned DATA_WIDTH = DATA_BYTES * 8,
    parameter int unsigned ADDRESS_WIDTH = 24,
    parameter int unsigned BANK_INDEX_WIDTH = $clog2(BANKS),
    parameter int unsigned CLIENT_INDEX_WIDTH = $clog2(CLIENTS),
    parameter int unsigned BANK_DEPTH = 16384,
    parameter int unsigned BANK_ADDRESS_WIDTH = $clog2(BANK_DEPTH),
    parameter int unsigned MODEL_DEPTH = 1024,
    parameter int unsigned MODEL_ADDRESS_WIDTH = $clog2(MODEL_DEPTH)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic [CLIENTS-1:0] read_request_valid_i,
    output logic [CLIENTS-1:0] read_request_ready_o,
    input  logic [CLIENTS*ADDRESS_WIDTH-1:0] read_request_address_i,
    output logic [CLIENTS-1:0] read_response_valid_o,
    input  logic [CLIENTS-1:0] read_response_ready_i,
    output logic [CLIENTS*DATA_WIDTH-1:0] read_response_data_o,
    input  logic [CLIENTS-1:0] write_valid_i,
    output logic [CLIENTS-1:0] write_ready_o,
    input  logic [CLIENTS*ADDRESS_WIDTH-1:0] write_address_i,
    input  logic [CLIENTS*DATA_WIDTH-1:0] write_data_i,
    input  logic [CLIENTS*DATA_BYTES-1:0] write_byte_enable_i,
    output logic busy_o,
    output logic protocol_error_o,
    output logic [63:0] accepted_reads_o,
    output logic [63:0] accepted_writes_o,
    output logic [63:0] read_conflict_cycles_o,
    output logic [63:0] write_conflict_cycles_o
);

    logic [DATA_WIDTH-1:0] memory [0:MODEL_DEPTH-1];
    logic [CLIENTS-1:0] response_valid_q;
    logic [CLIENTS*DATA_WIDTH-1:0] response_data_q;
    logic _unused_parameters;

    assign read_response_valid_o = response_valid_q;
    assign read_response_data_o = response_data_q;
    assign read_request_ready_o = ~response_valid_q |
                                  read_response_ready_i;
    assign write_ready_o = {CLIENTS{!rst_i && !clear_i}};
    assign busy_o = |response_valid_q;
    assign _unused_parameters = &{1'b0, BANK_INDEX_WIDTH,
        CLIENT_INDEX_WIDTH, BANK_ADDRESS_WIDTH};

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            response_valid_q <= '0;
            /* verilator lint_off WIDTHCONCAT */
            response_data_q <= '0;
            /* verilator lint_on WIDTHCONCAT */
            protocol_error_o <= 1'b0;
            accepted_reads_o <= '0;
            accepted_writes_o <= '0;
            read_conflict_cycles_o <= '0;
            write_conflict_cycles_o <= '0;
        end else begin
            for (integer client = 0; client < CLIENTS; client++) begin
                if (response_valid_q[client] &&
                    read_response_ready_i[client]) begin
                    response_valid_q[client] <= 1'b0;
                end
                if (read_request_valid_i[client] &&
                    read_request_ready_o[client]) begin
                    response_valid_q[client] <= 1'b1;
                    response_data_q[client*DATA_WIDTH +: DATA_WIDTH] <=
                        memory[read_request_address_i[
                            client*ADDRESS_WIDTH + 7 +:
                            MODEL_ADDRESS_WIDTH]];
                    accepted_reads_o <= accepted_reads_o + 1'b1;
                    if (read_request_address_i[
                        client*ADDRESS_WIDTH +: 7] != 7'd0) begin
                        protocol_error_o <= 1'b1;
                    end
                end
                if (write_valid_i[client] && write_ready_o[client]) begin
                    if ((write_address_i[
                            client*ADDRESS_WIDTH +: 7] != 7'd0) ||
                        (write_byte_enable_i[
                            client*DATA_BYTES +: DATA_BYTES] !=
                         {DATA_BYTES{1'b1}})) begin
                        protocol_error_o <= 1'b1;
                    end else begin
                        memory[write_address_i[
                            client*ADDRESS_WIDTH + 7 +:
                            MODEL_ADDRESS_WIDTH]] <= write_data_i[
                                client*DATA_WIDTH +: DATA_WIDTH];
                    end
                    accepted_writes_o <= accepted_writes_o + 1'b1;
                end
            end
        end
    end

endmodule
/* verilator lint_on DECLFILENAME */

`default_nettype wire
