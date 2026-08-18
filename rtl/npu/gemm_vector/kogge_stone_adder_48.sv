`timescale 1ns/1ps
`default_nettype none

module kogge_stone_adder_48 #(
    parameter int unsigned WIDTH = 48
) (
    input  logic [WIDTH-1:0] a_i,
    input  logic [WIDTH-1:0] b_i,
    input  logic        cin_i,
    output logic [WIDTH-1:0] sum_o
);

    localparam int unsigned LEVELS = $clog2(WIDTH);

    logic [WIDTH-1:0] propagate [0:LEVELS];
    logic [WIDTH-1:0] generate_bits [0:LEVELS];
    logic [WIDTH-1:0] carry;

    assign propagate[0] = a_i ^ b_i;
    assign generate_bits[0] = a_i & b_i;

    generate
        for (genvar level = 0; level < LEVELS; level++) begin : g_level
            localparam int unsigned DISTANCE = 1 << level;
            for (genvar bit_index = 0; bit_index < WIDTH; bit_index++) begin : g_bit
                if (bit_index < DISTANCE) begin : g_passthrough
                    assign propagate[level + 1][bit_index] = propagate[level][bit_index];
                    assign generate_bits[level + 1][bit_index] = generate_bits[level][bit_index];
                end else begin : g_prefix
                    assign propagate[level + 1][bit_index] =
                        propagate[level][bit_index] & propagate[level][bit_index-DISTANCE];
                    assign generate_bits[level + 1][bit_index] =
                        generate_bits[level][bit_index] |
                        (propagate[level][bit_index] & generate_bits[level][bit_index-DISTANCE]);
                end
            end
        end
    endgenerate

    assign carry[0] = cin_i;
    generate
        for (genvar carry_index = 0; carry_index < WIDTH-1; carry_index++) begin : g_carry
            assign carry[carry_index + 1] = generate_bits[LEVELS][carry_index] |
                (propagate[LEVELS][carry_index] & cin_i);
        end
    endgenerate
    assign sum_o = propagate[0] ^ carry;

endmodule

`default_nettype wire
