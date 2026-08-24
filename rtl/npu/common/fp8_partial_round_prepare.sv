`timescale 1ns/1ps

module fp8_partial_round_prepare (
    input  logic                    sign_i,
    input  logic             [26:0] significand_i,
    input  logic signed      [10:0] exponent_i,
    input  fp8_pkg::fp8_rounding_e rounding_i,
    output logic             [22:0] round_main_o,
    output logic              [5:0] round_group_all_ones_o,
    output logic                    round_increment_o,
    output logic                    exponent_in_range_o
);

    logic round_discarded_comb;
    logic [22:0] round_main_comb;

    always_comb begin
        round_main_comb = significand_i[25:3];
        round_main_o = round_main_comb;
        round_group_all_ones_o[0] = &round_main_comb[3:0];
        round_group_all_ones_o[1] = &round_main_comb[7:4];
        round_group_all_ones_o[2] = &round_main_comb[11:8];
        round_group_all_ones_o[3] = &round_main_comb[15:12];
        round_group_all_ones_o[4] = &round_main_comb[19:16];
        round_group_all_ones_o[5] = significand_i[26] && (&round_main_comb[22:20]);
        round_discarded_comb = |significand_i[2:0];
        round_increment_o = 1'b0;
        case (rounding_i)
            fp8_pkg::RNE: round_increment_o = significand_i[2] &&
                                              (significand_i[1] || significand_i[0] ||
                                               round_main_comb[0]);
            fp8_pkg::RTZ: round_increment_o = 1'b0;
            fp8_pkg::RUP: round_increment_o = !sign_i && round_discarded_comb;
            fp8_pkg::RDN: round_increment_o = sign_i && round_discarded_comb;
            default: round_increment_o = significand_i[2] &&
                                                (significand_i[1] || significand_i[0] ||
                                                 round_main_comb[0]);
        endcase
        exponent_in_range_o = (exponent_i >= -11'sd32) &&
                              (exponent_i <= 11'sd35);
    end

endmodule
