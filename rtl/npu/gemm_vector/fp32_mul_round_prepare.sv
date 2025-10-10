`timescale 1ns/1ps
`default_nettype none

module fp32_mul_round_prepare (
    input  logic                    sign_i,
    input  logic             [23:0] normal_main_i,
    input  logic                    normal_guard_i,
    input  logic                    normal_sticky_i,
    input  logic             [23:0] subnormal_main_i,
    input  logic                    subnormal_guard_i,
    input  logic                    subnormal_sticky_i,
    input  fp8_pkg::fp8_rounding_e rounding_i,
    output logic             [24:0] normal_rounded_o,
    output logic                    normal_carry_o,
    output logic             [23:0] subnormal_rounded_o,
    output logic                    overflow_to_inf_o
);

    logic normal_increment_comb;
    logic subnormal_increment_comb;

    function automatic logic round_increment(
        input logic sign,
        input logic lsb,
        input logic guard_bit,
        input logic sticky_bit,
        input fp8_pkg::fp8_rounding_e rounding
    );
        logic discarded;
        begin
            discarded = guard_bit | sticky_bit;
            case (rounding)
                fp8_pkg::RNE: round_increment = guard_bit && (sticky_bit || lsb);
                fp8_pkg::RTZ: round_increment = 1'b0;
                fp8_pkg::RUP: round_increment = !sign && discarded;
                fp8_pkg::RDN: round_increment = sign && discarded;
                default: round_increment = guard_bit && (sticky_bit || lsb);
            endcase
        end
    endfunction

    always_comb begin
        normal_increment_comb = round_increment(sign_i, normal_main_i[0],
                                                normal_guard_i, normal_sticky_i,
                                                rounding_i);
        normal_rounded_o = {1'b0, normal_main_i} + normal_increment_comb;
        normal_carry_o = normal_rounded_o[24];
        subnormal_increment_comb = round_increment(sign_i, subnormal_main_i[0],
                                                   subnormal_guard_i, subnormal_sticky_i,
                                                   rounding_i);
        subnormal_rounded_o = subnormal_main_i + subnormal_increment_comb;
        case (rounding_i)
            fp8_pkg::RNE: overflow_to_inf_o = 1'b1;
            fp8_pkg::RTZ: overflow_to_inf_o = 1'b0;
            fp8_pkg::RUP: overflow_to_inf_o = !sign_i;
            fp8_pkg::RDN: overflow_to_inf_o = sign_i;
            default: overflow_to_inf_o = 1'b1;
        endcase
    end

endmodule

`default_nettype wire
