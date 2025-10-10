`timescale 1ns/1ps
`default_nettype none

// 结果行缓冲的局部33位切片。保留层次，使捕获使能在每个lane内局部扇出。
(* keep_hierarchy = "yes" *)
module gemm_result_row_slice #(
    parameter integer SLICE_ID = 0
) (
    input  logic        clk_i,
    input  logic        valid_i,
    input  logic        ready_i,
    input  logic [32:0] payload_i,
    output logic [32:0] payload_o
);

    generate
        if (SLICE_ID >= 0) begin : gen_valid_slice
            always_ff @(posedge clk_i) begin
                if (valid_i && ready_i) begin
                    payload_o <= payload_i;
                end
            end
        end
    endgenerate

endmodule

`default_nettype wire
