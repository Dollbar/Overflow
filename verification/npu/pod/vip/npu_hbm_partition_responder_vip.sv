`timescale 1ns/1ps
`default_nettype none

module npu_hbm_partition_responder_vip #(
    parameter int unsigned PODS = 8,
    parameter int unsigned LANES_PER_POD = 5,
    parameter int unsigned PARTITION_BITS = 3,
    parameter int unsigned ADDRESS_WIDTH = 35,
    parameter int unsigned TAG_WIDTH = 12,
    parameter int unsigned DATA_BYTES = 128,
    parameter int unsigned TOTAL_LANES = PODS * LANES_PER_POD,
    parameter int unsigned DATA_WIDTH = DATA_BYTES * 8
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic enable_i,
    input  logic [31:0] seed_i,

    input  logic [TOTAL_LANES-1:0] request_valid_i,
    output logic [TOTAL_LANES-1:0] request_ready_o,
    input  logic [TOTAL_LANES-1:0] request_write_i,
    input  logic [TOTAL_LANES*PARTITION_BITS-1:0] request_partition_i,
    input  logic [TOTAL_LANES*ADDRESS_WIDTH-1:0] request_address_i,
    input  logic [TOTAL_LANES*TAG_WIDTH-1:0] request_tag_i,
    input  logic [TOTAL_LANES*DATA_WIDTH-1:0] request_write_data_i,
    input  logic [TOTAL_LANES*DATA_BYTES-1:0] request_byte_enable_i,

    output logic [TOTAL_LANES-1:0] response_valid_o,
    input  logic [TOTAL_LANES-1:0] response_ready_i,
    output logic [TOTAL_LANES-1:0] response_write_o,
    output logic [TOTAL_LANES*PARTITION_BITS-1:0] response_partition_o,
    output logic [TOTAL_LANES*TAG_WIDTH-1:0] response_tag_o,
    output logic [TOTAL_LANES*DATA_WIDTH-1:0] response_read_data_o,
    output logic [TOTAL_LANES*2-1:0] response_status_o,

    output logic [63:0] accepted_requests_o,
    output logic [63:0] delivered_responses_o,
    output logic [PODS-1:0] partition_seen_o,
    output logic backpressure_seen_o,
    output logic protocol_error_o
);

    logic [31:0] lfsr_q;

    always_comb begin
        request_ready_o = '0;
        for (integer lane = 0; lane < TOTAL_LANES; lane++) begin
            request_ready_o[lane] = enable_i && !response_valid_o[lane] &&
                (lfsr_q[lane % 32] || lfsr_q[(lane + 11) % 32]);
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            lfsr_q <= (seed_i == 32'd0) ? 32'h1 : seed_i;
            response_valid_o <= '0;
            response_write_o <= '0;
            response_partition_o <= '0;
            response_tag_o <= '0;
            /* verilator lint_off WIDTHCONCAT */
            response_read_data_o <= '0;
            /* verilator lint_on WIDTHCONCAT */
            response_status_o <= '0;
            accepted_requests_o <= '0;
            delivered_responses_o <= '0;
            partition_seen_o <= '0;
            backpressure_seen_o <= 1'b0;
            protocol_error_o <= 1'b0;
        end else begin
            lfsr_q <= {lfsr_q[30:0],
                lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
            accepted_requests_o <= accepted_requests_o +
                64'($countones(request_valid_i & request_ready_o));
            delivered_responses_o <= delivered_responses_o +
                64'($countones(response_valid_o & response_ready_i));
            for (integer lane = 0; lane < TOTAL_LANES; lane++) begin
                if (request_valid_i[lane] && !request_ready_o[lane]) begin
                    backpressure_seen_o <= 1'b1;
                end
                if (response_valid_o[lane] && response_ready_i[lane]) begin
                    response_valid_o[lane] <= 1'b0;
                end
                if (request_valid_i[lane] && request_ready_o[lane]) begin
                    response_valid_o[lane] <= 1'b1;
                    response_write_o[lane] <= request_write_i[lane];
                    response_partition_o[
                        lane*PARTITION_BITS +: PARTITION_BITS] <=
                        request_partition_i[
                            lane*PARTITION_BITS +: PARTITION_BITS];
                    response_tag_o[lane*TAG_WIDTH +: TAG_WIDTH] <=
                        request_tag_i[lane*TAG_WIDTH +: TAG_WIDTH];
                    response_status_o[lane*2 +: 2] <= 2'd0;
                    for (integer word = 0; word < DATA_WIDTH/32; word++) begin
                        response_read_data_o[
                            lane*DATA_WIDTH + word*32 +: 32] <=
                            request_address_i[
                                lane*ADDRESS_WIDTH +: 32] ^
                            32'(word) ^ 32'(lane);
                    end
                    partition_seen_o[lane / LANES_PER_POD] <= 1'b1;
                    if (request_partition_i[
                            lane*PARTITION_BITS +: PARTITION_BITS] !=
                        PARTITION_BITS'(lane / LANES_PER_POD)) begin
                        protocol_error_o <= 1'b1;
                    end
                    if (request_write_i[lane] &&
                        (request_byte_enable_i[
                            lane*DATA_BYTES +: DATA_BYTES] == '0)) begin
                        protocol_error_o <= 1'b1;
                    end
                end
            end
        end
    end

    wire _unused_write_payload = &{1'b0, request_write_data_i};

endmodule

`default_nettype wire
