`timescale 1ns/1ps
`default_nettype none

// Single-producer result bank.  The registered head keeps the external result
// stable under backpressure and leaves the payload array with one write port.
module vector_engine_result_fifo #(
    parameter int unsigned DEPTH = 16
) (
    input  logic                               clk_i,
    input  logic                               rst_i,
    input  logic                               clear_i,
    input  logic                               input_valid_i,
    output logic                               input_ready_o,
    input  vector_pkg::vector_engine_result_t  input_result_i,
    output logic                               output_valid_o,
    input  logic                               output_ready_i,
    output vector_pkg::vector_engine_result_t  output_result_o
);

    localparam int unsigned POINTER_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int unsigned LEVEL_WIDTH = $clog2(DEPTH + 1);

    vector_pkg::vector_engine_result_t result_mem [0:DEPTH-1];
    vector_pkg::vector_engine_result_t head_q;
    logic [POINTER_WIDTH-1:0] write_pointer_q;
    logic [POINTER_WIDTH-1:0] read_pointer_q;
    logic [LEVEL_WIDTH-1:0] memory_level_q;
    logic head_valid_q;
    logic push;
    logic pop;
    logic head_load;

    always_comb begin
        output_valid_o = head_valid_q;
        output_result_o = head_q;
        pop = output_valid_o && output_ready_i;
        input_ready_o = !rst_i && !clear_i &&
            ((memory_level_q + LEVEL_WIDTH'(head_valid_q)) <
             LEVEL_WIDTH'(DEPTH) || pop);
        push = input_valid_i && input_ready_o;
        head_load = (!head_valid_q || pop) && (memory_level_q != '0);
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            write_pointer_q <= '0;
            read_pointer_q <= '0;
            memory_level_q <= '0;
            head_q <= '0;
            head_valid_q <= 1'b0;
        end else begin
            if (push) begin
                result_mem[write_pointer_q] <= input_result_i;
                if (write_pointer_q == POINTER_WIDTH'(DEPTH - 1)) begin
                    write_pointer_q <= '0;
                end else begin
                    write_pointer_q <= write_pointer_q + 1'b1;
                end
            end

            if (head_load) begin
                head_q <= result_mem[read_pointer_q];
                if (read_pointer_q == POINTER_WIDTH'(DEPTH - 1)) begin
                    read_pointer_q <= '0;
                end else begin
                    read_pointer_q <= read_pointer_q + 1'b1;
                end
            end

            if (head_load) begin
                head_valid_q <= 1'b1;
            end else if (pop) begin
                head_valid_q <= 1'b0;
            end

            case ({push, head_load})
                2'b10: memory_level_q <= memory_level_q + 1'b1;
                2'b01: memory_level_q <= memory_level_q - 1'b1;
                default: memory_level_q <= memory_level_q;
            endcase
        end
    end

endmodule

`default_nettype wire
