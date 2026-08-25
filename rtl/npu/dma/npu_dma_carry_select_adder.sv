`timescale 1ns/1ps
`default_nettype none

module npu_dma_carry_select_adder #(
    parameter int unsigned WIDTH = 29,
    parameter int unsigned BLOCK_WIDTH = 5,
    parameter int unsigned BLOCKS = (WIDTH + BLOCK_WIDTH - 1) / BLOCK_WIDTH
) (
    input  logic [WIDTH-1:0] a_i,
    input  logic [WIDTH-1:0] b_i,
    input  logic cin_i,
    output logic [WIDTH-1:0] sum_o
);

    logic [BLOCKS-1:0] block_select;

    assign block_select[0] = cin_i;

    generate
        for (genvar block = 0; block < BLOCKS; block++) begin : g_block
            localparam int unsigned THIS_WIDTH =
                (block == (BLOCKS - 1)) ? WIDTH - block*BLOCK_WIDTH :
                BLOCK_WIDTH;
            logic [THIS_WIDTH-1:0] sum_without_carry;
            logic [THIS_WIDTH-1:0] sum_with_carry;
            logic carry_without_carry;
            logic carry_with_carry;

            npu_dma_carry_select_block #(
                .WIDTH(THIS_WIDTH)
            ) u_block (
                .a_i(a_i[block*BLOCK_WIDTH +: THIS_WIDTH]),
                .b_i(b_i[block*BLOCK_WIDTH +: THIS_WIDTH]),
                .sum_without_carry_o(sum_without_carry),
                .sum_with_carry_o(sum_with_carry),
                .carry_without_carry_o(carry_without_carry),
                .carry_with_carry_o(carry_with_carry)
            );

            assign sum_o[block*BLOCK_WIDTH +: THIS_WIDTH] =
                block_select[block] ? sum_with_carry : sum_without_carry;

            if (block == (BLOCKS - 1)) begin : g_last
                /* verilator lint_off UNUSEDSIGNAL */
                wire unused_carry = carry_without_carry ^ carry_with_carry;
                /* verilator lint_on UNUSEDSIGNAL */
            end else begin : g_carry
                assign block_select[block + 1] = block_select[block] ?
                    carry_with_carry : carry_without_carry;
            end
        end
    endgenerate

    initial begin
        if ((WIDTH <= BLOCK_WIDTH) || (BLOCK_WIDTH == 0)) begin
            $error("npu_dma_carry_select_adder parameters are invalid");
        end
    end

endmodule

`default_nettype wire
