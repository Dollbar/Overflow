`timescale 1ns/1ps
`default_nettype none

// Fall-through row FIFO used by the ordered GEMM result collector. An empty
// FIFO may forward a newly selected Tile result in the same cycle, which keeps
// adjacent tasks bubble-free when the next Context is already producing data.
module npu_gemm_result_fifo #(
    parameter int unsigned WIDTH = 528,
    parameter int unsigned DEPTH = 4
) (
    input  logic                     clk_i,
    input  logic                     rst_i,
    input  logic                     clear_i,
    input  logic                     input_valid_i,
    output logic                     input_ready_o,
    input  logic [WIDTH-1:0]         input_data_i,
    output logic                     output_valid_o,
    input  logic                     output_ready_i,
    output logic [WIDTH-1:0]         output_data_o,
    output logic [$clog2(DEPTH+1)-1:0] level_o
);

    localparam int unsigned POINTER_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int unsigned LEVEL_WIDTH = $clog2(DEPTH + 1);

    logic [WIDTH-1:0] data_mem [0:DEPTH-1];
    logic [POINTER_WIDTH-1:0] write_pointer_q;
    logic [POINTER_WIDTH-1:0] read_pointer_q;
    logic [LEVEL_WIDTH-1:0] level_q;
    logic stored_valid;
    logic input_fire;
    logic stored_pop;
    logic bypass_fire;
    logic stored_push;

    always_comb begin
        stored_valid = level_q != '0;
        output_valid_o = stored_valid || input_valid_i;
        output_data_o = stored_valid ? data_mem[read_pointer_q] : input_data_i;
        stored_pop = stored_valid && output_ready_i;
        input_ready_o = !rst_i && !clear_i &&
            ((level_q < LEVEL_WIDTH'(DEPTH)) || stored_pop);
        input_fire = input_valid_i && input_ready_o;
        bypass_fire = !stored_valid && input_fire && output_ready_i;
        stored_push = input_fire && !bypass_fire;
        level_o = level_q;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            write_pointer_q <= '0;
            read_pointer_q <= '0;
            level_q <= '0;
        end else begin
            if (stored_push) begin
                data_mem[write_pointer_q] <= input_data_i;
                if (write_pointer_q == POINTER_WIDTH'(DEPTH - 1)) begin
                    write_pointer_q <= '0;
                end else begin
                    write_pointer_q <= write_pointer_q + 1'b1;
                end
            end
            if (stored_pop) begin
                if (read_pointer_q == POINTER_WIDTH'(DEPTH - 1)) begin
                    read_pointer_q <= '0;
                end else begin
                    read_pointer_q <= read_pointer_q + 1'b1;
                end
            end
            unique case ({stored_push, stored_pop})
                2'b10: level_q <= level_q + 1'b1;
                2'b01: level_q <= level_q - 1'b1;
                default: level_q <= level_q;
            endcase
        end
    end

    initial begin
        assert (DEPTH > 0)
            else $error("npu_gemm_result_fifo DEPTH must be positive");
        assert (WIDTH > 0)
            else $error("npu_gemm_result_fifo WIDTH must be positive");
    end

endmodule

`default_nettype wire
