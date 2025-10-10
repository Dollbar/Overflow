`timescale 1ns/1ps

module fp8_reduce4_round_pack #(
    parameter bit FTZ = 1'b0
) (
    input  logic                    sign_i,
    input  logic             [22:0] round_main_i,
    input  logic              [5:0] round_group_all_ones_i,
    input  logic                    round_increment_i,
    input  logic signed       [7:0] exponent_i,
    input  logic                    exponent_in_range_i,
    input  logic                    zero_i,
    input  logic                    special_valid_i,
    input  logic             [31:0] special_result_i,
    output logic             [31:0] result_o
);

    (* keep = "true" *) logic [5:0] round_group_prefix1_comb;
    (* keep = "true" *) logic [5:0] round_group_prefix2_comb;
    (* keep = "true" *) logic [5:0] round_group_prefix4_comb;
    logic [5:0] round_group_carry_comb;
    logic [22:0] round_bit_carry_comb;
    logic round_overflow_comb;
    logic [22:0] rounded_fraction_comb;
    logic [7:0] biased_exponent_base_comb;
    logic [7:0] biased_exponent_rounded_comb;
    logic [7:0] biased_exponent_comb;
    logic [31:0] finite_result_comb;

    always_comb begin
        round_group_prefix1_comb = round_group_all_ones_i &
                                   {round_group_all_ones_i[4:0], 1'b1};
        round_group_prefix2_comb = round_group_prefix1_comb &
                                   {round_group_prefix1_comb[3:0], 2'b11};
        round_group_prefix4_comb = round_group_prefix2_comb &
                                   {round_group_prefix2_comb[1:0], 4'hf};
        round_group_carry_comb = {round_group_prefix4_comb[4:0], 1'b1} &
                                 {6{round_increment_i}};

        round_bit_carry_comb[0] = round_group_carry_comb[0];
        round_bit_carry_comb[1] = round_group_carry_comb[0] & round_main_i[0];
        round_bit_carry_comb[2] = round_group_carry_comb[0] & (&round_main_i[1:0]);
        round_bit_carry_comb[3] = round_group_carry_comb[0] & (&round_main_i[2:0]);
        round_bit_carry_comb[4] = round_group_carry_comb[1];
        round_bit_carry_comb[5] = round_group_carry_comb[1] & round_main_i[4];
        round_bit_carry_comb[6] = round_group_carry_comb[1] & (&round_main_i[5:4]);
        round_bit_carry_comb[7] = round_group_carry_comb[1] & (&round_main_i[6:4]);
        round_bit_carry_comb[8] = round_group_carry_comb[2];
        round_bit_carry_comb[9] = round_group_carry_comb[2] & round_main_i[8];
        round_bit_carry_comb[10] = round_group_carry_comb[2] & (&round_main_i[9:8]);
        round_bit_carry_comb[11] = round_group_carry_comb[2] & (&round_main_i[10:8]);
        round_bit_carry_comb[12] = round_group_carry_comb[3];
        round_bit_carry_comb[13] = round_group_carry_comb[3] & round_main_i[12];
        round_bit_carry_comb[14] = round_group_carry_comb[3] & (&round_main_i[13:12]);
        round_bit_carry_comb[15] = round_group_carry_comb[3] & (&round_main_i[14:12]);
        round_bit_carry_comb[16] = round_group_carry_comb[4];
        round_bit_carry_comb[17] = round_group_carry_comb[4] & round_main_i[16];
        round_bit_carry_comb[18] = round_group_carry_comb[4] & (&round_main_i[17:16]);
        round_bit_carry_comb[19] = round_group_carry_comb[4] & (&round_main_i[18:16]);
        round_bit_carry_comb[20] = round_group_carry_comb[5];
        round_bit_carry_comb[21] = round_group_carry_comb[5] & round_main_i[20];
        round_bit_carry_comb[22] = round_group_carry_comb[5] & (&round_main_i[21:20]);

        round_overflow_comb = round_increment_i && round_group_prefix4_comb[5];
        rounded_fraction_comb = round_main_i ^ round_bit_carry_comb;
    end

    always_comb begin
        biased_exponent_base_comb = exponent_i[7:0] + 8'd127;
        biased_exponent_rounded_comb = {!exponent_i[7], exponent_i[6:0]};
        biased_exponent_comb = round_overflow_comb ? biased_exponent_rounded_comb :
                                                    biased_exponent_base_comb;
        finite_result_comb = {sign_i, biased_exponent_comb, rounded_fraction_comb};
        if (zero_i) begin
            finite_result_comb = {sign_i, 31'd0};
        end else if (!exponent_in_range_i) begin
            finite_result_comb = 32'h7fc00000;
        end
    end

    always_comb begin
        result_o = finite_result_comb;
        if (special_valid_i) begin
            if (FTZ && (special_result_i[30:23] == 8'h00) &&
                (special_result_i[22:0] != 23'h000000)) begin
                result_o = {special_result_i[31], 31'd0};
            end else begin
                result_o = special_result_i;
            end
        end
    end

endmodule
