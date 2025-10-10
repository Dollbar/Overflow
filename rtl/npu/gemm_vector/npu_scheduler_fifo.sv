`timescale 1ns/1ps
`default_nettype none

module npu_scheduler_fifo #(
    parameter int unsigned WIDTH = 1,
    parameter int unsigned DEPTH = 4
) (
    input  logic                         clk_i,
    input  logic                         rst_i,
    input  logic                         clear_i,
    input  logic                         input_valid_i,
    output logic                         input_ready_o,
    input  logic [WIDTH-1:0]             input_data_i,
    output logic                         output_valid_o,
    input  logic                         output_ready_i,
    output logic [WIDTH-1:0]             output_data_o,
    output logic [$clog2(DEPTH+1)-1:0]   level_o
);
    localparam int unsigned POINTER_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int unsigned LEVEL_WIDTH = $clog2(DEPTH + 1);

    logic [WIDTH-1:0] data_mem [0:DEPTH-1];
    logic [POINTER_WIDTH-1:0] write_pointer_q;
    logic [POINTER_WIDTH-1:0] read_pointer_q;
    logic [LEVEL_WIDTH-1:0] level_q;
    logic push;
    logic pop;

    always_comb begin
        output_valid_o = level_q != '0;
        output_data_o = output_valid_o ? data_mem[read_pointer_q] : '0;
        pop = output_valid_o && output_ready_i;
        input_ready_o = !rst_i && !clear_i &&
            ((level_q < LEVEL_WIDTH'(DEPTH)) || pop);
        push = input_valid_i && input_ready_o;
        level_o = level_q;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            write_pointer_q <= '0;
            read_pointer_q <= '0;
            level_q <= '0;
        end else begin
            if (push) begin
                data_mem[write_pointer_q] <= input_data_i;
                if (write_pointer_q == POINTER_WIDTH'(DEPTH - 1)) begin
                    write_pointer_q <= '0;
                end else begin
                    write_pointer_q <= write_pointer_q + 1'b1;
                end
            end
            if (pop) begin
                if (read_pointer_q == POINTER_WIDTH'(DEPTH - 1)) begin
                    read_pointer_q <= '0;
                end else begin
                    read_pointer_q <= read_pointer_q + 1'b1;
                end
            end
            unique case ({push, pop})
                2'b10: level_q <= level_q + 1'b1;
                2'b01: level_q <= level_q - 1'b1;
                default: level_q <= level_q;
            endcase
        end
    end

    initial begin
        assert (DEPTH > 0) else $error("npu_scheduler_fifo DEPTH must be positive");
        assert (WIDTH > 0) else $error("npu_scheduler_fifo WIDTH must be positive");
    end

endmodule

`default_nettype wire
