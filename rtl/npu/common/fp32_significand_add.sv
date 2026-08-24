`timescale 1ns/1ps
`default_nettype none

// 已准备操作数的28位有效数加法级。
// 符号/幅值选择位于前一流水级，本级只保留一条标准单元加法路径。
module fp32_significand_add (
    input  logic [27:0] arithmetic_a_i,
    input  logic [27:0] arithmetic_b_i,
    input  logic        carry_i,
    input  logic        sign_i,
    output logic [27:0] magnitude_o,
    output logic        sign_o
);

    logic [27:0] propagate [0:5];
    logic [27:0] generate_bits [0:5];
    logic [27:0] carry;

    assign propagate[0] = arithmetic_a_i ^ arithmetic_b_i;
    assign generate_bits[0] = arithmetic_a_i & arithmetic_b_i;

    generate
        for (genvar level = 0; level < 5; level++) begin : g_level
            localparam int unsigned DISTANCE = 1 << level;
            for (genvar bit_index = 0; bit_index < 28; bit_index++) begin : g_bit
                if (bit_index < DISTANCE) begin : g_passthrough
                    assign propagate[level + 1][bit_index] =
                        propagate[level][bit_index];
                    assign generate_bits[level + 1][bit_index] =
                        generate_bits[level][bit_index];
                end else begin : g_prefix
                    assign propagate[level + 1][bit_index] =
                        propagate[level][bit_index] &
                        propagate[level][bit_index-DISTANCE];
                    assign generate_bits[level + 1][bit_index] =
                        generate_bits[level][bit_index] |
                        (propagate[level][bit_index] &
                         generate_bits[level][bit_index-DISTANCE]);
                end
            end
        end
    endgenerate

    assign carry[0] = carry_i;
    generate
        for (genvar carry_index = 0; carry_index < 27; carry_index++) begin : g_carry
            assign carry[carry_index + 1] =
                generate_bits[5][carry_index] |
                (propagate[5][carry_index] & carry_i);
        end
    endgenerate

    assign magnitude_o = propagate[0] ^ carry;
    assign sign_o = sign_i;

endmodule

`default_nettype wire
